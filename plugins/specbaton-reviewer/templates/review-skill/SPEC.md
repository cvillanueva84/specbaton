# {{SKILL_NAME}}: spec

## Purpose
Catch, before the team's reviewers do, what they keep flagging on our PRs. The skill is embedded whole in the reviewer agent's prompt, so `SKILL.md` has no external references and stays under 12 KB.

## Origin
{{ORIGIN}}

## How it changes
Through the learning step of `/specbaton-reviewer:code <change> learn`: every human finding is classified (`caught`, `caught-dismissed`, `missed-covered`, `missed-uncovered`, `out-of-scope`) against both the reviewer agent and the reviewer pass, and the evidence goes to `references/evidence/`. Each `missed-*`, and each `out-of-scope` already seen in another PR, becomes a lesson in `references/lessons.md` first, which the reviewer pass applies. `SKILL.md` changes only for a pattern seen in two or more PRs, a High one, or a pass that gave false positives twice: sharpen an existing pass or add an example, and add a new pass only when none covers it. The owner approves every change.

## Known limitations
- The reviewer agent can't run code: what only a run would settle is marked **unverified**, with the command that would settle it. In `/specbaton-reviewer:code`, the reviewer pass (Claude, with only what the team sees) runs the libraries, so it covers this gap and the next one.
- The reviewer agent doesn't read the tracker: Claude compares the ticket with the PR text during triage, and the reviewer pass reads the ticket when a tracker is connected.
- Code loaded at runtime from outside the repos (third-party scripts, remote config) isn't in the workspace.
