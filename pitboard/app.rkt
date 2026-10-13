#lang racket/base

;; The web application: one Racket web-server process serving pages,
;; JSON API, RSS, markdown dailies and the SSE edition stream.

(require web-server/servlet
         web-server/servlet-env
         web-server/dispatch
         web-server/http/response-structs
         web-server/http/response
         web-server/http/request-structs
         web-server/http/bindings
         racket/string
         racket/format
         racket/list
         racket/file
         json
         "store.rkt"
         "item.rkt"
         "render.rkt"
         server-sent-events
         (only-in "render.rkt" render-admin-page)
         "util.rkt")

;; (editions-of dir) → hash: date → 期数 (1-based, ascending by date)

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

(define (ingest-form req)
  (define (get key)
    (with-handlers ([exn:fail? (λ (_) 'null)])
      (extract-binding/single key (request-bindings req))))
  (hasheq 'title (get #"title")
          'url (get #"url")
          'summary (get #"summary")))

(define (start-server #:port [port 8090]
                      #:data-dir [data-dir "data"]
                      #:assets-dir [assets-dir "assets"]
                      #:topics [topics #f])
  ;; edition numbers grow over time: oldest archive = 第 1 期
  (define (editions-of dir)
    (for/hash ([d (in-list (reverse (list-dates dir)))]
               [i (in-naturals 1)])
      (values d i)))
  (define ctx (site-ctx "pitboard.jrtx.site" "" (current-seconds)
                        (λ () (editions-of data-dir))))
  (define topic-groups
    (or topics
        (list (cons "方向" (list "AUTOSAR" "DDS" "SOME/IP" "SOA" "信息安全"
                                 "功能安全" "安全刷写" "UDS" "车载以太网"
                                 "域控" "智能驾驶" "Robotaxi"))
              (cons "公司" (list "比亚迪" "华为车" "蔚来" "小鹏" "理想"
                                 "特斯拉" "地平线"))
              (cons "形态" (list "芯片" "开源" "论文" "召回" "政策")))))
  (define topic-terms
    (remove-duplicates (flatten (map cdr topic-groups))))
  (define (topics-index)
    (for/list ([g (in-list topic-groups)])
      (cons (car g)
            (for/list ([t (in-list (cdr g))])
              (cons t (length (collect-topic-items data-dir t)))))))
  (define hub (make-hub))

  ;; Directory contents (names + per-file mtimes) as a change
  ;; fingerprint; directory mtime alone proved unreliable on APFS.
  (define (dir-fingerprint dir)
    (with-handlers ([exn:fail? (λ (_) "")])
      (string-append*
       (for/list ([p (in-list (directory-list dir))])
         (define mt
           (with-handlers ([exn:fail? (λ (_) 0)])
             (file-or-directory-modify-seconds (build-path dir p))))
         (format "~a:~a;" (path->string p) mt)))))

  (define (latest-date-in dir)
    (with-handlers ([exn:fail? (λ (_) #f)])
      (define ds
        (for/list ([p (in-list (directory-list dir))]
                   #:when (regexp-match? #px"\\.json$" (path->string p)))
          (regexp-replace #px"\\.json$" (path->string p) "")))
      (and (pair? ds) (car (sort ds string>?)))))

  ;; Watch the data dir; a new edition date becomes an "edition" event.
  (define fp-box (box (dir-fingerprint data-dir)))
  (hub-watch! hub 5 "edition"
              (λ ()
                (define fp (dir-fingerprint data-dir))
                (cond
                  [(equal? fp (unbox fp-box)) #f]
                  [else
                   (set-box! fp-box fp)
                   (define d (latest-date-in data-dir))
                   (and d (jsexpr->string (hasheq 'date d)))])))

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
  (define (topics-h req)
    (resp-html (render-topics-index ctx (topics-index))))
  (define (topic-h req slug)
    (define term
      (for/first ([t (in-list topic-terms)]
                  #:when (equal? (topic-slug t) (string-trim slug "/")))
        t))
    (if term
        (resp-html
         (render-topic-page ctx term (collect-topic-items data-dir term)))
        (resp-404 ctx)))
  (define (ingest-h req)
    (define token (getenv "PITBOARD_INGEST_TOKEN"))
    (define provided
      (for/first ([h (in-list (request-headers/raw req))]
                  #:when (equal? (header-field h) #"x-pitboard-token"))
        (bytes->string/utf-8 (header-value h))))
    (cond [(not token)
           (response/full 403 #"Forbidden" (current-seconds)
                          (bytes->immutable-bytes #"text/plain; charset=utf-8")
                          '() (list (string->bytes/utf-8 "ingest disabled: set PITBOARD_INGEST_TOKEN\n")))]
          [(not (equal? provided token))
           (response/full 401 #"Unauthorized" (current-seconds)
                          (bytes->immutable-bytes #"text/plain; charset=utf-8")
                          '() (list (string->bytes/utf-8 "bad token\n")))]
          [else
           (define title (v (hash-ref (ingest-form req) 'title 'null)))
           (define url (v (hash-ref (ingest-form req) 'url 'null)))
           (cond [(non-empty-string? title)
                  (append-ingested!
                   data-dir
                   (hasheq 'kind "news" 'source "推送" 'source_url "ingest"
                           'title title 'url url 'summary "" 'published_at 'null
                           'extra (hasheq)))
                  (resp-text (string->bytes/utf-8 "ingested\n"))]
                 [else
                  (resp-404 ctx)])]))
  (define (events-h req)
    (response/output
     (λ (out) (hub-stream hub out))
     #:mime-type (bytes->immutable-bytes #"text/event-stream")
     #:headers
     (list (header #"Cache-Control" #"no-cache")
           (header #"X-Accel-Buffering" #"no"))))

  (define (admin-h req)
    (define health (load-health data-dir))
    (define dg (latest-digest data-dir))
    (define admin? (equal? (getenv "PITBOARD_ADMIN") "1"))
    (resp-html
     (render-admin-page
      ctx
      (if dg (hash-ref dg 'sources '()) '())
      health
      admin?)))
  (define-values (dispatch url)
    (dispatch-rules
     [("") index-h]
     [("admin") admin-h]
     [("ingest") ingest-h]
     [("d" (string-arg)) date-h]
     [("archive") archive-h]
     [("about") about-h]
     [("rss.xml") rss-h]
     [("llms.txt") llms-h]
     [("healthz") health-h]
     [("api" "events") events-h]
     [("topics") topics-h]
     [("topic" (string-arg)) topic-h]
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
                 #rx"^/($|d/.+|topics|topic/.+|admin|ingest|archive|about|rss\\.xml|llms\\.txt|healthz|api/.+|daily/.+)"
                 #:extra-files-paths
                 (list (path->complete-path assets-dir))
                 #:banner? #f))
