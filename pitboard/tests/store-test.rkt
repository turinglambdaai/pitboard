#lang racket/base

(require rackunit
         racket/file
         racket/list
         racket/path
         json
         "../store.rkt"
         "../score.rkt"
         "../item.rkt")

(test-case "store roundtrip"
  (define dir (make-temporary-file "pitboard-store-~a" 'directory))
  (dynamic-wind
   (λ () (void))
   (λ ()
     (check-equal? (list-dates dir) '())
     (check-false (latest-digest dir))
     (define j (hasheq 'date "2026-10-13" 'mode "scored"
                       'generated_at "2026-10-13T00:00:00Z"
                       'clusters '() 'sources '()))
     (save-digest! dir j)
     (save-digest! dir (hasheq 'date "2026-10-12" 'mode "scored"
                               'generated_at "x" 'clusters '() 'sources '()))
     (check-equal? (list-dates dir) '("2026-10-13" "2026-10-12"))
     (define back (load-digest dir "2026-10-13"))
     (check-equal? (hash-ref back 'date) "2026-10-13")
     (check-equal? (hash-ref (latest-digest dir) 'date) "2026-10-13"))
   (λ () (delete-directory/files dir))))

(test-case "digest->jsexpr"
  (define it (item "x:1" 'news "S" "example.com" "T" "https://example.com/t" "sum"
                   1791878400 (hasheq 'weight 1.0)))
  (define h (rank-clusters (cluster-items (list it)) #:now 1791888400))
  (define j (digest->jsexpr "2026-10-13" "scored" h '()))
  (check-equal? (hash-ref j 'date) "2026-10-13")
  (check-equal? (hash-ref j 'mode) "scored")
  (check-equal? (length (hash-ref j 'clusters)) 1)
  ;; must be write-json safe end to end
  (check-true (bytes? (jsexpr->bytes j))))
