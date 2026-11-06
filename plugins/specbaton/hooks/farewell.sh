#!/usr/bin/env bash
# UserPromptSubmit: when the user says goodbye, asks Claude to run the handoff before saying goodbye.
. "$(dirname "$0")/lib.sh"
exec python3 "$(dirname "$0")/farewell.py" "$SB_ROOT"
