## Ticket cycle (specbaton)

### Implement (test-first)
- For tasks that change behavior, write or adjust the test first and run it: it must fail for the expected reason. A test that never failed hasn't shown it can fail. Tasks that only touch configuration, copy or docs are exempt.
- Pause and ask me when a task is unclear, when the implementation reveals a design problem (propose updating the change's artifacts), or when the fix contradicts an ADR or the spec.
- Before editing a unit, read its instructions (README, `AGENTS.md`, `.github/instructions/`) and respect its style, its public APIs and its test setup.

### Local gate before the pull request
- Before opening or updating a pull request, run from each touched unit's folder the commands in `{{MEM}}/docs/reference/gates.md`: tests, lint and type-check. Everything must be green.
- When a unit already carries lint or type-check errors, only the ones on lines the diff touches count.
- Evidence before claims: report the result with its output (for example "485 passing, lint clean"). If something fails, say so.

### Pull request text
- Write the text in `{{MEM}}/pull-request/<TICKET>-<description>.pr.md`, in {{TEAM_LANG}}, following the repo's template when it has one (`.github/pull_request_template.md`).
- Two parts: **What changes**, in short bullets; and **Notes for reviewers**: where to start, the non-obvious decisions, the tests and their result, and the validation done. When they exist, two more bullets: **Trade-offs** (what was accepted knowingly, with its basis or saying it has none) and **Needs your call** (what the reviewer or the business decides).
- Explain decisions in the text itself, without citing ADRs (they live outside the repo) or other agents' reviews.
- Show me the text before opening the pull request.

### Permissions
| Action | Claude | Me |
| --- | --- | --- |
| Commit in the memory layer | Proposed by `/specbaton:handoff`, made with my approval | Approve |
| Commit and push on a draft pull request's branch and its fixes | <ADAPT: yes, authorized / with my approval> | — |
| Open a pull request | Draft only | — |
| Mark a pull request ready | No | Yes |
| Merge to `{{INTEGRATION_BRANCH}}` or production | No | Yes |
| Post comments on GitHub or {{TRACKER}} | After showing me the draft | Approve |
| Accept an ADR | No: proposes it | Yes |
| Hand over secrets | Never through the chat | — |
- Commits follow the repo's style and never use `--no-verify`.
- A pull request needs {{APPROVALS}} approvals. When reporting a pull request's status, count the ones it has and say how many are missing.

### Stacked branches
- A branch that depends on another starts from that branch, not from `{{INTEGRATION_BRANCH}}`.
- They merge layer by layer, waiting for each deploy, and always with a merge commit: with stacked branches, squashing duplicates commits.

### Cross-cutting rules
- Languages: your replies and the memory layer's files are in my language. What's for the team (pull requests, comments, tracker) is in {{TEAM_LANG}}.
- Personal data: logs carry identifiers only. Personal data never goes into the tracker or into text for the team.
- Configuration that already works isn't moved or rotated as part of a feature. Changes are additive.
