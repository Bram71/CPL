#lang eopl
(require racket/base)
(require rackunit)
(require "../../chapter7/INFERRED/syntax.rkt")
(require "../../chapter7/INFERRED/INFERRED.rkt")
(require "../../chapter7/INFERRED/infer.rkt")

;; Given the following types below. 
;;	Write for each a program that would have the given type according to the INFERRED language
;; Notice: %x is a var-type
;a) int
(define a
	(a-program 
	  (diff-exp
		(const-exp 3)
		(const-exp 5))))

(check-equal? (type-of-program a) (int-type))

;b) (int -> int) -> (int ->bool)
(define b
	(a-program 
	  (proc-exp 'arg1 (no-type)
		(proc-exp 'arg2 (no-type)
		 (zero?-exp 
		   (diff-exp 
			 (call-exp 
			   (var-exp 'arg1)
			   (const-exp 0))
			 (var-exp 'arg2)))))))

(check-equal? 
  (type-of-program b) 
  (proc-type 
	(proc-type (int-type) (int-type))
	(proc-type (int-type) (bool-type))))

;c) %1
; With letrec we can give an unspecified 
; return type of the function we are defining
(define c 
  (a-program 
   (letrec-exp (no-type) ; Proc return type
			   'f ; Proc name
			   'x ; Proc arg name
			   (no-type) ; Proc arg type
			   (call-exp (var-exp 'f) (var-exp 'x)) ; Proc arg body
			   (call-exp (var-exp 'f) (const-exp 3))))) ; Letrec body, type of f.

(check-true (tvar-type? (type-of-program c)))

;d) (%1 -> %2) -> (%2 -> int) -> (%1 -> bool)
; proc(f) proc(g) proc(x) (zero? (g (f x)))
(define d
  (a-program
   (proc-exp 'f (no-type)
             (proc-exp 'g (no-type)
                       (proc-exp 'x (no-type)
                                 (zero?-exp (call-exp (var-exp 'g)
                                                      (call-exp (var-exp 'f) (var-exp 'x)))))))))
(let* ((d-type (type-of-program d))
       (f-type (proc-type->arg-type d-type)) ; Argument of d, should be (%1 -> %2)
       (t1 (proc-type->arg-type f-type))     ; Argument of f, should be %1
       (t2 (proc-type->result-type f-type))) ; Result of f, should be %2
  (check-true (tvar-type? t1))
  (check-true (tvar-type? t2))
  (check-equal?
   d-type
   (proc-type
    (proc-type t1 t2)                        ; (%1 -> %2)
    (proc-type
     (proc-type t2 (int-type))               ; (%2 -> int)
     (proc-type t1 (bool-type))))))          ; (%1 -> bool)


;e) %1 -> %2
(define e 
  (a-program 
   (letrec-exp (no-type) ; Proc return type
			   'f ; Proc name
			   'x ; Proc arg name
			   (no-type) ; Proc arg type
			   (call-exp (var-exp 'f) (var-exp 'x)) ; Proc arg body
			   (var-exp 'f)))) ; Letrec body, a function

(check-true
  (cases type (type-of-program e)
		 (proc-type (t1 t2) (not (equal? t1 t2)))
		 (else #f)))

;f) (%1 -> %2) -> %1
; This should be the solution:
; proc (f) letrec f(x) = f x in let y = ( g ( f x) ) in (f x)
;(a-program )