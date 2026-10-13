#lang racket/base

;; `raco pitboard` entry point: fetch / serve / export.

(require racket/cmdline
         racket/vector
         (only-in "sources.rkt" default-watch-topics)
         racket/match
         racket/list
         racket/string
         racket/format
         "util.rkt"
         "sources.rkt"
         "score.rkt"
         "store.rkt"
         "llm.rkt"
         "app.rkt"
         "export.rkt")

(provide cli-main)

;; watch topics from config (or the built-in default)
(define (watch-topics config-path)
  (define cfg (load-config config-path))
  (define v (hash-ref cfg 'watch_topics #f))
  (if (and (list? v) (pair? v))
      (for/list ([x (in-list v)]) (~a x))
      default-watch-topics))

;; ---- pipeline --------------------------------------------------------------

(define (run-fetch date-override data-dir config-path use-llm?)
  (define now (current-seconds))
  (define date (or date-override (iso-date now)))
  (define cfg (load-config config-path))
  (printf "pitboard fetch · ~a\n" date)
  (define-values (items statuses) (fetch-all cfg))
  (printf "  条目 ~a · 信源状态：\n" (length items))
  (for ([s (in-list statuses)])
    (printf "    [~a] ~a · ~a 条~a\n"
            (if (source-status-ok s) "ok" "失败")
            (source-status-name s)
            (source-status-count s)
            (let ([m (source-status-message s)])
              (if m (format " · ~a" m) ""))))
  (define hots (rank-clusters (cluster-items items) #:now now))
  (printf "  聚簇 → ~a 个热点\n" (length hots))
  (define mode "scored")
  (when (and use-llm? (llm-available?) (pair? hots))
    (define top (take hots (min 15 (length hots))))
    (define entries
      (for/list ([h (in-list top)] [i (in-naturals)])
        (cons i (cons (hot-title h) (hot-summary h)))))
    (printf "  LLM 增强 ~a 条头条（~a / ~a）…\n"
            (length entries) (llm-base) (llm-model))
    (define zh (llm-polish! entries))
    (unless (zero? (hash-count zh))
      (set! mode "llm")
      (for ([(i ts) (in-hash zh)] #:when (< i (length top)))
        (set-hot-title! (list-ref top i) (car ts))
        (set-hot-summary! (list-ref top i) (cdr ts)))
      (printf "  LLM 改写 ~a 条\n" (hash-count zh))))
  (define j (digest->jsexpr date mode hots statuses now))
  (save-digest! data-dir j)
  (printf "  出刊 → ~a\n" (path->string (data-file data-dir date))))

;; ---- subcommands -----------------------------------------------------------

(define (fetch-cmd)
  (define date-ov (make-parameter #f))
  (define dir (make-parameter "data"))
  (define cfgp (make-parameter #f))
  (define no-llm (make-parameter #f))
  (command-line
   #:program "raco pitboard fetch"
   #:once-each
   [("--date") d "出刊日期 YYYY-MM-DD（默认今天 UTC）" (date-ov d)]
   [("--data") p "数据目录（默认 data/）" (dir p)]
   [("--config") p "信源配置 JSON（默认内置）" (cfgp p)]
   [("--no-llm") "跳过 LLM 增强" (no-llm #t)]
   #:args _ (void))
  (run-fetch (date-ov) (dir) (cfgp) (not (no-llm))))

(define (serve-cmd)
  (define port-p (make-parameter 8090))
  (define dir (make-parameter "data"))
  (define assets-p (make-parameter "assets"))
  (command-line
   #:program "raco pitboard serve"
   #:once-each
   [("--port") n "监听端口（默认 8090）" (port-p (string->number n))]
   [("--data") p "数据目录（默认 data/）" (dir p)]
   [("--assets") p "静态资源目录（默认 assets/）" (assets-p p)]
   #:args _ (void))
  (start-server #:port (port-p) #:data-dir (dir) #:assets-dir (assets-p)
                #:topics (watch-topics #f)))

(define (export-cmd)
  (define out-p (make-parameter "site"))
  (define dir (make-parameter "data"))
  (define assets-p (make-parameter "assets"))
  (define domain-p (make-parameter "pitboard.jrtx.site"))
  (define base-p (make-parameter "https://pitboard.jrtx.site"))
  (command-line
   #:program "raco pitboard export"
   #:once-each
   [("--out") p "输出目录（默认 site/）" (out-p p)]
   [("--data") p "数据目录（默认 data/）" (dir p)]
   [("--assets") p "静态资源目录（默认 assets/）" (assets-p p)]
   [("--domain") d "CNAME 域名" (domain-p d)]
   [("--base-url") u "绝对地址前缀" (base-p u)]
   #:args _ (void))
  (define n
    (export-site #:data-dir (dir) #:out (out-p) #:assets-dir (assets-p)
                 #:domain (domain-p) #:base-url (base-p)
                 #:topics (watch-topics #f)))
  (printf "export: ~a 个文件 → ~a\n" n (out-p)))

;; ---- dispatch ---------------------------------------------------------------

(define (print-usage)
  (printf "pitboard — 汽车行业每日热点日报站\n\n用法：\n~a\n~a\n~a\n"
          "  raco pitboard fetch [--date D] [--data DIR] [--config FILE] [--no-llm]"
          "  raco pitboard serve [--port N] [--data DIR] [--assets DIR]"
          "  raco pitboard export [--out DIR] [--data DIR] [--domain D] [--base-url U]"))

(define (cli-main [argv (current-command-line-arguments)])
  (define cmd (if (zero? (vector-length argv)) "help" (vector-ref argv 0)))
  (define rest-args
    (if (zero? (vector-length argv)) #() (vector-drop argv 1)))
  (current-command-line-arguments rest-args)
  (match cmd
    ["fetch" (fetch-cmd)]
    ["serve" (serve-cmd)]
    ["export" (export-cmd)]
    [_ (print-usage)
       (unless (equal? cmd "help") (exit 1))]))
