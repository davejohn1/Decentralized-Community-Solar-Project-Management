;; Credit Distribution Contract
;; Allocates energy credits to participants based on ownership

;; Error codes
(define-constant ERR_UNAUTHORIZED u3000)
(define-constant ERR_PERIOD_NOT_FOUND u3001)
(define-constant ERR_INVALID_CREDITS u3002)
(define-constant ERR_ALREADY_DISTRIBUTED u3003)
(define-constant ERR_OWNER_NOT_FOUND u3004)

;; Data maps
(define-map production-periods
  { period-id: uint }
  {
    start-date: uint,
    end-date: uint,
    total-energy: uint,
    total-credits: uint,
    distribution-status: uint,
    distribution-date: uint
  }
)

(define-map credit-allocations
  { period-id: uint, owner: principal }
  {
    ownership-percentage: uint,
    credits-allocated: uint
  }
)

;; Distribution status constants
(define-constant STATUS_PENDING u1)
(define-constant STATUS_DISTRIBUTED u2)
(define-constant STATUS_CANCELLED u3)

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; Read-only functions
(define-read-only (get-production-period (period-id uint))
  (map-get? production-periods { period-id: period-id })
)

(define-read-only (get-credit-allocation (period-id uint) (owner principal))
  (map-get? credit-allocations { period-id: period-id, owner: owner })
)

;; Check if caller is admin
(define-private (is-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Public functions
(define-public (register-production-period (period-id uint) (start-date uint) (end-date uint) (total-energy uint) (total-credits uint))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))
    (asserts! (> total-credits u0) (err ERR_INVALID_CREDITS))
    (asserts! (is-none (map-get? production-periods { period-id: period-id })) (err ERR_ALREADY_DISTRIBUTED))

    (map-set production-periods
      { period-id: period-id }
      {
        start-date: start-date,
        end-date: end-date,
        total-energy: total-energy,
        total-credits: total-credits,
        distribution-status: STATUS_PENDING,
        distribution-date: u0
      }
    )
    (ok period-id)
  )
)

(define-public (allocate-credits (period-id uint) (owner principal) (ownership-percentage uint))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))
    (asserts! (<= ownership-percentage u100) (err ERR_INVALID_CREDITS))

    (match (map-get? production-periods { period-id: period-id })
      period
      (begin
        (asserts! (is-eq (get distribution-status period) STATUS_PENDING) (err ERR_ALREADY_DISTRIBUTED))

        (let (
          (credits-to-allocate (/ (* (get total-credits period) ownership-percentage) u100))
        )
          (map-set credit-allocations
            { period-id: period-id, owner: owner }
            {
              ownership-percentage: ownership-percentage,
              credits-allocated: credits-to-allocate
            }
          )
          (ok credits-to-allocate)
        )
      )
      (err ERR_PERIOD_NOT_FOUND)
    )
  )
)

(define-public (finalize-distribution (period-id uint))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))

    (match (map-get? production-periods { period-id: period-id })
      period
      (begin
        (asserts! (is-eq (get distribution-status period) STATUS_PENDING) (err ERR_ALREADY_DISTRIBUTED))

        (map-set production-periods
          { period-id: period-id }
          (merge period {
            distribution-status: STATUS_DISTRIBUTED,
            distribution-date: block-height
          })
        )
        (ok true)
      )
      (err ERR_PERIOD_NOT_FOUND)
    )
  )
)

(define-public (claim-credits (period-id uint))
  (begin
    (match (map-get? credit-allocations { period-id: period-id, owner: tx-sender })
      allocation
      (begin
        (match (map-get? production-periods { period-id: period-id })
          period
          (begin
            (asserts! (is-eq (get distribution-status period) STATUS_DISTRIBUTED) (err ERR_PERIOD_NOT_FOUND))
            ;; In a real implementation, this would transfer tokens or update utility credits
            ;; For simplicity, we're just returning the allocated credits
            (ok (get credits-allocated allocation))
          )
          (err ERR_PERIOD_NOT_FOUND)
        )
      )
      (err ERR_OWNER_NOT_FOUND)
    )
  )
)

