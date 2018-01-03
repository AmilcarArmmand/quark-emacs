;; -*- lexical-binding: t -*-
(require 'cl-lib)
(require 'config-tramp)

(use-package eldoc
  :ensure nil
  :diminish eldoc-mode
  :config
  (eval-when-compile
    (with-demoted-errors "Load error: %s"
      (require 'flycheck)))

  (setq eldoc-idle-delay 0.1)
  (defun nadvice/eldoc-display-message-no-interference-p (old-fun &rest args)
    (and (apply old-fun args)
         (not (and (my/sp-on-delimiter-p)
                   (not (minibufferp))))
         (not (and (bound-and-true-p flycheck-mode)
                   (flycheck-overlay-errors-at (point))))))

  (advice-add 'eldoc-display-message-no-interference-p :around
              #'nadvice/eldoc-display-message-no-interference-p))


(use-package semantic
  :ensure nil
  :init
  ;; enable semantic code LALR(1) parser
  (add-hook 'prog-mode-hook #'semantic-mode)

  :config
  (with-eval-after-load 'semantic/db-file
    (defun my/semanticdb-file-directory-exists-p (old-fun &rest args)
      (cl-letf* (((symbol-function #'y-or-n-p) (lambda (prompt) t)))
        (apply old-fun args)))

    (advice-add 'semanticdb-file-directory-exists-p :around
                #'semanticdb-file-directory-exists-p))

  (setq semanticdb-default-save-directory
        (locate-user-emacs-file "data/semanticdb"))
  (global-semanticdb-minor-mode +1)
  (global-semantic-idle-scheduler-mode +1)
  (global-semantic-idle-summary-mode +1)

  (defun nadvice/semantic-idle-summary-idle-function (old-fun &rest args)
    (if (and (bound-and-true-p flycheck-mode)
             (flycheck-overlay-errors-at (point)))
        (flycheck-display-error-at-point)
      (apply old-fun args)))

  (advice-add 'semantic-idle-summary-idle-function
              :around
              #'nadvice/semantic-idle-summary-idle-function))

(use-package srefactor
  :defer-install t
  :commands (srefactor-refactor-at-point)
  :config
  (evil-set-initial-state 'srefactor-ui-menu-mode 'emacs))

(use-package abbrev
  :ensure nil
  :config
  (setq abbrev-file-name (locate-user-emacs-file "data/.abbrev_defs")))

;;; ====================================
;;; flycheck - real-time syntax checking
;;; ====================================

(use-package flycheck
  :init (global-flycheck-mode +1)
  :config
  (setq flycheck-display-errors-function #'my/display-error-messages-condensed
        flycheck-indication-mode nil)

  (defun my/display-error-messages-condensed (errors)
    (require 'dash)
    (-when-let (messages (-keep #'flycheck-error-message errors))
      (when (flycheck-may-use-echo-area-p)
        (display-message-or-buffer (mapconcat #'identity messages "\n")
                                   flycheck-error-message-buffer))))

  (set-face-background 'flycheck-fringe-warning nil)

  (set-face-attribute 'flycheck-error nil
                      :foreground nil
                      :background nil
                      :underline "#dc322f")

  (set-face-attribute 'flycheck-warning nil
                      :foreground nil
                      :background nil
                      :underline "#b58900")

  (set-face-attribute 'flycheck-info nil
                      :foreground nil
                      :background nil
                      :underline "#268bd2")

  ;; please don't give me emacs-lisp stylistic advice
  (setq-default flycheck-disabled-checkers '(emacs-lisp-checkdoc))

  (defun nadvice/flycheck-mode-line-status-text (&optional status)
    (let ((text (pcase (or status flycheck-last-status-change)
                  (`not-checked "")
                  (`no-checker "-")
                  (`running "*")
                  (`errored "!")
                  (`finished
                   (if flycheck-current-errors
                       (let ((error-counts (flycheck-count-errors
                                            flycheck-current-errors)))
                         (format "%s/%s"
                                 (or (cdr (assq 'error error-counts)) "")
                                 (or (cdr (assq 'warning error-counts)) "")))
                     ""))
                  (`interrupted "-")
                  (`suspicious "?"))))
      (concat (if (display-graphic-p) " ✓" " Γ") text)))

  (advice-add 'flycheck-mode-line-status-text :override
              #'nadvice/flycheck-mode-line-status-text)

  (defun flycheck-goto-nearest-error ()
    (interactive)
    (let ((next (flycheck-next-error-pos 1 nil))
          (prev (flycheck-next-error-pos -1 nil)))
      (cond
       ((and next prev)
        (goto-char (if  (< (abs (- (point) prev))
                           (abs (- (point) next)))
                       prev
                     next)))
       (next (goto-char next))
       (prev (goto-char prev))
       (t (user-error "No Flycheck errors")))))

  (define-key flycheck-mode-map (kbd "C-!") #'flycheck-goto-nearest-error))

;;; =======================================
;;; Flyspell - inline real time spell check
;;; =======================================
(use-package ispell
  :ensure nil
  :config
  (defun nadvice/ispell-init-process (old-fun &rest args)
    (cl-letf (((symbol-function 'message)
               (lambda (&rest args)
                 (when args
                   (apply #'format args)))))
      (apply old-fun args)))

  (advice-add 'ispell-init-process :around #'nadvice/ispell-init-process))

(use-package flyspell
  :ensure nil
  :init
  (when (or (executable-find "ispell")
            (executable-find "aspell")
            (executable-find "hunspell"))
    (add-hook 'text-mode-hook #'flyspell-mode)
    (add-hook 'prog-mode-hook #'flyspell-prog-mode))
  :config
  (setq flyspell-issue-message-flag nil
        flyspell-issue-welcome-flag nil)

  (add-hook 'flyspell-mode-hook
            (lambda ()
              (define-key flyspell-mode-map (kbd "C-.") nil)
              (define-key flyspell-mode-map (kbd "C-,") nil)
              (diminish 'flyspell-mode (if (display-graphic-p) " f̲" " f"))))

  (if (executable-find "hunspell")
      (setq ispell-program-name "hunspell")
    (when (executable-find "aspell")
      (add-to-list 'ispell-extra-args "--sug-mode=ultra"))))



;;; =============================================
;;; yasnippet -- extensible programmable snippets
;;; =============================================

(use-package yasnippet
  :init
  (setq yas-verbosity 0
        yas-alias-to-yas/prefix-p nil
        yas-use-menu nil)

  (defun my/yasnippet-onetime-setup ()
    (yas-global-mode +1)
    (remove-hook 'first-change-hook #'my/yasnippet-onetime-setup))

  (add-hook 'emacs-startup-hook
            (lambda ()
              (add-hook 'first-change-hook #'my/yasnippet-onetime-setup)))

  (defun my/ivy-yasnippet (_prompt choices &optional display-fn)
    "Use ivy to select a snippet. Put this into `yas-prompt-functions.'"
    (if (require 'ivy nil t)
        (let* ((disp-fn (or display-fn 'identity))
               (cands (mapcar (lambda (x) (cons (funcall disp-fn x) x)) choices))
               (result (ivy-read "Snippet: " (mapcar #'car cands))))
          (if (null result)
              (signal 'quit "user quit!")
            (cdr (assoc result cands))))
      nil))

  :config
  (set-face-attribute 'yas-field-highlight-face nil
                      :foreground nil
                      :background nil
                      :inherit 'region)
  (add-hook 'yas-global-mode-hook
            (lambda ()
              (diminish 'yas-minor-mode (if (display-graphic-p) " ¥" " Y"))))

  (setq yas-snippet-dirs (list (locate-user-emacs-file "data/snippets"))
        yas-key-syntaxes (remove "w" yas-key-syntaxes)
        yas-triggers-in-field t
        yas-key-syntaxes (list "w_." "w_.()" #'yas-try-key-from-whitespace))

  (defun yas-company-complete-or-next-field ()
    (interactive)
    (if company-candidates
        (company-complete-common-or-complete-full)
      (yas-next-field)))

  (define-key yas-keymap (kbd "<tab>") 'yas-company-complete-or-next-field)
  (define-key yas-keymap (kbd "TAB") 'yas-company-complete-or-next-field)

  (yas-reload-all)

  (add-to-list 'yas-prompt-functions #'my/ivy-yasnippet)

  ;; also use yasnippets for new file templates
  (defvar my/yas-template-dir (locate-user-emacs-file "data/templates"))

  (defun my/yatemplate-expand-yas-buffer ()
    "Expand the whole buffer with `yas-expand-snippet'."
    (require 'yasnippet)
    (yas-expand-snippet (buffer-string) (point-min) (point-max))
    (evil-insert-state))

  (defun my/yatemplate-fill-alist ()
    "Fill `auto-insert-alist'."
    (dolist (filename (nreverse (sort (file-expand-wildcards
                                       (concat my/yas-template-dir
                                               "**/*"))
                                      #'string<)))
      (let* ((split-name (split-string filename "="))
             (file-regex (if (eq (length split-name) 2)
                             (nth 1 split-name)
                           (lwarn "yatemplate" 'error
                                  "%s filename does not contain exactly one colon"
                                  filename)
                           nil)))
        (when file-regex
          (push (cons (intern file-regex)
                      (vector filename #'my/yatemplate-expand-yas-buffer))
                auto-insert-alist))))))

(use-package autoinsert
  :ensure nil
  :init
  (add-hook 'after-change-major-mode-hook
            (lambda ()
              (when (= (point-min) (point-max))
                (auto-insert))))

  :config
  (use-package yasnippet :demand t)
  (setq auto-insert-alist nil)
  (my/yatemplate-fill-alist))


;;; ==================================
;;; VLF intelligently edit large files
;;; ==================================

(defun my/buffer-binary-p (&optional buffer)
  "Return whether BUFFER or the current buffer is binary.

A binary buffer is defined as containing at least one null byte.

Returns either nil, or the position of the first null byte."
  (with-current-buffer (or buffer (current-buffer))
    (save-excursion
      (goto-char (point-min))
      (search-forward (string ?\x00) 4096 t 1))))

(defun my/hexl-if-binary ()
  "If `fundamental-mode' is active, and the current buffer
is binary, activate `hexl-mode'."
  (when (and (eq major-mode 'fundamental-mode)
             (my/buffer-binary-p))
    (hexl-mode)
    (message "Detected binary file. Switched to text mode.")))

(add-hook 'find-file-hooks 'my/hexl-if-binary)

(use-package vlf
  :defer-install t
  :commands (vlf)
  :init
  (defun nadvice/abort-if-file-too-large (_old-fun &rest args)
    (cl-destructuring-bind (size op-type filename) args
      (when (and size
                 (not (zerop size))
                 large-file-warning-threshold
                 (< large-file-warning-threshold size))
        (let ((char nil))
          (while (not (memq (setq char
                                  (read-event
                                   (propertize
                                    (format
                                     "File %s is large (%s): \
%s normally (o), %s with vlf (v) or abort (a)"
                                     (if filename
                                         (file-name-nondirectory filename)
                                       "")
                                     (file-size-human-readable size)
                                     op-type op-type)
                                    'face 'minibuffer-prompt)))
                            '(?o ?O ?v ?V ?a ?A))))
          (cond ((memq char '(?v ?V))
                 (vlf filename)
                 (error ""))
                ((memq char '(?a ?A))
                 (error "Aborted")))))))

  (advice-add 'abort-if-file-too-large :around #'nadvice/abort-if-file-too-large)

  :config
  (defun my/vlf-hook ()
    (setq bidi-display-reordering nil)
    (flyspell-mode -1)
    (flycheck-mode -1)
    (ws-butler-mode -1)
    (visual-line-mode -1)
    (adaptive-wrap-prefix-mode -1)
    (setq-local global-hl-line-mode nil)
    (setq-local column-number-mode nil)
    (my/hexl-if-binary)
    (message "Use C-c C-v → VLF"))

  (add-hook 'vlf-mode-hook #'my/vlf-hook))

;;; =================================
;;; Emacs fasd - find files from fasd
;;; =================================

(use-package fasd
  :defer-install t
  :commands (fasd-find-file)
  :config
  (setq fasd-enable-initial-prompt nil)

  (defun nadvice/fasd-find-file (old-fun &rest args)
    (require 'helm-mode)
    ;; overriding the completion system in emacs-fasd is surprisingly tricky
    (cl-letf (((symbol-function #'completing-read)
               #'helm--completing-read-default))
      (apply old-fun args)))

  (advice-add 'fasd-find-file :around
              #'nadvice/fasd-find-file))

;;; =================================================
;;; dumb-jump an unintelligent goto-definition system
;;; =================================================

(use-package dumb-jump
  :defer-install t
  :init
  (defun my/jump-to-definition-dwim ()
    (interactive)
    (if (and (executable-find "global")
             (or (getenv "GTAGSROOT")
                 (locate-dominating-file default-directory "GTAGS")))
        (helm-gtags-dwim)
      (dumb-jump-go)))

  :commands (dumb-jump-back
             dumb-jump-quick-look
             dumb-jump-go-other-window
             dumb-jump-go-current-window
             dumb-jump-go-prefer-external
             dumb-jump-go-prompt
             dumb-jump-go-prefer-external-other-window
             dumb-jump-go
             dumb-jump-mode))


;;; ===============================
;;; ix simple pastebin-like service
;;; ===============================

(use-package ix
  :defer-install t
  :commands (ix ix-delete ix-browse))

(provide 'config-intel)
