#!/usr/bin/env bats
# The published fixtures are broken on purpose, and must stay broken.
#
# fixtures/classification/ exists so an outside agent can check the
# classification contract on their own tree. Every file carries a defect
# deliberately, and the pack is worthless the moment one is repaired — which this
# repository's own pre-commit ruff did on the first commit that added it,
# removing the unused import that was the entire point of case 1.

C="${BATS_TEST_DIRNAME}/../scripts/check-fixtures"

@test "the pack is intact and says how many cases it checked" {
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ([0-9]+)\ fixture\ case ]]
  [ "${BASH_REMATCH[1]}" -ge 3 ]
  [[ "$output" == *"0 repaired"* ]]
}

@test "a repaired case is caught and named" {
  run python3 -c "
import sys, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
import tempfile, json, shutil, os
d = pathlib.Path(tempfile.mkdtemp())
shutil.copytree(m.PACK, d / 'p')
# Repair case 1 the way ruff --fix would.
f = d / 'p' / '01_true_finding.py'
f.write_text(f.read_text().replace('import os\n', ''))
m.PACK = d / 'p'
sys.exit(m.main())
"
  [ "$status" -eq 1 ]
  [[ "$output" == *"01_true_finding.py"* ]]
  [[ "$output" == *"repaired and useless"* ]]
}

@test "a missing pack is UNKNOWN, never a clean bill" {
  run python3 -c "
import sys, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
m.PACK = pathlib.Path('/nonexistent/pack')
sys.exit(m.main())
"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing was checked"* ]]
}

@test "the linter leaves the fixtures alone" {
  # force-exclude, not exclude: pre-commit passes filenames explicitly and plain
  # `exclude` is ignored then. Without it the hook repaired the file anyway and
  # the exclusion looked like it was working.
  run uvx ruff check --no-fix "${BATS_TEST_DIRNAME}/../fixtures/classification/01_true_finding.py"
  [ "$status" -eq 0 ]
  [[ "$output" != *"F401"* ]]
}

@test "every expected bucket is one the derivation rules define" {
  # @huddora-ambassador-1857: a bucket name nobody can independently recompute
  # just moves the reproduction-comparison from our output string to our
  # vocabulary. A case expecting a bucket the rules never define is exactly that,
  # and a reader trusting the file would never see it.
  run python3 "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 repaired"* ]]
}

@test "a bucket the rules do not define is caught" {
  run python3 -c "
import sys, json, shutil, tempfile, pathlib, importlib.util, importlib.machinery
loader = importlib.machinery.SourceFileLoader('c', '$C')
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec); sys.modules['c'] = m; loader.exec_module(m)
d = pathlib.Path(tempfile.mkdtemp()) / 'p'
shutil.copytree(m.PACK, d)
e = d / 'expected.json'
j = json.loads(e.read_text())
j['cases'][0]['expect'] = ['a_bucket_nobody_defined']
e.write_text(json.dumps(j))
m.PACK = d
sys.exit(m.main())
"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a_bucket_nobody_defined"* ]]
  [[ "$output" == *"cannot recompute"* ]]
}

@test "the derivation rules are stated in observable terms, not our wording" {
  F="${BATS_TEST_DIRNAME}/../fixtures/classification/expected.json"
  run python3 -c "
import json
d = json.load(open('$F'))
h = d['how_to_derive_the_bucket']
print(' '.join(x.split(':')[0] for x in h['observe']))
print('|'.join(h['buckets'].values()))
"
  # Both observables must be things any tool exposes: an exit status and whether
  # it pointed at the file.
  [[ "${lines[0]}" == *"exit"* ]]
  [[ "${lines[0]}" == *"named"* ]]
  # And the rules must be written in those terms, not in ours.
  [[ "${lines[1]}" == *"exit"* ]]
  [[ "${lines[1]}" == *"named"* ]]
}
