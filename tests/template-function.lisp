(in-package "TEMPLATE-FUNCTION.TESTS")
(in-suite all-template-function-tests)

;;;; Object Layer Tests

(template-function:defun/argument-specification xpy-function-type (<x> <y>
                                                                       &key
                                                                       ((:alpha <alpha>) 'number)
                                                                       ((:beta <beta>) 'number))
  `(function (,<x> ,<y> &key (:alpha ,<alpha>) (:beta ,<beta>)) (values)))

(template-function:defun/argument-specification xpy-lambda-form (<x> <y>
                                                                     &key
                                                                     ((:alpha <alpha>) 'number)
                                                                     ((:beta <beta>) 'number))
  (declare (ignore <x> <y>))
  (let* ((one (coerce 1 <alpha>))
         (zero (coerce 0 <beta>)))
    `(lambda (x y &key (alpha ,one) (beta ,zero))
       (assert (= (array-total-size x) (array-total-size y)))
       (dotimes (i (array-total-size y))
         (setf (row-major-aref y i) (+ (* alpha (row-major-aref x i))
                                       (* beta (row-major-aref y i)))))
       (values))))

(defun complete-xpy-values (continuation)
  (lambda (x y &key (alpha 1) (beta 0))
    (funcall continuation x y :alpha alpha :beta beta)))

(test make-template-function
  (let* ((tf (make-instance 'template-function:template-function
                            :name 'example
                            :lambda-list '(x y &key alpha beta)
                            :lambda-form-function #'xpy-lambda-form
                            :function-type-function #'xpy-function-type
                            :value-completion-function #'complete-xpy-values)))
    (is-true (typep tf 'template-function:template-function))
    (is (equal 'example/A_A_N_N (template-function:compute-name tf '(array array))))
    (is (equal '(function (array array &key (:alpha number) (:beta number)) (values))
               (template-function:compute-function-type tf '(array array))))

    (let* ((x (make-array 5 :initial-element 5))
           (y (make-array 5 :initial-element 0)))
      (signals specialization-store:inapplicable-arguments-error
        (template-function:funcall-template-function tf x y))

      (template-function:ensure-instantiation tf '(array array))

      ;; Test funcall-template-function
      (template-function:funcall-template-function tf x y)
      (is (equalp #(5 5 5 5 5) y))

      ;; Test apply-template-function
      (fill y 1)
      (template-function:apply-template-function tf x y (list :beta 1 :alpha 2))
      (is (equalp #(11 11 11 11 11) y))

      ;; Test expand-template-function
      (let* ((form '(example (the array x) (the array y))))
        (is (not (eql form (template-function:expand-template-function tf form)))))

      (let* ((form '(example (the array x) (the array y) :alpha 1)))
        (is (not (eql form (template-function:expand-template-function tf form))))))))

(test ensure-instantiation/keywords
  (let* ((tf (make-instance 'template-function:template-function
                            :name 'example
                            :lambda-list '(x y &key alpha beta)
                            :lambda-form-function #'xpy-lambda-form
                            :function-type-function #'xpy-function-type
                            :value-completion-function #'complete-xpy-values)))
    (finishes (template-function:ensure-instantiation tf '(array array &key (:alpha real) (:beta real))))
    (signals error (template-function:ensure-instantiation tf '(array)))
    (signals error (template-function:ensure-instantiation tf '(array array &key (:gamma real))))))

(test ensure-instantiation/optional
  (flet ((make-lambda-form (argument-specification)
           (template-function:destructuring-argument-specification (<x> <y> &optional (<z> 'number)) argument-specification
             `(lambda (x y z)
                (check-type x ,<x>)
                (check-type y ,<y>)
                (check-type z ,<z>)
                (+ x y z))))
         (make-function-type (argument-specification)
           (template-function:destructuring-argument-specification (x y &optional (z 'number)) argument-specification
             `(function (,x ,y ,z) number)))
         (complete-values (continuation)
           (lambda (x y &optional (z 1))
             (funcall continuation x y z))))
    (let* ((tf (make-instance 'template-function:template-function
                              :name 'example
                              :lambda-list '(x y &optional z)
                              :lambda-form-function #'make-lambda-form
                              :function-type-function #'make-function-type
                              :value-completion-function #'complete-values)))
      (finishes (template-function:ensure-instantiation* tf 'double-float 'double-float))
      (finishes (template-function:ensure-instantiation* tf 'double-float 'real 'real))
      (signals error (template-function:ensure-instantiation* tf 'real))
      (signals error (template-function:ensure-instantiation* tf 'real 'real 'real 'real)))))

(test ensure-instantiation/rest
  (flet ((make-lambda-form (argument-specification)
           (template-function:destructuring-argument-specification (<x> &others <others> &rest <args>) argument-specification
             (let* ((others (alexandria:make-gensym-list (length <others>)))
                    (args (gensym "ARGS")))
               `(lambda (x ,@others &rest ,args)
                  (check-type x ,<x>)
                  ,@(loop
                      for var in others
                      for type in <others>
                      collect `(check-type ,var ,type))
                  (reduce (lambda (current next)
                            (check-type next ,<args>)
                            (+ current next))
                          ,args :initial-value (+ x ,@others))))))
         (make-function-type (argument-specification)
           (template-function:destructuring-argument-specification (x &others others &rest args) argument-specification
             `(function (,x ,@others &rest ,args) number))))
    (let* ((tf (make-instance 'template-function:template-function
                              :name 'example
                              :lambda-list '(x &rest args)
                              :lambda-form-function #'make-lambda-form
                              :function-type-function #'make-function-type)))
      (signals error (template-function:ensure-instantiation* tf))
      (finishes (template-function:ensure-instantiation tf '(real &rest real)))
      (finishes (template-function:ensure-instantiation tf '(real real &rest real)))
      (finishes (template-function:ensure-instantiation tf '(real real integer &rest real)))
      (is (= (+ 1 2 3) (template-function:funcall-template-function tf 1 2 3))))))

(test reinitialize-instance/errors
  (let* ((tf (make-instance 'template-function:template-function
                            :name 'example
                            :lambda-list '(x y &key alpha beta)
                            :lambda-form-function #'xpy-lambda-form
                            :function-type-function #'xpy-function-type
                            :value-completion-function #'complete-xpy-values)))
    ;; Ensure trying to change the name signals an error.
    (signals error (reinitialize-instance tf :name 'example2))
    (finishes (reinitialize-instance tf :name 'example))

    ;; Ensure trying to change the lambda list signals an error
    (signals error (reinitialize-instance tf :lambda-list '(a b c)))
    (finishes (reinitialize-instance tf :lambda-list '(a b &key alpha beta)))))

(test reinitialize-instance/function-type-function
  (let* ((tf (make-instance 'template-function:template-function
                            :name 'example
                            :lambda-list '(x y &key alpha beta)
                            :lambda-form-function #'xpy-lambda-form
                            :function-type-function #'xpy-function-type
                            :value-completion-function #'complete-xpy-values))
         (new-fn (template-function:argument-specification-lambda (x y &key (alpha 'real) (beta 'real))
                   `(function (,x ,y &key (:alpha ,alpha) (:beta ,beta)) (values)))))
    (is (equalp '(t t &key (:alpha number) (:beta number))
                (template-function:complete-argument-specification* tf t t)))
    (reinitialize-instance tf :lambda-list '(x y &key alpha beta)
                              :function-type-function new-fn)
    (is (equalp '(t t &key (:alpha real) (:beta real))
                (template-function:complete-argument-specification* tf t t)))
    (is (equalp '(t t :alpha real :beta real)
                (funcall (funcall (template-function:type-completion-function tf) #'(lambda (&rest args) args))
                         t t)))))

(test reinitialize-instance/value-completion-function
  (let* ((tf (make-instance 'template-function:template-function
                            :name 'example
                            :lambda-list '(x y &key alpha beta)
                            :lambda-form-function #'xpy-lambda-form
                            :function-type-function #'xpy-function-type
                            :value-completion-function #'complete-xpy-values)))
    (let* ((completion-fn (template-function:value-completion-function tf))
           (fn (funcall completion-fn (lambda (&rest args)
                                        args))))
      (is (equalp '(2 2 :alpha 1 :beta 0)
                  (funcall fn 2 2))))

    ;; Ensure the value completion function is recomputed when the
    ;; lambda list changes.
    (reinitialize-instance tf :lambda-list '(a b &key (alpha 1) (beta 1)))
    (let* ((completion-fn (template-function:value-completion-function tf))
           (fn (funcall completion-fn (lambda (&rest args)
                                        args))))
      (is (equalp '(2 2 :alpha 1 :beta 1)
                  (funcall fn 2 2))))))

(test inlining
  (let* ((tf (make-instance 'template-function:template-function
                            :name 'example
                            :lambda-list '(x y &key (alpha 1) (beta 0))
                            :lambda-form-function #'xpy-lambda-form
                            :function-type-function #'xpy-function-type
                            :value-completion-function #'complete-xpy-values
                            :inline t)))
    (template-function:ensure-instantiation tf '(array array))
    (labels ((search-form (item form)
               (cond ((equalp item form)
                      (values form t))
                     ((listp form)
                      (dolist (subform form)
                        (multiple-value-bind (result match?) (search-form item subform)
                          (when match?
                            (return-from search-form (values result match?)))))))))
      (let* ((expansion (template-function:expand-template-function tf '(example (the array x) (the array y))))
             (fn (compile nil `(lambda (x y)
                                 ,expansion)))
             (expected (xpy-lambda-form '(array array)))
             (y (make-array 5 :initial-contents '(0 1 2 3 4))))
        (is-true (null (search-form 'example expansion)))
        (is (equalp expected (search-form expected expansion)))
        (funcall fn #(4 3 2 1 0) y)
        (is (equalp #(4 3 2 1 0) y))))))
