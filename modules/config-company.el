(eval-when-compile
  (with-demoted-errors
    (require 'cl-lib)
    (require 'flx)
    (require 'company)
    (require 'company-dabbrev-code)
    (require 'config-modes)))

(defvar company-flx-cache)
(defvar company-flx-limit 500)

(defun company-onetime-setup ()
  (require 'company)
  (run-hooks 'load-theme-hook)
  (remove-hook 'first-change-hook #'company-onetime-setup))

(add-hook 'emacs-startup-hook
  (lambda ()
    (add-hook 'first-change-hook #'company-onetime-setup)))

(defun completion-fuzzy-commonality (s1 s2)
  (setq
    s1 (string-to-list (copy-seq s1))
    s2 (string-to-list (copy-seq s2)))
  (if (> (length s1) (length s2))
    (cl-rotatef s1 s2))
  (let ((res))
    (dolist (char s1)
      (when-let ((idx (position char s2)))
        (push char res)
        (setq s2 (cl-subseq s2 (1+ idx)))))
    (concat (nreverse res))))

(defun completion-fuzzy-find-holes (merged str)
  (let ((holes) (idx))
    (dolist (i (number-sequence 0 (1- (length merged))))
      (setq idx
        (position
          (elt merged i)
          str))
      (when (> idx 0)
        (push i holes))
      (setq str (cl-subseq str (1+ idx))))
    (when (/= 0 (length str))
      (push (length merged) holes))
    holes))

(defun completion-fuzzy-merge (strs)
  (let ((common (car strs))
         (holes))

    (dolist (str strs)
      (setq common
        (completion-fuzzy-commonality common str)))

    (setq holes (make-vector (1+ (length common)) 0))
    (dolist (str strs)
      (dolist (hole (completion-fuzzy-find-holes common str))
        (cl-incf (elt holes hole))))

    (cons common (append holes nil))))

(defun completion-fuzzy-completion (string table predicate point
                                     &optional all-p)
  (let* ((beforepoint (substring string 0 point))
          (afterpoint (substring string point))
          (boundaries (completion-boundaries beforepoint table predicate afterpoint))
          (prefix (substring beforepoint 0 (car boundaries)))
          (infix (concat
                   (substring beforepoint (car boundaries))
                   (substring afterpoint 0 (cdr boundaries))))
          (suffix (substring afterpoint (cdr boundaries)))
          ;; |-              string                  -|
          ;;              point^
          ;;            |-  boundaries -|
          ;; |- prefix -|-    infix    -|-  suffix   -|
          ;;
          ;; Infix is the part supposed to be completed by table, AFAIKT.
          (regexp (concat "\\`"
                    (mapconcat
                      (lambda (x)
                        (setq x (string x))
                        (concat "[^" x "]*" (regexp-quote x)))
                      infix
                      "")))
          (candidates
            (let ((completion-regexp-list
                    (cons regexp completion-regexp-list)))
              (all-completions prefix table predicate))))

    (if all-p
      ;; Implement completion-all-completions interface
      (when candidates
        ;; Not doing this may result in an error.
        (setcdr (last candidates) (length prefix))
        candidates)
      ;; Implement completion-try-completions interface
      (if (= (length candidates) 1)
        (if (equal infix (car candidates))
          t
          ;; Avoid quirk of double / for filename completion. I don't
          ;; know how this is *supposed* to be handled.
          (when (and (> (length (car candidates)) 0)
                  (> (length suffix) 0)
                  (char-equal (aref (car candidates)
                                (1- (length (car candidates))))
                    (aref suffix 0)))
            (setq suffix (substring suffix 1)))
          (cons (concat prefix (car candidates) suffix)
            (length (concat prefix (car candidates)))))
        (if (= (length infix) 0)
          (cons string point)
          (cl-destructuring-bind (merged . holes)
            (completion-fuzzy-merge candidates)
            (cons
              (concat prefix merged suffix)
              (+ (length prefix)
                (if (string= infix merged)
                  (if (< point (+ (length prefix) (length infix)))
                    (length infix)
                    (while (/= point
                             (+ (length prefix)
                               (position (apply #'max holes) holes)))
                      (setf (elt holes (position (apply #'max holes) holes)) 0))
                    (setf (elt holes (position (apply #'max holes) holes)) 0)
                    (print holes)
                    (position (apply #'max holes) holes))
                  (position (apply #'max holes) holes))))))))))

(defun completion-fuzzy-try-completion (string table predicate point)
  (completion-fuzzy-completion string table predicate point))
(defun completion-fuzzy-all-completions (string table predicate point)
  (completion-fuzzy-completion string table predicate point 'all))

(add-to-list 'completion-styles-alist
  '(fuzzy
     completion-fuzzy-try-completion
     completion-fuzzy-all-completions
     "Simple fuzzy completion, which never alters the string to complete, unless a unique match exists."))

(setq completion-styles (list 'fuzzy))

(with-eval-after-load 'company
  (global-company-mode +1)
  (diminish 'company-mode (if (display-graphic-p) " ❃" " *"))
  (require 'flx)

  (setq
    company-idle-delay 0.1
    company-echo-delay 0
    company-auto-complete 'company-explicit-action-p
    company-minimum-prefix-length 2
    company-show-numbers nil
    company-tooltip-flip-when-above t
    company-tooltip-align-annotations t

    company-backends '((company-capf
                         company-yasnippet
                         company-dabbrev-code
                         company-files
                         company-keywords)

                        company-dabbrev)

    company-flx-cache (flx-make-string-cache 'flx-get-heatmap-str)
    company-transformers
    (list
      (lambda (cands)
        (let ((num-cands (length cands)))
          (mapcar #'car
            (sort (mapcar
                    (lambda (cand)
                      (cons
                        cand
                        (or (car (flx-score cand
                                   company-prefix
                                   company-flx-cache))
                          0)))
                    (if (< num-cands company-flx-limit)
                      cands
                      (let ((seq (sort cands
                                   (lambda (c1 c2)
                                     (< (length c1) (length c2)))))
                             (end (min company-flx-limit num-cands))
                             (result nil))
                        (while (and (>= (setq end (1- end)) 0) seq)
                          (push (pop seq) result))
                        (nreverse result))))
              (lambda (c1 c2)
                (> (cdr c1) (cdr c2)))))))))
  (eval-and-compile
    (cl-macrolet
      ((company-define-specific-modes (mode backend)
         `(add-hook ,mode
            (lambda ()
              (let ((old-backends company-backends))
                (set (make-local-variable 'company-backends)
                  (cons (cons
                          ,backend
                          (cdar old-backends))
                    (cdr old-backends))))))))

      (with-no-warnings
        (generate-calls company-define-specific-modes
          (
            ('c++-mode-hook     'company-clang)
            ('objc-mode-hook    'company-clang)
            ('c-mode-hook       'company-clang)
            ('cmake-mode-hook   'company-cmake)
            ('css-mode-hook     'company-css)
            ('java-mode-hook    'company-eclim)
            ('nxml-mode-hook    'company-nxml)
            ('html-mode-hook    'company-semantic)
            ('scheme-mode-hook  'company-semantic)
            ('texinfo-mode-hook 'company-semantic)
            ('python-mode-hook  'company-anaconda))))))

  (defun company-complete-common-or-complete-full ()
    (interactive)
    (when (company-manual-begin)
      (if (eq last-command #'company-complete-common-or-cycle)
        (let ((company-selection-wrap-around t))
          (call-interactively #'company-complete-selection))
        (let ((buffer-mod-tick (buffer-chars-modified-tick)))
          (call-interactively #'company-complete-common)
          (when (= buffer-mod-tick (buffer-chars-modified-tick))
            (call-interactively #'company-complete-selection)
            (call-interactively #'company-complete))))))

  (define-key company-active-map (kbd "<tab>")
    #'company-complete-common-or-complete-full)
  (define-key company-active-map (kbd "TAB")
    #'company-complete-common-or-complete-full)

  (defun setup-company-tooltip-faces  ()
    (set-face-attribute 'company-tooltip-common-selection nil
      :background "#839496"
      :foreground (if (< (display-color-cells) 256)
                    "black"
                    nil)
      :underline nil
      :inherit 'region)

    (set-face-attribute 'company-tooltip-selection nil
      :background "#586e75"
      :foreground nil
      :inherit 'region)

    (set-face-attribute 'company-tooltip-common nil
      :background nil
      :underline nil
      :inherit 'company-tooltip
      :foreground "#586e75")

    (set-face-attribute 'company-tooltip-annotation nil
      :foreground nil
      :background nil
      :inherit 'company-tooltip)

    (set-face-attribute 'company-tooltip nil
      :foreground nil
      :inherit 'default))

  (add-hook 'load-theme-hook #'setup-company-tooltip-faces)
  (setup-company-tooltip-faces))

(with-eval-after-load 'company-template
  (defun setup-company-template-faces ()
    (set-face-attribute 'company-template-field nil
      :foreground nil
      :background nil
      :inherit 'region))
  (add-hook 'load-theme-hook #'setup-company-template-faces)
  (setup-company-template-faces))

(with-eval-after-load 'company-dabbrev-code
  (setq company-dabbrev-code-everywhere t))

(provide 'config-company)
