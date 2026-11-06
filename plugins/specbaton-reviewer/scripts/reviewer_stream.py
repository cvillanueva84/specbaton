"""Read the reviewer agent's output from stdin and keep its final answer.

Usage: python3 reviewer_stream.py <cursor|agy|claude|custom> <output> <log> <meta>

- Writes a readable live log (to follow with tail -f) and the raw output next to it (<log>.ndjson).
- At the end, writes the agent's final answer to <output> and the metadata to <meta>: conversation_id, token usage,
  duration and, on failure, the error and the denied actions. <meta> is written even when the agent fails, with the
  conversation id, so the conversation can be resumed.

cursor: the `result` event joins all of the chat's text, including the progress notes the model writes between reads
("Checking…"). So the answer is the last segment (what was written after the last tool call), not `result`. With
--stream-partial-output each segment arrives in pieces and then again whole; the whole message is recognized because it
equals what was accumulated, and isn't added twice.

agy: `result.response` is already only the last message. When it's empty and there are `denied_actions`, the agent
tried something it was denied and didn't answer: that's a failure.

claude: `result.result` is the last message, and `is_error` marks a failure (an unknown model, for example).

custom: the whole stdout. With SPECBATON_CUSTOM_OUTPUT=json, the last JSON object in it, reading the answer from the
field SPECBATON_CUSTOM_TEXT and the conversation id from SPECBATON_CUSTOM_ID (dotted paths, such as result.text).

Exit code: 0 when a result arrived without an error and with text; 6 otherwise.
"""
import json
import os
import sys
import time

cli, out_path, log_path, meta_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
NAMES = {"cursor": "Cursor", "agy": "Antigravity", "claude": "Claude", "custom": "Reviewer"}
name = NAMES.get(cli, "Reviewer")
result = None
conv_id = None
segment = ""  # what the agent wrote since its last tool call
last_kind = None
saw_deltas = False
raw_text = []


def stamp():
    return time.strftime("%H:%M:%S")


def write_meta(data):
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)


def detail_of(args):
    if isinstance(args, dict):
        for key in ("path", "Path", "file_path", "pattern", "Pattern", "query", "Query", "command", "CommandLine",
                    "globPattern", "SearchPath", "DirectoryPath", "url"):
            if args.get(key):
                return f" {args[key]}"
    return ""


def write_text(log, text):
    global segment, last_kind
    if last_kind != "text":
        log.write(f"\n[{stamp()}] {name} writes:\n")
    log.write(text)
    segment += text
    last_kind = "text"


def tool_started(log, tool, args):
    global segment, last_kind
    log.write(f"\n[{stamp()}] → {tool}{detail_of(args)}")
    segment = ""  # what came before a tool call was progress, not the answer
    last_kind = "tool"


def dotted(obj, path):
    for part in [p for p in (path or "").split(".") if p]:
        if isinstance(obj, dict):
            obj = obj.get(part)
        else:
            return None
    return obj


with open(log_path, "a", encoding="utf-8") as log, open(log_path + ".ndjson", "a", encoding="utf-8") as raw:
    log.write(f"\n[{stamp()}] — start ({cli}) —\n")
    log.flush()
    for line in sys.stdin:
        raw.write(line)
        if cli == "custom":
            raw_text.append(line)
            log.write(line)
            log.flush()
            continue
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue

        if cli == "cursor":
            kind, sub = ev.get("type"), ev.get("subtype")
            conv_id = conv_id or ev.get("session_id")
            if kind == "result":
                result = ev
            elif kind == "system" and sub == "init":
                log.write(f"[{stamp()}] model: {ev.get('model', '?')} · conversation: {ev.get('session_id', '?')}\n")
            elif kind == "assistant":
                content = (ev.get("message") or {}).get("content") or []
                text = "".join(
                    c["text"] for c in (content if isinstance(content, list) else [])
                    if isinstance(c, dict) and c.get("type") == "text" and isinstance(c.get("text"), str)
                )
                if text and text != segment:  # the whole message repeats what arrived in pieces
                    write_text(log, text)
            elif kind == "tool_call":
                call = ev.get("tool_call") or {}
                tool = next(iter(call), "tool") if isinstance(call, dict) else "tool"
                args = ((call.get(tool) or {}).get("args") or {}) if isinstance(call, dict) else {}
                if sub == "started":
                    tool_started(log, tool, args)
                elif sub == "completed":
                    log.write(" ✓")

        elif cli == "agy":
            kind = ev.get("event")
            conv_id = conv_id or ev.get("conversation_id") or (ev.get("step_update") or {}).get("conversation_id")
            if kind == "init":
                init = ev.get("init") or {}
                log.write(f"[{stamp()}] model: {init.get('model', '?')} · conversation: {ev.get('conversation_id', '?')}"
                          f" · permissions: {init.get('permission_mode', '?')}\n")
            elif kind == "result":
                result = ev.get("result") or {}
                conv_id = conv_id or result.get("conversation_id")
            elif kind == "step_update":
                st = ev.get("step_update") or {}
                stype, state = st.get("step_type"), st.get("state")
                if stype == "agent_response" and st.get("text_delta"):
                    write_text(log, st["text_delta"])
                elif stype == "tool":
                    info = st.get("tool_info") or {}
                    if state == "ACTIVE":
                        tool_started(log, st.get("tool_name", "tool"), info.get("parameters"))
                    elif state == "DONE":
                        log.write(" ✓")
                    elif state:
                        log.write(f" ({state.lower()})")

        elif cli == "claude":
            kind, sub = ev.get("type"), ev.get("subtype")
            conv_id = conv_id or ev.get("session_id")
            if kind == "result":
                result = ev
            elif kind == "system" and sub == "init":
                log.write(f"[{stamp()}] model: {ev.get('model', '?')} · conversation: {ev.get('session_id', '?')}"
                          f" · tools: {', '.join(ev.get('tools') or [])}\n")
            elif kind == "stream_event":
                delta = ((ev.get("event") or {}).get("delta") or {})
                if delta.get("type") == "text_delta" and delta.get("text"):
                    saw_deltas = True
                    write_text(log, delta["text"])
            elif kind == "assistant":
                for c in ((ev.get("message") or {}).get("content") or []):
                    if not isinstance(c, dict):
                        continue
                    if c.get("type") == "tool_use":
                        tool_started(log, c.get("name", "tool"), c.get("input"))
                    elif c.get("type") == "text" and c.get("text") and not saw_deltas:
                        write_text(log, c["text"])
            elif kind == "user":
                for c in ((ev.get("message") or {}).get("content") or []):
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        log.write(" ✗" if c.get("is_error") else " ✓")

        log.flush()

    if cli == "custom":
        log.write(f"\n[{stamp()}] — end —\n")
    elif result is None:
        log.write(f"\n[{stamp()}] — ended without a result · conversation: {conv_id} —\n")
    else:
        secs = result.get("duration_seconds") or (result.get("duration_ms") or 0) / 1000
        status = result.get("status") or ("ERROR" if result.get("is_error") else "SUCCESS")
        log.write(f"\n[{stamp()}] — end · {int(secs)}s · {status} · conversation: {conv_id} —\n")
        if result.get("denied_actions"):
            log.write(f"[{stamp()}] denied actions: {result['denied_actions']}\n")

meta = {"cli": cli}
if cli == "cursor":
    failed = result is None or bool(result.get("is_error"))
    final = segment if segment.strip() else ((result or {}).get("result") if isinstance((result or {}).get("result"), str) else "")
elif cli == "agy":
    failed = result is None or result.get("status") not in (None, "SUCCESS")
    final = (result or {}).get("response") or ""
    if not final.strip():
        final = segment
    if not final.strip():
        failed = True  # agy answers empty when it was denied something it asked for in headless mode
elif cli == "claude":
    failed = result is None or bool(result.get("is_error"))
    final = (result or {}).get("result") if isinstance((result or {}).get("result"), str) else ""
    if not (final or "").strip():
        final = segment
    if failed and result is not None and isinstance(result.get("result"), str):
        meta["error"] = result.get("result")
else:  # custom
    text = "".join(raw_text)
    final = text
    failed = False
    if os.environ.get("SPECBATON_CUSTOM_OUTPUT") == "json":
        obj = None
        for chunk in reversed([l for l in text.splitlines() if l.strip().startswith("{")] or [text]):
            try:
                obj = json.loads(chunk)
                break
            except ValueError:
                continue
        if obj is None:
            failed = True
            final = ""
        else:
            found = dotted(obj, os.environ.get("SPECBATON_CUSTOM_TEXT", ""))
            final = found if isinstance(found, str) else ""
            conv_id = dotted(obj, os.environ.get("SPECBATON_CUSTOM_ID", "")) or None
    if not final.strip():
        failed = True

meta.update({"conversation_id": conv_id, "is_error": failed})
if result is not None:
    for k in ("usage", "duration_ms", "duration_seconds", "num_turns", "status", "error", "denied_actions",
              "request_id", "total_cost_usd", "permission_denials"):
        if result.get(k) not in (None, "", []):
            meta.setdefault(k, result.get(k))
write_meta(meta)
if failed:
    sys.exit(6)
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(final if isinstance(final, str) else "")
