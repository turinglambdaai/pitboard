#lang racket/base

(require rackunit
         racket/string
         json
         "../render.rkt")

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
  (check-true (string-contains? page "2 个独立来源"))
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
  (for ([admin (list #t #f)])
    (check-no-leaks (format "admin(~a)" admin)
                    (render-admin-page ctx
                      (list (hasheq 'ok #t 'name "盖世汽车" 'count 12)
                            (hasheq 'ok #f 'name "arXiv" 'count 0 'message "HTTP 429"))
                      (hasheq) admin))))

(test-case "topic page hero renders real values"
  (define txt (bytes->string/utf-8
               (render-topic-page ctx "UDS" (list (cons "2026-10-13" topic-item)))))
  (check-true (string-contains? txt "1 条相关内容 · 跨期归档追踪"))
  (check-true (string-contains? txt "上海出台汽车消费新政"))
  (check-false (string-contains? txt "&term;"))
  (check-false (string-contains? txt "&rows;")))
