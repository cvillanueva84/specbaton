#!/usr/bin/env bash
# Builds a change's diff, grouped by repo, for the reviewer agent's review.
#
# Usage:
#   change_diff.sh <base> <repo>[@<ref>] [<repo>[@<ref>]...]
#   base: the branch or ref to compare against, for example origin/main
#   repo: the repo's folder, relative to the workspace root (in a monorepo or a single repo: .)
#   ref:  the pull request's branch, for example origin/feat/ABC-123-name
#
# Without @<ref>, for each repo it includes: the current branch's commits since <base> (base...HEAD), the uncommitted
# changes, and the content of new untracked files. With @<ref>, only that branch's commits (base...ref): this reviews
# a pull request without switching the repo's branch.
#
# The output goes to another agent, so secrets are masked as <redacted>: .env-style variables whose name holds KEY,
# TOKEN, SECRET or PASSWORD, PEM keys, npm's _authToken, JSON secret fields and the known key prefixes (Stripe,
# GitHub, GitLab, Slack, AWS, Google). Code that only names the variable is left alone. Still grep the output before
# sending it.
#
# Optional variables:
#   WORKSPACE_ROOT  the workspace root (default: the project that holds .claude/specbaton.json, else the current dir)
set -uo pipefail
mask_secrets() {
  perl -pe '
    if ($pem) {
      $pem = 0 if /-----END [A-Z ]*PRIVATE KEY-----/;
      s/^([+\- ]?).*$/$1<redacted>/;
      next;
    }
    s/-----BEGIN ([A-Z ]*)PRIVATE KEY-----.*?-----END \1PRIVATE KEY-----/<redacted>/g;
    if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/) {
      $pem = 1;
      s/-----BEGIN [A-Z ]*PRIVATE KEY-----.*$/<redacted>/;
      next;
    }
    s/\b([A-Z][A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*=)\S+/$1<redacted>/g;
    s/(_authToken=)\S+/$1<redacted>/g;
    s/("(?:password|secret|apiKey|api_key|privateKey|private_key|token|accessToken|clientSecret)"\s*:\s*")[^"]{8,}"/$1<redacted>"/gi;
    s/\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{8,}/<redacted>/g;
    s/\bwhsec_[A-Za-z0-9]{8,}/<redacted>/g;
    s/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/<redacted>/g;
    s/\bgithub_pat_[A-Za-z0-9_]{20,}/<redacted>/g;
    s/\bglpat-[A-Za-z0-9_-]{20,}/<redacted>/g;
    s/\bxox[abposr]-[A-Za-z0-9-]{10,}/<redacted>/g;
    s/\bAKIA[0-9A-Z]{16}\b/<redacted>/g;
    s/\bAIza[0-9A-Za-z_-]{30,}/<redacted>/g;
  '
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${WORKSPACE_ROOT:-$(python3 "$SCRIPT_DIR/reviewer_config.py" --key root 2>/dev/null)}"
ROOT="$(cd "${ROOT:-$PWD}" && pwd)"
BASE="${1:-}"
[ -n "$BASE" ] && [ $# -ge 2 ] || { echo "usage: $0 <base> <repo>[@<ref>] [<repo>[@<ref>]...]" >&2; exit 2; }
shift
cd "$ROOT" || exit 2

for arg in "$@"; do
  r="${arg%%@*}"
  r="${r%/}"; [ -n "$r" ] || r="."
  ref=""
  [ "$arg" != "${arg#*@}" ] && ref="${arg#*@}"
  if ! git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
    echo "### $r: not a git repo"; continue
  fi
  if [ -n "$ref" ]; then
    git -C "$r" rev-parse --verify -q "$ref^{commit}" >/dev/null || { echo "### $r: couldn't resolve $ref"; continue; }
    head="$ref"
    label="$ref"
  else
    head="HEAD"
    label="$(git -C "$r" branch --show-current)"
  fi
  echo "### Repo: $r · branch: ${label:-detached} · base: $BASE"
  echo
  echo "#### Commits since $BASE"
  git -C "$r" log --oneline "$BASE..$head" 2>/dev/null || echo "(couldn't resolve $BASE in $r)"
  echo
  echo '```diff'
  git -C "$r" diff "$BASE...$head" 2>/dev/null
  if [ -z "$ref" ]; then
    git -C "$r" diff HEAD 2>/dev/null
    git -C "$r" ls-files --others --exclude-standard | while read -r f; do
      git -C "$r" diff --no-index /dev/null "$f" 2>/dev/null
    done
  fi
  echo '```'
  echo
done | mask_secrets
