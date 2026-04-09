;;;; macros.lisp - On Lisp Style Macros for LispIM
;;;;
;;;; This file contains advanced macros following the principles from
;;;; "On Lisp" by Paul Graham (1993)
;;;;
;;;; Note: Resource management macros (with-redis-connection, with-lock-held)
;;;; have been moved to utils.lisp to avoid package dependency issues at compile time.

(in-package :lispim-core)

;;;; =====================================================================
;;;; SECTION 1: Anaphoric Macros (On Lisp Chapter 8)
;;;; =====================================================================

(defmacro awhen (test &body body)
  "Anaphoric when - binds 'it' to result of test if non-nil
   Example: (awhen (find-user id) (print it))"
  `(let ((it ,test))
     (when it ,@body)))

(defmacro aand (&rest args)
  "Anaphoric and - binds 'it' to each arg sequentially
   Example: (aand (gethash id users) (gethash it sessions))"
  (cond ((null args) t)
        ((null (cdr args)) (car args))
        (t `(let ((it ,(car args)))
              (and it (aand ,@(cdr args)))))))

(defmacro aor (&rest args)
  "Anaphoric or - binds 'it' to first non-nil arg"
  (cond ((null args) nil)
        ((null (cdr args)) (car args))
        (t `(let ((it ,(car args)))
              (if it it (aor ,@(cdr args)))))))

(defmacro aif (test then-expr else-expr)
  "Anaphoric if - binds 'it' to result of test
   Example: (aif (find-user id) (use it) (create-new))"
  `(let ((it ,test))
     (if it ,then-expr ,else-expr)))

(defmacro aif* (bindings then-expr else-expr)
  "Sequential binding anaphoric if - binds 'it' to each binding
   Example: (aif* ((get-user id) (get-profile it)) (use it) (error))"
  (cond ((null bindings) `(progn ,then-expr))
        (t (let ((gval (gensym "VAL")))
             `(let ((,gval ,(car bindings)))
                (if ,gval
                    (let ((it ,gval))
                      (aif* ,(cdr bindings) ,then-expr ,else-expr))
                    ,else-expr))))))

(defmacro awhen* (bindings &body body)
  "Sequential binding anaphoric when - binds 'it' to each binding
   Example: (awhen* ((get-user id) (get-profile it)) (print it))"
  (cond ((null bindings) `(progn ,@body))
        (t `(aif* ,bindings (progn ,@body) nil))))

;;;; =====================================================================
;;;; SECTION 2: plist Utilities
;;;; =====================================================================

(defmacro with-plist-bindings ((plist &rest keys) &body body)
  "Bind multiple keys from a plist to local variables
   Example: (with-plist-bindings (user :id :username :email) ...)
   Creates local vars: id, username, email"
  (let ((plist-sym (gensym "PLIST")))
    `(let ((,plist-sym ,plist))
       (let ,(loop for key in keys
                   collect `(,(if (keywordp key)
                                  (intern (string key) (symbol-package key))
                                  key)
                             (getf ,plist-sym ,key)))
         ,@body))))

(defmacro define-getf* (name key &optional doc)
  "Define a getter for plist keys with consistent naming
   Example: (define-getf* user-id :id) creates (defun user-id (x) (getf x :id))"
  `(defun ,name (x)
     ,@(when doc `(,doc))
     (getf x ,key)))

;;;; =====================================================================
;;;; SECTION 3: Iteration Utilities
;;;; =====================================================================

(defmacro do-hash ((key-var val-var hash &optional result) &body body)
  "Iterate over hash-table entries
   Example: (do-hash (k v ht) (print (cons k v)))

   Note: key-var and val-var should be simple symbols, not expressions."
  (let ((hash-sym (gensym "HASH")))
    `(let ((,hash-sym ,hash))
       (maphash (lambda (,key-var ,val-var) ,@body) ,hash-sym)
       ,result)))

(defmacro accumulating ((collector init &key test) &body body)
  "Accumulate results with optional uniqueness test
   Example: (accumulating (result nil :test #'equal) (dolist (x items) (result x)))

   Note: The item argument to collector is evaluated exactly once."
  (let ((result-sym (gensym "RESULT"))
        (item-var (gensym "ITEM"))
        (test-var (gensym "TEST")))
    `(let ((,result-sym ,init)
           (,test-var ,test))
       (macrolet ((,collector (,item-var)
                    `(progn
                       ,@(if test-var
                             `((unless (find ,item-var ,,result-sym :test ,,test-var)
                                 (push ,item-var ,,result-sym)))
                             `((push ,item-var ,,result-sym))))))
         ,@body
         (nreverse ,result-sym)))))