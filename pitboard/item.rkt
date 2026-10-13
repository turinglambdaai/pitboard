#lang racket/base

;; The normalized atom every source produces: one story, one place, one time.

(require racket/format
         racket/list
         racket/string
         feed
         "util.rkt")

(provide (struct-out item)
         item->jsexpr
         jsexpr->item
         make-item-id
         feed->items)

;; kind is 'github, 'news or 'paper.  published is UTC seconds or #f.
;; extra is a hasheq with symbol keys whose values are jsexpr-safe.
(struct item (id kind source source-url title url summary published extra)
  #:transparent)

(define (make-item-id kind key)
  (format "~a:~a" kind (equal-hash-code key)))

(define (item->jsexpr it)
  (hasheq 'id (item-id it)
          'kind (symbol->string (item-kind it))
          'source (item-source it)
          'source_url (item-source-url it)
          'title (item-title it)
          'url (item-url it)
          'summary (truncate-s (item-summary it) 500)
          'published_at (jx (and (item-published it) (iso-datetime (item-published it))))
          'extra (item-extra it)))

(define (jsexpr->item h)
  (item (hash-ref h 'id "")
        (string->symbol (hash-ref h 'kind "news"))
        (hash-ref h 'source "")
        (hash-ref h 'source_url "")
        (hash-ref h 'title "")
        (hash-ref h 'url "")
        (hash-ref h 'summary "")
        (and (iso->secs (hash-ref h 'published_at 'null)))
        (hash-ref h 'extra (hasheq))))

(define (iso->secs v)
  (and (not (eq? v 'null))
       (string? v)
       (parse-date-any v)))

;; Assembly policy for generic feed entries (was pitboard/feed.rkt's
;; `make`): drop entries without a usable link or title, normalize the
;; URL for dedup, stamp the domain, strip HTML from the summary.
;; Parsing itself lives in the feed package.
(define (feed->items fis #:source-name name #:kind [kind 'news] #:weight [w 1.0])
  (filter-map
   (λ (fi)
     (define u (and (feed-item-link fi)
                    (non-empty-string? (string-trim (feed-item-link fi)))
                    (normalize-url (string-trim (feed-item-link fi)))))
     (and u
          (non-empty-string? (string-trim (feed-item-title fi)))
          (item (make-item-id kind u)
                kind
                name
                (slug-domain u)
                (string-trim (feed-item-title fi))
                u
                (truncate-s (strip-html (feed-item-summary fi)) 500)
                (feed-item-published fi)
                (hasheq 'weight w))))
   fis))
