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

(define hot-terms
  (list "固态电池" "robotaxi" "l3" "adas" "fsd" "自动驾驶" "智能驾驶" "智驾"
        "autonomous" "self-driving" "召回" "recall" "电池" "battery"
        "charging" "充电" "车规" "芯片" "chip" "v2x" "800v"
        "收购" "合并" "merger" "acquisition" "iso 26262" "iso 21434"
        "autosar" "撞车" "事故"))

(define (term-count s)
  (define lowered (string-downcase s))
  (for/sum ([t (in-list hot-terms)]
            #:when (string-contains? lowered t))
    1))

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
     (min 12.0
          (+ (* 2.0 (/ (log (+ 1.0 (max 0 stars))) (log 10.0)))
             (if (and created (< (- now created) (* 30 86400))) 3.0 0)
             (if (and (item-published it) (< (- now (item-published it)) (* 7 86400))) 1.0 0)))]
    ['news
     (define w (let ([v (hash-ref (item-extra it) 'weight 1.0)])
                 (if (real? v) v 1.0)))
     (* w (exp (- (/ (age-hours (item-published it) now) 60.0))))]
    ['paper
     (+ 1.5 (* 0.25 (term-count (string-append (item-title it) " " (item-summary it)))))]
    [_ 1.0]))

;; ---- hot clusters ----------------------------------------------------------

(struct hot (items heat title summary labels domains newest) #:transparent #:mutable)

(define (rank-clusters item-groups #:now [now (current-seconds)])
  (define scored
    (for/list ([g (in-list item-groups)])
      (define domains (remove-duplicates (map item-source-url g)))
      (define newest (for/fold ([m 0]) ([it (in-list g)])
                       (max m (or (item-published it) 0))))
      (define age-h (age-hours (and (> newest 0) newest) now))
      (define wsum (for/sum ([it (in-list g)]) (item-weight it now)))
      (define heat
        (* (+ 1.0 wsum)
           (+ 0.6 (* 0.4 (/ (min 4 (length domains)) 4.0)))
           (exp (- (/ age-h 48.0)))))
      (define labels '())
      (when (< age-h 24) (set! labels (cons 'new labels)))
      (when (and (>= (length domains) 2) (< age-h 18))
        (set! labels (cons 'rising labels)))
      ;; Display face of the cluster: the heaviest item carries the title.
      (define face (argmax (λ (it) (item-weight it now)) g))
      (hot g heat (item-title face) (item-summary face)
           labels (length domains) newest)))
  (sort scored > #:key hot-heat))

(define (hot->jsexpr h)
  (hasheq 'id (format "hot:~a" (equal-hash-code (hot-title h)))
          'heat (~r (hot-heat h) #:precision '(= 1))
          'labels (map symbol->string (hot-labels h))
          'domains (hot-domains h)
          'title (hot-title h)
          'summary (hot-summary h)
          'items (map item->jsexpr (hot-items h))))
