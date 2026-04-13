---
type: methodology
title: "Harness Engineering — Development in the Age of Agents"
description: "Design environments where AI agents do reliable work. Three components: context engineering, architectural constraints, feedback loops."
created: 2026-02-07
tags: [harness, agents, methodology, context-engineering, ai]
course_module: 5
course_order: 1
publish: true
publish_as: post
source_path: "1-methodology/harness-engineering.md"
---

# Harness Engineering — Development in the Age of Agents

Synthesis of three key sources: OpenAI experiment (Ryan Lopopolo), Mitchell Hashimoto's adoption journey, and Birgitta Böckeler's analysis (Thoughtworks/Martin Fowler).

---

## Definition

**Harness Engineering** — the discipline of designing environments, tools, and feedback loops so AI agents do reliable work. Humans steer, agents execute.

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
- **Directed dependencies** — custom linters validate direction
- **Parse at the boundary** — validate data on entry (Zod, Pydantic)
- **Structural tests** (ArchUnit-style) — check dependency graphs
- **Taste invariants** — structured logging, naming conventions, file size limits

> "Enforce boundaries centrally, allow autonomy locally." — OpenAI

### 3. Garbage Collection — fighting entropy

Agents replicate existing patterns, including bad ones. Without GC, code degrades.

- **Golden principles** — opinionated rules living in the repository
- **Recurring cleanup agents** — background tasks scanning for deviations
- **Doc-gardening agent** — finds stale documentation, opens fix-up PRs
- **Quality grades** — each domain has a score tracked over time
- **Rule:** tech debt as credit — better to pay continuously in small installments

OpenAI: previously 20% of time (Fridays) went to manual cleanup of "AI slop." Doesn't scale.

---

## 6 Steps of Adoption (Mitchell Hashimoto)

### Step 1: Drop the chatbot
Chat interface (ChatGPT, Gemini web) is a dead end for serious development. **Use an agent**: LLM that reads files, runs programs, makes HTTP requests.

### Step 2: Reproduce your own work
Do a task manually, then make the agent do the same with the same quality. Painful, but builds expertise:
- Break sessions into separate, clear, actionable tasks
- Separate planning from execution
- Give the agent verification tools. It will self-correct

**Negative space value:** understanding when **not** to use the agent saves the most time.

### Step 3: End-of-day agents
Block 30 minutes at end of day for agent runs. Don't try to do more during work hours. Do more in **off hours**.

What works:
- Deep research sessions — library reviews, competitor analysis
- Parallel agents on unclear ideas — illuminate unknown unknowns
- Issue/PR triage — agent with `gh` CLI compiles report (but does NOT respond)

### Step 4: Outsource slam dunks
Tasks where agent almost certainly succeeds: let it run in background. **Turn off desktop notifications.** Human decides when to context-switch.

> "Turn off agent desktop notifications. Context switching is expensive."

### Step 5: Engineer the Harness
Every agent mistake -> engineering solution so it never happens again. Two mechanisms:

1. **AGENTS.md / CLAUDE.md** — for simple problems (wrong commands, wrong APIs)
2. **Programmatic tools** — scripts, screenshots, filtered tests

> "Each line in that file is based on a bad agent behavior, and it almost completely resolved them all."

### Step 6: Always have an agent running
Goal: agent always running. If not, ask: "what could the agent be doing for me?"

Preference: slow, thoughtful models (Amp deep mode / GPT-5.2-Codex). 30+ min per task, but high quality. One agent, not parallel.

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
- Trying to "generate anything." Constraints are multipliers, not brakes

---

## Predictions (Böckeler/Fowler)

1. **Harness as new service templates** — organizations will create harness templates for main stacks
2. **Tech stack convergence** — AI pushes toward fewer stacks, "AI-friendliness" as selection criterion
3. **Topology convergence** — project structures will become more standard (stable data shapes, modular boundaries)
4. **Two worlds** — greenfield with harness vs. retrofit on legacy (different approaches)

---

## Further Reading

Curated from [awesome-harness-engineering](https://github.com/walkinglabs/awesome-harness-engineering). Grouped by actionability for solo-factory workflow.

### Context & Memory (improve pipeline context efficiency)

- [Manus — Context Engineering Lessons](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus) — KV-cache locality, tool masking, filesystem memory, keeping useful failures in-context
- [Anthropic — Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — context window as working memory budget
- [HumanLayer — Context-Efficient Backpressure](https://www.humanlayer.dev/blog/context-efficient-backpressure) — prevent agents from burning context on noisy/low-value work
- [OpenHands — Context Condensation](https://openhands.dev/blog/openhands-context-condensensation-for-more-efficient-ai-agents) — bounded conversation memory preserving goals, progress, failing tests
- [HumanLayer — Advanced Context Engineering](https://www.humanlayer.dev/blog/advanced-context-engineering) — reducing context drift, easier session resume

### Long-Running Agents (improve /build, /pipeline)

- [Anthropic — Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — initializer agents, feature lists, init.sh, self-verification, handoff artifacts
- [Anthropic — Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — task state and evaluator design for app generation
- [Inngest — Agent Needs a Harness, Not a Framework](https://www.inngest.com/blog/your-agent-needs-a-harness-not-a-framework) — state, retries, traces, concurrency as first-class infra

### Agent Design Patterns (audit skills against)

- [12 Factor Agents](https://www.humanlayer.dev/blog/12-factor-agents) — explicit prompts, state ownership, clean pause-resume
- [12-Factor AgentOps](https://www.12factoragentops.com/) — context discipline, validation, reproducible workflows
- [AGENTS.md spec](https://github.com/agentsmd/agents.md) — lightweight open format for repo-local agent instructions
- [GitHub Spec Kit](https://github.com/github/spec-kit) — spec-driven development toolkit

### Evals & Quality (improve /retro, /skill-audit, /review)

- [Anthropic — Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) — what to measure when agents have many trajectories
- [OpenHands — Evaluating Agent Skills](https://openhands.dev/blog/evaluating-agent-skills) — bounded tasks, deterministic verifiers, no-skill baselines
- [LangChain — Improving Agents with Harness Engineering](https://blog.langchain.com/improving-deep-agents-with-harness-engineering/) — evidence that harness changes alone move benchmarks
- [OpenHands — Learning to Verify AI-Generated Code](https://openhands.dev/blog/20260305-learning-to-verify-ai-generated-code) — trajectory critics for reranking, early stopping, review-time QC

### Safe Autonomy (improve sandboxing, guardrails)

- [Anthropic — Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing) — reducing approval friction without losing control
- [OpenHands — Mitigating Prompt Injection](https://openhands.dev/blog/mitigating-prompt-injection-attacks-in-software-agents) — confirmation mode, analyzers, hard policies
- [HumanLayer — Writing a Good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md) — durable repo-local instructions

### Multi-Agent (improve agent-teams, /swarm)

- [Anthropic — Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) — separation of roles, structured coordination
- [LangChain — Agent Frameworks vs Runtimes vs Harnesses](https://blog.langchain.com/agent-frameworks-runtimes-and-harnesses-oh-my/) — what belongs where

---

*Sources:*
- *[OpenAI — Harness Engineering](https://openai.com/index/harness-engineering/) (Ryan Lopopolo, 2026)*
- *[Mitchell Hashimoto — My AI Adoption Journey](https://mitchellh.com/writing/my-ai-adoption-journey) (Feb 2026)*
- *[Martin Fowler — Harness Engineering](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) (Birgitta Böckeler, Feb 2026)*
- *[awesome-harness-engineering](https://github.com/walkinglabs/awesome-harness-engineering) — curated list*
