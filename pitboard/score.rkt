#lang racket/base

;; The heat engine: tokenize, cluster near-duplicate stories, score clusters
;; by independent-source count with recency decay.  Runs with zero LLM.

(require racket/string
         racket/list
         racket/match
         racket/format
         racket/set
         racket/date
         "util.rkt"
         "item.rkt")

(provide tokenize
         jaccard
         cluster-items
         rank-clusters
         hot->jsexpr
         event-fingerprint
         annotate-progress!
         (struct-out hot))

;; ---- tokens ----------------------------------------------------------------

(define stopwords
  (set "the" "and" "for" "with" "from" "this" "that" "have" "has" "are"
       "was" "were" "will" "how" "why" "what" "its" "you" "your" "out"
       "about" "into" "over" "after" "before" "than" "then" "com" "www"
       "http" "https" "just" "more" "most" "can" "not" "but" "all" "one"
       "two" "our" "new" "get" "got" "when" "who" "his" "her" "says" "said"
       "here" "there" "been" "being" "also" "their" "them" "they"))

(define (tokenize s)
  (define lowered (string-downcase (or s "")))
  (define tset (mutable-set))
  (for ([w (in-list (regexp-match* #px"[a-z0-9]{3,}" lowered))]
        #:unless (set-member? stopwords w))
    (set-add! tset w))
  ;; CJK runs become character bigrams (single chars stay whole).
  (for ([run (in-list (regexp-match* #px"[一-龥]+" lowered))])
    (define cs (string->list run))
    (cond [(< (length cs) 2) (set-add! tset run)]
          [else
           (for ([i (in-range (sub1 (length cs)))])
             (set-add! tset (format "~a~a" (list-ref cs i) (list-ref cs (add1 i)))))]))
  tset)

;; Counting on lists instead of set-intersect/set-union: mutable-set
;; contract quirks across Racket versions make the generic set ops risky.
(define (jaccard a b)
  (define al (set->list a))
  (define inter (count (λ (x) (set-member? b x)) al))
  (define uni (+ (length al) (set-count b) (- inter)))
  ;; exact->inexact: (* 1.0 0) short-circuits to exact 0 in Racket.
  (if (zero? uni) 0.0 (exact->inexact (/ inter uni))))

;; ---- clustering ------------------------------------------------------------

;; Greedy single-pass clustering: newest first, join the most similar
;; existing group above the threshold, else start a new one.
(define (cluster-items items #:threshold [th 0.32])
  (define sorted
    (sort items > #:key (λ (i) (or (item-published i) 0)) #:cache-keys? #t))
  (define groups '())  ; list of (cons item-list token-set)
  (for ([it (in-list sorted)])
    (define toks (tokenize (string-append (item-title it) " " (item-summary it))))
    (define-values (best bs)
      (for/fold ([best #f] [bsim 0.0]) ([g (in-list groups)])
        (define s (jaccard toks (cdr g)))
        (if (> s bsim) (values g s) (values best bsim))))
    (if (and best (>= bs th))
        (begin
          (for ([x (in-set (cdr best))])
            (set-add! toks x))
          (set! groups
                (for/list ([g (in-list groups)])
                  (if (eq? g best)
                      (cons (cons it (car g)) toks)
                      g))))
        (set! groups (cons (cons (list it) toks) groups))))
  (map car groups))

;; ---- scoring ---------------------------------------------------------------

;; Tiered engineering lexicon: automotive software, functional safety,
;; automotive-grade silicon, ADAS.  Weights feed the cluster heat boost.
(define hot-terms
  (list
   ;; engineering core
   (cons "autosar" 1.2) (cons "iso 26262" 1.2) (cons "iso 21434" 1.2)
   (cons "iso26262" 1.2) (cons "aspice" 1.0) (cons "功能安全" 1.0)
   (cons "functional safety" 1.0) (cons "车规" 1.2) (cons "aec-q100" 1.0)
   (cons "汽车电子" 0.9) (cons "域控" 1.0) (cons "domain controller" 0.9)
   (cons "车载以太网" 1.0) (cons "can fd" 0.9) (cons "can bus" 0.7)
   (cons "soafee" 0.9) (cons "sdv" 0.7) (cons "qnx" 0.7) (cons "zephyr" 0.5)
   (cons "aurix" 0.8) (cons "rh850" 0.8) (cons "s32g" 0.8) (cons "orin" 0.7)
   (cons "thor" 0.5) (cons "snapdragon" 0.5) (cons "征程" 0.7) (cons "地平线" 0.6)
   (cons "ecu" 0.8) (cons "mcu" 0.8) (cons "芯片" 0.7) (cons "chip" 0.2)
   (cons "semiconductor" 0.4) (cons "晶圆" 0.5) (cons "车规soc" 1.0)
   ;; driving intelligence
   (cons "智驾" 1.0) (cons "智能驾驶" 1.0) (cons "autonomous driving" 0.9)
   (cons "self-driving" 0.8) (cons "adas" 0.9) (cons "robotaxi" 0.9)
   (cons "fsd" 0.6) (cons "noa" 0.6) (cons "行泊一体" 0.9) (cons "端到端" 0.5)
   (cons "lidar" 0.5) (cons "激光雷达" 0.6)
   ;; architecture / middleware / security engineering
   (cons "dds" 0.8) (cons "some/ip" 1.2) (cons "someip" 1.2) (cons "soa" 0.6)
   (cons "中间件" 0.6) (cons "middleware" 0.5) (cons "tsn" 0.8)
   (cons "车载以太网" 1.0) (cons "automotive ethernet" 1.0) (cons "ethernet" 0.3)
   (cons "信息安全" 1.0) (cons "网络安全" 0.9) (cons "cybersecurity" 1.0)
   (cons "security" 0.25) (cons "安全刷写" 1.2) (cons "secure flash" 1.0)
   (cons "安全启动" 0.9) (cons "secure boot" 0.9) (cons "刷写" 0.9)
   (cons "uds" 0.9) (cons "doip" 0.9) (cons "诊断" 0.4)
   (cons "中央计算" 0.9) (cons "central compute" 0.8) (cons "zonal" 0.8)
   (cons "区域架构" 0.9) (cons "e/e架构" 0.9) (cons "e/e 架构" 0.9)
   (cons "hpc" 0.4) (cons "iceoryx" 0.8) (cons "kuksa" 0.8) (cons "vsomeip" 1.0)
   (cons "covesa" 0.9) (cons "misra" 0.8) (cons "ota" 0.5)
   (cons "整车" 0.5) (cons "主机厂" 0.6) (cons "oem" 0.4) (cons "tier 1" 0.4)
   ;; general
   (cons "vehicle" 0.3) (cons "汽车" 0.3)
   (cons "battery" 0.2) (cons "电池" 0.3) (cons "charging" 0.2) (cons "充电" 0.2)
   (cons "召回" 0.4) (cons "recall" 0.3) (cons "收购" 0.3) (cons "merger" 0.2)))

(define (term-score s)
  (define lowered (string-downcase s))
  (for/sum ([tw (in-list hot-terms)]
            #:when (string-contains? lowered (car tw)))
    (cdr tw)))

(define (age-hours secs now)
  (if (not secs) 48.0 (/ (max 0 (- now secs)) 3600.0)))

(define (parse-extra-iso v)
  (and (string? v) (parse-date-any v)))

(define (item-weight it now)
  (match (item-kind it)
    ['github
     (define e (item-extra it))
     (define stars (let ([v (hash-ref e 'stars 0)]) (if (number? v) v 0)))
     (define created (parse-extra-iso (let ([v (hash-ref e 'created_at 'null)])
                                        (if (eq? v 'null) #f v))))
     ;; org-watch repos (AUTOSAR etc.) are first-party signal, star-sparse
     (define tier-boost (if (equal? (hash-ref e 'tier #f) 1) 1.5 0))
     (min 6.0
          (+ (* 1.5 (/ (log (+ 1.0 (max 0 stars))) (log 10.0)))
             (if (and created (< (- now created) (* 30 86400))) 3.0 0)
             (if (and (item-published it) (< (- now (item-published it)) (* 7 86400))) 1.0 0)
             tier-boost))]
    ['news
     (define w (let ([v (hash-ref (item-extra it) 'weight 1.0)])
                 (if (real? v) v 1.0)))
     (* 4.0 w (exp (- (/ (age-hours (item-published it) now) 60.0))))]
    ['paper
     (+ 1.5 (* 0.3 (min 6.0 (term-score (string-append (item-title it) " " (item-summary it))))))]
    [_ 1.0]))

;; ---- hot clusters ----------------------------------------------------------

(struct hot (items heat title summary labels domains newest first-seen) #:transparent #:mutable)

(define (rank-clusters item-groups #:now [now (current-seconds)])
  (define scored
    (for/list ([g (in-list item-groups)])
      (define domains (remove-duplicates (map item-source-url g)))
      (define newest (for/fold ([m 0]) ([it (in-list g)])
                       (max m (or (item-published it) 0))))
      (define age-h (age-hours (and (> newest 0) newest) now))
      (define wsum (for/sum ([it (in-list g)]) (item-weight it now)))
      ;; engineering-lexicon boost: best single item's term score, capped
      (define kw
        (for/fold ([m 0.0]) ([it (in-list g)])
          (max m (term-score (string-append (item-title it) " "
                                            (item-summary it))))))
      (define heat
        (* (+ 1.0 wsum)
           (+ 0.6 (* 0.4 (/ (min 4 (length domains)) 4.0)))
           (exp (- (/ age-h 48.0)))
           (+ 1.0 (* 0.12 (min 8.0 kw)))))
      (define labels '())
      (when (< age-h 24) (set! labels (cons 'new labels)))
      (when (and (>= (length domains) 2) (< age-h 18))
        (set! labels (cons 'rising labels)))
      ;; Display face of the cluster: the heaviest item carries the title.
      (define face (argmax (λ (it) (item-weight it now)) g))
      (hot g heat (item-title face) (item-summary face)
           labels (length domains) newest #f)))
  (sort scored > #:key hot-heat))

(define (hot->jsexpr h)
  (hasheq 'id (format "hot:~a" (equal-hash-code (hot-title h)))
          'heat (~r (hot-heat h) #:precision '(= 1))
          'labels (map symbol->string (hot-labels h))
          'domains (hot-domains h)
          'title (hot-title h)
          'summary (hot-summary h)
          'first_seen (jx (hot-first-seen h))
          'items (map item->jsexpr (hot-items h))))

;; ---- cross-day progress tracking -------------------------------------------

;; Canonical shape of a story: sorted token stream.  Two mentions of the
;; same event share the fingerprint (or sit at high Jaccard distance 0).
(define (event-fingerprint text)
  (string-join (sort (set->list (tokenize text)) string<?) " "))

;; history: hash fingerprint -> (cons token-list first-seen-date).
;; Marks clusters seen on earlier editions with the 进展 label.
(define (annotate-progress! hots history)
  (for ([h (in-list hots)])
    (define fp (event-fingerprint (string-append (hot-title h) " " (hot-summary h))))
    (define fp-toks (string-split fp " "))
    (let loop ([entries (hash-keys history)])
      (cond [(null? entries) (void)]
            [else
             (define key (car entries))
             (define toks (car (hash-ref history key)))
             (if (or (equal? key fp)
                     (>= (jaccard (list->set fp-toks) (list->set toks)) 0.55))
                 (begin
                   (set-hot-labels! h (cons 'progress (remq* '(progress) (hot-labels h))))
                   (set-hot-first-seen! h (cdr (hash-ref history key))))
                 (loop (cdr entries)))]))))
