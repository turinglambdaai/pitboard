#lang racket/base

;; File-backed store: one JSON edition per day under data/YYYY-MM-DD.json.

(require racket/file
         racket/string
         racket/list
         racket/match
         racket/date
         racket/port
         json
         "util.rkt"
         "score.rkt"
         "sources.rkt")

(provide data-file
         save-digest!
         load-digest
         list-dates
         latest-digest
         digest->jsexpr
         load-event-history
         monday-key
         month-key
         period-rows
         update-health!
         load-health
         append-ingested!
         load-ingested
         clear-ingested!)

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


;; fingerprint -> (cons token-list first-seen-date), earliest date wins.
;; Skips exclude-date (today's own edition, which is being rebuilt).
(define (load-event-history dir #:exclude-date [exclude-date #f])
  (for/fold ([hist (hash)])
            ([d (in-list (list-dates dir))]
             #:unless (equal? d exclude-date))
    (define dg (load-digest dir d))
    (for/fold ([hist hist])
              ([c (in-list (if dg (hash-ref dg 'clusters '()) '()))])
      (define text
        (string-append
         (let ([t (hash-ref c 'title "")]) (if (string? t) t ""))
         " "
         (let ([sm (hash-ref c 'summary "")]) (if (string? sm) sm ""))))
      (define fp (event-fingerprint text))
      (if (hash-has-key? hist fp)
          hist
          (hash-set hist fp
                    (cons (string-split fp " ") d))))))

;; ---- period grouping (weekly / monthly) ------------------------------------

;; Monday-of-week key for an ISO date (YYYY-MM-DD).
(define (monday-key ymd)
  (define secs (parse-date-any ymd))
  (if (not secs)
      ymd
      (let* ([d (seconds->date secs #t)]
             [wd (date-week-day d)]              ; 0 = Sunday
             [off (if (zero? wd) 6 (sub1 wd))])
        (iso-date (- secs (* off 86400))))))

(define (month-key ymd)
  (if (>= (string-length ymd) 7) (substring ymd 0 7) ymd))

;; Flatten top clusters of the given dates into deduped rows:
;; (list date title url heat).  Dedupe by normalized title prefix.
(define (period-rows dir dates #:per-day [per-day 8] #:cap [cap 40])
  (let loop ([rest dates] [rows '()] [seen (hash)])
    (if (or (null? rest) (>= (length rows) cap))
        (reverse rows)
        (let* ([d (car rest)]
               [dg (load-digest dir d)]
               [day-rows
                (for/list ([c (in-list (take (hash-ref dg 'clusters '())
                                             (min per-day
                                                  (length (hash-ref dg 'clusters '())))))]
                           #:do [(define first-item
                                   (car (hash-ref c 'items '())))]
                           #:when (eq? (hash-ref first-item 'kind "news") "news"))
                  (list d
                        (hash-ref c 'title "")
                        (hash-ref (car (hash-ref c 'items '())) 'url "")
                        (hash-ref c 'heat "0")))]
               [fresh
                (for/list ([r (in-list day-rows)]
                           #:unless (hash-has-key? seen
                                      (string-downcase
                                       (substring (cadr r) 0
                                                  (min 60 (string-length (cadr r)))))))
                  r)]
               [seen2
                (for/fold ([seen seen]) ([r (in-list fresh)])
                  (hash-set seen
                            (string-downcase
                             (substring (cadr r) 0 (min 60 (string-length (cadr r)))))
                            #t))])
          (loop (cdr rest)
                (append (reverse fresh) rows)
                seen2)))))


;; ---- source health (alerting) ------------------------------------------------

(define (health-file dir) (build-path dir "health.json"))

;; statuses: list of source-status. Streak++ on failure, reset on ok.
(define (update-health! dir statuses now)
  (define prev
    (with-handlers ([exn:fail? (λ (_) (hasheq))])
      (with-input-from-file (health-file dir) read-json)))
  (define next
    (for/hash ([st (in-list statuses)])
      (values (source-status-name st)
              (let* ([old (hash-ref prev (source-status-name st) (hasheq))]
                     [streak (if (source-status-ok st)
                                 0
                                 (add1 (let ([v (hash-ref old 'fail_streak 0)])
                                         (if (number? v) v 0))))]
                     [last-ok (if (source-status-ok st)
                                  (iso-datetime now)
                                  (hash-ref old 'last_ok 'null))])
                (hasheq 'ok (source-status-ok st)
                        'fail_streak streak
                        'last_ok last-ok)))))
  (with-output-to-file (health-file dir)
    (λ () (write-json next)) #:exists 'replace)
  next)

(define (load-health dir)
  (with-handlers ([exn:fail? (λ (_) (hasheq))])
    (with-input-from-file (health-file dir) read-json)))


;; ---- script-push ingest (external scripts POST items) ------------------------

(define (ingested-file dir) (build-path dir "ingested.jsonl"))

(define (append-ingested! dir item-jsexpr)
  (make-directory* dir)
  (with-output-to-file (ingested-file dir)
    (λ () (write-string (string-append (jsexpr->string item-jsexpr) "\n")))
    #:exists 'append))

(define (load-ingested dir)
  (define f (ingested-file dir))
  (if (not (file-exists? f))
      '()
      (with-input-from-file f
        (lambda ()
          (for/list ([line (in-lines)]
                     #:when (non-empty-string? (string-trim line)))
            (with-handlers ([exn:fail? (lambda (e) #f)])
              (read-json (open-input-string line))))))))

(define (clear-ingested! dir)
  (define f (ingested-file dir))
  (when (file-exists? f) (delete-file f)))
