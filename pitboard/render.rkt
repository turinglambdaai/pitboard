#lang racket/base

;; HTML / RSS / Markdown / llms.txt rendering.  Pure: jsexpr in, bytes out.

(require xml
         racket/string
         racket/pretty
         racket/list
         racket/format
         racket/match
         racket/date
         racket/port
         "util.rkt"
         (only-in "store.rkt" list-dates load-digest))

(provide (struct-out site-ctx)
         v
         group-section
         front-page-quota
         xexpr->html-bytes
         render-index-page
         render-archive-page
         render-about-page
         render-empty-page
         render-not-found
         render-rss-xml
         render-daily-md
         render-llms-txt
         topic-slug
         topic-match?
         collect-topic-items
         render-topic-page
         render-topics-index
         render-period-page
         render-periods-index
         render-og-svg
         render-admin-page)

(struct site-ctx (domain base-url generated-at editions-fn) #:transparent)

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

(define (weekday-cn ymd)
  (define s (parse-date-any ymd))
  (if s
      (vector-ref #("日" "一" "二" "三" "四" "五" "六")
                  (date-week-day (seconds->date s #t)))
      ""))

(define kind-label
  (match-lambda
    ["github" "开源"]
    ["paper" "论文"]
    [_ "资讯"]))

(define (label-chip* l)
  (cond [(equal? l "new") '(span ((class "chip chip-new")) "新")]
        [(equal? l "rising") '(span ((class "chip chip-rising")) "↑ 上升")]
        [(equal? l "progress") '(span ((class "chip chip-progress")) "进展")]
        [else (list 'span '((class "chip")) l)]))

;; ---- shell ------------------------------------------------------------------

(define brand-mark
  `(svg ((class "brand-mark") (viewBox "0 0 24 24") (width "20") (height "20")
         (aria-hidden "true"))
     (rect ((x "1.25") (y "6") (width "21.5") (height "12") (rx "2.6")
            (fill "none") (stroke "currentColor") (stroke-width "1.7")))
     (rect ((x "4.4") (y "9.2") (width "2.7") (height "5.6") (rx "0.6")
            (fill "var(--accent)")))
     (rect ((x "9.2") (y "9.4") (width "7") (height "1.9") (rx "0.9")
            (fill "currentColor") (opacity "0.5")))
     (rect ((x "9.2") (y "13") (width "10.4") (height "1.9") (rx "0.9")
            (fill "currentColor") (opacity "0.28")))))

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
                (a ((class "brand") (href "/"))
                   ,brand-mark
                   (span ((class "brand-name")) "pitboard"))
                (div ((class "nav-links"))
                     ,@(for/list ([p (in-list '(("index" "/" "今日")
                                                ("topics" "/topics/" "话题")
                                                ("bookmarks" "/bookmarks.html" "书签")
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
              (div ((class "footer-brand")) "pitboard")
              (div "汽车行业每日热点 · Racket 全栈自托管 · 每日自动出刊")
              (div ((class "muted"))
                   "MIT 开源 · "
                   (a ((href "/llms.txt")) "llms.txt")
                   " · "
                   (a ((href "/rss.xml")) "RSS 订阅"))))))

;; ---- cluster card -----------------------------------------------------------

(define (span-stars n)
  (list 'span '((class "stars")) (format " ★~a" n)))

(define (source-chip it)
  (define extra (hash-ref it 'extra (hasheq)))
  (define stars (hash-ref extra 'stars #f))
  `(a ((class "chip chip-src") (href ,(v (hash-ref it 'url ""))) (target "_blank") (rel "noopener"))
      ,(kind-label (hash-ref it 'kind 'news))
      " · " ,(v (hash-ref it 'source_url "unknown"))
      ,@(if stars (list (span-stars stars)) '())))

(define (cluster-card h idx max-heat)
  (define heat-str (v (hash-ref h 'heat "0")))
  (define heat-num (or (string->number heat-str) 0.0))
  (define pct
    (inexact->exact
     (floor (max 4 (min 100 (* 100.0 (/ heat-num (max max-heat 0.001))))))))
  (define domains (hash-ref h 'domains 0))
  (define its (hash-ref h 'items '()))
  (define card-kind (v (hash-ref (car its) 'kind "news")))
  (define card-text
    (string-downcase
     (string-append (v (hash-ref h 'title "")) " " (v (hash-ref h 'summary "")))))
  `(article ((class "card")
             (data-kind ,card-kind)
             (data-text ,card-text))
     (div ((class "card-top"))
          (span ((class "rank")) ,(format "~a" (~r (add1 idx) #:min-width 2 #:pad-string "0")))
          (span ((class ,(string-append "card-kind kind-" card-kind)))
                ,(kind-label card-kind))
          (div ((class "labels"))
               (span ((class "heat")) "🔥 " ,heat-str)
               ,@(map label-chip* (map ~a (hash-ref h 'labels '())))
               ,@(if (> domains 1)
                     (list (list 'span '((class "chip"))
                                 (format "~a 个独立来源" domains)))
                     '())
               ,@(let ([fs (hash-ref h 'first_seen 'null)])
                   (if (string? fs)
                       (list (list 'span '((class "chip chip-seen"))
                                   (format "首见 ~a" fs)))
                       '()))
               (span ((class "card-time")) ,(newest-time h))))
     (div ((class "heatbar"))
          (span ((class "heatbar-fill") (style ,(format "width:~a%" pct))) ""))
     (h2 ((class "card-title"))
         (a ((href ,(first-item-url h)) (target "_blank") (rel "noopener"))
            ,(v (hash-ref h 'title ""))))
     ,@(let ([s (v (hash-ref h 'summary ""))])
         (if (non-empty-string? s) (list (list 'p '((class "card-summary")) s)) '()))
     (div ((class "chips"))
          ,@(map source-chip (take its (min 10 (length its)))))
     ,@(if (> (length its) 2)
           (list
            `(details ((class "more-src"))
                      (summary ,(format "展开全部 ~a 条来源" (length its)))
                      (ul ((class "src-list"))
                          ,@(for/list ([it (in-list its)])
                              `(li
                                (a ((href ,(v (hash-ref it 'url "#")))
                                    (target "_blank") (rel "noopener"))
                                   ,(v (hash-ref it 'title ""))
                                   (span ((class "src-dom"))
                                         ,(v (hash-ref it 'source_url "")))))))))
           '())))

(define (first-item-url h)
  (define items (hash-ref h 'items '()))
  (if (null? items) "#" (v (hash-ref (car items) 'url "#"))))

(define (newest-time h)
  ;; HH:MM of the freshest source in the cluster, or ""
  (define newest
    (for/fold ([m #f]) ([it (in-list (hash-ref h 'items '()))])
      (define p (hash-ref it 'published_at 'null))
      (define s (and (string? p) (parse-date-any p)))
      (if (and s (or (not m) (> s m))) s m)))
  (if newest
      (let ([d (seconds->date newest #t)])
        (format "~a:~a" (~r (date-hour d) #:min-width 2 #:pad-string "0")
                (~r (date-minute d) #:min-width 2 #:pad-string "0")))
      ""))

;; Per-source display quota: a single source (e.g. AUTOSAR's newsroom)
;; must not flood the front page.  Papers get their own smaller cap.
(define (front-page-quota clusters total per-source paper-max)
  ;; counts must be an equal-based hash: source_url strings parsed from
  ;; JSON are never eq? to each other (the hasheq trap).
  (let loop ([rest clusters] [counts (hash)] [papers 0] [picked '()])
    (cond [(or (>= (length picked) total) (null? rest)) (reverse picked)]
          [else
           (define c (car rest))
           (define kind (hash-ref (car (hash-ref c 'items '())) 'kind "news"))
           (cond [(equal? kind "paper")
                  (if (>= papers paper-max)
                      (loop (cdr rest) counts papers picked)
                      (loop (cdr rest) counts (add1 papers) (cons c picked)))]
                 [else
                  (define src (hash-ref (car (hash-ref c 'items '())) 'source_url ""))
                  (define n (hash-ref counts src 0))
                  (if (>= n per-source)
                      (loop (cdr rest) counts papers picked)
                      (loop (cdr rest) (hash-set counts src (add1 n))
                            papers (cons c picked)))])])))

(define (quick-strip digest)
  ;; masthead diversity: at most 3 repos in the top strip so the front
  ;; door always mixes code with readable industry news
  (define clusters (hash-ref digest 'clusters '()))
  (define top
    (let loop ([rest clusters] [gh 0] [seen-src (hash)] [picked '()])
      (cond [(or (= (length picked) 5) (null? rest)) (reverse picked)]
            [else
             (define c (car rest))
             (define k (hash-ref (car (hash-ref c 'items '())) 'kind "news"))
             (define src (hash-ref (car (hash-ref c 'items '())) 'source_url ""))
             (cond [(and (equal? k "github") (>= gh 3))
                    (loop (cdr rest) gh seen-src picked)]
                   [(>= (hash-ref seen-src src 0) 1)
                    (loop (cdr rest) gh seen-src picked)]
                   [else
                    (loop (cdr rest)
                          (if (equal? k "github") (add1 gh) gh)
                          (hash-set seen-src src 1)
                          (cons c picked))])])))
  `(section ((class "quick"))
     (div ((class "quick-head"))
          (span ((class "kicker")) "CURRENT HOT")
          (span ((class "quick-label")) "当前热点")
          (span ((class "quick-count")) ,(format "TOP ~a" (length top))))
     (ol ((class "quick-list"))
         ,@(for/list ([c (in-list top)] [i (in-naturals)])
             `(li ((class "quick-item"))
                  (a ((class "quick-link")
                      (href ,(first-item-url c))
                      (target "_blank") (rel "noopener"))
                     (span ((class "quick-rank"))
                           ,(format "~a" (~r (add1 i) #:min-width 2 #:pad-string "0")))
                     (span ((class "quick-name"))
                           ,(truncate-s (v (hash-ref c 'title "")) 52))
                     (span ((class "quick-heat"))
                           ,(format "🔥~a" (v (hash-ref c 'heat "0"))))))))))

(define (filter-toolbar digest)
  (define clusters (hash-ref digest 'clusters '()))
  (define n
    (for/hasheq ([k (in-list '("github" "news" "paper"))])
      (values k
              (for/sum ([c (in-list clusters)])
                (for/sum ([it (in-list (hash-ref c 'items '()))])
                  (if (equal? (hash-ref it 'kind "news") k) 1 0))))))
  `(div ((class "toolbar"))
     (div ((class "tabs") (role "tablist") (aria-label "按类型筛选"))
          (button ((class "tab active") (type "button") (data-filter "all"))
                  "全部"
                  (span ((class "tab-n") (data-count "all"))
                        ,(number->string (length clusters))))
          ,@(for/list ([k (in-list '(("github" "开源") ("news" "资讯") ("paper" "论文")))])
              `(button ((class "tab") (type "button") (data-filter ,(car k)))
                       ,(cadr k)
                       (span ((class "tab-n") (data-count ,(car k)))
                             ,(number->string (hash-ref n (car k) 0)))))
          (span ((class "toolbar-hint")) "按独立来源数排序"))
     (input ((class "search") (id "search") (type "search")
             (placeholder "搜索标题 / 摘要…（按 / 聚焦）")
             (autocomplete "off") (aria-label "搜索热点")))))

;; ---- pages -------------------------------------------------------------------

(define (hero-digest ctx digest)
  (define clusters (hash-ref digest 'clusters '()))
  (define items (for/sum ([c (in-list clusters)]) (length (hash-ref c 'items '()))))
  (define mode (hash-ref digest 'mode "scored"))
  (define date (v (hash-ref digest 'date "")))
  (define ed (hash-ref ((site-ctx-editions-fn ctx)) date #f))
  `(section ((class "hero"))
     (div ((class "hero-grid"))
          (div ((class "hero-copy"))
               (p ((class "kicker"))
                  ,(if ed (format "AUTOMOTIVE DAILY · 第 ~a 期" ed)
                       "AUTOMOTIVE DAILY"))
               (h1 ((class "hero-date"))
                   ,(date-cn date)
                   (span ((class "hero-wd")) ,(format " 星期~a" (weekday-cn date))))
               (p ((class "hero-meta"))
                  (span ,(format "~a 个热点" (length clusters)))
                  (span ((class "dot")) "·")
                  (span ,(format "~a 条原始条目" items))
                  (span ((class "dot")) "·")
                  (span ,(format "~a 个信源" (length (hash-ref digest 'sources '()))))
                  ,@(if (equal? mode "llm")
                        (list '(span ((class "chip chip-llm")) "LLM 增强"))
                        '())))
          (div ((class "board") (aria-hidden "true"))
               (div ((class "board-label")) "EDITION")
               (div ((class "board-num")) ,(if ed (~r ed) "—"))
               (div ((class "board-sub")) "PITBOARD · 每日出刊")))))

(define (render-index-page ctx digest)
  (define clusters (hash-ref digest 'clusters '()))
  (define max-heat
    (for/fold ([m 1.0]) ([c (in-list clusters)])
      (max m (or (string->number (v (hash-ref c 'heat "0"))) 0.0))))
  (define content
    (if (null? clusters)
        (list '(p ((class "empty")) "今天还没有足够的热点。"))
        (let* ([face-kind (λ (c) (hash-ref (car (hash-ref c 'items '())) 'kind "news"))]
               [news-lane
                (front-page-quota
                 (for/list ([c (in-list clusters)]
                            #:when (not (equal? (face-kind c) "github")))
                   c)
                 30 2 6)]
               [repo-lane (for/list ([c (in-list clusters)]
                                     #:when (equal? (face-kind c) "github"))
                            c)]
               [news-cards `(div ((class "cards"))
                                 ,@(for/list ([c (in-list news-lane)]
                                              [i (in-naturals)]
                                              #:when (< i 30))
                                     (cluster-card c i max-heat)))]
               [repo-cards `(div ((class "cards"))
                                 ,@(for/list ([c (in-list repo-lane)]
                                              [i (in-naturals)]
                                              #:when (< i 8))
                                     (cluster-card c i max-heat)))])
          (append
           (list (quick-strip digest)
                 (filter-toolbar digest)
                 news-cards)
           (if (null? repo-lane)
               '()
               (list `(section ((class "lane-head"))
                         (span ((class "kicker")) "OPEN SOURCE RADAR")
                         (h2 ((class "lane-title")) "开源雷达"))
                      repo-cards))))))
  (xexpr->html-bytes
   (page-shell ctx "pitboard — 汽车行业每日热点" "index"
               (cons (hero-digest ctx digest) content))))

(define (render-archive-page ctx digests)
  ;; digests: list of (list date cluster-count top-title)
  (define editions ((site-ctx-editions-fn ctx)))
  (xexpr->html-bytes
   (page-shell ctx "归档 — pitboard" "archive"
               (list
                '(section ((class "hero hero-slim"))
                   (p ((class "kicker")) "ARCHIVE")
                   (h1 ((class "hero-date hero-date-s")) "往期归档"))
                `(ul ((class "archive-list"))
                     ,@(for/list ([d (in-list digests)])
                         `(li
                           (a ((class "arch-link") (href ,(format "/d/~a" (car d))))
                              (span ((class "arch-ed"))
                                    ,(let ([e (hash-ref editions (car d) #f)])
                                       (if e (format "第 ~a 期" e) "")))
                              (span ((class "arch-date")) ,(date-cn (car d)))
                              (span ((class "arch-title")) ,(caddr d))
                              (span ((class "arch-count"))
                                    ,(format "~a 个热点" (cadr d)))))))))))

(define (render-about-page ctx)
  (xexpr->html-bytes
   (page-shell ctx "关于 — pitboard" "about"
               (list
                '(section ((class "hero hero-slim"))
                   (p ((class "kicker")) "ABOUT")
                   (h1 ((class "hero-date hero-date-s")) "关于 pitboard"))
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
                  (section ((class "install-box"))
                     (p ((class "kicker")) "一句话安装")
                     (p ((class "install-line"))
                        "请安装 pitboard 技能：https://pitboard.jrtx.site/skill/pitboard/SKILL.md")
                     (button ((class "btn-install") (id "copy-install") (type "button"))
                             "复制安装语")
                     (p ((class "muted"))
                        "把这句话发给你的 agent（Claude Code、ZCode……），它会自己装好。"))
                  (ul
                   (li (code "/rss.xml") " — RSS 订阅")
                   (li (code "/api/v1/latest.json") " — 最新一期 JSON（" (code "/api/v1/digest/2026-10-13.json") " 按日期取）")
                   (li (code "/openapi.json") " — 全部只读 API 规范")
                   (li (code "/daily/<date>.md") " — Markdown 日报")
                   (li (code "/llms.txt") " — 站点索引")
                   (li (code "/skill/pitboard/SKILL.md") " — 可安装的 agent 技能：把链接发给 agent 即可安装"
                       "（权威仓库 " (a ((href "https://github.com/turinglambdaai/pitboard-skill")) "pitboard-skill") "）")
                   (li (code "raco pitboard mcp") " — 自托管 MCP（latest_digest / get_edition / get_topic）")
                   (li (code "/api/events") " — SSE 出刊推送"))
                  (h2 "自托管")
                  (p "一个 Racket 进程，零外部依赖（无数据库）：" (br)
                     (code "raco pkg install --auto https://github.com/turinglambdaai/pitboard.git") (br)
                     (code "raco pitboard fetch && raco pitboard serve --port 8090"))
                  (h2 "许可")
                  (p "MIT 许可，源码开源于 "
                     (a ((href "https://github.com/turinglambdaai/pitboard")) "GitHub") "。"))))))

(define (render-empty-page ctx)
  (xexpr->html-bytes
   (page-shell ctx "pitboard — 汽车行业每日热点" "index"
               (list
                '(section ((class "hero"))
                   (p ((class "kicker")) "AUTOMOTIVE DAILY")
                   (h1 ((class "hero-date")) "还没有出刊")
                   (p ((class "hero-meta")) "先跑一次抓取：")
                   (p (code "raco pitboard fetch")))))))

(define (render-not-found ctx)
  (xexpr->html-bytes
   (page-shell ctx "404 — pitboard" ""
               (list '(section ((class "hero"))
                              (p ((class "kicker")) "404")
                              (h1 ((class "hero-date")) "这块板上没写东西")
                              (p ((class "hero-meta")) (a ((href "/")) "← 回今日热点")))))))

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
    "- [话题雷达](" (site-ctx-base-url ctx) "/topics/): 24 个 E/E 话题的跨期追踪（AUTOSAR、UDS、智能驾驶、召回、政策等）\n"
    "- [归档](" (site-ctx-base-url ctx) "/archive): 往期所有刊物\n"
    "- [关于](" (site-ctx-base-url ctx) "/about): 产品说明与自托管指南\n\n"
    "## Machine-readable\n\n"
    "- " (site-ctx-base-url ctx) "/rss.xml — RSS 2.0 订阅\n"
    "- " (site-ctx-base-url ctx) "/api/v1/latest.json — 最新一期完整 JSON\n"
    "- " (site-ctx-base-url ctx) "/api/v1/digest/<date>.json — 指定日期 JSON\n"
    "- " (site-ctx-base-url ctx) "/openapi.json — 全部只读 API 的 OpenAPI 规范\n"
    "- " (site-ctx-base-url ctx) "/daily/<date>.md — Markdown 日报\n"
    "- " (site-ctx-base-url ctx) "/search-index.json — 全站标题检索索引\n"
    "- " (site-ctx-base-url ctx) "/api/events — SSE 出刊推送（自托管 serve 模式）\n"
    "- 自托管 MCP：`raco pitboard mcp`（stdio，工具 latest_digest/get_edition/get_topic）\n\n"
    "## Agent Skill\n\n"
    "- " (site-ctx-base-url ctx) "/skill/pitboard/SKILL.md — 可安装的 agent 技能："
    "数据端点、JSON 结构、简报/话题追踪/跨日对比的任务配方与引用约定"
    "（引用必须回源 url 字段）。把此链接发给 agent 即可安装，文件内含自装指引。\n"
    "- 手动安装：git clone https://github.com/turinglambdaai/pitboard-skill.git ~/.claude/skills/pitboard"
    "（ZCode 换 ~/.zcode/skills/pitboard）。\n")))


;; ---- topic radar (cross-edition keyword tracking) ---------------------------

(define (topic-slug term)
  (list->string
   (for/list ([ch (in-string (string-downcase term))])
     (if (or (char-alphabetic? ch) (char-numeric? ch)) ch #\-))))

;; Latin/acronym terms match on word boundaries: naive substring made
;; "adds"/"odds"/"RDDs" hit topic DDS. CJK terms have no word boundaries
;; and stay substring-based.
(define ascii-term-px #px"^[a-z0-9][a-z0-9/+.\\-]*$")

(define (topic-match? term text)
  (define lowered (string-downcase text))
  (define t (string-downcase term))
  (if (regexp-match? ascii-term-px t)
      ;; 左侧不得紧贴 ASCII 字母数字（拦 adds/RDDs/OpenDDS）；右侧同，
      ;; 但允许英文复数（robotaxis），且汉字不算边界字符（保住「UDS诊断」）。
      (regexp-match?
       (pregexp (string-append "(?<![a-z0-9])" (regexp-quote t)
                               "(?:s|es)?(?![a-z0-9])"))
       lowered)
      (string-contains? lowered t)))

;; Newest-first list of (cons date item) matching term across the archive.
(define (collect-topic-items data-dir term)
  (for*/list ([d (in-list (list-dates data-dir))]
              [dg (in-value (load-digest data-dir d))]
              #:when dg
              [c (in-list (hash-ref dg 'clusters '()))]
              [it (in-list (hash-ref c 'items '()))]
              #:when (topic-match? term
                                  (string-append (v (hash-ref it 'title "")) " "
                                                 (v (hash-ref it 'summary "")))))
    (cons d it)))

(define (render-topic-page ctx term rows)
  (xexpr->html-bytes
   (page-shell ctx (string-append term " — 话题雷达") "topics"
               (list
                `(section ((class "hero hero-slim"))
                   (p ((class "kicker")) "TOPIC RADAR")
                   (h1 ((class "hero-date hero-date-s")) ,term)
                   (p ((class "hero-meta"))
                      ,(format "~a 条相关内容 · 跨期归档追踪" (length rows))))
                `(ul ((class "topic-list"))
                     ,@(for/list ([row (in-list rows)])
                         `(li ((class "topic-row"))
                              (span ((class "topic-date")) ,(car row))
                              (a ((href ,(v (hash-ref (cdr row) 'url "#")))
                                  (target "_blank") (rel "noopener"))
                                 ,(v (hash-ref (cdr row) 'title "")))
                              (span ((class "src-dom"))
                                    ,(v (hash-ref (cdr row) 'source_url ""))))))))))

(define (topic-card t)
  ;; t: (cons term count)
  (list 'li
        (list (list 'class "quick-item"))
        (list 'a
              (list (list 'class "quick-link")
                    (list 'href (format "/topic/~a/" (topic-slug (car t)))))
              (list 'span
                    (list (list 'class "quick-rank"))
                    (format "~a" (cdr t)))
              (list 'span
                    (list (list 'class "quick-name"))
                    (format "~a" (car t)))
              (list 'span
                    (list (list 'class "quick-heat"))
                    "追踪 →"))))

(define (group-section g)
  (define cards
    (for/list ([t (in-list (cdr g))])
      (topic-card t)))
  (list 'section
        (list (list 'class "lane-head"))
        (list 'span (list (list 'class "kicker")) (car g))
        (list 'h2 (list (list 'class "lane-title")) (format "~a" (car g)))
        (append (list 'div
                      (list (list 'class "quick-list topics-grid")))
                cards)))

(define (render-topics-index ctx groups)
  (define hero
    (list 'section
          (list (list 'class "hero hero-slim"))
          (list 'p (list (list 'class "kicker")) "TOPIC RADAR")
          (list 'h1 (list (list 'class "hero-date hero-date-s")) "话题雷达")
          (list 'p (list (list 'class "hero-meta")) "每个热点话题的跨期追踪，天天见底。")))
  (xexpr->html-bytes
   (page-shell ctx "话题雷达 — pitboard" "topics"
               (cons hero (for/list ([g (in-list groups)])
                           (group-section g))))))

(define (render-period-page ctx kind-label rows)
  (xexpr->html-bytes
   (page-shell ctx (string-append kind-label " — pitboard") "topics"
               (list
                `(section ((class "hero hero-slim"))
                   (p ((class "kicker")) "COMPILATION")
                   (h1 ((class "hero-date hero-date-s")) ,kind-label)
                   (p ((class "hero-meta"))
                      ,(format "从当期日报汇编 · ~a 条要闻 · 按热度去重" (length rows))))
                `(ol ((class "topic-list"))
                     ,@(for/list ([r (in-list rows)])
                         `(li ((class "topic-row"))
                              (span ((class "topic-date")) ,(car r))
                              (a ((href ,(caddr r)) (target "_blank") (rel "noopener"))
                                 ,(cadr r))
                              (span ((class "src-dom"))
                                    ,(format "热度 ~a" (cadddr r))))))))))

(define (render-periods-index ctx kind-label base entries)
  (xexpr->html-bytes
   (page-shell ctx (string-append kind-label "归档 — pitboard") "topics"
               (list
                `(section ((class "hero hero-slim"))
                   (p ((class "kicker")) "COMPILATION")
                   (h1 ((class "hero-date hero-date-s")) ,kind-label "归档"))
                `(ul ((class "archive-list"))
                     ,@(for/list ([e (in-list entries)])
                         `(li
                           (a ((class "arch-link")
                               (href ,(format "~a/~a/" base (car e))))
                              (span ((class "arch-date")) ,(car e))
                              (span ((class "arch-title"))
                                    ,(format "~a 条要闻" (cadr e)))))))))))


;; ---- og share card (SVG; a static per-edition asset) ------------------------

(define (render-og-svg digest)
  (define date (v (hash-ref digest 'date "")))
  (define top
    (let ([cs (hash-ref digest 'clusters '())])
      (if (null? cs) "" (v (hash-ref (car cs) 'title "")))))
  (define esc
    (λ (t)
      (regexp-replace* #px"<" (regexp-replace* #px"&" t "&amp;") "&lt;")))
  (string->bytes/utf-8
   (format
    (string-append
     "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1200\" height=\"630\">\n"
     "  <rect width=\"1200\" height=\"630\" fill=\"#17140f\"/>\n"
     "  <rect x=\"0\" y=\"0\" width=\"1200\" height=\"6\" fill=\"#c15f3c\"/>\n"
     "  <rect x=\"0\" y=\"6\" width=\"14\" height=\"6\" fill=\"#faf7f2\"/>\n"
     "  <rect x=\"28\" y=\"6\" width=\"14\" height=\"6\" fill=\"#faf7f2\"/>\n"
     "  <rect x=\"56\" y=\"6\" width=\"14\" height=\"6\" fill=\"#faf7f2\"/>\n"
     "  <text x=\"80\" y=\"210\" font-family=\"Menlo, monospace\" font-size=\"30\"
     fill=\"#c15f3c\" letter-spacing=\"8\">PITBOARD · AUTOMOTIVE DAILY</text>\n"
     "  <text x=\"80\" y=\"330\" font-family=\"PingFang SC, sans-serif\"
     font-size=\"88\" font-weight=\"800\" fill=\"#f5efe2\">~a</text>\n"
     "  <text x=\"80\" y=\"430\" font-family=\"PingFang SC, sans-serif\"
     font-size=\"34\" fill=\"#a49d92\">~a</text>\n"
     "  <rect x=\"80\" y=\"500\" width=\"1040\" height=\"1\" fill=\"#3a332a\"/>\n"
     "  <text x=\"80\" y=\"560\" font-family=\"Menlo, monospace\" font-size=\"24\"
     fill=\"#a49d92\">pitboard.jrtx.site</text>\n"
     "</svg>\n")
    (esc date)
    (esc (truncate-s top 40)))))


;; ---- admin status page (read-only diagnostics) --------------------------------

(define (render-admin-page ctx sources health admin-enabled?)
  (xexpr->html-bytes
   (page-shell ctx "运行状态 — pitboard" ""
               (list
                `(section ((class "hero hero-slim"))
                   (p ((class "kicker")) "ADMIN")
                   (h1 ((class "hero-date hero-date-s")) "运行状态")
                   ,@(if admin-enabled?
                         '((p ((class "hero-meta"))
                              (code "/admin/try?source=源名") " 可单源试抓（需 PITBOARD_ADMIN=1）"))
                         '((p ((class "hero-meta"))
                              "试抓未开启（设 PITBOARD_ADMIN=1）"))))
                `(ul ((class "archive-list"))
                     ,@(for/list ([s (in-list sources)])
                         `(li ((class "topic-row"))
                              (span ((class "topic-date"))
                                    ,(if (hash-ref s 'ok #f) "ok" "失败"))
                              (span ((class "arch-title"))
                                    ,(format "~a · ~a 条" (v (hash-ref s 'name ""))
                                             (hash-ref s 'count 0)))
                              (span ((class "src-dom"))
                                    ,(let ([m (hash-ref s 'message 'null)])
                                       (if (eq? m 'null) "" (v m)))))))))))
