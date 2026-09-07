#!/usr/bin/env bats
# list-env-sensitive-calls — the list exists so it can be walked.
#
# A grep over `scripts/*` produced "six scripts call git; one scrubbed", published
# as a fact about the repository. It covered one directory at one depth. A peer
# session made the mirror mistake the same hour: their hand sweep missed a git call
# under `.claude/skills/`. Neither of us was undisciplined; neither of us had a list.

L="${BATS_TEST_DIRNAME}/../scripts/list-env-sensitive-calls"

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  D="$BATS_TEST_TMPDIR/r"
  mkdir -p "$D/deep/nested"
}

@test "a nested argv literal is found, not only a direct call argument" {
  # The first version matched a literal only as a DIRECT argument of a call and
  # missed four ["git", ...] entries inside a list of argvs. Caught by known-answer.
  cat > "$D/deep/nested/thing.py" <<'EOF'
import subprocess
STEPS = [
    ["git", "init", "-q", "."],
    ["git", "config", "user.name", "t"],
]
for s in STEPS:
    subprocess.run(s)
EOF
  run python3 "$L" "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"deep/nested/thing.py"* ]]
  [[ "$output" == *"2 call site(s)"* ]]
  [[ "$output" == *"UNDEFENDED"* ]]
}

@test "a prefix filter counts as a defence" {
  # measure-blind-spots scrubs with k.startswith("GIT_") and never writes the
  # literal GIT_DIR. A genuinely defended file read as UNDEFENDED: 4 of 20 call
  # sites on the first run.
  cat > "$D/pref.py" <<'EOF'
import os, subprocess
E = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
subprocess.run(["git", "log"], env=E)
EOF
  run python3 "$L" "$D"
  [ "$status" -eq 0 ]
  [[ "$output" == *"defended"* ]]
  [[ "$output" != *"UNDEFENDED"* ]]
}

@test "a comment naming the variable is not a defence" {
  # The exemption comment necessarily names GH_HOST, and the first version read
  # the whole file — so a file exempting itself also read as defended. A scanner
  # matching text cannot tell content from a statement about content.
  cat > "$D/comment.py" <<'EOF'
import subprocess
# GIT_DIR would redirect this, and one day somebody should deal with that.
subprocess.run(["git", "log"])
EOF
  run python3 "$L" "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDEFENDED"* ]]
  [[ "$output" != *"comment.py:3    git      defended"* ]]
}

@test "a declared exemption is printed with its reason, never swallowed" {
  cat > "$D/waived.py" <<'EOF'
# list-env-sensitive-calls: allow git — this hook is HANDED the repository by its
# caller, so the variable is the interface here rather than noise.
import subprocess
subprocess.run(["git", "log"])
EOF
  run python3 "$L" "$D"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXEMPT"* ]]
  # The reason is one line — the first. A wrapped continuation is not picked up,
  # which is a limitation rather than a defect, and it is stated here so the next
  # reader does not take the truncation for a bug.
  [[ "$output" == *"HANDED the repository"* ]]
  [[ "$output" != *"import subprocess"* ]]   # and it must not absorb the next line
}

@test "an exemption with no reason is not honoured" {
  cat > "$D/bare.py" <<'EOF'
# list-env-sensitive-calls: allow git —
import subprocess
subprocess.run(["git", "log"])
EOF
  run python3 "$L" "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNDEFENDED"* ]]
  [[ "$output" != *"EXEMPT"* ]]
}

@test "finding nothing is UNKNOWN, never a clean sweep" {
  cat > "$D/plain.py" <<'EOF'
x = 1
EOF
  run python3 "$L" "$D"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" == *"a walk that failed"* ]]
}
