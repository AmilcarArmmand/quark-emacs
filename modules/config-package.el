;; -*- lexical-binding: t -*-

(require 'package)

(eval-when-compile
  (with-demoted-errors "Load error: %s"
    (require 'cl-lib)))

;; Package archives
(setq package-enable-at-startup nil
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("melpa" . "https://melpa.org/packages/")))

(defvar my/package-cached-autoloads nil)
(defvar my/package-cached-descriptors nil)
(defvar my/package-cache-last-build-time nil)

(defvar my/package-autoload-file (expand-file-name "data/package-cache.el"
                                                user-emacs-directory))

(defun my/package-rebuild-cache ()
  (interactive)
  (let ((autoloads (file-expand-wildcards
                    (expand-file-name "*/*-autoloads.el"
                                      package-user-dir)))
        (pkg-descs))

    (with-temp-buffer
      (dolist (pkg-dir (cl-remove-if-not
                        #'file-directory-p
                        (file-expand-wildcards
                         (expand-file-name "*" package-user-dir))))
        (let ((pkg-file (expand-file-name
                         (package--description-file pkg-dir)
                         pkg-dir)))
          (when (file-exists-p pkg-file)
            (with-temp-buffer
              (insert-file-contents pkg-file)
              (goto-char (point-min))
              (push (cons pkg-dir (read (current-buffer))) pkg-descs)))))

        (insert (format "(setq my/package-cached-descriptors '%S)"
                        pkg-descs))

      (dolist (file autoloads)
        (insert-file-contents file)

        ;; detect custom themes
        (when (with-temp-buffer
                (insert-file-contents file)
                (search-forward "'custom-theme-load-path" nil t))
          (when (boundp 'custom-theme-load-path)
            (insert (format "(add-to-list 'custom-theme-load-path \"%s\")"
                            (file-name-as-directory
                             (file-name-directory file)))))))

      (insert (format "(setq my/package-cached-autoloads '%S)"
                      (mapcar #'file-name-sans-extension autoloads)))

      (let ((mtime (nth 6 (file-attributes
                           (expand-file-name package-user-dir)))))
        (insert (format "(setq my/package-cache-last-build-time '%S)" mtime)))
      (write-file my/package-autoload-file nil)
      (cl-letf ((load-path))
        (load my/package-autoload-file)))))

(unwind-protect (progn (unless (file-exists-p my/package-autoload-file)
                         (my/package-rebuild-cache))
                       (load my/package-autoload-file)
                       (unless (equal (nth 6 (file-attributes
                                              (expand-file-name
                                               package-user-dir)))
                                      my/package-cache-last-build-time)
                         (my/package-rebuild-cache)))

  (dolist (dir (file-expand-wildcards
                (expand-file-name "*" package-user-dir)))
    (when (file-directory-p dir)
      (add-to-list 'load-path dir))))

(defun nadvice/package-initialize (old-fun &rest args)
  (cl-letf* ((orig-load (symbol-function #'load))
             ((symbol-function #'load)
              (lambda (&rest args)
                (cl-destructuring-bind
                    (file &rest args_ignored)
                    args
                  (unless (member file my/package-cached-autoloads)
                    (message "Package autoload cache miss: %s" file)
                    (my/package-rebuild-cache)
                    (apply orig-load args))))))
    (apply old-fun args)))

(advice-add 'package-initialize :around #'nadvice/package-initialize)

(defun nadvice/package-load-descriptor (old-fun pkg-dir)
  "Load the description file in directory PKG-DIR."
  (let ((cached-desc (assoc pkg-dir my/package-cached-descriptors)))
    (if cached-desc
        (let* ((pkg-file (expand-file-name
                         (package--description-file pkg-dir)
                         pkg-dir))
               (signed-file (concat pkg-dir ".signed"))
               (pkg-desc (package-process-define-package
                           (cdr cached-desc) pkg-file)))
          (setf (package-desc-dir pkg-desc) pkg-dir)
          (when (file-exists-p signed-file)
            (setf (package-desc-signed pkg-desc) t))
          pkg-desc)
      ;; certain directories are queried, although they do not contain packages
      (unless (member (file-name-nondirectory pkg-dir)
                      '("elpa" ".emacs.d" "archives" "gnupg"))
        (message "Package descriptor cache miss: %s" pkg-dir))
      (funcall old-fun pkg-dir))))

(advice-add 'package-load-descriptor :around #'nadvice/package-load-descriptor)

(package-initialize)

;; Guarantee all packages are installed on start
(defun my/has-package-not-installed (packages)
  (catch 'package-return
    (dolist (package packages)
      (unless (package-installed-p package)
        (throw 'package-return t)))
    (throw 'package-return nil)))

(defun my/ensure-packages-are-installed (packages)
  (interactive)
  (save-window-excursion
    (when (my/has-package-not-installed packages)
      (package-refresh-contents)
      (dolist (package packages)
        (unless (package-installed-p package)
          (package-install package)))
      (byte-recompile-config)
      (package-initialize))))

(defvar my/required-packages
  '(;; evil based modes
    ;; evil
    evil-args
    evil-easymotion
    evil-exchange
    evil-jumper
    evil-matchit
    evil-nerd-commenter
    evil-org
    evil-snipe
    evil-surround
    evil-quickscope
    on-parens

    ace-window
    ace-jump-helm-line
    adaptive-wrap
    aggressive-indent
    auto-compile
    auto-highlight-symbol
    auto-indent-mode
    ;; avy
    bracketed-paste
    company
    company-flx
    counsel
    diff-hl
    diminish
    dtrt-indent
    easy-kill
    expand-region
    flx-isearch
    flycheck
    framemove
    ;; helm
    helm-ag
    helm-flx
    helm-git-grep
    helm-projectile
    hydra
    icicles
    iflipb
    idle-require
    key-chord
    magit
    multiple-cursors
    rainbow-delimiters
    session
    smartparens
    smex
    smooth-scrolling
    solarized-theme
    swiper
    volatile-highlights
    which-key
    whole-line-or-region
    ws-butler
    xclip
    yasnippet))

(my/ensure-packages-are-installed my/required-packages)

(eval-when-compile
  (with-demoted-errors "Load error: %s"
    (require 'idle-require)))

(add-to-list 'load-path (expand-file-name "personal/" user-emacs-directory))

(with-eval-after-load 'idle-require
  (add-hook 'idle-require-mode-hook
            (lambda ()
              (diminish 'idle-require-mode)))

  (setq idle-require-idle-delay 0.1
        idle-require-load-break 0.1
        idle-require-symbols '(helm-files
                               helm-ring
                               helm-projectile
                               helm-semantic
                               which-key
                               magit
                               evil-snipe
                               avy
                               ace-jump-helm-line
                               evil-jumper
                               multiple-cursors
                               hydra))

  ;; back off for non-essential resources
  (with-eval-after-load (elt idle-require-symbols 4)
    (setq idle-require-idle-delay 1
          idle-require-load-break 1)))

(with-eval-after-load 'idle-require
  (defun nadvice/idle-require-quiet (old-fun &rest args)
    (with-demoted-errors "Idle require error: %s"
      (cl-letf* ((old-load (symbol-function #'load))
                 ((symbol-function #'message) #'format)
                 ((symbol-function #'load)
                  (lambda (file &optional noerror _nomessage &rest args)
                    (apply old-load file noerror t args))))
        (apply old-fun args))))

  (advice-add 'idle-require-load-next :around #'nadvice/idle-require-quiet))

(add-hook 'emacs-startup-hook #'idle-require-mode)

(defun package-upgrade-all (&optional automatic)
  "Upgrade all packages automatically without showing *Packages* buffer."
  (interactive)
  (package-refresh-contents)
  (let (upgrades)
    (cl-flet ((get-version (name where)
                           (let ((pkg (cadr (assq name where))))
                             (when pkg
                               (package-desc-version pkg)))))
      (dolist (package (mapcar #'car package-alist))
        (let ((in-archive (get-version package package-archive-contents)))
          (when (and in-archive
                     (version-list-< (get-version package package-alist)
                                     in-archive))
            (push (cadr (assq package package-archive-contents))
                  upgrades)))))
    (if upgrades
        (when (or automatic
                  (yes-or-no-p
                   (format "Upgrade %d package%s (%s)? "
                           (length upgrades)
                           (if (= (length upgrades) 1) "" "s")
                           (mapconcat #'package-desc-full-name upgrades ", "))))
          (save-window-excursion
            (dolist (package-desc upgrades)
              (let ((old-package (cadr (assq (package-desc-name package-desc)
                                             package-alist))))
                (package-install package-desc)
                (package-delete old-package)))
            (message "All package upgrades completed.")
            (my/x-urgent)))
      (message "All packages are up to date"))))

(eval-and-compile
  (defun my/remove-keyword-params (seq)
    (when seq
      (cl-destructuring-bind (head . tail) seq
        (if (keywordp head) (my/remove-keyword-params (cdr tail))
          (cons head (my/remove-keyword-params tail)))))))

(cl-defmacro package-deferred-install (package-name
                                       &rest forms
                                       &key feature-name
                                       mode-entries
                                       autoload-names
                                       manual-setup
                                       &allow-other-keys)
  (declare (indent 4))
  `(with-no-warnings
     (unless (package-installed-p ,package-name)
       ,@(when manual-setup
           (list manual-setup))
       ,@(mapcar (lambda (item)
                   `(add-to-list 'auto-mode-alist ,item))
                 (cadr mode-entries))
       ,@(mapcar (lambda (name)
                   `(defun ,(cadr name) (&rest args)
                      (interactive)
                      (save-window-excursion
                        (package-install ,package-name))
                      (require ,(or feature-name package-name))
                      (if (called-interactively-p)
                          (call-interactively ,name)
                        (apply ,name args))))
                 (cadr autoload-names)))
     ,@(let ((forms (my/remove-keyword-params forms)))
         (when forms
           (list `(with-eval-after-load ,(or feature-name package-name)
                    ,@forms))))))

(package-deferred-install 'bug-hunter
    :autoload-names '('bug-hunter-file 'bug-hunter-init-file))

(defun package-uninstall (package-name)
  (interactive
   (let ((dir (expand-file-name package-user-dir)))
     (list (completing-read
            "Uninstall package: "
            (mapcar (lambda (package-dir)
                      (replace-regexp-in-string
                       "-[0-9.]+"
                       ""
                       (file-relative-name package-dir dir)))
                    (cl-remove-if-not
                     (lambda (item)
                       (and (file-directory-p item)
                            (not (string-match-p "archives$\\|\\.$" item))))
                     (directory-files dir t)))))))

  (dolist (item (file-expand-wildcards
                 (expand-file-name (concat package-user-dir "/*"))))
    (delete-directory item t t))
  (message "done."))

(provide 'config-package)
