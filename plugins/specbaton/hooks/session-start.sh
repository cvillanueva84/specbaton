#!/usr/bin/env bash
# SessionStart (startup|clear): what this prints is added to Claude's context. Claude Code can't run a command on its
# own in an interactive session, so the hook asks Claude to resume before it answers the user's first message.
. "$(dirname "$0")/lib.sh"
cat <<'MSG'
specbaton: this is a new session. Before you reply to the user's first message, run the specbaton resume-work skill (/specbaton:resume-work) and start your reply with its summary, in a few lines. Then handle what the user asked.
Exception: if the first message has nothing to do with the work in progress (a quick question, another topic), answer it directly and offer to resume in one line at the end.
MSG
exit 0
