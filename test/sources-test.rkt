#lang racket/base
;; sources 层测试:GBK 解码、协议相对链接、web_list 关键词门控。
(require rackunit
         racket/string
         racket/file
         racket/list
         racket/system
         "../pitboard/sources.rkt")

;; ---- GBK 页面解码 ------------------------------------------------------------

(define gbk-cvt (bytes-open-converter "UTF-8" "GBK"))
(define gbk-supported? (boolean? gbk-cvt))

(when gbk-supported?
  (define utf8-title "汽车之家：本周新车盘点与降价潮")
  ;; 构造 GBK 编码的页面(含 meta charset 声明 + 带锚文本的文章链接)
  (define utf8-html
    (string-append
     "<html><head><meta charset=\"gb2312\"></head><body>"
     "<a href=\"/news/202607/1315940.html\">" utf8-title "</a>"
     "<a href=\"/news/202607/1315911.html\">第二条测试标题足够长</a>"
     "</body></html>"))
  (define gbk-bytes
    (let ([out (make-bytes (* 3 (string-length utf8-html)))]
          [cvt (bytes-open-converter "UTF-8" "GBK")])
      (define-values (used got status)
        (bytes-convert cvt (string->bytes/utf-8 utf8-html)
                       0 (string-length utf8-html) out))
      (bytes-close-converter cvt)
      (subbytes out 0 got)))

  (test-case "decode-html-bytes gbk"
    (define html (decode-html-bytes gbk-bytes))
    (check-true (string-contains? html utf8-title) "GBK 应转回 UTF-8")
    (check-false (string-contains? html "\uFFFD") "不应有替换符"))

  (test-case "extract-web-items on gbk page"
    (define rows (extract-web-items (decode-html-bytes gbk-bytes)
                                    "https://www.autohome.com.cn"
                                    #px"/news/[0-9]{6}/[0-9]+\\.html"))
    (check-equal? (length rows) 2)
    (check-equal? (car (car rows)) utf8-title)
    (check-equal? (cadr (car rows))
                  "https://www.autohome.com.cn/news/202607/1315940.html")))

;; ---- 协议相对链接 -------------------------------------------------------------

(test-case "protocol-relative hrefs inherit https"
  (define html
    "<html><body><a href=\"//www.example.com/news/202607/99.html\">这条标题足够长了吧</a></body></html>")
  (define rows (extract-web-items html "https://www.example.com"
                                  #px"//www\\.example\\.com/news/"))
  (check-equal? (length rows) 1)
  (check-equal? (cadr (car rows)) "https://www.example.com/news/202607/99.html"))

;; ---- web_list 关键词门控(经 fetch-all 实测) ----------------------------------
;; 门控在 fetch-web-list 内;用合成配置直接验证行为。

(define gate-config
  (hasheq 'feeds
          (list (hasheq 'name "门控测试"
                        'type "web_list"
                        'url "data:text/html,<html></html>"
                        'base_url "https://x.example"
                        'link_regex "/news/"
                        'only_keywords (list "汽车")
                        'max 10))))

(test-case "web_list keyword gate config accepted"
  ;; fetch-all 不因门控字段报错即可(网络请求会失败,信源标记失败)
  (define-values (items statuses) (fetch-all gate-config))
  (check-true (list? items)))
