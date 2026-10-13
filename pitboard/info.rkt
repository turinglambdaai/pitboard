#lang info

(define collection "pitboard")
(define version "0.1.0")
(define deps '("base" "http-easy" "web-server-lib" "server-sent-events" "feed"))
(define build-deps '("base" "rackunit-lib" "scribble-lib" "racket-doc"))
(define scribblings '(("scribblings/pitboard.scrbl" ())))
(define pkg-desc "Automotive industry daily digest: fetch, score, cluster, publish")
(define pkg-authors '(turinglambdaai))
(define raco-commands
  '(("pitboard" pitboard/raco-pitboard "automotive daily digest: fetch / serve / export" #f)))
(define test-omit-paths '("raco-pitboard.rkt" "scribblings"))
