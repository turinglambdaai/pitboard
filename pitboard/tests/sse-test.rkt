#lang racket/base

(require rackunit
         racket/string
         json
         "../sse.rkt")

(test-case "sse frame encoding"
  (check-equal? (sse-encode "edition" "{\"a\":1}")
                "event: edition\ndata: {\"a\":1}\n\n")
  (check-true (regexp-match? #px"\n\n$" (sse-encode "ping" "x"))))

(test-case "hub fanout"
  (define h (make-hub))
  (define-values (rin rout) (make-pipe))
  (hub-attach! h rout)
  (hub-notify! h (hasheq 'date "2026-10-13"))
  (define line1 (read-line rin))
  (define line2 (read-line rin))
  (check-equal? line1 "event: edition")
  (check-true (string-prefix? line2 "data: "))
  (check-true (string-contains? line2 "2026-10-13")))
