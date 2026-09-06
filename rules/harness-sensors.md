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
| `cargo-fmt` | Changed `.rs` files are rustfmt-clean | `rustfmt --check` on the changed files only |
| `clippy` / `cargo-test` | clippy with `-D warnings`; tests pass — **whole workspace, not scoped** | cargo (full mode) |
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

**3b. A sensor obeys the scope, or says it does not.** `cargo fmt --check`
formats the whole workspace whatever changed. On a project that never adopted
rustfmt that is 93 files of noise every run — an actionable false-positive rate
of 100%, since nobody reformats 93 files because a verifier asked. Worse, it
printed a finding in the same receipt that said "empty scope: nothing was
verified": two contradictory statements at once. Scoped sensors now take the
changed files; the genuinely whole-project ones (clippy, cargo test) say so in
their promise.

**3c. A promised sensor that says nothing is a harness defect.** If a file type
is in scope and its sensor appears in neither `ran` nor `skipped`, the receipt
prints `HARNESS GAP` and the verdict becomes UNKNOWN, never PASS. This caught a
real hole: an Xcode project generated from `project.yml` has no `Package.swift`,
so the Swift stack never activated and `swiftlint` vanished from the receipt on
a tree that was half Swift — installed, reachable, and silent. Stacks now
activate from the changed files as well as from root markers.

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

## Tools that report success and do nothing

One class, several disguises: the command exits 0, prints nothing useful, and
the harness reads that as evidence. Contributed by a peer session working on
Apple tooling; each is measured, not folklore.

**`simctl launch` swallows environment variables.** `xcrun simctl launch <udid>
<bundle> FOO=1` passes `FOO=1` as an *argument*, not as an environment variable,
so a debug gate reading the environment stays shut and the feature looks dead.
The working form is `SIMCTL_CHILD_FOO=1 xcrun simctl launch ...` — the prefix is
stripped on the way in. `xcodebuild test` has the same shape via `TEST_RUNNER_`.
*Telling incomplete from real*: the app must print the value it read at startup.
No line means it is not reading, not that the flag is off.

**`simctl privacy grant` exits 0 without granting.** `grant all` writes a single
catch-all TCC row that some frameworks do not consult — speech recognition stayed
`notDetermined` and every call died on its own authorization timeout. The working
path writes a per-service row into the device's `TCC.db` while the device is
**shut down**, because `tccd` caches. *Telling incomplete from real*: read the
status back from the framework, never from the exit code. And note that a system
prompt in an automated run is a hang, not a denial — the callback never arrives
without a human tap.

**`log show` hides `.info` and serves the previous build.** Without `--info`,
info-level lines are not emitted at all, so `grep` comes back empty and the
feature looks dead when the reader is. Worse, after a rebuild-install-launch
cycle the window still holds lines from the *previous* build, so
`until grep -q marker` exits immediately on stale output. *Telling incomplete
from real*: stamp the time before launching and read lines with their timestamps.

**An equality check must assert its operands are non-empty.** A probe comparing
"the binary on the simulator" against "the binary I built" printed SAME for two
empty strings — the glob matched nothing. Comparing two absences is a passing
test with no content, the same family as verifying a hash with the function that
produced it.

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
