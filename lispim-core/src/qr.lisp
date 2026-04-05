;;;; qr.lisp - QR Code Services
;;;;
;;;; Provides QR code generation and scanning for user profiles
;;;; Support for adding friends via QR code

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :cl-json :ironclad :cl-base64 :flexi-streams)))

;;;; QR Code Data Format
;;;;
;;;; QR codes contain a JSON payload with the following structure:
;;;; {
;;;;   "type": "user_profile" | "group_invite",
;;;;   "userId": "user id",
;;;;   "username": "username",
;;;;   "timestamp": 1234567890,
;;;;   "signature": "hmac signature"
;;;; }

;;;; Constants

(defparameter *qr-secret-key* "lispim-qr-secret-key-2026"
  "Secret key for QR code signature")

(defparameter *qr-expiry-seconds* 86400  ; 24 hours
  "QR code validity period")

;;;; QR Code Generation

(defun generate-qr-payload (user-id username)
  "Generate QR code payload for user"
  (declare (type string user-id username))

  (let* ((now (floor (get-universal-time)))
         (payload (list :type "user_profile"
                        :userId user-id
                        :username username
                        :timestamp now)))
    payload))

(defun sign-qr-payload (payload)
  "Sign QR payload with HMAC-SHA256"
  (let* ((payload-json (cl-json:encode-json-to-string payload))
         (payload-octets (babel:string-to-octets payload-json))
         (hmac (ironclad:make-hmac (babel:string-to-octets *qr-secret-key*) :sha256))
         (signature (progn
                      (ironclad:update-hmac hmac payload-octets)
                      (ironclad:hmac-digest hmac))))
    (list :payload payload-json
          :signature (cl-base64:usb8-array-to-base64-string signature))))

(defun generate-qr-code (user-id username)
  "Generate QR code data for user"
  (declare (type string user-id username))

  (let* ((payload (generate-qr-payload user-id username))
         (signed (sign-qr-payload payload))
         (qr-data (list :type "user_profile"
                        :userId user-id
                        :username username
                        :timestamp (getf (first (cl-json:decode-json-from-string
                                                  (getf signed :payload))) :|timestamp|)
                        :signature (getf signed :signature))))
    (values (cl-json:encode-json-to-string qr-data)
            qr-data)))

;;;; QR Code Verification

(defun verify-qr-signature (payload-json signature)
  "Verify QR code signature"
  (let* ((payload-octets (babel:string-to-octets payload-json))
         (hmac (ironclad:make-hmac (babel:string-to-octets *qr-secret-key*) :sha256))
         (expected-sig (progn
                         (ironclad:update-hmac hmac payload-octets)
                         (cl-base64:usb8-array-to-base64-string (ironclad:hmac-digest hmac))))
         (provided-sig signature))
    (string= expected-sig provided-sig)))

(defun verify-qr-timestamp (timestamp)
  "Check if QR code timestamp is within validity period"
  (let* ((now (floor (get-universal-time)))
         (age (- now timestamp)))
    (and (>= age 0)
         (<= age *qr-expiry-seconds*))))

(defun decode-and-verify-qr (qr-json)
  "Decode and verify QR code, return user info if valid"
  (let* ((data (cl-json:decode-json-from-string qr-json))
         (type (getf data :|type|))
         (user-id (getf data :|userId|))
         (username (getf data :|username|))
         (timestamp (getf data :|timestamp|))
         (signature (getf data :|signature|)))

    ;; Verify type
    (unless (string= type "user_profile")
      (return-from decode-and-verify-qr (values nil "invalid_qr_type")))

    ;; Verify signature
    (let ((payload (cl-json:encode-json-to-string
                    (list :type type
                          :userId user-id
                          :username username
                          :timestamp timestamp))))
      (unless (verify-qr-signature payload signature)
        (return-from decode-and-verify-qr (values nil "invalid_signature"))))

    ;; Verify timestamp
    (unless (verify-qr-timestamp timestamp)
      (return-from decode-and-verify-qr (values nil "expired_qr")))

    ;; Return user info
    (values (list :user-id user-id
                  :username username)
            nil)))

;;;; QR Code for Group Invite

(defun generate-group-qr-code (group-id group-name creator-id)
  "Generate QR code for group invitation"
  (declare (type integer group-id)
           (type string group-name creator-id))

  (let* ((now (floor (get-universal-time)))
         (payload (list :type "group_invite"
                        :groupId group-id
                        :groupName group-name
                        :creatorId creator-id
                        :timestamp now))
         (payload-json (cl-json:encode-json-to-string payload))
         (payload-octets (babel:string-to-octets payload-json))
         (hmac (ironclad:make-hmac (babel:string-to-octets *qr-secret-key*) :sha256))
         (signature (progn
                      (ironclad:update-hmac hmac payload-octets)
                      (cl-base64:usb8-array-to-base64-string (ironclad:hmac-digest hmac)))))

    (cl-json:encode-json-to-string
     (list :type "group_invite"
           :groupId group-id
           :groupName group-name
           :creatorId creator-id
           :timestamp now
           :signature signature))))

;;;; Export Functions

(export '(generate-qr-code
          decode-and-verify-qr
          generate-group-qr-code
          *qr-secret-key*
          *qr-expiry-seconds*))