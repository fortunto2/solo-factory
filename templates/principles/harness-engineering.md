# Harness Engineering — Development in the Age of Agents

Synthesis of three key sources: OpenAI experiment (Ryan Lopopolo), Mitchell Hashimoto's adoption journey, and Birgitta Böckeler's analysis (Thoughtworks/Martin Fowler).

---

## Definition

**Harness Engineering** — the discipline of designing environments, tools, and feedback loops that enable AI agents to do reliable work. Humans steer, agents execute.

> "When the agent struggles, we treat it as a signal: identify what is missing — tools, guardrails, documentation — and feed it back into the repository." — OpenAI

> "Harness engineering: anytime an agent makes a mistake, you take the time to engineer a solution such that the agent never makes that mistake again." — Mitchell Hashimoto

---

## Three Components of Harness (Böckeler/Fowler)

### 1. Context Engineering — context as code

Continuously improved knowledge base **in the repository**:

- **AGENTS.md / CLAUDE.md** — map, not encyclopedia (~100 lines, links deeper)
- **docs/** — structured system of records: design docs, execution plans, product specs
- **Dynamic context** — observability (logs, metrics, traces), browser via CDP, screenshots
- **Progressive disclosure** — agent starts with a small stable entry point and knows where to look next

```
AGENTS.md           <- table of contents (~100 lines)
ARCHITECTURE.md     <- domain and layer map
docs/
├── design-docs/    <- design decisions (with verification status)
├── exec-plans/     <- active and completed plans
│   ├── active/
│   └── completed/
├── product-specs/  <- product specifications
├── references/     <- llms.txt for dependencies
├── QUALITY_SCORE.md
├── RELIABILITY.md
└── SECURITY.md
```

**Key OpenAI insight:** One big AGENTS.md is an **anti-pattern**. Pollutes context, rots instantly, impossible to validate mechanically.

### 2. Architectural Constraints — boundaries + freedom

Hard boundaries + freedom inside:

- **Layered domain architecture**: Types -> Config -> Repo -> Service -> Runtime -> UI
- **Directed dependencies** — validated by custom linters
- **Parse at the boundary** — data validated on entry (Zod, Pydantic)
- **Structural tests** (ArchUnit-style) — check dependency graphs
- **Taste invariants** — structured logging, naming conventions, file size limits

> "Enforce boundaries centrally, allow autonomy locally." — OpenAI

### 3. Garbage Collection — fighting entropy

Agents replicate existing patterns, including bad ones. Without GC, code degrades.

- **Golden principles** — opinionated rules encoded in the repository
- **Recurring cleanup agents** — background tasks scanning for deviations
- **Doc-gardening agent** — finds stale documentation, opens fix-up PRs
- **Quality grades** — each domain has a score tracked over time
- **Rule:** tech debt as credit — better to pay continuously in small installments

OpenAI: previously 20% of time (Fridays) went to manual cleanup of "AI slop" — doesn't scale.

---

## 6 Steps of Adoption (Mitchell Hashimoto)

### Step 1: Drop the chatbot
Chat interface (ChatGPT, Gemini web) is a dead end for serious development. **Use an agent** — LLM that can read files, run programs, make HTTP requests.

### Step 2: Reproduce your own work
Do a task manually, then make the agent do the same with the same quality. Painful, but builds expertise:
- Break sessions into separate, clear, actionable tasks
- Separate planning from execution
- Give the agent verification tools — it will self-correct

**Negative space value:** understanding when **not** to use the agent saves the most time.

### Step 3: End-of-day agents
Block 30 minutes at end of day for agent runs. Don't try to do more during work hours — do more in **off hours**.

What works:
- Deep research sessions — library reviews, competitor analysis
- Parallel agents on unclear ideas — illuminate unknown unknowns
- Issue/PR triage — agent with `gh` CLI compiles report (but does NOT respond)

### Step 4: Outsource slam dunks
Tasks where agent almost certainly succeeds — let it run in background. **Turn off desktop notifications** — human decides when to context-switch.

> "Turn off agent desktop notifications. Context switching is expensive."

### Step 5: Engineer the Harness
Every agent mistake -> engineering solution so it never happens again. Two mechanisms:

1. **AGENTS.md / CLAUDE.md** — for simple problems (wrong commands, wrong APIs)
2. **Programmatic tools** — scripts, screenshots, filtered tests

> "Each line in that file is based on a bad agent behavior, and it almost completely resolved them all."

### Step 6: Always have an agent running
Goal: agent always running. If not — ask: "what could the agent be doing for me?"

Preference: slow, thoughtful models (Amp deep mode / GPT-5.2-Codex) — 30+ min per task, but high quality. One agent, not parallel.

---

## OpenAI Experiment: Numbers

| Metric | Value |
|--------|-------|
| Engineers | 3 -> 7 |
| Duration | 5 months |
| Code | ~1M lines |
| Pull requests | ~1,500 |
| PR/engineer/day | 3.5 |
| Human code | 0 lines |
| Estimated speedup | ~10x |
| Max single Codex run | 6+ hours |

### Autonomy Levels (achieved)

One prompt -> agent can:
1. Validate codebase state
2. Reproduce bug
3. Record demo video
4. Implement fix
5. Validate fix via UI
6. Record second video
7. Open PR
8. Respond to feedback (agent and human)
9. Detect and fix build failures
10. Escalate to human only when judgment needed
11. Merge

### Tools for Legibility

- **App per worktree** — isolated instance per change
- **Chrome DevTools Protocol** -> DOM snapshots, screenshots, navigation
- **Local observability stack** — LogQL, PromQL, TraceQL (ephemeral per worktree)
- **Custom linters** — errors contain remediation instructions for agent
- **Ralph Wiggum Loop** — agent reviews its own changes, requests additional review, iterates until all satisfied

---

## Practical Recommendations

1. **CLAUDE.md as table of contents** — keep ~100 lines with links deeper
2. **docs/ as system of record** — design docs, execution plans, quality scores
3. **Custom linters with agent-friendly messages** — remediation instructions right in the error
4. **Structural tests** — check dependency direction, file sizes
5. **Doc-gardening** — periodic agent for cleaning stale docs
6. **End-of-day agents** — issue triage, research, background tasks
7. **Harness per project** — each project = its own CLAUDE.md + docs/ + linters
8. **"Boring" tech** — prefer stable, composable technologies

### Harness Health Checklist

- [ ] AGENTS.md/CLAUDE.md — table of contents, not encyclopedia?
- [ ] Pre-commit hooks exist and work?
- [ ] Custom linters with remediation instructions?
- [ ] Architectural constraints checked automatically?
- [ ] Documentation versioned with code?
- [ ] Entropy fighting mechanism exists (GC agents, quality grades)?
- [ ] Agent can self-validate its work (tests, screenshots)?

### Anti-Patterns

- One giant AGENTS.md ("graveyard of stale rules")
- Knowledge in Slack/Google Docs (invisible to agent)
- Micromanaging implementation instead of enforcing boundaries
- Manual cleanup of "AI slop" instead of automation
- Trying to "generate anything" — constraints are multipliers, not brakes

---

## Predictions (Böckeler/Fowler)

1. **Harness as new service templates** — organizations will create harness templates for main stacks
2. **Tech stack convergence** — AI pushes toward fewer stacks, "AI-friendliness" as selection criterion
3. **Topology convergence** — project structures will become more standard (stable data shapes, modular boundaries)
4. **Two worlds** — greenfield with harness vs. retrofit on legacy (different approaches)

---

*Sources:*
- *[OpenAI — Harness Engineering](https://openai.com/index/harness-engineering/) (Ryan Lopopolo, 2026)*
- *[Mitchell Hashimoto — My AI Adoption Journey](https://mitchellh.com/writing/my-ai-adoption-journey) (Feb 2026)*
- *[Martin Fowler — Harness Engineering](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) (Birgitta Böckeler, Feb 2026)*
