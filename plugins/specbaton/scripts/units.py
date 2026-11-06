#!/usr/bin/env python3
"""List a project's units for the code graphs: one "name<TAB>path" per line, then "platform<TAB>merge|full|none".

Usage: units.py [project dir]

A unit is a folder with a graph of its own: a repo, a service or a package. They come from the "graphs" section of
.claude/specbaton.json:

    "graphs": {
      "enabled": true,
      "units": "auto",                 or {"web": "apps/web", "api": "services/api"}
      "exclude": ["legacy"],           folders discovery skips (paths relative to the root)
      "platform": "auto"               merge | full | none | auto
    }

With "units": "auto" (the default), they're discovered every time, so a folder added later becomes a unit without
touching anything:
- a folder with its own .git, at the first level, is a unit (several repos in one workspace);
- otherwise, a first-level folder with a project manifest (package.json, pyproject.toml, go.mod, Cargo.toml…) is a
  unit; a first-level folder without one whose subfolders have one (apps/web, apps/api) gives one unit per subfolder,
  named after it ("web"), or "<parent>-<name>" when two share a name;
- a project with no unit folders has no units: its only graph is the root's ("platform" full).

"platform": "auto" is "merge" when the units are separate repos (merging their graphs links shared types) and "full"
otherwise (a graph of the whole root keeps the real imports between units).
"""
import json
import os
import sys

MANIFESTS = {
    "package.json", "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "go.mod", "Cargo.toml",
    "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile", "composer.json", "mix.exs", "pubspec.yaml",
    "Package.swift", "deno.json", "CMakeLists.txt",
}
SKIP = {
    "node_modules", "graphify-out", "dist", "build", "out", "target", "vendor", "venv", ".venv", "env", "__pycache__",
    "coverage", "tmp", "openspec", "decisions", "docs", "templates", "status", "pull-request", "dashboard",
}


def has_manifest(d):
    try:
        names = set(os.listdir(d))
    except OSError:
        return False
    return bool(names & MANIFESTS) or any(n.endswith((".csproj", ".sln")) for n in names)


def subdirs(d):
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return []
    return [n for n in names if not n.startswith(".") and n not in SKIP and os.path.isdir(os.path.join(d, n))]


def discover(root, exclude):
    excluded = {os.path.normpath(e).strip("/") for e in exclude}
    top = [n for n in subdirs(root) if n not in excluded]
    repos = [n for n in top if os.path.exists(os.path.join(root, n, ".git"))]
    if repos:
        return [(n, n) for n in repos], "merge"
    found = []
    for n in top:
        path = os.path.join(root, n)
        if has_manifest(path):
            found.append((n, n))
            continue
        for c in subdirs(path):
            rel = f"{n}/{c}"
            if rel not in excluded and has_manifest(os.path.join(path, c)):
                found.append((c, rel))
    names = [name for name, _ in found]
    units = []
    for name, rel in found:
        if names.count(name) > 1 and "/" in rel:
            name = rel.replace("/", "-")
        units.append((name, rel))
    return units, "full"


def main(argv):
    start = argv[0] if argv else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    from config import find_root  # noqa: E402

    root = find_root(start)
    if root is None:
        return 1
    try:
        with open(os.path.join(root, ".claude", "specbaton.json"), encoding="utf-8") as fh:
            graphs = (json.load(fh).get("graphs") or {})
    except (OSError, ValueError):
        return 2
    configured = graphs.get("units", "auto")
    if isinstance(configured, dict) and configured:
        units = [(str(k), str(v).rstrip("/") or ".") for k, v in configured.items()]
        separate = all(os.path.exists(os.path.join(root, p, ".git")) for _, p in units if p != ".")
        auto_platform = "merge" if separate and all(p != "." for _, p in units) else "full"
    else:
        units, auto_platform = discover(root, graphs.get("exclude") or [])
    platform = graphs.get("platform", "auto")
    if platform not in ("merge", "full", "none"):
        platform = auto_platform
    if not units and platform == "none":
        platform = "full"  # with no units, the root's graph is the only one
    for name, path in units:
        print(f"{name}\t{path}")
    print(f"platform\t{platform}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
