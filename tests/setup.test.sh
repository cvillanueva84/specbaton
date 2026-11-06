#!/usr/bin/env bash
# Tests check.py, which tells a second /specbaton:setup what's already in place, on throwaway projects: a 0.1 setup
# (the code graphs were never offered), a complete one, one with a deleted file, layer B's ignores, a unit without its
# graph, and features turned down.
# Usage: bash tests/setup.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$HERE/plugins/specbaton/scripts/check.py"
TPL="$HERE/plugins/specbaton/templates"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
has() { # has <name> <output> <line>...: every line must be in the output
  local name="$1" out="$2"; shift 2
  for l in "$@"; do
    grep -qxF "$l" <<<"$out" || { echo "FAIL $name: no \"$l\""; sed 's/^/    /' <<<"$out"; fail=$((fail + 1)); return; }
  done
  echo "ok   $name"; pass=$((pass + 1))
}
hasnt() { # hasnt <name> <output> <regex>: no line matches
  if grep -qE "$3" <<<"$2"; then echo "FAIL $1"; grep -E "$3" <<<"$2" | sed 's/^/    /'; fail=$((fail + 1)); else echo "ok   $1"; pass=$((pass + 1)); fi
}
tab=$'\t'

# A layer A project as a 0.1 setup left it: memory files, rules, .obsidian/ ignored, no "graphs" key.
layer_a() {
  local P="$T/$1"; mkdir -p "$P/.claude" "$P/decisions" "$P/templates" "$P/docs/reference" "$P/openspec"
  git -C "$P" init -q
  printf '# NOW\n' > "$P/NOW.md"; printf '# Decisions\n' > "$P/decisions/README.md"; cp "$TPL/adr.md" "$P/templates/adr.md"
  printf 'Operational reference\n' > "$P/docs/reference/README.md"
  # The 0.1 rules had no markers: the section is found through the command name.
  { printf '@NOW.md\n@decisions/README.md\n\n'; sed 1d "$TPL/rules.md"; } > "$P/CLAUDE.md"
  printf '.obsidian/\n' > "$P/.gitignore"
  printf '{"version": 1, "layer": "A", "memory_dir": ".", "rules_file": "CLAUDE.md", "status_path": "openspec/changes/{change}/status.md", "openspec": true, "farewell_patterns": []}\n' > "$P/.claude/specbaton.json"
  echo "$P"
}

# Not set up: exit 1.
mkdir -p "$T/bare"; python3 "$CHECK" "$T/bare" >/dev/null; [ $? -eq 1 ] && { echo "ok   not set up: exit 1"; pass=$((pass + 1)); } || { echo "FAIL not set up"; fail=$((fail + 1)); }

# A 0.1 setup: everything in place, the graphs, Obsidian and the cycle rules to ask, graphify-out/ not ignored yet.
P="$(layer_a old)"
out="$(python3 "$CHECK" "$P")"
has "0.1 setup: memory and rules in place" "$out" "ok${tab}memory: NOW.md" "ok${tab}rules: import @NOW.md" "ok${tab}rules: memory section" "ok${tab}ignore: .obsidian/${tab}$P"
has "0.1 setup: the new features are to ask" "$out" "ask${tab}code graphs${tab}never offered (new in 0.2.0)" "ask${tab}obsidian dashboard${tab}never asked" "ask${tab}ticket cycle rules${tab}never asked"
has "0.1 setup: graphify-out/ isn't ignored yet" "$out" "missing${tab}ignore: graphify-out/${tab}$P" "summary${tab}1 missing, 3 to ask"
out="$(cd "$P/docs/reference" && python3 "$CHECK")"; [[ "$out" == *"summary"* ]] && { echo "ok   finds the root from a subfolder"; pass=$((pass + 1)); } || { echo "FAIL from a subfolder"; fail=$((fail + 1)); }

# The same project, brought up to date with the features turned down: nothing missing, nothing to ask.
printf 'graphify-out/\n' >> "$P/.gitignore"
python3 - "$P/.claude/specbaton.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
c.update({"graphs": {"enabled": False}, "obsidian": False, "cycle_rules": False})
json.dump(c, open(p, "w"))
PY
out="$(python3 "$CHECK" "$P")"
has "up to date, features turned down" "$out" "off${tab}code graphs" "off${tab}obsidian dashboard" "off${tab}ticket cycle rules" "summary${tab}0 missing, 0 to ask"

# A deleted file and a dropped import are missing.
rm "$P/NOW.md"; sed -i.bak '/^@decisions/d' "$P/CLAUDE.md"
out="$(python3 "$CHECK" "$P")"
has "deleted file and dropped import" "$out" "missing${tab}memory: NOW.md${tab}$P/NOW.md" "missing${tab}rules: import @decisions/README.md"

# Features turned on but not in place: dashboard, cycle rules without the gates table, graphs without graphify's output.
P="$(layer_a on)"; printf 'graphify-out/\n' >> "$P/.gitignore"
mkdir -p "$P/apps/web"; echo '{}' > "$P/apps/web/package.json"
python3 - "$P/.claude/specbaton.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
c.update({"graphs": {"enabled": True}, "obsidian": True, "cycle_rules": True, "graphify_cmd": ""})
json.dump(c, open(p, "w"))
PY
cat "$TPL/cycle-rules.md" >> "$P/CLAUDE.md"
out="$(python3 "$CHECK" "$P")"
has "turned on, not in place" "$out" "missing${tab}obsidian dashboard${tab}dashboard.md doesn't exist" "ok${tab}ticket cycle rules" \
  "missing${tab}ticket cycle: gates table${tab}docs/reference/gates.md" "missing${tab}code graphs: units without a graph${tab}web" \
  "missing${tab}rules: code graphs section${tab}templates/graphs-rules.md isn't in the rules file"
# Once the unit has its graph, the graphs rules are in and the dashboard exists, those lines are ok.
mkdir -p "$P/graphify-out/units/web/graphify-out"; echo '{}' > "$P/graphify-out/units/web/graphify-out/graph.json"; echo '{}' > "$P/graphify-out/graph.json"
cat "$TPL/graphs-rules.md" >> "$P/CLAUDE.md"; cp "$TPL/dashboard.md" "$P/dashboard.md"; printf '| Unit |\n' > "$P/docs/reference/gates.md"
out="$(python3 "$CHECK" "$P")"
has "graphs, dashboard and gates in place" "$out" "ok${tab}code graphs: units${tab}1" "ok${tab}rules: code graphs section" "ok${tab}obsidian dashboard" "ok${tab}ticket cycle: gates table"
hasnt "no unit without a graph" "$out" "units without a graph"

# Layer B: the memory beside the team repo, rules in CLAUDE.local.md, ignores in .git/info/exclude.
P="$T/team"; M="$T/team-memory"; mkdir -p "$P/.claude" "$M/decisions" "$M/templates" "$M/docs/reference" "$M/status"
git -C "$P" init -q; git -C "$M" init -q
for f in NOW.md decisions/README.md templates/adr.md docs/reference/README.md; do echo x > "$M/$f"; done
printf '.obsidian/\n' > "$M/.gitignore"
{ printf '@../team-memory/NOW.md\n@../team-memory/decisions/README.md\n\n'; cat "$TPL/rules.md"; } > "$P/CLAUDE.local.md"
printf 'CLAUDE.local.md\n.claude/specbaton.json\n' >> "$P/.git/info/exclude"
printf '{"version": 1, "layer": "B", "memory_dir": "../team-memory", "rules_file": "CLAUDE.local.md", "status_path": "../team-memory/status/{change}.md", "openspec": false, "farewell_patterns": [], "graphs": {"enabled": false}, "obsidian": false, "cycle_rules": false}\n' > "$P/.claude/specbaton.json"
out="$(python3 "$CHECK" "$P")"
has "layer B: memory beside the repo" "$out" "ok${tab}memory folder${tab}$M" "ok${tab}status folder" "ok${tab}rules: import @../team-memory/NOW.md" \
  "ok${tab}ignore: .obsidian/${tab}$M" "ok${tab}ignore: CLAUDE.local.md${tab}$P" "missing${tab}ignore: graphify-out/${tab}$P" "summary${tab}1 missing, 0 to ask"

# Obsidian's excluded folders.
OB="$HERE/plugins/specbaton/scripts/obsidian.py"
V="$T/vault"; mkdir -p "$V/.obsidian" "$V/.claude" "$V/decisions" "$V/api" "$V/web" "$V/node_modules" "$V/notes" "$V/apps/admin"
git -C "$V" init -q; git -C "$V/api" init -q; echo '{}' > "$V/web/package.json"; echo '{}' > "$V/apps/admin/package.json"
printf '{"promptDelete": false, "userIgnoreFilters": ["archive/"]}\n' > "$V/.obsidian/app.json"
out="$(python3 "$OB" "$V")"
has "obsidian: an existing vault and its filters" "$out" "vault${tab}$V${tab}exists" "filter${tab}archive/" "always${tab}graphify-out/${tab}code graphs, written by graphify"
has "obsidian: suggests code and dependencies" "$out" "suggest${tab}api/${tab}its own git repo" "suggest${tab}node_modules/${tab}dependencies or build output" "folder${tab}notes/"
hasnt "obsidian: never suggests the memory folders" "$out" "decisions"
# Without settings yet (the setup asks before writing them), discovery is the plain one: here api/ is a repo, so the
# other folders aren't units.
python3 "$OB" "$V" --add api/ node_modules >/dev/null
out="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["promptDelete"], d["userIgnoreFilters"])' "$V/.obsidian/app.json")"
[ "$out" = "False ['archive/', 'graphify-out/', 'api/', 'node_modules/']" ] && { echo "ok   obsidian --add keeps the other settings and adds graphify-out/"; pass=$((pass + 1)); } || { echo "FAIL obsidian --add: $out"; fail=$((fail + 1)); }
out="$(python3 "$OB" "$V" --add api)"; [ "$out" = "added${tab}nothing (already excluded)" ] && { echo "ok   obsidian --add twice adds nothing"; pass=$((pass + 1)); } || { echo "FAIL obsidian twice: $out"; fail=$((fail + 1)); }
# A monorepo vault: its units (also one level down) are suggested.
M2="$T/monovault"; mkdir -p "$M2/apps/web" "$M2/packages/ui" "$M2/notes"; echo '{}' > "$M2/apps/web/package.json"; echo '{}' > "$M2/packages/ui/package.json"
out="$(python3 "$OB" "$M2")"
has "obsidian: a monorepo's units are suggested" "$out" "vault${tab}$M2${tab}absent" "suggest${tab}apps/web/${tab}a code unit" "suggest${tab}packages/ui/${tab}a code unit" "folder${tab}notes/"
python3 "$OB" "$M2" --add apps/web >/dev/null; [ -f "$M2/.obsidian/app.json" ] && { echo "ok   obsidian --add creates app.json in a new vault"; pass=$((pass + 1)); } || { echo "FAIL no app.json"; fail=$((fail + 1)); }
# app.json in a shape it doesn't expect: left untouched.
printf '{"userIgnoreFilters": "oops"}\n' > "$M2/.obsidian/app.json"; python3 "$OB" "$M2" --add x >/dev/null 2>&1; rc=$?
[ $rc -eq 3 ] && grep -q oops "$M2/.obsidian/app.json" && { echo "ok   obsidian: an unexpected app.json is left alone"; pass=$((pass + 1)); } || { echo "FAIL unexpected app.json: rc $rc"; fail=$((fail + 1)); }
# check.py: an open vault without graphify-out/ excluded is missing it.
Q="$T/old"; mkdir -p "$Q/.obsidian"; printf '{}\n' > "$Q/.obsidian/app.json"
out="$(python3 "$CHECK" "$Q")"
has "check: graphify-out/ not excluded in Obsidian" "$out" "missing${tab}obsidian: graphify-out/ excluded${tab}not in Files and links > Excluded files (.obsidian/app.json)"
python3 "$OB" "$Q" --add >/dev/null; out="$(python3 "$CHECK" "$Q")"
has "check: graphify-out/ excluded in Obsidian" "$out" "ok${tab}obsidian: graphify-out/ excluded"

# Invalid JSON: exit 2.
echo '{nope' > "$P/.claude/specbaton.json"; python3 "$CHECK" "$P" >/dev/null 2>&1; [ $? -eq 2 ] && { echo "ok   invalid JSON: exit 2"; pass=$((pass + 1)); } || { echo "FAIL invalid JSON"; fail=$((fail + 1)); }

# check.py only reads: the projects' git status is the same before and after.
before="$(git -C "$T/old" status --porcelain --ignored)"; python3 "$CHECK" "$T/old" >/dev/null; after="$(git -C "$T/old" status --porcelain --ignored)"
[ "$before" = "$after" ] && { echo "ok   check.py writes nothing"; pass=$((pass + 1)); } || { echo "FAIL check.py wrote"; fail=$((fail + 1)); }

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
