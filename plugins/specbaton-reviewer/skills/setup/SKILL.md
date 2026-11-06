---
name: setup
description: Set up the reviewer agent in this project - detects the CLIs installed (Cursor, Antigravity, Claude, or any other), asks which one to use and with which models, creates the team's review skill from the user's own or from a generic base, and checks the setup with real read-only runs. Run it only when the user types /specbaton-reviewer:setup or asks to set up the reviewer.
allowed-tools: Bash(python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" *)
---
Set up the reviewer agent: a second agent, run from the command line, that writes the implementation plan before Claude implements and reviews the diff afterwards. It only reads. A wrapper script runs it non-interactively and checks with a git snapshot that it didn't touch any file.

Reply in the user's language. Files you create are in English unless the user asks for their own language.

## Rules for this setup

- At each **⏸ CONFIRM**, show what you're about to do and wait for the user's approval.
- Never delete or overwrite existing files without showing the diff and asking.
- The reviewer agent **never** implements or changes files. If it changes something in a test, stop, show it, and revert nothing without the user's OK.

## 1. What's already here

```bash
python3 "${CLAUDE_SKILL_DIR}/../../scripts/reviewer_config.py" "${CLAUDE_PROJECT_DIR}"
```

- Exit 1: there's no `.claude/specbaton.json`. The reviewer works best with specbaton's memory (`/specbaton:setup`): its ADRs, `NOW.md` and change status are what the reviewer reads. Offer to set that up first. If the user prefers not to, create a minimal `.claude/specbaton.json` with `{"version": 1, "memory_dir": ".", "openspec": <true|false>}`.
- Without OpenSpec (`openspec` false and no `openspec/` folder), `/specbaton-reviewer:plan` has no artifacts to read: offer only `/specbaton-reviewer:code`, which works from the change's status and the pull request's text.

## 2. Which CLI (⏸ CONFIRM)

```bash
for b in cursor-agent agent agy claude codex gemini; do command -v "$b" >/dev/null && echo "$b: $(command -v "$b") · $("$b" --version 2>&1 | head -1)"; done
agent --help 2>/dev/null | grep -qi cursor && echo "agent is Cursor's CLI"
```

Ask the user which one to use, with AskUserQuestion when it's available:

| `cli` | Tool | Read-only through | Resumes with |
| --- | --- | --- | --- |
| `cursor` | Cursor (`cursor-agent`) | `--mode=ask` | `--resume=<id>` |
| `agy` | Antigravity (`agy`) | session `--settings` with deny rules | `--conversation <id>` |
| `claude` | Claude Code with another model | `--tools "Read,Grep,Glob"`, no MCP, no user or project settings | `--resume <id>` |
| `custom` | Any other CLI | its own read-only mode; the git snapshot guards it anyway | when it supports it |

Every reviewer must meet four requirements:
1. It runs non-interactively: it takes a prompt and returns its final answer as text.
2. It can work read-only. The wrapper checks this with a git snapshot anyway.
3. It can resume a conversation by its id, so the rounds stay in the same chat. If it can't, each round includes the previous output in the prompt.
4. It uses a different model from the implementer's, so its blind spots aren't Claude's.

**Claude as the reviewer.** It works, but a Claude model reviewing Claude's work shares more blind spots than a model from another family. It still brings a session with no memory of how the code was written. Recommend at least a different Claude model from the one implementing, and say this plainly to the user. It also spends from the same account as the implementer.

**A custom CLI.** Ask for its non-interactive command and write it to the settings as tokens, with `{prompt}` (the prompt's text), `{prompt_file}` (its path), `{model}` and `{id}` (a conversation to resume) where they go:

```json
"custom": {
  "command": ["codex", "exec", "--sandbox", "read-only", "{prompt}"],
  "model_args": ["--model", "{model}"],
  "resume_args": [],
  "output": "text",
  "text_field": "",
  "id_field": ""
}
```

`output` is `text` (the whole stdout is the answer) or `json` (the last JSON object in stdout; `text_field` and `id_field` are dotted paths to the answer and the conversation id). Without `resume_args`, rounds include the previous output. Check the CLI's own help for its read-only and non-interactive flags before writing them; don't guess them.

## 3. Sign-in and models (⏸ CONFIRM)

- **Cursor:** `cursor-agent status`; models with `cursor-agent --list-models` (or `cursor-agent models`). Cursor asks to trust the workspace the first time: if the test in step 6 exits with 3 for that, the user runs `cursor-agent` once in the root, accepts and exits.
- **Antigravity:** `agy models`. If it fails for sign-in, the user runs `agy` once and signs in.
- **Claude:** `claude --version`; the models are the ones the user's plan offers (aliases such as `sonnet`, `opus` and `haiku` work).

Choose two models with the user, `plan_model` and `review_model`:
- **Plan:** high reasoning, in its fast variant when there is one.
- **Review:** high reasoning.
- **Not from the implementer's family** when there's a choice (Antigravity and Cursor also offer Claude models; don't pick those when Claude implements).
- **No low-reasoning variants**, even if cheaper: in a real test, a low variant miscounted an ADR index (56 of 70) that the high one counted right. The low one is only for testing the setup.
- Use the exact identifier `--model` accepts. An unknown name exits with an error (code 5) and lists the available ones.

## 4. The team's review skill (⏸ CONFIRM)

The agent's review follows the user's own review skill, which improves over time from their human reviewers' comments (`/specbaton-reviewer:code <change> learn`). Look for existing code review skills:

```bash
ls -d .claude/skills/*/ ~/.claude/skills/*/ 2>/dev/null | grep -i -E 'review|revis'
find ~/.claude/plugins -path '*skills*' -name SKILL.md 2>/dev/null | xargs grep -l -i 'review' 2>/dev/null | head
```

Ask the user **whether they have a code review skill to start from**: one of those, one they keep elsewhere (a path, or text they paste), or none.

- **With a base:** the new skill starts from it. Keep its rules and checklist, and add what's missing from the generic base (the evidence rules, the passes table with default severities, and the Output section). Don't change the original: the new one is the user's own copy.
- **Without one:** start from the generic base in `${CLAUDE_SKILL_DIR}/../../templates/review-skill/`.

Ask also:
- the skill's name (lowercase, with hyphens; suggest `<project>-code-review`);
- where installed dependencies live, so the agent can read libraries' code: each unit's `node_modules/`, the virtualenv's `site-packages`, `vendor/`, Go's module cache…;
- how code reaches production, in one line (for example "every merge to main deploys"), or nothing.

Create `.claude/skills/<name>/` with `SKILL.md`, `SPEC.md`, `SOURCES.md` (from the templates, placeholders filled: `{{SKILL_NAME}}`, `{{SKILL_TITLE}}`, `{{PROJECT}}`, `{{DEPS_LOCATION}}`, `{{ROLLOUT_NOTES}}`, `{{ORIGIN}}`, `{{SOURCES}}`, `{{DATE}}`, `{{ORIGIN_SHORT}}`) and an empty `references/evidence/`. Tune pass 2's examples to the stack's real libraries (the SDKs and HTTP clients in the units' manifests) without inventing behavior: what you didn't check in the library's code stays generic. Then check it:

```bash
S=.claude/skills/<name>/SKILL.md
head -5 "$S" | grep -q '^name: ' && head -5 "$S" | grep -q '^description: ' && echo "frontmatter ok"
[ "$(wc -c <"$S")" -lt 12288 ] && echo "size ok" || echo "!! over 12 KB"
grep -n '{{' "$S" || echo "no placeholders left"
```

## 5. Settings (⏸ CONFIRM)

Merge a `reviewer` section into `.claude/specbaton.json`, keeping every other key:

```json
"reviewer": {
  "cli": "<cursor|agy|claude|custom>",
  "plan_model": "<model>",
  "review_model": "<model>",
  "base": "<the branch diffs compare against, such as origin/main>",
  "skill": "<the review skill's name>",
  "exclude": [".obsidian"],
  "max_rounds": 3
}
```

Optional keys: `bin` (the CLI's path), `effort` (agy only), `cursor_mode` (Cursor only, default `ask`), `runs_dir` (where live logs go, default `~/.specbaton-runs/<root name>`) and `custom` (above). Add to `exclude` any root folder that something else writes on its own while the reviewer runs (an editor's or a dev server's).

Add to the project's rules file (`CLAUDE.md`, or `CLAUDE.local.md` in specbaton's layer B):

```markdown
## Reviewer agent (specbaton-reviewer)

- Each change can have `plan.md` (the implementation plan, from `/specbaton-reviewer:plan`) and `review.md` (the second-opinion review, from `/specbaton-reviewer:code`; one `review-<TICKET>.md` per pull request when the change has several). The reviewer agent writes both, read-only. It never implements or checks off tasks: implementation is yours.
- Proposing a change (`/opsx:propose`) ends with `/specbaton-reviewer:plan`, without waiting to be asked.
- When you implement with a current `plan.md`, follow it. If you deviate, say so and record why in the change's status.
- `/specbaton-reviewer:code` runs as soon as I confirm the pull request is open as a draft. Don't fix any finding until I decide in the triage.
- Changes to the review skill are proposed with their diff and applied only with my approval.
```

## 6. Real test (required)

Three short runs against the real root, with the review model. Outputs go to a temporary folder outside the workspace. Run each in the background with a 10-minute limit.

```bash
W="${CLAUDE_SKILL_DIR}/../../scripts/reviewer_readonly.sh"
T="$(mktemp -d)"
printf 'You work read-only: do not edit, create or delete any file and do not run terminal commands. Use only your tools that read files, search and list folders.\nRead NOW.md in the memory layer and the decision index (decisions/README.md). Answer in three lines: how many active changes NOW.md lists, how many ADRs with status accepted the index has, and the names of three files in the project root.\n' > "$T/p1.md"
printf 'Still read-only. How many accepted ADRs did you tell me in your previous answer? Answer in one line.\n' > "$T/p2.md"
printf 'Permission test: try to create the file reviewer-probe.txt in the root with the text hello, then try to run the command git status. Then tell me, in two lines, what you could do and what you could not.\n' > "$T/p3.md"
bash "$W" "$T/p1.md" "$T/r1.md" <review model>; echo "exit=$?"; cat "$T/r1.md"
ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["conversation_id"] or "")' "$T/r1.md.meta.json")"
SPECBATON_RESUME="$ID" bash "$W" "$T/p2.md" "$T/r2.md" <review model>; echo "exit=$?"; cat "$T/r2.md"
bash "$W" "$T/p3.md" "$T/r3.md" <review model>; echo "exit=$?"; cat "$T/r3.md"
ls reviewer-probe.txt 2>/dev/null && echo "!! the agent created the file" || echo "ok: no file"
```

| Run | Expected | Otherwise |
| --- | --- | --- |
| 1. Read | `exit=0` and the right numbers (check them against the files yourself) | `3`: sign-in or workspace trust (step 3). `5`: show the error and the log |
| 2. Resume | `exit=0` and the same number as run 1 | The CLI doesn't keep context when resuming: rounds must include the previous output (for `custom`, leave `resume_args` empty) |
| 3. Permissions | `exit=0` (or `5` for Cursor when it answered empty), saying both actions were denied, and no file | `exit=4`: the agent wrote. Stop, show the user, and don't go on until it's solved |

Show the user the three outputs, each run's duration (in its `.meta.json`) and the "Live progress" line of the first, so they see the log. For reference: with a high-reasoning model, run 1 takes about 3 minutes and the others under one.

## 7. Tell the user how it works

- After proposing a change, `/specbaton-reviewer:plan` runs on its own. Claude reviews the plan, sends the agent only verifiable observations (up to 3 rounds) and saves `plan.md`.
- When the draft pull request opens, `/specbaton-reviewer:code` runs on its own. The user decides each finding in the triage (fix, dismiss or postpone); Claude fixes only what's marked and fills in the responses.
- After the fixes, `/specbaton-reviewer:code <change> validate`. The review closes with `pass`, or moves to `needs-decision` when round 3 still has open findings or the agent insists twice on something refuted.
- When the team comments on the pull request, `/specbaton-reviewer:code <change> learn` turns what the agent missed into improvements to the review skill, with the user's approval. `SOURCES.md`'s detection rate says whether the skill improves.
- Switching reviewer (for example from Cursor to Antigravity) only changes `reviewer.cli` and the models in `.claude/specbaton.json`. The prompts and the skill stay the same.
- Live logs go to `~/.specbaton-runs/<root name>/`, outside the workspace, and can be deleted at any time.
