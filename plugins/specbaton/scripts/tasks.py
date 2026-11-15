#!/usr/bin/env python3
"""Split a change's tasks.md into the units /specbaton:implement hands to the implementer.

Usage:
    tasks.py <tasks.md> [--mode task|group|change] [--range R]

Tasks are read with OpenSpec's own checkbox grammar, so both count the same: a checkbox is a "-", "*", "+" or
numbered bullet holding a box ("- [ ] 1.2 …", "* [x] …", "1. [ ] …"), done only with x or X. A task is a checkbox that
isn't indented under another task. Its text is its lines as written: the checkbox line and every blank line or line
indented deeper than it, up to the next task, the next "## " heading or another line as shallow as the task. A checkbox
indented under a task belongs to that task, and the task is done only when all of its boxes are. Its id is its number
(1.2, or 1.2a), or L<line> when it has none. A group is a "## " heading; its id is the heading's number ("## 1. Setup"
is 1), or its position among the headings when it has none.

Modes (default group):
    group   one unit per group with pending tasks
    task    one unit per pending task, with the task's id and its group's title
    change  one unit, id "all", with every pending task

--range keeps the tasks in comma-separated pieces, each A or A-B with dotted numbers: "1-3" (groups 1 to 3),
"2.1-2.4" (those tasks), "1.2,3". A task without a number counts as the end of its group: a range of groups includes
it, a range of task numbers doesn't.

Prints JSON: {"total", "done", "pending", "units": [{"id", "title", "tasks": [{"id", "line", "lines", "text"}]}]}.
The counts are the whole file's checkboxes, nested ones included, before the range, as OpenSpec counts them; "lines"
holds every checkbox line of a task, to check them all off once it passes.

Exit codes: 0 ok, 2 a missing or unreadable file (or one that isn't UTF-8), a malformed range or an unknown mode.
"""
import argparse
import json
import math
import re
import sys

# OpenSpec's own grammar (OpenSpec 1.16), so both count the same tasks: any line whose bullet (-, *, + or a number
# with . or )) holds a box is a checkbox, done only with x or X; a task id may end in letters (1.2a); a group is a
# level-two heading, numbered as "## N.".
CHECKBOX = re.compile(r"^(\s*)(?:[-*+]|\d{1,9}[.)])\s*\[(?:\s*([^\]\s]?)\s*\](?![(\[])|\s+\])\s*(.*)")
TASK_ID = re.compile(r"^(\d+(?:\.\d+)+)([A-Za-z]+)?(?=\s|$)")
HEADING = re.compile(r"^ {0,3}##(?!#)(?:[ \t]+|[ \t]*$)(.*?)\s*$")
GROUP_NUMBER = re.compile(r"^(\d+)\.(?:[ \t]|$)")
BOUND = re.compile(r"^\d+(?:\.\d+)*$")


def columns(indent):
    return len(indent.expandtabs(4))


def parse(text):
    """The groups, in order, each with its tasks: id, line, boxes (each checkbox line and whether it's done), text,
    done (every box done) and the key ranges compare. A checkbox indented under a task belongs to that task."""
    groups = []
    task = None

    def close():
        nonlocal task
        if task is not None:
            while task["lines"] and not task["lines"][-1].strip():
                task["lines"].pop()
            task["text"] = "\n".join(task.pop("lines"))
            task["done"] = all(done for _, done in task["boxes"])
            del task["indent"]
            task = None

    headings = 0
    for n, line in enumerate(text.replace("\r\n", "\n").replace("\r", "\n").split("\n"), start=1):
        heading = HEADING.match(line)
        box = CHECKBOX.match(line)
        if heading:
            close()
            headings += 1
            title = heading.group(1)
            number = GROUP_NUMBER.match(title)
            groups.append({"id": number.group(1) if number else str(headings), "title": title, "tasks": []})
        elif box:
            indent = columns(box.group(1))
            done = (box.group(2) or "").lower() == "x"
            if task is not None and indent > task["indent"]:
                task["lines"].append(line)
                task["boxes"].append((n, done))
                continue
            close()
            if not groups:
                groups.append({"id": "0", "title": "", "tasks": []})
            group = groups[-1]
            number = TASK_ID.match(box.group(3))
            if number:
                key = tuple(int(p) for p in number.group(1).split("."))
                tid = number.group(1) + (number.group(2) or "")
            else:
                key, tid = (int(group["id"]), math.inf), f"L{n}"
            task = {"id": tid, "line": n, "boxes": [(n, done)], "key": key, "indent": indent, "lines": [line]}
            group["tasks"].append(task)
        elif task is not None and (not line.strip() or columns(line[:len(line) - len(line.lstrip())]) > task["indent"]):
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
        return {"id": t["id"], "line": t["line"], "lines": [n for n, _ in t["boxes"]], "text": t["text"]}

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
        with open(args.tasks_file, encoding="utf-8-sig") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        print(f"specbaton: {args.tasks_file} doesn't exist or can't be read", file=sys.stderr)
        return 2
    groups = parse(text)
    try:
        result = units(groups, args.mode, args.spec)
    except ValueError as err:
        print(f"specbaton: {err} in --range {args.spec!r} (use pieces such as 1-3, 2.1-2.4 or 1.2,3)", file=sys.stderr)
        return 2
    boxes = [done for g in groups for t in g["tasks"] for _, done in t["boxes"]]
    total, done = len(boxes), sum(boxes)
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps({"total": total, "done": done, "pending": total - done, "units": result}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
