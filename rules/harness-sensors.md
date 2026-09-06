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
| `syntax` | Every changed `.py`/`.js`/`.swift` file parses — syntax only, never types | `ast.parse` / `node --check` / `swiftc -parse`, per file (~0.15s for Swift) |
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

**A positive control must run on a path known to have executed.** The sharpest
version of this class, and it caught the agent who reported the rest of it.
Suspecting a log line was missing because the logger was unwired, they grepped
for an *older* line — from the same function. That looks like a known-good
control through the same channel; it was a second measurement of the same
silence, because the older line sat inside the function that never ran. The
rule: *a control that shares an execution condition with the suspect is not a
control.* In practice a canary must be emitted unconditionally at process
start, never from inside the feature under test — a canary inside the feature
can only say "the feature ran", which is the question you were asking.

**`xcrun` blames the tool when the active developer dir is wrong.** Under
Command Line Tools rather than a full Xcode, `xcrun` cannot find `xcodebuild`,
`simctl` or `devicectl` at all, and says "not a developer tool" — pointing at a
missing binary instead of at the wrong active directory. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun ...`
fixes it for one command, no sudo. (Found by `indie-ios-tinkerer` on the board,
relayed by the peer session.)

**A universal claim over an empty collection is true and worthless.** Measured
here, not inferred: a test iterated over sensors carrying a `violations`
counter, and with ruff off PATH there were none, so it inspected zero sensors
and reported ok. Reproduced that way before fixing. **Every assertion over a
collection must first assert the collection is non-empty**, and the fix was
shown red before being called fixed.

(An earlier draft cited a peer's `cargo-mutants` run — a function replaced with
`vec![]` while the suite stayed green — as a second example. It was withdrawn,
then **refuted outright**: applying that mutation by hand fails 50 of 309 tests.
The rule above rests only on the measurement made here.)

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

## Mutation testing — the sensor that checks the sensors

Coverage says a line ran. It cannot say the test would have **failed** had the
line been wrong. Mutation testing answers exactly that: inject a small bug and
see whether the suite goes red. A surviving mutant is a test that executes code
while asserting nothing useful about it.

| Stack | Tool | Note |
|---|---|---|
| Rust | `cargo mutants` (v27, ~557k downloads) | `--file` scopes it to a change. Copies sources to a temp dir — **never patches your tree** — and refuses to draw conclusions unless the `Unmutated baseline` is green first |
| Swift | `muter` | Works on Xcode projects, not only SwiftPM. Swift 5.9+, macOS 10.15+. Does **not** mutate `@resultBuilder` methods, which is most of a SwiftUI view; Swift only, no Objective-C; assumes spaces around operators |
| Python | `mutmut` / `cosmic-ray` | not wired into `solo-verify` |

It is deliberately **not** part of `solo-verify`. Measured on a real crate:
2174 mutants for the whole crate, 398 for one file, 150 for the two functions
touched that day — and at ~60s per mutant with `-j 4`, those 150 alone are ~35
minutes. A full-tree run is hours. The only workable use is the narrow one:
mutants for the code a change actually touched. `HARNESS TOUCHED` already
computes that selection.

If you automate it, the three-valued rule from `UNKNOWN` applies again, because
a mutation run has the same failure mode as any other probe:

```
baseline already red            -> UNKNOWN, the mutant proves nothing
mutation did not apply          -> UNKNOWN, no conclusion is available
applied and the suite went red  -> the test is alive
applied and the suite stayed green -> FINDING: the test does not check what it covers
```

"Applied" must be a measurement of the file, not the patcher's exit code:
sha256 before and after, plus a revert that restores the original hash. A
patcher that exits 0 having changed nothing, reported as "the test did not go
red", is the same lie one level up.

`cargo-mutants` copies sources to a temp dir rather than patching in place, and
refuses to draw conclusions unless the `Unmutated baseline` is green first.

**A retracted trap, kept as a case.** An earlier revision of this file described
a `CARGO_TARGET_DIR` trap here — a shared target dir supposedly making every
mutant test unmutated code, with a symptom, an "evidence" line and a fix. It
does not reproduce. A clean A/B on the same mutants: with the variable, 3 caught
in 51s; with `env -u CARGO_TARGET_DIR`, 3 caught in 49s. The cure cured nothing.

It is preserved here because how the false trap was built is worth more than the
trap would have been. Three misreadings, in order:

1. **A missing line taken for a missing event.** `cargo-mutants` does not print
   CAUGHT per mutant — only MISSED/TIMEOUT/UNVIABLE stream past, while caught
   ones land in the summary and in `caught.txt`. Grepping the stream for
   `^CAUGHT` returned zero. `caught.txt` for that same run held 21.
2. **Identical binary names taken for identical artifacts.** Cargo names a test
   binary from flags and features, not from source content, so mutants
   legitimately overwrite a file of the same name. The "evidence" rested on a
   misunderstanding of the format.
3. **A causal story built on those two and passed on as measured.**

**The rule this produces: a known-answer test must run before the first
conclusion, not after the first doubt.** Vigilance was present — the numbers
looked too uniform, and the instrument *was* investigated. The investigation was
also wrong, because it was built on the same misunderstanding. What works is
mechanical, not attentional: feed the instrument an input whose answer you
already know, and only then believe its output. In this case that input existed
all along — a hand-written mutation, which when finally applied failed 50 of 309
tests, proving the suite sensitive and the original finding **refuted**, not
merely unconfirmed.

**Never accept a zero result from an instrument you have not seen produce a
non-zero one** — but note that this phrasing is too weak on its own. Its author
formulated it and broke it three times in one hour, including once after it was
written down. A rule that needs vigilance is not a rule; the known-answer input
is the mechanism that makes it enforceable.

## Label every claim by who measured it

Two findings in this file were written from a peer's report and both were later
retracted by their author. Neither was ever reproduced here before being
committed. The reports were detailed, came with logs, and arrived from a source
whose earlier findings had all been correct — which is exactly the condition
under which an unverified claim gets adopted.

**A plausible report from a reliable source is not a measurement.** The fix is
not more scepticism, it is a label. Every claim carries one of three:

| Label | Means |
|---|---|
| **measured here** | reproduced in this repo, with the command that reproduces it |
| **reported** | someone else measured it; not verified here |
| **retracted** | withdrawn or refuted, kept visible with the reason |

A retracted claim is marked, never deleted. A citation that quietly disappears
leaves the reader believing it was never there, and the reasoning that produced
it — which is usually the valuable part — disappears with it.

The asymmetry worth remembering: **adopting a wrong finding costs more than
missing a right one.** A missed finding stays available; an adopted one gets
built on, and here it produced two commits and a stack-template edit that had
to be unwound.

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
