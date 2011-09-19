(in-package :cleric)

(defvar *remote-nodes* (list)
  "Remote nodes connected to.")


(defclass remote-node ()
  ((socket :reader remote-node-socket :initarg :socket)
   (atom-cache :reader remote-node-atom-cache :initform (make-atom-cache))
   (lock :reader remote-node-lock :initform (bt:make-lock))
   (port :reader remote-node-port :initarg :port)
   (node-type :initarg :node-type) ;; 'ERLANG or 'HIDDEN
   (protocol :initarg :protocol :initform 0) ;; 0 (TCP/IP v4)
   (lowest-version :initarg :lowest-version)
   (highest-version :initarg :highest-version)
   (name :reader remote-node-name :initarg :name :documentation "The name of the remote node.")
   (host :reader remote-node-host :initarg :host)
   (full-name :initarg :full-name :initform nil)
   (extra-field :initarg :extra-field :initform #())
   (group-leader :initarg :group-leader :initform '|init|))
  (:documentation "A representation of a remote node."))

(defmethod print-object ((object remote-node) stream)
  (print-unreadable-object (object stream :type t)
    (with-slots (port node-type name host) object
      (format stream "(~a) ~a@~a [~a]" node-type name host port))))

(defmethod socket-stream ((node remote-node))
  (usocket:socket-stream (remote-node-socket node)))


(defun remote-node-connect (remote-node cookie)
  "Connect and perform handshake with a remote node."
  (let ((socket
         (handler-case
             (usocket:socket-connect (remote-node-host remote-node)
                                     (remote-node-port remote-node)
                                     :element-type '(unsigned-byte 8))
           (usocket:connection-refused-error ()
             (error 'node-unreachable-error)) )))
    (restart-case
        (handler-bind ((condition #'(lambda (condition)
                                      (declare (ignore condition))
                                      (usocket:socket-close socket))))
          (setf (usocket:socket-stream socket)
                (make-flexi-stream (usocket:socket-stream socket)))
          (multiple-value-bind (full-node-name flags version)
              (perform-client-handshake (usocket:socket-stream socket) cookie)
            (declare (ignore full-node-name flags version))
            (setf (slot-value remote-node 'socket) socket)
            (register-connected-remote-node remote-node)))
      (try-connect-again ()
        :test try-again-condition-p
        (remote-node-connect remote-node cookie))) ))

(defun remote-node-accept-connect (cookie)
  (let ((socket (restart-case (accept-connect)
                  (start-listening-on-socket ()
                    :report "Start listening on a socket."
                    (start-listening)
                    (accept-connect)) )))
    (handler-bind ((condition #'(lambda (condition)
                                  (declare (ignore condition))
                                  (usocket:socket-close socket))))
      (multiple-value-bind (full-node-name flags version)
          (perform-server-handshake (usocket:socket-stream socket) cookie)
        (declare (ignore flags))
        (register-connected-remote-node
         (make-instance 'remote-node
                        :socket socket
                        :node-type 'erlang ;; Can we get this information from flags?
                        :lowest-version version
                        :highest-version version
                        :name (node-name full-node-name)
                        :host (node-name full-node-name)
                        :full-name full-node-name))
        full-node-name))))


(defun register-connected-remote-node (remote-node)
  (push remote-node *remote-nodes*)
  t)

#|(defun find-connected-remote-node (node-name) ;; Make NODE-NAME a node designator
  (find node-name *remote-nodes* :key #'remote-node-name :test #'string=)) ;; Perhaps also check full name?
|#

(defun find-connected-remote-node (node-name)
  (flet ((node-name= (node-name1 node-name2)
	   (let ((len1 (length node-name1))
		 (len2 (length node-name2)))
	     (if (> len1 len2)
		 (string= (subseq node-name1 0 len2) node-name2)
		 (string= (subseq node-name2 0 len1) node-name1)))))
    (when (symbolp node-name)
      (setf node-name (symbol-name node-name)))
    (find node-name *remote-nodes* :key #'cleric::remote-node-name :test #'node-name=)))


(defun remote-node-sockets ()
  (mapcar #'remote-node-socket *remote-nodes*))

(defun connected-remote-nodes ()
  (mapcar #'remote-node-name *remote-nodes*))
