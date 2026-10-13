#lang racket/base

(require rackunit
         racket/date
         "../util.rkt")

(test-case "strip-html + entities"
  (check-equal? (strip-html "<p>A &amp; B <b>bold</b> text</p>") "A & B bold text")
  (check-equal? (strip-html "<script>evil()</script>kept") "kept")
  (check-equal? (strip-html "x&#39;s &#x201C;q&#x201D;") "x's “q”")
  (check-equal? (strip-html "multi\n  space\t text") "multi space text")
  (check-equal? (strip-html "&unknown; stays") "&unknown; stays"))

(test-case "iso-8601"
  (define z (parse-8601 "2026-10-13T09:00:00Z"))
  (check-equal? z (find-seconds 0 0 9 13 10 2026 #t))
  (check-equal? (parse-8601 "2026-10-13T11:00:00+02:00") (- z 0)) ; 09:00Z
  (check-equal? (parse-8601 "2026-10-13T08:30:00+0200") (find-seconds 0 30 6 13 10 2026 #t))
  (check-equal? (parse-8601 "2026-10-13") (find-seconds 0 0 0 13 10 2026 #t))
  (check-false (parse-8601 "not a date"))
  (check-false (parse-date-any #f)))

(test-case "rfc822"
  (check-equal? (parse-rfc822 "Tue, 13 Oct 2026 08:30:00 +0200")
                (find-seconds 0 30 6 13 10 2026 #t))
  (check-equal? (parse-rfc822 "13 Oct 2026 06:00:00 GMT")
                (find-seconds 0 0 6 13 10 2026 #t)))

(test-case "dates out"
  (check-equal? (iso-date (find-seconds 0 30 6 13 10 2026 #t)) "2026-10-13")
  (check-true (str-ends? (iso-datetime (find-seconds 0 30 6 13 10 2026 #t)) "Z")))

(test-case "urls"
  (check-equal? (normalize-url "https://example.com/a?utm_source=x&id=1#frag")
                "https://example.com/a?id=1")
  (check-equal? (slug-domain "https://WWW.Example.com/p/1") "www.example.com")
  (check-equal? (truncate-s "abcdef" 4) "abcd…"))
