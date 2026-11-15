#!/usr/bin/env bash
# Tests the delegated implementation's scripts on throwaway files: tasks.py, which splits a change's tasks.md into
# units by task, group or change.
# Usage: bash tests/implement.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
S="$HERE/plugins/specbaton/scripts"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /' | head -8; fail=$((fail + 1)); }
# tasks <args...>: runs tasks.py, keeping its JSON in $T/out.json and its exit code in $rc.
tasks() { python3 "$S/tasks.py" "$@" >"$T/out.json" 2>"$T/err"; rc=$?; }
# j <name> <python expression over d>: passes when the expression is true for the last JSON.
j() {
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$T/out.json" "$2" 2>/dev/null
  then ok "$1"; else no "$1" "$(head -c 600 "$T/out.json"; cat "$T/err")"; fi
}

# A change's tasks: a done task, sub-bullets and a nested checkbox, tasks without a number, a heading without one.
F="$T/tasks.md"
printf '%s\n' \
  '## 1. Setup' \
  '' \
  '- [x] 1.1 Done task' \
  '- [ ] 1.2 Write the migration. Verify in `tests/test_schema.py`:' \
  '  - Creates three tables.' \
  '  - [ ] a nested checkbox stays inside 1.2' \
  '- [ ] 1.3 Add the marker' \
  '' \
  '## 2. Build' \
  '' \
  '- [ ] 2.1 Write build' \
  '- [ ] Polish the build docs' \
  '' \
  '## Docs' \
  '' \
  '- [ ] Update the README' > "$F"

tasks "$F"
j "tasks: group mode" '[u["id"] for u in d["units"]] == ["1","2","3"] and (d["total"], d["done"], d["pending"]) == (6, 1, 5)'
j "tasks: sub-bullets and nested checkboxes stay in their task" \
  '[t["id"] for t in d["units"][0]["tasks"]] == ["1.2","1.3"] and d["units"][0]["tasks"][0]["line"] == 4 and d["units"][0]["tasks"][0]["text"].startswith("- [ ] 1.2 Write the migration") and "Creates three tables." in d["units"][0]["tasks"][0]["text"] and "a nested checkbox stays inside 1.2" in d["units"][0]["tasks"][0]["text"] and "1.3" not in d["units"][0]["tasks"][0]["text"]'
j "tasks: a task without a number keeps its line" '[t["id"] for t in d["units"][1]["tasks"]] == ["2.1","L12"] and [t["id"] for t in d["units"][2]["tasks"]] == ["L16"]'
tasks "$F" --mode task
j "tasks: task mode" '[u["id"] for u in d["units"]] == ["1.2","1.3","2.1","L12","L16"] and d["units"][2]["title"] == "2. Build"'
tasks "$F" --mode change
j "tasks: change mode" 'len(d["units"]) == 1 and d["units"][0]["id"] == "all" and len(d["units"][0]["tasks"]) == 5'
tasks "$F" --range 1
j "tasks: range of groups" '[u["id"] for u in d["units"]] == ["1"]'
tasks "$F" --mode task --range 1.3-2.1
j "tasks: range of tasks" '[u["id"] for u in d["units"]] == ["1.3","2.1"]'
tasks "$F" --mode task --range 1.2,3
j "tasks: range with several pieces" '[u["id"] for u in d["units"]] == ["1.2","L16"]'
tasks "$F" --range 9
[ "$rc" -eq 0 ] && j "tasks: range that matches nothing" 'd["units"] == []' || no "tasks: range that matches nothing exits $rc"

# CRLF line endings split exactly like LF.
tasks "$F"; cp "$T/out.json" "$T/lf.json"
sed 's/$/\r/' "$F" > "$T/crlf.md"; tasks "$T/crlf.md"
python3 - "$T/lf.json" "$T/out.json" "$F" "$T/crlf.md" <<'PY' && ok "tasks: CRLF splits like LF" || no "tasks: CRLF differs from LF"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
sys.exit(0 if a == b else 1)
PY

printf '%s\n' '- [x] 1.1 a' > "$T/done.md"; tasks "$T/done.md"
j "tasks: everything done" 'd["pending"] == 0 and d["units"] == []'

errs=""
tasks "$F" --range x-y; { [ "$rc" -eq 2 ] && grep -q "specbaton: .*range" "$T/err"; } || errs="$errs range:$rc"
tasks "$F" --mode nope; { [ "$rc" -eq 2 ] && grep -q "invalid choice" "$T/err"; } || errs="$errs mode:$rc"
tasks "$T/missing.md"; { [ "$rc" -eq 2 ] && grep -q "specbaton: .*missing.md" "$T/err"; } || errs="$errs missing:$rc"
[ -z "$errs" ] && ok "tasks: errors exit 2" || no "tasks: errors exit 2" "$errs"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
