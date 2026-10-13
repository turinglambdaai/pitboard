#lang racket/base

;; Shared helpers: strings, HTML cleanup, dates, URLs.

(require racket/string
         racket/list
         racket/format
         racket/match
         racket/date
         net/url
         (only-in feed parse-8601 parse-rfc822 parse-date-any))

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
;; Parsing lives in the feed package; util re-exports it (see require).

(define (pad2 n) (~r n #:min-width 2 #:pad-string "0"))

(define (iso-date [secs (current-seconds)])
  (define d (seconds->date secs #t))
  (format "~a-~a-~a" (date-year d) (pad2 (date-month d)) (pad2 (date-day d))))

(define (iso-datetime [secs (current-seconds)])
  (define d (seconds->date secs #t))
  (format "~a-~a-~aT~a:~a:~aZ"
          (date-year d) (pad2 (date-month d)) (pad2 (date-day d))
          (pad2 (date-hour d)) (pad2 (date-minute d)) (pad2 (date-second d))))

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
