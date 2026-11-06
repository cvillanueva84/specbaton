#!/usr/bin/env bash
# Runs the reviewer agent (Cursor, Antigravity, Claude with another model, or any CLI) non-interactively and
# read-only, and checks that it changed nothing in the workspace.
#
# Usage:
#   reviewer_readonly.sh <prompt file> <output file> [model]
#
# Writes the agent's final answer to <output file> (without the progress notes it writes between reads) and its
# conversation id, token usage and duration to <output file>.meta.json. When the agent fails, the .meta.json still
# holds the conversation id, so the conversation can be resumed. Writes nothing inside the workspace: <output file>
# must live outside it (use mktemp).
#
# Exit codes:
#   0  ok
#   2  wrong usage or settings
#   3  the CLI isn't installed, isn't signed in, or doesn't trust the workspace
#   4  the agent changed files (the affected repos and files are listed; nothing is reverted)
#   5  the agent failed, hit its usage limit, tried something it was denied and didn't answer, returned an empty
#      answer, or ended without a result
#
# Settings: the "reviewer" section of <project>/.claude/specbaton.json (see reviewer_config.py). Environment
# variables override them:
#   SPECBATON_CLI        cursor | agy | claude | custom
#   SPECBATON_BIN        path to the CLI (default: cursor-agent or agent; agy; claude)
#   SPECBATON_MODEL      model when no third argument is given
#   SPECBATON_ROOT       the workspace root (default: the project that holds .claude/specbaton.json)
#   SPECBATON_EXCLUDE    root paths, space-separated, that write on their own and don't count as changes
#                        (default: .obsidian; .DS_Store files never count)
#   SPECBATON_RUNS_DIR   where the live log goes (default ~/.specbaton-runs/<root name>). Outside the workspace,
#                        because the snapshot would see it.
#   SPECBATON_EFFORT     agy only: low | medium | high | xhigh | max
#   SPECBATON_RESUME     a previous conversation's id: continues it (validation rounds)
#
# How each adapter stays read-only (checked 2026-11 against cursor-agent, agy 1.5.1 and Claude Code 2.1):
#   cursor  --mode=ask and never --force: without --force, Cursor applies no changes in -p mode. --mode=plan works
#           but prints no answer with -p.
#   agy     session-only --settings (never touches ~/.gemini) with deny rules for commands, writes, MCP and URLs.
#           With a deny rule agy tells the tool "Permission denied" and goes on; without one the permission is
#           requested, headless mode denies it, and agy drops its whole answer. No --mode plan (it depends on
#           slash-command expansion and writes its own plan.md) and no --sandbox (it doesn't stop writes through
#           commands). A preamble names the allowed tools: without it, agy calls subagents that take minutes and
#           duplicate the answer.
#   claude  --tools "Read,Grep,Glob" plus --disallowedTools "mcp__*" (MCP servers that connect on their own, such as
#           Claude in Chrome, survive --strict-mcp-config), --setting-sources "" so the project's and the user's
#           hooks and plugins don't run in the reviewer's session, and SPECBATON_CHILD=1 for specbaton's own hooks.
#           --bare would skip them too, but it doesn't read a subscription's sign-in.
#   custom  whatever the command in the settings does; only the snapshot below guards it.
#   all     A git snapshot (status and diff) of the root, of each nested repo and of an external memory layer, before
#           and after, plus a search for files changed during the run, which covers folders git ignores. This is the
#           real guarantee: if anything changed, the script exits with 4.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="${1:-}"
OUT_FILE="${2:-}"

if [ -z "$PROMPT_FILE" ] || [ -z "$OUT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  echo "usage: $0 <prompt file> <output file> [model]" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "python3 is missing (the reviewer's scripts need it)." >&2; exit 2; }

cfg() { python3 "$SCRIPT_DIR/reviewer_config.py" "${SPECBATON_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}" --key "$1" 2>/dev/null; }
ROOT="${SPECBATON_ROOT:-$(cfg root)}"
[ -n "$ROOT" ] || { echo "No .claude/specbaton.json found from $PWD. Run /specbaton-reviewer:setup first." >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)" || exit 2
CLI="${SPECBATON_CLI:-$(cfg cli)}"
MODEL="${3:-${SPECBATON_MODEL:-}}"
EXCLUDE="${SPECBATON_EXCLUDE:-$(cfg exclude)}"
EFFORT="${SPECBATON_EFFORT:-$(cfg effort)}"
CURSOR_MODE="$(cfg cursor_mode)"
MEM="$(cfg memory_dir_abs)"
[ "$(cfg memory_outside_root)" = "true" ] && [ -d "$MEM" ] || MEM=""

case "$CLI" in
  cursor|agy|claude|custom) ;;
  *) echo "Set reviewer.cli to cursor, agy, claude or custom in .claude/specbaton.json (or SPECBATON_CLI)." >&2; exit 2 ;;
esac
case "$OUT_FILE" in
  "$ROOT"/*) echo "The output file must live outside the workspace (use mktemp): $OUT_FILE" >&2; exit 2 ;;
esac
cd "$ROOT" || exit 2

# 1. Find the CLI.
BIN="${SPECBATON_BIN:-$(cfg bin)}"
if [ -z "$BIN" ]; then
  case "$CLI" in
    cursor)
      if command -v cursor-agent >/dev/null 2>&1; then BIN="cursor-agent"
      elif command -v agent >/dev/null 2>&1 && agent --help 2>&1 | grep -qi cursor; then BIN="agent"; fi ;;
    agy) command -v agy >/dev/null 2>&1 && BIN="agy" ;;
    claude) command -v claude >/dev/null 2>&1 && BIN="claude" ;;
    custom) ;;
  esac
fi
if [ "$CLI" != custom ] && { [ -z "$BIN" ] || ! command -v "$BIN" >/dev/null 2>&1; }; then
  case "$CLI" in
    cursor) echo "Cursor's CLI (cursor-agent) isn't installed. Install it, then run: cursor-agent login" >&2 ;;
    agy) echo "Antigravity's CLI (agy) isn't installed. Install it and sign in by running agy once." >&2 ;;
    claude) echo "Claude Code's CLI (claude) isn't on the PATH." >&2 ;;
  esac
  exit 3
fi

# 2. Build the command.
PROMPT="$(cat "$PROMPT_FILE")"
RESUME="${SPECBATON_RESUME:-}"
args=()
case "$CLI" in
  cursor)
    HELP="$("$BIN" --help 2>&1 || true)"
    args=(-p --output-format stream-json)
    printf '%s' "$HELP" | grep -q -- "--stream-partial-output" && args+=(--stream-partial-output)
    printf '%s' "$HELP" | grep -q -- "--mode" && args+=("--mode=${CURSOR_MODE:-ask}")
    [ -n "$MODEL" ] && args+=(--model "$MODEL")
    [ -n "$RESUME" ] && args+=("--resume=$RESUME")
    args+=("$PROMPT")
    cmd=("$BIN" "${args[@]}") ;;
  agy)
    HELP="$("$BIN" --help 2>&1 || true)"
    SETTINGS='{"permissions":{"deny":["command(*)","write_file(*)","mcp(*)","read_url(*)","execute_url(*)"]}}'
    PREAMBLE="Tools: use only the ones that read files, search files and list folders. Don't run terminal commands, don't write or edit files, don't open URLs and don't call subagents: those actions are denied in this session. Write your final answer once."
    args=(-p "$PREAMBLE"$'\n\n'"$PROMPT" --output-format stream-json --settings "$SETTINGS")
    printf '%s' "$HELP" | grep -q -- "--disable-slash-commands" && args+=(--disable-slash-commands)
    [ -n "$MODEL" ] && args+=(--model "$MODEL")
    [ -n "$EFFORT" ] && args+=(--effort "$EFFORT")
    [ -n "$RESUME" ] && args+=(--conversation "$RESUME")
    # Layer B: the memory lives outside the root; without --add-dir, reading it asks for a permission and ends the run.
    [ -n "$MEM" ] && args+=(--add-dir "$MEM")
    cmd=("$BIN" "${args[@]}") ;;
  claude)
    args=(-p "$PROMPT" --output-format stream-json --verbose
      --tools "Read,Grep,Glob" --disallowedTools "mcp__*"
      --setting-sources "" --strict-mcp-config --disable-slash-commands)
    [ -n "$MODEL" ] && args+=(--model "$MODEL")
    [ -n "$RESUME" ] && args+=(--resume "$RESUME")
    [ -n "$MEM" ] && args+=(--add-dir "$MEM")
    cmd=(env SPECBATON_CHILD=1 "$BIN" "${args[@]}") ;;
  custom)
    cmd=()
    while IFS= read -r -d '' a; do cmd+=("$a"); done < <(python3 "$SCRIPT_DIR/reviewer_config.py" "$ROOT" --custom-args "$MODEL" "$RESUME" "$PROMPT_FILE")
    [ "${#cmd[@]}" -gt 0 ] || exit 2
    [ -z "$BIN" ] || cmd[0]="$BIN"
    command -v "${cmd[0]}" >/dev/null 2>&1 || { echo "The custom reviewer's command (${cmd[0]}) isn't on the PATH." >&2; exit 3; } ;;
esac

# 3. Live log, outside the workspace.
RUNS_DIR="${SPECBATON_RUNS_DIR:-$(cfg runs_dir)}"
RUNS_DIR="${RUNS_DIR:-$HOME/.specbaton-runs/$(basename "$ROOT")}"
mkdir -p "$RUNS_DIR"
NAME="$(basename "$OUT_FILE")"; NAME="${NAME//[^A-Za-z0-9._-]/_}"
LOG="$RUNS_DIR/$(date +%Y%m%d-%H%M%S)-$NAME.log"
echo "Live progress: tail -f \"$LOG\""

# 4. Snapshot of the root, each nested repo and an external memory layer (status + diff). The root's snapshot uses
#    --ignored: when its .gitignore is an allowlist that ignores /*, a new file at the root wouldn't show without it.
#    The paths in EXCLUDE (default .obsidian/, which Obsidian writes while it's open) and Finder's .DS_Store don't count.
ROOT_PATHS=(-- . ':(exclude,glob)**/.DS_Store')
for x in $EXCLUDE; do ROOT_PATHS+=(":(exclude)$x"); done
repo_photo() { { git -C "$1" status --porcelain "${@:2}"; git -C "$1" diff "${@:2}"; } 2>/dev/null | cksum; }
snapshot() {
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    && printf 'root %s\n' "$(repo_photo "$ROOT" --ignored "${ROOT_PATHS[@]}")"
  for d in */; do
    [ -e "${d}.git" ] || continue
    printf '%s %s\n' "${d%/}" "$(repo_photo "$d" -- . ':(exclude,glob)**/.DS_Store')"
  done
  if [ -n "$MEM" ]; then
    printf 'memory %s\n' "$(repo_photo "$MEM" -- . ':(exclude).obsidian' ':(exclude,glob)**/.DS_Store')"
  fi
}
# Files created or changed after $1 (a reference file), at the root and in an external memory layer, ignored folders
# included (node_modules, graphify-out…). Skips .git and the EXCLUDE paths.
touched_since() {
  local prune=(-name .git)
  for x in $EXCLUDE; do prune+=(-o -path "./${x%/}"); done
  find . \( "${prune[@]}" \) -prune -o -type f -newer "$1" ! -name .DS_Store -print 2>/dev/null
  [ -n "$MEM" ] \
    && (cd "$MEM" && find . \( -name .git -o -path ./.obsidian \) -prune -o -type f -newer "$1" ! -name .DS_Store -print 2>/dev/null | sed 's|^\.|memory:|')
}

BEFORE="$(mktemp)"; AFTER="$(mktemp)"; ERR="$(mktemp)"; STAMP="$(mktemp)"
trap 'rm -f "$BEFORE" "$AFTER" "$ERR" "$STAMP"' EXIT
snapshot >"$BEFORE"
touch "$STAMP"

# 5. Run the agent and process its output.
export SPECBATON_CUSTOM_OUTPUT="$(cfg custom_output)" SPECBATON_CUSTOM_TEXT="$(cfg custom_text_field)" SPECBATON_CUSTOM_ID="$(cfg custom_id_field)"
"${cmd[@]}" </dev/null 2>"$ERR" \
  | python3 "$SCRIPT_DIR/reviewer_stream.py" "$CLI" "$OUT_FILE" "$LOG" "$OUT_FILE.meta.json"
RCS=("${PIPESTATUS[@]}")
RC=${RCS[0]}
STREAM_RC=${RCS[1]}

# 6. Check that nothing changed.
snapshot >"$AFTER"
TOUCHED="$(touched_since "$STAMP" | head -20)"
if ! diff -q "$BEFORE" "$AFTER" >/dev/null || [ -n "$TOUCHED" ]; then
  echo "The agent changed files." >&2
  if ! diff -q "$BEFORE" "$AFTER" >/dev/null; then
    echo "Repos with new changes:" >&2
    diff "$BEFORE" "$AFTER" | grep '^>' | awk '{print "  - " $2}' >&2
  fi
  [ -n "$TOUCHED" ] && { echo "Files changed during the run (up to 20):" >&2; printf '%s\n' "$TOUCHED" | sed 's/^/  - /' >&2; }
  echo "Nothing was reverted. Check git status and git diff in those repos." >&2
  echo "If another program wrote them (an editor, a dev server), add its folder to reviewer.exclude." >&2
  exit 4
fi

CONV="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("conversation_id") or "")' "$OUT_FILE.meta.json" 2>/dev/null)"
RESUME_HINT="To resume that conversation: SPECBATON_RESUME=$CONV"

if [ "$RC" -ne 0 ]; then
  if grep -qi -E "usage limit|quota|rate limit|resource.?exhausted" "$ERR" "$LOG" 2>/dev/null; then
    echo "The agent hit its usage limit with model ${MODEL:-default}. Switch models or wait." >&2
    [ -n "$CONV" ] && echo "$RESUME_HINT" >&2
    tail -5 "$ERR" >&2
    exit 5
  fi
  if grep -qi -E "log ?in|authenticat|unauthori|not signed|sign in" "$ERR"; then
    echo "The CLI isn't signed in. Run ${BIN:-it} once (or its login command) and sign in." >&2
    exit 3
  fi
  if grep -qi -E "workspace trust|trust (this|the) (folder|workspace)|untrusted" "$ERR"; then
    echo "The CLI doesn't trust the workspace. Run ${BIN:-it} once in $ROOT, accept, and exit." >&2
    exit 3
  fi
  echo "The agent exited with code $RC:" >&2
  [ -n "$CONV" ] && echo "$RESUME_HINT" >&2
  tail -20 "$ERR" >&2
  python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
if m.get("error"): print("Error:", m["error"])' "$OUT_FILE.meta.json" >&2 2>/dev/null
  exit 5
fi
if [ "$STREAM_RC" -ne 0 ]; then
  echo "The agent ended without a valid answer (see $LOG and $LOG.ndjson)." >&2
  python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
if m.get("denied_actions"): print("It was denied:", ", ".join(d.get("display_name") or d.get("action","?") for d in m["denied_actions"]))
if m.get("error"): print("Error:", m["error"])' "$OUT_FILE.meta.json" >&2 2>/dev/null
  [ -n "$CONV" ] && echo "$RESUME_HINT" >&2
  tail -20 "$ERR" >&2
  exit 5
fi
if [ ! -f "$OUT_FILE" ] || ! grep -q '[^[:space:]]' "$OUT_FILE"; then
  echo "The agent returned an empty answer (or only whitespace)." >&2
  tail -20 "$ERR" >&2
  exit 5
fi

echo "ok: $(awk 'END{print NR}' "$OUT_FILE") lines in $OUT_FILE · conversation_id=$CONV · cli=$CLI · model=${MODEL:-default}"
exit 0
