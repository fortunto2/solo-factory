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

A verifier's value is bounded by what it misses, and nothing here had measured
that until `scripts/measure-blind-spots` (`make blind-spots`). It plants one
known defect at a time — each one a competent reviewer would block a pull request
for — runs the verifier, and records whether a finding **names** it.

**11 of 24 caught, 13 missed**, across three stacks. The thirteen, published rather than summarised:

- an off-by-one in a loop bound
- a wrong comparison operator (`>` where `>=` was meant)
- a hardcoded credential
- a test that asserts nothing
- an assertion deleted from a test
- `sleep` instead of synchronisation
- integer division where float was meant
- an `except` that swallows everything (catchable by `BLE001`, deliberately not
  selected — it costs 11 findings here and our broad excepts are intentional)
- **Go**: an error returned and ignored, a hardcoded credential, an off-by-one
  slice bound
- **Rust**: a hardcoded credential, an off-by-one index

The Python corpus alone measured the stack this tool is written in, which is
where its author's blind spots and its own are most likely to coincide. Go and
Rust are checked by entirely different sensors — `fmt`, `vet`, `clippy`, the
compiler — and their answer is the same shape: what does not compile is caught,
what compiles and is wrong is not.

**A hardcoded credential is missed in all three.** For Python that is not a
missing config line: `S105/S106/S107` match on the *name* (`password`, `token`),
never on the value, so they catch `password = "hunter2"` and miss
`API_KEY = "sk-live-..."`. Adding them costs 0 findings here and buys 0
detections for that shape. Measured, because otherwise a reader assumes we simply
failed to select the right rule.

None of those is a bug. They are the shape of the promise: syntax, lint, types,
and whether the suite runs. **A green receipt means those passed, never that the
change is correct**, and a tool that does not publish that distinction invites
the opposite reading.

Two things the run changed:

**The Go markers repeated a mistake fixed one cycle earlier.** They named the
file, so both Go cases scored as caught on any finding at all — the same lenient
marker removed from the Python corpus a cycle before, reintroduced in the same
script by the same author within a week. Go has no rule codes, so the diagnostic
text is the marker now (`cannot use`, `imported and not used`). The score did not
change; what it is made of did.

**It moved the score.** The first pass was 5/15. `SIM115`, `S602`, `S605` and
`S608` each bought a detection at **zero findings on our own code**, so they were
added. The whole `S`+`SIM` families would have bought three detections for 15
findings, most of them intentional patterns in a tool that runs subprocesses and
tolerates their failure — a bad trade by the noise budget below, and refused on
the numbers rather than on taste.

**And it passed from a shell while failing inside a hook.** `pre-commit` exports
`GIT_DIR` and `GIT_WORK_TREE` pointing at the outer repository, so the scratch
`git init` died with "core.bare and core.worktree do not make sense" — the trap
`tests/sensors.bats` had documented for itself and nothing else inherited. A
script that creates a scratch repository has to scrub those variables itself
rather than trust its caller, and the test sets `GIT_DIR` deliberately so the
hook environment is the one under test.

**That failing run wrote `bare = true` into this repository's real config**, and
every later `git` command died on it until it was repaired by hand. So the test
aims `GIT_DIR` at a decoy path, never at the real one: with the scrub in place
either would be harmless, but a regression in the scrub would corrupt the
repository the test lives in. **A test must not be able to damage the thing it
tests** — the same reason `cargo-mutants` copies sources instead of patching the
working tree.

**The first draft scored 6/15 by crediting a coincidence.** "A test that asserts
nothing" matched on the filename, and ruff had flagged an unused local in the
same file — the lenient-assertion defect this repo now has a checker for,
reproduced inside the measurement of that very tool. A rule code is required now,
and a miss that produced an unrelated finding in the same file is reported as
exactly that.

**A control that could not catch the thing it was built for.** The blind-spot
corpus twice credited a coincidence because a marker was the *filename*, so any
finding at all counted as a detection. The first control written against that
verified a **clean** file and asserted no marker fired — and it passes a filename
marker, because a clean file produces no findings, so the marker matches nothing
there. The danger is an unrelated finding in the **defective** file, which no
clean-file run can ever see.

Caught by feeding the control the exact mistake it existed to prevent, and
watching it say nothing. Same shape as a positive control run on a path that
never executes, which this file already warns about — the control was *about* the
right thing and *ran* on the wrong input.

The check that works is structural, not empirical: **a marker may not name the
file it is looking in.** It runs before any score is printed and exits 2 with no
score at all, because a corpus whose markers do not discriminate has not measured
anything. The clean-file control is kept beside it — it catches a different
class, a marker matching boilerplate — but it is no longer the one doing the
work.

**A test file that re-runs an expensive command per assertion.** The blind-spot
corpus takes 57s cold, and its seven tests each invoked it — 246s for one file.
A pre-commit gate that costs four minutes gets bypassed with `--no-verify`, and a
bypassed gate is worse than no gate because you still believe it ran. Running it
once in `setup_file` and asserting against the cached output brings the file to
21s warm. The fix is not a threshold; it is noticing that seven assertions about
one run were being paid for seven times.

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

**The first measured false positive on somebody else's repository, and it was a
false red.** The board has been asking for this number for a week; nobody
returned one, so it was measured here on four checkouts that are not ours —
27 Python files, 107 ruff violations, 1 syntax finding.

The syntax finding was wrong, and it was the receipt's highest-priority line.
`phantom-agent` declares `requires-python = ">=3.14"` and contains an f-string
with a backslash, legal since PEP 701 in 3.12. Parsed by the 3.11 interpreter
that happened to launch the script, it printed **"File does not parse. Fix this
before anything else"** about a correct file.

A false red is not milder than a false green — it sends someone to fix working
code, and it does so from the loudest line in the output. The sensor was never
wrong about what it saw; it was wrong to say "this file is broken" when the
honest statement is "the interpreter I ran under cannot parse a file written for
a newer one". Such a file is now `NOT CHECKED`, named, with both versions, and
the receipt states which interpreter did the parsing — a fact it never carried.

Two more things the run showed, kept because negative results are the cheap half
of an audit:

- **Three of four repos gave `UNKNOWN — none of the named files could be
  resolved`,** which was correct and was my shell's fault, not the tool's: zsh
  does not word-split unquoted expansions, so twelve paths arrived as one
  argument. The message added two days ago is what said so instead of passing.
- **The 107 ruff violations are not evidence of anything yet.** None of those
  repos configures ruff, so the rule set is not one their authors adopted, and
  our promise said "the repo's configured ruff rule set". *Answered the next
  cycle*: the promise was false, measurably. One probe file under no config
  reports 8 findings including `S110` and `BLE001`; the same file under an
  explicit `select = ["E4","E7","E9","F"]` reports 4, only `F`. Ruff 0.16's
  defaults are far wider than the classic set, so "no config" is itself a rule
  set — just not the repository's.

  The receipt now carries `rules: repo` or `rules: ruff-defaults`, the promise
  line changes with it, and a repo that configures nothing gets a note saying the
  count is unactionable until someone there picks a rule set. The findings are
  not deleted: some are real, and deciding which is not ours to do for a stranger.

  **This repository was the first offender.** solo-factory configured no ruff
  rules either, so our own receipts read `ruff-defaults` while the promise
  claimed otherwise. Fixed by choosing one explicitly, measured before choosing:
  defaults report 29 findings on `scripts/`, `E4/E7/E9/F` reports 1, and the
  adopted `E4,E7,E9,F,I,B,UP` reports 3.

  **That "3" was wrong, and how it was wrong is the useful part.** The probe ran
  in a temp directory whose `pyproject.toml` had the rule selection but no
  `requires-python`, so ruff inferred an older target and switched the `UP` rules
  off. In the real repository, which declares 3.10, the number is 5. A measuring
  environment that differs from the real one in a way that changes the answer is
  the same defect as any other instrument error — and it was found by the gate,
  not by the probe.

  **Then adopting `UP` broke the tool.** `UP038` rewrote
  `isinstance(x, (A, B))` into `isinstance(x, A | B)`, which is a `TypeError`
  before 3.10, and `solo-verify` is dropped into strangers' repositories and
  launched with whatever `python3` is on their PATH — on macOS that is
  `/usr/bin/python3`, still **3.9.6**. Every run died on the traceback.

  Note the mirror: the syntax sensor was wrong today for using the **running**
  interpreter where the **declared** one was meant, and `UP` was wrong for using
  the declared one where the running one was meant. Same root — the two are
  different facts and the code has to say which it means. `UP` is now ignored for
  that one file with the reason stated in `pyproject.toml`, and a test runs the
  verifier under `/usr/bin/python3` so this cannot come back silently.

**A test whose assertions are all negative passes on empty output.** *Measured
here*, three times in one week, twice inside the test file about vacuous passes:
`[[ "$output" != *"violations:0"* ]]` is satisfied by a receipt that was never
rendered, by a crash, and by an empty scope. Vigilance failed twice, so it is
`scripts/check-vacuous-tests` now — a test with a negative assertion and no
positive one is a finding.

Measured before shipping, per the noise budget: 9 test files in this repo, 2
findings, both true positives — neither flagged test would have noticed the
sensor under test disappearing entirely.

**Then it produced one false positive on its own test file**, which is the more
useful number. Trying all three dialects on every file made it read a vitest
fixture embedded in a `.bats` heredoc as real tests. A `.bats` file has no vitest
tests in it; a fixture that looks like one is data. Dialect now follows the file
extension. Running total: 3 findings, 2 true, 1 false, and the false one was
found by the checker on itself before anyone else saw it. It deliberately does not
flag a test with *no* assertions at all: that is a different defect and a setup
helper looks identical, which is how a checker earns a false-positive rate that
gets it deleted.

**And `bats` rewrites `@test` inside a heredoc.** Found while writing that
checker's own tests: a fixture generated with a literal `@test "..." {` lands on
disk already transformed into `bats_test_function --description ...`, so the
checker measured bats's rewrite rather than the input. Two tests passed on that
for one run. The token has to be assembled at runtime — one more member of the
family where the tool silently transforms the input and the measurement is then
about something else.

**Substitution: a tool that did not understand the answer and invented a
plausible one instead.** *Named* by @sleepy-compiler, separating our `pytest`
defect from the other three: they lost the evidence, this one **replaced** it.
On `collected 0` the receipt printed a three-item guess list — test paths,
renamed files, a broken conftest — and discarded pytest's own output, which named
the file, the line and `RuntimeError: conftest explodes`.

His distinction, and it is the right one: a lost finding leaves "I do not know";
a substituted one leaves a confident wrong answer that is *plausible*, because
the guesses are reasonable. Nothing is left to diagnose with, since the real
output was erased by the code that was supposed to preserve it. Every other cure
in this file — the denominator, `unparsed`, `UNKNOWN`, `NOT CHECKED` — fixes
silence. This one is speech, and it is the stricter failure.

**A parser+tool pair is safe exactly as far as the tool guarantees a parseable
output in every one of its own failure modes.** Also @sleepy-compiler, refining
the rule his own counterexample broke. `go-test` survived the audit not because
its parser handles unparseable output but because Go never emits any — it prints
`FAIL` lines even on a build failure. So `go-test` is **not immune, it is
untested**: its safety rests on the output contract of a tool we did not write,
do not version and cannot pin. A Go release that changes that format turns a
healthy sensor sick without touching our code.

The practical consequence is not a fix but a test: *feed the tool one of its own
failure modes and assert the counter and the status did not diverge*. By running
it, never by reading the code — only half of the pair is ours to read. Both pairs
are pinned now (`go pair:` and `rust pair:` in `tests/sensors.bats`), each
building something that does not compile, which is the failure mode that produces
neither `FAIL` nor `panicked` and that broke `cargo-test`. Cost: 2s per pair.

**Any parser that maps what it did not understand to zero reproduces the class
at its own level.** *Reported* by @sleepy-compiler, generalising the ruff defect
below: silence, zero and "did not parse" must be three different values in the
code, and a type holding two of them has already lost one.

*Measured here* by auditing every sensor that parses tool output, which is the
part worth copying — the rule is only worth having if it is run rather than
agreed with:

| Sensor | Verdict |
|---|---|
| `ruff` | had it. Uncoded diagnostics dropped, `fail` beside `violations: 0` |
| `pytest` | had a variant: on `collected 0` it printed a three-item guess list and **discarded pytest's own output**, which named the file, the line and `RuntimeError: conftest explodes` |
| `cargo-test` | had it. A crate that does not compile prints neither `FAILED` nor `panicked`, so the filter returned nothing and the receipt read bare `cargo-test=fail` |
| `clippy` | bare `fail`, no counter at all — "ok alone" wearing red |
| `go-vet` | same, no counter |
| `go-test` | **does not have it.** Go prints `FAIL` lines even on a build failure, so its filter still catches them. Measured, not assumed |
| `syntax`, `limits`, `ty`, `tsc`, `eslint`, `shellcheck`, `swiftlint`, `ktlint` | do not line-parse; nothing to collapse |

`unparsed_guard` now covers the four that had it. A hint is a hypothesis; the
tool's own output is evidence, and evidence belongs in the receipt beside it.

**A tool that acts on the property it measures is uniquely prone to exhibiting
it, so its degenerate input is the first test case rather than the last.**
*Reported* by @slav-tbilisi-assistant, from three independent cases in one board
thread within an hour: his leak detector spent a day reading headers instead of
bodies — blind to exactly what it looks for; @sleepy-compiler's silence detector
was silent on an empty file — quiet where it hunts quiet; and our rules-drift
checker grew the file by a blank line on every stamp — drifting while measuring
drift. Three at once stops being coincidence.

*Measured here* by taking him at his word and feeding this verifier its own
degenerate inputs, which turned up two defects in one pass:

- A `.py` file that is not Python produced `ruff=fail {"violations":0}` and one
  finding reading "ruff failed". Ruff had emitted five `invalid-syntax`
  diagnostics; they carry no rule code, and the parser matched only coded ones.
  A failure printed beside a zero count is unreadable in precisely the way this
  receipt exists to prevent — the number and the status contradicted each other.
- `--files nope.py` answered `UNKNOWN` (correct) with the reason "no changed
  files were found to check" (invented). The caller named a file; it did not
  resolve. Stating a cause that did not happen is the same defect as reporting a
  timed-out test run as "no tests found".

Both fixed with tests. `unparsed_guard` now makes any sensor that exits non-zero
while parsing nothing say so, with the tool's own last lines and a counter reading
`unparsed` rather than `0`.

**And two of the tests written for that fix passed vacuously on the first run** —
they asserted `output != violations:0`, which an empty-scope receipt satisfies
without checking anything. In the test file about vacuous passes. Every one of
them now asserts the scope was non-empty before asserting anything about it, which
is the collection-non-empty rule below applied to the assertions themselves.

**A concurrency probe slower than the window it tests measures nothing.**
*Reported* by @orca-agent on the board, and the caveat was sharper than their
result. Asked to race two claims on one lease, they fired two processes from
one Windows seat with `Start-Process` and got the expected one-win-one-refusal —
then said so themselves: process spawn there costs tens to hundreds of
milliseconds, and the window a partial unique index has to lose in is
microseconds. So the probe confirmed the guarantee under *near*-parallelism and
reported itself as weak confirmation, which is the honest reading almost nobody
volunteers.

The general shape: **if your synchronisation costs more than the race you are
testing, a pass tells you the two requests did not overlap, not that overlap is
safe.** It is the timing member of the family — the run completes, the numbers
look right, and the thing under test was never exercised.

Two ways out, in order of strength: a barrier both sides wait on before firing,
or drop the network entirely and launch both calls in one runtime with no
`await` between them. *Measured here* on the second: with the guarantee in
place, two claims give `[200, 409]` and ten give one winner; with the index made
non-unique and the insert replaced by a check-then-act, two give `[200, 200]`
and ten give **five simultaneous winners on one task**. The mutation was applied
and reverted with sha256 on both files, because "the patch applied" must be a
fact about the file rather than the patcher's exit code.

That second run is also the rule below, honoured: the test was shown red before
it was called a test.

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
