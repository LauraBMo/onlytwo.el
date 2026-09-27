#!/bin/sh
# mutation-check.sh --- do the tests actually bite?
#
# The suite passing proves nothing unless it would FAIL on the bugs it exists to
# catch.  Each mutant below breaks one of the traps the package was written
# around -- a side window mistaken for a pane, the reading exception, the
# caller's own wish, splitting where a pane should be reused, the reuse of a
# buffer already on screen, rule 8's discriminator in BOTH directions, and the
# advice that gives a full-frame layout back -- and the suite must go red,
# naming a case, for each.  It refuses to run at all while the unmutated suite
# is red, because then every mutant looks caught.
#
# A mutant is the package with one substitution, in a throwaway directory beside
# a copy of the suite (the test file puts its own directory on `load-path').
#
# Run:  sh mutation-check.sh     Exit code is the verdict: 0 = all caught.

set -u

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

caught=0
missed=0

# The baseline first.  A suite that is already red makes every mutant look
# caught -- and the failure lines then name whichever case is broken rather than
# the mutation, which reads as a clean sweep.
base="$work/baseline"
mkdir -p "$base"
cp "$here/onlytwo.el" "$here/onlytwo-test.el" "$base/"
if ! emacs -Q --batch -L "$base" -l "$base/onlytwo-test.el" > "$base/out" 2>&1; then
    echo "BASELINE IS RED -- the unmutated suite fails, so nothing below would mean anything:"
    grep '^FAIL  ' "$base/out" | sed 's/^/  /'
    exit 2
fi

mutant () {
    name=$1
    expr=$2
    dir="$work/$name"
    mkdir -p "$dir"

    sed "$expr" "$here/onlytwo.el" > "$dir/onlytwo.el"
    cp "$here/onlytwo-test.el" "$dir/"

    if cmp -s "$here/onlytwo.el" "$dir/onlytwo.el"; then
        echo "SKIP    $name -- the substitution did not apply, so nothing was tested"
        return
    fi

    if emacs -Q --batch -L "$dir" -l "$dir/onlytwo-test.el" > "$dir/out" 2>&1; then
        echo "MISS    $name -- the suite PASSED on a mutated package"
        missed=$((missed + 1))
    else
        # `FAIL  ' (two spaces) is a case line; the summary line is `FAILED:'.
        failed=$(grep '^FAIL  ' "$dir/out" | sed 's/^FAIL  //; s/ *expected.*//' | sort -u | tr '\n' '; ')
        if [ -z "$failed" ]; then
            # A run that died without naming a CASE proves nothing: a mutant
            # that unbalances the file makes the suite fail to load, which looks
            # like a catch and is not.
            echo "SUSPECT $name -- failed without naming a case; a broken file looks like a catch"
            missed=$((missed + 1))
        else
            echo "CAUGHT  $name -- by: $failed"
            caught=$((caught + 1))
        fi
    fi
}

# Rule 6 from both sides: `window-in-direction' happily answers with a SIDE
# window, and a side window counted as a pane makes a free pane look taken.
mutant side-window-guard  "s/(and (memq window others) window)/window/"
mutant side-window-filter "s/(seq-remove #'onlytwo--side-window-p/(seq-remove #'ignore/"

# Rule 4 from both sides: the mode list that decides what is being read, and the
# branch that acts on it.  The list keeps its own paren, hence FOUR closing
# parens; written with three it drops the form's last one and the mutant dies at
# load, which the SUSPECT branch reports instead of reading it as a catch.
mutant in-place-modes     "s/onlytwo-in-place-modes)))/'(not-a-mode))))/"
mutant in-place-branch    "s/^         ((onlytwo--in-place-window-p)$/         (nil/"

# Rule 1's caller exception: a caller asking not to get this window back.
mutant inhibit-same-window "s/(and (cdr (assq 'inhibit-same-window alist)) spare)/nil/"

# Rule 7's other half: a pane with no neighbour is taken over, not split --
# split it and a third window appears.
mutant no-neighbour-branch "s/^         (others$/         (nil/"

# A buffer already on screen is reused, not duplicated.  Cases 4, 8 and D3 rest
# on it.
mutant reuse-removed      "s/(display-buffer-reuse-window buffer alist)/nil/"

# Rule 5: the advice that puts back the layout a full-frame buffer displaced.
mutant quit-advice        "s/(advice-add 'quit-window :around #'onlytwo--quit-window-restore-a)/(ignore)/"

# Rule 8 in both directions: the cursor taken when it should not be, and never
# taken when it should.  Either one ALONE is passed by a policy that ignores the
# discriminator altogether, which is how both holes went unnoticed.
mutant focus-always       "s/^             onlytwo--in-command)/             t)/"
mutant never-focuses      "s/^             onlytwo--in-command)/             nil)/"

# NOT mutants, deliberately:
#
# - `onlytwo--place-in-pane' clears a dedicated window's dedication, but measured
#   on 30.2 `window--display-buffer' clears it anyway, so deleting that line
#   leaves every case green.  The line is kept for 29.1, where it is unmeasured;
#   see the comment beside it.
# - Removing `ignore-errors' from `onlytwo--split-side-by-side' (rule 7's floor)
#   makes the suite DIE on case 6c rather than fail it, which this script can
#   only report as SUSPECT.  The trap is real -- cases 6b and 6c exist for it --
#   but a mutant that cannot name a case is not evidence.

echo
echo "caught $caught, missed $missed"
[ "$missed" -eq 0 ]
