# Routing

Prompt shape → skill is decided by the profile's `UserPromptSubmit` hook, not by a
table in this file: `harness/routing.json` for the personal profile, `hooks/hook.py`
for a client profile (see harness-core). The hook injects "load `/solo:research`"
when the prompt looks like research, so nothing here has to be remembered.

What the hook cannot see is the state of the directory. Pick the next stage from it:

| Marker | Likely next step |
|--------|-----------------|
| No `CLAUDE.md` in CWD | `/solo:scaffold` |
| `docs/research.md` but no `docs/prd.md` | `/solo:validate` |
| `docs/prd.md` but no src files | `/solo:scaffold` |
| `docs/plan/*/plan.md` with open tasks | `/solo:build` |
| deployed but no `docs/launch-strategy.md` | `/solo:launch` |
| no `legal/privacy-policy.md` | `/solo:legal` |

Pipeline order: `/research` → `/validate` → `/scaffold` → `/setup` → `/plan` → `/build`
→ `/deploy` → `/launch` → `/review`. Skip stages already done.

Primitives, reachable from inside any stage: `/solo:grill` when the blocker is a
decision, not information; `/solo:diagnose` when something is broken and the cause is
unknown.
