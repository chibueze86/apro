
;; title: decentralized_identity
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-registered (err u102))
(define-constant err-kyc-already-verified (err u103))

;; Define data maps
(define-map users principal { did: (string-ascii 64), kyc-verified: bool })
(define-map companies principal { name: (string-ascii 64), kyc-verified: bool })

;; Read-only functions

(define-read-only (get-user-did (user principal))
  (default-to "" (get did (map-get? users user)))
)

(define-read-only (is-user-kyc-verified (user principal))
  (default-to false (get kyc-verified (map-get? users user)))
)

(define-read-only (is-company-kyc-verified (company principal))
  (default-to false (get kyc-verified (map-get? companies company)))
)

;; Public functions

(define-public (register-user (did (string-ascii 64)))
  (let ((user tx-sender))
    (if (is-none (map-get? users user))
      (ok (map-set users user { did: did, kyc-verified: false }))
      err-already-registered
    )
  )
)

(define-public (register-company (name (string-ascii 64)))
  (let ((company tx-sender))
    (if (is-none (map-get? companies company))
      (ok (map-set companies company { name: name, kyc-verified: false }))
      err-already-registered
    )
  )
)

(define-public (verify-user-kyc (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (match (map-get? users user)
      entry (if (get kyc-verified entry)
              err-kyc-already-verified
              (ok (map-set users user (merge entry { kyc-verified: true })))
            )
      err-not-registered
    )
  )
)

(define-public (verify-company-kyc (company principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (match (map-get? companies company)
      entry (if (get kyc-verified entry)
              err-kyc-already-verified
              (ok (map-set companies company (merge entry { kyc-verified: true })))
            )
      err-not-registered
    )
  )
)

;; Private functions

(define-private (is-kyc-verified (entity principal))
  (or
    (is-user-kyc-verified entity)
    (is-company-kyc-verified entity)
  )
)