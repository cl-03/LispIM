;;;; markdown.lisp - Markdown 渲染模块
;;;;
;;;; 实现 Markdown 格式解析和渲染
;;;; Features: 基础 Markdown 语法、代码高亮、表格、任务列表
;;;;
;;;; 参考：GitHub Flavored Markdown, CommonMark

(in-package :lispim-core)

;;;; 依赖声明

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:cl-ppcre :alexandria)))

;;;; Markdown 配置

(defparameter *markdown-options*
  '(:gfm t                    ; GitHub Flavored Markdown
    :breaks t                 ; 启用硬换行
    :linkify t                ; 自动链接 URL
    :highlight t)             ; 代码高亮
  "Markdown 渲染选项")

;;;; 支持的最大嵌套层级

(defparameter *max-nesting-level* 10
  "最大嵌套层级，防止 DoS 攻击")

;;;; 基础语法解析

(defun parse-markdown-inline (text)
  "解析行内 Markdown 元素
   支持：*italic*, **bold**, ~~strikethrough~~, `code`, [link](url)"
  (declare (type string text))

  (let ((result text))
    ;; 1. Code spans (先处理，避免与其他语法冲突)
    ;; `code` -> <code>code</code>
    (setf result (cl-ppcre:regex-replace-all
                  "`([^`]+)`"
                  result
                  "<code>\\1</code>"))

    ;; 2. Bold (**text** or __text__)
    ;; **bold** -> <strong>bold</strong>
    (setf result (cl-ppcre:regex-replace-all
                  "\\*\\*([^*]+)\\*\\*"
                  result
                  "<strong>\\1</strong>"))
    (setf result (cl-ppcre:regex-replace-all
                  "__([^_]+)__"
                  result
                  "<strong>\\1</strong>"))

    ;; 3. Italic (*text* or _text_)
    ;; *italic* -> <em>italic</em>
    (setf result (cl-ppcre:regex-replace-all
                  "(?<!\\*)\\*([^*]+)\\*(?!\\*)"
                  result
                  "<em>\\1</em>"))
    (setf result (cl-ppcre:regex-replace-all
                  "(?<!_)_([^_]+)_(?!_)"
                  result
                  "<em>\\1</em>"))

    ;; 4. Strikethrough (~~text~~)
    ;; ~~deleted~~ -> <del>deleted</del>
    (setf result (cl-ppcre:regex-replace-all
                  "~~([^~]+)~~"
                  result
                  "<del>\\1</del>"))

    ;; 5. Links [text](url)
    ;; [Google](https://google.com) -> <a href="...">Google</a>
    (setf result (cl-ppcre:regex-replace-all
                  "\\[([^\\]]+)\\]\\(([^)]+)\\)"
                  result
                  "<a href=\"\\2\">\\1</a>"))

    ;; 6. Images ![alt](url)
    ;; ![Image](image.png) -> <img src="..." alt="...">
    (setf result (cl-ppcre:regex-replace-all
                  "!\\[([^\\]]*)\\]\\(([^)]+)\\)"
                  result
                  "<img src=\"\\2\" alt=\"\\1\"/>"))

    ;; 7. Autolink URLs
    ;; https://example.com -> <a href="...">...</a>
    (when (getf *markdown-options* :linkify)
      (setf result (cl-ppcre:regex-replace-all
                    "(https?://[^\\s\\)\\\"\\<]+)"
                    result
                    "<a href=\"\\1\" target=\"_blank\" rel=\"noopener\">\\1</a>")))

    result))

(defun parse-markdown-block (text)
  "解析块级 Markdown 元素
   支持：headings, blockquotes, lists, code blocks, tables"
  (declare (type string text))

  (let ((lines (cl-ppcre:split "\\n" text))
        (result-lines nil)
        (in-code-block nil)
        (code-lang nil)
        (code-content nil)
        (in-list nil)
        (list-type nil)
        (list-items nil)
        (in-blockquote nil)
        (blockquote-content nil)
        (in-table nil)
        (table-rows nil)
        (table-header-p nil))

    (flet ((flush-code-block ()
             (when code-content
               (let ((highlighted (if (getf *markdown-options* :highlight)
                                      (highlight-code code-content code-lang)
                                      (escape-html code-content))))
                 (push (format nil "<pre><code class=\"language-~a\">~a</code></pre>"
                               (or code-lang "text") highlighted)
                       result-lines)))
             (setf code-content nil
                   code-lang nil
                   in-code-block nil))

           (flush-list ()
             (when list-items
               (let ((tag (if (eq list-type :ordered) "ol" "ul")))
                 (push (format nil "<~a>~{<li>~a</li>~}</~a>"
                               tag (nreverse list-items) tag)
                       result-lines)))
             (setf list-items nil
                   in-list nil
                   list-type nil))

           (flush-blockquote ()
             (when blockquote-content
               (push (format nil "<blockquote>~a</blockquote>"
                             (parse-markdown-inline blockquote-content))
                     result-lines))
             (setf blockquote-content nil
                   in-blockquote nil))

           (flush-table ()
             (when table-rows
               (let ((rows-html (loop for (row . is-header) in table-rows
                                      collect (format nil "<tr>~{<~a>~a</~a>~}</tr>"
                                                      (loop for cell in row
                                                            collect (if is-header "th" "td")
                                                            collect (parse-markdown-inline cell)
                                                            collect (if is-header "th" "td"))))))
                 (push (format nil "<table>~{~a~}</table>" (nreverse rows-html))
                       result-lines)))
             (setf table-rows nil
                   in-table nil
                   table-header-p nil)))

      (dolist (line lines)
        (cond
          ;; Code block start/end
          ((cl-ppcre:scan "^```" line)
           (if in-code-block
               (flush-code-block)
               (progn
                 (flush-list)
                 (flush-blockquote)
                 (setf in-code-block t
                       code-lang (cl-ppcre:regex-replace "^```\\s*" line "")))))

          (in-code-block
           (setf code-content (concatenate 'string code-content line (string #\Newline))))

          ;; Headings
          ((cl-ppcre:scan "^#{1,6}\\s+" line)
           (flush-list)
           (flush-blockquote)
           (let* ((hash-start 0)
                  (hash-end (position-if-not (lambda (c) (char= c #\#)) line :start 0))
                  (level (or hash-end 1)))
             (push (format nil "<h~a>~a</h~a>"
                           level
                           (parse-markdown-inline (cl-ppcre:regex-replace "^#{1,6}\\s+" line ""))
                           level)
                   result-lines)))

          ;; Blockquote
          ((cl-ppcre:scan "^>\\s*" line)
           (flush-list)
           (setf in-blockquote t)
           (setf blockquote-content
                 (concatenate 'string blockquote-content
                              (cl-ppcre:regex-replace "^>\\s*" line "")
                              " ")))

          ;; Ordered list item
          ((cl-ppcre:scan "^\\d+\\.\\s+" line)
           (when (and in-list (not (eq list-type :ordered)))
             (flush-list))
           (setf in-list t
                 list-type :ordered)
           (push (cl-ppcre:regex-replace "^\\d+\\.\\s+" line "") list-items))

          ;; Unordered list item
          ((cl-ppcre:scan "^[-*+]\\s+" line)
           (when (and in-list (not (eq list-type :unordered)))
             (flush-list))
           (setf in-list t
                 list-type :unordered)
           (push (parse-markdown-inline (cl-ppcre:regex-replace "^[-*+]\\s+" line ""))
                 list-items))

          ;; Table row
          ((cl-ppcre:scan "^\\|" line)
           (let ((cells (remove-if #'string-empty-p
                                   (cl-ppcre:split "\\|" line))))
             (if (cl-ppcre:scan "^\\|\\s*[-:]+\\s*\\|" line)
                 ;; Separator row - skip
                 nil
                 (progn
                   (setf in-table t)
                   (push (list cells table-header-p) table-rows)
                   (setf table-header-p nil)))))

          ;; Task list item (GFM)
          ((cl-ppcre:scan "^[-*+]\\s+\\[[ xX]\\]\\s+" line)
           (let* ((checked-p (not (null (cl-ppcre:scan "\\[x\\]" line :case-insensitive-mode t))))
                  (content (cl-ppcre:regex-replace "^[-*+]\\s+\\[[ xX]\\]\\s+" line "")))
             (when (and in-list (not (eq list-type :task)))
               (flush-list))
             (setf in-list t
                   list-type :task)
             (push (format nil "<label class=\"task-list-item\"><input type=\"checkbox\"~a disabled> ~a</label>"
                           (if checked-p " checked" "")
                           (parse-markdown-inline content))
                   list-items)))

          ;; Empty line
          ((string-empty-p (cl-ppcre:regex-replace "^\\s*$" line ""))
           (flush-code-block)
           (flush-list)
           (flush-blockquote)
           (push "" result-lines))

          ;; Regular paragraph
          (t
           (flush-code-block)
           (flush-list)
           (flush-blockquote)
           (push (format nil "<p>~a</p>" (parse-markdown-inline line))
                 result-lines))))

      ;; Flush remaining
      (flush-code-block)
      (flush-list)
      (flush-blockquote)
      (flush-table))

    ;; Join and return
    (format nil "~{~a~%~}" (nreverse result-lines))))

;;;; 代码高亮

(defun highlight-code (code &optional (language "text"))
  "简单的代码高亮（基础实现）"
  (declare (type string code))

  ;; 基础关键词高亮
  (let ((result (escape-html code)))
    ;; Lisp 关键词
    (when (member language '("lisp" "common-lisp" "cl" "scheme") :test #'string-equal)
      (setf result (cl-ppcre:regex-replace-all
                    "(?i)\\b(defun|defmacro|defvar|defparameter|let|lambda|if|when|unless|cond|loop|do|return|setq|setf|format|declare|type)\\b"
                    result
                    "<span class=\"keyword\">\\1</span>"))
      (setf result (cl-ppcre:regex-replace-all
                    "(?i);;;.*$"
                    result
                    "<span class=\"comment\">\\1</span>")))

    ;; JavaScript 关键词
    (when (member language '("javascript" "js" "typescript" "ts") :test #'string-equal)
      (setf result (cl-ppcre:regex-replace-all
                    "(?i)\\b(function|const|let|var|if|else|return|for|while|class|import|export|from|async|await|try|catch|throw|new|this)\\b"
                    result
                    "<span class=\"keyword\">\\1</span>")))

    ;; Python 关键词
    (when (member language '("python" "py") :test #'string-equal)
      (setf result (cl-ppcre:regex-replace-all
                    "(?i)\\b(def|class|if|elif|else|for|while|return|import|from|as|with|try|except|raise|lambda|yield|async|await)\\b"
                    result
                    "<span class=\"keyword\">\\1</span>")))

    ;; 字符串高亮（通用）
    (setf result (cl-ppcre:regex-replace-all
                  "\"([^\"]*)\""
                  result
                  "<span class=\"string\">\"\\1\"</span>"))

    ;; 数字高亮（通用）
    (setf result (cl-ppcre:regex-replace-all
                  "\\b(\\d+)\\b"
                  result
                  "<span class=\"number\">\\1</span>"))

    result))

;;;; HTML 转义

(defun escape-html (text)
  "转义 HTML 特殊字符"
  (declare (type string text))
  (let ((result text))
    (setf result (cl-ppcre:regex-replace-all "&" result "&amp;"))
    (setf result (cl-ppcre:regex-replace-all "<" result "&lt;"))
    (setf result (cl-ppcre:regex-replace-all ">" result "&gt;"))
    (setf result (cl-ppcre:regex-replace-all "\"" result "&quot;"))
    (setf result (cl-ppcre:regex-replace-all "'" result "&#39;"))
    result))

;;;; 空字符串判断

(defun string-empty-p (str)
  "检查字符串是否为空"
  (declare (type string str))
  (or (null str)
      (zerop (length str))
      (every #'whitespacep str)))

;;;; 主函数

(defun render-markdown (text &key (options *markdown-options*))
  "将 Markdown 文本渲染为 HTML
   参数:
   - text: Markdown 格式的输入文本
   - options: 渲染选项 plist
     - :gfm t/nil - GitHub Flavored Markdown
     - :breaks t/nil - 启用硬换行
     - :linkify t/nil - 自动链接 URL
     - :highlight t/nil - 代码高亮

   返回: HTML 字符串"
  (declare (type string text)
           (type list options))

  ;; 保存原始选项
  (let ((*markdown-options* options))
    (handler-case
        (progn
          ;; 预处理：标准化换行符
          (let ((normalized (cl-ppcre:regex-replace-all "\\r\\n" text "
")))
            ;; 解析块级元素
            (parse-markdown-block normalized)))
      (error (c)
        ;; 解析失败时返回原始文本（转义后）
        (log-error "Markdown parse error: ~a" c)
        (escape-html text)))))

(defun markdown-to-html (text)
  "将 Markdown 转换为 HTML（快捷函数）"
  (declare (type string text))
  (render-markdown text))

;;;; 消息内容 Markdown 渲染

(defun render-message-content (content &key (message-type :text))
  "渲染消息内容，支持 Markdown
   如果消息类型是 :text，则渲染 Markdown
   否则返回原始内容"
  (declare (type (or null string) content)
           (type keyword message-type))

  (unless content
    (return-from render-message-content ""))

  (cond
    ((eq message-type :text)
     (render-markdown content))
    (t
     ;; 非文本消息不进行 Markdown 渲染
     (escape-html content))))

;;;; 导出

(export '(;; Main functions
          render-markdown
          markdown-to-html
          render-message-content

          ;; Helpers
          parse-markdown-inline
          parse-markdown-block
          highlight-code
          escape-html

          ;; Configuration
          *markdown-options*
          *max-nesting-level*)
        :lispim-core)

;;;; End of markdown.lisp
