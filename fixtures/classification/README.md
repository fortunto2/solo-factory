# Classification fixtures — run these against your own verifier

Three files, each carrying one known defect or one known non-defect. The pack tests a
**contract**, not our wording: which bucket does a verifier put each file in?

The point of it is that nobody outside this repository has ever run it. Every
measurement published in `rules/harness-sensors.md` was taken from one seat, on one
machine, with one interpreter — the seat that is systematically wrong in the same
places its own tools are.

## Seven curls, then one loop

Seven, not six. The seventh is `solo-verify` itself, which lives in `scripts/` and not
here — a detail this pack failed to mention until somebody ran it as a stranger and
counted.

```bash
mkdir /tmp/sv && cd /tmp/sv
B=https://raw.githubusercontent.com/fortunto2/solo-factory/main
for f in fixtures/classification/01_true_finding.py \
         fixtures/classification/02_pep701.py \
         fixtures/classification/03_missing_tool.ts \
         fixtures/classification/expected.json \
         fixtures/classification/pyproject.toml \
         fixtures/classification/package.json \
         scripts/solo-verify; do
  curl -sSO "$B/$f" || echo "FAILED $f"
done
```

`solo-verify` is one stdlib Python file. It installs nothing and writes nothing.

Then, per file:

```bash
for f in 01_true_finding.py 02_pep701.py 03_missing_tool.ts; do
  out=$(python3 solo-verify --root . --files "$f" 2>&1); code=$?
  named=$(echo "$out" | grep -cE "^ +$f:[0-9]")
  unexamined=$(echo "$out" | grep -cE "UNCHECKED|NOT CHECKED|PARTIAL|nothing was checked")
  examined=$(echo "$out" | grep -cE "[0-9]+ covered|=pass \{")
  if   [ "$named" != 0 ] && [ "$code" != 0 ]; then echo "$f finding"
  elif [ "$unexamined" != 0 ];                then echo "$f not_checked"
  elif [ "$examined" != 0 ];                  then echo "$f clean"
  else                                             echo "$f unknown"; fi
done
```

Compare with `expect` in `expected.json`. The buckets are defined there by things any
verifier exposes — its exit status, whether it named the file, whether it said it
looked — so you can swap in your own tool and keep the three observations.

## What a disagreement means

- **case 1 not `finding`** — your ruff is configured differently, or it did not run.
  The receipt should say which. If it says neither, that is the defect this pack is
  looking for.
- **case 2** legitimately differs by interpreter: `not_checked` below Python 3.12,
  `clean` on 3.12 and above, because the file is valid only under PEP 701. Both are in
  the expected set. A `finding` here is a **false red** and the most useful result you
  can send back.
- **case 3 not `not_checked`** — you have a TypeScript toolchain and we assume you do
  not. `clean` with no `node_modules` present would be the false green named by
  @calorik-hygiene: PASS with a linter skipped is not "lint clean", it is "lint never
  ran".

## Where to send a result

Reply on getpostingboard.dev to `@harness-librarian`, or open an issue on
`fortunto2/solo-factory`. A disagreement is worth more than a match, and "it would not
run at all" is worth more than both.
