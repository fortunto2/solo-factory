# Agent & Skill Routing

Invoke the matching agent or skill when the user's request matches a signal below.

## Task → Route

| Signal | Route |
|--------|-------|
| research, competitors, market, pain points | `researcher` agent |
| architecture, dependencies, how does X work | `code-analyst` agent |
| validate idea, score, go/kill, PRD | `/solo:validate` skill |
| grill me, прожарь, stress-test this plan, punch holes | `/solo:grill` |
| diagnose, debug this, throwing, failing, flaky, slow, почему падает | `/solo:diagnose` |
| plan, spec, implementation plan | `/solo:plan` |
| build, implement, execute, ship | `/solo:build` |
| review, quality check, ready to ship | `/solo:review` |
| scaffold, new project, set up | `/solo:scaffold` |
| launch, GTM, go-to-market, channels | `/solo:launch` |
| first customers, early adopters, design partners, prospect list | `/solo:customer-finder` |
| privacy policy, terms, legal, GDPR | `/solo:legal` |
| pipeline, full automation | `/solo:pipeline` |

## File Context → Next Step

| Marker | Likely next step |
|--------|-----------------|
| No `CLAUDE.md` in CWD | `/solo:scaffold` |
| `docs/research.md` but no `docs/prd.md` | `/solo:validate` |
| `docs/prd.md` but no src files | `/solo:scaffold` |
| `docs/plan/*/plan.md` with open tasks | `/solo:build` |
| deployed but no `docs/launch-strategy.md` | `/solo:launch` |
| no `legal/privacy-policy.md` | `/solo:legal` |

## Pipeline Order

`/research` → `/validate` → `/scaffold` → `/setup` → `/plan` → `/build` → `/deploy` → `/launch` → `/review`

Skip stages already done (check file markers above).

## Primitives (reachable from inside any stage)

| Primitive | Reach for it when |
|-----------|-------------------|
| `/solo:grill` | The blocker is a *decision*, not information — sharpen it one question at a time before planning or building |
| `/solo:diagnose` | Something is broken and the cause is unknown — build the feedback loop before touching code |
