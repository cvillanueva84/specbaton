#!/usr/bin/env python3
"""Split a change's tasks.md into the units /specbaton:implement hands to the implementer.

Usage:
    tasks.py <tasks.md> [--mode task|group|change] [--range R]

A task is a checkbox at the start of a line ("- [ ] 1.2 …", or "- [x]" when it's done). Its text is its lines as
written: the checkbox line and every indented or blank line after it, up to the next task, the next "## " heading or
another line at the start of the line. A nested checkbox belongs to its task. Its id is its number (1.2), or L<line>
when it has none. A group is a "## " heading; its id is the heading's leading number ("## 1. Setup" is 1), or its
position among the headings when it has none.

Modes (default group):
    group   one unit per group with pending tasks
    task    one unit per pending task, with the task's id and its group's title
    change  one unit, id "all", with every pending task

--range keeps the tasks in comma-separated pieces, each A or A-B with dotted numbers: "1-3" (groups 1 to 3),
"2.1-2.4" (those tasks), "1.2,3". A task without a number counts as the end of its group: a range of groups includes
it, a range of task numbers doesn't.

Prints JSON: {"total", "done", "pending", "units": [{"id", "title", "tasks": [{"id", "line", "text"}]}]}, where the
counts are the whole file's, before the range.

Exit codes: 0 ok, 2 a missing file, a malformed range or an unknown mode.
"""
import argparse
import json
import math
import re
import sys

TASK = re.compile(r"^- \[( |x|X)\] (?:(\d+(?:\.\d+)+)\s+)?")
HEADING = re.compile(r"^##\s+(.*?)\s*$")
GROUP_NUMBER = re.compile(r"^(\d+)\b")
BOUND = re.compile(r"^\d+(?:\.\d+)*$")


def parse(text):
    """The groups, in order, each with its tasks: id, line, text, done and the key ranges compare."""
    groups = []
    task = None

    def close():
        nonlocal task
        if task is not None:
            while task["lines"] and not task["lines"][-1].strip():
                task["lines"].pop()
            task["text"] = "\n".join(task.pop("lines"))
            task = None

    headings = 0
    for n, line in enumerate(text.replace("\r\n", "\n").replace("\r", "\n").split("\n"), start=1):
        heading = HEADING.match(line)
        checkbox = TASK.match(line)
        if heading:
            close()
            headings += 1
            title = heading.group(1)
            number = GROUP_NUMBER.match(title)
            groups.append({"id": number.group(1) if number else str(headings), "title": title, "tasks": []})
        elif checkbox:
            close()
            if not groups:
                groups.append({"id": "0", "title": "", "tasks": []})
            group = groups[-1]
            number = checkbox.group(2)
            key = tuple(int(p) for p in number.split(".")) if number else (int(group["id"]), math.inf)
            task = {"id": number or f"L{n}", "line": n, "done": checkbox.group(1) != " ", "key": key, "lines": [line]}
            group["tasks"].append(task)
        elif task is not None and (not line or line[0] in " \t"):
            task["lines"].append(line)
        else:
            close()
    close()
    return groups


def bound(text):
    text = text.strip()
    if not BOUND.match(text):
        raise ValueError(f"malformed range piece {text!r}")
    return tuple(int(p) for p in text.split("."))


def in_range(key, spec):
    """Whether a task's key falls in any piece of a range such as "1-3", "2.1-2.4" or "1.2,3"."""
    for piece in spec.split(","):
        lo, dash, hi = piece.partition("-")
        lo = bound(lo)
        hi = bound(hi) if dash else lo
        if key[:len(lo)] >= lo and key[:len(hi)] <= hi:
            return True
    return False


def units(groups, mode, spec=None):
    def wanted(t):
        return not t["done"] and (spec is None or in_range(t["key"], spec))

    def public(t):
        return {"id": t["id"], "line": t["line"], "text": t["text"]}

    if mode == "change":
        tasks = [public(t) for g in groups for t in g["tasks"] if wanted(t)]
        return [{"id": "all", "title": "", "tasks": tasks}] if tasks else []
    if mode == "task":
        return [{"id": t["id"], "title": g["title"], "tasks": [public(t)]} for g in groups for t in g["tasks"] if wanted(t)]
    out = []
    for g in groups:
        tasks = [public(t) for t in g["tasks"] if wanted(t)]
        if tasks:
            out.append({"id": g["id"], "title": g["title"], "tasks": tasks})
    return out


def main(argv):
    parser = argparse.ArgumentParser(prog="tasks.py", description="Split a change's tasks.md into units.")
    parser.add_argument("tasks_file")
    parser.add_argument("--mode", choices=("task", "group", "change"), default="group")
    parser.add_argument("--range", dest="spec")
    args = parser.parse_args(argv)
    try:
        with open(args.tasks_file, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        print(f"specbaton: {args.tasks_file} doesn't exist or can't be read", file=sys.stderr)
        return 2
    groups = parse(text)
    try:
        result = units(groups, args.mode, args.spec)
    except ValueError as err:
        print(f"specbaton: {err} in --range {args.spec!r} (use pieces such as 1-3, 2.1-2.4 or 1.2,3)", file=sys.stderr)
        return 2
    every = [t for g in groups for t in g["tasks"]]
    done = sum(1 for t in every if t["done"])
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps({"total": len(every), "done": done, "pending": len(every) - done, "units": result}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
