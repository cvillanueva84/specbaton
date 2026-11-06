#!/usr/bin/env bash
# Collects the human reviewers' comments on a pull request, to compare them with the reviewer agent's review (the
# review skill's learning step).
#
# Usage:
#   pr_human_comments.sh <repo> <pull request number> [since]
#   repo:  the repo's folder, relative to the workspace root (in a monorepo or a single repo: .)
#   since: an ISO 8601 date in UTC (for example 2026-11-05T14:00:52Z). Only later comments are included; without it,
#          all of them.
#
# Leaves out the pull request's author (our replies) and bots (any user of type Bot and the logins in PR_BOTS).
# Includes inline comments, review bodies and the pull request's general comments, in date order, with their id and,
# for a reply, the id of the comment it answers. The last line is "last: <date>", the next run's `since` (empty when
# there were no new comments).
#
# Needs gh (signed in) and jq. The repo's GitHub owner and name come from the local repo's remote.
#
# Optional variables:
#   WORKSPACE_ROOT  the workspace root (default: the project that holds .claude/specbaton.json, else the current dir)
#   PR_BOTS         a regular expression of logins to ignore
set -euo pipefail
REPO="${1:-}"; PR="${2:-}"; SINCE="${3:-}"
if [ -z "$REPO" ] || [ -z "$PR" ]; then
  echo "usage: $0 <repo> <pull request number> [since]" >&2
  exit 2
fi
command -v gh >/dev/null && command -v jq >/dev/null || { echo "gh or jq is missing." >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${WORKSPACE_ROOT:-$(python3 "$SCRIPT_DIR/reviewer_config.py" --key root 2>/dev/null || true)}"
ROOT="$(cd "${ROOT:-$PWD}" && pwd)"
BOTS="${PR_BOTS:-\\[bot\\]|github-actions|dependabot|renovate|snyk|sonar|codecov|jenkins|copilot}"
SLUG="$(cd "$ROOT/$REPO" && gh repo view --json nameWithOwner --jq .nameWithOwner)"
API="repos/$SLUG"
AUTHOR="$(gh api "$API/pulls/$PR" --jq .user.login)"

{
  gh api "$API/pulls/$PR/comments" --paginate \
    --jq '.[] | {kind: "inline", login: .user.login, type: .user.type, at: .created_at, path, line: (.line // .original_line), id, reply_to: .in_reply_to_id, body}'
  gh api "$API/pulls/$PR/reviews" --paginate \
    --jq '.[] | select(.body != "") | {kind: ("review " + .state), login: .user.login, type: .user.type, at: .submitted_at, path: null, line: null, id, reply_to: null, body}'
  gh api "$API/issues/$PR/comments" --paginate \
    --jq '.[] | {kind: "general", login: .user.login, type: .user.type, at: .created_at, path: null, line: null, id, reply_to: null, body}'
} | jq -rs --arg author "$AUTHOR" --arg since "$SINCE" --arg bots "$BOTS" '
  map(select(
    .login != $author and .type != "Bot"
    and (.login | test($bots; "i") | not)
    and .at > $since
  )) | sort_by(.at)
  | (.[] | "## \(.kind) · \(.login) · \(.at)" + (if .path then " · \(.path):\(.line)" else "" end)
           + " · id=\(.id)" + (if .reply_to then " · replies to \(.reply_to)" else "" end)
           + "\n\n\(.body)\n"),
    "last: \(last.at // "")"
'
