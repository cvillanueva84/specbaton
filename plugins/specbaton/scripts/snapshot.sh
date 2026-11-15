#!/usr/bin/env bash
# Prints a git tree of a repo's working tree, so /specbaton:implement can diff exactly what each unit changed while
# nothing is committed yet.
#
# Usage:
#   snapshot.sh <repo>
#
# Prints one line, "<tree> <head> <branch>": <tree> holds the tracked files and the untracked ones git doesn't ignore,
# as they are on disk, <head> is HEAD's commit (none in a repo without commits) and <branch> is the checked-out branch
# (detached when there's none), so a branch switched at the same commit still shows. Two snapshots compare with
#   git -C <repo> diff <tree before> <tree after>
# It works through a temporary index (GIT_INDEX_FILE), so it never changes the repo's index, HEAD, branch or files. It
# only adds objects to the repo's object store, which git's garbage collection drops once nothing refers to them.
#
# Exit codes: 0 ok, 1 git failed (its message follows specbaton's on stderr), 2 wrong usage or <repo> isn't a git
# work tree.
set -uo pipefail
repo="${1:-}"
if [ -z "$repo" ] || [ "$(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  echo "specbaton: snapshot.sh <repo>: '${repo}' isn't a git work tree" >&2
  exit 2
fi
tmp="$(mktemp)" || exit 1
err="$(mktemp)" || exit 1
trap 'rm -f "$tmp" "$tmp.lock" "$err"' EXIT
# Seed the temporary index with the real one, so git add only rehashes what changed. The copy keeps the index's
# timestamp (-p): git rechecks the content of files written in the same second as the index ("racy git"), and a copy
# with a new timestamp would make it trust a same-size edit made in that second and miss it. Without a real index (a
# repo with no commits) it starts empty: git rejects an empty file as an index, so the file goes.
index="$(git -C "$repo" rev-parse --git-path index)"
case "$index" in /*) ;; *) index="$repo/$index" ;; esac
if [ -f "$index" ]; then cp -p "$index" "$tmp"; else rm -f "$tmp"; fi
if ! tree="$(GIT_INDEX_FILE="$tmp" git -C "$repo" add -A 2>"$err" && GIT_INDEX_FILE="$tmp" git -C "$repo" write-tree 2>>"$err")"; then
  echo "specbaton: couldn't take a snapshot of '$repo'. git said:" >&2
  cat "$err" >&2
  exit 1
fi
head="$(git -C "$repo" rev-parse -q --verify HEAD 2>/dev/null)" || head="none"
branch="$(git -C "$repo" symbolic-ref -q --short HEAD 2>/dev/null)" || branch="detached"
echo "$tree $head $branch"
