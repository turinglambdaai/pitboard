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
         racket/date
         json
         net/uri-codec
         net/http-easy
         "util.rkt"
         "item.rkt"
         feed)

(provide default-config
         decode-html-bytes
         load-config
         default-watch-topics
         normalize-watch-topics
         fetch-all
         extract-web-items
         json-path
         json-api-items
         parse-date-slash
         (struct-out source-status)
         source-status->jsexpr)

(struct source-status (name kind ok count message) #:transparent)

(define (source-status->jsexpr s)
  (hasheq 'name (source-status-name s)
          'kind (source-status-kind s)
          'ok (source-status-ok s)
          'count (source-status-count s)
          'message (jx (source-status-message s))))

(define UA
  "Mozilla/5.0 (compatible; pitboard/0.1; +https://pitboard.jrtx.site)")

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

;; Topics tracked on the topic radar pages.  Internal shape:
;;   (list (cons group (list (cons term (listof alias))) …))
;; Aliases let a CJK-named topic also match its English press vocabulary
;; (线控底盘 ↔ by-wire).  Config entries: "词" or {"term":…, "aka":[…]}.
;; 词表判据与维护规则见 docs/VOCABULARY.md。
(define default-watch-topics
  (list
   (cons "方向"
         (list (cons "AUTOSAR" '())
               (cons "DDS" '())
               (cons "SOME/IP" '())
               (cons "SOA" '())
               (cons "信息安全" '())
               (cons "功能安全" '())
               (cons "安全刷写" '())
               (cons "UDS" '())
               (cons "车载以太网" '())
               (cons "域控" (list "中央计算" "区域架构" "zonal" "central compute"))
               (cons "线控底盘" (list "线控制动" "线控转向" "by-wire" "x-by-wire"
                                     "brake-by-wire" "steer-by-wire"))
               (cons "智能座舱" (list "座舱" "cockpit"))
               (cons "智能驾驶" (list "智驾" "NOA" "城市NOA"))
               (cons "端到端" (list "end-to-end" "vla" "vlm"))
               (cons "Robotaxi" '())
               (cons "固态电池" (list "solid-state battery" "全固态"))
               (cons "OTA" '())
               (cons "数据闭环" (list "数据引擎" "data engine" "影子模式"))))
   (cons "公司"
         (list (cons "比亚迪" '())
               (cons "华为车" '())
               (cons "蔚来" '())
               (cons "小鹏" '())
               (cons "理想" '())
               (cons "特斯拉" '())
               (cons "地平线" '())
               (cons "博世" (list "bosch"))))
   (cons "形态"
         (list (cons "芯片" '())
               (cons "开源" '())
               (cons "论文" '())
               (cons "召回" '())
               (cons "政策" '())))))

;; one watch entry (string | {term,aka} dict | pre-shaped pair) → (cons term akas)
(define (normalize-topic-entry e)
  (cond [(string? e) (cons e '())]
        [(and (pair? e) (list? (cdr e))) e]
        [(hash? e)
         (cons (~a (hash-ref e 'term ""))
               (let ([aka (hash-ref e 'aka '())])
                 (if (list? aka) (map ~a aka) '())))]
        [else (cons (~a e) '())]))

;; normalize: hash/list → (list (cons group-name (list (cons term akas) …)))
(define (normalize-watch-topics v)
  (cond [(hash? v)
         (for/list ([(g terms) (in-hash v)]
                    #:when (list? terms))
           (cons (~a g) (map normalize-topic-entry terms)))]
        [(and (list? v) (pair? v))
         (list (cons "全部" (map normalize-topic-entry v)))]
        [else default-watch-topics]))

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
                        'tier 2 'weight 0.8)
                (hasheq 'name "Medium · Automotive Cybersecurity"
                        'url "https://medium.com/feed/tag/automotive-cybersecurity"
                        'tier 2 'weight 0.9)
                (hasheq 'name "Automotive Dive"
                        'url "https://www.automotivedive.com/feeds/news/"
                        'tier 2 'weight 0.8)
                (hasheq 'name "dev.to · Automotive"
                        'url "https://dev.to/feed/tag/automotive"
                        'tier 2 'weight 0.7)
                (hasheq 'name "CleanTechnica"
                        'url "https://cleantechnica.com/feed/"
                        'tier 3 'weight 0.5)
                (hasheq 'name "发现报告 · 交运设备"
                        'type "json_api"
                        'url "https://api.fxbaogao.com/mofoun/seo/seoApiV3/listHomeIndustryReports?industry=%E4%BA%A4%E8%BF%90%E8%AE%BE%E5%A4%87"
                        'path "data"
                        'title_field "title"
                        'date_field "pubTimeStr"
                        'url_template "https://www.fxbaogao.com/detail/{docId}"
                        'tier 2 'weight 0.95 'max 6
                        'except_keywords (list "晨会" "盘前" "复盘" "晨报" "日评"))
                (hasheq 'name "发现报告 · 电气设备"
                        'type "json_api"
                        'url "https://api.fxbaogao.com/mofoun/seo/seoApiV3/listHomeIndustryReports?industry=%E7%94%B5%E6%B0%94%E8%AE%BE%E5%A4%87"
                        'path "data"
                        'title_field "title"
                        'date_field "pubTimeStr"
                        'url_template "https://www.fxbaogao.com/detail/{docId}"
                        'tier 2 'weight 0.8 'max 6
                        'only_keywords (list "电池" "固态" "锂电" "新能源" "充电"
                                             "电动" "整车" "汽车" "车规" "智驾"
                                             "智能驾驶" "自动驾驶" "robotaxi"
                                             "battery" "solid-state")
                        'except_keywords (list "晨会" "盘前" "复盘" "晨报" "日评")))
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
;; store accepts them.  Also used for WAF-blocked hosts: gasgoo.com
;; fingerprints the TLS handshake, so no User-Agent fixes an HTTP 400.
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

;; http-get-bytes with a curl fallback for TLS-rejected and WAF-blocked
;; fetches (cert verify failed / 400 / 403 / 406).
(define (fetch-bytes url-str)
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (define msg (exn-message e))
          (if (or (regexp-match? #rx"certificate verify failed" msg)
                  (regexp-match? #rx"HTTP (400|403|406)" msg))
              (curl-get-bytes url-str #:timeout-seconds 25)
              (raise e)))])
    (http-get-bytes url-str)))

;; ---- RSS feeds -------------------------------------------------------------

(define (keyword-match? kws text)
  (define lowered (string-downcase text))
  (for/or ([k (in-list kws)])
    (string-contains? lowered (string-downcase (~a k)))))


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
  (define b (fetch-bytes (hash-ref f 'url)))
  (define raw (feed->items (parse-feed b #:max-entries 80)
                           #:source-name name #:kind 'news #:weight weight))
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

;; ---- web list sources (pages without RSS; AIHOT-style list scraper) -------

(define (attr-of-tag tag name)
  (define m (regexp-match (format "(?i:~a=\"([^\"]*)\")" (regexp-quote name)) tag))
  (and m (cadr m)))

;; Extract (list title url) pairs from an HTML page: every <a> whose href
;; matches link-regex.  Title prefers the anchor's title attribute.
(define (extract-web-items html base-url link-regex)
  (define seen (mutable-set))
  (for/list ([m (in-list
                 (regexp-match*
                  #:match-select values
                  #px"(?i:<a\\b[^>]*href=\"([^\"]+)\"[^>]*>)([\\s\\S]*?)</a>"
                  html))]
             #:do [(define href (cadr m))
                   (define inner (strip-html (caddr m)))]
             #:when (and (non-empty-string? href)
                         (regexp-match? link-regex href)
                         (not (str-starts? href "javascript")))
             #:do [(define title-attr
                     (string-trim (or (attr-of-tag (car m) "title") "")))
                   (define t
                     (if (>= (string-length title-attr) 8) title-attr inner))]
             #:unless (or (set-member? seen href) (< (string-length t) 8))
             #:do [(set-add! seen href)])
    (list t
          (cond [(or (str-starts? href "http://") (str-starts? href "https://"))
                 href]
                ;; 协议相对链接(//host/path)——继承页面协议
                [(str-starts? href "//")
                 (string-append "https:" href)]
                [else
                 (string-append base-url href)]))))

;; 老牌门户(汽车之家等)仍是 GB2312/GBK 编码;按页面声明转码,
;; 其余按 UTF-8(坏字节替换)。
(define (decode-html-bytes b)
  (define head (subbytes b 0 (min 4096 (bytes-length b))))
  (if (regexp-match? #rx"(?i:charset=[\"']?(gb2312|gbk))"
                     (bytes->string/latin-1 head))
      (let ([cvt (bytes-open-converter "GBK" "UTF-8")])
        (if (not cvt)
            (bytes->string/utf-8 b #\?)
            (let-values ([(out cleanup)
                          (values
                           (make-bytes (* 3 (bytes-length b)))
                           (λ () (bytes-close-converter cvt)))])
              (define-values (used got status)
                (bytes-convert cvt b 0 (bytes-length b) out))
              (cleanup)
              (bytes->string/utf-8
               (if (eq? status 'complete) (subbytes out 0 got) b)
               #\?))))
      (bytes->string/utf-8 b #\?)))

(define (fetch-web-list w)
  (define name (hash-ref w 'name "page"))
  (define tier (hash-ref w 'tier 2))
  (define weight
    (* (hash-ref w 'weight 1.0)
       (match tier [1 1.35] [3 0.85] [_ 1.0])))
  (define b (fetch-bytes (hash-ref w 'url)))
  (define rows
    (extract-web-items (decode-html-bytes b)
                       (hash-ref w 'base_url (hash-ref w 'url))
                       ;; pregexp, not regexp: #rx treats \w/\d/{n} as
                       ;; literal chars, silently breaking config patterns.
                       (pregexp (hash-ref w 'link_regex ""))))
  ;; web_list sources support the same keyword gates as RSS feeds
  ;; (only_keywords/except_keywords on title+summary).
  (define kws (let ([v (hash-ref w 'only_keywords #f)])
                (and (list? v) (pair? v) v)))
  (define excepts (let ([v (hash-ref w 'except_keywords #f)])
                    (and (list? v) (pair? v) v)))
  (define maxn (hash-ref w 'max 10))
  (define now (current-seconds))
  (define items
    (for/list ([row (in-list (take rows (min maxn (length rows))))]
               #:when (let ([txt (string-append (strip-html (car row)) " "
                                                (strip-html (cadr row)))])
                        (and (not (and excepts (keyword-match? excepts txt)))
                             (or (not kws) (keyword-match? kws txt)))))
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

;; ---- JSON API sources -------------------------------------------------------

(define (json-path v path)
  (for/fold ([v v]) ([k (in-list path)])
    (cond [(and (hash? v) (hash-has-key? v k)) (hash-ref v k)]
          [(and (list? v) (number? k) (< k (length v))) (list-ref v k)]
          [else 'null])))

;; Chinese sites often publish "2026/10/13" (occasionally with a trailing
;; slash) — a format neither ISO 8601 nor RFC 822 covers.  Noon UTC keeps
;; same-day items in one date bucket regardless of timezone.
(define (parse-date-slash s)
  (define m (and (string? s)
                 (regexp-match #px"^(\\d{4})[/\\.](\\d{1,2})[/\\.](\\d{1,2})"
                               (string-trim s))))
  (and m
       (let ([y (string->number (list-ref m 1))]
             [mo (string->number (list-ref m 2))]
             [d (string->number (list-ref m 3))])
         (and y mo d (<= 1 mo 12) (<= 1 d 31)
              (find-seconds 0 0 12 d mo y #t)))))

(define (parse-date-loose v)
  (and (string? v) (or (parse-date-any v) (parse-date-slash v))))

;; Resolve a "https://host/detail/{docId}" template against a JSON entry.
;; #f when a referenced field is missing or not a scalar, so the entry is
;; dropped rather than emitted with a half-built URL.
(define (fill-url-template tmpl e)
  (let loop ([ks (regexp-match* #px"\\{([a-zA-Z0-9_]+)\\}" tmpl
                                #:match-select cadr)]
             [s tmpl])
    (cond [(null? ks) s]
          [else
           (define v (hash-ref e (string->symbol (car ks)) 'null))
           (if (or (string? v) (real? v))
               (loop (cdr ks)
                     (string-replace s (string-append "{" (car ks) "}")
                                     (format "~a" v)))
               #f)])))

;; Pure item-building half of the json_api channel: parsed JSON root in,
;; items out.  Split from fetch-json-api so tests run without network.
(define (json-api-items root w)
  (define name (hash-ref w 'name "api"))
  (define weight
    (* (hash-ref w 'weight 1.0)
       (match (hash-ref w 'tier 2) [1 1.35] [3 0.85] [_ 1.0])))
  (define path
    (for/list ([seg (in-list (string-split (hash-ref w 'path "") "."))]
               #:when (non-empty-string? seg))
      (define n (string->number seg))
      (or n (string->symbol seg))))
  (define entries (json-path root path))
  (define title-f (string->symbol (hash-ref w 'title_field "title")))
  (define url-f (string->symbol (hash-ref w 'url_field "url")))
  ;; read-json hashes carry symbol keys; config fields arrive as strings
  (define date-f (string->symbol (hash-ref w 'date_field "published_at")))
  (define url-tmpl (hash-ref w 'url_template #f))
  ;; json_api sources support the same keyword gates as RSS/web_list
  ;; (only_keywords/except_keywords, matched on the title).
  (define kws (let ([v (hash-ref w 'only_keywords #f)])
                (and (list? v) (pair? v) v)))
  (define excepts (let ([v (hash-ref w 'except_keywords #f)])
                    (and (list? v) (pair? v) v)))
  (define maxn (hash-ref w 'max 10))
  ;; Entries with a broken/missing URL (e.g. url_template referencing a
  ;; field the entry lacks) are dropped here, keeping the builder pure.
  (filter values
          (for/list ([e (in-list (if (list? entries)
                                     (take entries (min maxn (length entries)))
                                     '()))]
                     #:when (hash? e)
                     #:when (let ([title (strip-html (~a (hash-ref e title-f 'null)))])
                              (and (non-empty-string? title)
                                   (not (and excepts (keyword-match? excepts title)))
                                   (or (not kws) (keyword-match? kws title)))))
            (define title (strip-html (~a (hash-ref e title-f 'null))))
            (define url (if url-tmpl
                            (fill-url-template url-tmpl e)
                            (let ([u (hash-ref e url-f 'null)])
                              (if (eq? u 'null) "" u))))
            (and (non-empty-string? url)
                 (item (make-item-id 'news (normalize-url url))
                       'news name (slug-domain url)
                       (truncate-s title 200) url ""
                       (parse-date-loose (hash-ref e date-f 'null))
                       (hasheq 'weight weight))))))

(define (fetch-json-api w)
  (define b (fetch-bytes (hash-ref w 'url)))
  (define root (with-input-from-bytes b read-json))
  (define items (json-api-items root w))
  (values items
          (source-status (hash-ref w 'name "api") "json" #t (length items) #f)))

;; ---- GitHub topic search ---------------------------------------------------

(define (github-headers token)
  (if token
      (hasheq 'User-Agent UA
              'Accept "application/vnd.github+json"
              'Authorization (string-append "Bearer " token))
      (hasheq 'User-Agent UA 'Accept "application/vnd.github+json")))

;; GitHub repos must clear an automotive-engineering relevance bar, or
;; broad topics pull in smart-home noise (home-assistant matched topic
;; "automotive" once already).  pregexp: the \b word boundaries are dead
;; under #rx (undefined escapes become literal chars there).
(define gh-relevance-regex
  (pregexp "(?i:autosar|iso.?26262|iso.?21434|aspice|can.?fd|can.?bus|\\buds\\b|\\bobd\\b|\\badas\\b|autonomous|self-driving|driv(ing|er)|vehicle|automotive|robotaxi|\\bcars?\\b|truck|\\becu\\b|\\bmcu\\b|carla|lidar|\\bradar\\b|zephyr|\\bsdv\\b|\\bagl\\b|chassis|线控|by.wire|座舱|cockpit|固态电池|solid.state|数据闭环|车路云|v2x|sotif|车|驾驶|汽车|智驾|芯片|整车)"))

(define gh-blocklist-regex
  (pregexp "^home-assistant/|^openhab/|^homebridge/|^domoticz/"))

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
      (define parsed (feed->items (parse-atom b #:max-entries 80)
                                  #:source-name "arXiv" #:kind 'paper #:weight 1.0))
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
         (cond [(equal? (hash-ref f 'type "rss") "web_list")
                (fetch-web-list f)]
               [(equal? (hash-ref f 'type "rss") "json_api")
                (fetch-json-api f)]
               [else (fetch-rss-feed f)])))
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
