;;;; utils.lisp - LispIM 工具函数
;;;;
;;;; 通用工具函数、宏、辅助函数
;;;;
;;;; 参考：Common Lisp Cookbook - Macros, Conditions, Types, Optimization
;;;; 使用现代库：str (字符串处理), fset (函数式数据结构), serapeum, alexandria

(in-package :lispim-core)

;;;; 日志宏 - 简单封装 log4cl - 使用 str:concat

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:log4cl :uuid :flexi-streams)))

(defmacro log-debug (format-str &rest args)
  "调试日志 - 仅在调试模式下输出"
  `(log:debug (format nil ,(str:concat "[~a] " format-str)
                      (get-universal-time) ,@args)))

(defmacro log-info (format-str &rest args)
  "信息日志 - 记录重要事件"
  `(log:info (format nil ,(str:concat "[~a] " format-str)
                     (get-universal-time) ,@args)))

(defmacro log-warn (format-str &rest args)
  "警告日志 - 记录潜在问题"
  `(log:warn (format nil ,(str:concat "[~a] " format-str)
                     (get-universal-time) ,@args)))

(defmacro log-error (format-str &rest args)
  "错误日志 - 记录错误信息"
  `(log:error (format nil ,(str:concat "[~a] " format-str)
                      (get-universal-time) ,@args)))

;;;; 安全宏 - 使用符号宏避免重复求值

(defmacro with-safe-division ((divisor &optional default) &body body)
  "安全除法宏 - 避免除零错误，参考 On Lisp 第 8 章"
  (let ((divisor-sym (gensym "DIVISOR"))
        (result-sym (gensym "RESULT")))
    `(let ((,divisor-sym ,divisor))
       (if (zerop ,divisor-sym)
           ,default
           (let ((,result-sym (/ ,divisor-sym)))
             (declare (ignore ,result-sym))
             ,@body)))))

;; 使用 lispim- 前缀避免与 alexandria 冲突

(defmacro lispim-when-let ((var test-form) &body body)
  "When-let 宏 - 测试形式绑定到变量，成功后执行
   参考 On Lisp：var 是故意捕获的，属于'anaphoric'宏"
  (once-only (test-form)
    `(let ((,var ,test-form))
       (when ,var ,@body))))

(defmacro lispim-when-let* (bindings &body body)
  "When-let* 宏 - 顺序绑定多个测试形式"
  (if (null bindings)
      `(progn ,@body)
      `(let ((,(caar bindings) ,(cadar bindings)))
         (when ,(caar bindings)
           (lispim-when-let* ,(cdr bindings) ,@body)))))

(defmacro lispim-if-let ((var test-form then-expr else-expr) &body body)
  "If-let 宏 - 测试形式绑定到变量，返回不同值
   参考 On Lisp：var 是故意捕获的，属于'anaphoric'宏"
  (declare (ignore body))
  (once-only (test-form)
    `(let ((,var ,test-form))
       (if ,var ,then-expr ,else-expr))))

;;;; 类型声明宏 - 增强的类型定义

(defmacro deftype+ (name lambda-list &body body)
  "增强的 DEFTYPE，支持文档字符串和类型检查 - 参考 On Lisp 第 8 章"
  (let ((docstring (when (stringp (car body)) (pop body))))
    `(deftype ,name ,lambda-list
       ,@(when docstring `(,docstring))
       ,@body)))

(deftype hash-table-of (key-type value-type)
  "参数化哈希表类型"
  `(and hash-table (satisfies (lambda (ht)
                                (every (lambda (k)
                                         (typep k ',key-type))
                                       (lispim-hash-table-keys ht))
                                (every (lambda (v)
                                         (typep v ',value-type))
                                       (lispim-hash-table-values ht))))))

(deftype alist-of (key-type value-type)
  "参数化关联列表类型"
  `(and list (satisfies (lambda (al)
                          (every (lambda (pair)
                                   (and (consp pair)
                                        (typep (car pair) ',key-type)
                                        (typep (cdr pair) ',value-type)))
                                 al)))))

(deftype plist-of (key-type value-type)
  "参数化属性列表类型"
  `(and list (satisfies (lambda (pl)
                          (loop for (k v) on pl by #'cddr
                                always (and (keywordp k)
                                            (typep v ',value-type)))))))

;;;; 哈希表工具 - 使用 alexandria

;; 使用 alexandria 的哈希表工具
;; alexandria:hash-table-keys - 获取所有键
;; alexandria:hash-table-values - 获取所有值
;; alexandria:hash-table-alist - 转为关联列表
;; alexandria:copy-hash-table - 浅拷贝

;; 直接定义函数别名
(declaim (inline lispim-copy-hash-table lispim-hash-table-keys
                 lispim-hash-table-values lispim-hash-table-alist))

(defun lispim-copy-hash-table (ht)
  "拷贝哈希表"
  (alexandria:copy-hash-table ht))

(defun lispim-hash-table-keys (ht)
  "获取哈希表所有键"
  (alexandria:hash-table-keys ht))

(defun lispim-hash-table-values (ht)
  "获取哈希表所有值"
  (alexandria:hash-table-values ht))

(defun lispim-hash-table-alist (ht)
  "哈希表转关联列表"
  (alexandria:hash-table-alist ht))

(defun lispim-hash-table-merge (ht1 ht2 &key (overwrite t))
  "合并两个哈希表 - 使用 alexandria:copy-hash-table"
  (declare (type hash-table ht1 ht2))
  (let ((result (alexandria:copy-hash-table (if overwrite ht1 ht2))))
    (maphash (lambda (k v)
               (unless (and (not overwrite) (gethash k result))
                 (setf (gethash k result) v)))
             (if overwrite ht2 ht1))
    result))

;; alexandria:assoc-default - 关联列表默认值查找
;; alexandria:plist-member - 检查属性列表是否包含键

(defun lispim-hash-table-filter (ht predicate)
  "根据谓词过滤哈希表"
  (declare (type hash-table ht)
           (type function predicate))
  (let ((result (make-hash-table :test (hash-table-test ht))))
    (maphash (lambda (k v)
               (when (funcall predicate k v)
                 (setf (gethash k result) v)))
             ht)
    result))

;;;; 字符串工具 - 使用 alexandria/serapeum 增强的处理函数

;; alexandria 提供有用的字符串/序列处理函数：
;; - alexandria:starts-with-subseq - 检查前缀
;; - alexandria:ends-with-subseq - 检查后缀
;; - alexandria:rotate - 旋转序列
;; - alexandria:shuffle - 随机打乱

;; 字符串谓词 - 直接使用 alexandria 和 str 库的函数
;; 注意：serapeum 也导出 string-prefix-p 和 string-suffix-p，所以不使用别名避免冲突
;; 请直接使用 alexandria:starts-with-subseq, alexandria:ends-with-subseq, str:emptyp

(defun lispim-string-contains-p (str substr)
  "检查字符串是否包含子串"
  (declare (type string str substr))
  (when (and str substr)
    (search substr str)))

(defun lispim-string-empty-p (str)
  "检查字符串是否为空 - 使用 str:emptyp"
  (declare (type string str))
  (str:emptyp str))

(defun lispim-string-present-p (str)
  "检查字符串是否非空"
  (declare (type string str))
  (not (str:emptyp str)))

(defun remove-prefix (str prefix)
  "Remove prefix from string if it exists - using alexandria"
  (declare (type string str prefix))
  (if (alexandria:starts-with-subseq prefix str)
      (subseq str (length prefix))
      str))

(defun remove-suffix (str suffix)
  "Remove suffix from string if it exists - using alexandria"
  (declare (type string str suffix))
  (if (alexandria:ends-with-subseq suffix str)
      (subseq str 0 (- (length str) (length suffix)))
      str))

;; 使用 str 库的空值谓词
;; string-empty-p, string-present-p 已在上面通过 defalias 定义

(defun string-uuid ()
  "生成字符串 UUID"
  (format nil "~a" (uuid:make-v4-uuid)))

(defun string-trim-all (str)
  "移除所有空白字符 - 只保留图形字符 - 使用 remove-if-not"
  (declare (type string str))
  (remove-if-not #'graphic-char-p str))

;; alexandria:non-nil-counting - 计算非 nil 元素数量
;; alexandria:count-if - 条件计数
;; alexandria:filter - 过滤列表

(defun string-downcase-keyword (sym)
  "将符号转换为小写关键词"
  (intern (string-downcase (symbol-name sym)) 'keyword))

(defun string-split (string delimiter &key (remove-empty nil))
  "分割字符串 - 使用 str:split"
  (declare (type string string delimiter))
  (let ((parts (str:split delimiter string)))
    (if remove-empty
        (remove-if (lambda (s) (zerop (length s))) parts)
        parts)))

(defun lispim-string-join (sequences separator)
  "连接字符串序列 - 使用 str:join"
  (declare (type sequence sequences)
           (type string separator))
  (str:join separator sequences))

;; Use serapeum:string-join directly if needed

(defun string-camel-case (string)
  "转换为驼峰命名 - 使用 alexandria:append"
  (declare (type string string))
  (let ((words (string-split string " ")))
    (apply #'concatenate 'string
           (cons (string-downcase (first words))
                 (mapcar (lambda (w)
                           (concatenate 'string
                                        (string (char-upcase (char w 0)))
                                        (string-downcase (subseq w 1))))
                         (rest words))))))

(defun string-snake-case (string)
  "转换为蛇形命名"
  (declare (type string string))
  (string-trim "_"
    (reduce (lambda (acc ch)
              (concatenate 'string acc
                (if (upper-case-p ch)
                    (format nil "_~a" (string-downcase ch))
                    (string ch))))
            string
            :initial-value "")))

;;;; 时间工具 - 使用 local-time 库增强的时间处理

;; local-time 提供现代时间处理功能：
;; - (local-time:now) - 当前时间
;; - (local-time:timestamp-to-unix) - 转为 Unix 时间戳
;; - (local-time:unix-to-timestamp) - 从 Unix 时间戳转换
;; - (local-time:format-timestring) - 格式化时间
;; - (local-time:parse-timestring) - 解析时间字符串

(defun now-unix ()
  "获取当前 Unix 时间戳（秒）- 使用 local-time"
  (local-time:timestamp-to-unix (local-time:now)))

(defun now-unix-ms ()
  "获取当前 Unix 时间戳（毫秒）"
  (* (now-unix) 1000))

(defun lispim-unix-to-universal (unix-time)
  "Unix 时间戳转换为 Universal Time"
  (local-time:timestamp-to-universal (local-time:unix-to-timestamp unix-time)))

(defun lispim-universal-to-unix (universal-time)
  "Universal Time 转换为 Unix 时间戳（秒）"
  (floor (- universal-time (encode-universal-time 0 0 0 1 1 1970 0))))

(defun lispim-universal-to-unix-ms (universal-time)
  "Universal Time 转换为 Unix 时间戳（毫秒）"
  (* (- universal-time (encode-universal-time 0 0 0 1 1 1970 0)) 1000))

(defun lispim-unix-to-human-readable (unix-time &key (format nil))
  "Unix 时间戳转换为人类可读格式 - 使用 local-time"
  (declare (ignore format))
  (local-time:format-timestring nil (local-time:unix-to-timestamp unix-time)))

(defun lispim-parse-time-string (time-string &key (format nil))
  "解析时间字符串为 Unix 时间戳 - 使用 local-time"
  (declare (type string time-string)
           (ignore format))
  (local-time:timestamp-to-unix (local-time:parse-timestring time-string)))

(defun format-duration (seconds &key (verbose nil))
  "格式化持续时间为人类可读形式 - 使用 serapeum"
  (declare (type integer seconds))
  (let* ((days (floor seconds 86400))
         (hours (floor (mod seconds 86400) 3600))
         (minutes (floor (mod seconds 3600) 60))
         (secs (mod seconds 60)))
    (cond
      (verbose
       (format nil "~a days, ~a hours, ~a minutes, ~a seconds" days hours minutes secs))
      ((>= days 1)
       (format nil "~ad ~ah" days hours))
      ((>= hours 1)
       (format nil "~ah ~am" hours minutes))
      ((>= minutes 1)
       (format nil "~am ~as" minutes secs))
      (t
       (format nil "~as" secs)))))

;; Time constants
(defconstant +seconds-per-minute+ 60)
(defconstant +seconds-per-hour+ 3600)
(defconstant +minutes-per-hour+ 60)

(defmacro with-timing ((var &optional (format-str nil)) &body body)
  "计算执行时间"
  (let ((start-sym (gensym "START")))
    `(let ((,start-sym (get-internal-real-time)))
       (multiple-value-prog1
           (progn ,@body)
         (let ((,var (/ (- (get-internal-real-time) ,start-sym)
                        internal-time-units-per-second)))
           (if ,format-str
               (log-debug "Timing: ~a~f seconds" ,format-str ,var)
               (log-debug "Timing: ~f seconds" ,var)))))))

;;;; 字节序工具 - 增强的字节操作

(declaim (inline write-u16-be write-u32-be write-u64-be
                 read-u16-be read-u32-be read-u64-be))

(defun write-u16-be (value stream)
  "写入 16 位大端整数"
  (declare (type (unsigned-byte 16) value)
           (type stream stream)
           (optimize (speed 3) (safety 1)))
  (write-byte (ldb (byte 8 8) value) stream)
  (write-byte (ldb (byte 8 0) value) stream))

(defun write-u32-be (value stream)
  "写入 32 位大端整数"
  (declare (type (unsigned-byte 32) value)
           (type stream stream)
           (optimize (speed 3) (safety 1)))
  (loop for i from 24 downto 0 by 8
        do (write-byte (ldb (byte 8 i) value) stream)))

(defun write-u64-be (value stream)
  "写入 64 位大端整数"
  (declare (type (unsigned-byte 64) value)
           (type stream stream)
           (optimize (speed 3) (safety 1)))
  (loop for i from 56 downto 0 by 8
        do (write-byte (ldb (byte 8 i) value) stream)))

(defun read-u16-be (stream)
  "读取 16 位大端整数"
  (declare (type stream stream)
           (optimize (speed 3) (safety 1)))
  (let ((b1 (read-byte stream))
        (b2 (read-byte stream)))
    (the (unsigned-byte 16) (logior (ash b1 8) b2))))

(defun read-u32-be (stream)
  "读取 32 位大端整数"
  (declare (type stream stream)
           (optimize (speed 3) (safety 1)))
  (let ((result 0))
    (dotimes (i 4 result)
      (setf result (the (unsigned-byte 32)
                        (logior result (ash (read-byte stream) (* 8 (- 3 i)))))))))

(defun read-u64-be (stream)
  "读取 64 位大端整数"
  (declare (type stream stream)
           (optimize (speed 3) (safety 1)))
  (let ((result 0))
    (dotimes (i 8 result)
      (setf result (the (unsigned-byte 64)
                        (logior result (ash (read-byte stream) (* 8 (- 7 i)))))))))

(defun write-u16-le (value stream)
  "写入 16 位小端整数"
  (declare (type (unsigned-byte 16) value)
           (type stream stream))
  (write-byte (ldb (byte 8 0) value) stream)
  (write-byte (ldb (byte 8 8) value) stream))

(defun write-u32-le (value stream)
  "写入 32 位小端整数"
  (declare (type (unsigned-byte 32) value)
           (type stream stream))
  (loop for i from 0 to 24 by 8
        do (write-byte (ldb (byte 8 i) value) stream)))

(defun read-u16-le (stream)
  "读取 16 位小端整数"
  (declare (type stream stream))
  (let ((b1 (read-byte stream))
        (b2 (read-byte stream)))
    (logior (ash b2 8) b1)))

(defun read-u32-le (stream)
  "读取 32 位小端整数"
  (declare (type stream stream))
  (let ((result 0))
    (dotimes (i 4 result)
      (setf result (logior result (ash (read-byte stream) (* 8 i)))))))

;;;; 向量输出流

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:flexi-streams)))

(defmacro with-output-to-byte-vector ((stream-var) &body body)
  "输出到字节向量"
  `(flexi-streams:with-output-to-sequence (,stream-var)
     ,@body))

;;;; 安全缓冲区

(defstruct secure-buffer
  "安全缓冲区，用于存储敏感数据"
  (data nil :type (or null (simple-array (unsigned-byte 8) (*))))
  (allocated-at (get-universal-time) :type integer)
  (expires-at nil :type (or null integer)))

(defun make-secure-buffer* (size)
  "创建安全缓冲区"
  (declare (type integer size))
  (make-secure-buffer
   :data (make-array size :element-type '(unsigned-byte 8) :initial-element 0)))

(defun secure-erase (buffer)
  "安全擦除敏感数据（多次覆盖防止内存恢复）"
  (declare (type (simple-array (unsigned-byte 8) (*)) buffer)
           (optimize (speed 3) (safety 0)))
  ;; 多次覆盖
  (fill buffer #x00)
  (fill buffer #xFF)
  (fill buffer #x55)
  (fill buffer #xAA)
  (fill buffer #x00))

(defun destroy-secure-buffer (buf)
  "销毁安全缓冲区"
  (declare (type secure-buffer buf))
  (when (secure-buffer-data buf)
    (secure-erase (secure-buffer-data buf))
    (setf (secure-buffer-data buf) nil)))

;;;; 重试宏 - 增强的错误恢复

(defmacro with-retry ((&key (max-retries 3) (delay 1) (backoff 2)
                          (condition 'error) (before-retry nil) (on-success nil))
                      &body body)
  "重试宏 - 支持指数退避和回调"
  (let ((retries (gensym "RETRIES"))
        (current-delay (gensym "DELAY"))
        (result (gensym "RESULT")))
    `(let ((,retries 0)
           (,current-delay ,delay))
       (loop
         (handler-case
             (let ((,result (progn ,@body)))
               ,@(when on-success `((funcall (function ,on-success) ,result)))
               (return ,result))
           (,condition (c)
             (when (>= ,retries ,max-retries)
               (error "Max retries (~a) exceeded. Last error: ~a" ,max-retries c))
             ,@(when before-retry `((funcall (function ,before-retry) ,retries c)))
             (incf ,retries)
             (sleep ,current-delay)
             (setf ,current-delay (* ,current-delay ,backoff))))))))

(defmacro with-timeout ((seconds &optional default) &body body)
  "超时宏 - 限制代码执行时间"
  (let ((result (gensym "RESULT")))
    `(handler-case
         (bordeaux-threads:with-timeout ,seconds
           ,@body)
       (bordeaux-threads:timeout ()
         ,default))))

(defmacro with-parallel ((&rest tasks) &key (timeout nil))
  "并行执行宏 - 同时执行多个任务"
  (let ((results (gensym "RESULTS"))
        (threads (gensym "THREADS")))
    `(let ((,results (make-array (length ,tasks)))
           (,threads nil))
       (dotimes (i (length ,tasks))
         (push (bordeaux-threads:make-thread
                (lambda ()
                  (setf (aref ,results i)
                        (handler-case
                            (funcall (nth ,i ,tasks))
                          (error (c) c)))))
               ,threads))
       ,@(when timeout `((bordeaux-threads:with-timeout ,timeout)))
       (mapc #'bordeaux-threads:join-thread ,threads)
       (coerce ,results 'list))))

;;;; 时间宏

;;;; 空值处理和流程控制宏

;; alexandria 提供：
;; - alexandria:when-let - 绑定并执行
;; - alexandria:when-let* - 顺序绑定并执行
;; - alexandria:if-let - 绑定并根据结果选择分支
;; - alexandria:anaphora - 访问宏

;; 注意：由于 serapeum 也导出这些宏，我们使用 lispim- 前缀避免冲突

(defmacro awhen (test-form &body body)
  "Anaphoric when - test-form 结果绑定到 it"
  (let ((it (gensym "IT")))
    `(let ((,it ,test-form))
       (when ,it ,@body))))

(defmacro aand (test-form &body body)
  "Anaphoric and - test-form 结果绑定到 it"
  (let ((it (gensym "IT")))
    `(let ((,it ,test-form))
       (if ,it
           (progn ,@body)
           nil))))

(defmacro acase (keyform &body clauses)
  "Anaphoric case - keyform 结果绑定到 it"
  (let ((it (gensym "IT")))
    `(let ((,it ,keyform))
       (case ,it ,@clauses))))

(defmacro lispim-cond-let (bindings &body clauses)
  "Cond-let 宏 - 在 cond 分支中绑定变量"
  (if (null clauses)
      nil
      (let ((clause (car clauses))
            (rest (cdr clauses)))
        (if (atom clause)
            `(let ,bindings ,clause)
            `(let ,bindings
               (if ,(car clause)
                   (progn ,@(cdr clause))
                   (lispim-cond-let ,bindings ,@rest)))))))

(defmacro do-hash ((key-var val-var hash-table &optional return) &body body)
  "哈希表遍历宏 - 参考 On Lisp，使用 gensym 避免变量捕获"
  (let ((ht-sym (gensym "HT")))
    `(let ((,ht-sym ,hash-table))
       (maphash (lambda (,key-var ,val-var)
                  ,@body)
                ,ht-sym)
       ,return)))

(defmacro lispim-with-gensyms ((&rest names) &body body)
  "生成多个临时符号"
  `(let ,(loop for name in names collect `(,name (gensym)))
     ,@body))

(defmacro lispim-with-unique-names ((&rest names) &body body)
  "lispim-with-gensyms 的别名"
  `(lispim-with-gensyms ,names ,@body))

;;;; JSON 和序列化工具

(defun plist-to-json (plist)
  "属性列表转 JSON 字符串"
  (cl-json:encode-json-to-string plist))

(defun json-to-plist (json-str)
  "JSON 字符串转属性列表"
  (cl-json:decode-json-from-string json-str))

(defun hash-to-json (hash)
  "哈希表转 JSON 字符串"
  (let ((plist (hash-table-to-plist hash)))
    (cl-json:encode-json-to-string plist)))

(defun hash-table-to-plist (ht)
  "哈希表转属性列表"
  (let ((plist nil))
    (maphash (lambda (k v)
               (push k plist)
               (push v plist))
             ht)
    (nreverse plist)))

(defun plist-to-hash-table (plist)
  "属性列表转哈希表"
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on plist by #'cddr
          do (setf (gethash k ht) v))
    ht))

(defun json-to-hash-table (json-str)
  "JSON 字符串转哈希表"
  (plist-to-hash-table (cl-json:decode-json-from-string json-str)))

(defun hash-table-to-json (ht)
  "哈希表转 JSON 字符串"
  (cl-json:encode-json-to-string (hash-table-to-plist ht)))

(defun safe-json-encode (object)
  "安全的 JSON 编码"
  (handler-case
      (cl-json:encode-json-to-string object)
    (error (c)
      (log-error "JSON encode failed: ~a" c)
      nil)))

(defun safe-json-decode (json-string)
  "安全的 JSON 解码"
  (handler-case
      (cl-json:decode-json-from-string json-string)
    (error (c)
      (log-error "JSON decode failed: ~a" c)
      nil)))
