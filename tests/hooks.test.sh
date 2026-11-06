#!/usr/bin/env bash
# Tests the specbaton plugin's hooks and settings reader with simulated hook inputs, in a throwaway project.
# Usage: bash tests/hooks.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
H="$HERE/plugins/specbaton/hooks"
CFG="$HERE/plugins/specbaton/scripts/config.py"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
no() { echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/    /' | head -8; fail=$((fail + 1)); }
prompt() { python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"session_id":"s1"}))' "$1"; }

P="$T/project"; mkdir -p "$P/sub/deep"
export CLAUDE_PROJECT_DIR="$P"

# Without settings, every hook is silent.
out="$(bash "$H/session-start.sh" </dev/null)"; [ -z "$out" ] && ok "no settings: session start is silent" || no "no settings: session start printed" "$out"
out="$(prompt "see you tomorrow" | bash "$H/farewell.sh")"; [ -z "$out" ] && ok "no settings: farewell is silent" || no "no settings: farewell printed" "$out"
python3 "$CFG" "$P" >/dev/null; [ $? -eq 1 ] && ok "config: exit 1 without settings" || no "config: exit code without settings"

# Layer B: the memory lives beside the project.
mkdir -p "$P/.claude" "$T/project-memory"
cat > "$P/.claude/specbaton.json" <<'EOF'
{"version": 1, "layer": "B", "memory_dir": "../project-memory", "rules_file": "CLAUDE.local.md",
 "status_path": "../project-memory/status/{change}.md", "openspec": false, "farewell_patterns": ["\\btschuss\\b"]}
EOF
printf '# NOW — updated 2026-11-06\n\n## Active changes\n\n- add-login\n' > "$T/project-memory/NOW.md"

v="$(python3 "$CFG" "$P/sub/deep" --key memory_dir_abs)"; [ "$v" = "$T/project-memory" ] && ok "config: finds the root from a subfolder and resolves MEM" || no "config: memory_dir_abs" "$v"
v="$(python3 "$CFG" "$P" --key status_path_abs)"; [ "$v" = "$P/../project-memory/status/{change}.md" ] && ok "config: status path" || no "config: status path" "$v"
v="$(python3 "$CFG" "$P" --key openspec)"; [ "$v" = "false" ] && ok "config: booleans" || no "config: booleans" "$v"

out="$(bash "$H/session-start.sh" </dev/null)"; [[ "$out" == *"/specbaton:resume-work"* ]] && ok "session start asks for resume-work" || no "session start" "$out"
out="$(bash "$H/after-compact.sh" </dev/null)"; [[ "$out" == *"compacted"* && "$out" == *"add-login"* ]] && ok "after compact re-anchors and prints NOW.md" || no "after compact" "$out"

for m in "see you tomorrow" "That's all for today, thanks" "hasta mañana!" "Seguimos mañana con esto" "por hoy es todo" "ok tschüss" "Bye!" "Thanks, goodbye" "ok, gracias, nos vemos" "listo, me voy"; do
  out="$(prompt "$m" | bash "$H/farewell.sh")"; [[ "$out" == *"/specbaton:handoff"* ]] && ok "farewell: \"$m\"" || no "farewell missed: \"$m\"" "$out"
done
for m in "/specbaton:handoff" "review PR 12" "the goodbye screen has a bug" "no me voy a meter con eso todavía" "goodbye page is broken" "nos vemos obligados a cambiarlo"; do
  out="$(prompt "$m" | bash "$H/farewell.sh")"; [ -z "$out" ] && ok "not a farewell: \"$m\"" || no "false farewell: \"$m\"" "$out"
done

# A reviewer session (SPECBATON_CHILD=1) runs no hook.
out="$(SPECBATON_CHILD=1 bash "$H/session-start.sh" </dev/null)"; [ -z "$out" ] && ok "child session: silent" || no "child session printed" "$out"

# Broken settings fail open.
echo '{nope' > "$P/.claude/specbaton.json"
out="$(bash "$H/session-start.sh" </dev/null 2>&1)"; [ -z "$out" ] && ok "invalid JSON: silent" || no "invalid JSON printed" "$out"

# hooks.json is valid and points at existing scripts.
python3 - "$H" <<'PY' && ok "hooks.json: valid, scripts exist" || no "hooks.json"
import json, os, re, sys
h = sys.argv[1]
data = json.load(open(os.path.join(h, "hooks.json")))
for event, groups in data["hooks"].items():
    for g in groups:
        for hook in g["hooks"]:
            for path in re.findall(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^"\s]+)', hook["command"]):
                assert os.path.isfile(os.path.join(h, "..", path)), path
PY

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
