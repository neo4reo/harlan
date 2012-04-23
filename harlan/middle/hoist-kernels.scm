(library
  (harlan middle hoist-kernels)
  (export hoist-kernels)
  (import (rnrs) (elegant-weapons helpers)
    (harlan helpers))

(define-match hoist-kernels
  ((module ,[hoist-decl -> decl* kernel*] ...)
   `(module
      (gpu-module . ,(apply append kernel*))
      . ,decl*)))

(define-match hoist-decl
  ((fn ,name ,args ,type ,[hoist-stmt -> stmt kernel*])
   (values `(fn ,name ,args ,type ,stmt) kernel*))
  ((extern ,name ,arg-types -> ,t)
   (values `(extern ,name ,arg-types -> ,t) '()))
  ((global ,type ,name ,e)
   (values `(global ,type ,name ,e) '())))

(define-match hoist-stmt
  ((kernel ,dims (free-vars (,fv* ,ft*) ...)
     ,[hoist-stmt -> stmt kernel*])
   (let ((name (gensym 'kernel)))
     (let-values (((fv*^ ft*^ casts)
                   (regionptr->voidptr fv* ft*)))
       (values
        `(apply-kernel ,name
                       ,dims
                       ,@(map (lambda (t x) `(var ,t ,x)) ft* fv*))
        `((kernel ,name
                  ,(map list fv*^ ft*^)
                  (begin ,@casts ,stmt))
          . ,kernel*)))))
  ((begin ,[hoist-stmt -> stmt* kernel*] ...)
   (values (make-begin stmt*) (apply append kernel*)))
  ((for (,i ,start ,end ,step) ,[hoist-stmt -> stmt kernel*])
   (values `(for (,i ,start ,end ,step) ,stmt) kernel*))
  ((while ,expr ,[hoist-stmt -> stmt kernel*])
   (values `(while ,expr ,stmt) kernel*))
  ((if ,test ,[hoist-stmt -> conseq ckernel*] ,[hoist-stmt -> alt akernel*])
   (values `(if ,test ,conseq ,alt) (append ckernel* akernel*)))
  (,else (values else '())))

(define (regionptr->voidptr fv* ft*)
  (match (map cons fv* ft*)
    (() (values `() `() `()))
    (((,x . (ptr region)) . ,[fv^ ft^ casts])
     (let ((void-region (gensym x)))
       (values
        (cons void-region fv^)
        (cons `(ptr void) ft^)
        (cons `(let ,x (ptr region)
                 (cast (ptr region)
                       (var (ptr void) ,void-region)))
              casts))))
    (((,x . ,t) . ,[fv^ ft^ casts])
     (values (cons x fv^) (cons t ft^) casts))
    (,else (error 'regionptr->voidptr "unmatched datum" else))))

;; end library
)
