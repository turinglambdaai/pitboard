#lang racket/base

;; HTML / RSS / Markdown / llms.txt rendering.  Pure: jsexpr in, bytes out.

(require xml
         racket/string
         racket/list
         racket/format
         racket/match
         racket/date
         racket/port
         "util.rkt")

(provide (struct-out site-ctx)
         v
         xexpr->html-bytes
         render-index-page
         render-archive-page
         render-about-page
         render-empty-page
         render-not-found
         render-rss-xml
         render-daily-md
         render-llms-txt)

(struct site-ctx (domain base-url generated-at) #:transparent)

;; ---- plumbing -------------------------------------------------------------

(define (xexpr->html-bytes x)
  (string->bytes/utf-8
   (string-append "<!DOCTYPE html>\n"
                  (with-output-to-string
                    (λ () (display-xml/content (xexpr->xml x)))))))

(define (v s)
  ;; jsexpr string-or-null → display string
  (if (eq? s 'null) "" (if (string? s) s (format "~a" s))))

(define (first-n l n)
  (take l (min (length l) n)))

(define (date-cn ymd)
  (define m (regexp-match #px"^(\\d{4})-(\\d{2})-(\\d{2})$" ymd))
  (if m
      (format "~a年~a月~a日" (list-ref m 1)
              (~r (string->number (list-ref m 2)))
              (~r (string->number (list-ref m 3))))
      ymd))

(define kind-label
  (match-lambda
    ["github" "开源"]
    ["paper" "论文"]
    [_ "资讯"]))

(define (label-chip* l)
  (cond [(equal? l "new") '(span ((class "chip chip-new")) "新")]
        [(equal? l "rising") '(span ((class "chip chip-rising")) "↑ 上升")]
        [else (list 'span '((class "chip")) l)]))

;; ---- shell ------------------------------------------------------------------

(define (page-shell ctx title active body)
  `(html ((lang "zh"))
     (head
      (meta ((charset "utf-8")))
      (meta ((name "viewport") (content "width=device-width, initial-scale=1")))
      (title ,title)
      (meta ((name "description")
             (content "pitboard — 汽车行业每日热点：开源项目、行业资讯、前沿论文，一天一块板。")))
      (link ((rel "stylesheet") (href "/styles.css")))
      (link ((rel "alternate") (type "application/rss+xml")
             (title "pitboard RSS") (href "/rss.xml")))
      (link ((rel "icon") (href "/favicon.svg") (type "image/svg+xml")))
      (script ((defer "defer") (src "/app.js"))))
     (body
      (nav ((class "nav"))
           (div ((class "nav-inner"))
                (a ((class "brand") (href "/")) "⏱ pitboard")
                (div ((class "nav-links"))
                     ,@(for/list ([p (in-list '(("index" "/" "今日")
                                                ("archive" "/archive" "归档")
                                                ("about" "/about" "关于")
                                                ("rss" "/rss.xml" "RSS")))])
                         `(a ((href ,(cadr p))
                              ,@(if (equal? (car p) active) '((class "active")) '()))
                            ,(caddr p)))
                     (button ((class "theme-btn") (id "theme-btn")
                              (type "button") (aria-label "切换主题")) "◐"))))
      (main ,@body)
      (footer ((class "footer"))
              (div "pitboard — 汽车行业每日热点 · Racket 全栈自托管")
              (div ((class "muted"))
                   "设计灵感致谢 AIHOT · 本站由开源管线每日自动生成 · "
                   (a ((href "/llms.txt")) "llms.txt"))))))

;; ---- cluster card -----------------------------------------------------------

(define (source-chip it)
  (define extra (hash-ref it 'extra (hasheq)))
  (define stars (hash-ref extra 'stars #f))
  `(a ((class "chip chip-src") (href ,(v (hash-ref it 'url ""))) (target "_blank") (rel "noopener"))
      ,(kind-label (hash-ref it 'kind 'news))
      " · " ,(v (hash-ref it 'source_url "unknown"))
      ,@(if stars (list (span-stars stars)) '())))

(define (span-stars n)
  (list 'span '((class "stars")) (format " ★~a" n)))

(define (cluster-card h idx)
  `(article ((class "card"))
     (div ((class "card-head"))
          (span ((class "rank")) ,(format "#~a" (add1 idx)))
          (span ((class "heat")) "🔥 " ,(v (hash-ref h 'heat "0")))
          ,@(map label-chip* (map ~a (hash-ref h 'labels '())))
          ,@(if (> (hash-ref h 'domains 0) 1)
                (list (list 'span '((class "chip"))
                            (format "~a 个独立来源" (hash-ref h 'domains 0))))
                '()))
     (h2 ((class "card-title"))
         (a ((href ,(first-item-url h)) (target "_blank") (rel "noopener"))
            ,(v (hash-ref h 'title ""))))
     ,@(let ([s (v (hash-ref h 'summary ""))])
         (if (non-empty-string? s) (list (list 'p '((class "card-summary")) s)) '()))
     (div ((class "chips"))
          ,@(map source-chip (take (hash-ref h 'items '())
                                   (min 10 (length (hash-ref h 'items '()))))))))

(define (first-item-url h)
  (define items (hash-ref h 'items '()))
  (if (null? items) "#" (v (hash-ref (car items) 'url "#"))))

;; ---- pages -------------------------------------------------------------------

(define (hero-digest digest)
  (define clusters (hash-ref digest 'clusters '()))
  (define items (for/sum ([c (in-list clusters)]) (length (hash-ref c 'items '()))))
  (define mode (hash-ref digest 'mode "scored"))
  `(section ((class "hero"))
     (h1 "今日热点")
     (p ((class "hero-date")) ,(date-cn (v (hash-ref digest 'date "")))
        ,@(if (equal? mode "llm") '((span ((class "chip chip-llm")) "LLM 增强")) '()))
     (div ((class "hero-stats"))
          (span ,(format "~a 个热点" (length clusters)))
          (span " · ")
          (span ,(format "~a 条原始条目" items))
          (span " · ")
          (span ,(format "~a 个信源" (length (hash-ref digest 'sources '())))))))

(define (render-index-page ctx digest)
  (define clusters (hash-ref digest 'clusters '()))
  (xexpr->html-bytes
   (page-shell ctx "pitboard — 汽车行业每日热点" "index"
               (list (hero-digest digest)
                     (if (null? clusters)
                         '(p ((class "empty")) "今天还没有足够的热点。")
                         `(div ((class "cards"))
                               ,@(for/list ([c (in-list clusters)]
                                            [i (in-naturals)]
                                            #:when (< i 30))
                                   (cluster-card c i))))))))

(define (render-archive-page ctx digests)
  ;; digests: list of (list date cluster-count top-title)
  (xexpr->html-bytes
   (page-shell ctx "归档 — pitboard" "archive"
               (list
                '(section ((class "hero")) (h1 "往期归档"))
                `(ul ((class "archive-list"))
                     ,@(for/list ([d (in-list digests)])
                         `(li
                           (a ((href ,(format "/d/~a" (car d))))
                              (span ((class "arch-date")) ,(date-cn (car d)))
                              (span ((class "arch-meta"))
                                    ,(format "~a 个热点" (cadr d))))
                           (span ((class "arch-title")) " " ,(caddr d)))))))))

(define (render-about-page ctx)
  (xexpr->html-bytes
   (page-shell ctx "关于 — pitboard" "about"
               (list
                '(section ((class "hero")) (h1 "关于 pitboard"))
                '(div ((class "prose"))
                  (p "pitboard 是一张举给汽车行业从业者的「pit 板」：每天把开源项目、"
                     "行业资讯、前沿论文抓到一起，聚簇去重，按独立来源数与时间衰减算出热度，"
                     "把真正在发生的事顶到最上面。")
                  (h2 "它怎么工作")
                  (ul
                   (li (b "抓取") " — RSS 媒体源、GitHub 汽车话题仓库、arXiv 论文检索，全部免 key。")
                   (li (b "聚簇") " — 中英分词（CJK 二元语法）+ Jaccard 相似度，同一事件的多方报道并成一条。")
                   (li (b "热度") " — 独立来源越多越靠前，48 小时窗口内按新旧衰减；可选用 OpenAI 兼容 LLM 把头条翻译成中文摘要。")
                   (li (b "出刊") " — 每日定时生成一期刊物，写进 data/ 归档，站点与 API 同步刷新。"))
                  (h2 "给 Agent 的出口")
                  (ul
                   (li (code "/rss.xml") " — RSS 订阅")
                   (li (code "/api/v1/latest.json") " — 最新一期 JSON（" (code "/api/v1/digest/2026-10-13.json") " 按日期取）")
                   (li (code "/daily/&lt;date&gt;.md") " — Markdown 日报")
                   (li (code "/llms.txt") " — 站点索引")
                   (li (code "/api/events") " — SSE 出刊推送"))
                  (h2 "自托管")
                  (p "一个 Racket 进程，零外部依赖（无数据库）：" (br)
                     (code "raco pkg install --auto https://github.com/turinglambdaai/pitboard.git") (br)
                     (code "raco pitboard fetch && raco pitboard serve --port 8090"))
                  (h2 "致谢")
                  (p "设计灵感来自 " (a ((href "https://github.com/KKKKhazix/AIHOT")) "AIHOT")
                     " ——「把信源和精选标准换成你的，它就是你的行业热点站」。pitboard 是这句话在汽车行业、"
                     "Racket 技术栈上的回答。MIT 许可。"))))))

(define (render-empty-page ctx)
  (xexpr->html-bytes
   (page-shell ctx "pitboard — 汽车行业每日热点" "index"
               (list
                '(section ((class "hero"))
                   (h1 "还没有出刊")
                   (p ((class "hero-date")) "先跑一次抓取：")
                   (p (code "raco pitboard fetch")))))))

(define (render-not-found ctx)
  (xexpr->html-bytes
   (page-shell ctx "404 — pitboard" ""
               (list '(section ((class "hero"))
                              (h1 "404")
                              (p "这块板上没写东西。")
                              (p (a ((href "/")) "回今日热点")))))))

;; ---- rss / md / llms ----------------------------------------------------------

(define (rfc822 secs)
  (date->string (seconds->date secs #t) #t))

(define (render-rss-xml ctx digest)
  (define clusters (first-n (hash-ref digest 'clusters '()) 20))
  (define items
    (for/list ([c (in-list clusters)])
      (define first-item (car (hash-ref c 'items '())))
      (define pub (hash-ref first-item 'published_at 'null))
      `(item
        (title ,(v (hash-ref c 'title "")))
        (link ,(v (hash-ref first-item 'url "")))
        (guid ((isPermaLink "false")) ,(string-append "pitboard:" (v (hash-ref digest 'date "")) ":" (v (hash-ref c 'id ""))))
        (description ,(v (hash-ref c 'summary "")))
        ,@(if (string? pub)
              (list (list 'pubDate (rfc822 (or (parse-date-any pub) (current-seconds)))))
              '()))))
  (string->bytes/utf-8
   (string-append
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    (with-output-to-string
      (λ ()
        (display-xml/content
         (xexpr->xml
          `(rss ((version "2.0"))
             (channel
              (title "pitboard — 汽车行业每日热点")
              (link ,(site-ctx-base-url ctx))
              (description "开源项目 · 行业资讯 · 前沿论文，一天一块板")
              (language "zh")
              ,@items)))))))))

(define (render-daily-md ctx digest)
  (define clusters (hash-ref digest 'clusters '()))
  (string->bytes/utf-8
   (string-append*
    (list*
     (format "# pitboard 日报 · ~a\n\n" (v (hash-ref digest 'date "")))
     (format "> 自动生成 · ~a 个热点 · 模式 ~a · 生成于 ~a\n\n"
             (length clusters) (v (hash-ref digest 'mode "scored"))
             (v (hash-ref digest 'generated_at "")))
     (append*
      (for/list ([c (in-list clusters)]
                 [i (in-naturals)])
        (list
         (format "## ~a. ~a\n\n" (add1 i) (v (hash-ref c 'title "")))
         (format "热度 ~a · ~a 个独立来源 · 标签：~a\n\n"
                 (v (hash-ref c 'heat "0")) (hash-ref c 'domains 0)
                 (let ([ls (map ~a (hash-ref c 'labels '()))])
                   (if (null? ls) "无" (string-join ls "、"))))
         (let ([s (v (hash-ref c 'summary ""))])
           (if (non-empty-string? s) (string-append s "\n\n") ""))
         (string-append*
          (for/list ([it (in-list (first-n (hash-ref c 'items '()) 6))])
            (format "- [~a] [~a](~a)\n"
                    (v (hash-ref it 'source ""))
                    (v (hash-ref it 'title ""))
                    (v (hash-ref it 'url "")))))
         "\n")))))))

(define (render-llms-txt ctx)
  (string->bytes/utf-8
   (string-append
    "# pitboard\n\n"
    "> 汽车行业每日热点日报：开源项目、行业资讯、前沿论文，聚簇去重、按独立来源数算热度。"
    "Racket 全栈、单进程自托管、MIT 开源。\n\n"
    "## Pages\n\n"
    "- [今日热点](" (site-ctx-base-url ctx) "/): 最新一期行业热点榜\n"
    "- [归档](" (site-ctx-base-url ctx) "/archive): 往期所有刊物\n"
    "- [关于](" (site-ctx-base-url ctx) "/about): 产品说明与自托管指南\n\n"
    "## Machine-readable\n\n"
    "- " (site-ctx-base-url ctx) "/rss.xml — RSS 2.0 订阅\n"
    "- " (site-ctx-base-url ctx) "/api/v1/latest.json — 最新一期完整 JSON\n"
    "- " (site-ctx-base-url ctx) "/api/v1/digest/<date>.json — 指定日期 JSON\n"
    "- " (site-ctx-base-url ctx) "/daily/<date>.md — Markdown 日报\n"
    "- " (site-ctx-base-url ctx) "/api/events — SSE 出刊推送\n")))
