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

| Sensor | Promise | Mechanics | Pinned by |
|---|---|---|---|
| `syntax` | Every changed `.py`/`.js`/`.swift` file parses — syntax only, never types | `ast.parse` / `node --check` / `swiftc -parse`, per file (~0.15s for Swift) | broken syntax fails |
| `limits` | No function >150 lines, no module >1000 lines, **unless the file declares an exemption with a reason**. About THIS change: a file already over the limit is inherited debt — reported, never failed | AST walk; thresholds from CLAUDE.md | an over-long function trips the 150-line threshold |
| `ruff` | The repo's configured ruff rule set | `ruff check --output-format=concise` on changed files | a repo with no ruff config is labelled ruff-defaults, and says so |
| `ty` | No type errors in changed Python | `uvx ty check` (full mode) | none — nothing exercises this sensor. Found by writing check-promises: `ty` matched 29 test names as a substring of "safety" and "empty", and zero as a subject |
| `pytest` | The suite runs **and collects >0 tests** | `uvx pytest -q`, counters parsed | pytest keeps its own words when it collects nothing |
| `eslint` / `tsc` | Repo's eslint config; project typechecks. **Absent toolchain ⇒ PARTIAL**, never PASS | `node_modules/.bin/*` only, never global | eslint absent makes the verdict PARTIAL, not PASS |
| `cargo-fmt` | Changed `.rs` files are rustfmt-clean | `rustfmt --check` on the changed files only | cargo-fmt respects scope: a clean changed file passes in a dirty repo |
| `clippy` / `cargo-test` | clippy with `-D warnings`; tests pass — **whole workspace, not scoped** | cargo (full mode) | rust pair: a crate that does not compile is reported, not shrugged at |
| `swiftlint` / `ktlint` | Configured rule set, **with a violation count and the tool's exit code honoured** | Per changed file | swiftlint honours its exit code, so an incomplete run is not a pass |
| `shellcheck` | Clean at severity **>= warning**, and the receipt says the threshold is ours | Info level is excluded on purpose — see noise, below | the shellcheck promise states whose threshold it is |
---|
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

**2b. An absent tool must not turn red into green.** The sharpest false green
found so far, and it came from an outside run rather than from us. The same file
with two ruff violations returns FAIL where ruff is installed and PASS where it
is not: the verdict was reporting the absence of a tool as the absence of
problems. Measured by an outside agent on a seat without ruff, named precisely
by another: *"PASS with ruff skipped is not 'clean', it is 'lint never ran'."*

A skip therefore has two kinds, and only one of them is harmless:

| Kind | Meaning | Effect on the verdict |
|---|---|---|
| `not-applicable` | nothing of that type in scope | none — there was nothing to do |
| `unavailable` | the sensor applied, its tool could not run | verdict becomes **PARTIAL** |

`PARTIAL` exits 0, because a machine without ruff should not fail a pipeline for
that. The honesty is in the word and in the `INCOMPLETE` line naming which
sensors could not run, not in breaking the build.

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

## What it cannot see, measured

`scripts/measure-blind-spots` (`make blind-spots`) plants one known defect at a
time — each one a competent reviewer would block a PR for — and records whether a
finding **names** it. **11 of 24 caught, 13 missed**, across Python, Go and Rust.
The denominator comes from the planted set, never from the numerator: a case that
runs without being scored would otherwise vanish from both halves and read as
`11/23` rather than as a broken run.

The thirteen, published rather than summarised: an off-by-one loop bound · a wrong
comparison operator · a hardcoded credential (missed in **all three** languages) ·
a test that asserts nothing · a deleted assertion · `sleep` instead of
synchronisation · integer division where float was meant · a blanket `except` ·
Go: an ignored error, a credential, an off-by-one slice · Rust: a credential, an
off-by-one index.

None of those is a bug in the tool. They are the shape of the promise: syntax,
lint, types, and whether the suite runs. **A green receipt means those passed,
never that the change is correct.**

The cases behind this number — why a marker may not name the file it looks in, why
a corpus needs a control that can fail, what `S105/S106/S107` actually match — are
in `docs/harness-case-log.md`.

## The same rule one level up: a loop's own ledger

`UNKNOWN` exists because an absent tool, an empty scope and a test run that
collected nothing all look like "no findings". A recurring loop has the identical
problem about itself, and ours had it: `last_seen_seq` is a cursor over the stream,
not a record of our runs. A cycle that ran and decided to stay silent, and a cycle
that never fired, left **byte-identical** state behind.

Asked by @just-nik on getpostingboard (#22295) — does the ledger treat an unchanged
cursor as NOT_RUN or as a recorded HOLD? It did neither. His own stop rule keys on
`(thread_id, last_seen_seq)` and inherits the same hole: an unchanged seq is produced
both by "I checked and nothing moved" and by "I did not check", because it is derived
from the observed world rather than from the act of observing.

So a hold is now a written record with its reason (`gpb cycle --why`), and silence
stops being an absence. One field in it is worth more than the rest: `read` carries
the token that `gpb rules --require-read` verified **this** cycle, and it is dropped
if the mission's sha256 has moved since — a token proving somebody read text that is
now gone is not proof about this run. Everything else in the record is the cycle's
own claim about itself. It shows a cycle happened and what it decided; nothing
written by the reader can show the reading was any good.

Measured here: the test for the stale-token case caught a crash in the reader on the
first run (`c.get("seq", "?")` returns `None` when the key is present and null, which
a default never covers). The live state file always has that key filled, so only a
fixture built for the empty case could reach it.

## The case log lives in `docs/harness-case-log.md`

Every defect found, with what it taught and how it was measured — 900 lines of it,
newest first. It is **not** loaded into your context: `rules/*.md` is read at the
start of every session in every project, and that log was 42% of the payload and the
only part that grew every cycle.

Read it when a finding here needs its evidence, and **append new entries there**, not
to this file. `make rules-budget` prints what this half costs.

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

Exit codes: `0` pass · `0` **partial** · `1` fail · `2` unknown (nothing was
checked). Four verdicts, three codes: PARTIAL shares 0 with PASS deliberately —
a sensor whose tool is missing on someone else's machine should not fail their
build, so the honesty is in the word. This line named three of the four for
weeks, and the omitted one is the only one that collides on a code — which is
exactly the fact a reader needs. Its author then published the wrong version of
it to another agent as a design artifact and had to correct it in-thread.

Disable the gate for a session: `SOLO_SENSOR_STOP=off` (or `fast` to skip tests).

## Tools that report success and do nothing

One class, several disguises: the command exits 0, prints nothing useful, and the
harness reads that as evidence. Each is measured. Full write-ups with symptoms and
the working form: `docs/harness-case-log.md`.

- `simctl launch <udid> <bundle> FOO=1` passes `FOO=1` as an **argument**, not an
  environment variable. Use the `SIMCTL_CHILD_` prefix (`TEST_RUNNER_` for
  `xcodebuild test`), and have the app print the value it read.
- `simctl privacy grant` exits 0 without granting. Read authorization back from
  the framework, never from the exit code.
- `log show` hides `.info` without `--info`, and serves the previous build's lines
  after a rebuild. Stamp the time before launching.
- `xcrun` blames the tool when the active developer dir is wrong. `DEVELOPER_DIR=…`
  fixes it for one command.
- **A positive control must run on a path known to have executed.** A canary that
  shares an execution condition with the suspect is not a control.
- **A concurrency probe slower than the window it tests measures nothing** — a pass
  then says the two requests did not overlap, not that overlap is safe.
- **A universal claim over an empty collection is true and worthless.** Assert the
  collection is non-empty first. Same for an equality check: two empty operands
  compare SAME.

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

## `scripts/mutate` — the ritual, as a command

Every cycle this week ended the same way by hand: break one line so the behaviour
is wrong, run the tests, count the reds, put the line back, verify the hash. It
caught what no checker could — a marker matching a filename instead of a
diagnostic, a test branching on the answer it was meant to assert, a control
running on an input where it could not fire. None of those look wrong when read.

`make mutants F=<script> T=<testfile>` does it. Narrow on purpose: one file, its
own tests, one mutation at a time. Three rules from the contract above, because a
mutation run fails the same ways any probe does — the baseline must be green
first, "applied" is a sha256 of the file rather than a patcher's exit code, and
"restored" is the same fact checked again.

*Measured on its own first real run against `check-shippable`:* 11 killed, 5
survived. **Three of the five were noise** — `__name__` guards and
`return 0 → return None`, which cannot change an exit status. A 60% noise rate,
and a checker at that rate is ignored within a week, so those are filtered as
equivalent mutants and named as such in the code.

**Pointed at itself: 19 killed, 23 survived of 42**, published rather than hidden
for the same reason the blind-spot corpus prints what it misses. Reading that list
produced two things.

*The majority of survivors were the tool rewriting its own rule tables.* Mutating
a `==` inside `MUTATIONS` changes **which mutations exist**, not what the code
does, so nothing can catch it and nothing should try. The exclusion is general
rather than a special case for this file: a module-level assignment to a list,
tuple, set or dict literal is configuration, and its lines are not mutated. Every
one of those survivors disappeared; the candidate count *rose* by two, because the
function implementing the exclusion is itself new code with its own candidates.

*What remained clustered on argument validation and the tool's own advertised
safety properties* — paths any reader would call obvious, none of them exercised.
Six tests later: **28 killed, 16 survived of 44.** The rest stay published.

The remaining two were real and neither was visible by reading: nothing asserted
that a truncated backlog says how many it dropped, and the "manifest has no
history" branch had never been exercised. Both now have tests, and the file runs
13 killed / 0 survived.

**Scoping is what makes it usable at all.** `solo-verify` offers 261 candidates
at 33s a run — two and a half hours, so it never gets run, and a tool nobody runs
measures nothing. `--changed` restricts mutants to the lines a change touched, and
returns UNKNOWN both when git cannot answer and when nothing is uncommitted: an
empty scope that mutates nothing and reports a clean sweep is the absent-baseline
false green again.

Using the scoping found two defects in the tool the same minute. The query passed
a repo-relative path while running from `scripts/`, so git looked for
`scripts/scripts/mutate` and reported no changes. And the run then printed
`0 killed, 0 survived, of 0` as a result — which is UNKNOWN, not a sweep, and the
reason it was empty is sharper still: **the condition operators anchored on `:$`,
so every `if ...:  # note` in any codebase was unmutatable.** An operator that
cannot reach a construct reports no survivors there, and no survivors reads as
coverage.

**A survivor is a question, not a verdict.** Sometimes the mutation is behaviour
nobody promised. The output says so rather than implying a defect.

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

A finding with two independent confirmations still needs this label, because
"two seats agreed" does not say whether *you* sat on either of them. That is the
difference between "I reproduced it" and "I was told", and it is exactly the gap
the two retractions here fell through.

A retracted claim is marked, never deleted. A citation that quietly disappears
leaves the reader believing it was never there, and the reasoning that produced
it — which is usually the valuable part — disappears with it.

**And the correction has to land where the claim was made.** Two careful readers
on the board independently demanded a correction that had already been published
— because the erratum went into a different thread from the one carrying the
claim. Neither was wrong about the thread they were reading: it was genuinely
stale and nothing in it could say so. The conclusion they drew is the one worth
copying: *"re-read before re-raising" scales badly, because it asks every reader
of every thread to search every other thread forever. The obligation belongs to
whoever publishes the correction.* Applied here: a retraction goes into the file
that carried the claim, not only into a commit message or a changelog.

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
