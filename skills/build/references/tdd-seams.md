# TDD — seams, slices, and tests worth keeping

The red → green loop is the easy part. This file is what makes the loop produce tests that survive a refactor: where tests go, how to slice the work, and the four ways a test lies to you.

Read before the first test of a feature, not after.

## Seams — where tests go

A **seam** is the public boundary you test at: the interface where you observe behaviour without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam.

This is the step that keeps TDD from turning into coverage theatre. You can't test everything — agreeing the seams up front is how the effort lands on critical paths and complex logic instead of every edge case. Ask: *"What's the public interface, and which seams should we test?"*

Deciding *where* the seam belongs is a design question, not a testing one — see `skills/review/references/codebase-design.md`.

## Vertical slices, not horizontal ones

**Horizontal slicing** — all the tests first, then all the implementation — is the anti-pattern that looks like diligence. Bulk tests verify _imagined_ behaviour: you test the *shape* of things rather than what a user does, the tests go insensitive to real changes, and you commit to a test structure before you understand the implementation.

Work in **vertical slices**: one test → one implementation → repeat. Each test is a **tracer bullet** that responds to what the last cycle taught you.

## Rules of the loop

- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the loop.** It belongs to the review stage (`/review`), not the red → green cycle.

## The four lying tests

**Implementation-coupled** — mocks internal collaborators, tests private methods, or verifies through a side channel. The tell: the test breaks when you refactor but behaviour hasn't changed.

```typescript
// BAD — asserts on a call, not an outcome
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});

// GOOD — asserts on observable behaviour
test("user can checkout with valid cart", async () => {
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

**Side-channel verification** — reaching past the interface to check the result.

```typescript
// BAD — bypasses the interface
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD — verifies through the interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  expect((await getUser(user.id)).name).toBe("Alice");
});
```

**Tautological** — the assertion recomputes the expected value the way the code does, so it passes by construction and can never disagree with the code.

```typescript
// BAD — expected value computed the same way as the implementation
const expected = items.reduce((sum, i) => sum + i.price, 0);
expect(calculateTotal(items)).toBe(expected);

// GOOD — expected value is an independent known literal
expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
```

Expected values come from an independent source of truth: a known-good literal, a worked example, the spec. Hand-derived snapshots computed the same way as the code are tautological too.

**Insensitive** — a test that passes whatever the code does. Prove a new test can fail: watch it go red before you make it green.

## Good test characteristics

- Tests behaviour a caller cares about, through the public interface only
- Survives internal refactors — describes WHAT, not HOW
- The name reads like a specification: `"user can checkout with valid cart"`
- One logical assertion per test

---

Adapted from [`tdd`](https://github.com/mattpocock/skills/tree/main/skills/engineering/tdd) by Matt Pocock (MIT, Copyright (c) 2026 Matt Pocock), merging its `tests.md`. See [THIRD-PARTY.md](../../../THIRD-PARTY.md).
