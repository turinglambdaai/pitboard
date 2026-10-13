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
