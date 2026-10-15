#lang racket/base

;; Static export: renders the whole site (Pages mirror) from data/.

(require racket/file
         racket/path
         racket/string
         racket/list
         racket/format
         json
         "util.rkt"
         (only-in "store.rkt" list-dates load-digest period-rows monday-key month-key)
         (only-in "sources.rkt" default-watch-topics)
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
                     #:assets-dir [assets-dir "assets"]
                     #:topics [topics #f])
  (define dates (list-dates data-dir))
  ;; topics: (list (cons group (list (cons term akas) …))) — see sources.rkt
  (define topic-groups (or topics default-watch-topics))
  (define topic-pages
    (append*
     (for/list ([g (in-list topic-groups)])
       (for/list ([t (in-list (cdr g))])
         (list (topic-slug (car t)) (car t)
               (collect-topic-items data-dir (car t) (cdr t)))))))
  (define editions
    (for/hash ([d (in-list (reverse dates))]
               [i (in-naturals 1)])
      (values d i)))
  (define ctx (site-ctx domain base-url (current-seconds) (λ () editions)))
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
  (put "topics/index.html"
       (render-topics-index
        ctx
        (for/list ([g (in-list topic-groups)])
          (cons (car g)
                (for/list ([t (in-list (cdr g))])
                  (cons (car t)
                        (length (collect-topic-items data-dir (car t) (cdr t)))))))))
  (for ([tp (in-list topic-pages)])
    (put (string-append "topic/" (car tp) "/index.html")
         (render-topic-page ctx (cadr tp) (caddr tp))))
  ;; weekly / monthly compilations
  (define (period-pages key-fn kind-label base)
    (define groups
      (for/fold ([g (hash)]) ([d (in-list dates)])
        (hash-set g (key-fn d) (cons d (hash-ref g (key-fn d) '())))))
    (define keys (sort (hash-keys groups) string>?))
    (put (string-append base "/index.html")
         (render-periods-index
          ctx kind-label base
          (for/list ([k (in-list keys)])
            (list k (length (period-rows data-dir (reverse (hash-ref groups k))))))))
    (for ([k (in-list keys)])
      (put (string-append base "/" k "/index.html")
           (render-period-page
            ctx
            (string-append kind-label " · " k)
            (period-rows data-dir (reverse (hash-ref groups k)))))))
  (period-pages monday-key "周报" "weekly")
  (period-pages month-key "月报" "monthly")
  ;; bookmarks/search rendered through the shared page shell — the old
  ;; hand-written site-tpl copies drifted out of sync with every nav
  ;; change (missing 书签/lang-btn/theme-btn/app.js for months).
  (put "bookmarks.html" (render-bookmarks-page ctx))
  (put "search.html" (render-search-page ctx))
  ;; agent skill (SKILL.md), served for direct download by user agents
  (define skill-dir "skill")
  (when (directory-exists? skill-dir)
    (for ([d (in-list (directory-list skill-dir))])
      (define src (build-path skill-dir d))
      (when (directory-exists? src)
        (for ([f (in-list (directory-list src))])
          (put (build-path "skill" d f) (file->bytes (build-path src f)))))))
  ;; og share cards
  (when latest
    (put (string-append "og/" (v (hash-ref latest 'date "")) ".svg")
         (render-og-svg latest)))
  ;; full-text search index (titles only, client-side filtering)
  (put "search-index.json"
       (jsexpr->bytes
        (for/list ([d (in-list dates)])
          (define dg (load-digest data-dir d))
          (for/list ([c (in-list (if dg (hash-ref dg 'clusters '()) '()))])
            (hasheq 'd d
                    't (hash-ref c 'title "")
                    'u (if (null? (hash-ref c 'items '()))
                           ""
                           (hash-ref (car (hash-ref c 'items '())) 'url ""))
                    'k (if (null? (hash-ref c 'items '()))
                           "news"
                           (hash-ref (car (hash-ref c 'items '())) 'kind "news"))
                    'h (hash-ref c 'heat "0"))))))
  (put "openapi.json"
       (string->bytes/utf-8
        (string-append
         "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"pitboard API\",\"version\":\"0.1.0\","
         "\"description\":\"汽车行业每日热点日报 · 只读 API\"},"
         "\"servers\":[{\"url\":\"" base-url "\"}],"
         "\"paths\":{"
         "\"/rss.xml\":{\"get\":{\"summary\":\"RSS 订阅\"}},"
         "\"/api/v1/latest.json\":{\"get\":{\"summary\":\"最新一期完整 JSON\"}},"
         "\"/api/v1/digest/{date}.json\":{\"get\":{\"summary\":\"指定日期 JSON\"}},"
         "\"/daily/{date}.md\":{\"get\":{\"summary\":\"Markdown 日报\"}},"
         "\"/topics/\":{\"get\":{\"summary\":\"话题雷达索引\"}},"
         "\"/topic/{slug}/\":{\"get\":{\"summary\":\"话题跨期追踪\"}},"
         "\"/llms.txt\":{\"get\":{\"summary\":\"Agent 索引\"}},"
         "\"/healthz\":{\"get\":{\"summary\":\"健康检查\"}}}}")))
  ;; static assets (flat at site root, matching serve-time URLs) + cname
  (for ([f (in-list (list "styles.css" "app.js" "favicon.svg"))])
    (define src (build-path assets-dir f))
    (when (file-exists? src)
      (copy-file src (build-path out f) #t)
      (set! count (add1 count))))
  (put "CNAME" (string->bytes/utf-8 (string-append domain "\n")))
  count)
