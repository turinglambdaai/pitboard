#lang racket/base

(require rackunit
         racket/set
         racket/list
         "../score.rkt"
         "../item.rkt")

(test-case "tokenize"
  (define t (tokenize "Solid-State Battery Breakthrough 固态电池来了"))
  (check-true (set-member? t "solid"))
  (check-true (set-member? t "battery"))
  (check-false (set-member? t "the"))
  (check-true (set-member? t "固态"))
  (check-true (set-member? t "态电"))
  (check-true (set-member? t "电池"))
  (check-false (set-member? t "固态电池来了"))
  (check-equal? (jaccard (tokenize "toyota solid state battery")
                         (tokenize "toyota solid state battery"))
                1.0)
  (check-equal? (jaccard (tokenize "alpha beta") (tokenize "gamma delta")) 0.0)
  (check-true (real? (jaccard (tokenize "alpha beta") (tokenize "gamma delta")))))

(define (mk id title summary kind url pub extra)
  (item id kind "src" (second (regexp-match #px"https://([^/]+)" url))
        title url summary pub extra))

(define now 1791878400) ; fixed "today"
(define now2 (current-seconds))

(test-case "clustering"
  (define items
    (list
     (mk "1" "Toyota doubles solid-state battery range" "toyota says range doubles"
         'news "https://a.com/1" (- now 3600) (hasheq 'weight 1.0))
     (mk "2" "Toyota says solid-state battery range doubles" "announcement today"
         'news "https://b.com/2" (- now 3600) (hasheq 'weight 1.0))
     (mk "3" "Unrelated: F1 race results" "someone won a race"
         'news "https://c.com/3" (- now 7200) (hasheq 'weight 1.0))))
  (define groups (cluster-items items))
  (check-equal? (length groups) 2)
  (define biggest (argmax length groups))
  (check-equal? (length biggest) 2))

(test-case "rank + labels"
  (define items
    (list
     ;; one multi-source, fresh story
     (mk "1" "NHTSA opens recall of ADAS module" "recall of adas module announced"
         'news "https://x.com/1" (- now2 3600) (hasheq 'weight 1.0))
     (mk "2" "ADAS module recall announced by NHTSA" "the recall covers modules"
         'news "https://y.com/2" (- now2 7200) (hasheq 'weight 1.0))
     ;; one old, single-source story
     (mk "3" "Ancient charging standard history" "old charging text"
         'news "https://z.com/3" (- now2 (* 96 3600)) (hasheq 'weight 1.0))))
  (define hots (rank-clusters (cluster-items items) #:now now2))
  (check-equal? (length hots) 2)
  (check-equal? (length (hot-items (first hots))) 2)
  (check-true (> (hot-heat (first hots)) (hot-heat (second hots))))
  (check-not-false (memq 'new (hot-labels (first hots))))
  (check-not-false (memq 'rising (hot-labels (first hots))))
  (check-false (memq 'new (hot-labels (second hots))))
  (check-equal? (hot-domains (first hots)) 2)
  (define j (hot->jsexpr (first hots)))
  (check-equal? (hash-ref j 'domains) 2)
  (check-true (string? (hash-ref j 'title)))
  (check-equal? (length (hash-ref j 'items)) 2))

(test-case "github weight beats stale news"
  (define items
    (list
     (mk "g" "commaai/openpilot" "open source driver assistance"
         'github "https://github.com/a/b" (- now2 (* 2 3600))
         (hasheq 'stars 50000 'created_at "2020-01-01T00:00:00Z"))
     (mk "n" "minor note" "tiny news"
         'news "https://n.com/1" (- now2 (* 60 3600)) (hasheq 'weight 0.5))))
  (define hots (rank-clusters (cluster-items items) #:now now2))
  (check-equal? (item-kind (car (hot-items (first hots)))) 'github))
