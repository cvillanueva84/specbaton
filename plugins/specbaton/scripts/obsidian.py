#!/usr/bin/env python3
"""Obsidian's excluded folders ("Files and links > Excluded files"), kept in the vault's .obsidian/app.json under
"userIgnoreFilters". Excluded folders stay out of Obsidian's search, graph view and quick switcher.

Usage:
    obsidian.py <vault>                    what's there and what to suggest, one "<kind><TAB><path><TAB><detail>" per line:
                                             vault     <vault>  exists | absent (no .obsidian/ yet)
                                             filter    <path>   already excluded
                                             always    <path>   specbaton excludes it without asking (graphify-out/)
                                             suggest   <path>   a code folder (a unit, a repo, dependencies): worth excluding
                                             folder    <path>   any other first-level folder, for the user to choose
    obsidian.py <vault> --add <path>...    add those folders (plus graphify-out/) to the filters, keeping everything else
                                           in app.json; creates .obsidian/app.json when the vault has none
    obsidian.py <vault> --colors           the graph view's color groups specbaton proposes, by path, without writing:
                                             color  <query>  <#rrggbb>  <what it is>  new | kept (the vault has it)
    obsidian.py <vault> --colors --apply   add the new ones to .obsidian/graph.json, after the vault's own groups, which
                                           are never changed (Obsidian colors a note with the first group it matches)

Color groups cover the memory files that exist (NOW.md, ADRs, changes, specs, status, reference, pull requests…) and
every other first-level folder that isn't excluded, each with its own color.

The memory files (NOW.md, decisions/, openspec/, status/…) are never suggested: they're what the vault is for.
Obsidian rewrites app.json when its settings change, so edit it with the vault closed, or reload Obsidian afterwards.
Exit codes: 0 done, 2 usage, 3 app.json or graph.json isn't in the expected shape (left untouched).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ALWAYS = ["graphify-out/"]
MEMORY = {"decisions", "templates", "docs", "openspec", "status", "pull-request"}
DEPENDENCIES = {"node_modules", "vendor", "venv", ".venv", "dist", "build", "target", "coverage", "__pycache__"}


# Memory files, most specific first: Obsidian colors a note with the first group it matches.
MEMORY_COLORS = [
    ("file:NOW.md", 0xE8B931, "NOW.md, the starting point", "NOW.md"),
    ("file:dashboard.md", 0xE0607E, "the dashboard", "dashboard.md"),
    ("path:decisions", 0x4C8BF5, "ADRs", "decisions"),
    ("path:openspec/changes/archive", 0x8A8F98, "archived changes", "openspec/changes/archive"),
    ("path:openspec/changes", 0x34A853, "changes in progress", "openspec/changes"),
    ("path:openspec/specs", 0x14A3A3, "specs", "openspec/specs"),
    ("path:status", 0x7CB342, "each change's status", "status"),
    ("path:docs", 0x9C6ADE, "operational reference", "docs"),
    ("path:pull-request", 0xF29D38, "pull request texts", "pull-request"),
    ("path:templates", 0xB0B4BA, "templates", "templates"),
]
OTHER_COLORS = [0xD08770, 0x5E81AC, 0xA3BE8C, 0xBF616A, 0xB48EAD, 0x88C0D0, 0xEBCB8B, 0x8FBCBB]


def proposed_colors(vault, excluded):
    groups = []
    for query, rgb, what, rel in MEMORY_COLORS:
        if os.path.exists(os.path.join(vault, rel)):
            groups.append((query, rgb, what))
    taken = {"openspec"} | MEMORY | DEPENDENCIES
    others = [n for n in sorted(os.listdir(vault))
              if os.path.isdir(os.path.join(vault, n)) and not n.startswith(".") and n not in taken
              and folder(n) not in excluded and folder(n) not in ALWAYS]
    for i, n in enumerate(others):
        groups.append((f"path:{n}", OTHER_COLORS[i % len(OTHER_COLORS)], f"the {n}/ folder"))
    return groups


def colors(vault, apply):
    path = os.path.join(vault, ".obsidian", "graph.json")
    data = {}
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            data = None
    groups = data.get("colorGroups", []) if isinstance(data, dict) else None
    if not isinstance(groups, list):
        print(f"{path}: not the expected shape (colorGroups should be a list): left untouched", file=sys.stderr)
        return 3
    try:
        _, app = load(vault)
    except (OSError, ValueError):
        app = {}
    excluded = {folder(f) for f in (app.get("userIgnoreFilters") or []) if isinstance(f, str) and not f.startswith("/")}
    have = {g.get("query") for g in groups if isinstance(g, dict)}
    new = []
    for query, rgb, what in proposed_colors(vault, excluded):
        state = "kept" if query in have else "new"
        print(f"color\t{query}\t#{rgb:06x}\t{what}\t{state}")
        if state == "new":
            new.append({"query": query, "color": {"a": 1, "rgb": rgb}})
    if apply:
        if new:
            data["colorGroups"] = groups + new
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2)
                fh.write("\n")
        print(f"added\t{len(new)} color group(s)")
    return 0


def folder(p):
    return os.path.normpath(p).strip("/") + "/"


def load(vault):
    path = os.path.join(vault, ".obsidian", "app.json")
    if not os.path.isfile(path):
        return path, {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return path, data


def units(vault):
    """Code folders specbaton's discovery finds in the vault, with its settings when they exist (the setup may ask
    before writing them)."""
    sys.path.insert(0, HERE)
    from units import discover  # noqa: E402

    graphs = {}
    try:
        with open(os.path.join(vault, ".claude", "specbaton.json"), encoding="utf-8") as fh:
            graphs = json.load(fh).get("graphs") or {}
    except (OSError, ValueError, AttributeError):
        pass
    found, _ = discover(vault, graphs.get("exclude") or [], graphs.get("include") or [])
    return {folder(rel): "a code unit" for _, rel in found}


def main(argv):
    if not argv or argv[0].startswith("--"):
        print("usage: obsidian.py <vault> [--add <path>...]", file=sys.stderr)
        return 2
    vault = os.path.abspath(argv[0])
    try:
        path, data = load(vault)
    except (OSError, ValueError):
        print(f"{os.path.join(vault, '.obsidian', 'app.json')} isn't valid JSON: left untouched", file=sys.stderr)
        return 3
    filters = data.get("userIgnoreFilters", []) if isinstance(data, dict) else None
    if not isinstance(data, dict) or not isinstance(filters, list):
        print(f"{path}: not the expected shape (userIgnoreFilters should be a list): left untouched", file=sys.stderr)
        return 3

    if len(argv) > 1 and argv[1] == "--colors":
        return colors(vault, "--apply" in argv[2:])
    if len(argv) > 1 and argv[1] == "--add":
        wanted = ALWAYS + [folder(p) for p in argv[2:]]
        have = {folder(f) for f in filters if isinstance(f, str) and not f.startswith("/")}
        added = [w for w in dict.fromkeys(wanted) if w not in have]
        if added:
            data["userIgnoreFilters"] = filters + added
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2)
                fh.write("\n")
        print(f"added\t{', '.join(added) if added else 'nothing (already excluded)'}")
        return 0
    if len(argv) > 1:
        print("usage: obsidian.py <vault> [--add <path>...]", file=sys.stderr)
        return 2

    print(f"vault\t{vault}\t{'exists' if os.path.isdir(os.path.join(vault, '.obsidian')) else 'absent'}")
    have = set()
    for f in filters:
        if isinstance(f, str):
            print(f"filter\t{f}")
            have.add(folder(f) if not f.startswith("/") else f)
    for a in ALWAYS:
        if a not in have:
            print(f"always\t{a}\tcode graphs, written by graphify")
    code = units(vault)
    try:
        names = sorted(os.listdir(vault))
    except OSError:
        names = []
    shown = set()
    for n in names:
        p = os.path.join(vault, n)
        f = folder(n)
        if not os.path.isdir(p) or n.startswith(".") or f in have or f in ALWAYS or n in MEMORY:
            continue
        if os.path.exists(os.path.join(p, ".git")):
            reason = "its own git repo"
        elif f in code:
            reason = code[f]
        elif n in DEPENDENCIES:
            reason = "dependencies or build output"
        else:
            print(f"folder\t{f}")
            continue
        print(f"suggest\t{f}\t{reason}")
        shown.add(f)
    for f, reason in sorted(code.items()):  # units one level down (apps/web/)
        if f not in shown and f not in have and folder(f.split("/")[0]) not in have:
            print(f"suggest\t{f}\t{reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
