(in-package :cleric)

;;;;
;;;; Erlang list
;;;;

;;;
;;; Methods
;;;

(defmethod match-p ((a list) (b list))
  (every #'match-p a b))

(defmethod match-p ((a string) (b string))
  (string= a b))


;;;
;;; Encode/Decode
;;;

(defmethod encode ((x list) &key atom-cache-entries &allow-other-keys)
  (if x
      (encode-external-list x atom-cache-entries)
      (encode-external-nil)))

(defmethod encode ((x string) &key &allow-other-keys)
  (cond (*lisp-string-is-erlang-binary*
         (encode (string-to-binary x)))
        ((> 65536 (length x))
         (encode-external-string x))
        (t
         (encode-external-list (map 'list #'char-code x)))))


;; NIL_EXT
;; +-----+
;; |  1  |
;; +-----+
;; | 106 |
;; +-----+
;;

(defun encode-external-nil ()
  (vector +nil-ext+))

(defun read-external-nil (stream)
  ;; Assume tag +nil-ext+ is read
  (decode-external-nil (read-bytes 0 stream)))

(defun decode-external-nil (bytes &optional (pos 0))
  (declare (ignore bytes))
  (values nil pos))


;; STRING_EXT
;; +-----+--------+------------+
;; |  1  |    2   |   Length   |
;; +-----+--------+------------+
;; | 107 | Length | Characters |
;; +-----+--------+------------+
;;

(defun encode-external-string (chars)
  (concatenate 'vector
               (vector +string-ext+)
               (uint16-to-bytes (length chars))
               (if (stringp chars)
                   (string-to-bytes chars)
                   (coerce chars 'vector))))

(defun read-external-string (stream) ;; OBSOLETE?
  ;; Assume tag +string-ext+ is read
  (let ((length-bytes (read-bytes 2 stream)))
    (decode-external-string
     (concatenate 'vector
                  length-bytes
                  (read-bytes (bytes-to-uint16 length-bytes) stream)))))

(defun decode-external-string (bytes &optional (pos 0))
  (let* ((length (bytes-to-uint16 bytes pos))
         (bytes (subseq bytes (+ 2 pos) (+ 2 length pos))))
    (values (if *erlang-string-is-lisp-string*
                (bytes-to-string bytes)
                (coerce bytes 'list))
            (+ 2 length pos))))



;; LIST_EXT
;; +-----+--------+----------+------+
;; |  1  |    4   |     N    |   M  |
;; +-----+--------+----------+------+
;; | 108 | Length | Elements | Tail |
;; +-----+--------+----------+------+
;;

(defun encode-external-list (list &optional atom-cache-entries)
  (multiple-value-bind (elements tail length)
      (list-contents-to-bytes list atom-cache-entries)
    (concatenate 'vector
                 (vector +list-ext+)
                 (uint32-to-bytes length)
                 elements
                 tail)))

(defun read-external-list (stream) ;; OBSOLETE?
  ;; Assume tag +list-ext+ is read
  (read-list-contents stream (read-uint32 stream)))

(defun decode-external-list (bytes &optional (pos 0))
  (decode-list-contents bytes (bytes-to-uint32 bytes pos) (+ 4 pos)))



;;; Helper functions

(defun list-contents-to-bytes (list &optional atom-cache-entries)
  (loop
     with bytes = #()
     for (element . tail) on list
     for length upfrom 1
     do (setf bytes (concatenate
                     'vector
                     bytes
                     (encode element :atom-cache-entries atom-cache-entries)))
     finally
       (let ((tail-bytes (if (and (null tail)
                                  *lisp-nil-at-tail-is-erlang-empty-list*)
                             (encode-external-nil)
                             (encode tail
                                     :atom-cache-entries atom-cache-entries))))
         (return (values bytes tail-bytes length))) ))

(defun read-list-contents (stream length)
  (if (= 0 length)
      (read-erlang-term stream)
      (cons (read-erlang-term stream)
            (read-list-contents stream (1- length)))))

(defun decode-list-contents (bytes length &optional (pos 0))
  (if (= 0 length)
      (decode bytes :start pos)
      (multiple-value-bind* (((term new-pos) (decode bytes :start pos))
                             ((tail end-pos)
                              (decode-list-contents bytes (1- length) new-pos)))
        (values (cons term tail) end-pos) )))
