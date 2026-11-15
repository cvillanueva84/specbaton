#!/usr/bin/env bash
# Tests the delegated implementation on throwaway files: tasks.py (a change's tasks.md split into units, read with
# OpenSpec's own checkbox grammar), snapshot.sh (git trees of the working tree) and the implement skill's text.
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
j "tasks: group mode" '[u["id"] for u in d["units"]] == ["1","2","H3"] and (d["total"], d["done"], d["pending"]) == (7, 1, 6)'
j "tasks: a nested checkbox's line is listed with its task" 'd["units"][0]["tasks"][0]["lines"] == [4, 6] and d["units"][0]["tasks"][1]["lines"] == [7]'
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
tasks "$F" --mode task --range 1.2,2
j "tasks: range with several pieces" '[u["id"] for u in d["units"]] == ["1.2","2.1","L12"]'
tasks "$F" --range 9
[ "$rc" -eq 0 ] && j "tasks: range that matches nothing" 'd["units"] == []' || no "tasks: range that matches nothing exits $rc"

printf '%s\n' '## Prep' '- [ ] tidy up' '## 1. Setup' '- [ ] 1.1 b' > "$T/heads.md"; tasks "$T/heads.md"
j "tasks: a heading without a number never takes another's id" '[u["id"] for u in d["units"]] == ["H1","1"]'
tasks "$T/heads.md" --range 1
j "tasks: a range of groups skips headings without a number" '[u["id"] for u in d["units"]] == ["1"]'

# CRLF line endings split exactly like LF.
tasks "$F"; cp "$T/out.json" "$T/lf.json"
sed 's/$/\r/' "$F" > "$T/crlf.md"; tasks "$T/crlf.md"
python3 - "$T/lf.json" "$T/out.json" "$F" "$T/crlf.md" <<'PY' && ok "tasks: CRLF splits like LF" || no "tasks: CRLF differs from LF"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
sys.exit(0 if a == b else 1)
PY

# OpenSpec's other checkbox forms: *, + and numbered bullets, extra spaces, an empty box, a letter suffix, X.
G="$T/forms.md"
printf '%s\n' '## 1. Forms' '' '* [ ] 1.1 star' '1. [ ] 1.2 numbered' '- [ ]  1.3 two spaces' '- [] 1.4 empty box' \
  '- [ ] 1.5a suffix' '  - [ ] nested' '- [X] 1.6 done' '+ [ ] 1.7 plus' > "$G"
tasks "$G"
j "tasks: OpenSpec's other checkbox forms" '(d["total"], d["done"]) == (8, 1) and [t["id"] for t in d["units"][0]["tasks"]] == ["1.1","1.2","1.3","1.4","1.5a","1.7"] and d["units"][0]["tasks"][4]["lines"] == [7, 8]'
tasks "$G" --mode task --range 1.5
j "tasks: a letter suffix is in its number's range" '[u["id"] for u in d["units"]] == ["1.5a"]'
printf '%s\n' '- [x] 1.1 done' '  - [ ] its open sub-task' > "$T/open-sub.md"; tasks "$T/open-sub.md"
j "tasks: a done task with an open nested box stays pending" '(d["total"], d["done"]) == (2, 1) and [t["id"] for u in d["units"] for t in u["tasks"]] == ["1.1"]'
printf '\xef\xbb\xbf- [ ] 1.1 first line\n' > "$T/bom.md"; tasks "$T/bom.md"
j "tasks: a byte-order mark doesn't hide line 1" 'd["total"] == 1 and d["units"][0]["tasks"][0]["id"] == "1.1"'
# The counts match OpenSpec's own, when its CLI is installed.
if command -v openspec >/dev/null 2>&1; then
  O="$T/os"; mkdir -p "$O/openspec/changes/a" "$O/openspec/changes/b"
  cp "$F" "$O/openspec/changes/a/tasks.md"; cp "$G" "$O/openspec/changes/b/tasks.md"; printf '# x\n' | tee "$O/openspec/changes/a/proposal.md" > "$O/openspec/changes/b/proposal.md"
  diffs=""
  for c in a b; do
    want="$(cd "$O" && openspec instructions apply --change "$c" --json 2>/dev/null | python3 -c 'import json,sys; p=json.load(sys.stdin)["progress"]; print(p["total"], p["complete"])')"
    got="$(python3 "$S/tasks.py" "$O/openspec/changes/$c/tasks.md" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["total"], d["done"])')"
    [ "$want" = "$got" ] || diffs="$diffs $c: openspec $want, tasks.py $got;"
  done
  [ -z "$diffs" ] && ok "tasks: the counts match OpenSpec's" || no "tasks: the counts differ from OpenSpec's:$diffs"
else
  ok "tasks: the counts match OpenSpec's (skipped: openspec isn't installed)"
fi

printf '%s\n' '- [x] 1.1 a' > "$T/done.md"; tasks "$T/done.md"
j "tasks: everything done" 'd["pending"] == 0 and d["units"] == []'

errs=""
tasks "$F" --range x-y; { [ "$rc" -eq 2 ] && grep -q "specbaton: .*range" "$T/err"; } || errs="$errs range:$rc"
tasks "$F" --mode nope; { [ "$rc" -eq 2 ] && grep -q "invalid choice" "$T/err"; } || errs="$errs mode:$rc"
tasks "$T/missing.md"; { [ "$rc" -eq 2 ] && grep -q "specbaton: .*missing.md" "$T/err"; } || errs="$errs missing:$rc"
tasks "$F" --range 1,x; [ "$rc" -eq 2 ] || errs="$errs range-piece:$rc"
tasks "$T/done.md" --range x-y; [ "$rc" -eq 2 ] || errs="$errs range-on-done:$rc"
[ -z "$errs" ] && ok "tasks: errors exit 2" || no "tasks: errors exit 2" "$errs"

# snapshot.sh: a tree of the working tree, in a repo whose path has a space, without touching the index or HEAD.
R="$T/my repo"; mkdir -p "$R"; git -C "$R" init -q -b main; printf 'ignored.log\n' > "$R/.gitignore"
snap() { bash "$S/snapshot.sh" "$R" 2>"$T/err"; }
s="$(snap)"
if [[ "$s" =~ ^[0-9a-f]{40}\ none\ main$ ]] && [ "$(git -C "$R" cat-file -t "${s%% *}")" = "tree" ]; then ok "snapshot: a repo with no commits"; else no "snapshot: a repo with no commits" "$s$(cat "$T/err")"; fi
echo one > "$R/a.txt"; git -C "$R" add -A; git -C "$R" -c user.email=t@t -c user.name=t commit -qm init
s1="$(snap)"; echo two > "$R/a.txt"; s2="$(snap)"
names="$(git -C "$R" diff --name-only "${s1%% *}" "${s2%% *}")"
[ "$names" = "a.txt" ] && [ "$(cut -d' ' -f2 <<<"$s2")" = "$(git -C "$R" rev-parse HEAD)" ] && ok "snapshot: an edit to a tracked file" || no "snapshot: an edit to a tracked file" "$names / $s2"
echo new > "$R/b.txt"; s3="$(snap)"
[ "$(git -C "$R" diff --name-only "${s2%% *}" "${s3%% *}")" = "b.txt" ] && ok "snapshot: a new untracked file" || no "snapshot: a new untracked file" "$s2 / $s3"
echo noise > "$R/ignored.log"; s4="$(snap)"
[[ "$s4" =~ ^[0-9a-f]{40}\  ]] && [ "${s4%% *}" = "${s3%% *}" ] && ok "snapshot: an ignored file doesn't count" || no "snapshot: an ignored file doesn't count" "$s3 / $s4"
git -C "$R" add a.txt
before="$(git -C "$R" diff --cached --name-only; git -C "$R" status --porcelain)"; s5="$(snap)"
after="$(git -C "$R" diff --cached --name-only; git -C "$R" status --porcelain)"
[[ "$s5" =~ ^[0-9a-f]{40}\  ]] && [ -n "$before" ] && [ "$before" = "$after" ] && ok "snapshot: touches nothing" || no "snapshot: touches nothing" "$before / $after"
git -C "$R" checkout -q -b other; s6="$(snap)"
[ "$(cut -d' ' -f2 <<<"$s6")" = "$(cut -d' ' -f2 <<<"$s5")" ] && [ "$(cut -d' ' -f3 <<<"$s5")" = "main" ] && [ "$(cut -d' ' -f3 <<<"$s6")" = "other" ] \
  && ok "snapshot: a new branch at the same commit shows" || no "snapshot: a branch change at the same commit" "$s5 / $s6"
# Racy git: an edit of the same size, in the same second the index was written, must still be seen. Repeated, since
# it depends on the clock: with a seed index that loses its timestamp, some rounds miss the edit.
stale=0
for i in $(seq 10 49); do
  git -C "$R" add a.txt; printf 'v%s\n' "$i" > "$R/a.txt"; s="$(snap)"
  [ "$(git -C "$R" rev-parse "${s%% *}:a.txt")" = "$(git -C "$R" hash-object "$R/a.txt")" ] || stale=$((stale + 1))
done
[ "$stale" -eq 0 ] && ok "snapshot: a same-size edit in the same second is seen" || no "snapshot: $stale of 40 snapshots missed a same-size edit"
if [ "$(id -u)" -ne 0 ]; then
  echo secret > "$R/locked.txt"; chmod 000 "$R/locked.txt"; s="$(snap)"; rc=$?; chmod 644 "$R/locked.txt"
  [ "$rc" -eq 1 ] && [ -z "$s" ] && grep -q "specbaton: " "$T/err" && [ "$(grep -vc 'specbaton: ' "$T/err")" -gt 0 ] \
    && ok "snapshot: a failure shows git's message" || no "snapshot: a failure (exit $rc)" "$(cat "$T/err")"
  rm -f "$R/locked.txt"
else
  ok "snapshot: a failure shows git's message (skipped: running as root)"
fi
mkdir -p "$T/plain"; bash "$S/snapshot.sh" "$T/plain" >/dev/null 2>"$T/err"; rc=$?
[ "$rc" -eq 2 ] && grep -q "specbaton: " "$T/err" && ok "snapshot: not a repo exits 2" || no "snapshot: not a repo exits $rc" "$(cat "$T/err")"

# The skill carries the implementer's prompt itself: a plugin's other folders can sit outside what the session may
# read (a plugin installed under ~/.claude/plugins), and a blocked read stops the run before any unit.
M="$HERE/plugins/specbaton"; SKILL="$M/skills/implement/SKILL.md"
if [ -f "$SKILL" ] && grep -q "^## The implementer's prompt" "$SKILL" && ! grep -q 'prompts/implementer' "$SKILL" && [ ! -e "$M/prompts" ]
then ok "implement: the prompt lives in the skill"; else no "implement: the skill reads its prompt from outside its own file"; fi
got="$(sed -n "/^## The implementer's prompt/,\$p" "$SKILL" | grep -o '{{[A-Z_]*}}' | sort -u | tr '\n' ' ')"
[ "$got" = "{{CHANGE}} {{CONTEXT_FILES}} {{OPENSPEC_CONTEXT}} {{REPOS}} {{ROOT}} {{RULES_FILE}} {{UNIT}} " ] && ok "implement: the prompt's placeholders are the design's" || no "implement: the prompt's placeholders" "$got"
ctx="$(sed -n '/^## 2. Context/,/^## 3/p' "$SKILL")"; loop="$(sed -n '/^## 4. Each unit/,/^## 5/p' "$SKILL")"
grep -q '^- Add STATUS' <<<"$ctx" && ok "implement: STATUS is among the implementer's context files" || no "implement: STATUS isn't in the context files"
grep -q 'progress' <<<"$ctx" && ok "implement: the units are checked against OpenSpec's progress" || no "implement: no check against OpenSpec's progress"
grep -q 'tasks.py" <root>/' "$SKILL" && grep -q 'snapshot.sh" <root>/' "$SKILL" && ok "implement: the scripts get absolute paths" || no "implement: the scripts get paths relative to the current folder"
grep -q 'MEM' <<<"$(grep -m1 -A3 'Snapshot' <<<"$loop")" && ok "implement: the root and MEM are snapshotted too" || no "implement: edits outside the change's repos go unseen"
grep -q 'snapshot fails' <<<"$loop" && ok "implement: a failed snapshot stops the run" || no "implement: nothing says what to do when a snapshot fails"
grep -q '`lines`' <<<"$loop" && ok "implement: every checkbox line of a passed task is checked off" || no "implement: only each task's first line is checked off"
bad=""
for skill in "$HERE"/plugins/*/skills/*/SKILL.md; do
  plugin="${skill%/skills/*}"
  for s in $(grep -m1 '^allowed-tools:' "$skill" | grep -o 'scripts/[A-Za-z_]*\.[a-z]*' | sort -u); do [ -f "$plugin/$s" ] || bad="$bad ${skill#"$HERE"/}:$s"; done
done
[ -z "$bad" ] && ok "skills: every script in allowed-tools exists" || no "skills: scripts that don't exist:$bad"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
