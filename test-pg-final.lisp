;;;; test-pg-final.lisp - Final PostgreSQL connection test

;; Try to set external format before connection
(setf *default-pathname-defaults*
      (merge-pathnames (make-pathname :external-format :utf-8)
                       *default-pathname-defaults*))

(ql:quickload '(:postmodern))

(in-package :postmodern)

(format t "~%=== PostgreSQL Connection Test ===~%~%")

;; Enable debug output
(setf cl-postgres-trace:*trace-query-p* nil)

(handler-case
    (let* ((db-config (list :database "lispim"
                            :user "lispim"
                            :password "Clsper03"
                            :host "127.0.0.1"
                            :port 5432)))

      (format t "Config: ~A~%~%" db-config)
      (format t "Connecting...~%")

      ;; Connect
      (connect "lispim" "lispim" "Clsper03" "127.0.0.1" :port 5432 :use-ssl :no)

      (format t "SUCCESS!~%")

      ;; Test query
      (query "SELECT 1 as test"))

  (condition (c)
    (format t "Condition: ~A~%" c)
    (format t "Class: ~A~%" (class-name (class-of c))))
  (:default (other)
    (format t "Other: ~A~%" other)))

(uiop:quit 0)
