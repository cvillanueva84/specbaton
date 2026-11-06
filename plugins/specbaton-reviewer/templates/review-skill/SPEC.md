# {{SKILL_NAME}}: spec

## Purpose
Catch, before the team's reviewers do, what they keep flagging on our PRs. The skill is embedded whole in the reviewer agent's prompt, so `SKILL.md` has no external references and stays under 12 KB.

## Origin
{{ORIGIN}}

## How it changes
Through the learning step of `/specbaton-reviewer:code <change> learn`: every human finding is classified (`caught`, `caught-dismissed`, `missed-covered`, `missed-uncovered`, `out-of-scope`), the evidence goes to `references/evidence/`, and each `missed-*` becomes a proposed diff to `SKILL.md` that the owner approves. A new pass needs the pattern in two or more PRs, or a High finding.

## Known limitations
- The reviewer agent can't run code: what only a run would settle is marked **unverified**, with the command that would settle it.
- The reviewer agent doesn't read the tracker: Claude compares the ticket with the PR text during triage.
- Code loaded at runtime from outside the repos (third-party scripts, remote config) isn't in the workspace.
