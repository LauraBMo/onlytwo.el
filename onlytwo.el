;;; onlytwo.el --- At most two windows, and the pane you asked from answers -*- lexical-binding: t; -*-

;; Copyright (C) 2026 LauraBMo

;; Author: LauraBMo
;; Maintainer: LauraBMo <laurea987@gmail.com>
;; URL: https://github.com/LauraBMo/onlytwo.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: windows, convenience
;; SPDX-License-Identifier: MIT

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `onlytwo-mode' arranges `display-buffer' so that a frame never grows a third
;; window, and so that a newcomer lands where you would look for it:
;;
;;   1. It takes the pane on the RIGHT of the selected window, or the selected
;;      window itself when the frame has no pane to its right.
;;   2. Never a third window: two panes, or one buffer filling the frame.
;;   3. No pane has privileges: a pane is taken even when it is dedicated to its
;;      buffer -- the dedication is cleared first.
;;   4. Reading is not working: what you ask for from documentation (or the
;;      dashboard) takes the window you asked from, not the one beside it.
;;   5. Whole-frame buffers exist: the modes in `onlytwo-full-frame-modes' take
;;      the frame, and quitting one puts back the layout it displaced.
;;   6. Side windows -- anything with a non-nil `window-side' parameter, such as
;;      treemacs or pdf-tools' outline -- are NOT panes: never taken, and never
;;      counted, or a frame edge would look like a taken pane.
;;   7. Never stack.  A pane with no neighbour is split side by side whenever
;;      Emacs can split it at all, and reused when it cannot.
;;   8. A window moves the cursor only when your own command opened it.  A job
;;      finishing, or a process writing, changes what is on screen but never
;;      yanks the cursor out of what you are typing.
;;
;; The numbers are the design record's, from the configuration this package grew
;; out of; rules 8 and 10 of it were dropped along the way and are not gaps.
;;
;; Three claims here are load-bearing, and each was measured rather than assumed:
;;
;; - The policy arrives as `display-buffer-base-action' and NOT as an entry in
;;   `display-buffer-alist'.  An entry outranks even the ACTION a caller passes
;;   explicitly, so a same-window jump (rule 7's cousin, `g d') could not have its
;;   way.  The base action is consulted only when nothing else claimed the buffer.
;; - Rule 8's discriminator cannot be `called-interactively-p': it answers for the
;;   function whose BODY makes the call, and `display-buffer' reaches the base
;;   action through a plain `funcall' -- so inside this chain it is nil however the
;;   display was started.  Nor `this-command'/`real-this-command': both are still
;;   set after a command ends, so an idle timer would look like you.  A flag kept
;;   by `pre-command-hook' and `post-command-hook' is what works.
;; - `display-buffer-full-frame' takes the frame but saves nothing, so rule 5's
;;   restore cannot come from Emacs: `quit-restore-window' never calls
;;   `set-window-configuration'.  Hence this package's own action, and the
;;   `:around' advice on `quit-window' that puts the configuration back.

;;; Code:

(require 'seq)

(defgroup onlytwo nil
  "At most two windows, and the pane you asked from answers."
  :group 'windows
  :prefix "onlytwo-")

(defcustom onlytwo-in-place-modes '(helpful-mode julia-help-mode +dashboard-mode)
  "Major modes whose buffers are read, not worked in (rule 4).
What you ask for from one of these takes the window you asked from instead of
the pane beside it -- following a link in a help buffer, or clicking a dashboard
item.  A mode named here that is not loaded yet is harmless: `derived-mode-p'
simply never matches it.  Modes without a parent (`helpful-mode' is one, as is
`org-agenda-mode') have to be named; those derived from `special-mode' need
not be."
  :type '(repeat symbol))

(defcustom onlytwo-full-frame-modes '(dired-mode ibuffer-mode elfeed-search-mode)
  "Major modes whose buffers take the whole frame (rule 5).
Quitting one puts back the layout it displaced.  Conditions in
`display-buffer-alist' match DERIVED modes too, so a package's variant of one of
these is covered by the same rule."
  :type '(repeat symbol))

(defcustom onlytwo-focus-on-display t
  "Whether a window opened by your own command should take the cursor (rule 8).
When nil, no display ever moves the cursor; buffers still land in the right
pane.  A display that did NOT come from a command you ran -- a job finishing, a
process writing -- never moves the cursor either way."
  :type 'boolean)


;;
;;; Panes, and windows that are not panes

(defun onlytwo--side-window-p (window)
  "Non-nil when WINDOW is a frame-edge side window (rule 6)."
  (and window (window-parameter window 'window-side)))

(defun onlytwo--pane-windows (&optional frame)
  "The live panes of FRAME: its windows that are not side windows.
A frame edge owned by treemacs or pdf-tools' outline is not a pane; counted as
one, it would make a free pane look taken (rule 6)."
  (seq-remove #'onlytwo--side-window-p
              (window-list-1 nil 'nomini (or frame (selected-frame)))))

(defun onlytwo--place-in-pane (buffer window alist)
  "Display BUFFER in WINDOW, a pane, and return the window it landed in.
Rule 3: a pane has no privileges, so a window dedicated to its buffer is
un-dedicated rather than skipped.  Side windows never arrive here."
  ;; Rule 3's clearing is belt-and-braces: measured on 30.2, the
  ;; `window--display-buffer' call below clears the dedication itself, so no
  ;; case can catch this line being deleted.  Kept because the package claims
  ;; 29.1 too, and there it is unmeasured.
  (when (window-dedicated-p window)
    (set-window-dedicated-p window nil))
  (let ((window (window--display-buffer buffer window 'reuse alist)))
    (onlytwo--focus-window-maybe window)
    window))

(defun onlytwo--split-side-by-side (buffer alist)
  "Split the selected window side by side and display BUFFER in the new half.
Rule 7: side by side or not at all -- nil when Emacs cannot split this window,
which leaves the caller to reuse it instead.  A window below twice
`window-min-width' makes `split-window-right' SIGNAL rather than return nil
(measured: 16, 12 and 10 columns signal; 20 splits), hence `ignore-errors'."
  (when (and pop-up-windows
             (not (onlytwo--side-window-p (selected-window))))
    (when-let* ((window (ignore-errors (split-window-right))))
      (onlytwo--place-in-pane buffer window alist))))


;;
;;; Rule 4: what is being read is replaced, not split

(defun onlytwo--in-place-window-p ()
  "Non-nil when the selected window shows a buffer from `onlytwo-in-place-modes'.
Rule 3 applies here too: a dedicated window showing documentation counts."
  (with-current-buffer (window-buffer (selected-window))
    (apply #'derived-mode-p onlytwo-in-place-modes)))


;;
;;; Rule 8: a window moves the cursor only when your own command opened it

(defvar onlytwo--in-command nil
  "Non-nil while a command is executing, nil between commands.
Set and cleared from `pre-command-hook' and `post-command-hook'; see the
Commentary for why nothing else can answer this question.")

(defun onlytwo--in-command-on-h () (setq onlytwo--in-command t))
(defun onlytwo--in-command-off-h () (setq onlytwo--in-command nil))

(defun onlytwo--focus-window-maybe (window)
  "Select WINDOW when this display came from a command of yours.
`onlytwo--in-command' is the discriminator, gated by `onlytwo-focus-on-display'.
The minibuffer guard keeps a completion or help window shown DURING minibuffer
input from taking the cursor."
  (when (and onlytwo-focus-on-display
             window
             (window-live-p window)
             (not (active-minibuffer-window))
             onlytwo--in-command)
    (select-window window)))


;;
;;; The policy

(defun onlytwo-display-buffer (buffer alist)
  "Display BUFFER in one of the frame's panes, never creating a third.
The pane on the right of the selected window; the selected window itself
when the frame has no pane to its right, or when documentation is being
read there; the frame's only pane split side by side, or reused when it
cannot be split."
  (or (display-buffer-reuse-window buffer alist)
      (let* ((selected (selected-window))
             (panes (onlytwo--pane-windows))
             (others (delq selected panes))
             (spare (car others))
             ;; `window-in-direction' may answer with a SIDE window -- treemacs on
             ;; the left, pdf-tools' outline on the right -- which is not a pane,
             ;; so only a member of `others' counts (rule 6).
             (right (let ((window (window-in-direction 'right selected)))
                      (and (memq window others) window)))
             ;; The other pane: the one on the right, or any pane for a caller
             ;; that asked not to get this window back.
             (other (or right
                        (and (cdr (assq 'inhibit-same-window alist)) spare))))
        (cond
         ;; Reading: this pane is the one that gets replaced.
         ((onlytwo--in-place-window-p)
          (onlytwo--place-in-pane buffer selected alist))
         (other
          (onlytwo--place-in-pane buffer other alist))
         ;; Nothing to the right of this pane: rule 1 says this pane is the one
         ;; that gets replaced.  A pane with NO neighbour is split instead (rule
         ;; 7), since taking it over would leave a single window.
         (others
          (onlytwo--place-in-pane buffer selected alist))
         (t
          (or (onlytwo--split-side-by-side buffer alist)
              (onlytwo--place-in-pane buffer selected alist)))))))


;;
;;; Rule 5: whole-frame buffers, and putting the layout back

(defun onlytwo-display-buffer-full-frame (buffer alist)
  "Display BUFFER in the whole frame, remembering the layout to put back.
`display-buffer-full-frame' takes the frame but saves nothing, so the
configuration is captured here for `onlytwo--quit-window-restore-a'."
  (let ((config (current-window-configuration)))
    (when-let* ((window (display-buffer-full-frame buffer alist)))
      (set-window-parameter window 'onlytwo--saved-wconf config)
      window)))

(defun onlytwo--quit-window-restore-a (fn &optional kill window)
  "Put back the layout a full-frame buffer displaced, then quit it (rule 5).
`:around' rather than `:before': the configuration must be READ while the
window is still alive (quitting may delete it), and restored only AFTER the
original has run, or the restored layout's own window would be the one quit
next."
  (let* ((window (or window (selected-window)))
         (config (and (window-live-p window)
                      (window-parameter window 'onlytwo--saved-wconf))))
    (prog1 (funcall fn kill window)
      (when (window-configuration-p config)
        (set-window-configuration config)))))

(defun onlytwo--install-full-frame-rules ()
  "Install the `display-buffer-alist' rules for `onlytwo-full-frame-modes'.
`add-to-list', not `setq'/`append', so that re-enabling the mode -- or any other
re-evaluation -- cannot push a second copy of the same rule."
  (dolist (mode onlytwo-full-frame-modes)
    (add-to-list 'display-buffer-alist
                 `((major-mode . ,mode) . (onlytwo-display-buffer-full-frame)))))

(defun onlytwo--uninstall-full-frame-rules ()
  "Remove this package's rules from `display-buffer-alist'."
  (setq display-buffer-alist
        (seq-remove (lambda (entry)
                      (equal (cdr entry) '(onlytwo-display-buffer-full-frame)))
                    display-buffer-alist)))


;;
;;; The mode

(defvar onlytwo--saved-base-action nil
  "The `display-buffer-base-action' this mode displaced, to restore on disable.")

;;;###autoload
(define-minor-mode onlytwo-mode
  "Never more than two windows, and place the newcomer where you would look.

The rules, and what they are for, are in this file's Commentary; the reasoning
and the measurements behind them are in the README.

Turning the mode off withdraws the policy only: the windows and the frame
configuration are left exactly as they are."
  :global t
  :lighter nil
  :group 'onlytwo
  (if onlytwo-mode
      (progn
        (add-hook 'pre-command-hook #'onlytwo--in-command-on-h)
        (add-hook 'post-command-hook #'onlytwo--in-command-off-h)
        (advice-add 'quit-window :around #'onlytwo--quit-window-restore-a)
        ;; A window parameter must be declared persistent to survive the state
        ;; saving `set-window-configuration' does.
        (add-to-list 'window-persistent-parameters '(onlytwo--saved-wconf . writable))
        (onlytwo--install-full-frame-rules)
        (setq onlytwo--saved-base-action display-buffer-base-action
              display-buffer-base-action '((onlytwo-display-buffer) . nil)))
    (remove-hook 'pre-command-hook #'onlytwo--in-command-on-h)
    (remove-hook 'post-command-hook #'onlytwo--in-command-off-h)
    (advice-remove 'quit-window #'onlytwo--quit-window-restore-a)
    (onlytwo--uninstall-full-frame-rules)
    (setq display-buffer-base-action onlytwo--saved-base-action
          onlytwo--saved-base-action nil)))

(provide 'onlytwo)
;;; onlytwo.el ends here
