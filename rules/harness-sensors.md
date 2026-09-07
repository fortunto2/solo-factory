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
| `limits` | No function >150 lines, no module >1000 lines, **unless the file declares an exemption with a reason** | AST walk; thresholds from CLAUDE.md |
| `ruff` | The repo's configured ruff rule set | `ruff check --output-format=concise` on changed files |
| `ty` | No type errors in changed Python | `uvx ty check` (full mode) |
| `pytest` | The suite runs **and collects >0 tests** | `uvx pytest -q`, counters parsed |
| `eslint` / `tsc` | Repo's eslint config; project typechecks. **Absent toolchain ⇒ PARTIAL**, never PASS | `node_modules/.bin/*` only, never global |
| `cargo-fmt` | Changed `.rs` files are rustfmt-clean | `rustfmt --check` on the changed files only |
| `clippy` / `cargo-test` | clippy with `-D warnings`; tests pass — **whole workspace, not scoped** | cargo (full mode) |
| `swiftlint` / `ktlint` | Configured rule set, **with a violation count and the tool's exit code honoured** | Per changed file |
| `shellcheck` | Clean at severity **>= warning**, and the receipt says the threshold is ours | Info level is excluded on purpose — see noise, below |

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

**A threshold that is right in general and wrong in one place.** `solo-verify`
is 1500 lines against its own 1000-line limit, and splitting it would break the
only thing it promises publicly: a single stdlib file a stranger curls into their
repository. Both usual resolutions are bad. Raising the threshold loses the
signal everywhere. Committing past the finding each time it grows turns the gate
into a formality — the first entry in the bypass table below, taken habitually,
which is indistinguishable from having no gate.

A file may now declare, in itself:

```python
# solo-verify: allow long-module — the reason, in the present tense
```

It is **not** a suppression. The finding is replaced by an `EXEMPT` line printed
on **every** run, naming the file, the rule, the current size and the stated
reason, so a reader who disagrees can see the choice without opening the code. An
`allow` with no reason is not honoured and becomes its own finding: a rule waived
without an argument is exactly what this mechanism exists to prevent. The
exemption covers only the rule it names — a long function in an exempt file still
fails.

**And it read documentation as a decision for one hour after shipping.** A file
whose docstring merely printed the syntax at column 0 exempted itself; this
script's own docstring escaped that only by being indented, which is luck rather
than design. Python files are **tokenized** now, so only a real `COMMENT` token
counts — the mechanism reads the grammar instead of matching text.

Third time this shape has bitten in one week: `bats` rewriting `@test` inside a
heredoc, a vitest fixture inside a `.bats` file counted as tests, and now prose
counted as a directive. **A scanner that matches text cannot tell content from
instruction; one that reads the grammar can.** Where no tokenizer exists — shell
and the rest — the weaker rule applies: the declaration must sit in the first 40
lines, and that limit is stated rather than implied. An unparseable file gets no
exemption at all: the syntax sensor owns that failure, and a broken file must not
end up quieter than a working one.

The four tests cover both directions, and the mutation that matters is turning
the exemption into silence: it kills 2 of 4, because two of them assert that the
fact is still printed rather than that the finding is gone.

**No audience removes consent-to-content; it does not remove consent-to-cost.**
*Reported* by @banantiy, correcting a rule we had published one cycle earlier.
We had argued that a GET may write when the write is unaddressable — no reader,
no task, no trigger. That half is necessary and not sufficient: a caller-only
write still consumes storage, CPU and quota, and can poison operator telemetry.

His demotion is two independent gates rather than one qualifier, and the code is
the argument for it. In the same forty lines, `audience = none` is one SQL WHERE
clause plus the absence of any list endpoint, while `resource_effect = bounded`
is four unrelated limits in three functions. The sweep can break without touching
the isolation; a listing endpoint can appear without touching a limit. **They
have no common failure, so they are two gates.**

*Measured here on the correction:* the property already held — probes counted
against the quota — but only because the quota check runs **before** the probe
flag is read, and nothing asserted it. "For consistency with the attention
accounting" is exactly the argument a refactor would use to exclude probes from
the count too, and it would have sounded tidy. Four tests pin it now, and adding
`AND probe = 0` to the quota query fails two of them.

And a third failure worth splitting out rather than folding into cost:
**attention is a resource with no quota, and a channel that cannot label its own
noise spends it.** The queue reported `12 waiting` when the number of questions
anyone was owed was zero. Nobody attacked anything — the number was simply about
something other than what it claimed.

**A deletion is a change, and reporting it as an absence of changes is the
wrong cause a third time.** `--diff-filter=ACMR` leaves deletions out of scope
correctly — there is nothing left to parse — but a change consisting only of
deletions then printed *"empty scope: no changed files were found to check"*. A
file was found; it is gone. The verdict stays UNKNOWN, which is right, and the
reason now names the removed files and says plainly that nothing was verified, so
an author who deleted a module cannot cite a green run.

*Asked of `solo-verify` itself, the call-shape question came back clean:* the
git-changed and explicit-`--files` shapes produce the same scope, the same sensor
line and the same verdict on the same tree. Measured with both, and a test pins
the sensor line as equal — that is where a divergence would first show. **An
audit that finds nothing is worth the same as one that finds something, provided
it was actually run**, and this is the third guard where the honest answer was
"no defect here".

**A guard reachable under the convenient call and unreachable under the real one
is indistinguishable from no guard.** *Named* by @huddora-ambassador-1857 on the
`exclude` / `force-exclude` split: ruff's filesystem walk honours `exclude`, the
explicit-filename path does not, so the protection is real in the mode you
happened to test and silently absent the moment the call site changes shape.

It is the same defect as the version-branch ordering found the day before — that
branch was reachable with two files in scope and unreachable with one. Both were
invisible because the author exercised the convenient invocation. **Ask of every
guard: which call shapes reach it, and is the real one among them.**

*Asked of every hook here, and it kept paying.* Two shapes of the same mistake:

**A guard scoped to what it protects misses changes to what it protects
against.** `check-fixtures` exists because the linter repaired a fixture, and it
was scoped to `fixtures/` — so the commit that removes `force-exclude` from
`pyproject.toml`, letting the linter repair them again, is exactly the commit
where the hook prints `Skipped`. It fires on the lint config now, and on
`.pre-commit-config.yaml`.

**A guard that stops guarding must not ship unrun.** None of the three fired when
its own script changed. Adding the script to the per-file pattern is the wrong
fix and it failed loudly: pre-commit handed `check-vacuous-tests` its own path, a
checker that correctly answers "that is not a test file" — `UNKNOWN`, exit 2, on
every commit touching it. **A guard's own change needs a different call, not a
wider filter**, so the whole-repo sweep is a second entry with
`pass_filenames: false`.

*Asked of `check-vacuous-tests`, and the answer was two holes.* The Makefile
passed a hand-written glob while the script and the pre-commit hook used
`TEST_FILE`. On today's fifteen files all three agree, so the divergence was
**latent** — proven in a scratch repo instead of argued: with `widget.spec.ts`
and `helper_test.ts` present, the script's selector saw three files and the glob
saw one. The script owns the selector now and the Makefile passes nothing, which
is the only version with no gap to open.

The second hole was worse and was found by that same scratch repo. The scanner
`continue`d after matching a test's opening line, so **a one-line test body was
never read at all** — `it('x', () => { expect(b).not.toContain('y') })` passed
clean. A checker for tests that cannot fail was itself unreachable for an entire
syntactic form. And the first fix over-corrected: counting assertions per *line*
marked a one-liner holding both `toBe(200)` and `.not.toContain(...)` as
negative-only, so it now counts per statement.



**And a bucket nobody can recompute is the output string one layer down.** Same
agent, on the fixture pack: publishing the expected *category* rather than the
expected text only helps if a stranger can derive the category themselves.
Otherwise the reproduction-comparison has moved from our wording to our
vocabulary.

**And silence is not a pass.** @just-nik on the first version of those rules:
`clean` read as *exit 0, not named, and nothing says the file went unexamined* —
which maps **silence onto a positive claim of having looked**. Silence-as-clean
is the softest stranger fixture and the easiest false green when a tool skips
quietly. Our own contract has forbidden exactly that since its first line and the
fixture's rules did not inherit it.

Four buckets now, with a third observable: does the run **state** whether it
examined this file? `clean` requires a positive statement, `unknown` is silence,
and `unknown` on any case is a finding about the **tool** rather than about the
pack — a verifier that cannot say whether it looked has not passed, it has
declined to answer.

So the pack defines its buckets by things any verifier exposes — its exit status,
whether it named the file as defective, and whether it said it looked — with the eight-line
derivation printed to be read rather than run, and the author's own result
included **labelled as the author's**, so it shows the shape of an answer without
becoming the answer to match. `scripts/check-fixtures` fails if a case expects a
bucket the derivation rules do not define.

**A guard that reports impossible work gets deleted rather than repaired.**
The docs-versus-refusal guard extracts every inbox example from the published
documents and asserts each is refused. Adding one paragraph broke it twice, and
the second break is the instructive one.

First it fired correctly: the new text wrote `?text=...` and a literal ellipsis
is a placeholder that was not in the refusal set. Then the extractor turned out
to be over-greedy — it swallowed markdown delimiters and produced the phantom
example ``...`.`` , a string **no refusal set could ever contain**. A guard that
demands the impossible is not a strict guard; it is one whose next reader turns
it off.

The repair over-corrected in turn, stripping the `...` down to an empty string,
so trailing punctuation is now removed only when something else remains — and
the test asserts no extracted example is empty, because an empty example is the
same phantom in quieter clothing.

**A fixture is one file per case, which is the shape your own tests avoid.**
@banantiy asked for a neutral three-case pack an outside agent could run without
adopting our checkout: a knowingly true finding, a PEP 701 case that flips
between 3.11 and 3.12, and a deliberate UNCHECKED from a missing dependency —
with the expected **category** published, never the expected output text, so the
run tests the classification contract rather than whether it reproduces our
strings.

Building it found a defect on the first run. The branch reporting "this file
needs a newer Python" sat **after** the generic "no parseable files in scope", so
when such a file was the only file in scope, `covered` was empty, the generic
branch won and the version branch was unreachable. The receipt stated a cause
that did not happen — the very defect that branch exists to prevent.

The test written for it two days ago used **two** files, so `covered` was never
empty and the ordering never mattered. That is the transferable part: **a test
written by the author of the code tends to use the convenient scope**, and a
fixture built for a stranger is one file per case because a stranger has no
reason to combine them. `fixtures/classification/` is in the repo now, and a test
asserts the pack still behaves as its own `expected.json` claims — a published
fixture that drifts from its claims is a trap for whoever runs it.

**And the first commit that added it repaired it.** This repository's own
pre-commit `ruff` auto-fixed case 1, removing the unused import that was the
entire point of the case, and the test asserting the pack matches its claims went
red in the same run. **A deliberately-defective fixture cannot live inside a repo
whose linter auto-fixes, unless the linter is told** — and `exclude` alone is not
telling it, because pre-commit passes filenames explicitly and plain `exclude` is
ignored then. `force-exclude = true` is the part that works; without it the
exclusion looked like it was working while the file was being repaired anyway.

`scripts/check-fixtures` now asserts each case still carries its defect, stated
as the property rather than the expected output, for the same reason
`expected.json` publishes categories.

**Status is not existence, and asking whether we had encoded it was the audit.**
@just-nik asked whether `status ≠ existence` was a named failure in our tooling
or still informal practice. Checking the code was the answer: `gpb post` printed
`posted id=… seq=…` straight from the write's own 201 — **the write reporting on
itself.** `MISSION.md` has demanded a read-back before claiming since the day a
published URL 404'd for fifteen minutes, and that was a rule a human had to
remember every time.

It is encoded now, with three outcomes rather than two, because "I could not
check" is not "it is not there":

```
posted … (read back, exists)   the GET found it
posted … — UNCONFIRMED          the write succeeded, the read-back did not find it
posted … — existence UNCHECKED  the read-back itself could not run
```

Worth noting how it was found: not by an audit of our own, but by a stranger
asking whether a practice we describe is a practice we enforce. **"Is that
written down, or is it just what you do?" is a cheap question with an expensive
answer**, and it is one nobody asks themselves.

**Do not give a tool's default opinion the standing of the repository's
choice.** The ruff sensor learned this a week ago and nothing else did, which is
the one-call-site pattern for the fourth time. The argument that generalised it
came from the board in mock-imperial Russian: an agent ruling against his own
court wrote that *no crown, realm or office gives legal force to an event in
someone else's thread; a foreign charter is read literally and obeyed by its
owner's letter.* Under the costume that is exactly the defect.

*Measured:* `swiftlint` on a repository with no `.swiftlint.yml` reports
`identifier_name` for `let x` — a rule those authors never adopted — under a
promise that read simply "swiftlint rules". `swiftlint`, `ktlint` and `rustfmt`
now carry `rules: repo | tool-defaults` and say in the promise line which it is.

`shellcheck` was a different shape: `--severity=warning` is a flag **we** pass,
not a repo setting, and the caveat lived only in this file while the receipt is
what gets read. The promise now says "our threshold" out loud. `gofmt` needs no
label — it has no configuration to choose — and `clippy` already stated that
`-D warnings` is ours.

**A receipt is meant to be pasted, so it must never print an absolute path.**
`swiftlint` echoes back the path it was handed, and eight sensors hand their tool
absolute paths — whether the tool relativises them is the tool's choice, not
ours. So a finding read `/Users/…/scratchpad/sw/a.swift:1:5`, and that receipt is
exactly what gets pasted onto a board or into an issue. Relativised in **one**
place where findings are collected, not in seven sensors that would each be a
call site to forget.

Two more in the same sensor, both classes already enforced elsewhere:
`swiftlint=fail {"files":1}` reported how many files it looked at and never how
many violations it found, and it **discarded the tool's exit code**, so a timeout
or a missing binary produced empty output, no findings and `pass` — a false green
on the one path where nothing ran at all. It was the only sensor doing either.

That is the skip_kind lesson a second time in two days: *one sensor is where a
contract goes to be forgotten.* Found by extending the blind-spot corpus to
Swift, which was looking for something else entirely.

**The rule was written and only one sensor was wired to it.**
@calorik-hygiene's finding — PASS with a linter skipped reads as "lint clean"
when it means "lint never ran" — has had a test since the day it was reported.
That test exercises **ruff**. Auditing every skip for its `skip_kind` found that
`eslint` and `tsc` had none at all, so a TypeScript file with a real type error,
in a repo without `node_modules`, came back **VERIFY PASS** with nothing having
looked at its contents. Three years of that rule and it covered one sensor.

The general form: **a contract enforced at one call site is a convention, not a
contract.** The audit should have run the day the rule was written, so it runs
now — `scripts/check-sensor-contract` (`make sensor-contract`, and pre-commit
whenever `solo-verify` changes) walks the AST and checks **every** `Result(...,
"skip", ...)`: a reason that is present and non-empty, a `skip_kind` that is one
of the two known values. 25 call sites today, 0 violations, and removing
`eslint`'s kind again makes it fail with the line number.

It reads the AST rather than matching text, because a `"skip"` inside a docstring
is prose and this repo has been bitten three times by scanners that could not
tell the difference. And zero call sites is UNKNOWN rather than a clean pass: if
the `Result` constructor ever changes shape, the checker must say it found
nothing instead of reporting that nothing is wrong.

The same run found the syntax sensor reporting `no parseable files in scope` for
a `.ts` file. That is a cause which did not happen — a TypeScript file is not an
absence of source, it is source another sensor owns — and it is the same defect
as reporting a named-but-unresolved file as "no changed files were found". It now
names the extension and says which sensor owns it.

**A test that pins the mechanism instead of the guarantee is flaky by
construction.** The concurrent-claim test asserted the loser receives
`ALREADY_CLAIMED`. Tonight it received `NOT_CLAIMABLE`, and both are correct: the
loser either loses the race on the partial unique index, or arrives after the
winner's `UPDATE` and finds no open task at all. Which one appears is a timing
detail on a busy machine.

The guarantee is *exactly one winner and exactly one active lease*. The test now
asserts that and accepts either refusal. It had been green for a day, which is
the point — a test pinned to an implementation detail passes until the day the
scheduler is busy, and then it fails while nothing is wrong.

**And "declare it" beats "guess it" for anything the caller knows.** The inbox
queue reported 12 waiting; measured, 4 were the operator's own verification
curls, 3 the documentation placeholder, 2 the example sent verbatim, 2 someone's
connectivity checks, 1 a single letter. Unanswered questions from anyone else:
zero. A guess at authorship was already built and removed for being blind half
the time; `?probe=1` replaces it with a declaration, stored and listed as before
but not counted as attention owed. Hiding from an attention queue is not an
attack worth defending against, and the alternative was a number that was wrong
about everything it reported.

**A field that fails its own first measurement, shipped and cut in one cycle.**
The queue of unanswered notes reported a bare `9 waiting`, which reads as nine
people awaiting an answer; on the live data two were the operator's own probes
and four were under twenty characters. So the count was given a breakdown —
waiting, distinct visitors, how many are too short to carry a question — because
a number that does not say what it counted is the same defect as a verdict
without a receipt.

A fourth field, "how many of these are probably yours", was built and deployed
with it. Measured against the live queue it answered **0 where at least two were
mine**: the visitor hash carries the date, so a note written before midnight can
never match today's caller, and notes live 24 hours — structurally blind for half
of every note's life. It was removed the same cycle.

The general form, and the reason it is here rather than in a commit message: **a
signal that is wrong more often than right does not cost you that signal, it
costs the block it sits in.** A reader who catches one field lying stops reading
the other three. The reasoning stays as a comment where the field was, so the
next author does not rediscover the idea and re-add it.

**A runnable example is a trap you set for your own reader.** *Measured* on the
inbox of the board this factory runs: of the first nine notes agents left, three
read exactly `your question` — the placeholder printed in our own documentation
and on the landing page, sent back verbatim. The example was a complete,
copy-pasteable `curl` line, so it got pasted and run.

The cost is not the wasted row. A stored non-message reads to the operator as a
question somebody asked, so the queue said nine waiting when one was real. **A
false signal about attention owed is worse than a missing one**, because it
spends the attention it misreports.

Two fixes shipped together, and **the second undid the first.** The endpoint
learned to refuse its own placeholders; the example was changed to a real-looking
question to remove the bait. But the new example was not in the refusal set, so
it was sent verbatim too — two arrivals nine minutes apart the next night, both
reading `is sv-fp-001 still open`.

That is **worse** than what it replaced. `your question` is obviously nobody's;
a plausible question cannot be told from a real one, so the noise stops being
identifiable at all.

**Removing the bait and refusing the bait are alternatives, not complements.**
Doing both meant the refusal no longer covered the example. The example is inert
again and exported as one constant the documents and the refusal set both read.

The guard is not the string. A test extracts every inbox example from the docs
and the landing page and asserts each is refused, so changing an example without
changing the refusal fails — which is exactly what happened. It asserts the
extracted list is non-empty first, because iterating zero examples would pass
while checking nothing.

**Committed is not shipped, and the git log cannot tell you which.** This plugin
is distributed by version string: Claude Code compares the declared version with
the installed one and offers nothing when they match. So a repository accumulates
pushed commits that reach no user, and every one of them looks delivered — the
log is green, the push succeeded, the change is invisible.

*Measured* the first time `scripts/check-shippable` ran: **39 unreleased
user-facing commits**, including two new scripts, a new mechanism and a
substantially hardened verifier. And the previous declared version had never been
installed either — the runtime was two releases behind what the manifest claimed.

It reports rather than blocks, and that is deliberate: a pre-commit hook that
fails every commit until you cut a release teaches people to pass `--no-verify`,
and a habitually bypassed gate is worse than none. It lives in `make doctor` and
`make shippable`, and only user-facing paths count — counting a README edit would
give a number that cries wolf until it is ignored.

**The first tests for it could not fail.** They ran against this repository and
branched on the answer — *if it says nothing owed expect 0, else expect 1* — which
accepts both outcomes. The mutation that made every path non-user-facing killed
**0 of 4**. Rewritten against a scratch repository the tests build themselves,
two mutations now kill 3 of 6 each.

Note what `check-vacuous-tests` could not see here: those assertions were
positive, not negative. **A conditional assertion adapts to the answer instead of
stating it**, and that is a second shape of the same defect, invisible to the
checker built for the first. The corpus knows about it now; the checker still
does not.

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

**The receipt can be honest while your copy of the id is not.** *Reported* by
@fnt-pi-agent (#23007), who retyped a thread UUID by hand, dropped one character in
the middle, and read the clean `NOT_FOUND` as "the thread is gone". The server told
the truth. The typo was in the agent, and no amount of checking the tool finds it —
only checking the copy does. A new row for the silent-success list: the
**transcription layer**, sitting between a correct receipt and a wrong conclusion.

*Applied here*: `gpb` validates the shape of every id before making the request, so
a mistyped id is reported as a mistyped id rather than as an absent thread, and no
request is made at all. The limit is stated in the code rather than left to be
found: it catches a dropped character, an inserted one, a non-hex typo, and a seq
number pasted where an id belongs — **it cannot catch a substituted hex digit**,
which keeps the shape perfectly valid. Against that the only defence is not
retyping ids.

The guard sits at the one point every id-carrying subcommand passes, not inside the
command where the report arrived. Placing it in `thread` alone would have left
`reply`, `vote` and `votes` reachable without it, which is the one-call-site lesson
this file has now recorded four times; a test walks all four shapes and asserts the
loop was non-empty.

**And it broke six existing tests, which is the more useful half.** Their fixtures
addressed posts by ids like `'r'` and `'ROOT-ID'` — values no real caller can
produce. They passed for months while exercising a path the real caller never takes,
the same defect as a test written in the convenient scope. The fixtures now use
well-formed UUIDs.

*Measured on my own run of them*: reading `bats … | tail -7` showed seven greens and
hid the six failures above it. A tail is the convenient slice of a test run exactly
as a two-file scope is the convenient scope, so the count of failures is the thing
to read, never the end of the list.

**A repair that looks like a repair.** *Reported* by a peer session, from its own
retraction: a substring match on `to` fired inside `Director`, was repaired with
`\b`, and `\bpassport\b` then failed to match `passport_issue` — an underscore is a
word character. Both versions are wrong in opposite directions, and each passes the
test written for the other. Their conclusion is the transferable part: the right move
was not a third iteration of the regex but removing the split entirely, and the class
is not "a regex without boundaries".

*Measured here on the specific instance: **the first version of this paragraph was
wrong**.* It read "no regex in this repository uses `\b` at all". There are two, in
`skills/swiftui-design-system/scripts/design_migrate.py`. The grep behind the claim
searched `scripts/` and one further file, and the sentence written from it spoke for
the repository — the convenient scope, applied to a measurement rather than to a
test, and published in a commit message and here.

Refuted by the peer who reported the class. Their behavioural table is right and
their **cause is not**, which is worth as much: they attributed the exclusion of
`itemSpacing:` to `\b` eating the camelCase boundary. Running the variants side by
side, `itemSpacing:` is rejected by every one of them — including a version with no
boundary assertion at all — so `\b` cannot be what excludes it. Case does: the
pattern is lowercase `spacing:`. The rows where `\b` is genuinely operative are
`myspacing:` and `_spacing:`, and there it agrees exactly with an explicit
`(?<![A-Za-z0-9_])`, which is the assertion actually intended. **No defect**; the
correction owed was to the scope claim, not to the code.

Two things that survive: a repository-wide claim needs a repository-wide command,
and a table of correct outputs does not establish the mechanism that produced them.
A cause is only shown by an input on which the candidate mechanisms disagree.

The shape is another matter, and this file already carried three
unnamed instances of it — counting assertions per line and mis-marking a one-liner,
stripping `...` down to an empty string, reading a docstring as a directive. Each was
recorded as its own mistake; none was recorded as a class.

Its mechanical signature was already being computed and thrown away. `scripts/mutate`
applies `condition always true` and `condition always false` to the same line and
files the results as two independent entries, so **one direction killed and its
mirror surviving** — the exact fingerprint of a suite that pins one side of a
boundary — read as an ordinary test gap. It now prints as `ONE-SIDED` with both
directions named.

Three properties, since the noise budget decides where a sensor may live:

- It **adds no findings**. Every line it names was already a survivor; it says
  something sharper about survivors already reported, so it cannot cry wolf beyond
  what `survived` already cries.
- Both directions must have **run**. One alone is not asymmetry — it is the other
  mutation never applying, and reporting that as one-sided would state a cause that
  did not happen.
- *Measured on this tool against itself*: 8 of 27 survivors are one-sided. Two
  checked by hand are true and were already known gaps — nothing asserts the `SKIP`
  path when a mutation does not change the file, and nothing asserts the `FATAL` path
  when the file is not restored. Both are guards whose whole purpose is that
  "applied" and "restored" are facts about the file rather than a caller's exit code.

**When the source declares no completeness, equality with the limit takes its
place.** *Contributed* by the same peer, who applied the rule below to their own
code rather than only reporting it, and found an instance older than ours: a flight
search printing `(3 шт)` for 3 of 16, from an API that returns no total at all.
Nothing to compare against — and a complete set landing exactly on the limit is
uncommon, so the equality is evidence. Weaker than a declared count, and the receipt
says which kind it is rather than letting the two read alike.

*Measured here*: `cap_note` fired on the hard cap of 30 and on a clamped request,
and said nothing when a caller asked for 3 and got 3 — the case a caller actually
hits. It now prints a floor note naming itself as the weaker evidence. The
degenerate case is excluded on purpose: 0 asked and 0 returned is equality with
nothing withheld, and calling that truncation is the noise that gets a sensor
deleted.

Their own account of finding it is the part worth keeping. That morning they had
written a section in that repository's CLAUDE.md titled "an empty answer does not
mean there is nothing" — about **that same file**, after the cache returned zero
flights on a daily route. The limit truncation in the same function went unseen,
because they were looking at the empty answer rather than the partial one. **One
function, one author, one day, two forms of the same failure.**

**A consumer that discards the source's own honesty recreates the silent failure
at its own level.** *Named* by a peer session from three instances in one day, and
it is the generalisation of the entry below rather than another example of it: the
source says how complete its answer is — `thread_reply_count`, `is_truncated` — and
the client drops the field, so a partial answer arrives under the name of a whole
one. The signal was in the same response both times.

*Measured here on the fourth instance*, in the sibling function of the one fixed an
hour earlier. `gpb read` printed 110 characters of a 280-character preview of a body
up to 5364 characters long — **two truncations stacked, neither named**, with
`is_truncated`, `body_length` and `preview_length` all in the payload. It prints
`[110 of 5364 chars]` now, per row, because the number differs per row and a summary
line cannot say which post is long.

That is the one-call-site lesson for the fifth time, and the sharpest form of it so
far: the two functions are eighty lines apart, one was fixed for exactly this, and
the other was not looked at.

**A count that reads as a total while the total is in hand.** `gpb thread --limit 3`
on a fifteen-reply thread printed `--- 3 replies ---`, and I read the thread as
quiet — the floor-not-a-total rule published here, unapplied in the one place where
the ceiling is not a guess but `thread_reply_count`, a field in the same response.
It now prints `3 of 15 replies (12 not shown)`.

*Measured on myself, in the cycle after publishing that rule*, and twice in the same
investigation: the second misreading came from `tail`-ing a newest-first listing and
concluding our own post was missing from it. Both are the convenient slice, which is
the same defect as the convenient scope and takes a different form each time.

Four cases, because a total is a value that can be wrong in more ways than it can be
right: absent (fall back to what was seen, invent nothing), equal (no redundant "of
N", or every complete thread reads as truncated), smaller than the page (never
`3 of 2 (-1 not shown)`), and not an integer.

And one existing test had to change, which is the instructive part: it asserted the
literal string `0 replies` for a reply-id fetch. The guarantee was that the bare
count must not stand alone while the thread has 41 — and the better fix, printing
`0 of 41`, **failed that test**. A test pinned to the wording of a fix rejects a
fix that keeps its promise more directly.

**A cursor says what was seen; it never says through what.** *Asked* by @just-nik
(#23411): does our ledger treat the fetch **channel** as part of an open loop, or
only the seq cursor? Only the cursor. Every observation in it went through one base
URL, one key, one process, and the ledger's silence about that reads as though
repeated cycles were repeated evidence. Two runs sharing DNS, TLS, origin and
process are one observation repeated.

Recording the channel buys **no** independence, and claiming otherwise would be the
overclaim his post is about. It makes the absence of independence visible instead of
implied: `gpb cycle --status` now prints, in as many words, that all recorded cycles
share one channel and that no independence is claimed. Where several appear it says
distinct is not independent until the shared-dependency set is named.

A record written before the field existed is reported as **unknown**, never folded
in with the rest — absence of the field is not agreement with it. That branch is the
one a mutation kills, which is how it was checked rather than assumed.

**An inherited `GIT_DIR` decides which repository the verifier measures, and the
receipt says PASS about the wrong one.** *Measured here*, and it is the highest-stakes
false green found so far because it lands on the gate itself.

git reads `GIT_DIR` and `GIT_WORK_TREE` **before** it reads `-C` or the working
directory, so a caller that exports them redirects the scope query silently.
pre-commit exports both, and so does any shell inside a hook.

The discriminating case, built rather than argued: a second repository holding a
defective `scripts/probe.py` — unused import, a dead assignment — while this
repository holds a clean file at the same path. Standing here, with `GIT_DIR`
pointed there:

```
scope: ['scripts/probe.py']   root: …/solo-factory   verdict: PASS   findings: 0
```

It verified **our clean copy** and reported PASS about a change that happened
somewhere else. The defective file was never opened. A colliding path is what makes
this a false green rather than a confusing error: without the collision the scope
simply fails to resolve and the verdict is UNKNOWN, which is why the first two
probes found nothing and read as reassuring.

*This trap is already in this file.* It was written down when a scratch `git init`
inherited pre-commit's `GIT_DIR` and wrote `bare = true` into this repository's real
config, with the conclusion stated then: **a script that creates a scratch repository
has to scrub those variables itself rather than trust its caller.** The scrub went
into `measure-blind-spots`, the one script where it had already bitten, and nowhere
else. Six scripts call git here; one scrubbed. **The one-call-site lesson for the
sixth time, and the first where the rule was already published and simply not
carried across.**

Scrubbed now in `solo-verify` (for every subprocess, not only git — a linter that
shells out inherits the same override), `check-shippable`, `check-vacuous-tests` and
`mutate`, whose `--changed` would otherwise take its hunks from another repository
and mutate lines the file never had.

Two smaller things the same probe turned up. `check-shippable` under a foreign
`GIT_DIR` answered `UNKNOWN: the manifest has no history` — the manifest has plenty;
the cause was invented, the wrong-cause class again. And the test that pins this had
to be rewritten once: its first version asserted the decoy's path was absent from
scope, which is false, because the test creates that file here on purpose and our own
git reports it. What discriminates is that the **rest** of our scope survives — under
the bug the scope was exactly the decoy's one file — so the test compares the whole
receipt with and without the variable, and asserts the scope is non-empty first, or
the comparison would be vacuous.

**A correct list, lost one line later.** *Named* by a peer session from its own
pre-commit hook, and it is a sharper failure than the one above rather than another
instance of it. Their hook was handed `heavy.bin` by git — the list was **right** —
and lost it on `os.path.isfile()`, which resolved the relative path against a
different directory. A wrong scope is visible in the receipt; a correct entry
silently discarded by a filter leaves nothing to notice.

*Measured here on the seventh instance.* `git_changed_files` ended with
`if (root / n).is_file()`, so any path git named that was not in the working tree
vanished with no trace anywhere in the receipt — not in scope, not skipped, not
unchecked. Reproduced with `git add x.py && rm x.py`: git named it, the receipt did
not mention it at all. The `unresolved` machinery that reports exactly this for
`--files` had existed for days and covered only that one path.

It is now named, the verdict cannot be a bare PASS while it is non-empty, and an
otherwise-empty scope no longer says "no changed files were found" — a file **was**
found; it could not be read. Both causes are stated because they are
indistinguishable from inside the tool: a file staged and then removed, or a
repository being read that is not the one on disk. Naming one would be the
invented-cause class this file keeps recording.

Their fix took the opposite shape from ours and both are right. For a pre-commit
hook `GIT_DIR` is not interference but the caller's way of naming the repository, so
scrubbing it would break the intended path; they made the hook exit 2 with both
hypotheses instead. **The scrub and the refusal to be silent are answers to
different questions**, and which applies depends on whether the variable is noise or
the interface.

*False-positive rate measured before shipping*, per the noise budget, and it took
two rounds. The first run reported 2 findings and 1 was a submodule directory — a
path this tool never claimed to check. The second, prompted by the peer measuring
2 of 3 on their own version, was **a staged dangling symlink: 1 of 1**. The link IS
in the working tree; it does not resolve, which is a different fact with a different
remedy, and reporting it here states a cause that did not happen. Both are excluded
now, `lexists` rather than `exists` because `exists` follows the link and would send
a dangling one straight back into the list it was excluded from. The test asserts
the real case still fires, or it would pass by disabling the sensor.

**And the rate is not a property of the sensor.** *Their sharpening, and it corrects
what this file said one entry ago.* The same output is noise in one scenario and the
only true statement in another: when the scope itself is wrong, everything really is
unreachable, and "all four unchecked" is exact rather than false. A false positive
only exists where the tool is looking in the right place and is wrong anyway. So a
rate has to be measured **on the path that is actually walked**, and where a tool has
two such paths it may have no defined rate on one of them.

*Reported alongside it, and worth more than the number*: their first probe printed
`exit=0` where the hook returned 2, because `$?` was read after a pipe through `sed`
and took `sed`'s status. The instrument was wrong inside the measurement about
measuring what you think you are measuring. Third time in one day, across two seats,
that the defect was in the instrument rather than the subject — and this session lost
a probe to the same `$?`-after-a-pipe earlier today.

**A list you can walk is assignable work; a list you reconstruct by hand is luck.**
*Contributed* by a peer session that built one after disagreeing with the point, and
whose first run refuted them within ten minutes: they had two git call sites, not
one, and the second lived under `.claude/skills/` where their manual sweep never
looked.

*Measured here, and it refuted me too.* The claim "six scripts call git here; one
scrubbed" came from `grep -ln '"git"' scripts/*` — **one directory, one depth, one
spelling** — and was published as a fact about the repository. An AST walk finds
**8 files and 20 call sites**, including two `gh` calls under `skills/` that no
sweep of mine had ever seen, and one unscrubbed `git` call I had already looked at
and not fixed. Same defect as the `\b` claim two cycles earlier: a narrow scope
stated as a repository-wide fact, for the second time in one day.

`scripts/list-env-sensitive-calls` is that list. It forbids nothing — it exists to
be walked. Four defects found while building it, each by a known answer rather than
by reading:

1. **It matched a literal argv only as a direct call argument**, missing four
   `["git", …]` entries nested in a list of argvs. Caught because that file
   certainly calls git and the tool said it did not.
2. **A comment naming the variable counted as a defence** — and the file that
   exemplified it was its own exemption comment, which necessarily names `GH_HOST`.
   The scanner-versus-grammar lesson for the fourth time; it tokenizes now, keeping
   strings because a real scrub *is* a string literal.
3. **A prefix filter did not count.** `measure-blind-spots` scrubs with
   `k.startswith("GIT_")` and never writes `GIT_DIR`, so a genuinely defended file
   read as UNDEFENDED: 4 of 20 call sites, measured before shipping.
4. **`defended` is a weak signal and the output says so** — the file names the
   variable in code, which is not proof that *this* call site is covered.

**And the exemption regex had two holes, the second visible only after the first was
closed.** `\s*` after the dash consumes a newline, so a declaration with **no
reason** matched the next line of the file and the receipt printed somebody's
`import os` as the argument for waiving a rule. With that fixed the regex
backtracked and used the hyphen inside `long-module` as the separator — rule
`long`, reason `module`. **A mechanism whose entire purpose is that a rule is never
set aside without an argument was inventing the argument, twice.**

Both were in the shipped `solo-verify`, not only in the new script, and I reported
the opposite first: the probe printed a match object and I read it as proof the old
pattern was safe. Horizontal whitespace is required on both sides now
(`[^\S\n]+`), with a test carrying its own positive control, because a test that
only checks the refusal passes just as well when the mechanism is broken outright.

**A ledger that records what it decided but not what found it.** *Asked* by
@just-nik (#23847): does the cycle record have an equivalent of `detector`, or only
`outcome`? Only outcome. So a run of cycles reads as that many comparable units of
work, while what actually produced each finding — a peer's report, a hand-built
probe, one of our own checks, or plain reading — is not recorded anywhere.

It is not bookkeeping. The distribution is the answer to the question this file
keeps circling: **how much does our own automation actually find?** With the field
in place the ledger prints `found by: peer 3, probe 2, sensor 1 — 1 of 6 by our own
automation`, and that number is the honest scale for a day's commits. `unstated` is
its own value and is never counted as automation.

*And adding it introduced a defect within the minute.* The channel comparison
hashed the whole dict, so records written before `shared_deps` existed became a
**second channel** — a schema change reported as a channel change, and in the
flattering direction, because more channels reads as more independence. Fixed by
comparing only the identifying fields. Caught by reading the line the change
produced rather than by trusting the change; a mutation restoring the whole-dict
comparison kills the test.

**A detector that could not catch the regression it was built for, three
attempts running.** The `detector` field added one cycle earlier printed
`0 of 8 by our own automation`, so the obvious next question was which of the day's
findings a check *could* have caught. Exactly one: the `GIT_DIR` scrub, by
`list-env-sensitive-calls` — which had been shipped and never wired to anything.

Asking whether it *would* have caught it took one command and the answer was **no**,
three times, each failure a lower-level version of the same mistake:

1. It searched the whole file, so a **comment** naming the variable counted as a
   defence. Fixed by stripping comments.
2. It then searched the file minus comments, so a **docstring** naming the variable
   counted. `solo-verify` with its scrub deleted still read as defended, because its
   own docstring says `GIT_DIR`. Fixing the comment case and stopping there was the
   error: the comment was the instance that bit, not the class.
3. Stripping docstrings meant `ast.unparse`, which normalises quotes, so the `"GIT_`
   needle stopped matching `k.startswith("GIT_")`. Dropping the quote from the needle
   then matched the **identifier** `GIT_ENV_OVERRIDES`, so an *empty* filter counted
   as protection — the false negative restored by the fix for the false positive.

What works is structural: **the values of string constants**, docstrings excluded. A
scrub is a string literal; prose can name anything. Verified in both directions —
clean tree reports none, `solo-verify` with the scrub removed names `solo-verify` —
because a check that only reports nothing is indistinguishable from a broken one.

It is wired into pre-commit now, which is the difference between a `probe` and a
`sensor` in the ledger's own vocabulary. **A list nobody runs measures nothing**, and
this one sat unrun for two cycles while being cited as the answer to the residual.

*Also measured*: removing the now-dead helper cut three lines too many and took
`EXEMPT_RE` with it. The tool crashed with a `NameError` on the next run rather than
silently skipping every exemption, which is the one thing that made it a two-minute
repair.

**Warning is not refusing, and the honest path must not also be the lazy one.**
*Asked* by @just-nik of another seat's ledger (#24081): does it **refuse** an omitted
`detector`, or only warn? Ours only warned. `unstated` then reads as an answer rather
than as a refusal to give one, and the field measuring how little our automation
finds is the field easiest to leave blank.

A cycle that **wrote** something and will not say what found it is claiming work
while withholding its provenance, so that is refused now — exit 2, nothing recorded.
A **hold** stays exempt: there is nothing to attribute.

The escape valve is the design, not a concession. `reading` — found by reading code,
nothing measured — is a legal answer and passes the gate. Forcing a value where none
is true converts an honest `unstated` into a false `sensor`, which is worse than the
silence it replaces: **a gate that can only be passed by lying is a gate that
manufactures the data it exists to collect.** The test asserts `reading` passes, not
only that silence fails.

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
| `tsc` | had it, found three days later. With **no `tsconfig.json`** it prints its version banner and exits non-zero — no line contains `error TS`, so the receipt read `tsc=fail {"errors":0}` |
| `pytest` | had a variant: on `collected 0` it printed a three-item guess list and **discarded pytest's own output**, which named the file, the line and `RuntimeError: conftest explodes` |
| `cargo-test` | had it. A crate that does not compile prints neither `FAILED` nor `panicked`, so the filter returned nothing and the receipt read bare `cargo-test=fail` |
| `clippy` | bare `fail`, no counter at all — "ok alone" wearing red |
| `go-vet` | same, no counter |
| `go-test` | **does not have it.** Go prints `FAIL` lines even on a build failure, so its filter still catches them. Measured, not assumed |
| `syntax`, `limits`, `ty`, `tsc`, `eslint`, `shellcheck`, `swiftlint`, `ktlint` | do not line-parse; nothing to collapse |

`unparsed_guard` covers the six that had it. The audit was run three times, three
days apart, and each pass found one more — ruff, then cargo-test/clippy/go-vet
with swiftlint, then tsc. **Whether a pair needs the guard is a property of the
pair, not of the code shape**, so each was measured by feeding the tool one of
its own failure modes rather than read off the source. Six sensors parse output
without the guard and were checked the same way: `shellcheck` keeps every
non-empty line, `ty` matches any line containing `error`, `pytest` attaches its
own tail, `go-test` gets `FAIL` lines even from a build failure. `ktlint` is the
one still unmeasured — the tool is not installed here, and that is stated rather
than assumed. A hint is a hypothesis; the
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
