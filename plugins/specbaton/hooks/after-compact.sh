#!/usr/bin/env bash
# SessionStart (compact): re-anchors Claude on the files after a compaction. PreCompact isn't used: it can only block
# the compaction, and blocking it with a full context would leave no room even for the handoff.
. "$(dirname "$0")/lib.sh"
cat <<'MSG'
specbaton: the context was just compacted, so what you remember of this session may be incomplete or summarized. Before you go on:
1. Re-read the state of the active change (see NOW.md below) and its status file.
2. Treat the ADRs as the source of truth over any summary of the conversation.
3. If this session made decisions that don't have an ADR yet, propose them now, before touching code.
4. Suggest running /specbaton:handoff and continuing in a clean session.

MSG
[ -n "$SB_MEM" ] && [ -f "$SB_MEM/NOW.md" ] && cat "$SB_MEM/NOW.md"
exit 0
