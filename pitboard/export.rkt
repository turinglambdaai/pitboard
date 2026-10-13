#lang racket/base

;; Static export: renders the whole site (Pages mirror) from data/.

(require racket/file
         racket/path
         racket/string
         racket/list
         racket/format
         json
         "util.rkt"
         "store.rkt"
         "render.rkt")

(provide export-site)

(define (write-bytes! path b)
  (make-directory* (path-only path))
  (with-output-to-file path (λ () (write-bytes b)) #:exists 'replace))

(define (copy-tree! src dst)
  (when (directory-exists? src)
    (make-directory* dst)
    (for ([p (in-list (directory-list src))])
      (define s (build-path src p))
      (define d (build-path dst p))
      (if (directory-exists? s)
          (copy-tree! s d)
          (copy-file s d #t)))))

(define (export-site #:data-dir [data-dir "data"]
                     #:out [out "site"]
                     #:domain [domain "pitboard.jrtx.site"]
                     #:base-url [base-url "https://pitboard.jrtx.site"]
                     #:assets-dir [assets-dir "assets"])
  (define ctx (site-ctx domain base-url (current-seconds)))
  (define dates (list-dates data-dir))
  (define latest (and (pair? dates) (load-digest data-dir (car dates))))
  (define count 0)
  (define (put rel b) (write-bytes! (build-path out rel) b) (set! count (add1 count)))

  ;; pages
  (put "index.html"
       (if latest
           (render-index-page ctx latest)
           (render-empty-page ctx)))
  (put "archive.html"
       (render-archive-page
        ctx
        (for/list ([d (in-list dates)])
          (define dg (load-digest data-dir d))
          (define clusters (if dg (hash-ref dg 'clusters '()) '()))
          (list d (length clusters)
                (if (null? clusters) "" (v (hash-ref (car clusters) 'title "")))))))
  (put "about.html" (render-about-page ctx))
  (put "404.html" (render-not-found ctx))
  (for ([d (in-list dates)])
    (define dg (load-digest data-dir d))
    (when dg
      (put (string-append "d/" d ".html") (render-index-page ctx dg))
      (put (string-append "api/v1/digest/" d ".json") (jsexpr->bytes dg))
      (put (string-append "daily/" d ".md") (render-daily-md ctx dg))))
  ;; feeds & api
  (when latest
    (put "rss.xml" (render-rss-xml ctx latest))
    (put "api/v1/latest.json" (jsexpr->bytes latest)))
  (put "llms.txt" (render-llms-txt ctx))
  ;; static assets (flat at site root, matching serve-time URLs) + cname
  (for ([f (in-list (list "styles.css" "app.js" "favicon.svg"))])
    (define src (build-path assets-dir f))
    (when (file-exists? src)
      (copy-file src (build-path out f) #t)
      (set! count (add1 count))))
  (put "CNAME" (string->bytes/utf-8 (string-append domain "\n")))
  count)
