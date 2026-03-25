;;;; start-server-test.lisp - Start the server for testing

;; Register the system path
(pushnew #P"D:/Claude/LispIM/lispim-core/" asdf:*central-registry* :test #'equal)

;; Force recompilation by deleting FASL files
(let ((fasl-dir #P"C:/Users/Administrator/AppData/Local/cache/common-lisp/sbcl-2.5.8-win-x64/D/Claude/LispIM/lispim-core/src/"))
  (when (probe-file fasl-dir)
    (dolist (file (directory (merge-pathnames "*.fasl" fasl-dir)))
      (ignore-errors (delete-file file)))))

;; Load and compile the system
(asdf:load-system :lispim-core :force t)

(format t "~%Starting LispIM server...~%")

;; Start the gateway
(lispim-core:start-server)

(format t "~%Server started!~%")

;; Test the JSON parsing directly
(let* ((json-str "{\"username\":\"admin\",\"password\":\"admin123\"}")
       (data (cl-json:decode-json-from-string json-str :key-fn #'string-downcase))
       (username (cdr (assoc "username" data :test #'string=)))
       (password (cdr (assoc "password" data :test #'string=))))
  (format t "DEBUG: Parsed data: ~a~%" data)
  (format t "Username: ~a, Password: ~a~%" username password))

(quit)
