# Harness Engineering Principles

Principles for AI-agent-first development. Injected into project CLAUDE.md and referenced by /plan.

Sources: OpenAI (Ryan Lopopolo), Mitchell Hashimoto, Birgitta Böckeler (Thoughtworks).

---

## Core Idea

Build environments that make agents succeed, not just prompts that hope they do. When agent struggles — fix the harness, not the prompt.

## Three Pillars

### 1. Context Engineering — repo as system of record

- CLAUDE.md = table of contents (~100 lines), NOT encyclopedia
- `docs/` = structured knowledge base: design docs, specs, plans, quality scores
- Everything agent needs must be in-repo (Slack/Docs = invisible to agent)
- Progressive disclosure: small entry point → pointers to deeper sources

### 2. Architectural Constraints — boundaries + freedom

- Enforce module boundaries mechanically (custom linters, structural tests)
- Parse/validate data at boundaries (Zod, Pydantic)
- Naming conventions, file size limits — lint with remediation instructions
- "Enforce boundaries centrally, allow autonomy locally"

### 3. Garbage Collection — fight entropy

- Agents replicate existing patterns, including bad ones
- Recurring cleanup agents scan for deviations
- Doc-gardening: find stale docs, open fix-up PRs
- Quality grades per domain, tracked over time
- Tech debt = high-interest loan — pay continuously

## Harness Health Checklist

- [ ] CLAUDE.md is a map, not a manual
- [ ] Pre-commit hooks active and useful
- [ ] Custom linters with agent-friendly error messages
- [ ] Architectural constraints enforced automatically
- [ ] Documentation versioned with code
- [ ] Entropy fighting mechanism exists (GC agents, quality grades)
- [ ] Agent can self-validate (tests, screenshots, health checks)

## Agent Legibility Rules

- App bootable per worktree (isolated instances per change)
- Observability stack accessible to agent (logs, metrics, traces)
- Custom lint errors include remediation instructions
- "Boring" tech preferred — stable, composable, well-represented in training data
- Dependencies fully internalized in-repo when possible

## Anti-Patterns

- One giant AGENTS.md (context pollution, instant rot)
- Knowledge in Slack/Docs (invisible to agent)
- Micromanaging implementation instead of enforcing boundaries
- Manual "AI slop" cleanup instead of automation
- No verification tools — agent can't check its own work
