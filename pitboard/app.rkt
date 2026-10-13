#lang racket/base

;; The web application: one Racket web-server process serving pages,
;; JSON API, RSS, markdown dailies and the SSE edition stream.

(require web-server/servlet
         web-server/servlet-env
         web-server/dispatch
         web-server/http/response-structs
         web-server/http/response
         web-server/http/request-structs
         racket/string
         racket/format
         racket/list
         racket/file
         json
         "store.rkt"
         "render.rkt"
         "sse.rkt"
         "util.rkt")

(provide start-server)

(define (resp-html b)
  (response/full 200 #"OK" (current-seconds)
                 (bytes->immutable-bytes #"text/html; charset=utf-8")
                 '() (list b)))

(define (resp-json b)
  (response/full 200 #"OK" (current-seconds)
                 (bytes->immutable-bytes #"application/json; charset=utf-8")
                 '() (list b)))

(define (resp-text b)
  (response/full 200 #"OK" (current-seconds)
                 (bytes->immutable-bytes #"text/plain; charset=utf-8")
                 '() (list b)))

(define (resp-rss b)
  (response/full 200 #"OK" (current-seconds)
                 (bytes->immutable-bytes #"application/rss+xml; charset=utf-8")
                 '() (list b)))

(define (resp-404 ctx)
  (response/full 404 #"Not Found" (current-seconds)
                 (bytes->immutable-bytes #"text/html; charset=utf-8")
                 '() (list (render-not-found ctx))))

(define (start-server #:port [port 8090]
                      #:data-dir [data-dir "data"]
                      #:assets-dir [assets-dir "assets"])
  (define ctx (site-ctx "pitboard.jrtx.site" "" (current-seconds)))
  (define hub (make-hub))
  (hub-watch! hub data-dir 5)

  (define (with-digest f)
    (define dg (latest-digest data-dir))
    (if dg (f dg) (resp-html (render-empty-page ctx))))

  (define (index-h req) (with-digest (λ (dg) (resp-html (render-index-page ctx dg)))))
  (define (date-h req date)
    (define dg (load-digest data-dir date))
    (if dg
        (resp-html (render-index-page ctx dg))
        (resp-404 ctx)))
  (define (archive-h req)
    (define dates (list-dates data-dir))
    (define rows2
      (for/list ([d (in-list (take dates (min 120 (length dates))))])
        (define dg (load-digest data-dir d))
        (define clusters (if dg (hash-ref dg 'clusters '()) '()))
        (list d (length clusters)
              (if (null? clusters) "" (v (hash-ref (car clusters) 'title ""))))))
    (resp-html (render-archive-page ctx rows2)))
  (define (about-h req) (resp-html (render-about-page ctx)))
  (define (rss-h req) (with-digest (λ (dg) (resp-rss (render-rss-xml ctx dg)))))
  (define (llms-h req) (resp-text (render-llms-txt ctx)))
  (define (health-h req) (resp-text (string->bytes/utf-8 "ok\n")))
  (define (api-latest-h req)
    (define dg (latest-digest data-dir))
    (if dg (resp-json (jsexpr->bytes dg)) (resp-404 ctx)))
  (define (api-date-h req date)
    (define d (regexp-replace #rx"\\.json$" date ""))
    (define dg (load-digest data-dir d))
    (if dg (resp-json (jsexpr->bytes dg)) (resp-404 ctx)))
  (define (daily-h req date)
    (define d (regexp-replace #rx"\\.md$" date ""))
    (define dg (load-digest data-dir d))
    (if dg
        (resp-text (render-daily-md ctx dg))
        (resp-404 ctx)))
  (define (events-h req)
    (response/output
     (λ (out) (hub-stream hub out))
     #:mime-type (bytes->immutable-bytes #"text/event-stream")
     #:headers
     (list (header #"Cache-Control" #"no-cache")
           (header #"X-Accel-Buffering" #"no"))))

  (define-values (dispatch url)
    (dispatch-rules
     [("") index-h]
     [("d" (string-arg)) date-h]
     [("archive") archive-h]
     [("about") about-h]
     [("rss.xml") rss-h]
     [("llms.txt") llms-h]
     [("healthz") health-h]
     [("api" "events") events-h]
     [("api" "v1" "latest.json") api-latest-h]
     [("api" "v1" "digest" (string-arg)) api-date-h]
     [("daily" (string-arg)) daily-h]))

  (printf "pitboard serving on http://0.0.0.0:~a (data: ~a)\n" port data-dir)
  (flush-output)
  (serve/servlet dispatch
                 #:port port
                 #:listen-ip #f
                 #:servlet-path "/"
                 #:servlet-regexp
                 #rx"^/($|d/.+|archive|about|rss\\.xml|llms\\.txt|healthz|api/.+|daily/.+)"
                 #:extra-files-paths
                 (list (path->complete-path assets-dir))
                 #:banner? #f))
