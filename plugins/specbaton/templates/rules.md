<!-- specbaton:rules -->
## Memory between sessions (specbaton)

- The chat keeps nothing that must survive: state and decisions live in files under `{{MEM}}`.
- `{{MEM}}/NOW.md` is the index of active epics and changes. Each change's state is in `{{STATUS}}`.
- Decisions live in `{{MEM}}/decisions/` as ADRs. RFCs and specs are the starting point: when an ADR contradicts them, the ADR wins.
- A hook asks you to resume (`/specbaton:resume-work`) before replying in a new session; I can also ask for it. To close a session, or when the context gets heavy: `/specbaton:handoff`. When I say goodbye, run the full handoff before you say goodbye, even if I don't ask; leave the files written and the commit for when the work resumes.
- One change per session. If we switch topics, run `/specbaton:handoff` first.

## Decisions

- Before proposing architecture, libraries or patterns, check the index in `{{MEM}}/decisions/` and open the ADRs of the units involved.
- Don't contradict an ADR with `status: accepted`. If you think it should change, cite it, explain what changed and propose a new ADR that supersedes it. Don't implement until I accept it.
- If the code or a requirement contradicts an ADR or the spec, stop and report it instead of resolving it on your own.
- When we make a decision in the conversation, propose the ADR right then, not at the end of the session.
- Decisions about the workflow itself (commands, rules, prompts) are ADRs too, with `repos: [workspace]`.

## How I work

- The memory layer's commits are proposed by `/specbaton:handoff` and made only with my approval.
- Don't commit, push or open pull requests in the code without explicit approval for that case.
