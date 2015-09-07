;; -*- lexical-binding: t -*-

(setq mouse-wheel-scroll-amount '(3 ((shift) . 1))
      mouse-wheel-progressive-speed nil
      mouse-wheel-follow-mouse t
      smooth-scroll-margin 5
      scroll-step 1
      auto-window-vscroll nil
      scroll-conservatively 1000)

(global-set-key (kbd "<left-margin> <mouse-5>")
                (kbd "<mouse-5> <mouse-5> <mouse-5>"))
(global-set-key (kbd "<left-margin> <mouse-4>")
                (kbd "<mouse-4> <mouse-4> <mouse-4>"))

(provide 'config-scroll)
