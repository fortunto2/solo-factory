# Sensors — what the harness measures, and what it promises

Most of this factory is **feedforward**: 39 skills, rules, stack templates, a
CLAUDE.md. All of it steers the agent *before* it acts. This file covers the
other half — the **sensors** that observe *after* it acts, so mistakes
self-correct before they reach you.

Martin Fowler's split ([harness engineering](https://martinfowler.com/articles/harness-engineering.html),
Apr 2026): feedback-only gives an agent that repeats mistakes; feedforward-only
gives an agent that encodes rules and never learns whether they worked. You had
the second one.

## The three placements

| Where | What runs | Budget | Why there |
|---|---|---|---|
| **Every Edit/Write** (`sensor-edit.sh`) | Syntax only — parse the one file just written | <1s | A semantic check here floods the agent with errors from files it has not reached yet mid-refactor, and it reverts good work to silence them |
| **End of turn** (`sensor-stop.sh`) | `solo-verify --full`: lint, types, tests | <120s | The step boundary. Cross-file meaning is only well-defined once the agent thinks it is done |
| **Commit** (pre-commit) | Formatting, repo-specific gates | seconds | Already yours; unchanged |

The middle one blocks. If the receipt is red, the turn cannot end — so
"I finished" stops being a claim the agent makes about itself.

## Published promises

Every sensor states what it checks. This exists so that **weakening a threshold
reads as a diff against a stated promise** instead of an invisible edit. Change
a promise deliberately and say so; the harness will not stop you, but it will
never let it happen quietly.

| Sensor | Promise | Mechanics |
|---|---|---|
| `syntax` | Every changed `.py`/`.js` file parses | `ast.parse` / `node --check`, per file |
| `limits` | No function >150 lines, no module >1000 lines | AST walk; thresholds from CLAUDE.md |
| `ruff` | The repo's configured ruff rule set | `ruff check --output-format=concise` on changed files |
| `ty` | No type errors in changed Python | `uvx ty check` (full mode) |
| `pytest` | The suite runs **and collects >0 tests** | `uvx pytest -q`, counters parsed |
| `eslint` / `tsc` | Repo's eslint config; project typechecks | `node_modules/.bin/*` only, never global |
| `cargo-fmt` / `clippy` / `cargo-test` | rustfmt clean; clippy with `-D warnings`; tests pass | cargo |
| `swiftlint` / `ktlint` | Configured rule set | Per changed file |
| `shellcheck` | Clean at severity **>= warning** | Info level is excluded on purpose — see noise, below |

Tooling never crosses languages: Python sensors never touch a `.ts` file.

## Four rules the receipt obeys

**1. "ok" alone is forbidden.** A green result that does not say what ran, what
was skipped and *what it refused to look at* is indistinguishable from never
having looked. Every run prints `ran` / `skipped` / `UNCHECKED`.

**2. Zero scope is never a pass.** Nothing checked returns `UNKNOWN` and exit 2,
not exit 0. A test runner that collects 0 tests exits 0; that is a false green,
so `pytest` fails on `collected == 0`.

**3a. An incomplete run is not a result.** Exit `124` (timed out), `126` (not
executable) and `127` (command not found) mean the check never observed the
thing under test, so they become skips with a stated reason, never failures and
never passes. And the completion check runs *before* the output is interpreted:
a timed-out pytest parses as "0 collected", and reporting that as "no tests
found" would state a cause that did not happen.

**3. A skip always carries a reason, and "not installed" is a claim about PATH.**
A hook's PATH differs from your shell's, so a tool that works in the terminal
can be unreachable in the hook. The receipt says which of those it observed.

**4. Editing the harness is loud, not forbidden.** Test files and lint configs
in a change are printed as `HARNESS TOUCHED` with a sha256. Sometimes the rule
really is what is wrong — in one agent's measured sample, 3 of 5 times the
correct repair *was* the rule. So the harness surfaces the edit and leaves the
judgment to you.

## On noise

A sensor's false-positive rate decides where it can live, more than its speed
does. A measured example from the wild: a naive dead-link checker flagged 73% of
links, 18% after repair, ~3% confirmed by hand. **A 73% sensor gets deleted
within a week and leaves you worse off than having none** — you believe a check
exists when it does not. Fowler's "spiral of over-engineered refactorings" is a
property of a *noisy* sensor, not an early one.

So: measure false positives on a real repo before moving a sensor earlier. That
is why `shellcheck` sits at severity>=warning and why the edit hook checks only
syntax.

## Usage

```bash
solo-verify                  # fast: syntax + lint on changed files
solo-verify --full           # + types + tests
solo-verify --files a.py     # explicit scope
solo-verify --json           # machine-readable receipt
make verify / make verify-full
```

Exit codes: `0` pass · `1` fail · `2` unknown (nothing was checked).

Disable the gate for a session: `SOLO_SENSOR_STOP=off` (or `fast` to skip tests).

## Every way around this gate, listed on purpose

A guard is only as strong as its cheapest bypass, and a bypass nobody wrote
down is one you will rediscover by accident. Board agent @pohuy-ultra put it as
two questions every guard owes an answer to: **can the protected operation be
reached without passing through me**, and **can a missing or empty value turn
into a result that looks valid**. Both answers for this harness:

| Bypass | Effect | When it is legitimate |
|---|---|---|
| `git commit --no-verify` | Skips pre-commit entirely | A broken hook environment, never a red check |
| `SOLO_SENSOR_STOP=off` | Stop gate does nothing | Long unrelated session; set it deliberately, not to escape a finding |
| `SOLO_SENSOR_STOP=fast` | Skips types and tests | Slow suite, mid-exploration |
| Editing a lint config or test | Changes what counts as a pass | Genuinely wrong rule — reported as `HARNESS TOUCHED`, not blocked |
| Running the tool outside a git repo | Empty scope | Nothing to verify; returns UNKNOWN, not PASS |
| A tool missing from the hook's PATH | That sensor cannot run | Reported as a skip naming PATH, never as a pass |

The second question is why `UNKNOWN` exists as a third verdict with its own
exit code. An absent tool, an empty scope and a test run that collected nothing
all produce "no findings", and "no findings" is exactly what a passing run looks
like. Separating them is the whole point of the receipt.

None of these are locked down, because a gate the author cannot open is a gate
the author routes around permanently. They are listed so that using one is a
decision rather than an accident.

## The part a solo setup cannot fix alone

A sensor written by whoever writes the code is blind in the same place. Rules
and hooks do not cure this — they come from the same head. In practice an
outside reader finds the defects your own run cannot see, so a solo harness has
to substitute for that deliberately: a second model reviewing the diff, an
adversarial pass that tries to refute a finding, or literally another agent.

This file was itself revised by outside agents who supplied counterexamples for
half its claims. The verifier then found a real bug in itself on first run
(`scripts/solo-verify` has no `.py` suffix, so every suffix-filtered sensor
skipped it silently) — which is exactly what rule 1 exists to surface.
