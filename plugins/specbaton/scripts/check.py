#!/usr/bin/env python3
"""Check what a project's specbaton setup has and what it's missing, so /specbaton:setup can offer only what's left.

Usage: check.py [project dir]

One line per item: "<state><TAB><item><TAB><detail>", then "summary<TAB><missing> missing, <ask> to ask".
States:
    ok       in place
    missing  part of the chosen setup, but not there (a file deleted, an ignore never added, a unit without its graph)
    ask      an optional feature the user was never asked about (for example the code graphs, new in 0.2.0)
    off      an optional feature the user turned down
    note     worth knowing, nothing to do (for example, OpenSpec's folder appears with the first change)
It reads and runs git; it never writes. Exit codes: 0 checked, 1 no settings file (not set up), 2 invalid JSON.
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from config import DEFAULTS, find_root  # noqa: E402

lines = []


def report(state, item, detail=""):
    lines.append((state, item, detail))


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


def is_repo(d):
    return subprocess.run(["git", "-C", d, "rev-parse", "--git-dir"], capture_output=True).returncode == 0


def ignored(repo, path):
    return subprocess.run(["git", "-C", repo, "check-ignore", "-q", path], capture_output=True).returncode == 0


def has(text, marker, *fallbacks):
    """A rules section is there when its marker is, or (for files written before the markers) a token that isn't
    translated: a command name or a path."""
    return text is not None and any(t in text for t in (f"<!-- specbaton:{marker} -->",) + fallbacks)


def main(argv):
    start = argv[0] if argv else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    root = find_root(start)
    if root is None:
        return 1
    try:
        with open(os.path.join(root, ".claude", "specbaton.json"), encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        print("specbaton: .claude/specbaton.json isn't valid JSON", file=sys.stderr)
        return 2

    def absolute(p):
        return p if os.path.isabs(p) else os.path.normpath(os.path.join(root, p))

    layer = cfg.get("layer", DEFAULTS["layer"])
    mem = absolute(str(cfg.get("memory_dir", DEFAULTS["memory_dir"])))
    rules_path = absolute(str(cfg.get("rules_file", DEFAULTS["rules_file"])))
    status_path = str(cfg.get("status_path", DEFAULTS["status_path"]))
    openspec = bool(cfg.get("openspec", DEFAULTS["openspec"]))

    # Settings: the keys every version writes.
    for key in ("layer", "memory_dir", "rules_file", "status_path", "openspec", "farewell_patterns"):
        report("ok" if key in cfg else "missing", f"settings: {key}", "" if key in cfg else "not in .claude/specbaton.json")

    # The memory layer and its git repo.
    if not os.path.isdir(mem):
        report("missing", "memory folder", mem)
    elif not is_repo(mem):
        report("missing", "memory folder: git repo", f"{mem} isn't a git repo")
    else:
        report("ok", "memory folder", mem)
    for rel in ("NOW.md", "decisions/README.md", "templates/adr.md", "docs/reference/README.md"):
        p = os.path.join(mem, rel)
        report("ok" if os.path.isfile(p) else "missing", f"memory: {rel}", "" if os.path.isfile(p) else p)
    status_dir = os.path.dirname(absolute(status_path.split("{change}")[0] + "x"))
    if openspec and status_path.startswith("openspec/"):
        ok = os.path.isdir(os.path.join(root, "openspec"))
        report("ok" if ok else "note", "openspec folder", "" if ok else "openspec/ doesn't exist yet: openspec init, or the first change")
    else:
        ok = os.path.isdir(status_dir)
        report("ok" if ok else "missing", "status folder", "" if ok else status_dir)

    # The rules file: the imports and the specbaton section.
    rules = read(rules_path)
    if rules is None:
        report("missing", "rules file", rules_path)
    else:
        mem_rel = os.path.relpath(mem, root)
        prefix = "" if mem_rel == "." else mem_rel.rstrip("/") + "/"
        for target in ("NOW.md", "decisions/README.md"):
            imp = f"@{prefix}{target}"
            report("ok" if imp in rules else "missing", f"rules: import {imp}")
        report("ok" if has(rules, "rules", "/specbaton:resume-work") else "missing", "rules: memory section",
               "" if has(rules, "rules", "/specbaton:resume-work") else "templates/rules.md isn't in the rules file")

    # What git ignores.
    vault = mem if layer == "B" else root
    if is_repo(vault):
        report("ok" if ignored(vault, ".obsidian/") else "missing", "ignore: .obsidian/", vault)
    if is_repo(root):
        wanted = ["graphify-out/"] + (["CLAUDE.local.md", ".claude/specbaton.json"] if layer == "B" else [])
        for p in wanted:
            report("ok" if ignored(root, p) else "missing", f"ignore: {p}", root)

    # Optional: the code graphs (new in 0.2.0).
    graphs = cfg.get("graphs")
    if not isinstance(graphs, dict):
        report("ask", "code graphs", "never offered (new in 0.2.0)")
    elif not graphs.get("enabled"):
        report("off", "code graphs")
    else:
        cmd = (cfg.get("graphify_cmd") or "").strip()
        if not cmd and not shutil.which("graphify"):
            report("missing", "code graphs: graphify", "not installed (pipx install graphifyy)")
        out = subprocess.run([sys.executable, os.path.join(HERE, "units.py"), root], capture_output=True, text=True)
        units = [ln.split("\t", 1) for ln in out.stdout.splitlines() if ln and not ln.startswith("platform\t")]
        without = [n for n, _ in units
                   if not os.path.isfile(os.path.join(root, "graphify-out", "units", n, "graphify-out", "graph.json"))]
        if without:
            report("missing", "code graphs: units without a graph", ", ".join(without))
        elif units:
            report("ok", "code graphs: units", f"{len(units)}")
        if cmd:
            report("ok", "code graphs: own command", cmd)
        elif not os.path.isfile(os.path.join(root, "graphify-out", "graph.json")):
            report("missing", "code graphs: platform graph", "graphify-out/graph.json doesn't exist yet")
        ok = has(rules, "graphs-rules", "graphify-out/units/")
        report("ok" if ok else "missing", "rules: code graphs section", "" if ok else "templates/graphs-rules.md isn't in the rules file")

    # Optional: Obsidian's dashboard.
    obsidian = cfg.get("obsidian")
    dashboard = os.path.isfile(os.path.join(vault, "dashboard.md"))
    if obsidian is False:
        report("off", "obsidian dashboard")
    elif dashboard:
        report("ok", "obsidian dashboard")
    else:
        report("missing" if obsidian else "ask", "obsidian dashboard",
               "dashboard.md doesn't exist" if obsidian else "never asked")

    # Optional: the ticket cycle rules.
    cycle = cfg.get("cycle_rules")
    in_rules = has(rules, "cycle-rules", "docs/reference/gates.md")
    if cycle is False:
        report("off", "ticket cycle rules")
    elif in_rules:
        report("ok", "ticket cycle rules")
        gates = os.path.isfile(os.path.join(mem, "docs", "reference", "gates.md"))
        report("ok" if gates else "missing", "ticket cycle: gates table", "" if gates else "docs/reference/gates.md")
    else:
        report("missing" if cycle else "ask", "ticket cycle rules",
               "templates/cycle-rules.md isn't in the rules file" if cycle else "never asked")

    for state, item, detail in lines:
        print(f"{state}\t{item}\t{detail}".rstrip("\t"))
    missing = sum(1 for s, _, _ in lines if s == "missing")
    ask = sum(1 for s, _, _ in lines if s == "ask")
    print(f"summary\t{missing} missing, {ask} to ask")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
