"""UserPromptSubmit: when the user's message is a goodbye, ask Claude to run the specbaton handoff first.

Reads the hook input from stdin; what it prints is added to Claude's context with the message. Accents are folded and
messages that start with "/" are ignored. Goodbyes in English and Spanish are built in; .claude/specbaton.json can add
more as "farewell_patterns" (regular expressions, lowercase, without accents).
"""
import json
import os
import re
import subprocess
import sys
import unicodedata

try:
    prompt = json.load(sys.stdin).get("prompt", "") or ""
except Exception:
    sys.exit(0)

text = unicodedata.normalize("NFKD", prompt.lower()).encode("ascii", "ignore").decode().strip()
if not text or text.startswith("/"):
    sys.exit(0)  # explicit commands, /specbaton:handoff included

# A goodbye word alone ("bye", "adios") counts only at the start or the end of the message, so "the goodbye screen has
# a bug" isn't one; the longer phrases count anywhere.
EDGE_WORDS = r"(bye|goodbye|good ?night|see you|buenas noches|adios|chao|chau)"
PATTERNS = [
    rf"^(ok(ay)?|well|thanks|thank you|gracias|bueno|listo)?[,!. ]*{EDGE_WORDS}([!.,]|$)",
    rf"\b{EDGE_WORDS}[!.,]*( (all|everyone|team|a todos|equipo))?[!.,]*$",
    # English
    r"\bsee you (tomorrow|later|on monday|soon)\b",
    r"\b(talk|catch you) (to you )?(tomorrow|later|on monday)\b",
    r"\b(that'?s (it|all)|i'?m done|wrapping up) for (today|now|the day)\b",
    r"\b(calling it a day|signing off|logging off|heading out)\b",
    # Spanish
    r"\bhasta (manana|luego|el lunes|pronto)\b",
    r"\bnos vemos( manana| luego| el lunes| pronto)?[!.,]*$",
    r"\b(continuamos|seguimos|retomamos)( con esto)? (manana|el lunes|luego|despues|otro dia)\b",
    r"\bme (despido|retiro)\b",
    r"\b(ya )?me voy( ya)?( por hoy)?[!.,]*( gracias)?[!.,]*$",
    r"\b(eso es todo|es todo|terminamos|cerramos|lo dejamos( aqui)?) por hoy\b",
    r"\bpor hoy es todo\b",
]

root = sys.argv[1] if len(sys.argv) > 1 else ""
if root:
    try:
        extra = subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(__file__), "..", "scripts", "config.py"), root, "--key", "farewell_patterns"],
            capture_output=True, text=True, timeout=5,
        ).stdout
        PATTERNS += [p for p in extra.splitlines() if p.strip()]
    except Exception:
        pass

def matches(p):
    try:
        return re.search(p, text) is not None
    except re.error:
        return False

if any(matches(p) for p in PATTERNS):
    print(
        "specbaton: the user is saying goodbye. Before you say goodbye, run the full specbaton handoff skill "
        "(/specbaton:handoff): status, pending ADRs, indexes, tasks and graphs. Leave the files written even though the "
        "user may not be here to approve the commit; the commit is proposed when the work resumes. If this session "
        "changed nothing (only questions), say so in one line and say goodbye without a handoff."
    )
