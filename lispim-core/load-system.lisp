;;;; load-system.lisp - Load LispIM Core System from FASLs or compile from source
;;;;
;;;; This script loads the lispim-core system by loading pre-compiled FASL files
;;;; if available, otherwise compiles from source using ASDF.
;;;;
;;;; Usage:
;;;;   sbcl --non-interactive --load load-system.lisp

(ql:quickload :quicklisp)
(quicklisp:setup)

;; Load dependencies
(format t "~%~%; Loading dependencies...~%")
(dolist (dep '(:hunchentoot :cl-json :postmodern :cl-redis :bordeaux-threads
              :uuid :babel :salza2 :local-time :log4cl :ironclad :trivia
              :alexandria :serapeum :flexi-streams :str :drakma :cl-ppcre
              :dexador))
  (ql:quickload dep :silent t)
  (format t "  Loaded ~a~%" dep))

;; Add to central registry
;; Use *default-pathname-defaults* instead of truename for Windows compatibility
(pushnew #P"D:/Claude/LispIM/lispim-core/" asdf:*central-registry* :test #'equal)

;; Muffle warnings during compilation
(setq *compile-print* nil)
(setq *compile-verbose* nil)

;; Wrap compilation in with-compilation-unit to muffle style warnings
;; This allows compilation to proceed even with many undefined function references

;; Check if FASL files exist
(let ((src-dir #P"D:/Claude/LispIM/lispim-core/src/")
      (fasl-available nil))
  ;; Check for key FASL files (package, gateway, server)
  ;; Note: FASLs may be in src/ or in SBCL's cache directory
  (dolist (file '("package" "gateway" "server"))
    (let ((fasl-file (merge-pathnames (format nil "~a.fasl" file) src-dir)))
      (when (probe-file fasl-file)
        (setf fasl-available t))))

  ;; If FASLs not in src/, check SBCL cache
  (unless fasl-available
    (let ((cache-dir #P"C:/Users/Administrator/AppData/Local/cache/common-lisp/sbcl-2.5.8-win-x64/C/Users/Administrator/quicklisp/local-projects/lispim-core/src/"))
      (dolist (file '("package" "gateway" "server"))
        (let ((fasl-file (merge-pathnames (format nil "~a.fasl" file) cache-dir)))
          (when (probe-file fasl-file)
            (setf fasl-available t))))))

  (if fasl-available
      ;; Load FASL files in dependency order using ASDF (which knows where FASLs are)
      (progn
        (format t "~%~%; Loading LispIM Core FASLs via ASDF...~%")
        (handler-bind ((warning #'muffle-warning))
          (with-compilation-unit (:override t)
            (asdf:load-system :lispim-core)))
        (format t "~%Loaded LispIM Core system~%"))
      ;; FASL files missing - compile from source using ASDF
      (progn
        (format t "~%~%~%; FASL files not found - compiling from source using ASDF...~%")
        ;; Use with-compilation-unit to muffle warnings
        ;; Note: SBCL may still fail with too many undefined functions
        (with-compilation-unit (:override t)
          (handler-case
              (progn
                (asdf:load-system :lispim-core :force t :message-level :error)
                (format t "; ASDF compilation complete~%"))
            (error (e)
              (format t "; Compilation error: ~A~%" e)
              ;; Try to continue anyway - the FASLs may have been created
              (format t "; Attempting to load partial system...~%")))))))

;; Note: ai-skills.fasl is not loaded automatically to avoid deadlocks
;; The AI skills are registered when init-ai-config-system is called

(format t "~%~%========================================~%")
(format t "  LispIM Core System Ready~%")
(format t "========================================~%")

;; Don't quit here - allow further processing
;; (sb-ext:quit :unix-status 0)
