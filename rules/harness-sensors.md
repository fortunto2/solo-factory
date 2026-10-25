# Sensors — what the harness measures, and what it promises

Feedforward (skills, rules, CLAUDE.md) steers the agent before it acts; the sensors
observe after it acts, so mistakes self-correct before they reach you. This is the
contract. The reasoning and measurements behind every line are in
`docs/harness-sensors.md` (not loaded; read it when a rule needs its why).

## The three placements

| Where | What runs | Budget | Why there |
|---|---|---|---|
| **Every Edit/Write** (`sensor-edit.sh`) | Syntax only — parse the one file just written | <1s | A semantic check here floods the agent with errors from files it has not reached yet mid-refactor, and it reverts good work to silence them |
| **End of turn** (`sensor-stop.sh`) | `solo-verify --full`: lint, types, tests | <120s | The step boundary. Cross-file meaning is only well-defined once the agent thinks it is done |
| **Commit** (pre-commit) | Formatting, repo-specific gates | seconds | Already yours; unchanged |

The middle one blocks. If the receipt is red, the turn cannot end — so
"I finished" stops being a claim the agent makes about itself.
An UNKNOWN blocks **once per input**: the same verdict on byte-identical files
(names and contents) does not block the next turn again. FAIL always blocks.

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
| `ty` | No type errors in changed Python | `uv run --with ty` where the project declares dependencies, `uvx ty check` otherwise (full mode) | none — nothing exercises this sensor. Found by writing check-promises: `ty` matched 29 test names as a substring of "safety" and "empty", and zero as a subject |
| `pytest` | The suite runs **and collects >0 tests** — when the change has a Python file or manifest; otherwise not-applicable | `uv run --with pytest` where the project declares dependencies, `uvx pytest -q` otherwise; counters parsed | pytest keeps its own words when it collects nothing |
| `eslint` / `tsc` | Repo's eslint config; project typechecks (tsc only when the change has TS/JS or its manifest). **Absent toolchain ⇒ PARTIAL**, never PASS | `node_modules/.bin/*` only, never global | eslint absent makes the verdict PARTIAL, not PASS |
| `cargo-fmt` | Changed `.rs` files are rustfmt-clean | `rustfmt --check` on the changed files only | cargo-fmt respects scope: a clean changed file passes in a dirty repo |
| `clippy` / `cargo-test` | clippy with `-D warnings`; tests pass — **whole workspace, not scoped**, run only when the change has a `.rs` or Cargo file | cargo (full mode) | rust pair: a crate that does not compile is reported, not shrugged at |
| `swiftlint` / `ktlint` | Configured rule set, **with a violation count and the tool's exit code honoured** | Per changed file | swiftlint honours its exit code, so an incomplete run is not a pass |
| `shellcheck` | Clean at severity **>= warning**, and the receipt says the threshold is ours | Info level is excluded on purpose — see "On noise" in `docs/harness-sensors.md` | the shellcheck promise states whose threshold it is |
---|
Tooling never crosses languages: Python sensors never touch a `.ts` file.

## Rules the receipt obeys

1. **"ok" alone is forbidden.** Every run prints `ran` / `skipped` / `UNCHECKED`.
2. **Zero scope is never a pass.** Nothing checked → `UNKNOWN`, exit 2. A test run
   that collects 0 tests fails.
3. **An incomplete run is not a result.** Exit 124/126/127 → a skip with a reason,
   checked *before* the output is parsed.
4. **An absent tool must not turn red into green.** A skip is `not-applicable`
   (nothing in scope, no effect) or `unavailable` (tool could not run → **PARTIAL**).
   "Not installed" is a claim about the hook's PATH, and the receipt says so.
5. **A sensor obeys the scope, or its promise says it does not** (clippy, cargo test).
6. **A promised sensor that says nothing is a harness defect** → `HARNESS GAP`, UNKNOWN.
7. **Editing the harness is loud, not forbidden.** Tests and lint configs in a change
   print as `HARNESS TOUCHED` with a sha256; sometimes the rule is what is wrong.
8. **A green receipt means syntax, lint, types and the suite passed — never that the
   change is correct.** Measured: 11 of 24 planted defects caught (`make blind-spots`).
9. **Never accept a zero from an instrument you have not seen produce a non-zero.**
   Feed it a known-answer input first. Label claims *measured here* / *reported* /
   *retracted*; a retraction goes where the claim was made.

## Usage

```bash
solo-verify                  # fast: syntax + lint on changed files
solo-verify --full           # + types + tests
solo-verify --files a.py     # explicit scope
solo-verify --json           # machine-readable receipt
make verify / make verify-full
make mutants F=<script> T=<testfile>   # does the suite go red when a line is wrong
```

Exit codes: `0` pass · `0` **partial** · `1` fail · `2` unknown (nothing was
checked). PARTIAL shares 0 with PASS deliberately: a tool missing on someone
else's machine should not fail their build, so the honesty is in the word.

## Bypasses, listed so using one is a decision

| Bypass | Effect | When it is legitimate |
|---|---|---|
| `git commit --no-verify` | Skips pre-commit entirely | A broken hook environment, never a red check |
| `SOLO_SENSOR_STOP=off` | Stop gate does nothing | Long unrelated session; set it deliberately, not to escape a finding |
| `SOLO_SENSOR_STOP=fast` | Skips types and tests | Slow suite, mid-exploration |
| Editing a lint config or test | Changes what counts as a pass | Genuinely wrong rule — reported as `HARNESS TOUCHED`, not blocked |
| Running the tool outside a git repo | Empty scope | Nothing to verify; returns UNKNOWN, not PASS |
| A tool missing from the hook's PATH | That sensor cannot run | Reported as a skip naming PATH, never as a pass |

## The case log lives in `docs/harness-case-log.md`

Every defect found, with what it taught and how it was measured — 900 lines of it,
newest first. It is **not** loaded into your context: `rules/*.md` is read at the
start of every session in every project, and that log was 42% of the payload and the
only part that grew every cycle.

Read it when a finding here needs its evidence, and **append new entries there**, not
to this file. `make rules-budget` prints what this half costs.
