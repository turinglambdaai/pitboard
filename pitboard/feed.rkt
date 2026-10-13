#lang racket/base

;; RSS 2.0 + Atom parsing on top of the stdlib xml package.
;; Pure: bytes in, items out.  No network here.

(require xml
         racket/string
         racket/list
         racket/match
         "util.rkt"
         "item.rkt")

(provide parse-feed
         parse-rss
         parse-atom
         xexpr-from-bytes)

;; ---- xexpr navigation -----------------------------------------------------

(define (xexpr-from-bytes b)
  (with-handlers ([exn:fail? (λ (_) #f)])
    (define doc (read-xml (open-input-bytes b)))
    (xml->xexpr (document-element doc))))

(define (tag? x n)
  (and (pair? x) (symbol? (car x)) (eq? (car x) n)))

;; Tolerate namespace prefixes like 'content:encoded'.
(define (tag-suffix? x n)
  (and (pair? x) (symbol? (car x))
       (let ([s (symbol->string (car x))])
         (or (eq? (car x) n)
             (str-ends? s (string-append ":" (symbol->string n)))))))

(define (elem-children x)
  (for/list ([c (in-list (cddr x))]
             #:when (and (pair? c) (symbol? (car c))))
    c))

(define (text-of x)
  (string-append*
   (for/list ([c (in-list (cddr x))])
     (cond [(string? c) c]
           [(cdata? c) (cdata-string c)]
           [(pair? c) (text-of c)]
           [else ""]))))

(define (find-child n x)
  (findf (λ (c) (tag-suffix? c n)) (elem-children x)))

(define (child-text x n)
  (define c (find-child n x))
  (and c (text-of c)))

(define (attr-of x n)
  (define attrs (cadr x))
  (for/first ([av (in-list attrs)] #:when (eq? (car av) n)) (cadr av)))

(define (first-n l n)
  (take l (min (length l) n)))

(define max-entries 80)

;; ---- item assembly --------------------------------------------------------

(define (make kind w name title link summary published)
  (define u (and (string? link) (non-empty-string? (string-trim link))
                 (normalize-url (string-trim link))))
  (and u
       (string? title) (non-empty-string? (string-trim title))
       (item (make-item-id kind u)
             kind
             name
             (slug-domain u)
             (string-trim title)
             u
             (truncate-s (strip-html (or summary "")) 500)
             published
             (hasheq 'weight w))))

(define (parse-rss b #:source-name name #:kind [kind 'news] #:weight [w 1.0])
  (define root (xexpr-from-bytes b))
  (define ch (and root (find-child 'channel root)))
  (if (not ch)
      '()
      (filter
       values
       (for/list ([it (in-list (first-n (filter (λ (c) (tag? c 'item)) (elem-children ch)) max-entries))])
         (make kind w name
               (child-text it 'title)
               (child-text it 'link)
               (or (child-text it 'description) (child-text it 'content:encoded))
               (parse-date-any (or (child-text it 'pubDate) (child-text it 'dc:date))))))))

(define (atom-link it)
  (or (for/first ([c (in-list (elem-children it))]
                  #:when (tag? c 'link)
                  #:unless (let ([rel (attr-of c 'rel)])
                             (and rel (not (equal? rel "alternate")))))
        (attr-of c 'href))
      (for/first ([c (in-list (elem-children it))] #:when (tag? c 'link))
        (attr-of c 'href))))

(define (parse-atom b #:source-name name #:kind [kind 'news] #:weight [w 1.0])
  (define root (xexpr-from-bytes b))
  (if (not root)
      '()
      (filter
       values
       (for/list ([it (in-list (first-n (filter (λ (c) (tag? c 'entry)) (elem-children root)) max-entries))])
         (make kind w name
               (child-text it 'title)
               (atom-link it)
               (or (child-text it 'summary) (child-text it 'content))
               (parse-date-any (or (child-text it 'published) (child-text it 'updated))))))))

;; Entry point: sniffs Atom vs RSS 2.0.  Returns a list of items.
(define (parse-feed b #:source-name name #:kind [kind 'news] #:weight [w 1.0])
  (define root (xexpr-from-bytes b))
  (cond [(not root) '()]
        [(and (pair? root) (eq? (car root) 'feed))
         (parse-atom b #:source-name name #:kind kind #:weight w)]
        [else (parse-rss b #:source-name name #:kind kind #:weight w)]))
