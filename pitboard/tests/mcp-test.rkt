#lang racket/base

(require rackunit
         racket/string
         json
         "../mcp.rkt")

(test-case "mcp initialize + tools/call"
  (define init
    (handle-mcp-request (hasheq 'jsonrpc "2.0" 'id 1 'method "initialize"
                                'params (hasheq))
                        "/nonexistent"))
  (check-equal? (hash-ref init 'id) 1)
  (check-equal? (hash-ref (hash-ref (hash-ref init 'result) 'serverInfo) 'name) "pitboard")

  (define tools
    (handle-mcp-request (hasheq 'jsonrpc "2.0" 'id 2 'method "tools/list"
                                'params (hasheq))
                        "/nonexistent"))
  (define names
    (for/list ([t (in-list (hash-ref (hash-ref tools 'result) 'tools))])
      (hash-ref t 'name)))
  (check-true (and (member "latest_digest" names) #t))
  (check-true (and (member "get_topic" names) #t))

  (define bad
    (handle-mcp-request (hasheq 'jsonrpc "2.0" 'id 3 'method "nope"
                                'params (hasheq))
                        "/nonexistent"))
  (check-equal? (hash-ref (hash-ref bad 'error) 'code) -32601))
