#lang racket/base

(require rackunit
         racket/string
         racket/file
         racket/runtime-path
         json
         "../render.rkt"
         (only-in "../sources.rkt" normalize-watch-topics))

(define-runtime-path search-app-js "../../assets/app.js")

(define ctx (site-ctx "pitboard.jrtx.site" "https://pitboard.jrtx.site" 0
                      (λ () (hasheq "2026-10-13" 1))))

(define digest
  (hasheq 'date "2026-10-13"
          'mode "scored"
          'generated_at "2026-10-13T07:30:00Z"
          'clusters
          (list (hasheq 'id "hot:1"
                        'heat "7.3"
                        'labels '("new" "rising")
                        'domains 2
                        'title "Toyota & NIO expand solid-state battery pilot"
                        'summary "Both makers announced pilot lines."
                        'items
                        (list (hasheq 'id "n:1" 'kind "news" 'source "Ars" 'source_url "arstechnica.com"
                                      'title "Toyota battery pilot"
                                      'url "https://arstechnica.com/1?utm_source=rss"
                                      'summary "pilot" 'published_at "2026-10-13T06:00:00Z"
                                      'extra (hasheq 'weight 1.2))
                              (hasheq 'id "g:1" 'kind "github" 'source "GitHub" 'source_url "github.com"
                                      'title "owner/repo"
                                      'url "https://github.com/owner/repo"
                                      'summary "" 'published_at "2026-10-13T05:00:00Z"
                                      'extra (hasheq 'stars 1200 'language "C++"))))
                (hasheq 'id "hot:2" 'heat "2.0" 'labels '() 'domains 1
                        'title "Second story <with> markup"
                        'summary ""
                        'items (list (hasheq 'id "n:2" 'kind "paper" 'source "arXiv" 'source_url "arxiv.org"
                                             'title "paper title" 'url "http://arxiv.org/abs/x"
                                             'summary "s" 'published_at 'null 'extra (hasheq)))))
          'sources '()))

(define page (bytes->string/utf-8 (render-index-page ctx digest)))

(test-case "index page"
  (check-true (string-contains? page "2026年10月13日"))
  (check-true (string-contains? page "Toyota &amp; NIO expand solid-state battery pilot"))
  (check-true (string-contains? page "chip-new"))
  (check-true (string-contains? page "个独立来源"))
  (check-true (string-contains? page "★1200"))
  (check-true (string-contains? page "Second story &lt;with&gt; markup")))

(test-case "scored mode hides llm chip"
  ;; "LLM 增强" chip must NOT appear when mode is scored
  (check-false (string-contains? page "LLM 增强")))

(test-case "archive + about + 404 + empty"
  (check-true (string-contains?
               (bytes->string/utf-8
                (render-archive-page ctx '(("2026-10-13" 2 "Top story"))))
               "/d/2026-10-13"))
  (check-true (string-contains? (bytes->string/utf-8 (render-about-page ctx)) "自托管"))
  (check-true (string-contains? (bytes->string/utf-8 (render-not-found ctx)) "404"))
  (check-true (string-contains? (bytes->string/utf-8 (render-empty-page ctx)) "fetch")))

(test-case "rss"
  (define rss (bytes->string/utf-8 (render-rss-xml ctx digest)))
  (check-true (string-contains? rss "<rss"))
  (check-true (string-contains? rss "Toyota &amp; NIO expand solid-state battery pilot")))

(test-case "daily markdown"
  (define md (bytes->string/utf-8 (render-daily-md ctx digest)))
  (check-true (string-contains? md "# pitboard 日报 · 2026-10-13"))
  (check-true (string-contains? md "## 1. Toyota & NIO expand solid-state battery pilot"))
  (check-true (string-contains? md "https://github.com/owner/repo")))

(test-case "llms.txt"
  (define t (bytes->string/utf-8 (render-llms-txt ctx)))
  (check-true (string-contains? t "/api/v1/latest.json")))

(test-case "per-source quota counts equal strings, not eq ones"
  ;; regression guard: counters must be equal-based hashes — string
  ;; instances parsed from JSON are never eq? to each other
  (define (mk i)
    (hasheq 'id (format "x:~a" i) 'kind "news" 'source "AUTOSAR 官方"
            'source_url (string-append "www.autosar" ".org")  ; fresh instance
            'title (format "AUTOSAR news number ~a" i) 'url (format "https://a.org/~a" i)
            'summary "" 'published_at "2026-10-13T00:00:00Z" 'extra (hasheq)))
  (define clusters
    (for/list ([i (in-range 6)])
      (hasheq 'id (format "hot:~a" i) 'heat "9.0" 'labels '() 'domains 1
              'title (format "AUTOSAR news number ~a" i) 'summary ""
              'items (list (mk i)))))
  (define kept (front-page-quota clusters 30 2 6))
  (check-equal? (length kept) 2))

;; ---- template leakage sweep -------------------------------------------------
;; Regression guard for the "plain quote around a template" family:
;; ',x inside '(...) never evaluates, and the serializer emits
;; <unquote>&x;</unquote> — seen live as &term; / &rows; / ~a on topic
;; pages and <unquote><format> on weekly pages. Every render entry
;; point must be free of unresolved template artifacts.

(define known-entities '("&amp;" "&lt;" "&gt;" "&quot;" "&apos;"))
(define leak-px #px"<unquote|~[asv]|&[a-zA-Z][a-zA-Z0-9]+;")

(define (check-no-leaks label b)
  (define out (bytes->string/utf-8 b))
  (define leaks
    (for/list ([m (in-list (regexp-match* leak-px out))]
               #:unless (member m known-entities))
      m))
  (check-equal? leaks '() (format "~a leaked template artifacts" label)))

(define topic-item
  (hasheq 'id "n:9" 'kind "news" 'source "盖世汽车" 'source_url "auto.gasgoo.com"
          'title "上海出台汽车消费新政"
          'url "https://auto.gasgoo.com/news/202610/14X.shtml"
          'summary "新政鼓励置换" 'published_at "2026-10-14T02:00:00Z"
          'extra (hasheq 'weight 0.95)))

(test-case "template leakage sweep — every page type"
  (define rows (list (cons "2026-10-13" topic-item)
                     (cons "2026-10-14" topic-item)))
  (check-no-leaks "index" (render-index-page ctx digest))
  (check-no-leaks "archive" (render-archive-page ctx '(("2026-10-13" 2 "Top story"))))
  (check-no-leaks "about" (render-about-page ctx))
  (check-no-leaks "404" (render-not-found ctx))
  (check-no-leaks "empty" (render-empty-page ctx))
  (check-no-leaks "rss" (render-rss-xml ctx digest))
  (check-no-leaks "daily-md" (render-daily-md ctx digest))
  (check-no-leaks "llms.txt" (render-llms-txt ctx))
  (for ([term (list "UDS" "SOME/IP" "信息安全")])
    (check-no-leaks (format "topic ~a" term) (render-topic-page ctx term rows)))
  (check-no-leaks "topics-index"
                  (render-topics-index ctx
                    (list (cons "方向" (list (cons "AUTOSAR" 10) (cons "SOME/IP" 3)))
                          (cons "形态" (list (cons "芯片" 0))))))
  (check-no-leaks "period-page"
                  (render-period-page ctx "周报"
                    (list (list "2026-10-13" "标题标题标题" "https://example.com/a" "12.0"))))
  (check-no-leaks "periods-index"
                  (render-periods-index ctx "周报" "/weekly" (list (list "2026-W42" 5))))
  (check-no-leaks "og-svg" (render-og-svg digest))
  (check-no-leaks "bookmarks" (render-bookmarks-page ctx))
  (check-no-leaks "search" (render-search-page ctx))
  (for ([admin (list #t #f)])
    (check-no-leaks (format "admin(~a)" admin)
                    (render-admin-page ctx
                      (list (hasheq 'ok #t 'name "盖世汽车" 'count 12)
                            (hasheq 'ok #f 'name "arXiv" 'count 0 'message "HTTP 429"))
                      (hasheq) admin))))

(test-case "i18n keys present on chrome"
  (define about-txt (bytes->string/utf-8 (render-about-page ctx)))
  (check-true (string-contains? about-txt "data-i18n"))
  (check-true (string-contains? (bytes->string/utf-8 (render-index-page ctx digest)) "data-i18n"))
  (check-true (string-contains? (bytes->string/utf-8 (render-topic-page ctx "UDS" '())) "data-i18n")))

(test-case "topic page hero renders real values"
  (define txt (bytes->string/utf-8
               (render-topic-page ctx "UDS" (list (cons "2026-10-13" topic-item)))))
  (check-true (string-contains? txt "条相关内容 · 跨期归档追踪"))
  (check-true (string-contains? txt "上海出台汽车消费新政"))
  (check-false (string-contains? txt "&term;"))
  (check-false (string-contains? txt "&rows;")))

;; ---- topic matching: word boundaries ----------------------------------------
;; Regression: naive substring matching made English "adds"/"odds"/"RDDs"
;; hit topic DDS — a BMW "adds new iX3" headline landed on the DDS page.

(test-case "topic-match? uses word boundaries for ascii terms"
  (check-false (topic-match? "DDS" "BMW adds new iX3 M60 xDrive with 603 hp"))
  (check-false (topic-match? "DDS" "Spark RDDs explained"))
  (check-false (topic-match? "SOA" "soaring battery prices"))
  (check-true (topic-match? "DDS" "DDS middleware standard update"))
  (check-true (topic-match? "DDS" "DDS-based communication"))
  (check-true (topic-match? "SOME/IP" "SOME/IP service discovery"))
  (check-true (topic-match? "UDS" "UDS diagnostic services"))
  (check-true (topic-match? "AUTOSAR" "AUTOSAR CAPI release"))
  (check-true (topic-match? "Robotaxi" "Tesla robotaxis speed in school zones"))
  (check-true (topic-match? "UDS" "UDS诊断服务升级"))
  (check-true (topic-match? "DDS" "DDS中间件标准发布"))
  (check-false (topic-match? "DDS" "OpenDDS 1.4 released")))

(test-case "topic-match? keeps substring for cjk terms"
  (check-true (topic-match? "智能驾驶" "小鹏城市智能驾驶开城"))
  (check-true (topic-match? "比亚迪" "比亚迪月度出口创新高"))
  (check-false (topic-match? "比亚迪" "丰田超越大众")))

(test-case "collect-topic-items filters through boundary matching"
  (define dir (build-path (find-system-path 'temp-dir)
                          (format "pb-topics-~a" (current-inexact-milliseconds))))
  (make-directory* dir)
  (define bmw (hasheq 'id "n:10" 'kind "news" 'source "Electrek" 'source_url "electrek.co"
                      'title "BMW adds new iX3 M60 xDrive"
                      'url "https://electrek.co/1" 'summary "603 hp"
                      'published_at "2026-10-14T00:00:00Z" 'extra (hasheq)))
  (define dds (hasheq 'id "n:11" 'kind "news" 'source "SDV" 'source_url "sdv.example"
                      'title "DDS gateway standard ratified"
                      'url "https://example.org/dds" 'summary "middleware"
                      'published_at "2026-10-14T00:00:00Z" 'extra (hasheq)))
  (define dg
    (hasheq 'date "2026-10-14" 'mode "scored" 'generated_at "2026-10-14T07:30:00Z"
            'clusters
            (list (hasheq 'id "hot:9" 'heat "3" 'labels '() 'domains 1
                          'title "BMW adds new iX3 M60 xDrive" 'summary ""
                          'items (list bmw))
                  (hasheq 'id "hot:10" 'heat "3" 'labels '() 'domains 1
                          'title "DDS gateway standard ratified" 'summary ""
                          'items (list dds)))
            'sources '()))
  (with-output-to-file (build-path dir "2026-10-14.json")
    (λ () (write-json dg)))
  (define hits (collect-topic-items dir "DDS"))
  (check-equal? (length hits) 1)
  (check-equal? (v (hash-ref (cdr (car hits)) 'title "")) "DDS gateway standard ratified"))

;; ---- topic aliases: CJK topics must catch English press vocabulary ----------

(test-case "collect-topic-items matches through aliases"
  (define dir (build-path (find-system-path 'temp-dir)
                          (format "pb-alias-~a" (current-inexact-milliseconds))))
  (make-directory* dir)
  (define item
    (hasheq 'id "n:20" 'kind "news" 'source "Electrek" 'source_url "electrek.co"
            'title "BMW shows brake-by-wire future"
            'url "https://electrek.co/2" 'summary "x-by-wire chassis"
            'published_at "2026-10-14T00:00:00Z" 'extra (hasheq)))
  (define dg
    (hasheq 'date "2026-10-14" 'mode "scored" 'generated_at "t"
            'clusters
            (list (hasheq 'id "hot:11" 'heat "3" 'labels '() 'domains 1
                          'title "BMW brake-by-wire" 'summary ""
                          'items (list item)))
            'sources '()))
  (with-output-to-file (build-path dir "2026-10-14.json")
    (λ () (write-json dg)))
  (define hits (collect-topic-items dir "线控底盘"
                                    (list "线控制动" "by-wire" "x-by-wire")))
  (check-equal? (length hits) 1)
  ;; 主词不带别名时抓不到英文——这正是别名机制存在的理由
  (check-equal? (length (collect-topic-items dir "线控底盘")) 0))

(test-case "normalize-watch-topics accepts dict entries"
  (define groups
    (normalize-watch-topics
     (hasheq "方向"
             (list "AUTOSAR"
                   (hasheq 'term "线控底盘"
                           'aka (list "by-wire" "线控制动"))))))
  (check-equal? (length groups) 1)
  (check-equal? (car (car groups)) "方向")
  (define entries (cdr (car groups)))
  (check-equal? (car (car entries)) "AUTOSAR")
  (check-equal? (cdr (car entries)) '())
  (check-equal? (car (cadr entries)) "线控底盘")
  (check-equal? (cdr (cadr entries)) (list "by-wire" "线控制动")))

(test-case "bookmarks/search share the main nav shell"
  ;; regression guard for the hand-written site-tpl era: those static
  ;; copies missed every nav/head change (书签 entry, lang-btn,
  ;; theme-btn, app.js, analytics). Both pages must carry all of it.
  (define (has? b needle) (string-contains? (bytes->string/utf-8 b) needle))
  (for ([p (list (render-bookmarks-page ctx) (render-search-page ctx))])
    (check-true (has? p "lang-btn") "missing EN switch button")
    (check-true (has? p "theme-btn") "missing theme button")
    (check-true (has? p "nav.bookmarks") "missing 书签 nav entry")
    (check-true (has? p "/app.js") "missing app.js")
    (check-true (has? p "hm.baidu.com/hm.js") "missing analytics snippet"))
  (check-true (has? (render-bookmarks-page ctx) "导出 JSON"))
  (check-true (has? (render-search-page ctx) "搜索标题关键词")))

(test-case "search page ships loading/error/retry/no-match states"
  ;; issue #1: an unloaded, HTTP-failing or invalid search index must be
  ;; visible and recoverable — never a silent noop. States are static
  ;; data-i18n elements so the language switch reaches all of them.
  (define page (render-search-page ctx))
  (define has? (λ (b needle) (string-contains? (bytes->string/utf-8 b) needle)))
  (for ([id (list "search-loading" "search-error" "search-retry" "search-empty")])
    (check-true (has? page id) (format "missing state element ~a" id)))
  (for ([k (list "search.loading" "search.error" "search.retry" "search.empty")])
    (check-true (has? page (format "data-i18n=\"~a\"" k))
                (format "missing i18n key ~a" k)))
  (check-true (has? page "正在加载搜索索引"))
  (check-true (has? page "搜索索引加载失败"))
  (check-true (has? page "没有匹配内容"))
  (check-true (has? page "站内搜索需要启用 JavaScript"))
  ;; failure copy must be distinct from no-match copy — extracted from the
  ;; rendered page, not from these literals
  (define (para-copy b id)
    (cadr (regexp-match (format "id=\"~a\"[^>]*>([^<]+)</p>" id)
                        (bytes->string/utf-8 b))))
  (check-false (equal? (para-copy page "search-error")
                       (para-copy page "search-empty"))
               "zh failure and no-match copy must differ"))

(test-case "search asset guards against failing/invalid index"
  ;; static drift guard on assets/app.js: status check, catch branch,
  ;; retry wiring and the EN state vocabulary must all stay present.
  (define js (file->string search-app-js))
  (define (has? needle) (string-contains? js needle))
  (check-true (has? "search-index.json"))
  (check-true (has? "r.ok") "missing HTTP status check")
  (check-true (has? ".catch(") "missing fetch error branch")
  (check-true (has? "search-retry"))
  (check-true (has? "\"search.loading\""))
  (check-true (has? "\"search.error\""))
  (check-true (has? "\"search.retry\""))
  (check-true (has? "\"search.empty\""))
  (check-true (has? "Array.isArray(j)") "missing index shape validation")
  (define (dict-value key)
    (cadr (regexp-match (format "\"~a\": \"([^\"]+)\"" key) js)))
  (check-false (equal? (dict-value "search.error") (dict-value "search.empty"))
               "en failure and no-match copy must differ"))
