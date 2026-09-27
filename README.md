# onlytwo.el

Never more than two windows — and the pane you asked from is the one that
answers.

`onlytwo-mode` is a policy for `display-buffer`. It decides **where** a buffer
goes, so that a frame never grows a third window, a newcomer lands where you
would look for it, and the layouts you build stay where you put them.

```
before                       after: the doc takes the pane beside you
+-------+-------+            +-------+-------+
| solve | CLAUDE|            | solve | *julia|
|  .jl  |       |            |  .jl  | help* |
|       |       |            |       |       |
+-------+-------+            +-------+-------+

                           ... and q gives the pane back to CLAUDE
```

It grew out of one configuration's answer to a question that comes up daily —
*why is this buffer there?* — and was extracted once the answers had stopped
moving. The rules below are the whole of it; everything else is consequences.

## The rules

The numbers are the design record's; 8 and 10 were dropped on the way and are
not gaps.

1. **A newcomer takes the pane on the right of the selected window**, or the
   selected window itself when the frame has no pane to its right.
2. **Never a third window.** Two panes, or one buffer filling the frame.
3. **No pane has privileges.** A pane is taken even when it is dedicated to its
   buffer — the dedication is cleared first. So a terminal in the right pane is
   displaced by documentation, and comes back when you are done, without either
   one being a special case of the other.
4. **Reading is not working.** What you ask for from documentation — or from the
   Doom dashboard — takes the window you asked *from*, not the one beside it.
   Following a link in a help buffer replaces the help, as it should.
5. **Whole-frame buffers exist.** The modes in `onlytwo-full-frame-modes` take
   the frame, and quitting one puts back the layout it displaced.
6. **Side windows are not panes.** Anything Emacs places on a frame edge
   (`window-side' non-nil: treemacs, pdf-tools' outline) is never taken, and
   never counted — counted, a frame edge would make a free pane look taken.
7. **Never stack.** A pane with no neighbour is split side by side whenever
   Emacs can split it at all, and reused when it cannot.
8. **A window moves the cursor only when your own command opened it.** A job
   finishing, or a process writing, changes what is on screen but never yanks
   the cursor out of what you are typing.

## Why the policy is the base action, and not an entry in `display-buffer-alist`

This is the one structural decision that everything else leans on. Emacs tries
its display actions in a fixed order: the overriding action, the first matching
`display-buffer-alist` entry, the buffer's special action, **the ACTION the
caller passed**, then `display-buffer-base-action`, then the fallback.

An alist entry therefore outranks even a caller that says "the same window,
please" — which is how you end up unable to open a file in the window you are
already in, and why a policy that lives there needs an escape hatch per caller.
Living at the base action instead means the policy is consulted only when
nothing else claimed the buffer: an explicit wish from a caller still wins, and
ordinary placement is still yours.

`onlytwo-mode` saves the base action you had and restores it when you turn the
mode off.

## Why rule 8's discriminator is a flag, not `called-interactively-p`

Rule 8 is easy to state and was hard to implement, and the two obvious answers
are both wrong:

- **`called-interactively-p`** answers for the function whose *body* makes the
  call. `display-buffer` reaches the base action through a plain `funcall`, so
  inside this chain it is `nil` however the display was started — including when
  you typed the command. A policy checking it looks correct and silently never
  focuses anything.
- **`this-command` and `real-this-command`** are still set *after* a command
  ends, so an idle timer firing in the gap looks exactly like you.

What works is a flag kept by `pre-command-hook` and `post-command-hook`: on for
exactly as long as a command runs, and `nil` in a timer or a process filter. The
positive half is then gated by `onlytwo-focus-on-display`, and both halves by a
guard against the active minibuffer, so a completion window shown while you are
choosing a command never takes the cursor.

## Why quitting a full-frame buffer needs an advice

`display-buffer-full-frame` takes the frame but saves nothing, and nothing in
Emacs puts the panes back: `quit-restore-window` can only delete a window or show
another buffer *in the same window* — it never calls `set-window-configuration` —
and `delete-other-windows` leaves no window behind to restore a split into.
Measured on all of `ibuffer-mode`, `dired-mode` and `elfeed-search-mode`, whose
`q` is `quit-window` inherited from `special-mode-map`.

So this package supplies the action that captures the configuration before the
frame is taken, and an `:around` advice on `quit-window` that restores it after
the quit runs. It is `:around` and not `:before` for a reason worth knowing: the
configuration has to be *read* while the window still exists, and *restored* only
after the original has finished, or the restored layout's own window would be the
one quit next.

## Requirements

Emacs 29.1 or newer — `display-buffer-full-frame`, and `major-mode` conditions in
`display-buffer-alist`. Developed and measured on 30.2.

## Install

```elisp
(add-to-list 'load-path "/path/to/onlytwo.el/")
(require 'onlytwo)
(onlytwo-mode +1)
```

## Options

```elisp
;; Buffers read rather than worked in: what you ask for from one takes its window (rule 4).
(setq onlytwo-in-place-modes '(helpful-mode julia-help-mode +dashboard-mode))

;; Buffers that take the whole frame, and give the layout back when you quit (rule 5).
(setq onlytwo-full-frame-modes '(dired-mode ibuffer-mode elfeed-search-mode))

;; Whether a window opened by your own command takes the cursor (rule 8).
(setq onlytwo-focus-on-display t)
```

Both mode lists are matched with `derived-mode-p`, so a package's variant of
`dired-mode` is covered by the same entry, and a mode that is not loaded yet is
harmless — it simply never matches.

If you use [`zoom`](https://github.com/cyrus-and/zoom) for proportions, the two
compose well: zoom enlarges whichever window you are in, and adding the same
modes to `zoom-ignored-major-modes` (as *symbols* — `derived-mode-p` silently
answers `nil` for strings) leaves a doc balanced at half rather than enlarged.

## What it does not do

- No third window, ever, and no stacking: those are the point, not oversights.
- No side windows: they are excluded on purpose (rule 6), because a frame edge is
  not a pane and Emacs' own `other-window` will not enter one.
- No kill-buffer wrapper. A dedicated window can make a buffer unkillable when
  something else advises `kill-current-buffer` — Doom does exactly that — but
  that is a bug in the thing doing the advising, not a window-placement problem,
  so it belongs in the configuration that hits it, not here.

## Running the tests

```
emacs -Q --batch -l onlytwo-test.el ; echo "exit=$?"
```

Exit code is the verdict: 0 = everything that ran passed; non-zero means a case
failed, and never anything else. The cases drive `display-buffer` against the
policy in bare Emacs and cover the placement rules, the dedicated pane, the side
window, the split floor, the reading exception and the full-frame restore. They
are geometry only — which window shows which buffer, and how many there are —
because that is what the policy decides.

Twelve of them run against the **real `helpful`** package, to prove the reading
exception works with a mode this package does not own. Where `helpful` cannot be
loaded — which is every machine without Doom, since those cases otherwise read it
out of Doom's build directory — the twelve are **skipped by name**, not counted as
passes, and the summary says so:

```
ALL PASS: 27 passed, 0 failed, 12 skipped
SKIPPED (12, the real helpful package is not installed):
  H1 open help: policy, splits right
  ...
```

## Measured, not assumed

Every claim above that could have been wrong was measured, and the measurements
are in the comments beside the code that depends on them:

- A pane needs 20 columns to split side by side (`window-min-width' twice);
  below that `split-window-right` **signals** rather than returning `nil`, which
  is why the split is wrapped in `ignore-errors`.
- `window-in-direction 'right` will hand you a *side* window, which is how a free
  pane comes to look taken.
- `called-interactively-p` is `nil` at any depth below the command loop inside a
  display chain — the finding that rule 8's section above is built on.
- `display-buffer-full-frame` takes the frame and saves nothing, and no branch of
  `quit-restore-window` restores a deleted split.

## Licence

MIT — see [LICENSE](LICENSE).
