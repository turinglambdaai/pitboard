#lang racket/base

;; Optional LLM pass: rewrite the top clusters' titles/summaries into
;; Chinese via any OpenAI-compatible chat endpoint.  Every failure mode
;; degrades to the plain ranked mode — the site never depends on this.

(require racket/string
         racket/list
         racket/format
         racket/match
         racket/port
         json
         net/http-easy)

(provide llm-available?
         llm-base
         llm-model
         llm-polish!)

;; ---- config ---------------------------------------------------------------

(define (llm-key) (getenv "PITBOARD_LLM_API_KEY"))
(define (llm-base) (or (getenv "PITBOARD_LLM_BASE_URL") "https://api.deepseek.com"))
(define (llm-model) (or (getenv "PITBOARD_LLM_MODEL") "deepseek-chat"))

(define (llm-available?) (and (llm-key) #t))

;; ---- request --------------------------------------------------------------

(define (chat-completions prompt)
  (define ch (make-channel))
  (thread
   (λ ()
     (with-handlers ([exn:fail? (λ (e) (channel-put ch (cons 'err (exn-message e))))])
       (define r
         (post (string-append (llm-base) "/chat/completions")
               #:headers (hasheq 'Authorization (string-append "Bearer " (llm-key))
                                 'Content-Type "application/json")
               #:data
               (jsexpr->bytes
                (hasheq 'model (llm-model)
                        'temperature 0.2
                        'messages (list (hasheq 'role "user" 'content prompt))))))
       (when (>= (response-status-code r) 400)
         (error 'llm "HTTP ~a" (response-status-code r)))
       (channel-put ch (cons 'ok (with-input-from-bytes (response-body r) read-json))))))
  (define v (sync/timeout 120 ch))
  (cond [(not v) (error 'llm "timeout")]
        [(eq? (car v) 'err) (error 'llm (cdr v))]
        [else (cdr v)]))

;; ---- polish ---------------------------------------------------------------

;; entries: list of (cons index (cons title summary)).
;; Returns (hash index => (cons title summary)).
(define (llm-polish! entries)
  (define out (make-hash))
  (with-handlers ([exn:fail? (λ (_) out)])
    (define input
      (for/list ([e (in-list entries)])
        (hasheq 'i (car e)
                'title (car (cdr e))
                'summary (cdr (cdr e)))))
    (define prompt
      (string-append
       "你是汽车行业日报编辑。下面是 JSON 数组，每项含 i（编号）、title（标题）、summary（摘要）。"
       "为每一项输出中文标题 title_zh（不超过30字，专有名词保留英文）"
       "和中文摘要 summary_zh（不超过80字，两句话）。"
       "只输出一个 JSON 对象：{\"items\":[{\"i\":0,\"title_zh\":\"…\",\"summary_zh\":\"…\"}]}，不要任何其他文字。\n"
       "输入：" (jsexpr->string input)))
    (define resp (chat-completions prompt))
    (define content
      (let* ([choices (hash-ref resp 'choices '())]
             [first (and (pair? choices) (car choices))]
             [msg (and first (hash-ref first 'message #f))])
        (and msg (hash-ref msg 'content ""))))
    (when (string? content)
      (define m (regexp-match #px"\\{.*\\}" content))
      (when m
        (define parsed
          (with-handlers ([exn:fail? (λ (_) #f)])
            (with-input-from-string (car m) read-json)))
        (when (hash? parsed)
          (for ([it (in-list (hash-ref parsed 'items '()))]
                #:when (hash? it))
            (define i (hash-ref it 'i #f))
            (define tz (hash-ref it 'title_zh #f))
            (define sz (hash-ref it 'summary_zh #f))
            (when (and (integer? i) (string? tz))
              (hash-set! out i (cons tz (or (and (string? sz) sz) ""))))))))
    out))
