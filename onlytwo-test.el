;;; onlytwo-test.el --- the cases for the window-placement policy -*- lexical-binding: t; -*-

;;   emacs -Q --batch -l ~/src/lisp/onlytwo.el/onlytwo-test.el ; echo "exit=$?"

;; Exit code is the verdict: 0 = everything that RAN passed, 1 = something
;; failed.  A skip is not a failure -- but it is not a pass either, so the
;; summary carries the skip count and names every skipped check: a green run
;; that quietly left half the suite out must not look like a full one.
;;
;; WHAT IT CHECKS, in `onlytwo.el':
;;
;;   1. `onlytwo-display-buffer' itself -- which pane a new buffer lands in, and
;;      that a THIRD window never appears.  The panes are the frame's non-side
;;      windows, so an edge owned by treemacs or pdf-tools' outline is not
;;      mistaken for one (rule 6); a pane DEDICATED to its buffer is taken over --
;;      un-dedicated -- rather than skipped (rule 3); and a sole window is split
;;      side by side however narrow, or reused when it cannot be split at all,
;;      `split-width-threshold' never being consulted (rule 7);
;;   2. the one exception to it: a buffer being *read* -- `onlytwo-in-place-modes',
;;      helpful, the Julia doc buffers and the Doom dashboard -- takes the window
;;      it was asked from instead of the pane beside it. A case for each of the
;;      three: both kinds of link followed in a real helpful buffer, a stand-in in
;;      `julia-help-mode', and the `find-file' a dashboard click runs (the
;;      real dashboard needs Doom, so its clicks are driven on a stand-in buffer
;;      in `+dashboard-mode');
;;   3. and that the exception is scoped to reading: an unrelated buffer landing
;;      while documentation is selected obeys the policy instead.
;;
;; Rule 8 (the cursor) is NOT here: it needs a real command, and a batch run has
;; none -- `onlytwo--in-command' is never set, so no case could see it.  That
;; half lives in the fresh-Emacs harness beside this file's old home
;; (~/.claude/test-scripts/-home-laury--config-doom/fresh-window-policy.el).
;;
;; HOW THE PACKAGE GETS HERE.  The repo this file sits in goes on `load-path';
;; `onlytwo-mode' then installs the whole policy -- the base action, the two
;; hooks rule 8 needs, the full-frame rules and the `quit-window' advice -- so
;; these cases run against what a session actually loads, not against a copy.
;;
;; The shape check that used to open this file is gone, and deliberately: it read
;; each form out of config.org and asserted the next one was the one expected,
;; because org-tangle can silently swallow a form -- an unbalanced `defun' makes
;; `read' take what follows -- and the block would still "work" while quietly
;; losing the `setq' that installed the policy (that happened once; see
;; CONFIG-NOTES.org).  A plain .el file has no tangling step to go wrong, so the
;; check has no subject left.
;;
;; HELPFUL IS NOT A DEPENDENCY.  Section 2's cases follow links in a REAL helpful
;; buffer, and helpful is not something a clone of this repo can assume: it is
;; installed by the user's configuration, here under Doom's straight build
;; directory.  `ot/load-helpful' tries that, and when helpful does not come up
;; those cases are SKIPPED -- by name, in the summary -- instead of failing, so
;; the suite still runs on a machine that has never seen Doom.  `ot/helpful-checks'
;; lists every check the section makes, which is what a skipped run reports.
;; Helpful names its buffers itself ("*helpful function: car*", but "*helpful
;; command: ...*" for a command), so where the name is not certain a case picks
;; the buffer up from the window instead.
;;
;; Geometry: batch frames are 80 columns wide, and a window needs 20 columns to
;; be split at all (twice `window-min-width' -- cases 6b and 6c).  The policy
;; never consults `split-width-threshold', so that variable is set only where a
;; case has to prove it is ignored (case 6); case 6c narrows the frame itself to
;; get a window under that floor.  What is under test is which window ends up
;; showing which buffer.

(require 'cl-lib)
(require 'seq)

;;; Setup

(defconst ot/package-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "The repo this test lives in: onlytwo.el's own directory.")

(defun ot/straight-build-dir ()
  "Doom's straight build directory for this Emacs, else the newest one.
nil when there is no straight tree at all, which is the normal state on a
machine that does not run Doom."
  (let* ((root (expand-file-name "~/.config/emacs/.local/straight"))
         (exact (expand-file-name (format "build-%d.%d"
                                          emacs-major-version emacs-minor-version)
                                  root))
         (all (and (file-directory-p root)
                   (sort (seq-filter #'file-directory-p
                                     (directory-files root t "\\`build-"))
                         #'string<))))
    (or (and (file-directory-p exact) exact)
        (car (last all)))))

;; `helpful' is optional and loaded late, so the compiler cannot see this
;; definition; declared rather than left as a warning.
(declare-function helpful-callable "helpful" (symbol))

(defun ot/load-helpful ()
  "Load the real helpful package, or return nil without signalling.
Helpful is where the user's configuration put it -- here, Doom's straight build
directory -- so that directory goes on `load-path' first, and then plain
`require'.  A machine with neither answers nil, and the cases that need helpful
are skipped rather than failed."
  (or (require 'helpful nil t)
      (when-let* ((build (ot/straight-build-dir)))
        (dolist (dir (directory-files build t))
          (when (file-directory-p dir)
            (push dir load-path)))
        (require 'helpful nil t))))

(defvar ot/helpful-p (ot/load-helpful)
  "Non-nil when the real helpful package is loaded.
nil reads as \"this machine has not got it\", and section 2's cases are then
reported as skipped instead of run.")

(add-to-list 'load-path ot/package-dir)
(require 'onlytwo)
(onlytwo-mode +1)

;;; Harness

(defvar ot/test-failures 0)
(defvar ot/passes 0)
(defvar ot/skips 0)
(defvar ot/skipped-names nil
  "The skipped checks, newest first; nreversed into the summary.")

(defun ot/skip (name)
  "Report the check NAME as skipped: it needs the real helpful package.
Printed where the check would have been, and listed again in the summary."
  (setq ot/skips (1+ ot/skips))
  (setq ot/skipped-names (cons name ot/skipped-names))
  (princ (format "SKIP  %-38s needs helpful\n" name)))

(defun ot/check (name expected got)
  (if (equal expected got)
      (progn (setq ot/passes (1+ ot/passes))
             (princ (format "PASS  %-38s %S\n" name got)))
    (setq ot/test-failures (1+ ot/test-failures))
    (princ (format "FAIL  %-38s expected %S, got %S\n" name expected got))))

(defconst ot/test-buffers '("*A*" "*B*" "*C*" "*source.el*" "*dash*" "*doc*" "*dired*")
  "Buffers the cases below display; reset (and emptied) before each one.")

(defun ot/reset-buffers ()
  "A clean slate: no dedicated windows and no leftover displayable buffer.
A leftover *helpful* buffer would be found by `display-buffer-reuse-window'
and quietly change the answer, so those go too.  The stand-in buffers get
their major mode back too: two of the cases below put `+dashboard-mode' and
`julia-help-mode' into one of `ot/test-buffers', and a mode left behind
would make the next case read as documentation."
  (dolist (w (window-list nil 'nomini))
    (set-window-dedicated-p w nil))
  (dolist (b (buffer-list))
    (when (and (or (string-prefix-p "*helpful" (buffer-name b))
                   (equal (buffer-name b) "helpful.el"))
               (not (buffer-modified-p b)))
      (kill-buffer b)))
  (dolist (name ot/test-buffers)
    (with-current-buffer (get-buffer-create name)
      (setq buffer-read-only nil)
      (setq major-mode 'fundamental-mode)
      (erase-buffer))))

(defun ot/state ()
  "Geometry, not selection order: (FIRST SECOND LAYOUT COUNT).
FIRST/SECOND are the buffer names read top-left to bottom-right: for a
side-by-side split that is (LEFT RIGHT), for a stacked one (TOP BOTTOM),
for a single window just (THE ONE).  `window-list' starts at the selected
window and wraps, so it cannot be used for this."
  (let* ((ws (window-list nil 'nomini))
         (sorted (sort (copy-sequence ws)
                       (lambda (a b)
                         (let ((ea (window-edges a))
                               (eb (window-edges b)))
                           (or (< (nth 0 ea) (nth 0 eb))
                               (and (= (nth 0 ea) (nth 0 eb))
                                    (< (nth 1 ea) (nth 1 eb))))))))
         (names (mapcar (lambda (w) (buffer-name (window-buffer w))) sorted)))
    (append names
            (list (cond ((null (cdr ws)) 'single)
                        ((and (= (nth 0 (window-edges (car ws)))
                                 (nth 0 (window-edges (cadr ws))))
                              (= (nth 2 (window-edges (car ws)))
                                 (nth 2 (window-edges (cadr ws)))))
                         'stacked)
                        ((and (= (nth 1 (window-edges (car ws)))
                                 (nth 1 (window-edges (cadr ws))))
                              (= (nth 3 (window-edges (car ws)))
                                 (nth 3 (window-edges (cadr ws)))))
                         'side-by-side)
                        (t 'unknown))
                  ;; The window count is what catches a third window.
                  (length ws)))))

(defun ot/one-window (buf)
  "A sole window showing BUF."
  (ot/reset-buffers)
  (delete-other-windows)
  (setq split-width-threshold 40
        split-height-threshold nil)
  (switch-to-buffer buf))

(defun ot/two-windows (left-buf right-buf &optional dedicated-right)
  "Side-by-side LEFT-BUF | RIGHT-BUF, left selected.  Returns (LEFT RIGHT)."
  (ot/one-window left-buf)
  (let* ((l (selected-window))
         (r (split-window l nil 'right)))
    (set-window-buffer r right-buf)
    (select-window l)
    (when dedicated-right (set-window-dedicated-p r t))
    (list l r)))

(defun ot/find-navigate-button (buffer)
  "The first \"defined in foo.el\" button in BUFFER, or nil.
Those are the buttons `helpful--navigate' acts on; they are the only ones
carrying a `path' property."
  (with-current-buffer buffer
    (let ((pos (point-min)) found b)
      (while (and (not found) (< pos (point-max)))
        (setq b (next-button pos t))    ; t: a button sitting at POS counts too
        (cond ((null b) (setq pos (point-max)))
              ((button-get b 'path) (setq found b))
              (t (setq pos (1+ (button-end b))))))
      found)))

;;; 1. The policy itself

;; 1. Sole window, split possible -> split to the right, buffer on the RIGHT.
(ot/one-window "*A*")
(display-buffer "*B*")
(ot/check "1  sole window, split" '("*A*" "*B*" side-by-side 2) (ot/state))

;; 2. Two windows, left selected -> the right pane takes it, still two windows.
(ot/two-windows "*A*" "*C*")
(display-buffer "*B*")
(ot/check "2  left selected" '("*A*" "*B*" side-by-side 2) (ot/state))

;; 3. Two windows, right selected -> that pane takes it, no third window.
(let* ((wins (ot/two-windows "*A*" "*C*"))
       (r (cadr wins)))
  (select-window r)
  (display-buffer "*B*")
  (ot/check "3  rightmost selected" '("*A*" "*B*" side-by-side 2) (ot/state))
  (ot/check "3b selected pane unchanged" t (eq (selected-window) r)))

;; 4. Buffer already on screen (left pane) while the right is selected
;;    -> reuse it, do not move it and do not show it twice.
(ot/two-windows "*B*" "*C*")
(select-window (cadr (window-list nil 'nomini)))  ; right window
(display-buffer "*B*")
(ot/check "4  already visible, left alone" '("*B*" "*C*" side-by-side 2) (ot/state))

;; 5. Rule 3: no pane has privileges, so a pane DEDICATED to its buffer is
;;    TAKEN OVER -- the dedication is cleared and the newcomer lands there --
;;    instead of being skipped for the pane beside it.  Dedicated panes are
;;    ordinary here: `+vterm/toggle' and Doom's eshell dedicate theirs.  A SIDE
;;    window is the different thing, not a pane at all -- case 5c.
(let* ((wins (ot/two-windows "*A*" "*C*" 'dedicated))
       (r (cadr wins)))
  (display-buffer "*B*")
  (ot/check "5  dedicated pane taken over"
            '("*A*" "*B*" side-by-side 2 nil)
            (append (ot/state) (list (window-dedicated-p r)))))

;; 5b. Rule 3 again, with the dedicated pane the SELECTED one: rule 1 hands the
;;     newcomer the selected window (there is no pane to its right) and rule 3
;;     makes it take that window over rather than the frame's other pane.  Used
;;     to be the other way round.
(let* ((wins (ot/two-windows "*A*" "*C*" 'dedicated))
       (r (cadr wins)))
  (select-window r)                        ; the dedicated window is selected
  (display-buffer "*B*")
  (ot/check "5b selected pane dedicated, taken over"
            '("*A*" "*B*" side-by-side 2 nil)
            (append (ot/state) (list (window-dedicated-p r)))))

;; 5c. Rule 6: a side window on the frame's right edge (treemacs, pdf-tools'
;;     outline) is NOT a pane.  Mistaken for the pane to the right of the sole
;;     window it would be written into and the buffer it holds lost; instead the
;;     window is split and the side window keeps showing its own buffer.
(ot/one-window "*A*")
(display-buffer-in-side-window (get-buffer-create "side") '((side . right)))
(display-buffer "*B*")
(ot/check "5c side window is not a pane"
          '("*A*" "*B*" "side" side-by-side 3)
          (ot/state))

;; 6. Rule 7: the policy never consults `split-width-threshold' -- it calls
;;    `split-window-right' directly -- so a sole window is ALWAYS split side by
;;    side, however narrow, and `split-window-sensibly's stacked fallback is
;;    gone.  The thresholds below are set to what used to force a stack, to prove
;;    they now change nothing.
(ot/one-window "*A*")
(setq split-width-threshold 1000
      split-height-threshold 10)
(display-buffer "*B*")
(ot/check "6  threshold ignored: still side by side"
          '("*A*" "*B*" side-by-side 2)
          (ot/state))

;; 6b. Rule 7's floor: `split-window-right' needs each half at least
;;     `window-min-width' (10) columns, so below 20 columns it SIGNALS rather than
;;     returning nil (measured: 20 splits; 18, 16, 14, 12 and 10 all signal) --
;;     hence the `ignore-errors' in the policy.  A pane that narrow is REUSED:
;;     built with `split-window-right' and selected (a negative SIZE gives the
;;     new RIGHT window the columns), the buffer lands in it, no third window
;;     appearing.
(ot/one-window "*A*")
(select-window (split-window-right -16))
(display-buffer "*B*")
(ot/check "6b too narrow to split: reused"
          '("*A*" "*B*" side-by-side 2)
          (ot/state))
(ot/check "6b buffer landed in the selected pane"
          "*B*" (buffer-name (window-buffer (selected-window))))
(ot/check "6b that pane is under 20 columns"
          t (< (window-width (selected-window)) 20))

;; 6c. The floor as the SOLE pane: the one shape that reaches the `ignore-errors'
;;     in `onlytwo--split-side-by-side'.  With a second pane present 6b never
;;     tries to split at all; alone, the 16-column window cannot be split
;;     (`split-window-right' signals), so the policy REUSES it -- the buffer
;;     replaces what the window held, no new window appears and the frame keeps
;;     one window.  The frame is narrowed for this and widened again after, since
;;     the cases below are built on the 80-column frame.
(ot/one-window "*A*")
(let ((full (frame-width)))
  (set-frame-width (selected-frame) 16)
  (display-buffer "*B*")
  (ot/check "6c too narrow alone: reused, one window"
            '("*B*" single 1)
            (ot/state))
  (ot/check "6c the sole window is still under 20 columns"
            t (< (window-width (selected-window)) 20))
  (set-frame-width (selected-frame) full))

;; 7. Caller insists on another window while the selected one is rightmost
;;    -> the left pane is the only other one.
(ot/two-windows "*A*" "*C*")
(select-window (cadr (window-list nil 'nomini)))
(display-buffer "*B*" '(nil (inhibit-same-window . t)))
(ot/check "7  inhibit-same-window" '("*B*" "*C*" side-by-side 2) (ot/state))

;; 8. Re-displaying the buffer of the current pane -> nothing moves, no dup.
(ot/two-windows "*A*" "*B*")
(display-buffer "*A*")
(ot/check "8  re-display current pane" '("*A*" "*B*" side-by-side 2) (ot/state))

;; 8b. Rule 8's other half: the discriminator itself.  A display that lands in
;;     the pane BESIDE the selected one must leave the cursor where it was, since
;;     no command of yours opened it.  Case 3b cannot show this -- there the
;;     newcomer goes into the pane already selected, so a policy that took the
;;     cursor unconditionally passed it too.  The second check keeps the first
;;     honest: had the newcomer landed in the selected pane, "the cursor stayed
;;     put" would have been true for the wrong reason.
(let* ((wins (ot/two-windows "*A*" "*C*"))
       (left (car wins))
       (right (cadr wins)))
  (display-buffer "*B*")
  (ot/check "8b newcomer in the other pane" "*B*" (buffer-name (window-buffer right)))
  (ot/check "8b top level: cursor stays put" t (eq (selected-window) left)))

;; 8c. The same display, inside the command loop's hooks: this one is a command
;;     of yours, so the cursor DOES follow the newcomer.  `run-hooks' is what the
;;     loop does, so the case drives the real discriminator -- the flag the hooks
;;     keep -- rather than setting the flag itself.
(let* ((wins (ot/two-windows "*A*" "*C*"))
       (right (cadr wins)))
  (unwind-protect
      (progn (run-hooks 'pre-command-hook)
             (display-buffer "*B*"))
    (run-hooks 'post-command-hook))
  (ot/check "8c your own command: cursor moves" t (eq (selected-window) right)))

;;; 2. Links inside a helpful buffer

;; H1-H6b need the REAL helpful package; `ot/helpful-checks' names every check
;; they make, so a run without helpful reports them all as SKIPPED instead of
;; running them against nothing.

(defconst ot/helpful-checks
  '("H1 open help: policy, splits right"
    "H2 symbol link: in place"
    "H2 the pane keeps the click"
    "H3 setup: help alone"
    "H3 symbol link: stays one window"
    "H4 setup: helpful-mode in the sole window"
    "H4 setup: one window"
    "H4 file link: same window"
    "H5 dedicated help pane taken over"
    "H5 the pane is un-dedicated"
    "H6a unrelated buffer, help rightmost"
    "H6b unrelated buffer, help left: takes its pane")
  "Every check section 2 makes; all of them need the real helpful package.")

(when ot/helpful-p

  ;; H1. Opening help from a source file in a sole window: the policy still
  ;;     applies -- help opens in a new pane on the right, source stays visible.
  (ot/one-window "*source.el*")
  (helpful-callable 'car)
  (ot/check "H1 open help: policy, splits right"
            '("*source.el*" "*helpful function: car*" side-by-side 2) (ot/state))

  ;; H2. A symbol link inside that help, in the selected (rightmost) pane: the
  ;;     target replaces the help in place, no third window, source untouched.
  (helpful-callable 'cdr)
  (ot/check "H2 symbol link: in place"
            '("*source.el*" "*helpful function: cdr*" side-by-side 2) (ot/state))
  (ot/check "H2 the pane keeps the click"
            "*helpful function: cdr*" (buffer-name (window-buffer (selected-window))))

  ;; H3. The case that started this: help ALONE in a single-window frame.  A link
  ;;     replaces it there rather than splitting the frame -- what built-in
  ;;     `help-mode' does, since it reuses its one *Help* buffer, while helpful
  ;;     makes a new buffer per symbol and so has nothing to reuse.
  (ot/one-window "*source.el*")
  (helpful-callable 'car)
  (delete-other-windows)                  ; keep the help window, now alone
  (ot/check "H3 setup: help alone" '("*helpful function: car*" single 1) (ot/state))
  (helpful-callable 'cdr)
  (ot/check "H3 symbol link: stays one window"
            '("*helpful function: cdr*" single 1) (ot/state))

  ;; H4. The other door: "defined in foo.el" goes through `helpful--navigate'.
  ;;     Same window too -- here the real button, out of the real help buffer for
  ;;     a function that does have a source file.  The buffer is taken from the
  ;;     window rather than named: helpful picks the name itself, and it is
  ;;     "*helpful command: ...*" for a command, "*helpful function: ...*" for a
  ;;     plain function.
  (ot/one-window "*source.el*")
  (helpful-callable 'helpful-callable)
  (delete-other-windows)
  (let ((help (window-buffer (selected-window))))
    (ot/check "H4 setup: helpful-mode in the sole window"
              t (eq 'helpful-mode (buffer-local-value 'major-mode help)))
    (ot/check "H4 setup: one window" 1 (length (window-list nil 'nomini)))
    (with-current-buffer help
      (let ((button (ot/find-navigate-button help)))
        (cond ((null button)
               (ot/check "H4 file link: button found" 'found 'missing))
              (t
               ;; `push-button' acts on a text-property button in the current
               ;; buffer, which is why this runs inside the help buffer.
               (push-button (button-start button))
               (ot/check "H4 file link: same window"
                         '("helpful.el" single 1) (ot/state)))))))

  ;; H5. Rule 3 reaches the reading case too: a pane showing help and dedicated to
  ;;     it is TAKEN OVER -- the link replaces the help in place there, in the pane
  ;;     it was asked from, and the dedication is cleared.  (A pane that is itself a
  ;;     side window is the different thing rule 6 keeps untouched; this one is a
  ;;     normal pane dedicated by hand.)
  (ot/two-windows "*source.el*" "*scratch*")
  (helpful-callable 'car)                 ; left selected -> help lands right
  (let ((pane (selected-window)))         ; the pane help-callable showed
    (set-window-dedicated-p pane t)
    (helpful-callable 'cdr)               ; the pane is dedicated and selected
    (ot/check "H5 dedicated help pane taken over"
              '("*source.el*" "*helpful function: cdr*" side-by-side 2)
              (ot/state))
    (ot/check "H5 the pane is un-dedicated" nil (window-dedicated-p pane)))

  ;; H6. The exception is scoped by what is *read*, not by who asked -- the whole
  ;;     difference from the doors it replaced.  An unrelated buffer arriving while
  ;;     documentation is selected follows the exception; where the docs are
  ;;     rightmost that is the pane the policy would have taken anyway, so only
  ;;     the left-hand geometry shows the change.
  (ot/one-window "*source.el*")
  (helpful-callable 'car)
  (display-buffer "*B*")
  (ot/check "H6a unrelated buffer, help rightmost"
            '("*source.el*" "*B*" side-by-side 2) (ot/state))

  ;; H6b. The cost accepted with the simplification, stated as a case so it cannot
  ;;      change unnoticed: help on the LEFT loses its own pane to the arriving
  ;;      buffer instead of the pane beside it.
  (ot/one-window "*source.el*")
  (helpful-callable 'car)
  (let* ((r (selected-window))
         (l (window-in-direction 'left r)))
    (set-window-buffer l (get-buffer "*helpful function: car*"))
    (set-window-buffer r "*source.el*")
    (select-window l)
    (display-buffer "*B*")
    (ot/check "H6b unrelated buffer, help left: takes its pane"
              '("*B*" "*source.el*" side-by-side 2) (ot/state))))

(unless ot/helpful-p
  (dolist (name ot/helpful-checks)
    (ot/skip name)))

;; H7. The third entry of `onlytwo-in-place-modes', and the reason no Julia code
;;     binds anything for this any more: a doc buffer is the same question as a
;;     helpful one.  Single window, which is where the split used to happen.
;;     (No helpful needed: the stand-in carries the mode itself.)
(ot/one-window "*source.el*")
(let ((doc (get-buffer-create "*doc*")))
  (with-current-buffer doc (setq major-mode 'julia-help-mode))
  (set-window-buffer (selected-window) doc)
  (display-buffer "*B*")
  (ot/check "H7 doc buffer, single window: stays one" '("*B*" single 1) (ot/state)))

;;; 3. Clicking an item on the Doom dashboard

;; What a dashboard click runs is `find-file' on the file the item names ("Open
;; private configuration" is config.org, "Open my org" is my.org), so unlike the
;; helpful cases there is no door to stand in for: the file and the rule are the
;; whole story, and what the click adds -- `+dashboard/push-button', reached by
;; the remap in `+dashboard-mode-map' -- only decides that `find-file' is what
;; runs.  The real dashboard needs Doom (the module, its icons,
;; `doom-fallback-buffer'), so these drive a stand-in buffer in
;; `+dashboard-mode', which is a real `define-derived-mode' from `special-mode'
;; (doom+/modules/ui/dashboard/config.el), so `derived-mode-p' answers about it
;; the way it will in a live session.

(defun ot/dash-window (buf)
  "A sole window showing BUF, standing in for the dashboard."
  (ot/one-window buf)
  (with-current-buffer buf (setq-local major-mode '+dashboard-mode))
  buf)

(defun ot/dash-two-windows (other)
  "Two windows: the dashboard on the LEFT, selected, OTHER on the right."
  (ot/two-windows "*dash*" other)
  (with-current-buffer "*dash*" (setq-local major-mode '+dashboard-mode)))

;; D1. The complaint: a click on a dashboard that fills the frame. The file
;;     takes the window whole -- no split, and no dashboard left beside it.
(ot/dash-window "*dash*")
(find-file "helpful.el")
(ot/check "D1 click on a lone dashboard" '("helpful.el" single 1) (ot/state))

;; D2. With a second pane open, the dashboard's own pane takes the target and
;;     the pane beside it is left alone.
(ot/dash-two-windows "*source.el*")
(find-file "helpful.el")
(ot/check "D2 second pane open: in place"
          '("helpful.el" "*source.el*" side-by-side 2) (ot/state))

;; D3. A target that is already on screen in the other pane is reused, not
;;     duplicated, and not moved.
(ot/dash-two-windows "*B*")
(pop-to-buffer "*B*")
(ot/check "D3 target already visible: reused"
          '("*dash*" "*B*" side-by-side 2) (ot/state))

;; D4. The accepted cost in its dashboard form: the dashboard is normally the
;;     whole frame, so a buffer arriving from elsewhere takes it. Same answer as
;;     D1, from the same rule.
(ot/dash-window "*dash*")
(display-buffer "*B*")
(ot/check "D4 unrelated buffer, dashboard selected"
          '("*B*" single 1) (ot/state))

;;; 4. Whole-frame buffers

;; 9. Rule 5: a buffer whose major mode is in `onlytwo-full-frame-modes' takes
;;    the frame -- and quitting it puts back the layout it displaced.  Nothing
;;    in Emacs restores that split: `display-buffer-full-frame' saves nothing,
;;    and no branch of `quit-restore-window' calls `set-window-configuration'.
;;    So the action stores the configuration on the new window, and an `:around'
;;    advice on `quit-window' restores it.  Both halves are exercised here, and
;;    neither was before this case existed: deleting the advice left every other
;;    case green.
(ot/two-windows "*A*" "*C*")
(ot/check "9  setup: two panes" '("*A*" "*C*" side-by-side 2) (ot/state))
(with-current-buffer (get-buffer-create "*dired*")
  (setq major-mode 'dired-mode))
(display-buffer "*dired*")
(ot/check "9b whole-frame mode takes the frame" '("*dired*" single 1) (ot/state))
(quit-window)
(ot/check "9c quitting it puts the layout back" '("*A*" "*C*" side-by-side 2) (ot/state))

;;; Verdict

(princ (format "\n%s: %d passed, %d failed, %d skipped\n"
               (if (zerop ot/test-failures) "ALL PASS" "FAILED")
               ot/passes ot/test-failures ot/skips))
(when (> ot/skips 0)
  (princ (format "SKIPPED (%d, the real helpful package is not installed):\n"
                 ot/skips))
  (dolist (name (nreverse ot/skipped-names))
    (princ (format "  %s\n" name))))
(kill-emacs (if (zerop ot/test-failures) 0 1))
