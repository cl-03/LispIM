;;; test-package.lisp — Test package definition for LispIM client
;;;
;;; This file defines the test package for the LispIM client tests.

(defpackage :lispim-client/test
  (:use :common-lisp :fiveam :cl-mock)
  (:export :run!
           :test-api-client
           :test-websocket
           :test-auth))

(in-package :lispim-client/test)
