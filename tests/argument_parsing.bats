#!/usr/bin/env bats
# argument_parsing.bats — CLI argument parsing tests
#
# Tests parse_args() from solo-lib.sh (real code, no copies).

load test_helper

setup() {
  common_setup
}

@test "requires project and stack arguments" {
  run parse_args
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "requires stack argument" {
  run parse_args "myproject"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "parses project and stack" {
  parse_args "myproject" "ios-swift"
  [ "$PROJECT_NAME" = "myproject" ]
  [ "$STACK" = "ios-swift" ]
}

@test "parses --from stage correctly" {
  parse_args "myproject" "ios-swift" --from build
  [ "$START_FROM" = "build" ]
}

@test "rejects invalid --from stage" {
  run parse_args "myproject" "ios-swift" --from "invalid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown stage"* ]]
}

@test "valid --from stages accepted" {
  for stage in scaffold setup plan build deploy review; do
    parse_args "p" "s" --from "$stage"
    [ "$START_FROM" = "$stage" ]
  done
}

@test "--max-hours sets timeout" {
  parse_args "p" "s" --max-hours 12
  [ "$MAX_HOURS" = "12" ]
}

@test "--no-retro skips retro" {
  parse_args "p" "s" --no-retro
  [ "$SKIP_RETRO" = "true" ]
}

@test "--no-autoplan skips autoplan" {
  parse_args "p" "s" --no-autoplan
  [ "$SKIP_AUTOPLAN" = "true" ]
}

@test "--no-dashboard sets flag" {
  parse_args "p" "s" --no-dashboard
  [ "$NO_DASHBOARD" = "true" ]
}

@test "--feature passes feature description" {
  parse_args "p" "s" --feature "user onboarding flow"
  [ "$FEATURE" = "user onboarding flow" ]
}

@test "--file passes context file" {
  parse_args "p" "s" --file "/tmp/research.md"
  [ "$CONTEXT_FILE" = "/tmp/research.md" ]
}

@test "--max sets iteration limit" {
  parse_args "p" "s" --max 25
  [ "$MAX_ITERATIONS" = "25" ]
}

@test "defaults: max_iterations=15 max_hours=6" {
  parse_args "p" "s"
  [ "$MAX_ITERATIONS" = "15" ]
  [ "$MAX_HOURS" = "6" ]
  [ "$NO_DASHBOARD" = "false" ]
  [ "$SKIP_RETRO" = "false" ]
  [ "$SKIP_AUTOPLAN" = "false" ]
  [ -z "$FEATURE" ]
  [ -z "$CONTEXT_FILE" ]
  [ -z "$START_FROM" ]
}

@test "multiple flags combined" {
  parse_args "lovon" "nextjs-supabase" --from build --feature "auth" --max-hours 3 --no-retro
  [ "$PROJECT_NAME" = "lovon" ]
  [ "$STACK" = "nextjs-supabase" ]
  [ "$START_FROM" = "build" ]
  [ "$FEATURE" = "auth" ]
  [ "$MAX_HOURS" = "3" ]
  [ "$SKIP_RETRO" = "true" ]
  [ "$SKIP_AUTOPLAN" = "false" ]
}
