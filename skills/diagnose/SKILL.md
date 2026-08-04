---
name: solo-diagnose
description: Diagnosis loop for hard bugs and performance regressions — build a tight feedback loop first, hypothesise second. Use when user says "diagnose", "debug this", "why is this broken", "почему падает", "тормозит", or reports something throwing, failing, flaky, or slow. Do NOT use for code quality review (/review) or feature planning (/plan).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔬"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
argument-hint: "<what's broken>"
---

# /diagnose — the feedback loop is the skill

A discipline for hard bugs. Skip a phase only with an explicit reason.

Before exploring, read the project `CLAUDE.md` and any `CONTEXT.md` for the module vocabulary, and check ADRs in the area you're touching.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. With a **tight** pass/fail signal that goes red on _this_ bug, you will find the cause — bisection, hypothesis-testing, and instrumentation all just consume it. Without one, no amount of staring at code saves you.

Spend disproportionate effort here. Be aggressive, be creative, refuse to give up.

### Ways to construct one — roughly in this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright MCP or a script) — drives the UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real request / payload / event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** A minimal subset of the system (one service, mocked deps) exercising the bug path in a single function call.
7. **Property / fuzz loop.** For "sometimes wrong output": 1000 random inputs, look for the failure mode.
8. **Bisection harness.** If it appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so `git bisect run` can eat it.
9. **Differential loop.** Same input through old vs new version (or two configs), diff the outputs.
10. **HITL bash script.** Last resort — if a human must click, drive _them_ with `scripts/hitl-loop.template.sh` so the loop stays structured and its output feeds back to you.

Servers and log streams run in the background (`run_in_background: true`) so the loop and the work proceed together.

### Tighten the loop

Treat the loop as a product. Once you have _a_ loop, **tighten** it:

- Faster? Cache setup, skip unrelated init, narrow the test scope.
- Sharper signal? Assert the specific symptom, not "didn't crash".
- More deterministic? Pin time, seed RNG, isolate filesystem, freeze network.

A 30-second flaky loop is barely better than none; a 2-second deterministic one is a superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it is.

### Completion criterion — a tight loop that goes red

Phase 1 is done when you can name **one command** — a script path, a test invocation, a curl — that you have **already run at least once** (paste the invocation and its output), and that is:

- [ ] **Red-capable** — drives the actual bug path and asserts the **user's exact symptom**, so it can go red now and green once fixed. Not "runs without erroring".
- [ ] **Deterministic** — same verdict every run (flaky bugs: a pinned, high reproduction rate).
- [ ] **Fast** — seconds, not minutes.
- [ ] **Agent-runnable** — runs unattended; a human enters only via `scripts/hitl-loop.template.sh`.

If you catch yourself reading code to build a theory before this command exists, **stop — jumping straight to a hypothesis is the exact failure this skill prevents.** No red-capable command, no Phase 2.

### When you genuinely cannot build a loop

Say so explicitly and list what you tried. Ask for one of: access to an environment that reproduces it, a captured artifact (HAR, log dump, core dump, screen recording with timestamps), or permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.

## Phase 2 — Reproduce + minimise

Run the loop. Watch it go red.

- [ ] The failure is the one the **user** described — not a different failure that happens to live nearby. Wrong bug = wrong fix.
- [ ] It reproduces across runs (or at a high enough rate to debug against).
- [ ] The exact symptom is captured (error message, wrong output, timing) so later phases can verify the fix addresses it.

Then **minimise**: shrink to the smallest scenario that still goes red. Cut inputs, callers, config, data, and steps **one at a time**, re-running after each cut. Done when every remaining element is load-bearing — removing any one makes it go green.

A minimal repro shrinks the hypothesis space in Phase 3 and becomes the clean regression test in Phase 5. Do not proceed until you have reproduced **and** minimised.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them — single-hypothesis generation anchors on the first plausible idea.

Each must be **falsifiable**, stating its prediction:

> "If X is the cause, then changing Y makes the bug disappear / changing Z makes it worse."

Can't state the prediction? It's a vibe — discard or sharpen it.

**Show the ranked list to the user before testing.** They re-rank instantly with domain knowledge ("we just deployed a change to #3") or name what they've already ruled out. Cheap checkpoint, big saving. Don't block on it — proceed with your ranking if they're AFK.

## Phase 4 — Instrument

Each probe maps to a specific prediction from Phase 3. **Change one variable at a time.**

1. **Debugger / REPL** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Tag every debug log** with a unique prefix — `[DEBUG-a4f2]`. Cleanup becomes a single grep; untagged logs live forever.

**Perf branch.** For performance regressions logs are usually wrong. Establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 5 — Fix + regression test

Write the regression test **before the fix** — but only if a **correct seam** exists: one where the test exercises the real bug pattern as it occurs at the call site. A seam too shallow (single-caller test when the bug needs multiple callers) gives false confidence.

**If no correct seam exists, that itself is the finding.** Note it — the architecture is preventing the bug from being locked down.

With a correct seam: turn the minimised repro into a failing test there → watch it fail → apply the fix → watch it pass → re-run the Phase 1 loop against the original un-minimised scenario.

Test shape and seam agreement: `${CLAUDE_PLUGIN_ROOT}/skills/build/references/tdd-seams.md`.

## Phase 6 — Cleanup + post-mortem

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes, or the absence of a seam is documented
- [ ] All `[DEBUG-...]` instrumentation removed (grep the prefix)
- [ ] Throwaway harnesses deleted or moved somewhere clearly marked
- [ ] The hypothesis that turned out correct is stated in the commit message — so the next debugger learns

**Then ask: what would have prevented this bug?** If the answer is architectural (no good test seam, tangled callers, hidden coupling), hand off with specifics — `${CLAUDE_PLUGIN_ROOT}/skills/review/references/codebase-design.md` has the vocabulary. Make that recommendation **after** the fix lands, when you know more than you did at the start.

## Gotchas

- **A green loop is not a fixed bug.** If the loop never went red before the fix, it proves nothing — it may not reach the bug path at all.
- **Minimising after hypothesising wastes the minimisation.** The point is to shrink the hypothesis space *before* generating hypotheses.
- **Untagged debug logs ship.** The `[DEBUG-xxxx]` prefix makes cleanup mechanical instead of a memory test.
- **HITL is a loop, not a chat.** Driving the user through `scripts/hitl-loop.template.sh` keeps their answers structured and parseable; asking freeform questions loses the loop.

## Don't

- Read code to form a theory before a red-capable command exists — that's the failure this skill prevents.
- Fix a *nearby* failure the loop happens to catch instead of the symptom the user reported.

---

Adapted from [`diagnosing-bugs`](https://github.com/mattpocock/skills/tree/main/skills/engineering/diagnosing-bugs) by Matt Pocock (MIT, Copyright (c) 2026 Matt Pocock). See [THIRD-PARTY.md](../../THIRD-PARTY.md).
