;; Enhanced Immutable Storage Contract
;; This contract allows storing multiple types of immutable data with metadata and access controls

;; Data Variables
(define-data-var stored-value (optional uint) none)
(define-data-var stored-string (optional (string-ascii 256)) none)
(define-data-var stored-boolean (optional bool) none)
(define-data-var is-value-set bool false)
(define-data-var is-string-set bool false)
(define-data-var is-boolean-set bool false)
(define-data-var contract-owner principal tx-sender)
(define-data-var creation-timestamp uint block-height)
(define-data-var value-set-timestamp (optional uint) none)
(define-data-var total-storage-operations uint u0)

;; Maps for multiple key-value storage
(define-map immutable-data 
  { key: (string-ascii 64) }
  { 
    value: (string-ascii 512),
    setter: principal,
    timestamp: uint,
    is-locked: bool
  }
)

;; Map to track authorized setters
(define-map authorized-setters principal bool)

;; Error Constants
(define-constant ERR-VALUE-ALREADY-SET (err u100))
(define-constant ERR-UNAUTHORIZED (err u101))
(define-constant ERR-KEY-ALREADY-EXISTS (err u102))
(define-constant ERR-KEY-NOT-FOUND (err u103))
(define-constant ERR-INVALID-INPUT (err u104))
(define-constant ERR-STRING-TOO-LONG (err u105))

;; Public Functions

;; Store a uint value (can only be called once)
(define-public (store-value (value uint))
  (begin
    (asserts! (is-eq (var-get is-value-set) false) ERR-VALUE-ALREADY-SET)
    (asserts! (> value u0) ERR-INVALID-INPUT)
    
    (var-set stored-value (some value))
    (var-set is-value-set true)
    (var-set value-set-timestamp (some block-height))
    (var-set total-storage-operations (+ (var-get total-storage-operations) u1))
    
    (print { event: "value-stored", value: value, setter: tx-sender, timestamp: block-height })
    (ok value)
  )
)

;; Store a string value (can only be called once)
(define-public (store-string (value (string-ascii 256)))
  (begin
    (asserts! (is-eq (var-get is-string-set) false) ERR-VALUE-ALREADY-SET)
    (asserts! (> (len value) u0) ERR-INVALID-INPUT)
    
    (var-set stored-string (some value))
    (var-set is-string-set true)
    (var-set total-storage-operations (+ (var-get total-storage-operations) u1))
    
    (print { event: "string-stored", value: value, setter: tx-sender, timestamp: block-height })
    (ok value)
  )
)

;; Store a boolean value (can only be called once)
(define-public (store-boolean (value bool))
  (begin
    (asserts! (is-eq (var-get is-boolean-set) false) ERR-VALUE-ALREADY-SET)
    
    (var-set stored-boolean (some value))
    (var-set is-boolean-set true)
    (var-set total-storage-operations (+ (var-get total-storage-operations) u1))
    
    (print { event: "boolean-stored", value: value, setter: tx-sender, timestamp: block-height })
    (ok value)
  )
)

;; Store key-value pair (immutable once set)
(define-public (store-data (key (string-ascii 64)) (value (string-ascii 512)))
  (begin
    (asserts! (> (len key) u0) ERR-INVALID-INPUT)
    (asserts! (> (len value) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? immutable-data { key: key })) ERR-KEY-ALREADY-EXISTS)
    
    (map-set immutable-data 
      { key: key }
      {
        value: value,
        setter: tx-sender,
        timestamp: block-height,
        is-locked: true
      }
    )
    
    (var-set total-storage-operations (+ (var-get total-storage-operations) u1))
    (print { event: "data-stored", key: key, value: value, setter: tx-sender })
    (ok true)
  )
)

;; Authorize a principal to store data (only owner)
(define-public (authorize-setter (setter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (map-set authorized-setters setter true)
    (print { event: "setter-authorized", setter: setter, by: tx-sender })
    (ok true)
  )
)

;; Revoke authorization (only owner)
(define-public (revoke-setter (setter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (map-delete authorized-setters setter)
    (print { event: "setter-revoked", setter: setter, by: tx-sender })
    (ok true)
  )
)

;; Store data with authorization check
(define-public (store-authorized-data (key (string-ascii 64)) (value (string-ascii 512)))
  (begin
    (asserts! (or 
      (is-eq tx-sender (var-get contract-owner))
      (default-to false (map-get? authorized-setters tx-sender))
    ) ERR-UNAUTHORIZED)
    (asserts! (> (len key) u0) ERR-INVALID-INPUT)
    (asserts! (> (len value) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? immutable-data { key: key })) ERR-KEY-ALREADY-EXISTS)
    
    (map-set immutable-data 
      { key: key }
      {
        value: value,
        setter: tx-sender,
        timestamp: block-height,
        is-locked: true
      }
    )
    
    (var-set total-storage-operations (+ (var-get total-storage-operations) u1))
    (print { event: "authorized-data-stored", key: key, value: value, setter: tx-sender })
    (ok true)
  )
)

;; Read-only Functions

;; Get the stored uint value
(define-read-only (get-stored-value)
  (var-get stored-value)
)

;; Get the stored string value
(define-read-only (get-stored-string)
  (var-get stored-string)
)

;; Get the stored boolean value
(define-read-only (get-stored-boolean)
  (var-get stored-boolean)
)

;; Get data by key
(define-read-only (get-data (key (string-ascii 64)))
  (map-get? immutable-data { key: key })
)

;; Get just the value by key
(define-read-only (get-data-value (key (string-ascii 64)))
  (match (map-get? immutable-data { key: key })
    data (some (get value data))
    none
  )
)

;; Check if any value type has been set
(define-read-only (is-any-value-set)
  (or 
    (var-get is-value-set)
    (or (var-get is-string-set) (var-get is-boolean-set))
  )
)

;; Check specific value type initialization
(define-read-only (get-initialization-status)
  {
    uint-set: (var-get is-value-set),
    string-set: (var-get is-string-set),
    boolean-set: (var-get is-boolean-set)
  }
)

;; Get contract metadata
(define-read-only (get-contract-info)
  {
    owner: (var-get contract-owner),
    creation-timestamp: (var-get creation-timestamp),
    value-set-timestamp: (var-get value-set-timestamp),
    total-operations: (var-get total-storage-operations)
  }
)

;; Check if principal is authorized
(define-read-only (is-authorized-setter (setter principal))
  (or 
    (is-eq setter (var-get contract-owner))
    (default-to false (map-get? authorized-setters setter))
  )
)

;; Get value with default fallback
(define-read-only (get-value-or-default (default uint))
  (match (var-get stored-value)
    value value
    default
  )
)

;; Get string with default fallback
(define-read-only (get-string-or-default (default (string-ascii 256)))
  (match (var-get stored-string)
    value value
    default
  )
)

;; Utility function to check if key exists
(define-read-only (key-exists (key (string-ascii 64)))
  (is-some (map-get? immutable-data { key: key }))
)

;; Get multiple values at once
(define-read-only (get-all-primary-values)
  {
    uint-value: (var-get stored-value),
    string-value: (var-get stored-string),
    boolean-value: (var-get stored-boolean)
  }
)

;; Validation function for data integrity
(define-read-only (validate-storage-state)
  {
    consistent: (is-eq 
      (var-get is-value-set) 
      (is-some (var-get stored-value))
    ),
    total-operations: (var-get total-storage-operations),
    contract-age: (- block-height (var-get creation-timestamp))
  }
)