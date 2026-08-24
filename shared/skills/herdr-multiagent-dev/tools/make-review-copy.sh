#!/usr/bin/env bash
# Build the disposable copy a reviewer works in.
#
# The copy IS the reviewer's working directory, so "do not touch the real repo"
# is structural rather than a rule the reviewer has to follow. It is committed
# once so the reviewer can inject a defect, run the tests, and restore with
# `git checkout -- .` -- without a restore path the reviewer tries to stash a
# backup outside its sandbox and stalls.
#
# usage: [REPO=<path>] [EXTRA_FROM_GIT="<ref>:<path> ..."] \
#          make-review-copy.sh <copy-dir> <PLAN.md> [files-under-review...]
#
#   files      paths relative to the repo, taken from the WORKING TREE, so
#              uncommitted builder output (untracked files included) is reviewed
#   EXTRA_FROM_GIT
#              files to bundle from other refs, saved as <copy>/extra/<basename>.txt
#              (.txt so the copy's own typecheck ignores them). Use this whenever
#              the reviewer needs a file the working tree does not have -- a
#              headless reviewer confined by --dir cannot read outside the copy,
#              and it stalls rather than adapting when the read is refused
set -euo pipefail
REPO="${REPO:-$(git rev-parse --show-toplevel)}"
C="$1"; PLAN="$2"; shift 2
mkdir -p "$C"
(cd "$REPO" && git archive HEAD) | tar -x -C "$C"
[ -d "$REPO/node_modules" ] && ln -sfn "$REPO/node_modules" "$C/node_modules"
cp "$PLAN" "$C/PLAN.md"
for f in "$@"; do mkdir -p "$C/$(dirname "$f")"; cp "$REPO/$f" "$C/$f"; done
if [ $# -gt 0 ]; then (cd "$REPO" && git diff HEAD -- "$@") > "$C/REVIEW-DIFF.patch"; fi
for spec in ${EXTRA_FROM_GIT:-}; do
  mkdir -p "$C/extra"
  (cd "$REPO" && git show "$spec") > "$C/extra/$(basename "${spec#*:}").txt"
done
cd "$C" && git init -q && git add -A &&
  git -c user.name=review -c user.email=review@example.com \
      commit -qm "repo at HEAD + work under review + PLAN.md" &&
  git log --oneline | head -1
