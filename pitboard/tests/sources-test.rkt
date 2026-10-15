#lang racket/base

(require rackunit
         racket/date
         racket/list
         racket/string
         "../sources.rkt"
         "../item.rkt")

;; json-path navigation
(test-case "json-path"
  (define h (hash 'a (hash 'b (list 10 (hash 'c "x")))))
  (check-equal? (json-path h '(a b 1 c)) "x")
  (check-equal? (json-path h '(a b 0)) 10)
  (check-equal? (json-path h '(a missing)) 'null)
  (check-equal? (json-path h '(a b 5 c)) 'null)
  (check-equal? (json-path h '()) h))

;; Chinese slash-date format ("2026/10/13", sometimes with a trailing
;; slash) that parse-date-any (8601/822 only) cannot read
(test-case "parse-date-slash"
  (check-equal? (parse-date-slash "2026/10/13/")
                (find-seconds 0 0 12 13 10 2026 #t))
  (check-equal? (parse-date-slash "2026/10/13")
                (find-seconds 0 0 12 13 10 2026 #t))
  (check-equal? (parse-date-slash " 2026/1/2 ")
                (find-seconds 0 0 12 2 1 2026 #t))
  (check-false (parse-date-slash "2026/13/13"))
  (check-false (parse-date-slash "not a date"))
  (check-false (parse-date-slash #f)))

;; fxbaogao-shaped entries through the pure json_api item builder:
;; no url field (url_template instead), slash dates, keyword gates.
(define fx-entries
  (hash 'code 0
        'data (list (hash 'docId 1001 'title "中国整车出口白皮书"
                          'orgName "特易咨询" 'pubTimeStr "2026/10/13/")
                    (hash 'docId 1002 'title "开源晨会"
                          'orgName "某证券" 'pubTimeStr "2026/10/13/")
                    (hash 'docId 1003 'title "人形机器人减速器专题"
                          'orgName "某证券" 'pubTimeStr "2026/10/12/"))))

(define fx-cfg
  (hasheq 'name "发现报告 · 交运设备"
          'tier 2 'weight 0.95
          'path "data"
          'title_field "title"
          'date_field "pubTimeStr"
          'url_template "https://www.fxbaogao.com/detail/{docId}"
          'max 10
          'except_keywords (list "晨会" "盘前" "复盘")))

(test-case "json-api items: url_template + gates + slash dates"
  (define items (json-api-items fx-entries fx-cfg))
  ;; 开源晨会 gated out by except_keywords; the rest survive
  (check-equal? (length items) 2)
  (define first (car items))
  (check-equal? (item-title first) "中国整车出口白皮书")
  (check-equal? (item-url first) "https://www.fxbaogao.com/detail/1001")
  (check-equal? (item-source first) "发现报告 · 交运设备")
  (check-equal? (item-published first) (find-seconds 0 0 12 13 10 2026 #t))
  (check-equal? (hash-ref (item-extra first) 'weight) 0.95)
  ;; docId numbers must render into the URL as digits, not "1001.0"
  (check-false (string-contains? (item-url first) ".0")))

(test-case "json-api items: url_template missing field drops entry"
  (define broken (hash 'code 0 'data (list (hash 'title "无 docId 的条目"))))
  (check-equal? (json-api-items broken fx-cfg) '()))

(test-case "json-api items: only_keywords gate"
  (define cfg-elec
    (hasheq 'name "发现报告 · 电气设备"
            'tier 2 'weight 0.8
            'path "data"
            'title_field "title"
            'date_field "pubTimeStr"
            'url_template "https://www.fxbaogao.com/detail/{docId}"
            'max 10
            'only_keywords (list "固态" "电池" "锂电")))
  (define elec-entries
    (hash 'code 0
          'data (list (hash 'docId 2001 'title "固态电池带来新投资周期"
                            'pubTimeStr "2026/10/14/")
                      (hash 'docId 2002 'title "算力租赁价格跟踪"
                            'pubTimeStr "2026/10/14/"))))
  (define items (json-api-items elec-entries cfg-elec))
  (check-equal? (length items) 1)
  (check-equal? (item-title (car items)) "固态电池带来新投资周期"))

(test-case "json-api items: classic url_field still works"
  (define entries (hash 'items (list (hash 'title "外刊标题"
                                           'url "https://example.com/a"
                                           'published_at "2026-10-13T09:00:00Z"))))
  (define cfg (hasheq 'name "api" 'path "items" 'max 5))
  (define items (json-api-items entries cfg))
  (check-equal? (length items) 1)
  (check-equal? (item-url (car items)) "https://example.com/a")
  (check-equal? (item-published (car items)) (find-seconds 0 0 9 13 10 2026 #t)))

(test-case "json-api items: max caps entries"
  (define many (hash 'code 0
                     'data (for/list ([i (in-range 12)])
                             (hash 'docId i 'title (format "报告 ~a" i)
                                   'pubTimeStr "2026/10/13/"))))
  (check-equal? (length (json-api-items many fx-cfg)) 10))
