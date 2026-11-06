#!/usr/bin/env python3
"""Print the reviewer's resolved settings for a project.

Usage:
    reviewer_config.py [project dir]                 all settings, one KEY=value per line
    reviewer_config.py [project dir] --key KEY       one value, or nothing when unset
    reviewer_config.py [project dir] --custom-args MODEL RESUME_ID PROMPT_FILE
                                                     the custom adapter's command, NUL-separated

Settings live in the "reviewer" section of .claude/specbaton.json, written by /specbaton-reviewer:setup. The memory
layer's settings (memory_dir, status_path) come from the same file when the specbaton plugin set it up. The project
root is the given dir (default: $CLAUDE_PROJECT_DIR, else the current dir) or the nearest folder above it that has
.claude/specbaton.json.

Exit codes: 0 found, 1 no settings file, 2 the file isn't valid JSON or a custom command is missing.
"""
import json
import os
import sys

DEFAULTS = {
    "cli": "",
    "bin": "",
    "plan_model": "",
    "review_model": "",
    "base": "origin/main",
    "skill": "",
    "exclude": ".obsidian",
    "effort": "",
    "cursor_mode": "ask",
    "runs_dir": "",
    "max_rounds": "3",
}


def find_root(start):
    d = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(d, ".claude", "specbaton.json")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def load(start):
    root = find_root(start)
    if root is None:
        return None, None
    with open(os.path.join(root, ".claude", "specbaton.json"), encoding="utf-8") as fh:
        return root, json.load(fh)


def main(argv):
    positional = []
    i = 0
    key = None
    custom = None
    while i < len(argv):
        a = argv[i]
        if a == "--key":
            key = argv[i + 1] if i + 1 < len(argv) else ""
            i += 2
            continue
        if a == "--custom-args":
            custom = argv[i + 1:i + 4]
            break
        positional.append(a)
        i += 1
    start = positional[0] if positional else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        root, cfg = load(start)
    except (OSError, ValueError):
        print("specbaton-reviewer: .claude/specbaton.json isn't valid JSON", file=sys.stderr)
        return 2
    if root is None:
        return 1
    rev = cfg.get("reviewer") or {}

    if custom is not None:
        spec = rev.get("custom") or {}
        command = spec.get("command") or []
        if not command:
            print('specbaton-reviewer: "reviewer.custom.command" is missing in .claude/specbaton.json', file=sys.stderr)
            return 2
        model, resume_id, prompt_file = (custom + ["", "", ""])[:3]
        with open(prompt_file, encoding="utf-8") as fh:
            prompt = fh.read()
        args = list(command)
        if model:
            args += spec.get("model_args") or []
        if resume_id:
            args += spec.get("resume_args") or []
        values = {"{prompt}": prompt, "{model}": model, "{id}": resume_id, "{prompt_file}": prompt_file}
        out = []
        for a in args:
            for k, v in values.items():
                a = a.replace(k, v)
            out.append(a)
        sys.stdout.write("\0".join(out) + "\0")
        return 0

    values = dict(DEFAULTS)
    for k, v in rev.items():
        if k == "exclude" and isinstance(v, list):
            values[k] = " ".join(v)
        elif not isinstance(v, (dict, list)):
            values[k] = v
    spec = rev.get("custom") or {}
    values["custom_output"] = spec.get("output", "text")
    values["custom_text_field"] = spec.get("text_field", "")
    values["custom_id_field"] = spec.get("id_field", "")
    values["custom_resume"] = "true" if spec.get("resume_args") else "false"
    values["root"] = root
    mem = str(cfg.get("memory_dir", "."))
    values["memory_dir_abs"] = mem if os.path.isabs(mem) else os.path.normpath(os.path.join(root, mem))
    values["memory_outside_root"] = "false" if (values["memory_dir_abs"] + os.sep).startswith(root + os.sep) or values["memory_dir_abs"] == root else "true"
    status = str(cfg.get("status_path", "openspec/changes/{change}/status.md"))
    values["status_path_abs"] = status if os.path.isabs(status) else os.path.join(root, status)
    values["openspec"] = "true" if cfg.get("openspec", True) else "false"
    for k, v in list(values.items()):
        if isinstance(v, bool):
            values[k] = "true" if v else "false"
    if key is not None:
        v = values.get(key, "")
        if str(v) != "":
            print(v)
        return 0
    for k in sorted(values):
        print(f"{k}={values[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
