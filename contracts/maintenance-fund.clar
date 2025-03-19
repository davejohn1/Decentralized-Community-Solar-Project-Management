;; Maintenance Fund Contract
;; Manages shared costs for system upkeep

;; Error codes
(define-constant ERR_UNAUTHORIZED u4000)
(define-constant ERR_INSUFFICIENT_FUNDS u4001)
(define-constant ERR_MAINTENANCE_NOT_FOUND u4002)
(define-constant ERR_INVALID_AMOUNT u4003)
(define-constant ERR_INVALID_STATUS u4004)

;; Maintenance status constants
(define-constant STATUS_PROPOSED u1)
(define-constant STATUS_APPROVED u2)
(define-constant STATUS_IN_PROGRESS u3)
(define-constant STATUS_COMPLETED u4)
(define-constant STATUS_CANCELLED u5)

;; Data variables
(define-data-var fund-balance uint u0)
(define-data-var contribution-rate uint u10) ;; percentage of energy credits
(define-data-var next-maintenance-id uint u1)

;; Data maps
(define-map maintenance-records
  { maintenance-id: uint }
  {
    description: (string-utf8 100),
    estimated-cost: uint,
    actual-cost: uint,
    proposed-date: uint,
    completion-date: uint,
    contractor: principal,
    status: uint
  }
)

(define-map contributions
  { owner: principal, year: uint, month: uint }
  {
    amount: uint,
    contribution-date: uint
  }
)

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; Read-only functions
(define-read-only (get-fund-balance)
  (var-get fund-balance)
)

(define-read-only (get-contribution-rate)
  (var-get contribution-rate)
)

(define-read-only (get-maintenance-record (maintenance-id uint))
  (map-get? maintenance-records { maintenance-id: maintenance-id })
)

(define-read-only (get-contribution (owner principal) (year uint) (month uint))
  (map-get? contributions { owner: owner, year: year, month: month })
)

;; Check if caller is admin
(define-private (is-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Public functions
(define-public (contribute-to-fund (amount uint))
  (begin
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))

    ;; Update fund balance
    (var-set fund-balance (+ (var-get fund-balance) amount))

    ;; Record contribution
    (let (
      (year (/ block-height u1000)) ;; Simplified year calculation
      (month (mod (/ block-height u100) u12)) ;; Simplified month calculation
    )
      (match (map-get? contributions { owner: tx-sender, year: year, month: month })
        existing-contribution
        (map-set contributions
          { owner: tx-sender, year: year, month: month }
          {
            amount: (+ (get amount existing-contribution) amount),
            contribution-date: block-height
          }
        )
        (map-set contributions
          { owner: tx-sender, year: year, month: month }
          {
            amount: amount,
            contribution-date: block-height
          }
        )
      )
    )
    (ok true)
  )
)

(define-public (propose-maintenance (description (string-utf8 100)) (estimated-cost uint) (contractor principal))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))
    (asserts! (> estimated-cost u0) (err ERR_INVALID_AMOUNT))

    (let (
      (maintenance-id (var-get next-maintenance-id))
    )
      (var-set next-maintenance-id (+ maintenance-id u1))

      (map-set maintenance-records
        { maintenance-id: maintenance-id }
        {
          description: description,
          estimated-cost: estimated-cost,
          actual-cost: u0,
          proposed-date: block-height,
          completion-date: u0,
          contractor: contractor,
          status: STATUS_PROPOSED
        }
      )
      (ok maintenance-id)
    )
  )
)

(define-public (approve-maintenance (maintenance-id uint))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))

    (match (map-get? maintenance-records { maintenance-id: maintenance-id })
      record
      (begin
        (asserts! (is-eq (get status record) STATUS_PROPOSED) (err ERR_INVALID_STATUS))
        (asserts! (<= (get estimated-cost record) (var-get fund-balance)) (err ERR_INSUFFICIENT_FUNDS))

        (map-set maintenance-records
          { maintenance-id: maintenance-id }
          (merge record { status: STATUS_APPROVED })
        )
        (ok true)
      )
      (err ERR_MAINTENANCE_NOT_FOUND)
    )
  )
)

(define-public (complete-maintenance (maintenance-id uint) (actual-cost uint))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))
    (asserts! (> actual-cost u0) (err ERR_INVALID_AMOUNT))

    (match (map-get? maintenance-records { maintenance-id: maintenance-id })
      record
      (begin
        (asserts! (is-eq (get status record) STATUS_APPROVED) (err ERR_INVALID_STATUS))
        (asserts! (<= actual-cost (var-get fund-balance)) (err ERR_INSUFFICIENT_FUNDS))

        ;; Update maintenance record
        (map-set maintenance-records
          { maintenance-id: maintenance-id }
          (merge record {
            status: STATUS_COMPLETED,
            actual-cost: actual-cost,
            completion-date: block-height
          })
        )

        ;; Deduct from fund balance
        (var-set fund-balance (- (var-get fund-balance) actual-cost))

        (ok true)
      )
      (err ERR_MAINTENANCE_NOT_FOUND)
    )
  )
)

(define-public (update-contribution-rate (new-rate uint))
  (begin
    (asserts! (is-admin) (err ERR_UNAUTHORIZED))
    (asserts! (<= new-rate u100) (err ERR_INVALID_AMOUNT))

    (var-set contribution-rate new-rate)
    (ok true)
  )
)

