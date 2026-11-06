#!/usr/bin/env bash
# Code graphs with graphify: one graph per unit (repo, service or package) plus a platform graph.
#
# Usage:
#   graphs.sh                 every unit, and the platform graph
#   graphs.sh web api         only those units (the platform graph is rebuilt too)
#   graphs.sh --missing       only the units that don't have a graph yet, such as a folder added since the last run
#   graphs.sh --list          the units and the platform mode, without building anything
#
# The units come from units.py: the "graphs" section of .claude/specbaton.json, or discovered on every run (folders
# with their own .git, or with a project manifest), so a folder added later becomes a unit on its own. Run it from
# anywhere inside the project.
#
# Writes:
#   graphify-out/units/<name>/graphify-out/   graph.json, GRAPH_REPORT.md, graph.html, wiki/, cache/
#   graphify-out/graph.json + GRAPH_REPORT.md the platform graph (merge of the units, or the whole root)
#   graphify-out/INDEX.md                     a table per unit, also readable in Obsidian
# The nested graphify-out/ is on purpose: merge-graphs labels each node with the name of its graph.json's
# grandparent folder, which is then the unit's name.
#
# AST extraction only: it calls no model and costs nothing.
#
# Optional variables:
#   GRAPHIFY_BIN  path to graphify
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAPHIFY="${GRAPHIFY_BIN:-graphify}"
ROOT="$(python3 "$SCRIPT_DIR/config.py" --key root 2>/dev/null || true)"
[ -n "$ROOT" ] || { echo "No .claude/specbaton.json found from $PWD. Run /specbaton:setup first." >&2; exit 2; }
cd "$ROOT"
OUT="$ROOT/graphify-out"

LIST="$(python3 "$SCRIPT_DIR/units.py" "$ROOT")" || { echo "Couldn't read the units from .claude/specbaton.json." >&2; exit 2; }
platform="$(printf '%s\n' "$LIST" | awk -F'\t' '$1 == "platform" { print $2 }')"
units="$(printf '%s\n' "$LIST" | awk -F'\t' '$1 != "platform"')"

if [ "${1:-}" = "--list" ]; then
  if [ -z "$units" ]; then echo "No units: the project's graph is the root's."; else printf '%s\n' "$units" | awk -F'\t' '{ printf "%-24s %s\n", $1, $2 }'; fi
  echo "platform: $platform"
  exit 0
fi

command -v "$GRAPHIFY" >/dev/null || {
  echo "graphify isn't installed. Install it with: pipx install graphifyy (the package has two y's; the command is graphify)." >&2
  exit 3
}

# Which units to build.
todo=""
if [ "${1:-}" = "--missing" ]; then
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    [ -f "$OUT/units/$name/graphify-out/graph.json" ] || todo="$todo$name"$'\t'"$path"$'\n'
  done <<<"$units"
  if [ -z "$todo" ]; then
    if [ -n "$units" ] || [ -f "$OUT/graph.json" ]; then echo "· every unit already has a graph"; exit 0; fi
  fi
elif [ $# -gt 0 ]; then
  for want in "$@"; do
    line="$(printf '%s\n' "$units" | awk -F'\t' -v w="$want" '$1 == w')"
    if [ -n "$line" ]; then todo="$todo$line"$'\n'; else echo "· $want: not a known unit, skipped (graphs.sh --list shows them)" >&2; fi
  done
else
  todo="$units"
fi

mkdir -p "$OUT"
while IFS=$'\t' read -r name path; do
  [ -n "$name" ] || continue
  if [ ! -d "$path" ]; then echo "· $name: $path doesn't exist, skipped"; continue; fi
  dest="$OUT/units/$name/graphify-out"
  mkdir -p "$dest"
  printf "· %-32s" "$name ($path)"
  if GRAPHIFY_OUT="$dest" "$GRAPHIFY" update "$path" >"$dest/.last-update.log" 2>&1; then
    "$GRAPHIFY" export wiki --graph "$dest/graph.json" >>"$dest/.last-update.log" 2>&1 || true
    echo "ok"
  else
    echo "failed (see $dest/.last-update.log)"
  fi
done <<<"$todo"

case "$platform" in
  merge)
    graphs=()
    while IFS= read -r g; do graphs+=("$g"); done < <(ls "$OUT"/units/*/graphify-out/graph.json 2>/dev/null || true)
    if [ "${#graphs[@]}" -gt 1 ]; then
      echo "· platform: merge of the units"
      "$GRAPHIFY" merge-graphs "${graphs[@]}" --out "$OUT/graph.json" >"$OUT/.last-platform.log" 2>&1
      GRAPHIFY_OUT="$OUT" "$GRAPHIFY" cluster-only . --graph "$OUT/graph.json" --no-viz --no-label >>"$OUT/.last-platform.log" 2>&1 || true
    elif [ "${#graphs[@]}" -eq 1 ]; then
      cp "${graphs[0]}" "$OUT/graph.json"
    fi ;;
  full)
    echo "· platform: graph of the whole root"
    GRAPHIFY_OUT="$OUT" "$GRAPHIFY" update . >"$OUT/.last-platform.log" 2>&1 || echo "  failed (see $OUT/.last-platform.log)" ;;
  none) ;;
esac

python3 - "$OUT" "$platform" <<'PY'
import datetime, json, pathlib, sys
out, platform = pathlib.Path(sys.argv[1]), sys.argv[2]
rows = []
for g in sorted(out.glob("units/*/graphify-out/graph.json")):
    unit = g.parent.parent.name
    try:
        data = json.loads(g.read_text())
    except Exception:
        continue
    nodes, links = data.get("nodes", []), data.get("links", data.get("edges", []))
    comms = len({n.get("community") for n in nodes if n.get("community") is not None})
    when = datetime.datetime.fromtimestamp(g.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
    base = f"units/{unit}/graphify-out"
    rows.append(f"| {unit} | {len(nodes):,} | {len(links):,} | {comms} | {when} | [wiki]({base}/wiki/index.md) · [report]({base}/GRAPH_REPORT.md) |")
plat = out / "graph.json"
summary = "no platform graph"
if plat.exists():
    try:
        d = json.loads(plat.read_text())
        kind = {"merge": "merge of the units", "full": "graph of the whole root"}.get(platform, platform)
        summary = f"{len(d.get('nodes', [])):,} nodes · {len(d.get('links', d.get('edges', []))):,} edges ({kind}) · [report](GRAPH_REPORT.md)"
    except Exception:
        pass
lines = [
    "# Code graphs",
    "",
    "Built by specbaton's graphs.sh. Don't edit by hand.",
    "",
    f"**Platform:** {summary}. `graphify query \"...\"` uses this graph by default.",
    "",
]
if rows:
    lines += [
        "For a single unit: `graphify query \"...\" --graph graphify-out/units/<unit>/graphify-out/graph.json`",
        "",
        "| Unit | Nodes | Edges | Communities | Updated | Browse |",
        "| --- | --- | --- | --- | --- | --- |",
        *rows,
        "",
    ]
(out / "INDEX.md").write_text("\n".join(lines))
print(f"· INDEX.md with {len(rows)} unit(s)")
PY
