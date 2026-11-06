#!/usr/bin/env bash
# Tests unit discovery for the code graphs (units.py and graphs.sh --list) on throwaway projects, and, when graphify is
# installed, a real build that picks up a folder added later.
# Usage: bash tests/graphs.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
S="$HERE/plugins/specbaton/scripts"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
expect() { # expect <name> <project> <expected units.py output>
  local got; got="$(python3 "$S/units.py" "$2")"
  if [ "$got" = "$3" ]; then echo "ok   $1"; pass=$((pass + 1)); else echo "FAIL $1"; diff <(printf '%s\n' "$3") <(printf '%s\n' "$got") | sed 's/^/    /'; fail=$((fail + 1)); fi
}
DEFAULT_CFG='{"version": 1, "graphs": {"enabled": true}}'
project() { mkdir -p "$T/$1/.claude"; printf '%s\n' "${2:-$DEFAULT_CFG}" > "$T/$1/.claude/specbaton.json"; }
tab=$'\t'

# Several repos in one folder: each repo is a unit, merged.
project multi; for r in api web; do mkdir -p "$T/multi/$r" && git -C "$T/multi/$r" init -q; done; mkdir -p "$T/multi/notes"
expect "multi-repo: repos are units, platform merge" "$T/multi" "api${tab}api
web${tab}web
platform${tab}merge"

# A monorepo: manifests at the first level and one level down; docs and dependencies are skipped.
project mono; cd "$T/mono" && git init -q
mkdir -p apps/web apps/api packages/ui docs node_modules/x infra
echo '{}' > apps/web/package.json; echo '[project]' > apps/api/pyproject.toml; echo '{}' > packages/ui/package.json
echo '{}' > node_modules/x/package.json; echo '{}' > docs/package.json
expect "monorepo: services and packages, platform full" "$T/mono" "api${tab}apps/api
web${tab}apps/web
ui${tab}packages/ui
platform${tab}full"

# A folder added later becomes a unit with no change to the settings.
mkdir -p frontend && echo 'module x' > frontend/go.mod
expect "a new folder is a unit on its own" "$T/mono" "api${tab}apps/api
web${tab}apps/web
frontend${tab}frontend
ui${tab}packages/ui
platform${tab}full"

# Excluded folders, and two units with the same name.
project dup '{"version": 1, "graphs": {"enabled": true, "exclude": ["legacy"]}}'
mkdir -p "$T/dup/apps/web" "$T/dup/sites/web" "$T/dup/legacy"; echo '{}' > "$T/dup/apps/web/package.json"; echo '{}' > "$T/dup/sites/web/package.json"; echo '{}' > "$T/dup/legacy/package.json"
expect "exclude and same-name units" "$T/dup" "apps-web${tab}apps/web
sites-web${tab}sites/web
platform${tab}full"

# A single app: no units, the root's graph only.
project single; mkdir -p "$T/single/src"; echo '{}' > "$T/single/package.json"
expect "single app: no units" "$T/single" "platform${tab}full"

# Units set by hand, and an explicit platform.
project manual '{"version": 1, "graphs": {"enabled": true, "units": {"front": "client/", "back": "server"}, "platform": "none"}}'
expect "units set by hand" "$T/manual" "front${tab}client
back${tab}server
platform${tab}none"

# include adds a folder discovery misses; --candidates says why each folder is or isn't a unit.
project inc '{"version": 1, "graphs": {"enabled": true, "include": ["scripts"], "exclude": ["apps/old"]}}'
mkdir -p "$T/inc/apps/web" "$T/inc/apps/old" "$T/inc/apps/assets" "$T/inc/scripts" "$T/inc/notes" "$T/inc/decisions"
echo '{}' > "$T/inc/apps/web/package.json"; echo '{}' > "$T/inc/apps/old/package.json"
expect "include adds a folder without a manifest" "$T/inc" "web${tab}apps/web
scripts${tab}scripts
platform${tab}full"
got="$(python3 "$S/units.py" "$T/inc" --candidates)"
want="memory${tab}decisions${tab}specbaton's memory files
excluded${tab}apps/old${tab}in exclude
no-code${tab}apps/assets${tab}no project manifest
unit${tab}apps/web${tab}has a project manifest
no-code${tab}notes${tab}no project manifest
unit${tab}scripts${tab}in include"
[ "$(sort <<<"$got")" = "$(sort <<<"$want")" ] && { echo "ok   --candidates explains every folder"; pass=$((pass + 1)); } || { echo "FAIL --candidates"; diff <(sort <<<"$want") <(sort <<<"$got") | sed 's/^/    /'; fail=$((fail + 1)); }

# Layer W never gets "full": its root .gitignore hides the repos.
project wlayer '{"version": 1, "layer": "W", "graphs": {"enabled": true, "platform": "full"}}'
for r in api web; do mkdir -p "$T/wlayer/$r" && git -C "$T/wlayer/$r" init -q; done
expect "layer W: full becomes merge" "$T/wlayer" "api${tab}api
web${tab}web
platform${tab}merge"

# graphs.sh --list works from a subfolder.
out="$(cd "$T/mono/apps/web" && bash "$S/graphs.sh" --list)"
[[ "$out" == *"frontend"*"platform: full"* ]] && { echo "ok   graphs.sh --list from a subfolder"; pass=$((pass + 1)); } || { echo "FAIL graphs.sh --list"; echo "$out" | sed 's/^/    /'; fail=$((fail + 1)); }

# A real build, when graphify is installed: the folder added later gets its graph with --missing.
if command -v graphify >/dev/null 2>&1; then
  cd "$T/mono" && rm -rf frontend
  printf 'export const b = () => 1;\n' > packages/ui/b.js; printf 'export const w = () => 1;\n' > apps/web/w.js; printf 'def h():\n    return 1\n' > apps/api/h.py
  bash "$S/graphs.sh" >/dev/null 2>&1
  mkdir -p frontend && echo '{}' > frontend/package.json && printf 'export const f = () => 1;\n' > frontend/f.js
  out="$(bash "$S/graphs.sh" --missing 2>&1)"
  if [[ "$out" == *"frontend (frontend)"*"ok"* ]] && [ -f graphify-out/units/frontend/graphify-out/graph.json ] && grep -q '| frontend |' graphify-out/INDEX.md; then
    echo "ok   graphify: a new folder gets its graph with --missing"; pass=$((pass + 1))
  else echo "FAIL graphify build"; echo "$out" | sed 's/^/    /'; fail=$((fail + 1)); fi
  # A whole-root platform graph leaves the excluded folders out.
  project full '{"version": 1, "graphs": {"enabled": true, "exclude": ["legacy"]}}'
  cd "$T/full" && git init -q && mkdir -p apps/web legacy
  echo '{}' > apps/web/package.json; printf 'export const w = () => 1;\n' > apps/web/w.js; printf 'export const old = () => 1;\n' > legacy/old.js
  out="$(bash "$S/graphs.sh" 2>&1)"
  files="$(python3 -c 'import json; print(sorted({n.get("source_file") for n in json.load(open("graphify-out/graph.json"))["nodes"]}))' 2>&1)"
  if [[ "$files" == *"apps/web/w.js"* && "$files" != *"legacy"* ]] && [ -f graphify-out/GRAPH_REPORT.md ]; then
    echo "ok   graphify: the whole-root graph leaves excluded folders out"; pass=$((pass + 1))
  else echo "FAIL graphify full with exclude"; printf '%s\n%s\n' "$out" "$files" | sed 's/^/    /'; fail=$((fail + 1)); fi
else
  echo "skip graphify build (graphify isn't installed)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
