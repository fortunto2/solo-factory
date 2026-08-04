# Codebase Design — deep modules, seams, deepening

Vocabulary for judging *shape* during a review, and for recommending a restructure that the next agent can act on. Design **deep modules**: a lot of behaviour behind a small interface, placed at a clean seam, testable through that interface. The aim is leverage for callers, locality for maintainers, testability for everyone.

Reach for this when a review finding is "this code works but is the wrong shape", when deciding where a seam goes, or when asked to make code more testable or AI-navigable.

## Glossary

Use these terms exactly — don't substitute "component", "service", "API", or "boundary". Consistent language is the whole point.

**Module** — anything with an interface and an implementation. Deliberately scale-agnostic: a function, class, package, or tier-spanning slice. _Avoid_: unit, component, service.

**Interface** — everything a caller must know to use the module correctly: the type signature, but also invariants, ordering constraints, error modes, required configuration, and performance characteristics. _Avoid_: API, signature (too narrow — they name only the type-level surface).

**Implementation** — what's inside a module. Distinct from **adapter**: a thing can be a small adapter with a large implementation (a Postgres repo) or a large adapter with a small implementation (an in-memory fake). Say "adapter" when the seam is the topic; "implementation" otherwise.

**Depth** — leverage at the interface: how much behaviour a caller (or test) can exercise per unit of interface they must learn. **Deep** = large behaviour behind a small interface. **Shallow** = interface nearly as complex as the implementation.

**Seam** _(Michael Feathers)_ — a place where you can alter behaviour without editing in that place; the *location* at which a module's interface lives. Where to put the seam is its own design decision, distinct from what goes behind it. _Avoid_: boundary (overloaded with DDD's bounded context).

**Adapter** — a concrete thing satisfying an interface at a seam. Describes *role* (what slot it fills), not substance (what's inside).

**Leverage** — what callers get from depth: more capability per unit of interface learned. One implementation pays back across N call sites and M tests.

**Locality** — what maintainers get from depth: change, bugs, knowledge, and verification concentrate in one place. Fix once, fixed everywhere.

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module can be internally composed of small, swappable parts — they just aren't part of the interface. A module can have **internal seams** (private, used by its own tests) as well as the **external seam** at its interface. Don't expose an internal seam through the interface just because a test uses it.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same seam. If you want to test *past* the interface, the module is probably the wrong shape.
- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't introduce a seam unless something actually varies across it — typically production + test. A single-adapter seam is just indirection.

When designing an interface, ask: can I reduce the number of methods? Simplify the parameters? Hide more complexity inside?

## Designing for testability

1. **Accept dependencies, don't create them.** `processOrder(order, paymentGateway)`, not `processOrder(order)` with `new StripeGateway()` inside.
2. **Return results, don't produce side effects.** `calculateDiscount(cart): Discount`, not `applyDiscount(cart): void` mutating `cart.total`.
3. **Small surface area.** Fewer methods = fewer tests. Fewer params = simpler setup.

## Deepening a shallow cluster

Classify the cluster's dependencies first — the category decides how the deepened module is tested across its seam.

| Category | What it is | How to deepen |
|----------|-----------|---------------|
| **In-process** | Pure computation, in-memory state, no I/O | Always deepenable. Merge the modules, test through the new interface. No adapter. |
| **Local-substitutable** | Has a local test stand-in (PGLite for Postgres, in-memory FS) | Deepenable if the stand-in exists. Run the stand-in in the suite. Seam is internal — no port at the external interface. |
| **Remote but owned** | Your own services across a network boundary | Define a **port** at the seam. Deep module owns the logic; transport is injected. HTTP adapter for prod, in-memory for tests. |
| **True external** | Third-party you don't control (Stripe, Twilio, OpenAI) | Injected port; tests provide a mock adapter. |

**Replace, don't layer.** Old unit tests on the shallow modules become waste once tests exist at the deepened interface — delete them. Write the new tests at the interface, asserting observable outcomes rather than internal state. A test that must change when the implementation changes is testing past the interface.

## Rejected framings

- **Depth as implementation-lines ÷ interface-lines** (Ousterhout's own metric): rewards padding the implementation. Use depth-as-leverage.
- **"Interface" as the TypeScript `interface` keyword or a class's public methods**: too narrow — interface here is every fact a caller must know.
- **"Boundary"**: overloaded with DDD's bounded context. Say **seam** or **interface**.

## Where this fits

- `/review` — use the deletion test and depth-as-leverage to justify a shape finding instead of "this feels wrong".
- `/plan` — pick the seam before slicing tasks; the seam decides where the tests go.
- `templates/principles/dev-principles.md` — Clean Architecture and DDD sections cover layering and bounded contexts; this file covers module depth and seam placement inside a layer.

---

Adapted from [`codebase-design`](https://github.com/mattpocock/skills/tree/main/skills/engineering/codebase-design) by Matt Pocock (MIT, Copyright (c) 2026 Matt Pocock), merging its `DEEPENING.md`. See [THIRD-PARTY.md](../../../THIRD-PARTY.md).
