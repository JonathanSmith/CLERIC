(in-package :cleric)


(defclass remote-node ()
  ((socket :reader remote-node-socket :initarg :socket)
   (atom-cache :reader remote-node-atom-cache :initform (make-atom-cache))
   (port :reader remote-node-port :initarg :port)
   (node-type :initarg :node-type) ;; 'ERLANG or 'HIDDEN
   (protocol :initarg :protocol) ;; 0 (TCP/IP v4)
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
             (usocket:socket-connect host port :element-type '(unsigned-byte 8))
           (usocket:connection-refused-error ()
             (error 'node-unreachable-error)) )))
    (restart-case
        (handler-bind ((condition #'(lambda (condition)
                                      (declare (ignore condition))
                                      (usocket:socket-close socket))))
          (when (perform-client-handshake (usocket:socket-stream socket)
                                          cookie)
            (register-connected-remote-node remote-node socket)))
      (try-connect-again ()
        (remote-node-connect remote-node cookie))) ))

(defun start-listening-for-remote-nodes ()
  (if *listening-socket*
      (error 'already-listening-on-socket) ;; How can we get the port?
      (progn
        (setf *listening-socket*
              (usocket:socket-listen usocket:*wildcard-host*
                                     usocket:*auto-port*
                                     :element-type '(unsigned-byte 8)))
        t))) ;; Return port?

(defun stop-listening-for-remote-nodes ()
  (when *listening-socket*
    (usocket:socket-close *listening-socket*)
    (setf *listening-socket* nil)
    t))

(defun remote-node-accept-connect (cookie)
  (restart-case
      (if *listening-socket*
          (let ((socket (usocket:socket-accept *listening-socket*)))
            (handler-case
                (let ((remote-node (perform-server-handshake
                                    (usocket:socket-stream socket)
                                    cookie)))
                  (when remote-node
                    (register-connected-remote-node remote-node socket) ))
              (condition ()
                (usocket:socket-close socket)
                nil) ))
          (error 'not-listening-on-socket) )
    (start-listening-on-socket ()
      :report "Start listening on a socket."
      (start-listening-for-remote-nodes)
      (remote-node-accept-connect cookie))))

(defun register-connected-remote-node (remote-node socket)
  (setf (slot-value remote-node 'socket) socket)
  (push remote-node *remote-nodes*)
  t)

(defun find-connected-remote-node (node-name) ;; Make NODE-NAME a node designator
  (find node-name *remote-nodes* :key #'remote-node-name :test #'string=)) ;; Perhaps also check full name?