;; Multi-Send Fungible Token Contract
;; Supports sending multiple SIP-010 compliant tokens to multiple recipients

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-TRANSFER-FAILED (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-INVALID-RECIPIENT (err u104))
(define-constant ERR-TOKEN-NOT-FOUND (err u105))
(define-constant ERR-ARRAY-LENGTH-MISMATCH (err u106))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Fee structure (in microSTX)
(define-data-var base-fee uint u1000)
(define-data-var per-transfer-fee uint u100)

;; Temporary variables for fold operations (since Clarity doesn't support closures)
(define-data-var temp-token-contract principal tx-sender)
(define-data-var temp-amount uint u0)
(define-data-var temp-sender principal tx-sender)

;; Events
(define-map multi-send-events 
  { tx-id: uint }
  {
    sender: principal,
    token-contract: principal,
    total-amount: uint,
    recipient-count: uint,
    timestamp: uint
  }
)

(define-data-var event-nonce uint u0)

;; Note: Tuples are defined inline in Clarity, not as separate type definitions

;; Trait definition for SIP-010 fungible token
(define-trait sip-010-token
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Internal helper functions

;; Calculate total fee based on number of transfers
(define-private (calculate-fee (transfer-count uint))
  (+ (var-get base-fee) (* (var-get per-transfer-fee) transfer-count))
)

;; Validate that recipient is not zero address equivalent
(define-private (is-valid-recipient (recipient principal))
  (not (is-eq recipient 'SP000000000000000000002Q6VF78))
)

;; Calculate total amount from transfers list
(define-private (sum-transfer-amounts (transfers (list 100 { recipient: principal, amount: uint })))
  (fold + (map get-amount transfers) u0)
)

(define-private (get-amount (transfer { recipient: principal, amount: uint }))
  (get amount transfer)
)

;; Execute single token transfer
(define-private (execute-transfer 
  (token-contract <sip-010-token>)
  (transfer { recipient: principal, amount: uint })
  (sender principal)
)
  (let (
    (recipient (get recipient transfer))
    (amount (get amount transfer))
  )
    (if (is-eq amount u0)
      (err u101) ;; ERR-INVALID-AMOUNT
      (if (not (is-valid-recipient recipient))
        (err u104) ;; ERR-INVALID-RECIPIENT
        (contract-call? token-contract transfer amount sender recipient none)
      )
    )
  )
)

;; Execute multiple transfers for a single token
(define-private (execute-token-transfers
  (token-contract <sip-010-token>)
  (transfers (list 100 { recipient: principal, amount: uint }))
  (sender principal)
)
  (let (
    (total-amount (sum-transfer-amounts transfers))
  )
    ;; Check if sender has sufficient balance
    (match (contract-call? token-contract get-balance sender)
      balance 
        (if (>= balance total-amount)
          ;; Execute all transfers
          (let (
            (result (fold execute-single-transfer 
              transfers 
              { 
                token: token-contract, 
                sender: sender, 
                success: true,
                error: u0
              }
            ))
          )
            (if (get success result)
              (ok true)
              (err (get error result))
            )
          )
          (err u103) ;; ERR-INSUFFICIENT-BALANCE
        )
      error (err u105) ;; ERR-TOKEN-NOT-FOUND
    )
  )
)

;; Fold helper for executing transfers
(define-private (execute-single-transfer
  (transfer { recipient: principal, amount: uint })
  (context { token: <sip-010-token>, sender: principal, success: bool, error: uint })
)
  (if (get success context)
    (match (execute-transfer (get token context) transfer (get sender context))
      success-result context
      error-code { 
        token: (get token context),
        sender: (get sender context),
        success: false,
        error: error-code
      }
    )
    context
  )
)

;; Public functions

;; Send single token to multiple recipients
(define-public (multi-send-token
  (token-contract <sip-010-token>)
  (transfers (list 100 { recipient: principal, amount: uint }))
)
  (let (
    (sender tx-sender)
    (transfer-count (len transfers))
    (fee (calculate-fee transfer-count))
    (total-amount (sum-transfer-amounts transfers))
    (event-id (+ (var-get event-nonce) u1))
  )
    ;; Validate inputs
    (asserts! (> transfer-count u0) ERR-INVALID-AMOUNT)
    (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Check STX balance for fees
    (asserts! (>= (stx-get-balance sender) fee) ERR-INSUFFICIENT-BALANCE)
    
    ;; Pay fee to contract owner
    (try! (stx-transfer? fee sender (var-get contract-owner)))
    
    ;; Execute transfers
    (match (execute-token-transfers token-contract transfers sender)
      success-result 
        (begin
          ;; Log event
          (map-set multi-send-events 
            { tx-id: event-id }
            {
              sender: sender,
              token-contract: (contract-of token-contract),
              total-amount: total-amount,
              recipient-count: transfer-count,
              timestamp: block-height
            }
          )
          (var-set event-nonce event-id)
          (ok true)
        )
      error-code (err error-code)
    )
  )
)

;; Send multiple tokens to multiple recipients
(define-public (multi-send-multiple-tokens
  (token-transfers (list 10 {
    token-contract: <sip-010-token>,
    transfers: (list 100 { recipient: principal, amount: uint })
  }))
)
  (let (
    (sender tx-sender)
    (token-count (len token-transfers))
    (total-transfers (fold + (map count-transfers token-transfers) u0))
    (fee (calculate-fee total-transfers))
  )
    ;; Validate inputs
    (asserts! (> token-count u0) ERR-INVALID-AMOUNT)
    (asserts! (> total-transfers u0) ERR-INVALID-AMOUNT)
    
    ;; Check STX balance for fees
    (asserts! (>= (stx-get-balance sender) fee) ERR-INSUFFICIENT-BALANCE)
    
    ;; Pay fee to contract owner
    (try! (stx-transfer? fee sender (var-get contract-owner)))
    
    ;; Execute all token transfers
    (fold process-token-transfer token-transfers { sender: sender, success: true })
    
    (ok true)
  )
)

;; Helper function to count transfers
(define-private (count-transfers 
  (token-transfer {
    token-contract: <sip-010-token>,
    transfers: (list 100 { recipient: principal, amount: uint })
  })
)
  (len (get transfers token-transfer))
)

;; Helper function to process each token transfer
(define-private (process-token-transfer
  (token-transfer {
    token-contract: <sip-010-token>,
    transfers: (list 100 { recipient: principal, amount: uint })
  })
  (context { sender: principal, success: bool })
)
  (if (get success context)
    (match (execute-token-transfers 
      (get token-contract token-transfer) 
      (get transfers token-transfer) 
      (get sender context)
    )
      success-result context
      error-code { sender: (get sender context), success: false }
    )
    context
  )
)

;; Send same amount of a token to multiple recipients
(define-public (multi-send-equal-amounts
  (token-contract <sip-010-token>)
  (recipients (list 100 principal))
  (amount-per-recipient uint)
)
  (begin
    ;; Set temp variable for amount (workaround for Clarity's limitations)
    (var-set temp-amount amount-per-recipient)
    
    ;; Create transfers list and use existing multi-send-token function
    (multi-send-token 
      token-contract 
      (create-equal-transfers-list recipients amount-per-recipient)
    )
  )
)

;; Helper function to create transfers list for equal amounts
(define-private (create-equal-transfers-list 
  (recipients (list 100 principal))
  (amount uint)
)
  (begin
    ;; Set the amount in temp variable for map function
    (var-set temp-amount amount)
    (map create-transfer recipients)
  )
)

;; Create a single transfer record (uses fold variables)
(define-private (create-transfer (recipient principal))
  { recipient: recipient, amount: (var-get temp-amount) }
)

;; Admin functions

;; Update fees (only contract owner)
(define-public (set-fees (new-base-fee uint) (new-per-transfer-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set base-fee new-base-fee)
    (var-set per-transfer-fee new-per-transfer-fee)
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Emergency withdrawal of accumulated fees
(define-public (withdraw-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (stx-transfer? amount (as-contract tx-sender) (var-get contract-owner))
  )
)

;; Read-only functions

;; Get current fees
(define-read-only (get-fees)
  {
    base-fee: (var-get base-fee),
    per-transfer-fee: (var-get per-transfer-fee)
  }
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Calculate fee for a given number of transfers
(define-read-only (get-fee-for-transfers (transfer-count uint))
  (calculate-fee transfer-count)
)

;; Get multi-send event details
(define-read-only (get-multi-send-event (tx-id uint))
  (map-get? multi-send-events { tx-id: tx-id })
)

;; Get current event nonce
(define-read-only (get-current-event-nonce)
  (var-get event-nonce)
)