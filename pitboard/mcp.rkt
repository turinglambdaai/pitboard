#lang racket/base

;; Minimal MCP (Model Context Protocol) server over stdio: newline-delimited
;; JSON-RPC 2.0.  Exposes pitboard's archive as agent-callable tools.

(require racket/string
         racket/list
         racket/match
         racket/format
         racket/file
         racket/port
         json
         "store.rkt"
         "render.rkt")

(provide handle-mcp-request
         run-mcp-server)

;; ---- tool implementations ---------------------------------------------------

(define (summary-of digest)
  (define clusters (hash-ref digest 'clusters '()))
  (string-append*
   (list*
    (format "pitboard ~a · ~a 个热点 · 模式 ~a\n\n"
            (v (hash-ref digest 'date ""))
            (length clusters) (v (hash-ref digest 'mode "scored")))
    (for/list ([c (in-list (take clusters (min 15 (length clusters))))]
               [i (in-naturals)])
      (format "~a. [热度 ~a] ~a\n   ~a\n"
              (add1 i) (hash-ref c 'heat "0")
              (v (hash-ref c 'title ""))
              (first-item-url-of c))))))

(define (first-item-url-of c)
  (define items (hash-ref c 'items '()))
  (if (null? items) "" (v (hash-ref (car items) 'url ""))))

(define (handle-mcp-request req data-dir)
  (define id (hash-ref req 'id 0))
  (define method (hash-ref req 'method ""))
  (define params (hash-ref req 'params (hasheq)))
  (define (result r) (hasheq 'jsonrpc "2.0" 'id id 'result r))
  (define (err code msg)
    (hasheq 'jsonrpc "2.0" 'id id
            'error (hasheq 'code code 'message msg)))
  (with-handlers ([exn:fail? (λ (e) (err -32603 (exn-message e)))])
    (match method
      ["initialize"
       (result (hasheq 'protocolVersion "2024-11-05"
                       'capabilities (hasheq 'tools (hasheq))
                       'serverInfo (hasheq 'name "pitboard" 'version "0.1.0")))]
      ["notifications/initialized" #f]
      ["tools/list"
       (result
        (hasheq
         'tools
         (list
          (hasheq 'name "latest_digest"
                  'description "今日/最新一期的汽车行业热点榜（AUTOSAR、智驾、车规芯片等）"
                  'inputSchema (hasheq 'type "object" 'properties (hasheq)))
          (hasheq 'name "get_edition"
                  'description "取指定日期的完整日报"
                  'inputSchema
                  (hasheq 'type "object"
                          'properties (hasheq 'date (hasheq 'type "string"
                                                            'description "YYYY-MM-DD"))
                          'required (list "date")))
          (hasheq 'name "get_topic"
                  'description "按话题追踪（如 AUTOSAR、SOME/IP、信息安全、功能安全、UDS）"
                  'inputSchema
                  (hasheq 'type "object"
                          'properties (hasheq 'topic (hasheq 'type "string"))
                          'required (list "topic"))))))]

      ["tools/call"
       (define name (hash-ref params 'name ""))
       (define args (hash-ref params 'arguments (hasheq)))
       (define text
         (match name
           ["latest_digest"
            (define dg (latest-digest data-dir))
            (if dg (summary-of dg) "尚无出刊")]
           ["get_edition"
            (define dg (load-digest data-dir (~a (hash-ref args 'date ""))))
            (if dg (summary-of dg) (format "无 ~a 的出刊" (hash-ref args 'date)))]
           ["get_topic"
            (define term (~a (hash-ref args 'topic "")))
            (define rows (collect-topic-items data-dir term))
            (string-append*
             (format "话题「~a」共 ~a 条（近 100 条）：\n" term (length rows))
             (for/list ([row (in-list (take rows (min 20 (length rows))))])
               (format "- [~a] ~a\n  ~a\n"
                       (car row)
                       (v (hash-ref (cdr row) 'title ""))
                       (v (hash-ref (cdr row) 'url "")))))]
           [_ (format "未知工具: ~a" name)]))
       (result (hasheq 'content (list (hasheq 'type "text" 'text text))))]
      ["ping" (result (hasheq))]
      [_ (err -32601 (format "method not found: ~a" method))])))

;; id-less notifications get no response.
(define (run-mcp-server #:data-dir [data-dir "data"])
  (let loop ()
    (define line (read-line))
    (unless (eof-object? line)
      (define req
        (with-handlers ([exn:fail? (λ (_) #f)])
          (with-input-from-string line read-json)))
      (when (hash? req)
        (define resp (handle-mcp-request req data-dir))
        (when resp
          (write-string (jsexpr->string resp))
          (newline)
          (flush-output)))
      (loop))))
