;; Quartz Extract - Ethical Mineral Provenance Tracking
;; A Clarity smart contract for tracking mineral and precious stone provenance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-score (err u104))

;; Data Variables
(define-data-var min-ethical-score uint u60)

;; Data Maps
(define-map materials
  { material-id: (string-ascii 64) }
  {
    origin: (string-ascii 100),
    extraction-date: uint,
    material-type: (string-ascii 50),
    weight-grams: uint,
    extractor: principal,
    geo-verified: bool,
    satellite-confirmed: bool,
    ethical-score: uint,
    current-holder: principal,
    ipfs-hash: (string-ascii 64)
  }
)

(define-map supply-chain-events
  { event-id: uint }
  {
    material-id: (string-ascii 64),
    event-type: (string-ascii 50),
    timestamp: uint,
    actor: principal,
    location: (string-ascii 100),
    verified: bool,
    ipfs-document: (string-ascii 64)
  }
)

(define-map compliance-scores
  { material-id: (string-ascii 64) }
  {
    environmental-score: uint,
    labor-score: uint,
    transparency-score: uint,
    overall-score: uint,
    last-updated: uint
  }
)

(define-map authorized-validators
  { validator: principal }
  { authorized: bool }
)

(define-map escrow-contracts
  { escrow-id: uint }
  {
    material-id: (string-ascii 64),
    buyer: principal,
    seller: principal,
    amount: uint,
    min-score-required: uint,
    released: bool
  }
)

;; Data variable for event counter
(define-data-var event-counter uint u0)
(define-data-var escrow-counter uint u0)

;; Authorization functions
(define-public (add-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-validators { validator: validator } { authorized: true }))
  )
)

(define-read-only (is-validator (validator principal))
  (default-to false (get authorized (map-get? authorized-validators { validator: validator })))
)

;; Register new material at extraction point
(define-public (register-material 
  (material-id (string-ascii 64))
  (origin (string-ascii 100))
  (material-type (string-ascii 50))
  (weight-grams uint)
  (ipfs-hash (string-ascii 64)))
  (let
    (
      (existing (map-get? materials { material-id: material-id }))
    )
    (asserts! (is-none existing) err-already-exists)
    (ok (map-set materials
      { material-id: material-id }
      {
        origin: origin,
        extraction-date: block-height,
        material-type: material-type,
        weight-grams: weight-grams,
        extractor: tx-sender,
        geo-verified: false,
        satellite-confirmed: false,
        ethical-score: u0,
        current-holder: tx-sender,
        ipfs-hash: ipfs-hash
      }
    ))
  )
)

;; Verify extraction with geolocation and satellite data
(define-public (verify-extraction 
  (material-id (string-ascii 64))
  (geo-verified bool)
  (satellite-confirmed bool))
  (let
    (
      (material (unwrap! (map-get? materials { material-id: material-id }) err-not-found))
    )
    (asserts! (is-validator tx-sender) err-unauthorized)
    (ok (map-set materials
      { material-id: material-id }
      (merge material {
        geo-verified: geo-verified,
        satellite-confirmed: satellite-confirmed
      })
    ))
  )
)

;; Record supply chain event
(define-public (add-supply-chain-event
  (material-id (string-ascii 64))
  (event-type (string-ascii 50))
  (location (string-ascii 100))
  (ipfs-document (string-ascii 64)))
  (let
    (
      (event-id (+ (var-get event-counter) u1))
      (material (unwrap! (map-get? materials { material-id: material-id }) err-not-found))
    )
    (var-set event-counter event-id)
    (map-set supply-chain-events
      { event-id: event-id }
      {
        material-id: material-id,
        event-type: event-type,
        timestamp: block-height,
        actor: tx-sender,
        location: location,
        verified: false,
        ipfs-document: ipfs-document
      }
    )
    (ok event-id)
  )
)

;; Update compliance scores (AI-generated, recorded by validators)
(define-public (update-compliance-score
  (material-id (string-ascii 64))
  (environmental-score uint)
  (labor-score uint)
  (transparency-score uint))
  (let
    (
      (material (unwrap! (map-get? materials { material-id: material-id }) err-not-found))
      (overall-score (/ (+ environmental-score labor-score transparency-score) u3))
    )
    (asserts! (is-validator tx-sender) err-unauthorized)
    (asserts! (<= environmental-score u100) err-invalid-score)
    (asserts! (<= labor-score u100) err-invalid-score)
    (asserts! (<= transparency-score u100) err-invalid-score)
    
    (map-set compliance-scores
      { material-id: material-id }
      {
        environmental-score: environmental-score,
        labor-score: labor-score,
        transparency-score: transparency-score,
        overall-score: overall-score,
        last-updated: block-height
      }
    )
    
    (ok (map-set materials
      { material-id: material-id }
      (merge material { ethical-score: overall-score })
    ))
  )
)

;; Transfer material custody
(define-public (transfer-custody
  (material-id (string-ascii 64))
  (new-holder principal))
  (let
    (
      (material (unwrap! (map-get? materials { material-id: material-id }) err-not-found))
    )
    (asserts! (is-eq (get current-holder material) tx-sender) err-unauthorized)
    (ok (map-set materials
      { material-id: material-id }
      (merge material { current-holder: new-holder })
    ))
  )
)

;; Create escrow contract with ethical score requirement
(define-public (create-escrow
  (material-id (string-ascii 64))
  (seller principal)
  (min-score-required uint))
  (let
    (
      (escrow-id (+ (var-get escrow-counter) u1))
      (material (unwrap! (map-get? materials { material-id: material-id }) err-not-found))
    )
    (asserts! (<= min-score-required u100) err-invalid-score)
    (var-set escrow-counter escrow-id)
    (map-set escrow-contracts
      { escrow-id: escrow-id }
      {
        material-id: material-id,
        buyer: tx-sender,
        seller: seller,
        amount: u0,
        min-score-required: min-score-required,
        released: false
      }
    )
    (ok escrow-id)
  )
)

;; Release escrow if ethical score meets requirements
(define-public (release-escrow (escrow-id uint))
  (let
    (
      (escrow (unwrap! (map-get? escrow-contracts { escrow-id: escrow-id }) err-not-found))
      (material (unwrap! (map-get? materials { material-id: (get material-id escrow) }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get buyer escrow)) err-unauthorized)
    (asserts! (not (get released escrow)) err-unauthorized)
    (asserts! (>= (get ethical-score material) (get min-score-required escrow)) err-invalid-score)
    
    (ok (map-set escrow-contracts
      { escrow-id: escrow-id }
      (merge escrow { released: true })
    ))
  )
)

;; Read-only functions
(define-read-only (get-material (material-id (string-ascii 64)))
  (map-get? materials { material-id: material-id })
)

(define-read-only (get-compliance-score (material-id (string-ascii 64)))
  (map-get? compliance-scores { material-id: material-id })
)

(define-read-only (get-supply-chain-event (event-id uint))
  (map-get? supply-chain-events { event-id: event-id })
)

(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrow-contracts { escrow-id: escrow-id })
)

(define-read-only (get-min-ethical-score)
  (var-get min-ethical-score)
)

;; Initialize contract with owner as first validator
(map-set authorized-validators { validator: contract-owner } { authorized: true })