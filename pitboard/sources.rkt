#lang racket/base

;; Source adapters: RSS feeds, GitHub topic search, arXiv query.
;; All network calls run under a hard timeout; any failure degrades to
;; a source-status record instead of killing the edition.

(require racket/string
         racket/list
         racket/format
         racket/match
         racket/file
         racket/system
         racket/set
         racket/port
         json
         net/uri-codec
         net/http-easy
         "util.rkt"
         "item.rkt"
         "feed.rkt")

(provide default-config
         load-config
         default-watch-topics
         fetch-all
         extract-web-items
         (struct-out source-status)
         source-status->jsexpr)

(struct source-status (name kind ok count message) #:transparent)

(define (source-status->jsexpr s)
  (hasheq 'name (source-status-name s)
          'kind (source-status-kind s)
          'ok (source-status-ok s)
          'count (source-status-count s)
          'message (jx (source-status-message s))))

(define UA "pitboard/0.1 (+https://pitboard.jrtx.site)")

;; ---- config ---------------------------------------------------------------

(define arxiv-default-query
  "(cat:cs.RO OR cat:eess.SY OR cat:cs.AR) AND (abs:automotive OR abs:\"autonomous driving\" OR abs:vehicle OR abs:ADAS OR abs:\"connected vehicles\" OR abs:AUTOSAR OR abs:\"functional safety\" OR abs:\"in-vehicle\" OR abs:ECU)")

(define default-topics
  (list "autosar" "uds" "iso-26262" "can-bus" "adas"
        "autonomous-driving" "self-driving" "robotaxi"
        "automotive" "automotive-software"
        "someip" "tsn" "doip"))

;; Official orgs watched without a star floor: first-party signal.
(define default-orgs
  (list "AUTOSAR" "COVESA"))

;; Topics tracked on the topic radar pages.
(define default-watch-topics
  (list "AUTOSAR" "DDS" "SOME/IP" "SOA" "信息安全" "功能安全"
        "安全刷写" "UDS" "车载以太网" "域控" "智能驾驶" "Robotaxi" "芯片"))

;; title keywords an HN story must match to count as automotive
(define hn-default-keywords
  (list "automotive" "autosar" "some/ip" "someip" "uds" "can bus" "can fd"
        "adas" "autonomous" "self-driving" "driverless" "robotaxi" "waymo"
        "vehicle" "iso 26262" "iso 21434" "functional safety" "car hacking"
        "tesla" "byd" "nio " "xpeng" "zeekr" "cruise" "zoox" "motorsport"))

(define default-config
  (hasheq 'feeds
          (list (hasheq 'name "AUTOSAR 官方"
                        'type "web_list"
                        'url "https://www.autosar.org/news-events"
                        'base_url "https://www.autosar.org"
                        'link_regex "/news-events/detail/"
                        'tier 1 'weight 1.3 'max 8)
                (hasheq 'name "The Verge · Transportation"
                        'url "https://www.theverge.com/rss/transportation/index.xml"
                        'tier 2 'weight 1.0)
                (hasheq 'name "IEEE Spectrum · Transportation"
                        'url "https://spectrum.ieee.org/feeds/topic/transportation.rss"
                        'tier 2 'weight 1.1)
                (hasheq 'name "Just Auto"
                        'url "https://www.just-auto.com/feed/"
                        'tier 2 'weight 0.8)
                (hasheq 'name "雷峰网 · AI 与芯片"
                        'url "https://www.leiphone.com/feed"
                        'tier 3 'weight 0.9
                        'only_keywords (list "汽车" "智驾" "智能驾驶" "自动驾驶" "芯片"
                                             "车载" "车规" "电池" "autosar" "半导体"
                                             "nvidia" "英伟达" "地平线" "小鹏" "蔚来"
                                             "理想" "比亚迪" "固态电池" "mcu" "soc"
                                             "adas" "robotaxi" "vehicle" "激光雷达"
                                             "智能网联" "大疆车载" "华为车" "robotruck")
                        'except_keywords (list "淘宝" "一加" "电商" "退款" "京东"
                                               "折叠屏" "手机发布" "销量榜"))
                (hasheq 'name "EE Times"
                        'url "https://www.eetimes.com/feed/"
                        'tier 2 'weight 0.7
                        'only_keywords (list "automotive" "vehicle" "autonomous"
                                             "adas" "chip" "semiconductor" "mcu"
                                             "soc" "sensor" "nvidia" "qualcomm"
                                             "infineon" "renesas" "stmicro" "nxp"
                                             "tsmc" "foundry" "fab" "ecu" "radar"
                                             "battery" "power" "analog"))
                (hasheq 'name "NVIDIA Developer Blog"
                        'url "https://developer.nvidia.com/blog/feed/"
                        'tier 1 'weight 0.7
                        'only_keywords (list "drive" "thor" "orin" "automotive" "vehicle"
                                             "adas" "autonomous" "robotaxi" "truck" "driving"))
                (hasheq 'name "Ars Technica · Cars"
                        'url "https://arstechnica.com/cars/feed/"
                        'tier 3 'weight 0.9)
                (hasheq 'name "TechCrunch · Transportation"
                        'url "https://techcrunch.com/category/transportation/feed/"
                        'tier 3 'weight 0.6)
                (hasheq 'name "Electrek"
                        'url "https://electrek.co/feed/"
                        'tier 3 'weight 0.5)
                (hasheq 'name "Zephyr Project Blog"
                        'url "https://zephyrproject.org/feed/"
                        'tier 1 'weight 0.5)
                (hasheq 'name "Medium · AUTOSAR"
                        'url "https://medium.com/feed/tag/autosar"
                        'tier 2 'weight 0.8)
                (hasheq 'name "Medium · Automotive Software"
                        'url "https://medium.com/feed/tag/automotive-software"
                        'tier 2 'weight 0.8))
          'hn
          (hasheq 'keywords hn-default-keywords 'days 7 'per_page 1000 'min_points 2)
          'github
          (hasheq 'topics default-topics
                  'orgs default-orgs
                  'per_page 3
                  'min_stars 20)
          'arxiv
          (hasheq 'query arxiv-default-query
                  'max_results 40)
          'watch_topics default-watch-topics))

;; Accepts either our embedded shape or a JSON file with the same keys.
(define (load-config [path #f])
  (cond
    [(and path (file-exists? path))
     (with-handlers ([exn:fail? (λ (_) default-config)])
       (define j (with-input-from-file path read-json))
       (if (hash? j) j default-config))]
    [else default-config]))

;; ---- HTTP with a hard wall-clock timeout ----------------------------------

(define (http-get-bytes url-str
                        #:headers [hdrs (hasheq 'User-Agent UA)]
                        #:timeout-seconds [secs 25])
  (define ch (make-channel))
  (define worker
    (thread
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (channel-put ch (cons 'err (exn-message e))))])
         (define r (get url-str #:headers hdrs))
         (when (>= (response-status-code r) 400)
           (error 'http-get "HTTP ~a" (response-status-code r)))
         (channel-put ch (cons 'ok (response-body r)))))))
  (define v (sync/timeout secs ch))
  (cond
    [(not v)
     (kill-thread worker)
     (error 'http-get "timeout after ~as: ~a" secs url-str)]
    [(eq? (car v) 'err) (error 'http-get (cdr v))]
    [else (cdr v)]))

;; Fallback HTTP via system curl: some servers (autosar.org) ship TLS
;; chains that Racket's strict verification rejects while the system CA
;; store accepts them.
(define (curl-get-bytes url-str #:timeout-seconds [secs 25])
  (define curl
    (or (find-executable-path "curl")
        (error 'curl-get "curl not found on PATH")))
  (define tmp (make-temporary-file "pitboard-curl~a.html"))
  (dynamic-wind
    (λ () (void))
    (λ ()
      (define code
        (with-handlers ([exn:fail? (λ (_) 127)])
          (system*/exit-code curl "-sSL" "--compressed"
                             "--max-time" (~a secs) "-A" UA
                             "-o" (path->string tmp) url-str)))
      (unless (zero? code) (error 'curl-get "exit ~a" code))
      (file->bytes tmp))
    (λ () (with-handlers ([exn:fail? void]) (delete-file tmp)))))

;; ---- RSS feeds -------------------------------------------------------------

(define (keyword-match? kws text)
  (define lowered (string-downcase text))
  (for/or ([k (in-list kws)])
    (string-contains? lowered (string-downcase (~a k)))))

;; ---- web list sources (pages without RSS; AIHOT-style list scraper) -------

(define (attr-of-tag tag name)
  (define m (regexp-match (format "(?i:~a=\"([^\"]*)\")" (regexp-quote name)) tag))
  (and m (cadr m)))

;; Extract (list title url) pairs from an HTML page: every <a> whose href
;; matches link-regex.  Title prefers the anchor's title attribute.
(define (extract-web-items html base-url link-regex)
  (define seen (mutable-set))
  (for/list ([tag (in-list (regexp-match* #px"(?i:<a\\b[^>]*>)" html))]
             #:do [(define href (and tag (attr-of-tag tag "href")))]
             #:when (and href
                         (non-empty-string? href)
                         (regexp-match? link-regex href)
                         (not (str-starts? href "javascript")))
             #:do [(define t (string-trim (or (attr-of-tag tag "title") "")))]
             #:unless (or (set-member? seen href) (< (string-length t) 8))
             #:do [(set-add! seen href)])
    (list t
          (if (or (str-starts? href "http://") (str-starts? href "https://"))
              href
              (string-append base-url href)))))

(define (fetch-web-list w)
  (define name (hash-ref w 'name "page"))
  (define tier (hash-ref w 'tier 2))
  (define weight
    (* (hash-ref w 'weight 1.0)
       (match tier [1 1.35] [3 0.85] [_ 1.0])))
  (define b
    (with-handlers
        ([exn:fail?
          (λ (e)
            (if (regexp-match? #rx"certificate verify failed" (exn-message e))
                (curl-get-bytes (hash-ref w 'url) #:timeout-seconds 25)
                (raise e)))])
      (http-get-bytes (hash-ref w 'url))))
  (define rows
    (extract-web-items (bytes->string/utf-8 b #\?)
                       (hash-ref w 'base_url (hash-ref w 'url))
                       (regexp (hash-ref w 'link_regex ""))))
  (define maxn (hash-ref w 'max 10))
  (define now (current-seconds))
  (define items
    (for/list ([row (in-list (take rows (min maxn (length rows))))])
      (item (make-item-id 'news (normalize-url (cadr row)))
            'news
            name
            (slug-domain (cadr row))
            (strip-html (car row))
            (cadr row)
            ""
            now
            (hasheq 'weight weight))))
  (values items (source-status name "web" #t (length items) #f)))

(define (fetch-rss-feed f)
  (define name (hash-ref f 'name "feed"))
  ;; source tier: 1 official first-party, 2 trade press, 3 general media
  (define tier (hash-ref f 'tier 2))
  (define weight
    (* (hash-ref f 'weight 1.0)
       (match tier [1 1.35] [3 0.85] [_ 1.0])))
  (define kws (let ([v (hash-ref f 'only_keywords #f)])
                (and (list? v) (pair? v) v)))
  (define excepts (let ([v (hash-ref f 'except_keywords #f)])
                    (and (list? v) (pair? v) v)))
  (define b (http-get-bytes (hash-ref f 'url)))
  (define raw (parse-feed b #:source-name name #:kind 'news #:weight weight))
  (define items
    (for/list ([it (in-list raw)]
               #:unless (and excepts
                             (keyword-match? excepts
                                             (string-append (item-title it) " "
                                                            (item-summary it))))
               #:when (or (not kws)
                          (keyword-match? kws
                                          (string-append (item-title it) " "
                                                         (item-summary it)))))
      it))
  (values items (source-status name "rss" #t (length items) #f)))

;; ---- GitHub topic search ---------------------------------------------------

(define (github-headers token)
  (if token
      (hasheq 'User-Agent UA
              'Accept "application/vnd.github+json"
              'Authorization (string-append "Bearer " token))
      (hasheq 'User-Agent UA 'Accept "application/vnd.github+json")))

;; GitHub repos must clear an automotive-engineering relevance bar, or
;; broad topics pull in smart-home noise (home-assistant matched topic
;; "automotive" once already).
(define gh-relevance-regex
  (regexp "(?i:autosar|iso.?26262|iso.?21434|aspice|can.?fd|can.?bus|\\buds\\b|\\bobd\\b|\\badas\\b|autonomous|self-driving|driv(ing|er)|vehicle|automotive|robotaxi|\\bcars?\\b|truck|\\becu\\b|\\bmcu\\b|carla|lidar|\\bradar\\b|zephyr|\\bsdv\\b|\\bagl\\b|chassis|车|驾驶|汽车|智驾|芯片|整车)"))

(define gh-blocklist-regex
  (regexp "^home-assistant/|^openhab/|^homebridge/|^domoticz/"))

(define (gh-relevant? h)
  (define full (hash-ref h 'full_name ""))
  (define desc (let ([d (hash-ref h 'description 'null)])
                 (if (eq? d 'null) "" d)))
  (and (not (regexp-match? gh-blocklist-regex full))
       (regexp-match? gh-relevance-regex (string-append full " " desc))))

(define (repo->item h [tier 2])
  (define full (hash-ref h 'full_name ""))
  (define url (hash-ref h 'html_url ""))
  (define pushed (parse-date-any (let ([v (hash-ref h 'pushed_at 'null)])
                                   (if (eq? v 'null) #f v))))
  (define desc (let ([d (hash-ref h 'description 'null)])
                 (if (eq? d 'null) "" (string-trim d))))
  (define lang (let ([l (hash-ref h 'language 'null)])
                 (if (eq? l 'null) #f l)))
  (and (non-empty-string? full)
       (non-empty-string? url)
       (item (format "gh:~a" full)
             'github
             "GitHub"
             "github.com"
             full
             url
             desc
             pushed
             (hasheq 'stars (hash-ref h 'stargazers_count 0)
                     'language (jx lang)
                     'created_at (jx (hash-ref h 'created_at 'null))
                     'tier tier))))

(define (github-search q per-page token)
  (define url
    (format "https://api.github.com/search/repositories?q=~a&sort=stars&order=desc&per_page=~a"
            (uri-encode q) per-page))
  (define b (http-get-bytes url #:headers (github-headers token)))
  (with-input-from-bytes b read-json))

(define (fetch-github [cfg (hasheq)] #:now [now (current-seconds)])
  (define topics (hash-ref cfg 'topics default-topics))
  (define per-page (hash-ref cfg 'per_page 4))
  (define min-stars (hash-ref cfg 'min_stars 20))
  (define token (getenv "GITHUB_TOKEN"))
  (define pushed-since (iso-date (- now (* 30 86400))))
  (define created-since (iso-date (- now (* 90 86400))))
  (define orgs (hash-ref cfg 'orgs default-orgs))
  (define queries
    (append
     (for/list ([t (in-list topics)])
       (format "topic:~a pushed:>~a stars:>~a" t pushed-since min-stars))
     (for/list ([o (in-list orgs)])
       (format "user:~a pushed:>~a" o pushed-since))
     (list (format "topic:automotive created:>~a" created-since))))
  (define items '())
  (define errs '())
  (for ([q (in-list queries)]
        [i (in-naturals)])
    (with-handlers ([exn:fail? (λ (e) (set! errs (cons (exn-message e) errs)))])
      (when (positive? i) (sleep (if token 2 7)))   ; search API rate limits
      (define res (github-search q per-page token))
      (define rows (hash-ref res 'items '()))
      ;; org-watch repos are first-party: no star floor, tier 1
      (set! items
            (append items
                    (filter values
                            (map (λ (h)
                                   (define is-org
                                     (for/or ([o (in-list orgs)])
                                       (str-starts? (string-downcase
                                                     (hash-ref h 'full_name ""))
                                                    (string-downcase
                                                     (string-append o "/")))))
                                   (repo->item h (if is-org 1 2)))
                                 (filter gh-relevant? rows)))))))
  (values items
          (source-status "GitHub 话题" "github" (null? errs)
                         (length items)
                         (and (pair? errs) (car errs)))))

;; ---- arXiv -----------------------------------------------------------------

(define (fetch-arxiv [cfg (hasheq)])
  (define q (hash-ref cfg 'query arxiv-default-query))
  (define maxn (hash-ref cfg 'max_results 40))
  (define url
    (format "https://export.arxiv.org/api/query?search_query=~a&sortBy=submittedDate&sortOrder=descending&max_results=~a"
            (uri-encode q) maxn))
  (define-values (items err)
    (with-handlers ([exn:fail? (λ (e) (values '() (exn-message e)))])
      (define b (http-get-bytes url #:timeout-seconds 30))
      (define parsed (parse-atom b #:source-name "arXiv" #:kind 'paper #:weight 1.0))
      (values parsed
              (and (null? parsed)
                   (format "parsed 0 of ~a bytes" (bytes-length b))))))
  (values items (source-status "arXiv" "arxiv" (not err) (length items) err)))

;; ---- all sources ------------------------------------------------------------

;; ---- Hacker News (Algolia title search) ------------------------------------

(define (fetch-hn [cfg (hasheq)] #:now [now (current-seconds)])
  ;; Algolia's query is typo-tolerant (no exact keyword match, no OR on
  ;; this endpoint), so pull recent stories and filter titles locally.
  (define kws (hash-ref cfg 'keywords hn-default-keywords))
  (define days (hash-ref cfg 'days 7))
  (define per-page (hash-ref cfg 'per_page 1000))
  (define min-pts (hash-ref cfg 'min_points 2))
  (define url
    (format "https://hn.algolia.com/api/v1/search_by_date?tags=story&hitsPerPage=~a&numericFilters=created_at_i%3E~a,points%3E~a"
            per-page (- now (* days 86400)) min-pts))
  (define b (http-get-bytes url))
  (define res (with-input-from-bytes b read-json))
  (define items
    (for/list ([h (in-list (hash-ref res 'hits '()))]
               #:do [(define title (hash-ref h 'title ""))]
               #:when (and (string? title)
                           (non-empty-string? title)
                           (keyword-match? kws title)))
      (define link (hash-ref h 'url 'null))
      (define pts (hash-ref h 'points 0))
      (and (non-empty-string? title)
           (item (make-item-id 'news (string-append "hn:" title))
                 'news
                 "Hacker News"
                 "news.ycombinator.com"
                 title
                 (if (eq? link 'null)
                     (string-append "https://news.ycombinator.com/item?id="
                                    (hash-ref h 'objectID ""))
                     link)
                 ""
                 (parse-date-any (hash-ref h 'created_at 'null))
                 (hasheq 'weight 0.9 'points (jx (and (number? pts) (> pts 0) pts)))))))
  (values (filter values items)
          (source-status "Hacker News" "hn" #t
                         (length (filter values items)) #f)))

(define (fetch-all cfg)
  (define items '())
  (define statuses '())
  (define (absorb its st)
    (set! items (append items its))
    (set! statuses (cons st statuses)))
  (for ([f (in-list (hash-ref cfg 'feeds '()))])
    (call-with-values
     (λ ()
       (with-handlers
           ([exn:fail?
             (λ (e)
               (values '()
                       (source-status (hash-ref f 'name "feed")
                                      (hash-ref f 'type "rss") #f 0
                                      (exn-message e))))])
         (if (equal? (hash-ref f 'type "rss") "web_list")
             (fetch-web-list f)
             (fetch-rss-feed f))))
     absorb))
  (call-with-values
   (λ ()
     (with-handlers
         ([exn:fail?
           (λ (e)
             (values '()
                     (source-status "GitHub 话题" "github" #f 0 (exn-message e))))])
       (fetch-github (hash-ref cfg 'github (hasheq)))))
   absorb)
  (call-with-values
   (λ ()
     (with-handlers
         ([exn:fail?
           (λ (e)
             (values '()
                     (source-status "Hacker News" "hn" #f 0 (exn-message e))))])
       (fetch-hn (hash-ref cfg 'hn (hasheq)))))
   absorb)
  (call-with-values
   (λ ()
     (with-handlers
         ([exn:fail?
           (λ (e)
             (values '()
                     (source-status "arXiv" "arxiv" #f 0 (exn-message e))))])
       (fetch-arxiv (hash-ref cfg 'arxiv (hasheq)))))
   absorb)
  ;; dedupe by id (the same repo can surface from two queries)
  (define seen (mutable-set))
  (define dedup
    (for/list ([it (in-list items)]
               #:unless (set-member? seen (item-id it)))
      (set-add! seen (item-id it))
      it))
  (values dedup (reverse statuses)))
