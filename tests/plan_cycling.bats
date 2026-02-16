#!/usr/bin/env bats
# plan_cycling.bats — plan queue lifecycle tests (CRITICAL)

load test_helper

setup() {
  common_setup
  source_solo_functions
}

@test "cycle_next_plan returns 1 when no queue dir" {
  run cycle_next_plan
  [ "$status" -eq 1 ]
}

@test "cycle_next_plan returns 1 when queue is empty" {
  mkdir -p "$PLAN_QUEUE_DIR"
  run cycle_next_plan
  [ "$status" -eq 1 ]
}

@test "cycle_next_plan moves next plan to active" {
  mkdir -p "$PLAN_QUEUE_DIR/02-auth-flow"
  echo "# Auth Plan" > "$PLAN_QUEUE_DIR/02-auth-flow/spec.md"

  run cycle_next_plan
  [ "$status" -eq 0 ]

  [ -d "$PLAN_CHECK/02-auth-flow" ]
  [ -f "$PLAN_CHECK/02-auth-flow/spec.md" ]
  [ ! -d "$PLAN_QUEUE_DIR/02-auth-flow" ]
}

@test "cycle_next_plan archives completed plans to plan-done" {
  mkdir -p "$PLAN_CHECK/01-onboarding"
  echo "# Done" > "$PLAN_CHECK/01-onboarding/spec.md"

  mkdir -p "$PLAN_QUEUE_DIR/02-auth-flow"
  echo "# Next" > "$PLAN_QUEUE_DIR/02-auth-flow/spec.md"

  cycle_next_plan

  [ -d "$PLAN_DONE_DIR/01-onboarding" ]
  [ -f "$PLAN_DONE_DIR/01-onboarding/spec.md" ]
  [ -d "$PLAN_CHECK/02-auth-flow" ]
}

@test "cycle_next_plan resets state markers" {
  echo "done" > "$STATES_DIR/build"
  echo "done" > "$STATES_DIR/deploy"
  echo "done" > "$STATES_DIR/review"

  mkdir -p "$PLAN_QUEUE_DIR/02-auth-flow"
  echo "spec" > "$PLAN_QUEUE_DIR/02-auth-flow/spec.md"

  cycle_next_plan

  [ ! -f "$STATES_DIR/build" ]
  [ ! -f "$STATES_DIR/deploy" ]
  [ ! -f "$STATES_DIR/review" ]
}

@test "cycle_next_plan processes alphabetical order" {
  mkdir -p "$PLAN_QUEUE_DIR/03-payments"
  echo "payments" > "$PLAN_QUEUE_DIR/03-payments/spec.md"
  mkdir -p "$PLAN_QUEUE_DIR/02-auth"
  echo "auth" > "$PLAN_QUEUE_DIR/02-auth/spec.md"

  cycle_next_plan

  [ -d "$PLAN_CHECK/02-auth" ]
  [ -d "$PLAN_QUEUE_DIR/03-payments" ]
}

@test "archive_active_plans moves all plans to plan-done" {
  mkdir -p "$PLAN_CHECK/01-onboarding"
  echo "done1" > "$PLAN_CHECK/01-onboarding/spec.md"
  mkdir -p "$PLAN_CHECK/02-auth"
  echo "done2" > "$PLAN_CHECK/02-auth/spec.md"

  archive_active_plans

  [ -d "$PLAN_DONE_DIR/01-onboarding" ]
  [ -d "$PLAN_DONE_DIR/02-auth" ]
  [ -d "$PLAN_CHECK" ]
  [ -z "$(find "$PLAN_CHECK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]
}

@test "archive_active_plans is no-op when plan dir missing" {
  rmdir "$PLAN_CHECK"
  run archive_active_plans
  [ "$status" -eq 0 ]
}

@test "archive_active_plans is no-op when plan dir has no subdirs" {
  touch "$PLAN_CHECK/some-file.txt"
  run archive_active_plans
  [ "$status" -eq 0 ]
}

@test "cycle_next_plan removes empty queue dir" {
  mkdir -p "$PLAN_QUEUE_DIR/only-plan"
  echo "spec" > "$PLAN_QUEUE_DIR/only-plan/spec.md"

  cycle_next_plan

  [ ! -d "$PLAN_QUEUE_DIR" ]
}
