#lang eopl
(require "syntax.rkt")
(require "store.rkt")
(provide (all-defined-out))

;; Semantics

(define-datatype expval expval?
  (num-val
   (value number?))
  (bool-val
   (boolean boolean?))
  (proc-val
   (proc proc?))
  (ref-val
   (ref reference?)))
  
  ;; proc? : SchemeVal -> Bool
  ;; procedure : Var * Exp * Env -> Proc
  (define-datatype proc proc?
    (procedure
     (var symbol?)
     (body expression?)
     (env environment?)))

;; Addition for CALL-BY-NEED see p. 136
(define-datatype thunk thunk? 
	(a-thunk
		(exp1 expression?)
		(env environment?)))
  
  ;; expval->num : ExpVal -> Int
  ;; Page: 70
  (define expval->num
    (lambda (v)
      (cases expval v
        (num-val (num) num)
        (else (expval-extractor-error 'num v)))))
  
  ;; expval->bool : ExpVal -> Bool
  ;; Page: 70
  (define expval->bool
    (lambda (v)
      (cases expval v
        (bool-val (bool) bool)
        (else (expval-extractor-error 'bool v)))))
  
  ;; expval->proc : ExpVal -> Proc
  (define expval->proc
    (lambda (v)
      (cases expval v
        (proc-val (p) p)
        (else (expval-extractor-error 'proc v)))))
  
  (define expval->ref
    (lambda (v)
      (cases expval v
        (ref-val (ref) ref)
        (else (expval-extractor-error 'reference v)))))
  
  (define expval-extractor-error
    (lambda (variant value)
      (eopl:error 'expval-extractors "Looking for a ~s, found ~s"
                  variant value)))
  
  ;; Environments
  
  (define-datatype environment environment?
    (empty-env)
    (extend-env 
     (bvar symbol?)
     (bval expval?)
     (saved-env environment?))
    (extend-env-rec*
     (proc-names (list-of symbol?))
     (b-vars (list-of symbol?))
     (proc-bodies (list-of expression?))
     (saved-env environment?)))
  
  (define apply-env
    (lambda (env search-sym)
      (cases environment env
        (empty-env ()
                   (eopl:error 'apply-env "No binding for ~s" search-sym))
        (extend-env (bvar bval saved-env)
                    (if (eqv? search-sym bvar)
                        bval
                        (apply-env saved-env search-sym)))
        (extend-env-rec* (p-names b-vars p-bodies saved-env)
                         (cond 
                           ((location search-sym p-names)
                            => (lambda (n)
                                 (proc-val
                                  (procedure 
                                   (list-ref b-vars n)
                                   (list-ref p-bodies n)
                                   env))))
                           (else (apply-env saved-env search-sym)))))))
  
  ;; location : Sym * Listof(Sym) -> Maybe(Int)
  ;; (location sym syms) returns the location of sym in syms or #f is
  ;; sym is not in syms.  We can specify this as follows:
  ;; if (memv sym syms)
  ;;   then (list-ref syms (location sym syms)) = sym
  ;;   else (location sym syms) = #f
  (define location
    (lambda (sym syms)
      (cond
        ((null? syms) #f)
        ((eqv? sym (car syms)) 0)
        ((location sym (cdr syms))
         => (lambda (n) 
              (+ n 1)))
        (else #f))))
  
  ;; init-env : () -> Env
  ;; usage: (init-env) = [i=1, v=5, x=10]
  ;; (init-env) builds an environment in which i is bound to the
  ;; expressed value 1, v is bound to the expressed value 5, and x is
  ;; bound to the expressed value 10.
  ;; Page: 69
  
  (define init-env 
    (lambda ()
      (extend-env 
       'i (num-val 1)
       (extend-env
        'v (num-val 5)
        (extend-env
         'x (num-val 10)
         (empty-env))))))
  
  ;; Interpreter
  
  ;; value-of-program : Program -> ExpVal
  ;; Page: 71
  (define value-of-program 
    (lambda (pgm)
      (initialize-store!)               ; new for explicit refs.
      (cases program pgm
        (a-program (exp1)
                   (value-of exp1 (init-env))))))

;; Additions of CALL-BY-NEED see p 137,138
(define value-of-operand 
  (lambda (exp env)
	(cases expression exp
		(var-exp (var)
				 (let ((ref1 (apply-env env var)))
				   (let ((w (deref ref1)))
					(if (expval? w)
						w
						(let ((val1 (value-of-thunk w)))
						  (begin
							(setref! ref1 val1)
							val1))))))
		(else
		  (newref (a-thunk exp env))))))


(define value-of-thunk
  (lambda (th)
	(cases thunk th
		   (a-thunk (exp1 saved-env)
					(value-of exp1 saved-env)))))
  
  ;; value-of : Exp * Env -> ExpVal
  ;; Page: 71
  (define value-of
    (lambda (exp env)
      (cases expression exp
        (const-exp (num) (num-val num))
        (var-exp (var) (apply-env env var))
        (diff-exp (exp1 exp2)
                  (let ((val1 (value-of exp1 env))
                        (val2 (value-of exp2 env)))
                    (let ((num1 (expval->num val1))
                          (num2 (expval->num val2)))
                      (num-val
                       (- num1 num2)))))
        (zero?-exp (exp1)
                   (let ((val1 (value-of exp1 env)))
                     (let ((num1 (expval->num val1)))
                       (if (zero? num1)
                           (bool-val #t)
                           (bool-val #f)))))
        (if-exp (exp1 exp2 exp3)
                (let ((val1 (value-of exp1 env)))
                  (if (expval->bool val1)
                      (value-of exp2 env)
                      (value-of exp3 env))))
        (let-exp (var exp1 body)       
                 (let ((val1 (value-of exp1 env)))
                   (value-of body
                             (extend-env var val1 env))))
        (proc-exp (var body)
                  (proc-val (procedure var body env)))
        (call-exp (rator rand)
                  (let ((proc (expval->proc (value-of rator env)))
                        (arg (value-of rand env)))
                    (apply-procedure proc arg)))
        (letrec-exp (p-names b-vars p-bodies letrec-body)
          (value-of letrec-body
            (extend-env-rec* p-names b-vars p-bodies env)))

        (begin-exp (exp1 exps)
          (letrec 
            ((value-of-begins
               (lambda (e1 es)
                 (let ((v1 (value-of e1 env)))
                   (if (null? es)
                     v1
                     (value-of-begins (car es) (cdr es)))))))
            (value-of-begins exp1 exps)))

        (newref-exp (exp1)
          (let ((v1 (value-of exp1 env)))
            (ref-val (newref v1))))

        (deref-exp (exp1)
          (let ((v1 (value-of exp1 env)))
            (let ((ref1 (expval->ref v1)))
              (deref ref1))))

        (setref-exp (exp1 exp2)
          (let ((ref (expval->ref (value-of exp1 env))))
            (let ((v2 (value-of exp2 env)))
              (begin
                (setref! ref v2)
                (num-val 23)))))
        
        )))
  
  ;; apply-procedure : Proc * ExpVal -> ExpVal
  ;; Page: 79
  (define apply-procedure
    (lambda (proc1 val)
      (cases proc proc1
        (procedure (var body saved-env)
                   (value-of body (extend-env var val saved-env))))))
  