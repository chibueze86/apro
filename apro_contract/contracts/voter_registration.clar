;; Enhanced Voting with Voter Registration Smart Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-registered (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-invalid-candidate (err u103))
(define-constant err-voting-closed (err u104))
(define-constant err-voting-not-started (err u105))
(define-constant err-voting-already-open (err u106))
(define-constant err-invalid-time (err u107))
(define-constant err-proposal-not-found (err u108))
(define-constant err-delegate-not-found (err u109))
(define-constant err-cannot-delegate-to-self (err u110))
(define-constant err-already-delegated (err u111))
(define-constant err-voting-period-active (err u112))

;; Data Variables
(define-data-var voting-open bool false)
(define-data-var voting-start-time uint u0)
(define-data-var voting-end-time uint u0)
(define-data-var total-registered-voters uint u0)
(define-data-var total-votes-cast uint u0)
(define-data-var min-quorum-percentage uint u50) ;; 50% minimum quorum
(define-data-var allow-vote-delegation bool true)
(define-data-var voting-fee uint u0) ;; Fee in microSTX to vote (anti-spam)

;; Data Maps
;; Voter registration and info
(define-map registered-voters principal {
  is-registered: bool,
  registration-time: uint,
  voter-weight: uint ;; For weighted voting
})

;; Voting records
(define-map voting-records principal {
  has-voted: bool,
  vote-time: uint,
  candidate-voted: uint
})

;; Vote delegation
(define-map vote-delegation principal principal) ;; delegator => delegate
(define-map delegation-power principal uint) ;; delegate => total delegated power

;; Candidate information
(define-map candidates uint {
  name: (string-ascii 50),
  description: (string-ascii 200),
  vote-count: uint,
  is-active: bool
})

;; Proposals (for multiple concurrent votes)
(define-map proposals uint {
  title: (string-ascii 100),
  description: (string-ascii 500),
  start-time: uint,
  end-time: uint,
  is-active: bool,
  votes-for: uint,
  votes-against: uint,
  total-votes: uint
})

;; Proposal voting records
(define-map proposal-votes { voter: principal, proposal-id: uint } {
  vote: bool, ;; true = for, false = against
  vote-time: uint
})

;; Emergency controls
(define-map emergency-admins principal bool)

;; Audit trail
(define-map audit-log uint {
  action: (string-ascii 50),
  actor: principal,
  timestamp: uint,
  details: (string-ascii 200)
})

;; Counters
(define-data-var candidate-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var audit-counter uint u0)

;; Read-only functions

;; Get comprehensive voter info
(define-read-only (get-voter-info (voter principal))
  (map-get? registered-voters voter)
)

;; Check if an address is a registered voter
(define-read-only (is-registered-voter (voter principal))
  (match (map-get? registered-voters voter)
    voter-info (get is-registered voter-info)
    false
  )
)

;; Get voting record for a voter
(define-read-only (get-voting-record (voter principal))
  (map-get? voting-records voter)
)

;; Get candidate information
(define-read-only (get-candidate-info (candidate-id uint))
  (map-get? candidates candidate-id)
)

;; Get proposal information
(define-read-only (get-proposal-info (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; Check voting statistics
(define-read-only (get-voting-stats)
  {
    total-registered: (var-get total-registered-voters),
    total-votes-cast: (var-get total-votes-cast),
    turnout-percentage: (if (> (var-get total-registered-voters) u0)
      (/ (* (var-get total-votes-cast) u100) (var-get total-registered-voters))
      u0
    ),
    quorum-met: (>= 
      (/ (* (var-get total-votes-cast) u100) (var-get total-registered-voters))
      (var-get min-quorum-percentage)
    )
  }
)

;; Check if voting period is active
(define-read-only (is-voting-period-active)
  (and 
    (var-get voting-open)
    (>= block-height (var-get voting-start-time))
    (<= block-height (var-get voting-end-time))
  )
)

;; Get delegation info
(define-read-only (get-delegation-info (voter principal))
  {
    delegated-to: (map-get? vote-delegation voter),
    delegation-power: (default-to u1 (map-get? delegation-power voter))
  }
)

;; Get audit log entry
(define-read-only (get-audit-entry (log-id uint))
  (map-get? audit-log log-id)
)

;; Calculate effective voting power (including delegations)
(define-read-only (get-effective-voting-power (voter principal))
  (let
    (
      (base-weight (match (map-get? registered-voters voter)
        voter-info (get voter-weight voter-info)
        u0
      ))
      (delegated-power (default-to u0 (map-get? delegation-power voter)))
    )
    (+ base-weight delegated-power)
  )
)

;; Private functions

;; Log actions for audit trail
(define-private (log-action (action (string-ascii 50)) (details (string-ascii 200)))
  (let
    (
      (log-id (+ (var-get audit-counter) u1))
    )
    (map-set audit-log log-id {
      action: action,
      actor: tx-sender,
      timestamp: block-height,
      details: details
    })
    (var-set audit-counter log-id)
    log-id
  )
)

;; Public functions

;; Enhanced voter registration with additional info
(define-public (register-voter (voter principal) (weight uint))
  (begin
    ;; Only contract owner can register voters
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    ;; Register the voter with additional info
    (map-set registered-voters voter {
      is-registered: true,
      registration-time: block-height,
      voter-weight: (if (> weight u0) weight u1)
    })
    
    ;; Update total registered voters count
    (var-set total-registered-voters (+ (var-get total-registered-voters) u1))
    
    ;; Log the action
    (log-action "VOTER_REGISTERED" "Voter registered with weight")
    (ok true)
  )
)

;; Batch register voters with weights
(define-public (batch-register-voters (voters-data (list 50 { voter: principal, weight: uint })))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map register-voter-from-data voters-data))
  )
)

(define-private (register-voter-from-data (voter-data { voter: principal, weight: uint }))
  (begin
    (map-set registered-voters (get voter voter-data) {
      is-registered: true,
      registration-time: block-height,
      voter-weight: (if (> (get weight voter-data) u0) (get weight voter-data) u1)
    })
    (var-set total-registered-voters (+ (var-get total-registered-voters) u1))
    true
  )
)

;; Add candidate with detailed information
(define-public (add-candidate (name (string-ascii 50)) (description (string-ascii 200)))
  (let
    (
      (new-candidate-id (+ (var-get candidate-counter) u1))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set candidates new-candidate-id {
      name: name,
      description: description,
      vote-count: u0,
      is-active: true
    })
    
    (var-set candidate-counter new-candidate-id)
    (log-action "CANDIDATE_ADDED" name)
    (ok new-candidate-id)
  )
)

;; Deactivate a candidate
(define-public (deactivate-candidate (candidate-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (match (map-get? candidates candidate-id)
      candidate-info (begin
        (map-set candidates candidate-id (merge candidate-info { is-active: false }))
        (log-action "CANDIDATE_DEACTIVATED" (get name candidate-info))
        (ok true)
      )
      err-invalid-candidate
    )
  )
)

;; Schedule voting with specific time period
(define-public (schedule-voting (start-time uint) (end-time uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> end-time start-time) err-invalid-time)
    (asserts! (>= start-time block-height) err-invalid-time)
    
    (var-set voting-start-time start-time)
    (var-set voting-end-time end-time)
    (var-set voting-open true)
    
    (log-action "VOTING_SCHEDULED" "Voting period scheduled")
    (ok true)
  )
)

;; Enhanced voting function with delegation support
(define-public (vote (candidate-id uint))
  (let
    (
      (voter-info (unwrap! (map-get? registered-voters tx-sender) err-not-registered))
      (current-candidate (unwrap! (map-get? candidates candidate-id) err-invalid-candidate))
      (voting-power (get-effective-voting-power tx-sender))
      (current-votes (get vote-count current-candidate))
    )
    ;; Check if voting is active
    (asserts! (is-voting-period-active) err-voting-closed)
    
    ;; Check if voter is registered
    (asserts! (get is-registered voter-info) err-not-registered)
    
    ;; Check if candidate is active
    (asserts! (get is-active current-candidate) err-invalid-candidate)
    
    ;; Check if voter hasn't already voted
    (asserts! (is-none (map-get? voting-records tx-sender)) err-already-voted)
    
    ;; Pay voting fee if required
    (if (> (var-get voting-fee) u0)
      (unwrap! (stx-transfer? (var-get voting-fee) tx-sender contract-owner) (err u999))
      true
    )
    
    ;; Record the vote
    (map-set voting-records tx-sender {
      has-voted: true,
      vote-time: block-height,
      candidate-voted: candidate-id
    })
    
    ;; Update candidate vote count with voting power
    (map-set candidates candidate-id 
      (merge current-candidate { vote-count: (+ current-votes voting-power) }))
    
    ;; Update total votes cast
    (var-set total-votes-cast (+ (var-get total-votes-cast) u1))
    
    ;; Log the vote
    (log-action "VOTE_CAST" (get name current-candidate))
    (ok true)
  )
)

;; Delegate voting power
(define-public (delegate-vote (delegate principal))
  (begin
    ;; Check if delegation is allowed
    (asserts! (var-get allow-vote-delegation) (err u113))
    
    ;; Cannot delegate to self
    (asserts! (not (is-eq tx-sender delegate)) err-cannot-delegate-to-self)
    
    ;; Check if delegate is registered
    (asserts! (is-registered-voter delegate) err-delegate-not-found)
    
    ;; Check if not already delegated
    (asserts! (is-none (map-get? vote-delegation tx-sender)) err-already-delegated)
    
    ;; Get voter's weight
    (let
      (
        (voter-weight (match (map-get? registered-voters tx-sender)
          voter-info (get voter-weight voter-info)
          u1
        ))
        (current-delegation-power (default-to u0 (map-get? delegation-power delegate)))
      )
      
      ;; Set delegation
      (map-set vote-delegation tx-sender delegate)
      (map-set delegation-power delegate (+ current-delegation-power voter-weight))
      
      (log-action "VOTE_DELEGATED" "Vote delegated")
      (ok true)
    )
  )
)

;; Revoke vote delegation
(define-public (revoke-delegation)
  (match (map-get? vote-delegation tx-sender)
    delegate (let
      (
        (voter-weight (match (map-get? registered-voters tx-sender)
          voter-info (get voter-weight voter-info)
          u1
        ))
        (current-delegation-power (default-to u0 (map-get? delegation-power delegate)))
      )
      ;; Remove delegation
      (map-delete vote-delegation tx-sender)
      (map-set delegation-power delegate 
        (if (>= current-delegation-power voter-weight)
          (- current-delegation-power voter-weight)
          u0
        ))
      
      (log-action "DELEGATION_REVOKED" "Vote delegation revoked")
      (ok true)
    )
    (err err-delegate-not-found)
  )
)

;; Create a proposal for voting
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (duration-blocks uint))
  (let
    (
      (proposal-id (+ (var-get proposal-counter) u1))
      (end-time (+ block-height duration-blocks))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set proposals proposal-id {
      title: title,
      description: description,
      start-time: block-height,
      end-time: end-time,
      is-active: true,
      votes-for: u0,
      votes-against: u0,
      total-votes: u0
    })
    
    (var-set proposal-counter proposal-id)
    (log-action "PROPOSAL_CREATED" title)
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal-info (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
      (voting-power (get-effective-voting-power tx-sender))
      (vote-key { voter: tx-sender, proposal-id: proposal-id })
    )
    ;; Check if voter is registered
    (asserts! (is-registered-voter tx-sender) err-not-registered)
    
    ;; Check if proposal is active and within time bounds
    (asserts! (get is-active proposal-info) err-proposal-not-found)
    (asserts! (<= block-height (get end-time proposal-info)) err-voting-closed)
    (asserts! (>= block-height (get start-time proposal-info)) err-voting-not-started)
    
    ;; Check if haven't voted on this proposal yet
    (asserts! (is-none (map-get? proposal-votes vote-key)) err-already-voted)
    
    ;; Record the vote
    (map-set proposal-votes vote-key {
      vote: vote-for,
      vote-time: block-height
    })
    
    ;; Update proposal vote counts
    (map-set proposals proposal-id
      (merge proposal-info {
        votes-for: (if vote-for 
          (+ (get votes-for proposal-info) voting-power)
          (get votes-for proposal-info)
        ),
        votes-against: (if vote-for
          (get votes-against proposal-info)
          (+ (get votes-against proposal-info) voting-power)
        ),
        total-votes: (+ (get total-votes proposal-info) voting-power)
      })
    )
    
    (log-action "PROPOSAL_VOTE" (get title proposal-info))
    (ok true)
  )
)

;; Emergency functions
(define-public (add-emergency-admin (admin principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set emergency-admins admin true)
    (log-action "EMERGENCY_ADMIN_ADDED" "Emergency admin added")
    (ok true)
  )
)

(define-public (emergency-pause-voting)
  (begin
    (asserts! (or 
      (is-eq tx-sender contract-owner)
      (default-to false (map-get? emergency-admins tx-sender))
    ) err-owner-only)
    
    (var-set voting-open false)
    (log-action "EMERGENCY_PAUSE" "Voting paused due to emergency")
    (ok true)
  )
)

;; Configuration functions
(define-public (set-min-quorum (percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= percentage u100) err-invalid-time)
    (var-set min-quorum-percentage percentage)
    (ok true)
  )
)

(define-public (set-voting-fee (fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set voting-fee fee)
    (log-action "VOTING_FEE_SET" "Voting fee updated")
    (ok true)
  )
)

(define-public (toggle-delegation (allow bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set allow-vote-delegation allow)
    (ok true)
  )
)

;; Results and finalization
(define-public (finalize-voting)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (is-voting-period-active)) err-voting-period-active)
    
    (var-set voting-open false)
    (log-action "VOTING_FINALIZED" "Voting results finalized")
    (ok (get-voting-stats))
  )
)