---
name: solo-grill
description: Relentless one-question-at-a-time interview that stress-tests a plan, design, or decision before anything gets built. Use when user says "grill me", "прожарь", "разбери мою идею", "stress-test this", "punch holes in this", or a plan still has soft spots. Also reachable by other skills that need an interview. Do NOT use for scoring an idea (/validate) or writing the implementation plan (/plan).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔥"
allowed-tools: Read, Grep, Glob, Bash, WebSearch
argument-hint: "<the plan, design, or decision to grill>"
---

# /grill — the interview primitive

Interview the user relentlessly about every aspect of the thing until you reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one by one. For each question, give your own recommended answer.

**Ask one question at a time**, waiting for the answer before the next. A batch of questions is bewildering and destroys the dependency order that makes the interview converge.

**Look up facts; ask for decisions.** If something can be settled by exploring the environment — filesystem, git history, the codebase, the web — go and settle it. The decisions are the user's: put each one to them and wait.

Do not act on the plan until the user confirms the shared understanding is reached.

## Why one at a time

The mental model is a **decision tree**. An early answer reshapes which questions come next — a firehose of parallel questions throws away that structure and produces answers to questions that turned out not to matter.

## Composing

This is a primitive, not a workflow. Reach for it from inside other work whenever a plan needs sharpening:

- Before `/plan` — when the feature is still fuzzy. `/plan` deliberately asks zero questions and researches code instead, so grill first when the *decisions*, not the code, are what's missing.
- Before `/validate` — when the idea itself hasn't been pinned down enough to score.
- Inside `/stream` — when a STREAM layer needs the user's judgement rather than analysis.
- After `/diagnose` Phase 3 — to pressure-test which hypothesis to chase.

## Gotchas

- **Recommendations are the point.** A bare question makes the user do all the work; a question with your recommended answer lets them correct a draft, which is far faster.
- **Asking what you could look up burns trust.** Check the repo, the config, the git log first.

## Don't

- Batch questions "to save time" — it costs more.
- Start building the moment the user answers the last question; confirm the shared understanding first.

---

Adapted from [`grilling`](https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling) by Matt Pocock (MIT, Copyright (c) 2026 Matt Pocock). See [THIRD-PARTY.md](../../THIRD-PARTY.md).
