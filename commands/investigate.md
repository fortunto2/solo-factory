# /investigate — Debug Orchestrator

Command → Agent → Skill orchestration for investigating and fixing bugs.

## Usage
`/investigate <bug description or error message>`

## Orchestration Flow

### Phase 1: Gather Evidence (Agent: code-analyst)
Spawn the `code-analyst` agent:
- Search codebase for related code paths
- Trace dependencies and call chains
- Identify likely root cause areas

### Phase 2: Reproduce & Fix
Based on findings:
1. Run the failing scenario as a **background task** to capture logs
2. Read logs and error output
3. Write a failing test that reproduces the bug
4. Implement the fix
5. Verify the test passes

### Phase 3: Verify (Skill: /solo:review)
Quick review:
- Run full test suite
- Confirm no regressions
- Commit fix with descriptive message

## Rules
- Always run log-producing processes as background tasks
- Write a regression test before fixing
- If root cause is unclear after Phase 1, ask the user — don't guess
