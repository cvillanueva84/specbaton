# Shared setup for specbaton's hooks. Sourced, not run.
# Every hook fails open: in a project without .claude/specbaton.json, without python3, or in a session that
# specbaton-reviewer started as a read-only reviewer (SPECBATON_CHILD=1), it prints nothing and exits 0, so specbaton
# never gets in the way of a session.
[ -z "${SPECBATON_CHILD:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
SB_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
SB_ROOT="$(python3 "$SB_SCRIPTS/config.py" --key root 2>/dev/null)" || exit 0
[ -n "$SB_ROOT" ] || exit 0
SB_MEM="$(python3 "$SB_SCRIPTS/config.py" "$SB_ROOT" --key memory_dir_abs 2>/dev/null)"
