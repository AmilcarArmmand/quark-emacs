;; -*- lexical-binding: t -*-
(require 'cl-lib)
(eval-when-compile
  (require 'config-setq))

;; =============================================
;; Setup straight.el
;; =============================================

(setq straight-repository-branch "develop"
      straight-check-for-modifications 'live
      straight-use-package-version 'ensure
      straight-use-package-by-default t
      straight-vc-git-auto-fast-forward t
      straight-cache-autoloads t)

(let ((bootstrap-file (concat user-emacs-directory "straight/bootstrap.el"))
      (bootstrap-version 2))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; ================================================
;; Require packages in the background after startup
;; ================================================

(add-to-list 'load-path (locate-user-emacs-file "personal/"))

(defun my/sit-for (seconds)
  "Redisplay, then wait for SECONDS seconds.  Stop when input is available.
SECONDS may be a floating-point value.
\(On operating systems that do not support waiting for fractions of a
second, floating-point values are rounded down to the nearest integer.)"
  (unless (input-pending-p t)
    (redisplay)
    (let ((read (let ((input-method-function nil))
                  (read-event nil t seconds))))
      (when read
        ;; This is from the normal definition of sit-for, but
        ;; "(cons t read)" has been replaced by "read".
        ;; This is to avoid nasty "<t> is undefined" errors.
        (push read unread-command-events)))))

(defvar idle-require-symbols '(helm-files
                               helm-ring
                               helm-projectile
                               helm-semantic
                               counsel
                               which-key
                               evil-snipe
                               avy
                               ace-jump-helm-line
                               multiple-cursors)
  "Symbols which need to be autoloaded.")

(defvar idle-require-timer (run-with-idle-timer 0.1 t 'idle-require-load-next))

(defun idle-require-load-next ()
  "Load symbols from `idle-require-symbols' until input occurs."
  (let (symbol)
    (while (and idle-require-symbols
                (not (input-pending-p)))
      (cl-letf* ((old-load (symbol-function #'load))
                 ((symbol-function #'load)
                  (lambda (file &optional noerror _nomessage &rest args)
                    (apply old-load
                           file
                           noerror
                           (not (eq debug-on-error 'startup))
                           args))))
        (require (pop idle-require-symbols)))
      (my/sit-for 0.1))))

(straight-use-package '(use-package
                         :type git
                         :host github
                         :repo "raxod502/use-package"))

(straight-use-package '(el-patch
                        :type git
                        :host github
                        :repo "raxod502/el-patch"
                        :branch "develop"))

(eval-when-compile (require 'el-patch))
(setq el-patch-use-aggressive-defvar t)
(defvar el-patch--patches (make-hash-table))

(with-eval-after-load 'el-patch
  (el-patch-defun el-patch--classify-definition-type (type)
    "Classifies a definition TYPE as a `function' or `variable'.
TYPE is a symbol `defun', `defmacro', etc."
    (pcase type
      ((or 'defun 'defmacro 'defsubst 'define-minor-mode
           (el-patch-add 'evil-define-command
                         'evil-define-motion
                         'evil-define-text-object
                         'evil-define-operator))
       'function)
      ((or 'defvar 'defconst 'defcustom)
       'variable)
      (_ (error "Unexpected definition type %S" type))))

  ;; See https://github.com/raxod502/el-patch/issues/13
  (defun nadvice/el-patch--compute-load-history-items (old-fun definition)
    (cl-destructuring-bind (type name . body) definition
      (pcase type
        ((or 'evil-define-command
             'evil-define-motion
             'evil-define-text-object
             'evil-define-operator)
         (list (cons 'defun name)))
        (_ (funcall old-fun definition)))))

  (advice-add 'el-patch--compute-load-history-items
              :around
              #'nadvice/el-patch--compute-load-history-items))

(with-eval-after-load 'use-package
  (setq use-package-always-ensure t
        use-package-always-defer t)

  (defun nadvice/straight-use-package-ensure-function (old-fun &rest args)
    (cl-letf* (((symbol-function #'y-or-n-p) (lambda (prompt) t)))
      (apply old-fun args)))

  (advice-add 'straight-use-package-ensure-function :around
              #'nadvice/straight-use-package-ensure-function)

  (el-patch-defun use-package-handler/:ensure (name keyword ensure rest state)
    (let* ((body (use-package-process-keywords name rest
                   ;; Here we are conditionally updating the marker
                   ;; value for deferred installation; this will be
                   ;; checked later by `:config'. For more information
                   ;; see `use-package-handler/:defer-install'.
                   (if (eq (plist-get state :defer-install)
                           :defer-install)
                       (plist-put state :defer-install :ensure)
                     state))))
      ;; We want to avoid installing packages when the `use-package'
      ;; macro is being macro-expanded by elisp completion (see
      ;; `lisp--local-variables'), but still do install packages when
      ;; byte-compiling to avoid requiring `package' at runtime.
      (cond
       ((plist-get state :defer-install)
        (push
         `(puthash ',name '(,ensure . ,state)
                   use-package--deferred-packages)
         body)
        (push `(,use-package-pre-ensure-function
                ',name ',ensure ',state)
              body))
       (el-patch-remove
         ((bound-and-true-p byte-compile-current-file)
          ;; Eval when byte-compiling,
          (funcall use-package-ensure-function
                   name ensure state :byte-compile)))
       ;;  or else wait until runtime.
       (t (push `(,use-package-ensure-function
                  ',name ',ensure ',state :ensure)
                body)))
      body)))

(autoload 'use-package-install-deferred-package "use-package"
  "Install a package whose installation has been deferred.
NAME should be a symbol naming a package (actually, a feature).
This is done by calling `use-package-ensure-function' is called
with four arguments: the key (NAME) and the two elements of the
cons in `use-package--deferred-packages' (the value passed to
`:ensure', and the `state' plist), and a keyword providing
information about the context in which the installation is
happening. (This defaults to `:unknown' but can be overridden by
providing CONTEXT.)

Return t if the package is installed, nil otherwise. (This is
determined by the return value of `use-package-ensure-function'.)
If the package is installed, its entry is removed from
`use-package--deferred-packages'. If the package has no entry in
`use-package--deferred-packages', do nothing and return t.")

(el-patch-defvar use-package--deferred-packages (make-hash-table)
  "Hash mapping packages to data about their installation.

The keys are not actually symbols naming packages, but rather
symbols naming the features which are the names of \"packages\"
required by `use-package' forms. Since
`use-package-ensure-function' could be set to anything, it is
actually impossible for `use-package' to determine what package
is supposed to provide the feature being ensured just based on
the value of `:ensure'.

Each value is a cons, with the car being the the value passed to
`:ensure' and the cdr being the `state' plist. See
`use-package-install-deferred-package' for information about how
these values are used to call `use-package-ensure-function'.")

(use-package hydra
  :init
  (autoload 'hydra-default-pre "hydra"))

(use-package s)
(use-package restart-emacs
  :config
  (eval-when-compile
    (with-demoted-errors "Load error: %s"
      (require 'restart-emacs)))
  (el-patch-feature restart-emacs)
  (el-patch-defun restart-emacs--guess-startup-directory-using-lsof ()
    "Get the startup directory of the current Emacs session using the `lsof' program."
    (when (executable-find "lsof")
      (let* ((el-patch-add (default-directory "/"))
             (lsof-op (shell-command-to-string (format "lsof -d cwd -a -Fn -p %d"
                                                       (emacs-pid))))
             (raw-cwd (car (last (split-string lsof-op "\n" t))))
             (cwd (substring raw-cwd 1)))
        (when (< 0 (length cwd))
          cwd)))))

(provide 'config-package)
