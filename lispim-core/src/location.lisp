;;;; location.lisp - Location-Based Services
;;;;
;;;; Provides "People Nearby" (附近的人) functionality
;;;; including location reporting, storage, and proximity search

(in-package :lispim-core)

;;;; Dependencies

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload '(:postmodern :cl-redis :bordeaux-threads :cl-json)))

;;;; Configuration

(defparameter *location-ttl* 3600  ; 1 hour
  "TTL for location data in Redis (seconds)")

(defparameter *nearby-max-results* 50
  "Maximum number of nearby users to return")

;;;; Location Data Structure

(defstruct location
  (user-id "" :type string)
  (latitude 0.0 :type float)
  (longitude 0.0 :type float)
  (accuracy 0.0 :type float)
  (timestamp 0 :type integer)
  (city "")
  (district ""))

;;;; Redis Key Patterns

(defun location-key (user-id)
  "Get Redis key for user location"
  (format nil "location:user:~a" user-id))

(defun nearby-geo-key ()
  "Get Redis key for geo index"
  "location:geo")

;;;; Redis Helper Functions (using cl-redis directly)

(defun get-redis ()
  "Get Redis connection"
  (ensure-redis-connected)
  *redis-client*)

(defun location-set-key-with-ttl (key value ttl)
  "Set key with TTL in Redis"
  (declare (type string key value)
           (type integer ttl))
  (let ((redis (get-redis)))
    (redis:red-set key value)
    (redis:red-expire key ttl)))

(defun location-get-key (key)
  "Get key from Redis"
  (declare (type string key))
  (let ((redis (get-redis)))
    (redis:red-get key)))

(defun location-del-key (key)
  "Delete key from Redis"
  (declare (type string key))
  (let ((redis (get-redis)))
    (redis:red-del key)))

(defun location-zadd (key score member)
  "Add member to sorted set"
  (declare (type string key member)
           (type number score))
  (let ((redis (get-redis)))
    (redis:red-zadd key score member)))

(defun location-zrem (key member)
  "Remove member from sorted set"
  (declare (type string key member))
  (let ((redis (get-redis)))
    (redis:red-zrem key member)))

(defun location-zrangebyscore (key min-score max-score)
  "Get members from sorted set by score range"
  (declare (type string key)
           (type number min-score max-score))
  (let ((redis (get-redis)))
    (redis:red-zrangebyscore key min-score max-score)))

;;;; Location Storage

(defun store-user-location (user-id latitude longitude accuracy city district)
  "Store user location in Redis with TTL"
  (declare (type string user-id)
           (type float latitude longitude accuracy)
           (type string city district))

  (let* ((now (floor (get-universal-time)))
         (key (location-key user-id))
         (geo-key (nearby-geo-key))
         (location-json (cl-json:encode-json-to-string
                         (list :userId user-id
                               :latitude latitude
                               :longitude longitude
                               :accuracy accuracy
                               :timestamp now
                               :city city
                               :district district)))
         ;; Use geohash-like encoding: combine lat/lon into a single score
         ;; This is a simplified approach - real geohash would be more complex
         (geo-score (+ (* latitude 1000) longitude)))

    ;; Store location JSON
    (location-set-key-with-ttl key location-json *location-ttl*)

    ;; Add to geo index for proximity search (using sorted set)
    (location-zadd geo-key geo-score user-id)
    (redis:red-expire geo-key *location-ttl*)

    t))

(defun get-user-location (user-id)
  "Get user location from Redis"
  (declare (type string user-id))

  (let* ((key (location-key user-id))
         (location-json (location-get-key key)))

    (if location-json
        (let ((data (cl-json:decode-json-from-string location-json)))
          (make-location
           :user-id (getf data :|userId|)
           :latitude (getf data :|latitude|)
           :longitude (getf data :|longitude|)
           :accuracy (getf data :|accuracy|)
           :timestamp (getf data :|timestamp|)
           :city (getf data :|city|)
           :district (getf data :|district|)))
        nil)))

(defun delete-user-location (user-id)
  "Delete user location"
  (declare (type string user-id))

  (let* ((key (location-key user-id))
         (geo-key (nearby-geo-key)))

    ;; Delete from Redis
    (location-del-key key)

    ;; Remove from geo index
    (location-zrem geo-key user-id)

    t))

;;;; Nearby Users Search

(defun get-nearby-users (latitude longitude radius-in-km)
  "Search for users within radius (km) of given coordinates"
  (declare (type float latitude longitude radius-in-km))

  (let* ((geo-key (nearby-geo-key))
         ;; Calculate score range for proximity search
         (min-lat (- latitude (/ radius-in-km 111.0)))  ;; 1 degree ≈ 111km
         (max-lat (+ latitude (/ radius-in-km 111.0)))
         (min-lon (- longitude (/ radius-in-km 111.0)))
         (max-lon (+ longitude (/ radius-in-km 111.0)))
         (min-score (+ (* min-lat 1000) min-lon))
         (max-score (+ (* max-lat 1000) max-lon))
         (result '()))

    ;; Use ZRANGEBYSCORE to find users in range
    (let ((members (location-zrangebyscore geo-key min-score max-score)))
      (when members
        (loop for user-id in members
              for location = (get-user-location user-id)
              when location
              do (let ((dist (calculate-distance latitude longitude
                                                 (location-latitude location)
                                                 (location-longitude location))))
                   (when (<= dist radius-in-km)
                     (push (list :user-id user-id
                                 :latitude (location-latitude location)
                                 :longitude (location-longitude location)
                                 :distance dist
                                 :timestamp (location-timestamp location)
                                 :city (location-city location)
                                 :district (location-district location))
                           result))))))

    (nreverse result)))

(defun get-nearby-users-by-city (city district)
  "Get nearby users by city/district"
  (declare (type string city district))

  ;; Iterate through recent locations and filter by city
  (let ((result '()))

    ;; Get all keys matching location:user:*
    (let* ((pattern "location:user:*")
           (keys (redis:red-keys pattern)))

      (when keys
        (loop for key in keys
              for json = (location-get-key key)
              when json
              do (let* ((data (cl-json:decode-json-from-string json))
                        (data-city (getf data :|city|))
                        (data-district (getf data :|district|)))
                   (when (and (string= data-city city)
                              (or (null district)
                                  (string= data-district district)))
                     (push (list :user-id (getf data :|userId|)
                                 :latitude (getf data :|latitude|)
                                 :longitude (getf data :|longitude|)
                                 :city data-city
                                 :district data-district
                                 :timestamp (getf data :|timestamp|))
                           result))))))

    result))

;;;; Privacy Controls

(defun set-location-privacy (user-id visible)
  "Set user location privacy setting"
  (declare (type string user-id boolean visible))

  (let ((key (format nil "location:privacy:~a" user-id)))
    (if visible
        (location-del-key key)  ; No key = visible
        (location-set-key-with-ttl key "hidden" 86400))  ; Hidden for 24 hours
    t))

(defun is-location-visible (user-id)
  "Check if user location is visible"
  (declare (type string user-id))

  (let ((key (format nil "location:privacy:~a" user-id)))
    (null (location-get-key key))))  ; Visible if key doesn't exist

;;;; Haversine Distance Calculation

(defun calculate-distance (lat1 lon1 lat2 lon2)
  "Calculate distance between two points in kilometers using Haversine formula"
  (declare (type float lat1 lon1 lat2 lon2))

  (let* ((earth-radius 6371.0)
         (lat1-rad (deg-to-rad lat1))
         (lat2-rad (deg-to-rad lat2))
         (dlat (deg-to-rad (- lat2 lat1)))
         (dlon (deg-to-rad (- lon2 lon1)))
         (a (+ (* (sin (/ dlat 2)) (sin (/ dlat 2)))
               (* (cos lat1-rad) (cos lat2-rad)
                  (sin (/ dlon 2)) (sin (/ dlon 2)))))
         (c (* 2 (atan (sqrt a) (sqrt (- 1 a))))))
    (* earth-radius c)))

(defun deg-to-rad (deg)
  "Convert degrees to radians"
  (declare (type float deg))
  (* deg (/ pi 180.0)))

;;;; Export Functions

(export '(store-user-location
          get-user-location
          delete-user-location
          get-nearby-users
          get-nearby-users-by-city
          set-location-privacy
          is-location-visible
          calculate-distance
          *location-ttl*
          *nearby-max-results*))
