---
name: handoff
description: Close the session by writing the change's state and decisions to the memory files, so a clean session can resume with no briefing. Run it when the user types /specbaton:handoff, says goodbye (a specbaton hook asks for it), when the context gets heavy, or before switching to another change.
argument-hint: "[change]"
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" *)
---
Close the session by writing to files everything needed to resume it in a clean session. Change: $ARGUMENTS (when empty, use this conversation's change; when that isn't clear, ask the user).

First, get this project's settings: `python3 "${CLAUDE_SKILL_DIR}/../../scripts/config.py" "${CLAUDE_PROJECT_DIR}"`. In what follows, MEM is its `memory_dir_abs`, STATUS is its `status_path_abs` with `{change}` replaced by the change's name, and `graphify_cmd` is the command that refreshes the code graphs (empty when the project doesn't use them). If it exits with 1, specbaton isn't set up in this project: say so in one line, suggest `/specbaton:setup`, and stop.

1. **State.** Overwrite STATUS (create it if it doesn't exist), following `${CLAUDE_SKILL_DIR}/../../templates/status.md`:
   - `# <change> — updated <today's date>`
   - a `Unit | Repo/path | Branch | PR | Status` table with each unit the change touches;
   - `Next:` one concrete step, naming the file and function, never "continue with X";
   - `Blockers:` and `Open questions:`;
   - `Deviations from the spec:` each one with its ADR.

   It's a snapshot of the present, not a diary: the history stays in git.
2. **Decisions.** Review this session. For each decision without an ADR, create one in `<MEM>/decisions/` from `<MEM>/templates/adr.md` (or `${CLAUDE_SKILL_DIR}/../../templates/adr.md` when the project has no template), with the next free 4-digit number (`NNNN-slug.md`), `status: proposed`, today's date and the units it affects. Always include the rejected alternatives and why. If the ADR marks something [UNCERTAIN], summarize what's missing in its `uncertain:` property (without `: `, which breaks the YAML) so it shows up in the dashboard; remove the property once it's resolved. If it supersedes an existing ADR, change only the old one's frontmatter (`status: superseded`, `superseded_by`); its body is never edited.
3. **Indexes.** Update `<MEM>/decisions/README.md` and the change's line in `<MEM>/NOW.md`.
4. **Tasks.** Check off in the change's `tasks.md` what's finished, when it exists.
5. **Plan.** If the change has a `plan.md` (from specbaton-reviewer) and this session changed `proposal.md`, `specs/`, `design.md` or `tasks.md`, change `state: current` to `state: outdated` in its frontmatter and tell the user it's worth regenerating with `/specbaton-reviewer:plan`. Don't regenerate it yourself.
6. **Graphs.** If this session changed code and `graphify_cmd` is set, run it from the project root with the units touched. If it fails, tell the user and go on with the handoff.
7. **Review.** Show `git -C <MEM> status` and the diff of the memory files (status, ADRs, indexes, NOW.md), and propose a commit message that includes only those files. Don't commit without the user's approval. If the user is saying goodbye, leave the files written and the commit for when the work resumes.

Reply in the user's language.
