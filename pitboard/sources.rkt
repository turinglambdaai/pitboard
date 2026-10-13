#lang racket/base

;; Source adapters: RSS feeds, GitHub topic search, arXiv query.
;; All network calls run under a hard timeout; any failure degrades to
;; a source-status record instead of killing the edition.

(require racket/string
         racket/list
         racket/format
         racket/match
         racket/file
         racket/set
         racket/port
         json
         net/uri-codec
         net/http-easy
         "util.rkt"
         "item.rkt"
         "feed.rkt")

(provide default-config
         load-config
         fetch-all
         (struct-out source-status)
         source-status->jsexpr)

(struct source-status (name kind ok count message) #:transparent)

(define (source-status->jsexpr s)
  (hasheq 'name (source-status-name s)
          'kind (source-status-kind s)
          'ok (source-status-ok s)
          'count (source-status-count s)
          'message (jx (source-status-message s))))

(define UA "pitboard/0.1 (+https://pitboard.jrtx.site)")

;; ---- config ---------------------------------------------------------------

(define arxiv-default-query
  "(cat:cs.RO OR cat:eess.SY) AND (abs:automotive OR abs:\"autonomous driving\" OR abs:vehicle OR abs:ADAS OR abs:\"connected vehicles\")")

(define default-topics
  (list "automotive" "autonomous-driving" "self-driving" "can-bus"
        "obd-ii" "adas" "ev-charging" "car-hacking"))

(define default-config
  (hasheq 'feeds
          (list (hasheq 'name "Ars Technica · Cars"
                        'url "https://arstechnica.com/cars/feed/"
                        'weight 1.2)
                (hasheq 'name "TechCrunch · Transportation"
                        'url "https://techcrunch.com/category/transportation/feed/"
                        'weight 1.0)
                (hasheq 'name "IEEE Spectrum · Transportation"
                        'url "https://spectrum.ieee.org/feeds/topic/transportation.rss"
                        'weight 1.1)
                (hasheq 'name "Electrek"
                        'url "https://electrek.co/feed/"
                        'weight 0.9))
          'github
          (hasheq 'topics default-topics
                  'per_page 8)
          'arxiv
          (hasheq 'query arxiv-default-query
                  'max_results 40)))

;; Accepts either our embedded shape or a JSON file with the same keys.
(define (load-config [path #f])
  (cond
    [(and path (file-exists? path))
     (with-handlers ([exn:fail? (λ (_) default-config)])
       (define j (with-input-from-file path read-json))
       (if (hash? j) j default-config))]
    [else default-config]))

;; ---- HTTP with a hard wall-clock timeout ----------------------------------

(define (http-get-bytes url-str
                        #:headers [hdrs (hasheq 'User-Agent UA)]
                        #:timeout-seconds [secs 25])
  (define ch (make-channel))
  (define worker
    (thread
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (channel-put ch (cons 'err (exn-message e))))])
         (define r (get url-str #:headers hdrs))
         (when (>= (response-status-code r) 400)
           (error 'http-get "HTTP ~a" (response-status-code r)))
         (channel-put ch (cons 'ok (response-body r)))))))
  (define v (sync/timeout secs ch))
  (cond
    [(not v)
     (kill-thread worker)
     (error 'http-get "timeout after ~as: ~a" secs url-str)]
    [(eq? (car v) 'err) (error 'http-get (cdr v))]
    [else (cdr v)]))

;; ---- RSS feeds -------------------------------------------------------------

(define (fetch-rss-feed f)
  (define name (hash-ref f 'name "feed"))
  (define weight (hash-ref f 'weight 1.0))
  (define b (http-get-bytes (hash-ref f 'url)))
  (define items (parse-feed b #:source-name name #:kind 'news #:weight weight))
  (values items (source-status name "rss" #t (length items) #f)))

;; ---- GitHub topic search ---------------------------------------------------

(define (github-headers token)
  (if token
      (hasheq 'User-Agent UA
              'Accept "application/vnd.github+json"
              'Authorization (string-append "Bearer " token))
      (hasheq 'User-Agent UA 'Accept "application/vnd.github+json")))

(define (repo->item h)
  (define full (hash-ref h 'full_name ""))
  (define url (hash-ref h 'html_url ""))
  (define pushed (parse-date-any (let ([v (hash-ref h 'pushed_at 'null)])
                                   (if (eq? v 'null) #f v))))
  (define desc (let ([d (hash-ref h 'description 'null)])
                 (if (eq? d 'null) "" (string-trim d))))
  (define lang (let ([l (hash-ref h 'language 'null)])
                 (if (eq? l 'null) #f l)))
  (and (non-empty-string? full)
       (non-empty-string? url)
       (item (format "gh:~a" full)
             'github
             "GitHub"
             "github.com"
             full
             url
             desc
             pushed
             (hasheq 'stars (hash-ref h 'stargazers_count 0)
                     'language (jx lang)
                     'created_at (jx (hash-ref h 'created_at 'null))))))

(define (github-search q per-page token)
  (define url
    (format "https://api.github.com/search/repositories?q=~a&sort=stars&order=desc&per_page=~a"
            (uri-encode q) per-page))
  (define b (http-get-bytes url #:headers (github-headers token)))
  (with-input-from-bytes b read-json))

(define (fetch-github [cfg (hasheq)] #:now [now (current-seconds)])
  (define topics (hash-ref cfg 'topics default-topics))
  (define per-page (hash-ref cfg 'per_page 8))
  (define token (getenv "GITHUB_TOKEN"))
  (define pushed-since (iso-date (- now (* 30 86400))))
  (define created-since (iso-date (- now (* 90 86400))))
  (define queries
    (append
     (for/list ([t (in-list topics)]) (format "topic:~a pushed:>~a" t pushed-since))
     (list (format "topic:automotive created:>~a" created-since))))
  (define items '())
  (define errs '())
  (for ([q (in-list queries)]
        [i (in-naturals)])
    (with-handlers ([exn:fail? (λ (e) (set! errs (cons (exn-message e) errs)))])
      (when (positive? i) (sleep (if token 2 7)))   ; search API rate limits
      (define res (github-search q per-page token))
      (define rows (hash-ref res 'items '()))
      (set! items (append items (filter values (map repo->item rows))))))
  (values items
          (source-status "GitHub 话题" "github" (null? errs)
                         (length items)
                         (and (pair? errs) (car errs)))))

;; ---- arXiv -----------------------------------------------------------------

(define (fetch-arxiv [cfg (hasheq)])
  (define q (hash-ref cfg 'query arxiv-default-query))
  (define maxn (hash-ref cfg 'max_results 40))
  (define url
    (format "https://export.arxiv.org/api/query?search_query=~a&sortBy=submittedDate&sortOrder=descending&max_results=~a"
            (uri-encode q) maxn))
  (define items
    (with-handlers ([exn:fail? (λ (_) '())])
      (define b (http-get-bytes url #:timeout-seconds 30))
      (parse-atom b #:source-name "arXiv" #:kind 'paper #:weight 1.0)))
  (values items (source-status "arXiv" "arxiv" #t (length items) #f)))

;; ---- all sources ------------------------------------------------------------

(define (fetch-all cfg)
  (define items '())
  (define statuses '())
  (define (absorb its st)
    (set! items (append items its))
    (set! statuses (cons st statuses)))
  (for ([f (in-list (hash-ref cfg 'feeds '()))])
    (call-with-values
     (λ ()
       (with-handlers
           ([exn:fail?
             (λ (e)
               (values '()
                       (source-status (hash-ref f 'name "feed") "rss" #f 0
                                      (exn-message e))))])
         (fetch-rss-feed f)))
     absorb))
  (call-with-values
   (λ ()
     (with-handlers
         ([exn:fail?
           (λ (e)
             (values '()
                     (source-status "GitHub 话题" "github" #f 0 (exn-message e))))])
       (fetch-github (hash-ref cfg 'github (hasheq)))))
   absorb)
  (call-with-values
   (λ ()
     (with-handlers
         ([exn:fail?
           (λ (e)
             (values '()
                     (source-status "arXiv" "arxiv" #f 0 (exn-message e))))])
       (fetch-arxiv (hash-ref cfg 'arxiv (hasheq)))))
   absorb)
  ;; dedupe by id (the same repo can surface from two queries)
  (define seen (mutable-set))
  (define dedup
    (for/list ([it (in-list items)]
               #:unless (set-member? seen (item-id it)))
      (set-add! seen (item-id it))
      it))
  (values dedup (reverse statuses)))
