# Agent & Skill Routing

Invoke the matching agent or skill when the user's request matches a signal below.

## Task → Route

| Signal | Route |
|--------|-------|
| research, competitors, market, pain points | `researcher` agent |
| architecture, dependencies, how does X work | `code-analyst` agent |
| validate idea, score, go/kill, PRD | `/solo:validate` skill |
| plan, spec, implementation plan | `/solo:plan` |
| build, implement, execute, ship | `/solo:build` |
| review, quality check, ready to ship | `/solo:review` |
| scaffold, new project, set up | `/solo:scaffold` |
| pipeline, full automation | `/solo:pipeline` |

## File Context → Next Step

| Marker | Likely next step |
|--------|-----------------|
| No `CLAUDE.md` in CWD | `/solo:scaffold` |
| `docs/research.md` but no `docs/prd.md` | `/solo:validate` |
| `docs/prd.md` but no src files | `/solo:scaffold` |
| `docs/plan/*/plan.md` with open tasks | `/solo:build` |

## Pipeline Order

`/research` → `/validate` → `/scaffold` → `/setup` → `/plan` → `/build` → `/deploy` → `/review`

Skip stages already done (check file markers above).
