;; -*- lexical-binding: t -*-
(require 'cl-lib)

(setq history-length 100
      history-delete-duplicates t)

(defvar file-name-mode-alist nil)

(defun my/register-file-name-mode-maybe ()
  (when (and buffer-file-name
             (not
              (file-name-extension
               buffer-file-name))
             (not (eq major-mode 'fundamental-mode)))
    (push (cons buffer-file-name major-mode) file-name-mode-alist)
    (push (cons buffer-file-name major-mode) auto-mode-alist)))

(add-hook 'after-change-major-mode-hook #'my/register-file-name-mode-maybe)

(defun my/compress-alist (alist)
  "Remove shadowed keys from `alist'"
  (let ((result))
    (dolist (elem alist)
      (unless (assoc (car elem) result)
        (push elem result)))
    (nreverse result)))

(use-package x-win
  :ensure nil
  :config
  (eval-when-compile
    (with-demoted-errors "Load error: %s"
      (require 'x-win)
      (require 'el-patch)))

  (el-patch-defun emacs-session-filename (session-id)
    "Construct a filename to save the session in based on SESSION-ID.
Return a filename in `user-emacs-directory', unless the session file
already exists in the home directory."
    (let ((basename (concat "session." session-id)))
      (el-patch-swap
        (locate-user-emacs-file basename
                                (concat ".emacs-" basename))
        (expand-file-name basename (locate-user-emacs-file "data"))))))

(use-package session
  :init
  (add-hook 'after-init-hook #'session-initialize)
  (setq auto-mode-alist (append auto-mode-alist file-name-mode-alist))

  :config
  (setq session-save-file (locate-user-emacs-file "data/.session")
        session-globals-max-string 16384
        session-registers-max-string 16384
        session-globals-max-size 1024
        session-jump-undo-remember 7
        session-jump-undo-threshold 60
        session-name-disable-regexp (eval-when-compile
                                      (rx (or (and line-start "/tmp")
                                              (and "COMMIT_EDITMSG" line-end))))

        session-globals-include '((kill-ring 400)
                                  (session-file-alist 200 t)
                                  (file-name-history 400)
                                  (file-name-mode-alist 400 t)
                                  search-ring
                                  regexp-search-ring)

        session-initialize '(session keys))

  (defun nadvice/session-save-session/quiet (old-fun &rest args)
    (if (called-interactively-p 'any)
        (apply old-fun args)
      (cl-letf* ((old-wr (symbol-function #'write-region))
                 ((symbol-function #'y-or-n-p) (lambda (&rest _args) t))
                 ((symbol-function #'write-region)
                  (lambda (start end filename
                                 &optional append _visit &rest args)
                    (apply old-wr
                           start
                           end
                           filename
                           append
                           0
                           args))))
        (apply old-fun args))))

  (defun nadvice/session-save-session/file-name-mode-alist (&rest _args)
    (setq file-name-mode-alist
          (nreverse
           (let ((res)
                 (orig (my/compress-alist file-name-mode-alist)))
             (dotimes (_ (min history-length (length orig)) res)
               (push (pop orig) res))))))

  (defun nadvice/session-initialize-quiet (old-fun &rest args)
    (let ((inhibit-message t))
      (apply old-fun args)))
  (run-with-idle-timer 10 t #'session-save-session)

  (advice-add 'session-save-session :around
              #'nadvice/session-save-session/quiet)
  (advice-add 'session-save-session :before
              #'nadvice/session-save-session/file-name-mode-alist)
  (advice-add 'session-save-session :before #'my/unpropertize-session)
  (advice-add 'session-initialize :around #'nadvice/session-initialize-quiet)

  ;; text properties severely bloat the history so delete them
  (defun my/unpropertize-session (&rest _args)
    (mapc (lambda (lst)
            (with-demoted-errors "Error: %s"
              (when (boundp lst)
                (set lst (mapcar #'substring-no-properties (eval lst))))))
          '(kill-ring
            minibuffer-history
            helm-grep-history
            helm-ff-history
            file-name-history
            read-expression-history
            extended-command-history
            evil-ex-history))))

(use-package saveplace
  :ensure nil
  :init
  (autoload 'save-place-find-file-hook "saveplace")
  (autoload 'save-place-dired-hook "saveplace")
  (autoload 'save-place-kill-emacs-hook "saveplace")
  (autoload 'save-place-to-alist "saveplace")

  (el-patch-defun save-place--setup-hooks (add)
    (cond
     (add
      (add-hook 'find-file-hook #'save-place-find-file-hook t)
      (add-hook 'dired-initial-position-hook #'save-place-dired-hook)
      (unless noninteractive
        (add-hook 'kill-emacs-hook #'save-place-kill-emacs-hook))
      (add-hook 'kill-buffer-hook #'save-place-to-alist))
     (t
      ;; We should remove the hooks, but only if save-place-mode
      ;; is nil everywhere.  Is it worth the trouble, tho?
      ;; (unless (or (default-value 'save-place-mode)
      ;;             (cl-some <save-place-local-mode-p> (buffer-list)))
      ;;   (remove-hook 'find-file-hook #'save-place-find-file-hook)
      ;;   (remove-hook 'dired-initial-position-hook #'save-place-dired-hook)
      ;;   (remove-hook 'kill-emacs-hook #'save-place-kill-emacs-hook)
      ;;   (remove-hook 'kill-buffer-hook #'save-place-to-alist))
      )))

  (el-patch-define-minor-mode save-place-mode
    "Non-nil means automatically save place in each file.
This means when you visit a file, point goes to the last place
where it was when you previously visited the same file."
    :global t
    :group 'save-place
    (save-place--setup-hooks save-place-mode))

  (save-place-mode +1)

  :config
  (setq save-place-file (locate-user-emacs-file "data/places")))

(use-package recentf
  :commands (recentf-track-opened-file
             recentf-track-closed-file
             recentf-save-list)
  :init
  (el-patch-feature recentf)
  (el-patch-defconst recentf-used-hooks
    '(
      (find-file-hook       recentf-track-opened-file)
      (write-file-functions recentf-track-opened-file)
      (kill-buffer-hook     recentf-track-closed-file)
      (kill-emacs-hook      recentf-save-list)
      )
    "Hooks used by recentf.")

  (defun my/recentf-onetime-setup ()
    (dolist (hook recentf-used-hooks) (apply #'add-hook hook)))

  (add-hook 'emacs-startup-hook #'my/recentf-onetime-setup)

  :config
  (setq recentf-save-file (locate-user-emacs-file "data/.recentf")
        recentf-max-saved-items 1000
        recentf-max-menu-items 50
        recentf-auto-cleanup 30)
  (add-to-list 'recentf-exclude (eval-when-compile
                                  (concat (rx line-start)
                                          (expand-file-name
                                           (locate-user-emacs-file "elpa")))))

  ;; TODO: Yeah so this is actually a horrifying hack.
  (dolist (hook recentf-used-hooks) (apply #'remove-hook hook))
  (recentf-mode +1)

  (let ((recentf-autosave-timer nil))
    (defun nadvice/recentf-autosave (&rest _args)
      (when (timerp recentf-autosave-timer)
        (cancel-timer recentf-autosave-timer))
      (setq recentf-autosave-timer
            (run-with-idle-timer
             3 nil
             (lambda ()
               ;; TODO: Yeah so this is actually another horrifying hack.
               (let ((inhibit-message t)
                     (write-file-functions
                      (remove 'recentf-track-opened-file
                              write-file-functions)))
                 (recentf-save-list)))))))

  (advice-add 'recentf-track-opened-file :after
              #'nadvice/recentf-autosave)

  (defun nadvice/recentf-quiet (old-fun &rest args)
    (let ((inhibit-message t))
      (apply old-fun args)))

  (advice-add 'recentf-cleanup :around #'nadvice/recentf-quiet))

(use-package desktop
  :ensure nil
  :init
  (defun desktop-autosave (&optional arg)
    (interactive "p")
    (if (called-interactively-p 'any)
        (if (= arg 4)
            (let* ((desktop-base-file-name
                    (read-from-minibuffer "Session name: "))
                   (desktop-base-lock-name
                    (concat
                     desktop-base-file-name
                     ".lock")))
              (desktop-save-in-desktop-dir))
          (desktop-save-in-desktop-dir)))
    (cl-letf ((inhibit-message t)
              ((symbol-function #'y-or-n-p) (lambda (_prompt) t)))
      (desktop-save-in-desktop-dir)))

  (defun desktop-load (&optional arg)
    (interactive "p")
    (if (= arg 4)
        (let* ((files (cl-remove-if
                       (lambda (item)
                         (string-match-p
                          (rx line-start
                              (or (and "." (zero-or-more not-newline))
                                  (and (zero-or-more not-newline) ".lock"))
                              line-end)
                          item))
                       (directory-files desktop-dirname)))
               (desktop-base-file-name (completing-read
                                        "Enter a desktop name: "
                                        files
                                        nil t))
               (desktop-base-lock-name
                (concat desktop-base-file-name ".lock")))
          (desktop-read)
          (desktop-remove))
      (desktop-read)))

  (unless (daemonp)
    (defvar desktop-auto-save-timer
      (run-with-idle-timer 3 nil #'desktop-autosave))

    (add-hook 'focus-out-hook
              (lambda ()
                (ignore-errors (cancel-timer desktop-auto-save-timer))
                (setq desktop-auto-save-timer
                      (run-with-idle-timer 0.2 nil #'desktop-autosave))))

    (add-hook 'focus-in-hook
              (lambda ()
                (ignore-errors (cancel-timer desktop-auto-save-timer))
                (setq desktop-auto-save-timer
                      (run-with-idle-timer 3 t #'desktop-autosave)))))

  :config
  (setq desktop-dirname (locate-user-emacs-file "data/desktop/")
        desktop-path (list desktop-dirname)
        desktop-base-file-name "emacs-desktop"
        desktop-base-lock-name "emacs-desktop.lock")

  ;; don't let a dead emacs own the lockfile
  (defun nadvice/desktop-owner (pid)
    (when pid
      (let* ((attributes (process-attributes pid))
             (cmd (cdr (assoc 'comm attributes))))
        (if (and cmd (string-prefix-p "emacs" cmd))
            pid
          nil))))

  (defun nadvice/desktop-claim-lock (&optional dirname)
    (write-region (number-to-string (emacs-pid)) nil
                  (desktop-full-lock-name dirname) nil 1))

  (advice-add 'desktop-owner :filter-return #'nadvice/desktop-owner)
  (advice-add 'desktop-claim-lock :override #'nadvice/desktop-claim-lock))

(use-package server
  :ensure nil
  :init
  (defun send-file-to-server (&optional arg)
    (interactive)
    (server-eval-at (concat "server"
                            (or arg
                                (read-from-minibuffer "Server ID: ")))
                    `(progn (find-file ,(buffer-file-name))
                            nil)))

  (defun send-desktop-to-server ()
    (interactive)
    (save-some-buffers t)
    (let* ((desktop-base-file-name "transplant")
           (desktop-base-lock-name
            (concat desktop-base-file-name ".lock")))
      (desktop-save-in-desktop-dir)
      (desktop-release-lock))
    (server-eval-at (concat "server"
                            (read-from-minibuffer "Server ID: "))
                    `(let* ((desktop-base-file-name "transplant")
                            (desktop-base-lock-name
                             (concat desktop-base-file-name ".lock")))
                       (desktop-clear)
                       (desktop-read)
                       (desktop-remove)))
    (kill-emacs))

  (defun send-all-files-to-server ()
    (let ((count 1))
      (catch 'done
        (while t
          (if (server-running-p
               (concat "server" (number-to-string count)))
              (throw 'done server-name)
            (cl-incf count))
          (when (> 20 count)
            (throw 'done nil))))
      (dolist (buf (buffer-list))
        (with-current-buffer buf
          (when (buffer-file-name (current-buffer))
            (send-file-to-server (number-to-string count)))))
      (kill-emacs)))

  (when (member "-P" command-line-args)
    (setq debug-on-error t)
    (delete "-P" command-line-args)
    (require 'server)
    (add-hook 'emacs-startup-hook #'send-all-files-to-server))

  :config
  (defun nadvice/server-mode (old-fun &rest args)
    (catch 'done
      (let ((count 1))
        (while t
          (if (server-running-p server-name)
              (progn
                (setq server-name (concat "server" (number-to-string count)))
                (cl-incf count))
            (apply old-fun args)
            (throw 'done server-name))))))

  (advice-add 'server-start :around #'nadvice/server-mode))

(use-package atomic-chrome
  :commands (atomic-chrome-start-server
             atomic-chrome-stop-server)
  :init
  (when (display-graphic-p)
    (idle-job-add-function #'atomic-chrome-start-server))

  :config
  (defun my/atomic-chrome-focus-browser ()
    (let ((srv (websocket-server-conn
                (atomic-chrome-get-websocket (current-buffer))))
          (srv-ghost (bound-and-true-p atomic-chrome-server-ghost-text))
          (srv-atomic (bound-and-true-p atomic-chrome-server-atomic-chrome)))
      (cond ((memq window-system '(mac ns))
             (cond ((eq srv srv-ghost)
                    (call-process "open" nil nil nil "-a" "Firefox"))
                   ((eq srv srv-atomic)
                    (call-process "open" nil nil nil "-a" "Google Chrome"))))
            ((and (eq window-system 'x) (executable-find "wmctrl"))
             (cond ((eq srv srv-ghost)
                    (call-process "wmctrl" nil nil nil "-a" "Firefox"))
                   ((eq srv srv-atomic)
                    (call-process "wmctrl" nil nil nil "-a" "Google Chrome")))))))

  (add-hook 'atomic-chrome-edit-done-hook #'my/atomic-chrome-focus-browser))

(provide 'config-desktop)
