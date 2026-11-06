#!/usr/bin/env python3
"""Print the resolved specbaton settings of a project.

Usage:
    config.py [project dir]            all settings, one KEY=value per line
    config.py [project dir] --key KEY  one value, or nothing when unset

The project's settings live in .claude/specbaton.json, written by /specbaton:setup. Paths in it are relative to the
project root, or absolute. The project root is the given dir (default: $CLAUDE_PROJECT_DIR, else the current dir) or
the nearest folder above it that has .claude/specbaton.json.

Exit codes: 0 found, 1 no settings file (specbaton isn't set up in this project), 2 the file isn't valid JSON.
"""
import json
import os
import sys

DEFAULTS = {
    "layer": "A",
    "memory_dir": ".",
    "rules_file": "CLAUDE.md",
    "status_path": "openspec/changes/{change}/status.md",
    "openspec": True,
    "graphify_cmd": "",
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


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    key = None
    if "--key" in argv:
        i = argv.index("--key")
        key = argv[i + 1] if i + 1 < len(argv) else None
        args = [a for a in args if a != key]
    start = args[0] if args else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    root = find_root(start)
    if root is None:
        return 1
    try:
        with open(os.path.join(root, ".claude", "specbaton.json"), encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        print("specbaton: .claude/specbaton.json isn't valid JSON", file=sys.stderr)
        return 2
    values = dict(DEFAULTS)
    values.update({k: v for k, v in cfg.items() if not isinstance(v, (dict, list))})

    def absolute(p):
        return p if os.path.isabs(p) else os.path.normpath(os.path.join(root, p))

    values["root"] = root
    values["memory_dir_abs"] = absolute(str(values["memory_dir"]))
    values["rules_file_abs"] = absolute(str(values["rules_file"]))
    values["status_path_abs"] = (
        str(values["status_path"]) if os.path.isabs(str(values["status_path"])) else os.path.join(root, str(values["status_path"]))
    )
    values["farewell_patterns"] = "\n".join(cfg.get("farewell_patterns", []))
    graphs = cfg.get("graphs") if isinstance(cfg.get("graphs"), dict) else {}
    values["graphs_enabled"] = bool(graphs.get("enabled", False))
    values["graphs_exclude"] = "\n".join(str(e).strip("/") for e in graphs.get("exclude") or [])
    for k, v in list(values.items()):
        if isinstance(v, bool):
            values[k] = "true" if v else "false"
    if key:
        v = values.get(key, "")
        if v != "":
            print(v)
        return 0
    for k in sorted(values):
        if k not in ("farewell_patterns", "graphs_exclude"):
            print(f"{k}={values[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
