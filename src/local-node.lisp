(in-package :cleric)

(defvar *this-node* "lispnode@localhost"
  "The name and host for this node.")


(defun this-node ()
  *this-node*)

(defun (setf this-node) (node-name)
  ;; TODO: Add sanity checks.
  ;; The node name should be valid.
  ;; It should not be possible to change node name while connected to other
  ;; nodes and/or registered on the EPMD.
  (setf *this-node* node-name))


;;;
;;; Utility functions
;;;

(defun node-name (node-string)
  "Return the name part of a node identifier"
  ;; All characters up to a #\@ is the name
  (let ((pos (position #\@ node-string)))
    (if pos
        (subseq node-string 0 pos)
        node-string)))

(defun node-host (node-string)
  "Return the host part of a node identifier"
  ;; All characters after a #\@ is the host
  (let ((pos (position #\@ node-string)))
    (if pos
        (subseq node-string (1+ pos))
        "localhost"))) ;; OK with localhost??
