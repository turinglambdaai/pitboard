#lang racket/base

;; File-backed store: one JSON edition per day under data/YYYY-MM-DD.json.

(require racket/file
         racket/string
         racket/list
         racket/match
         json
         "util.rkt"
         "score.rkt"
         "sources.rkt")

(provide data-file
         save-digest!
         load-digest
         list-dates
         latest-digest
         digest->jsexpr)

(define (data-file dir date)
  (build-path dir (string-append date ".json")))

(define (save-digest! dir j)
  (make-directory* dir)
  (with-output-to-file (data-file dir (hash-ref j 'date))
    (λ () (write-json j))
    #:exists 'replace))

(define (list-dates dir)
  (if (directory-exists? dir)
      (sort
       (for/list ([p (in-list (directory-list dir))]
                  #:when (str-ends? (path->string p) ".json"))
         (substring (path->string p) 0 (- (string-length (path->string p)) 5)))
       string>?)
      '()))

(define (load-digest dir date)
  (define p (data-file dir date))
  (and (file-exists? p)
       (with-input-from-file p read-json)))

(define (latest-digest dir)
  (match (list-dates dir)
    ['() #f]
    [(cons d _) (load-digest dir d)]))

(define (digest->jsexpr date mode hots statuses [now (current-seconds)])
  (hasheq 'date date
          'generated_at (iso-datetime now)
          'mode mode
          'clusters (map hot->jsexpr hots)
          'sources (map source-status->jsexpr statuses)))
