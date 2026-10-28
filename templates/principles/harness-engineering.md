---
type: methodology
title: "Harness Engineering — Development in the Age of Agents"
description: "Design environments where AI agents do reliable work: context engineering, architectural constraints, garbage collection, and sensors that check the agent's work after it acts."
created: 2026-02-07
updated: 2026-10-27
tags: [harness, agents, methodology, context-engineering, ai]
course_module: 4
course_order: 1
publish: true
publish_as: post
source_path: "1-methodology/harness-engineering.md"
---

# Harness Engineering — Development in the Age of Agents

Synthesis of three sources: the OpenAI experiment (Ryan Lopopolo), Mitchell Hashimoto's adoption journey, and Birgitta Böckeler's analysis (Thoughtworks/Martin Fowler). The sensors section is newer: it comes from running this harness in solo-factory.

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

Every always-loaded line is resent with every request. Moving the reasoning out of this repo's rules into a doc the agent opens on demand took them from 37.7 KB to 16.0 KB. A rules file states rules; how you arrived at one belongs elsewhere.

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
- **Queues call the gated tool.** A batch or queue script runs the project's own tool
  for each step, never a re-implementation of its steps. A hand-rolled outro join in a
  queue script made 48 kHz silence for a 96 kHz film and drifted the audio clock by
  1.4 s; the project tool already took the sample rate from the film, and its checks
  were what the copy skipped.
- **Recurring cleanup agents** — background tasks scanning for deviations
- **Doc-gardening agent** — finds stale documentation, opens fix-up PRs
- **Quality grades** — each domain has a score tracked over time
- **Rule:** tech debt as credit — better to pay continuously in small installments

OpenAI: previously 20% of time (Fridays) went to manual cleanup of "AI slop." Doesn't scale.

---

## Feedback Loops — the agent's only ground truth

An agent cannot see. Everything it believes about the running system comes through a loop: a command it runs that returns a verdict. The **tightness** of that loop sets the ceiling on everything else — context engineering and constraints only decide what the agent tries, the loop decides whether it finds out it was wrong.

A loop is **tight** when it is:

- **Red-capable** — it can fail on the thing you care about, and you have watched it fail. A loop that has only ever been green proves nothing; it may not reach the code path at all.
- **Deterministic** — same verdict every run. Pin time, seed RNG, isolate the filesystem, freeze the network.
- **Fast** — seconds, not minutes. A 30-second flaky loop is barely better than none; a 2-second deterministic one is a superpower.
- **Agent-runnable** — runs unattended. A human in the loop is a last resort, and even then driven by a script so answers come back structured.

**Build the loop before the work, not after.** The pull is always to read code and form a theory first — that's the failure mode. Whatever the task, name the command that will tell you whether it worked, run it once to see its output, and only then start.

**Treat the loop as a product.** Once you have one, tighten it: cache setup, skip unrelated init, narrow scope, assert the specific symptom instead of "didn't crash". The loop gets used hundreds of times; two seconds saved compounds.

**When it can't be deterministic**, raise the reproduction rate instead of chasing a clean repro: loop the trigger 100×, parallelise, add stress, inject sleeps. A 50%-flake is debuggable; 1% is not.

The catalogue of loop constructions — failing test, curl script, CLI+snapshot diff, headless browser, trace replay, throwaway harness, fuzz loop, bisect harness, differential run, HITL script — lives in `skills/diagnose/SKILL.md` Phase 1, ordered by preference. It's written for bugs but the constructions are general: any task where you need a verdict picks from the same list.

**Loops elsewhere in the factory:** TDD's red→green is a loop with a seam agreed up front (`skills/build/references/tdd-seams.md`). `make integration` is the CLI-first loop over business logic. `/review` is the slow loop over a whole change. `/retro` → `~/.solo/evolution.md` is the loop over the factory itself. The sensors below are the loop that runs on every turn without anyone asking for it. When a stage feels unreliable, ask what its loop is and whether it can go red.

---

## Sensors: checking the work after the agent acts

Everything in the three components is **feedforward**: it steers the agent before it acts. Most of solo-factory is feedforward too: 57 skills, 2 agents, rules, stack templates. Böckeler's follow-up ([Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html), April 2026) names the gap. Feedback alone gives an agent that repeats mistakes; feedforward alone gives one that encodes rules and never learns whether they worked.

Sensors are the feedback half: they observe after the agent acts, so a mistake gets corrected before it reaches you. The contract is `rules/harness-sensors.md`, the reasoning and measurements are in `docs/harness-sensors.md`.

### Three placements

| Where | What runs | Budget |
|---|---|---|
| Every Edit/Write | Syntax of the one file just written | <1s |
| End of turn (Stop hook) | `solo-verify --full`: lint, types, tests | <120s |
| Commit (pre-commit) | Formatting, repo-specific gates | seconds |

**Every edit gets syntax only**, because of noise rather than speed. Mid-refactor, the agent has changed one file and not yet reached the files that depend on it. A type checker at that moment floods it with errors from code it has not touched yet, and the agent reverts good work to silence them. Measure false positives before moving a sensor earlier: a dead-link checker that flags 73% of links, about 3% of them confirmed by hand, gets deleted within a week.

**The end of the turn is where meaning gets checked**, because cross-file meaning is only well-defined once the agent thinks it is done. This gate blocks: if the receipt is red, the turn cannot end, so "I finished" stops being a claim the agent makes about itself. FAIL always blocks. UNKNOWN blocks once per input, and a session that changed nothing is never blocked, however red the tree it inherited.

### Published promises

Every sensor states what it checks, in a table that tests pin. `pytest` must run **and collect more than 0 tests**. `limits` fails a function over 150 lines or a module over 1000, unless the file declares an exemption with a reason. `shellcheck` must be clean at severity warning and above, and the receipt says that threshold is ours. Written down, a weakened threshold reads as a diff against a stated promise instead of an invisible edit.

Editing the harness is loud, not forbidden: a change to tests or lint configs prints `HARNESS TOUCHED` with a sha256. Sometimes the rule is what is wrong; in one agent's measured sample, the correct repair was the rule 3 times out of 5.

### What a receipt may say

`solo-verify` prints a receipt, never a bare colour, and each of its rules comes from a false green that happened:

- **"ok" alone is forbidden.** Every run prints what `ran`, what was `skipped` and why, and which changed files stayed `UNCHECKED`. A green that does not say what it refused to look at is indistinguishable from never having looked.
- **Zero scope is UNKNOWN, not PASS.** Nothing checked exits 2. A test run that collects 0 tests fails, because "nothing ran" must not read as "nothing failed".
- **An absent tool gives PARTIAL, never PASS.** An outside agent found the same file with two ruff violations returning FAIL where ruff was installed and PASS where it was not: the absence of a tool reported as the absence of problems.
- **Never accept a zero from an instrument you have not seen produce a non-zero.** Feed it an input whose answer you know first. A mutation-testing "trap" was once published here on a grep that found zero caught mutants; that run's own `caught.txt` held 21, and the trap was retracted.

The ruff case, reproduced on a scratch repo with ruff kept off PATH (excerpt):

```
VERIFY PARTIAL (fast, 0.19s)
  ran:      syntax=pass {"parsed":1,"broken":0,"python":"3.9"}, limits=pass {"files":1}
  INCOMPLETE — these sensors applied but could not run: ruff
    A green result here means 'nothing found by what ran', not 'clean'.
```

With ruff on PATH the same file gives `VERIFY FAIL`, exit 1. PARTIAL exits 0 on purpose: a tool missing on someone else's machine should not fail their build, so the honesty is in the word.

### What green does not mean

A green receipt means syntax, lint, types and the suite passed, never that the change is correct. `make blind-spots` plants one known defect at a time, each one a competent reviewer would block a PR for, and records whether a finding names it: **11 of 24 caught** across Python, Go and Rust. The 13 misses are published, among them an off-by-one loop bound, a test that asserts nothing, and a hardcoded credential missed in all three languages.

A sensor written by whoever writes the code is blind in the same places, so a solo harness needs an outside reader on purpose: a second model on the diff, an adversarial pass, another agent. Feedforward needs the same check: `claude plugin eval` runs each case with and without the plugin, and only that delta measures what a skill added.

---

## What a loop costs is part of its design

A loop nobody runs guards nothing, and cost is what decides whether it gets
run. Five rules, each learned by paying for the opposite:

**Split hooks by cost, not by importance.** A pre-commit hook that runs the
whole test suite takes minutes, so it gets bypassed with `--no-verify`, and a
bypassed hook checks nothing. Put seconds-long tripwires on commit and the
suites at the end of the turn or on push. The tripwires are worth writing by
hand: one per bug that actually shipped, phrased as "this file must still
contain that guard".

**Measure per test, not per suite.** A suite's total time names the suite, not
the culprit. Trimming what looked like the expensive loop in one suite saved
three seconds; the real cost was a different test in the same file, and one
sort over per-test timings found it in a minute:

```bash
<test command> 2>&1 | grep -E "passed|failed" | sort -t'(' -k2 -rn
```

**A test guards a code path, not an amount of data.** The same route through
the system is exercised by three fixtures or by nine; the extra six buy
nothing but wall-clock. Fixture volume is a dial, and its default should be
the smallest value that still reaches the path.

**Repetition is a deliberate act, not a default.** Tests that repeat an
operation to catch a flake are worth having and worth switching off: put the
count behind an environment variable, default it to one, and raise it before a
release or while chasing the flake. Derive the assertions from the fixture too
— a hardcoded expectation ("the output is at least 25 seconds") turns the next
deliberate trim red for the wrong reason.

**Verify parallelism instead of assuming it.** Test runners that parallelise by
cloning a whole environment can be slower than serial when the work is not
CPU-bound: measured 11m32s against 3m on one iOS suite. And inside a test that
measures duration, concurrency destroys the very number being asserted.

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

Both mechanisms act after a mistake has happened once. The sensors above add a third that checks the work in the same turn it was made.

### Step 6: Always have an agent running
Goal: agent always running. If not, ask: "what could the agent be doing for me?"

Hashimoto's preference in February 2026: slow, thoughtful models (Amp deep mode / GPT-5.2-Codex). 30+ min per task, but high quality. One agent, not parallel. On Claude Opus 5.5 that choice is the effort level, a verification dial rather than an intelligence dial: high adds roughly 20K thinking tokens per task, about $0.40, the price of a ten-turn retry.

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

Each project gets its own harness: CLAUDE.md, docs/, linters, sensors.

### Harness Health Checklist

- [ ] AGENTS.md/CLAUDE.md: table of contents, not encyclopedia?
- [ ] Pre-commit hooks exist and work?
- [ ] Custom linters with remediation instructions?
- [ ] Architectural constraints checked automatically?
- [ ] Documentation versioned with code?
- [ ] Entropy fighting mechanism exists (GC agents, quality grades)?
- [ ] Agent can self-validate its work (tests, screenshots)?
- [ ] A red check at the end of a turn stops the turn from ending?
- [ ] Every check says what it skipped, and you have watched it go red on a known defect?

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

A short pick from [awesome-harness-engineering](https://github.com/walkinglabs/awesome-harness-engineering):

- [Anthropic: Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents): context window as working memory budget
- [HumanLayer: Context-Efficient Backpressure](https://www.humanlayer.dev/blog/context-efficient-backpressure): keep agents from burning context on noisy, low-value output
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): initializer agents, feature lists, self-verification, handoff artifacts
- [OpenHands: Evaluating Agent Skills](https://openhands.dev/blog/evaluating-agent-skills): bounded tasks, deterministic verifiers, no-skill baselines
- [LangChain: Improving Agents with Harness Engineering](https://blog.langchain.com/improving-deep-agents-with-harness-engineering/): evidence that harness changes alone move benchmarks
- [Naresh Jain: Are Harnesses Worth the Cost?](https://martinfowler.com/articles/are-harnesses-worth-the-cost.html) (Oct 2026): a behavioral harness took a cheap model from 3/10 to 10/10 accepted runs and cost a frontier model 7x for nothing; capability decides when sensors run, not whether
- [Birgitta Böckeler: TDD inside the agent loop](https://martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html) (Aug 2026): agent-run TDD cost 2.96x to 8.5x the tokens with no better mutation scores; mutation testing as the regression sensor instead
- [Anthropic: Redesigning source control](https://www.anthropic.com/research/redesigning-source-control) (Oct 2026): 30,000+ merges a day, and the engineers' job is often telling Claude no

---

*Sources:*
- *[OpenAI: Harness Engineering](https://openai.com/index/harness-engineering/) (Ryan Lopopolo, 2026)*
- *[Mitchell Hashimoto: My AI Adoption Journey](https://mitchellh.com/writing/my-ai-adoption-journey) (Feb 2026)*
- *[Martin Fowler: Harness Engineering](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) (Birgitta Böckeler, Feb 2026)*
- *[Martin Fowler: Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html) (Birgitta Böckeler, April 2026)*
- *[awesome-harness-engineering](https://github.com/walkinglabs/awesome-harness-engineering): curated list*
