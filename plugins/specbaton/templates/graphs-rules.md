## Code graphs (specbaton)

- There's a graph per unit in `graphify-out/units/<unit>/graphify-out/`, and a platform graph in `graphify-out/graph.json`, graphify's default path. `graphify-out/INDEX.md` lists them with their date; each unit has a wiki at `wiki/index.md`.
- Ask about one unit with `graphify query "..." --graph graphify-out/units/<unit>/graphify-out/graph.json`. Use the platform graph for questions that cross units.
- `/specbaton:handoff` refreshes the graphs of the units a session touched. A folder added to the project becomes a unit on its own and gets its graph at the first handoff that touches it.
- Never run `graphify update .` yourself: it would break this layout.
