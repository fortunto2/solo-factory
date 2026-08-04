# Glossary — the vocabulary of skill quality

The domain model behind [writing-skills.md](writing-skills.md). Root virtue: **Predictability**. Every term is a lever on it, or a **failure mode** that costs it.

Use these words exactly when auditing or discussing a skill — the shared vocabulary is what makes two audits agree. Each entry ends with _Avoid_: the near-synonyms that blur the term.

## Predictability

The degree to which a skill makes the agent behave the same _way_ on every run — the same process, not the same output. The root virtue every other term serves; cost and maintainability are symptoms of it, not rivals.

_Avoid_: consistency, reliability, robustness, output-determinism

## Invocation

**Model-invoked** — a skill that keeps its **description**, so the agent can fire it autonomously; the human can still type its name, so model-invocation always _includes_ user reach. Pays permanent **context load**. Reachable by other skills. A model-invoked skill that is all **reference** is one home for shared reference. _Avoid_: ability, tool, capability

**User-invoked** — a skill with its description stripped: invisible to the agent, reachable only by the human typing its name. Zero context load; nothing but the human can fire it. _Avoid_: procedure, workflow, command

**Description** — the machine-readable trigger, and the one **context pointer** a model-invoked skill keeps loaded at all times. Its mere presence _is_ the invocation axis: keep it and the skill is model-invoked; delete it and it is user-invoked. _Avoid_: frontmatter, summary

**Context pointer** — a reference held in context that names out-of-context material and encodes the condition for reaching it. The description is the top-level pointer (window → skill); pointers to `references/` files are the same object one level down. Its wording, not its target, decides when and how reliably the agent reaches. _Avoid_: link, import

**Context load** — the cost a model-invoked skill imposes on the context window: its description, always loaded, spending tokens and attention. The brake on splitting into more model-invoked skills. _Avoid_: token cost, context bloat

**Cognitive load** — the cost a user-invoked skill imposes on the human: remembering it exists and when to reach for it. Not a cost to minimise — it is the price of human agency. Spend it where human judgement matters. _Avoid_: burden, overhead

**Router** — one place that names your user-invoked skills and when to reach for each, so the human holds one index instead of many. In solo-factory: `rules/routing.md`. _Avoid_: dispatcher, menu, registry

**Granularity** — how finely you divide skills. Finer division spends one of the two loads. Two cuts: by **invocation** (a distinct **leading word** deserves its own trigger) and by **sequence** (a step's **post-completion steps** need hiding). _Avoid_: chunking, modularity

## Information hierarchy

**Information hierarchy** — a skill's content ranked by how immediately the agent needs it: **steps** (in-file, primary) → **reference** in-file (secondary) → **reference** disclosed behind a **context pointer**. Independent of invocation. In-file reference that should be disclosed buries the steps and turns attending to them into a coin-flip. _Avoid_: structure, layout

**Steps** — the ordered actions the agent performs; the primary tier when a skill has them. Every step ends on a **completion criterion**. _Avoid_: workflow, instructions

**Reference** — material consulted on demand: definitions, facts, parameters, examples, conditional instructions. The prime candidate for **progressive disclosure**. _Avoid_: supporting material, background

**External reference** — reference living outside the skill system (`templates/principles/*.md`), pointable by any skill. The only shared home two user-invoked skills can use, since neither can fire the other. _Avoid_: doc, knowledge base

**Progressive disclosure** — moving reference out of `SKILL.md` into `references/` behind a pointer, so the top stays legible. Not primarily a token optimisation; it is how the hierarchy is protected. Licensed by **branching**. _Avoid_: lazy loading

**Co-location** — keeping a concept's definition, rules, and caveats under one heading rather than scattered, so reading one part brings its neighbours. The hierarchy ranks how far _down_ a piece sits; co-location decides what sits _beside_ it. Distinct from **duplication**: that repeats one meaning twice, scattering fragments one meaning across many places. _Avoid_: grouping, cohesion

## Steering

**Branch** — a distinct way a skill can be invoked, so different runs take different paths through it. The cleanest test for what to disclose. _Avoid_: path, case, fork

**Leading word** — a compact concept already in the model's pretraining that the agent thinks with while running the skill (_lesson_, _fog of war_, _tracer bullet_, _tight_, _red_). Repeated as a token, never as a sentence, it accumulates a distributed definition and anchors a region of behaviour in the fewest tokens. Anchors _execution_ in the body and _invocation_ in the description — word a description with the leading words you actually type when you want the skill. _Avoid_: keyword, term, motif

**Completion criterion** — the condition that tells the agent a unit of work is done. Two properties make it a lever: **clarity** (can it tell done from not-done?) resists **premature completion**; **demand** (how much it requires) sets **legwork**, and binds flat reference too ("every rule applied"). The strongest criteria are both checkable and exhaustive. _Avoid_: done condition, exit condition

**Legwork** — the digging an agent does within a single step: reading files, exploring, finding out rather than asking the user. Never written as its own step; latent in the wording. Raised by a leading word (_relentless_) or a demanding completion criterion. _Avoid_: scope, diligence, coverage

**Post-completion steps** — the steps that follow the current one. Visible, they pull the agent forward into **premature completion**; the defence is to hide them across a real context boundary. _Avoid_: horizon, lookahead

## Failure modes

**Premature completion** — ending the current step before it is genuinely done, because attention slips to _being done_. A between-steps failure: needs steps to occur. A tug-of-war between visible post-completion steps (the pull) and the criterion's clarity (the resistance). Sharpen the bound first — local and cheap; hide the later steps only when the criterion is irreducibly fuzzy _and_ you observe the rush. _Avoid_: premature closure, rushing

**Duplication** — the same meaning given more than one **single source of truth**. Costs maintenance and tokens, and inflates a meaning's prominence past its real rank. The accidental inverse of a leading word, which repeats a _token_ on purpose, never the meaning. _Avoid_: repetition, redundancy

**Sediment** — stale layers that settle because adding feels safe and removing feels risky, so you must core down through them to find what is live. The default fate of any skill without a pruning discipline. _Avoid_: accretion, cruft, rot

**Sprawl** — a skill simply too long, even when every line is live and unique. Distinct from sediment (length from staleness) and duplication (length from repetition) — sprawl is length itself. Cure: the ladder, plus splitting by branch or sequence. _Avoid_: bloat, verbosity

**No-op** — an instruction the model already obeys by default, so you pay load to say nothing. The test: does this line change behaviour versus the default? Model-relative, not reader-relative — two people disagreeing about a no-op disagree about the default, and settle it by running the skill, not by debate. _Avoid_: restating the obvious

**Negation** — steering by prohibition, which drags the forbidden behaviour into context and makes it _more_ available. _Never write verbose comments_ makes verbosity the pattern just read. Cure: prompt the **positive**. A prohibition earns its place only as a hard guardrail you cannot phrase positively — and even then, pair it with the positive target. _Avoid_: don't-prompting, pink elephant

## Pruning

**Single source of truth** — each meaning in exactly one authoritative place, so a behaviour change is a one-place edit. **Duplication** is its violation. _Avoid_: canonical location

**Relevance** — whether a line still bears on what the skill does. A line loses it by never bearing on the task, or by going stale. Distinct from **no-op**: relevance asks whether a line bears on the task, not whether it changes behaviour. _Avoid_: staleness, load-bearing

---

Adapted from [`writing-great-skills/GLOSSARY.md`](https://github.com/mattpocock/skills/tree/main/skills/productivity/writing-great-skills) by Matt Pocock (MIT). Condensed; solo-factory paths substituted. See [THIRD-PARTY.md](../../../THIRD-PARTY.md).
