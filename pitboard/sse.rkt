#lang racket/base

;; Server-Sent Events: a tiny hub that fans out edition notifications and
;; keeps connections alive with heartbeats.  Encoding follows the WHATWG
;; SSE wire format (event/data lines, blank-line terminated).

(require racket/string
         racket/format
         racket/list
         json
         racket/file)

(provide make-hub
         hub-notify!
         hub-attach!
         hub-watch!
         hub-stream
         sse-encode
         dir-fingerprint)

(struct hub (sema clients-box payload-box) #:transparent)

(define (make-hub)
  (hub (make-semaphore) (box '()) (box #f)))

(define (sse-encode event data-string)
  (string-append "event: " event "\ndata: " data-string "\n\n"))

(define (hub-clients h) (unbox (hub-clients-box h)))

(define (hub-detach! h port)
  (when (memq port (hub-clients h))
    (set-box! (hub-clients-box h) (remq port (hub-clients h)))
    (with-handlers ([exn:fail? void])
      (close-output-port port))))

(define (safe-write h port s)
  (with-handlers ([exn:fail? (λ (_) (hub-detach! h port))])
    (display s port)
    (flush-output port)))

(define (hub-attach! h port)
  (set-box! (hub-clients-box h) (append (hub-clients h) (list port))))

(define (hub-notify! h payload-jsexpr)
  (set-box! (hub-payload-box h) payload-jsexpr)
  (define frame (sse-encode "edition" (jsexpr->string payload-jsexpr)))
  (for ([p (in-list (hub-clients h))])
    (safe-write h p frame))
  (semaphore-post (hub-sema h)))

;; Poll the directory contents (names + per-file mtimes); directory
;; mtime alone proved unreliable on APFS.  On change, notify the latest date.
(define (dir-fingerprint dir)
  (with-handlers ([exn:fail? (λ (_) "")])
    (string-append*
     (for/list ([p (in-list (directory-list dir))])
       (define mt
         (with-handlers ([exn:fail? (λ (_) 0)])
           (file-or-directory-modify-seconds (build-path dir p))))
       (format "~a:~a;" (path->string p) mt)))))

(define (hub-watch! h data-dir poll-seconds)
  (thread
   (λ ()
     (let loop ([last-fp (dir-fingerprint data-dir)])
       (sleep poll-seconds)
       (define fp (dir-fingerprint data-dir))
       (unless (equal? fp last-fp)
         (define d (latest-date-in data-dir))
         (when d
           (hub-notify! h (hasheq 'date d))))
       (loop fp)))))

(define (latest-date-in dir)
  (with-handlers ([exn:fail? (λ (_) #f)])
    (define ds
      (for/list ([p (in-list (directory-list dir))]
                 #:when (regexp-match? #px"\\.json$" (path->string p)))
        (regexp-replace #px"\\.json$" (path->string p) "")))
    (and (pair? ds) (car (sort ds string>?)))))

;; Long-lived response body: attach, replay last known payload, then
;; heartbeat every 15s until the client goes away.  A dead client makes
;; the next write raise, which detaches and ends this thread.
(define (hub-stream h port)
  (hub-attach! h port)
  (with-handlers ([exn:fail? (λ (_) (hub-detach! h port))])
    (display "retry: 5000\n\n" port)
    (flush-output port)
    (define last-payload (unbox (hub-payload-box h)))
    (when last-payload
      (display (sse-encode "edition" (jsexpr->string last-payload)) port)
      (flush-output port))
    (let loop ()
      (cond
        [(sync/timeout 0 (port-closed-evt port)) (hub-detach! h port)]
        [else
         (define hit (sync/timeout 15 (hub-sema h)))
         (if hit
             (let ([payload (unbox (hub-payload-box h))])
               (when payload
                 (display (sse-encode "edition" (jsexpr->string payload)) port)
                 (flush-output port)))
             (begin
               (display ": ping\n\n" port)
               (flush-output port)))
         (loop)]))))
