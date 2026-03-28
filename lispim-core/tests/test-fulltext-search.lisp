;;;; test-fulltext-search.lisp - 全文搜索模块单元测试
;;;;
;;;; 测试全文搜索功能：
;;;; - 中文分词
;;;; - 倒排索引
;;;; - 消息搜索
;;;; - 联系人搜索
;;;; - 会话搜索
;;;; - 搜索结果高亮

(in-package :lispim-core-test)

(def-suite test-fulltext-search
  :description "全文搜索模块测试")

(in-suite test-fulltext-search)

;;;; 分词测试

(def-test test-tokenize-text-english ()
  "测试英文分词"
  (let* ((text "Hello World, this is a test message")
         (tokens (lispim-core::tokenize-text text)))
    (is (>= (length tokens) 4))
    (is (member "hello" tokens :test 'string=))
    (is (member "world" tokens :test 'string=))
    (is (member "test" tokens :test 'string=))
    (is (member "message" tokens :test 'string=))))

(def-test test-tokenize-text-chinese ()
  "测试中文分词"
  (let* ((text "你好世界这是一个测试消息")
         (tokens (lispim-core::tokenize-text text)))
    ;; 中文单字索引
    (is (>= (length tokens) 1))
    (is (member "你" tokens :test 'string=))))

(def-test test-tokenize-text-mixed ()
  "测试混合文本分词"
  (let* ((text "Hello 你好 World 世界 Test 测试")
         (tokens (lispim-core::tokenize-text text)))
    (is (>= (length tokens) 3))
    ;; 应该包含英文单词和中文单字
    (is (member "hello" tokens :test 'string=))
    (is (member "world" tokens :test 'string=))))

(def-test test-tokenize-text-min-length ()
  "测试最小词长度"
  (let* ((text "a ab abc test")
         (tokens (lispim-core::tokenize-text text)))
    ;; 单字符不应该被索引（除了中文）
    (is (not (member "a" tokens :test 'string=)))
    (is (member "ab" tokens :test 'string=))
    (is (member "abc" tokens :test 'string=))
    (is (member "test" tokens :test 'string=))))

;;;; 倒排索引测试

(def-test test-build-inverted-index ()
  "测试倒排索引构建"
  (let* ((text "hello world hello test")
         (index (lispim-core::build-inverted-index text)))
    (is (typep index 'hash-table))
    (is (= 2 (gethash "hello" index 0)))
    (is (= 1 (gethash "world" index 0)))
    (is (= 1 (gethash "test" index 0)))))

;;;; 搜索高亮测试

(def-test test-highlight-text ()
  "测试搜索结果高亮"
  (let* ((text "Hello World, this is a test message")
         (terms '("hello" "test"))
         (highlighted (lispim-core::highlight-text text terms)))
    (is (search "<mark>hello</mark>" highlighted :test 'char=))
    (is (search "<mark>test</mark>" highlighted :test 'char=))))

(def-test test-highlight-text-case-insensitive ()
  "测试高亮不区分大小写"
  (let* ((text "Hello WORLD test")
         (terms '("hello" "world"))
         (highlighted (lispim-core::highlight-text text terms)))
    (is (search "<mark>hello</mark>" highlighted :test 'char=))
    (is (or (search "<mark>WORLD</mark>" highlighted :test 'char=)
            (search "<mark>world</mark>" highlighted :test 'char=)))))

(def-test test-highlight-text-custom-markers ()
  "测试自定义高亮标记"
  (let* ((text "Hello test")
         (terms '("hello"))
         (highlighted (lispim-core::highlight-text text terms
                                                   :prefix "**"
                                                   :suffix "**")))
    (is (search "**hello**" highlighted :test 'char=))))

;;;; 搜索引擎初始化测试

(def-test test-init-fulltext-search ()
  "测试搜索引擎初始化"
  (let ((engine (lispim-core::init-fulltext-search
                 :redis-host "localhost"
                 :redis-port 6379
                 :index-prefix "lispim:test:search:")))
    (is (typep engine 'lispim-core::search-engine))
    (is (string= "lispim:test:search:"
                 (lispim-core::search-engine-index-prefix engine)))
    (is (= 2 (lispim-core::search-engine-min-word-length engine)))
    (is (= 100 (lispim-core::search-engine-max-results engine)))))

;;;; 搜索统计测试

(def-test test-get-search-stats ()
  "测试获取搜索统计"
  (let ((engine (lispim-core::init-fulltext-search)))
    (let ((stats (lispim-core::get-search-stats engine)))
      (is (getf stats :document-count))
      (is (getf stats :term-count))
      (is (getf stats :index-prefix))
      (is (getf stats :max-results)))))

;;;; 高层 API 测试

(def-test test-search-function ()
  "测试高层搜索 API"
  ;; 测试 :all 类型
  (let ((result (lispim-core::search "test-user" "test query" :type :all)))
    (is (getf result :messages))
    (is (getf result :contacts))
    (is (getf result :conversations))))

(def-test test-search-messages-type ()
  "测试搜索消息类型"
  (let ((result (lispim-core::search "test-user" "test" :type :messages)))
    (is (listp result))))

(def-test test-search-contacts-type ()
  "测试搜索联系人类型"
  (let ((result (lispim-core::search "test-user" "test" :type :contacts)))
    (is (listp result))))

(def-test test-search-conversations-type ()
  "测试搜索会话类型"
  (let ((result (lispim-core::search "test-user" "test" :type :conversations)))
    (is (listp result))))

(def-test test-highlight-search-result ()
  "测试高层高亮 API"
  (let ((text "Hello World test message")
        (query "hello test")
        (highlighted (lispim-core::highlight-search-result text query)))
    (is (search "<mark>" highlighted :test 'char=))))

;;;; 关闭测试

(def-test test-shutdown-fulltext-search ()
  "测试关闭搜索引擎"
  (let ((engine (lispim-core::init-fulltext-search)))
    (lispim-core::shutdown-fulltext-search)
    ;; 验证全局实例被清理
    (is (null lispim-core::*search-engine*))))
