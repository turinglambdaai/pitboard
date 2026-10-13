#lang racket/base

(require rackunit
         racket/file
         racket/string
         racket/list
         racket/runtime-path
         "../feed.rkt"
         "../item.rkt")

(define-runtime-path rss-sample.xml "rss-sample.xml")
(define-runtime-path atom-sample.xml "atom-sample.xml")

(define rss-bytes (file->bytes rss-sample.xml))
(define atom-bytes (file->bytes atom-sample.xml))

(test-case "rss 2.0"
  (define items (parse-rss rss-bytes #:source-name "Test" #:weight 1.2))
  (check-equal? (length items) 2)   ; link-less item dropped
  (define a (first items))
  (check-equal? (item-title a) "Solid-state battery breakthrough at &scale")
  (check-false (string-contains? (item-url a) "utm_"))
  (check-true (string-contains? (item-url a) "id=1"))
  (check-false (string-contains? (item-summary a) "<b>"))
  (check-true (string-contains? (item-summary a) "solid-state batteries"))
  (check-equal? (item-source a) "Test")
  (check-equal? (item-source-url a) "example.com")
  (check-true (number? (item-published a)))
  (check-equal? (item-kind a) 'news))

(test-case "atom"
  (define items (parse-atom atom-bytes #:source-name "arXiv" #:kind 'paper))
  (check-equal? (length items) 2)
  (check-equal? (item-url (first items)) "http://arxiv.org/abs/2026.12345v1")
  (check-equal? (item-kind (first items)) 'paper)
  (check-equal? (item-url (second items)) "http://right.example")
  (check-true (number? (item-published (first items))))
  (check-true (number? (item-published (second items))))) ; falls back to <updated>

(test-case "parse-feed sniffing"
  (check-equal? (length (parse-feed rss-bytes #:source-name "x")) 2)
  (check-equal? (length (parse-feed atom-bytes #:source-name "x")) 2)
  (check-equal? (parse-feed #"this is not xml" #:source-name "x") '()))
