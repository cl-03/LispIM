;;;; commands.lisp - 系统命令消息
;;;;
;;;; 参考 Fiora 的系统命令设计（-roll, -rps 等）
;;;; 支持扩展的命令行式消息处理
;;;;
;;;; 设计原则：
;;;; - 纯 Common Lisp 实现
;;;; - 易于扩展新命令
;;;; - 支持中文命令别名

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-json :str)))

;;;; 类型定义

(deftype command-handler ()
  "命令处理器函数类型"
  '(function (list) list))

(deftype command-spec ()
  "命令规格"
  '(list (or null string) function string list))

;;;; 命令注册表

(defvar *system-commands* (make-hash-table :test 'equal)
  "系统命令注册表：command-name -> spec")

(defvar *command-aliases* (make-hash-table :test 'equal)
  "命令别名表：alias -> command-name")

;;;; 命令统计

(defvar *commands-executed-counter* 0
  "执行的命令总数")

(defvar *commands-stats* (make-hash-table :test 'equal)
  "各命令执行次数统计")

;;;; 命令定义宏

(defmacro define-command (name docstring args &body body)
  "定义系统命令

   Syntax:
     (define-command \"-roll\"
       \"掷骰子命令\"
       (&optional max)
       (let ((result (random max)))
         ...))

   Parameters:
     name     - 命令名称字符串，如 \"-roll\"
     docstring - 命令描述
     args     - 参数列表
     body     - 命令实现"
  (let ((cmd-name (if (stringp name) name (string name))))
    `(progn
       ;; 注册命令
       (setf (gethash ,cmd-name *system-commands*)
             (list ,cmd-name
                   (lambda ,args ,@body)
                   ,docstring
                   ',args))
       ;; 记录命令
       (log-info "Command registered: ~a" ,cmd-name)
       ,cmd-name)))

(defun register-command (name handler docstring &key (aliases nil))
  "注册系统命令

   Parameters:
     name     - 命令名称
     handler  - 处理函数
     docstring - 描述
     aliases  - 别名列表"
  (declare (type string name)
           (type command-handler handler)
           (type string docstring))
  (setf (gethash name *system-commands*)
        (list name handler docstring nil))
  ;; 注册别名
  (dolist (alias aliases)
    (setf (gethash alias *command-aliases*) name))
  (log-info "Command registered: ~a (aliases: ~{~a~^, ~})" name aliases)
  t)

;;;; 内置命令实现

;; 掷骰子命令
(define-command "-roll"
  "掷骰子，生成随机数。用法：-roll [最大值]，默认 100"
  (&optional max)
  (let ((max-value (or max 100))
        (result (random (1+ (or max 100)))))
    (list :type :system
          :command "roll"
          :value result
          :top max-value
          :display (format nil "掷出了 ~a 点（1-~a）" result max-value))))

;; 石头剪刀布
(define-command "-rps"
  "石头剪刀布游戏。用法：-rps"
  ()
  (let ((result (elt '("石头" "剪刀" "布") (random 3))))
    (list :type :system
          :command "rps"
          :value result
          :display (format nil "结果是：~a" result))))

;; 帮助命令
(define-command "-help"
  "显示帮助信息。用法：-help [命令名]"
  (&optional cmd-name)
  (if cmd-name
      ;; 显示特定命令帮助
      (let ((cmd (gethash cmd-name *system-commands*)))
        (if cmd
            (list :type :system
                  :command "help"
                  :name (first cmd)
                  :doc (third cmd)
                  :display (format nil "~a: ~a" (first cmd) (third cmd)))
            (list :type :system
                  :command "help"
                  :error "命令不存在"
                  :display (format nil "命令 ~a 不存在" cmd-name))))
      ;; 显示所有命令列表
      (let ((commands nil))
        (maphash (lambda (name spec)
                   (push (list :name name :doc (third spec)) commands))
                 *system-commands*)
        (list :type :system
              :command "help"
              :commands commands
              :display (format nil "可用命令：~{~a~^, ~}"
                               (loop for key being the hash-keys of *system-commands*
                                     collect key))))))

;; /me 动作命令
(define-command "/me"
  "发送动作消息。用法：/me 很高兴"
  (&rest text)
  (list :type :action
        :command "me"
        :content (format nil "~{~a~^ ~}" text)
        :display (format nil "~a" (format nil "~{~a~^ ~}" text))))

;; 抽签命令
(define-command "-draw"
  "抽签命令。用法：-draw [选项 1] [选项 2] ..."
  (&rest options)
  (if (null options)
      (list :type :system
            :command "draw"
            :error "请提供选项"
            :display "请提供至少两个选项")
      (list :type :system
            :command "draw"
            :options options
            :result (elt options (random (length options)))
            :display (format nil "抽签结果：~a" (elt options (random (length options)))))))

;; 今日运势
(define-command "-fortune"
  "今日运势"
  ()
  (let ((fortunes '("大吉" "吉" "中吉" "小吉" "末吉" "凶" "大凶"))
        (advice '("适合写代码" "适合摸鱼" "适合开会" "适合 debugging"
                  "适合重构" "适合测试" "适合文档")))
    (let ((fortune (elt fortunes (random (length fortunes))))
          (adv (elt advice (random (length advice)))))
      (list :type :system
            :command "fortune"
            :fortune fortune
            :advice adv
            :display (format nil "今日运势：~a - ~a" fortune adv)))))

;; 选择器
(define-command "-choose"
  "二选一。用法：-choose A B"
  (option-a option-b)
  (let ((choices (list option-a option-b))
        (result nil))
    (setf result (elt choices (random 2)))
    (list :type :system
          :command "choose"
          :option-a option-a
          :option-b option-b
          :result result
          :display (format nil "选择了：~a" result))))

;; 倒计时命令
(define-command "-timer"
  "倒计时。用法：-timer 秒数"
  (seconds)
  (declare (ignore seconds))
  (list :type :system
        :command "timer"
        :error "not implemented"
        :display "倒计时命令尚未实现"))

;; 中文命令别名
(define-command "掷骰子"
  "掷骰子（中文别名）"
  (&optional max)
  (declare (ignore max))
  (let ((max-value 100)
        (result (random 101)))
    (list :type :system
          :command "roll"
          :value result
          :top max-value
          :display (format nil "掷出了 ~a 点（1-~a）" result max-value))))

(define-command "石头剪刀布"
  "石头剪刀布（中文别名）"
  ()
  (let ((result (elt '("石头" "剪刀" "布") (random 3))))
    (list :type :system
          :command "rps"
          :value result
          :display (format nil "结果是：~a" result))))

;;;; 命令解析

(defun parse-command (content)
  "解析消息内容是否为命令

   Parameters:
     content - 消息内容

   Returns:
     (values is-command-p command-name args)"
  (declare (type string content))
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline) content)))
    (cond
      ;; 以 - 开头的命令
      ((and (> (length trimmed) 1)
            (char= (char trimmed 0) #\-)
            (or (char= (char trimmed 1) #\a)
                (char= (char trimmed 1) #\r)
                (char= (char trimmed 1) #\d)
                (char= (char trimmed 1) #\h)
                (char= (char trimmed 1) #\/)))
       (let* ((parts (str:split #\Space trimmed :limit 2))
              (cmd-name (first parts))
              (args-str (if (> (length parts) 1) (second parts) "")))
         ;; 检查别名
         (let ((real-name (gethash cmd-name *command-aliases* cmd-name)))
           (values t real-name (parse-command-args cmd-name args-str)))))
      ;; 以 /me 开头的动作
      ((str:starts-with-p "/me " trimmed)
       (values t "/me" (list (subseq trimmed 4))))
      ;; 中文命令
      ((or (str:starts-with-p "掷骰子" trimmed)
           (str:starts-with-p "石头剪刀布" trimmed))
       (values t trimmed nil))
      (t (values nil nil nil)))))

(defun parse-command-args (command-name args-string)
  "解析命令参数"
  (declare (type string args-string))
  (let ((cmd (gethash command-name *system-commands*)))
    (unless cmd
      (return-from parse-command-args nil))
    (let ((args-spec (fourth cmd)))
      (if (null args-spec)
          nil
          (let ((parts (str:split #\Space args-string)))
            parts)))))

;;;; 命令执行

(defun execute-command (command-name args)
  "执行系统命令

   Parameters:
     command-name - 命令名称
     args         - 参数列表

   Returns:
     命令执行结果（plist）"
  (let ((cmd (gethash command-name *system-commands*)))
    (unless cmd
      (return-from execute-command
        (list :type :error
              :command command-name
              :error "命令不存在"
              :display (format nil "未知命令：~a" command-name))))
    (let ((handler (second cmd)))
      (incf *commands-executed-counter*)
      ;; 更新统计
      (let ((count (gethash command-name *commands-stats* 0)))
        (setf (gethash command-name *commands-stats*) (1+ count)))
      ;; 执行命令
      (handler-case
          (apply handler args)
        (error (c)
          (list :type :error
                :command command-name
                :error (format nil "~a" c)
                :display (format nil "命令执行失败：~a" c)))))))

;;;; 命令帮助

(defun list-commands ()
  "列出所有可用命令"
  (let ((commands nil))
    (maphash (lambda (name spec)
               (push (list :name name
                           :doc (third spec)
                           :count (gethash name *commands-stats* 0))
                     commands))
             *system-commands*)
    (sort commands #'string< :key #'first)))

(defun get-command-help (command-name)
  "获取命令帮助"
  (let ((cmd (gethash command-name *system-commands*)))
    (when cmd
      (list :name (first cmd)
            :doc (third cmd)
            :args (fourth cmd)
            :count (gethash command-name *commands-stats* 0)))))

(defun get-commands-stats ()
  "获取命令统计"
  (let ((total *commands-executed-counter*)
        (by-command nil))
    (maphash (lambda (name count)
               (push (list :name name :count count) by-command))
             *commands-stats*)
    (list :total total
          :by-command (sort by-command #'> :key #'second))))

;;;; 初始化

(defun init-system-commands ()
  "初始化系统命令

   注册所有内置命令和别名"
  ;; 内置命令已在 define-command 中注册
  ;; 注册中文别名
  (setf (gethash "骰子" *command-aliases*) "-roll")
  (setf (gethash "猜拳" *command-aliases*) "-rps")
  (setf (gethash "抽签" *command-aliases*) "-draw")
  (setf (gethash "运势" *command-aliases*) "-fortune")
  (log-info "System commands initialized"))

;;;; 导出公共 API
;;;; (Symbols are exported via package.lisp)
