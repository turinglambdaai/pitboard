#lang racket/base

;; Shared helpers: strings, HTML cleanup, dates, URLs.

(require racket/string
         racket/list
         racket/format
         racket/match
         racket/date
         net/url)

(provide collapse-ws
         strip-html
         truncate-s
         iso-date
         iso-datetime
         parse-8601
         parse-rfc822
         parse-date-any
         slug-domain
         normalize-url
         str-starts?
         str-ends?
         jx)

;; ---- strings ------------------------------------------------------------

(define (collapse-ws s)
  (string-trim (string-normalize-spaces s)))

(define entity-map
  '(("amp" . "&") ("lt" . "<") ("gt" . ">") ("quot" . "\"")
    ("apos" . "'") ("nbsp" . " ") ("hellip" . "…") ("mdash" . "—")
    ("ndash" . "–") ("rsquo" . "’") ("lsquo" . "‘")
    ("ldquo" . "“") ("rdquo" . "”") ("copy" . "©") ("reg" . "®")))

(define (decode-entities s)
  (define (code->str n)
    (with-handlers ([exn:fail? (λ (_) "")])
      (string (integer->char n))))
  (collapse-ws
   (regexp-replace*
    #px"&[A-Za-z][A-Za-z0-9]*;"
    (regexp-replace*
     #px"&#([0-9]+);"
     (regexp-replace* #px"&#x([0-9A-Fa-f]+);" s (λ (_all hex) (code->str (string->number hex 16))))
     (λ (_all dec) (code->str (string->number dec 10))))
    (λ (all)
      (define name (substring all 1 (sub1 (string-length all))))
      (cond [(assoc name entity-map) => cdr] [else all])))))

(define (strip-html s)
  (unless (string? s) (set! s (or (and s (format "~a" s)) "")))
  (decode-entities
   (regexp-replace*
    #px"<[^>]*>"
    (regexp-replace*
     #px"(?i:<script[^>]*>[\\s\\S]*?</script>)"
     (regexp-replace* #px"(?i:<style[^>]*>[\\s\\S]*?</style>)" s " ")
     " ")
    " ")))

(define (truncate-s s [n 300])
  (cond [(<= (string-length s) n) s]
        [else (string-append (substring s 0 n) "…")]))

(define (str-starts? s p)
  (and (>= (string-length s) (string-length p))
       (equal? (substring s 0 (string-length p)) p)))

(define (str-ends? s p)
  (and (>= (string-length s) (string-length p))
       (equal? (substring s (- (string-length s) (string-length p))) p)))

;; #f and missing values must become 'null before write-json.
(define (jx v)
  (if (not v) 'null v))

;; ---- dates (UTC everywhere) ----------------------------------------------

(define (pad2 n) (~r n #:min-width 2 #:pad-string "0"))

(define (iso-date [secs (current-seconds)])
  (define d (seconds->date secs #t))
  (format "~a-~a-~a" (date-year d) (pad2 (date-month d)) (pad2 (date-day d))))

(define (iso-datetime [secs (current-seconds)])
  (define d (seconds->date secs #t))
  (format "~a-~a-~aT~a:~a:~aZ"
          (date-year d) (pad2 (date-month d)) (pad2 (date-day d))
          (pad2 (date-hour d)) (pad2 (date-minute d)) (pad2 (date-second d))))

(define (tz-offset-seconds tz)
  (cond [(not tz) 0]
        [(regexp-match? #px"^[+-]\\d{2}:?\\d{2}$" tz)
         (define digits (regexp-replace* #px":" tz ""))
         (define sign (if (equal? (substring digits 0 1) "-") -1 1))
         (* sign (+ (* (string->number (substring digits 1 3)) 3600)
                    (* (string->number (substring digits 3 5)) 60)))]
        [else 0]))

(define (parse-8601 s)
  (define m (regexp-match
             #px"^(\\d{4})-(\\d{2})-(\\d{2})(?:[T ](\\d{2}):(\\d{2}):(\\d{2})(?:\\.\\d+)?)?\\s*(Z|[+-]\\d{2}:?\\d{2})?"
             (string-trim s)))
  (and m
       (let ([y (string->number (list-ref m 1))]
             [mo (string->number (list-ref m 2))]
             [d (string->number (list-ref m 3))]
             [h (string->number (or (list-ref m 4) "0"))]
             [mi (string->number (or (list-ref m 5) "0"))]
             [se (string->number (or (list-ref m 6) "0"))]
             [tz (list-ref m 7)])
         (- (find-seconds se mi h d mo y #t)
            (tz-offset-seconds (and tz (not (member (string-upcase tz) '("Z"))) tz))))))

(define month-num
  (for/hash ([m (in-list '("jan" "feb" "mar" "apr" "may" "jun"
                           "jul" "aug" "sep" "oct" "nov" "dec"))]
             [i (in-naturals 1)])
    (values m i)))

(define (parse-rfc822 s)
  (define m (regexp-match
             #px"^(?:\\w{3},\\s*)?(\\d{1,2})\\s+(\\w{3})\\s+(\\d{2,4})\\s+(\\d{2}):(\\d{2}):(\\d{2})\\s*([+-]\\d{4}|[A-Za-z]{1,5})?"
             (string-trim s)))
  (and m
       (let ([d (string->number (list-ref m 1))]
             [mo (hash-ref month-num (string-downcase (list-ref m 2)) #f)]
             [y (let ([v (string->number (list-ref m 3))])
                  (if (< v 100) (+ 2000 v) v))]
             [h (string->number (list-ref m 4))]
             [mi (string->number (list-ref m 5))]
             [se (string->number (list-ref m 6))]
             [tz (list-ref m 7)])
         (and mo
              (- (find-seconds se mi h d mo y #t)
                 (tz-offset-seconds tz))))))

(define (parse-date-any s)
  (and (string? s) (non-empty-string? (string-trim s))
       (or (parse-8601 s) (parse-rfc822 s))))

;; ---- urls -----------------------------------------------------------------

(define (slug-domain s)
  (with-handlers ([exn:fail? (λ (_) "unknown")])
    (define u (string->url s))
    (cond [(url-host u) => string-downcase]
          [else "unknown"])))

;; Drop tracking params and fragments so the same story from the same
;; outlet dedupes to one URL.  Query entries are (field . value) pairs.
(define (normalize-url s)
  (with-handlers ([exn:fail? (λ (_) s)])
    (define u (string->url s))
    (define (track? b)
      (define f (string-downcase (~a (car b))))
      (or (str-starts? f "utm_")
          (member f '("ref" "ref_src" "ref_url" "spm" "fbclid" "gclid"
                      "igshid" "guccounter" "cmpid" "sh"))))
    (define u2 (struct-copy url u
                            [query (for/list ([b (in-list (url-query u))]
                                              #:unless (track? b))
                                     b)]
                            [fragment #f]))
    (define s2 (url->string u2))
    (if (str-ends? s2 "/") (substring s2 0 (sub1 (string-length s2))) s2)))
