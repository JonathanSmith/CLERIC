(in-package :cleric)

;;;;
;;;; Erlang atom
;;;;

;;;
;;; Methods
;;;

(defun make-atom (string)
  (if *atom-symbol-package*
      (intern string *atom-symbol-package*)
      (make-symbol string)))

(defmethod match-p ((a symbol) (b symbol))
  (eql a b)) ;; What about symbols in different packages?


;;;
;;; Encode/Decode
;;;

(defmethod encode ((x symbol) &key atom-cache-entries &allow-other-keys)
  (cond
    ((and (null x) *lisp-nil-is-erlang-empty-list*)
     (encode-external-nil))
    ((and (null x) *lisp-nil-is-erlang-false*)
     (encode '|false| :atom-cache-entries atom-cache-entries))
    ((and (eq T x) *lisp-t-is-erlang-true*)
     (encode '|true| :atom-cache-entries atom-cache-entries))
    (t
     (let ((index (when atom-cache-entries
                    (make-atom-cache-entry x atom-cache-entries))))
       (cond
         (index ;; Use an atom cache reference
          (encode-external-atom-cache-ref index))
         ;; Encode the atom as usual
         ((> 256 (length (symbol-name x)))
          (encode-external-small-atom x))
         (t
          (encode-external-atom x)) ))) ))

(defun decode-erlang-atom (bytes &optional (pos 0))
  (let ((tag (aref bytes pos)))
    (multiple-value-bind (symbol pos2)
        (case tag
          (#.+atom-cache-ref+
           (decode-external-atom-cache-ref bytes (1+ pos)))
          (#.+atom-ext+
           (decode-external-atom bytes (1+ pos)))
          (#.+small-atom-ext+
           (decode-external-small-atom bytes (1+ pos)))
          (#.+compressed-term+
           (decode-compressed-erlang-term bytes (1+ pos)))
          (otherwise
           (error 'unexpected-message-tag-error
                  :received-tag tag
                  :expected-tags (list +atom-cache-ref+
                                       +atom-ext+
                                       +small-atom-ext+
                                       +compressed-term+))) )
      (cond
        ((and (eq symbol '|true|) *erlang-true-is-lisp-t*)
         (values T pos2))
        ((and (eq symbol '|false|) *erlang-false-is-lisp-nil*)
         (values NIL pos2))
        (t
         (values symbol pos2))) )))



;; ATOM_CACHE_REF
;; +----+-------------------+
;; |  1 |         1         |
;; +----+-------------------+
;; | 82 | AtomCacheRefIndex |
;; +----+-------------------+
;;

(defun encode-external-atom-cache-ref (reference-index)
  (concatenate '(vector octet)
               (vector +atom-cache-ref+)
               (vector reference-index)))

(defun decode-external-atom-cache-ref (bytes &optional (pos 0))
  (values (svref *cached-atoms* (aref bytes pos))
          (1+ pos)))



;; ATOM_EXT
;; +-----+-----+----------+
;; |  1  |  2  |    Len   |
;; +-----+-----+----------+
;; | 100 | Len | AtomName |
;; +-----+-----+----------+
;;

(defun encode-external-atom (atom)
  (concatenate '(vector octet)
               (vector +atom-ext+)
               (uint16-to-bytes (length (symbol-name atom)))
               (string-to-bytes (symbol-name atom))))

(defun decode-external-atom (bytes &optional (pos 0))
  (let ((length (bytes-to-uint16 bytes pos))
        (pos2 (+ 2 pos)))
    (values (make-atom (bytes-to-string bytes length pos2))
            (+ pos2 length))))



;; SMALL_ATOM_EXT
;; +-----+-----+----------+
;; |  1  |  1  |    Len   |
;; +-----+-----+----------+
;; | 115 | Len | AtomName |
;; +-----+-----+----------+
;;

(defun encode-external-small-atom (atom)
  (concatenate '(vector octet)
               (vector +small-atom-ext+)
               (vector (length (symbol-name atom)))
               (string-to-bytes (symbol-name atom))))

(defun decode-external-small-atom (bytes &optional (pos 0))
  (let ((length (aref bytes pos))
        (pos1 (1+ pos)))
    (values (make-atom (bytes-to-string bytes length pos1))
            (+ pos1 length))))
