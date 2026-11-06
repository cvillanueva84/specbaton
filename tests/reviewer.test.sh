#!/usr/bin/env bash
# Tests specbaton-reviewer's wrapper (reviewer_readonly.sh) and its stream parser with fake CLIs that print each
# adapter's real output format, in a throwaway workspace: no network, no model calls.
# Usage: bash tests/reviewer.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$HERE/plugins/specbaton-reviewer/scripts"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { # check <name> <expected exit> <actual exit> [<grep pattern in output file or stderr>] [<file>]
  local name="$1" want="$2" got="$3" pat="${4:-}" file="${5:-}"
  if [ "$want" != "$got" ]; then echo "FAIL $name: exit $got, expected $want"; sed 's/^/    /' "$T/err" | head -8; fail=$((fail + 1)); return; fi
  if [ -n "$pat" ] && ! grep -q -- "$pat" "${file:-$T/err}"; then echo "FAIL $name: no \"$pat\" in ${file:-stderr}"; sed 's/^/    /' "${file:-$T/err}" | head -8; fail=$((fail + 1)); return; fi
  echo "ok   $name"; pass=$((pass + 1))
}

# The workspace: a private root repo whose .gitignore is an allowlist, with a team repo inside.
W="$T/ws"; mkdir -p "$W/.claude" "$W/api" "$W/.obsidian" "$W/graphify-out"
cd "$W" || exit 1
git init -q && printf '/*\n!/.gitignore\n!/NOW.md\n!/.claude/\n' > .gitignore && echo now > NOW.md
cat > .claude/specbaton.json <<'EOF'
{"version": 1, "memory_dir": ".", "reviewer": {"cli": "agy", "exclude": [".obsidian"],
 "custom": {"command": ["fakecustom", "--ask", "{prompt}"], "model_args": ["-m", "{model}"], "output": "json", "text_field": "answer.text", "id_field": "thread"}}}
EOF
git add -A && git -c user.email=t@t -c user.name=t commit -qm init
git -C api init -q && echo a > api/a.js && git -C api add . && git -C api -c user.email=t@t -c user.name=t commit -qm init

# Fake CLIs. Each records its arguments in $T/args-<name>, and FAKE picks the case.
B="$T/bin"; mkdir -p "$B"
cat > "$B/agy" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "--help" ] && { echo "  --disable-slash-commands"; exit 0; }
printf '%s\n' "$@" > "$ARGS_DIR/args-agy"
case "${FAKE:-ok}" in
ok) cat <<'J'
{"event":"init","conversation_id":"c-1","init":{"model":"m","permission_mode":"request-review"}}
{"event":"step_update","step_update":{"conversation_id":"c-1","state":"ACTIVE","step_type":"agent_response","text_delta":"Reading"}}
{"event":"step_update","step_update":{"conversation_id":"c-1","state":"ACTIVE","step_type":"tool","tool_name":"read_file","tool_info":{"parameters":{"Path":"/x/NOW.md"}}}}
{"event":"step_update","step_update":{"conversation_id":"c-1","state":"DONE","step_type":"tool","tool_name":"read_file"}}
{"event":"step_update","step_update":{"conversation_id":"c-1","state":"DONE","step_type":"agent_response","text_delta":"# Plan\ndone\n"}}
{"event":"result","result":{"conversation_id":"c-1","status":"SUCCESS","response":"# Plan\ndone\n","duration_seconds":3.2,"usage":{"total_tokens":10}}}
J
;;
denied) echo 'no output produced — a tool required the "command" permission' >&2
  echo '{"event":"result","result":{"conversation_id":"c-2","status":"SUCCESS","response":"","denied_actions":[{"action":"command","display_name":"RunCommand"}]}}' ;;
write-repo) echo x >> api/a.js; echo '{"event":"result","result":{"conversation_id":"c-3","status":"SUCCESS","response":"changed"}}' ;;
write-ignored) echo x > graphify-out/hidden.md; echo '{"event":"result","result":{"conversation_id":"c-4","status":"SUCCESS","response":"ok"}}' ;;
obsidian) echo x > .obsidian/workspace.json; touch api/.DS_Store; echo '{"event":"result","result":{"conversation_id":"c-5","status":"SUCCESS","response":"ok"}}' ;;
badmodel) echo 'error: invalid model selection' >&2; echo '{"conversation_id":"","status":"ERROR","error":"invalid model"}'; exit 1 ;;
limit) echo 'Error: usage limit reached' >&2; exit 1 ;;
esac
EOF
cat > "$B/cursor-agent" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "--help" ] && { echo "--stream-partial-output --mode"; exit 0; }
printf '%s\n' "$@" > "$ARGS_DIR/args-cursor"
cat <<'J'
{"type":"system","subtype":"init","model":"m","session_id":"s-1"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Checking"}]}}
{"type":"tool_call","subtype":"started","tool_call":{"readToolCall":{"args":{"path":"a"}}}}
{"type":"tool_call","subtype":"completed","tool_call":{"readToolCall":{"args":{"path":"a"}}}}
{"type":"assistant","message":{"content":[{"type":"text","text":"# Review"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":" ok"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"# Review ok"}]}}
{"type":"result","subtype":"success","is_error":false,"result":"Checking# Review ok","session_id":"s-1","duration_ms":2000}
J
EOF
cat > "$B/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGS_DIR/args-claude"
echo "SPECBATON_CHILD=${SPECBATON_CHILD:-}" >> "$ARGS_DIR/args-claude"
case "${FAKE:-ok}" in
ok) cat <<'J'
{"type":"system","subtype":"init","session_id":"cl-1","model":"claude-x","tools":["Glob","Grep","Read"]}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Looking"}},"session_id":"cl-1"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Looking"},{"type":"tool_use","name":"Read","input":{"file_path":"/x/a.js"}}]},"session_id":"cl-1"}
{"type":"user","message":{"content":[{"type":"tool_result","content":"1 a","is_error":false}]},"session_id":"cl-1"}
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"# Review\nfine"}},"session_id":"cl-1"}
{"type":"assistant","message":{"content":[{"type":"text","text":"# Review\nfine"}]},"session_id":"cl-1"}
{"type":"result","subtype":"success","is_error":false,"result":"# Review\nfine","session_id":"cl-1","num_turns":2,"total_cost_usd":0.01,"duration_ms":4000}
J
;;
badmodel) cat <<'J'
{"type":"system","subtype":"init","session_id":"cl-2","model":"no-such"}
{"type":"result","subtype":"success","is_error":true,"result":"There's an issue with the selected model (no-such).","session_id":"cl-2"}
J
exit 1 ;;
esac
EOF
cat > "$B/fakecustom" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGS_DIR/args-custom"
echo 'some progress line'
echo '{"thread":"t-9","answer":{"text":"# Custom review\nall good"}}'
EOF
chmod +x "$B"/*
export PATH="$B:$PATH" ARGS_DIR="$T" SPECBATON_RUNS_DIR="$T/runs" CLAUDE_PROJECT_DIR="$W"
P="$T/prompt.md"; printf 'Plan the change.\n' > "$P"
run() { OUT="$(mktemp -u "$T/out.XXXX")"; bash "$SCRIPTS/reviewer_readonly.sh" "$P" "$OUT" "${1:-}" >"$T/stdout" 2>"$T/err"; }
reset() { git -C api checkout -q -- . 2>/dev/null; rm -f graphify-out/hidden.md .obsidian/workspace.json api/.DS_Store; }

# agy
FAKE=ok SPECBATON_RESUME=c-0 run gem-high; rc=$?; check "agy: answer" 0 "$rc" "done" "$OUT"
grep -q '^--conversation$' "$T/args-agy" && grep -q '^c-0$' "$T/args-agy" && grep -q 'deny' "$T/args-agy" && grep -q '^--disable-slash-commands$' "$T/args-agy" \
  && { echo "ok   agy: resume, deny rules and flags"; pass=$((pass + 1)); } || { echo "FAIL agy: arguments"; cat "$T/args-agy"; fail=$((fail + 1)); }
grep -q '"conversation_id": "c-1"' "$OUT.meta.json" && { echo "ok   agy: meta"; pass=$((pass + 1)); } || { echo "FAIL agy: meta"; fail=$((fail + 1)); }
FAKE=denied run; rc=$?; check "agy: denied and empty -> 5" 5 "$rc" "RunCommand"
FAKE=write-repo run; rc=$?; check "agy: write in a repo -> 4" 4 "$rc" "api"; reset
FAKE=write-ignored run; rc=$?; check "agy: write in an ignored folder -> 4" 4 "$rc" "graphify-out/hidden.md"; reset
FAKE=obsidian run; rc=$?; check "agy: .obsidian and .DS_Store don't count" 0 "$rc"; reset
FAKE=badmodel run nope; rc=$?; check "agy: unknown model -> 5" 5 "$rc" "invalid model"
FAKE=limit run; rc=$?; check "agy: usage limit -> 5" 5 "$rc" "usage limit"

# cursor
SPECBATON_CLI=cursor SPECBATON_RESUME=s-0 run grok; rc=$?; check "cursor: last segment only" 0 "$rc" "# Review ok" "$OUT"
grep -q 'Checking' "$OUT" && { echo "FAIL cursor: progress note in the answer"; fail=$((fail + 1)); } || { echo "ok   cursor: no progress note"; pass=$((pass + 1)); }
grep -q '^--mode=ask$' "$T/args-cursor" && grep -q '^--resume=s-0$' "$T/args-cursor" \
  && { echo "ok   cursor: ask mode and resume"; pass=$((pass + 1)); } || { echo "FAIL cursor: arguments"; cat "$T/args-cursor"; fail=$((fail + 1)); }

# claude
SPECBATON_CLI=claude SPECBATON_RESUME=cl-0 run sonnet; rc=$?; check "claude: answer" 0 "$rc" "fine" "$OUT"
grep -q 'Looking' "$OUT" && { echo "FAIL claude: progress in the answer"; fail=$((fail + 1)); } || { echo "ok   claude: final message only"; pass=$((pass + 1)); }
for want in '^--tools$' '^Read,Grep,Glob$' '^--disallowedTools$' '^mcp__\*$' '^--setting-sources$' '^--resume$' '^cl-0$' '^SPECBATON_CHILD=1$'; do
  grep -q -- "$want" "$T/args-claude" || { echo "FAIL claude: missing $want"; cat "$T/args-claude"; fail=$((fail + 1)); continue 2; }
done; echo "ok   claude: read-only flags, resume and child guard"; pass=$((pass + 1))
grep -q '"total_cost_usd": 0.01' "$OUT.meta.json" && { echo "ok   claude: meta"; pass=$((pass + 1)); } || { echo "FAIL claude: meta"; cat "$OUT.meta.json"; fail=$((fail + 1)); }
SPECBATON_CLI=claude FAKE=badmodel run no-such; rc=$?; check "claude: unknown model -> 5" 5 "$rc" "selected model"

# custom
SPECBATON_CLI=custom run mx; rc=$?; check "custom: JSON answer" 0 "$rc" "all good" "$OUT"
grep -q '"conversation_id": "t-9"' "$OUT.meta.json" && grep -q '^-m$' "$T/args-custom" && grep -q '^Plan the change.$' "$T/args-custom" \
  && { echo "ok   custom: id, model args and prompt"; pass=$((pass + 1)); } || { echo "FAIL custom: meta or arguments"; cat "$T/args-custom" "$OUT.meta.json"; fail=$((fail + 1)); }

# usage errors
bash "$SCRIPTS/reviewer_readonly.sh" "$P" "$W/inside.md" >/dev/null 2>"$T/err"; check "output inside the workspace -> 2" 2 $? "outside the workspace"
SPECBATON_CLI=nope bash "$SCRIPTS/reviewer_readonly.sh" "$P" "$T/x.md" >/dev/null 2>"$T/err"; check "unknown cli -> 2" 2 $? "cursor, agy, claude or custom"
PATH="/usr/bin:/bin" SPECBATON_CLI=claude bash "$SCRIPTS/reviewer_readonly.sh" "$P" "$T/x.md" >/dev/null 2>"$T/err"; check "missing CLI -> 3" 3 $? "isn't on the PATH"

# change_diff.sh masks secrets
git -C api checkout -qb feat && printf 'STRIPE_SECRET_KEY=sk_live_abcdefghijk123\n"password": "supersecret123"\nghp_abcdefghijklmnopqrstuvwxyz1234\nconst k = process.env.API_TOKEN;\n' > api/s.env \
  && git -C api add . && git -C api -c user.email=t@t -c user.name=t commit -qm s
bash "$SCRIPTS/change_diff.sh" master api > "$T/diff" 2>"$T/err" || bash "$SCRIPTS/change_diff.sh" main api > "$T/diff" 2>"$T/err"
if grep -q 'sk_live_\|supersecret\|ghp_' "$T/diff"; then echo "FAIL change_diff: a secret survived"; grep 'sk_live_\|supersecret\|ghp_' "$T/diff"; fail=$((fail + 1))
elif grep -q 'process.env.API_TOKEN' "$T/diff" && grep -q '<redacted>' "$T/diff"; then echo "ok   change_diff: secrets masked, code kept"; pass=$((pass + 1))
else echo "FAIL change_diff: unexpected output"; head -20 "$T/diff"; fail=$((fail + 1)); fi

# The workspace is untouched by the wrapper itself.
[ -z "$(git status --porcelain)" ] && { echo "ok   the root has no stray files"; pass=$((pass + 1)); } || { echo "FAIL stray files:"; git status --porcelain; fail=$((fail + 1)); }

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
