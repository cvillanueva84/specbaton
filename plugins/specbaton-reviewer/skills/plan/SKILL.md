---
name: plan
description: Generate a change's plan.md with the reviewer agent (read-only), iterating in the same conversation until no verifiable observation is left. Run it when the user types /specbaton-reviewer:plan, and right after an OpenSpec change is proposed (/opsx:propose), without waiting to be asked.
argument-hint: "<change> [model]"
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" *)
---
Generate the change's implementation plan with the reviewer agent. The agent only reads and returns text; you save the file. If the plan has verifiable gaps, send them back **in the same conversation** so the agent delivers the corrected plan, until none is left.

Arguments: $ARGUMENTS. The first is the change; when empty, use the active change in the memory layer's NOW.md, and when it lists several or none, run `openspec list` and ask the user. The second is the model; when absent, use `plan_model` from the settings.

Reply to the user in their language. Whenever a step says "run the wrapper", it means, from the project root, in the background and with a 25-minute limit (a round can take about 20 minutes, and the Bash tool stops foreground commands at 10):
`bash "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_readonly.sh" <prompt file> <output file> <model>`
Before waiting, show the user the "Live progress: tail -f …" line it prints, so they can follow it.

0. **Settings.** Run `python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" "${CLAUDE_PROJECT_DIR}"`. If it exits with 1, or prints no `cli`, the reviewer isn't set up: suggest `/specbaton-reviewer:setup` and stop. Note `cli`, `plan_model`, `memory_dir_abs` (MEM), `status_path_abs`, `memory_outside_root`, `custom_resume` and `max_rounds`.
1. **Artifacts.** Check that `openspec/changes/<change>/proposal.md`, `specs/`, `design.md` and `tasks.md` exist. If one is missing, say which and stop.
2. **Earlier plan.** If `plan.md` already exists, tell the user and ask whether to regenerate it (the old one stays in git).
3. **Round 1.** Copy `${CLAUDE_SKILL_DIR}/../../prompts/plan.md` to a temporary file outside the workspace (`mktemp`), replacing:
   - `{{CHANGE}}` with the change's name;
   - `{{ROOT}}` with the project root's absolute path;
   - `{{MEM_DIR}}` with MEM;
   - `{{STATUS_FILE}}` with `status_path_abs`, `{change}` replaced;
   - `{{LANGUAGE}}` with the user's language;
   - `{{MEMORY_CONTEXT}}`: empty when `memory_outside_root` is false (the agent reads the memory from the root); otherwise the content of the change's status file and of the ADRs that apply, each under a heading with its path, since the agent may not be able to read outside the root.

   Run the wrapper with that prompt, an output file from `mktemp`, and the model. Keep the `conversation_id` from `<output>.meta.json`: it's the conversation for the next rounds.
4. **Exit codes** (in any round):
   - `3`: the CLI isn't installed, isn't signed in, or doesn't trust the workspace. Tell the user what the wrapper reported and offer to write the plan yourself with the same prompt (then `generated_by: claude` and no rounds).
   - `4`: the agent changed files. Show what the wrapper reported, with `git status` and `git diff` in each affected repo, and stop. Discard nothing without the user's OK.
   - `5` or anything else but 0: show the error and the log, and stop. If the wrapper says actions were denied, say the agent tried something outside read-only and didn't answer.
5. **Quality check.** Review the output without rewriting it, and note only **verifiable observations**:
   - a WHEN/THEN scenario in `specs/` the plan doesn't cover (compare them one by one);
   - a cited path that doesn't exist;
   - a task in `tasks.md` with no step in the plan;
   - a consumer outside the change (another unit or a shared file) that you found in the code and the plan doesn't list under "Assumptions and blast radius";
   - a step that contradicts an `accepted` ADR or `design.md`;
   - a missing required section.

   Style or approach preferences are **not** sent to the agent: note them for the final summary, as the user's decisions.
6. **Next rounds** (at most `max_rounds` in all, 3 by default). When there are verifiable observations, copy `${CLAUDE_SKILL_DIR}/../../prompts/plan-followup.md` to a temporary file, replacing `{{ROUND}}`, `{{CHANGE}}` and `{{OBSERVATIONS}}` (numbered, each with its evidence). `{{PREVIOUS_OUTPUT}}` stays empty, unless the CLI can't resume (`cli` is `custom` and `custom_resume` is false): then it's "## Your previous plan" followed by the previous round's whole output. Run the wrapper with `SPECBATON_RESUME=<conversation_id>` in front (only when the CLI can resume). The output is the whole revised plan. Repeat step 5. If the agent rejects an observation and its reason is right, accept it; if it isn't, don't insist more than once: it stays pending.
7. **Save.** Write `openspec/changes/<change>/plan.md` with this frontmatter followed by the agent's last output:
   ```
   ---
   type: plan
   change: <change>
   generated_by: <the CLI's --version output> · model <model>
   date: <YYYY-MM-DD>
   sources: proposal.md, specs/, design.md, tasks.md, ADRs
   memory_commit: <git -C MEM rev-parse --short HEAD>
   reviewer_chat: <conversation_id>
   rounds: <number of rounds>
   state: current
   ---
   ```
   If observations remain unresolved after the last round, add them at the end under `## Pending observations (Claude)`.
8. **Summary.** Tell the user in a few lines: rounds used and what was fixed in each, scenario coverage, the diagrams included, the main risks, the "ADR proposals" the plan suggests (don't write ADRs without the user's OK), and the preferences you noted in step 5. End with how to open the conversation with the reviewer agent: `cursor-agent --resume <id>`, `agy --conversation <id>` or `claude --resume <id>`, depending on `cli`.
