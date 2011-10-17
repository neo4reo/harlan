(library
  (lift-vectors)
  (export
    lift-vectors
    verify-lift-vectors
    lift-expr->stmt)
  (import
    (only (chezscheme) format)
    (rnrs)
    (util match)
    (print-c)
    (verify-grammar)
    (util helpers))
  
;; Vector simplification code. Weirdly, this runs before
;; typechecking.
  
(generate-verify lift-vectors
  (Module wildcard)
  (Decl
    (fn Var (Var *) Stmt * Ret-Stmt)
    (extern Var Var -> Type))
  (Stmt
    integer
    (var Var)
    (assert Stmt)
    (let Var Stmt)
    (reduce Binop Stmt)
    (Binop Stmt Stmt)
    (vector Expr *)
    (print Expr)
    (print Expr Expr))
  (Ret-Stmt
    (return Expr))
  (Var symbol)
  (Type wildcard)
  (Expr wildcard)
  (Binop binop))

(define lift-expr->stmt
  (lambda (expr finish)
    (match expr
      (,n (guard (number? n)) (finish n))
      (,str (guard (string? str)) (finish str))
      ((var ,x) (finish `(var ,x)))
      ((time)
       (finish '(time)))
      ((vector-ref ,e1 ,e2)
       (lift-expr->stmt
         (if (symbol? e1) `(var ,e1) e1)
         (lambda (e1^)
           (lift-expr->stmt
             e2 (lambda (e2^)
                  (finish `(vector-ref ,e1^ ,e2^)))))))
      ((kernel ((,x* ,e*) ...) ,body)
       (let ((finish
               (lambda (e*^)
                 (let ((v (gensym 'v)))
                   (cons `(let ,v
                            (kernel ,(map list x* e*^)
                              ,@(lift-expr->stmt
                                  body (lambda (body^) `(,body^)))))
                     (finish `(var ,v)))))))
         (let loop ((e* e*) (e*^ '()))
           (if (null? e*)
               (finish (reverse e*^))
               (lift-expr->stmt
                 (car e*)
                 (lambda (e^)
                   (loop (cdr e*) (cons e^ e*^))))))))
      ((vector ,e* ...)
       (let ((finish (lambda (e*^)
                       (let ((v (gensym 'v)))
                         (cons `(let ,v (vector . ,e*^))
                           (finish `(var ,v)))))))
         (let loop ((e* e*) (e*^ '()))
           (if (null? e*)
               (finish (reverse e*^))
               (lift-expr->stmt
                 (car e*)
                 (lambda (e^)
                   (loop (cdr e*) (cons e^ e*^))))))))
      ((make-vector ,c)
       (finish `(make-vector ,c)))
      ((iota ,c)
       (finish `(iota ,c)))
      ((reduce ,op ,e)
       (lift-expr->stmt
         e
         (lambda (e^)
           (let ((v (gensym 'v)))
             (cons `(let ,v (reduce ,op ,e^))
               (finish `(var ,v)))))))
      ((,op ,e) (guard (unaryop? op))
       (lift-expr->stmt
         e (lambda (e^)
             (finish `(,op ,e^)))))
      ((,op ,e1 ,e2) (guard (binop? op))
       (lift-expr->stmt
         e1 (lambda (e1^)
              (lift-expr->stmt
                e2 (lambda (e2^)
                     (finish `(,op ,e1^ ,e2^)))))))
      ((,rator ,rand* ...)
       (guard (symbol? rator))
       (let loop ((e* rand*) (e*^ '()))
         (if (null? e*)
             (finish `(call ,rator . ,(reverse e*^)))
             (lift-expr->stmt
               (car e*)
               (lambda (e^)
                 (loop (cdr e*) (cons e^ e*^)))))))
      (,else (error 'lift-expr->stmt "unknown expression" else)))))

(define lift-stmt*
  (lambda (stmt*)
    (match stmt*
      (() '())
      (((print ,expr) . ,[rest])
       (lift-expr->stmt expr (lambda (e^)
                               (cons `(print ,e^)
                                 rest))))
      (((print ,e1 ,e2) . ,[rest])
       (lift-expr->stmt
         e1 (lambda (e1^)
              (lift-expr->stmt
                e2 (lambda (e2^)
                     (cons `(print ,e1^ ,e2^)
                       rest))))))
      (((assert ,expr) . ,[rest])
       (lift-expr->stmt expr (lambda (e^)
                               (cons `(assert ,e^)
                                 rest))))
      (((set! ,x ,e) . ,[rest])
       ;; TODO: should x be any expression, or just a variable?
       (lift-expr->stmt e (lambda (e^)
                            (cons `(set! ,x ,e^)
                              rest))))
      (((vector-set! ,x ,e1 ,e2) . ,[rest])
       ;; TODO: should x be any expression, or just a variable?
       ;; WEB: any expression
       (lift-expr->stmt
         x
         (lambda (x^)
           (lift-expr->stmt
             e1
             (lambda (e1^)
               (lift-expr->stmt e2 (lambda (e2^)
                                     (cons `(vector-set! ,x^ ,e1^ ,e2^)
                                       rest))))))))             
      (((kernel ,iters ,body* ...) . ,[rest])
       ;; TODO: For now just pass the kernel through... this
       ;; won't let us declare vectors inside kernels though.
       (cons `(kernel ,iters ,body* ...) rest))
      (((let ,x ,e) . ,[rest])
       (lift-expr->stmt e (lambda (e^)
                            (cons `(let ,x ,e^)
                              rest))))
      (((return ,expr) . ,[rest])
       (lift-expr->stmt expr
         (lambda (e^)
           (cons `(return ,e^) rest))))
      (((for (,x ,start ,end) ,stmt* ...) . ,[rest])
       (lift-expr->stmt
         start
         (lambda (start)
           (lift-expr->stmt
             end
             (lambda (end)
               (cons `(for (,x ,start ,end) . ,(lift-stmt* stmt*))
                 rest))))))
      (,else (error 'lift-stmt* "unknown statement" else)))))

(define (lift-decl fn)
  (match fn
    ((fn ,name ,args ,stmt* ...)
     `(fn ,name ,args . ,(lift-stmt* stmt*)))
    ((extern ,name ,args -> ,rtype)
     `(extern ,name ,args -> ,rtype))
    (,else (error 'lift-decl "bad function" else))))

(define lift-vectors
  (lambda (mod)
    (match mod
      ((module ,fn* ...)
       `(module . ,(map lift-decl fn*)))
      (,else (error 'lift-vectors "malformed module" else)))))

)
