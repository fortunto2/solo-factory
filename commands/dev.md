# /dev — Full Development Orchestrator

Command → Agent → Skill orchestration for end-to-end feature development.

## Usage
`/dev <description of what to build>`

## Orchestration Flow

### Phase 1: Research (Agent: researcher)
Spawn the `researcher` agent to gather context:
- Search KB for related patterns, prior art, stack decisions
- Search codebase for relevant existing code
- Return findings summary

### Phase 2: Plan (Skill: /solo:plan)
Use `/solo:plan` to create implementation spec:
- Read researcher findings
- Explore codebase structure
- Produce phased plan with file-level tasks

### Phase 3: Build (Skill: /solo:build)
Use `/solo:build` to execute the plan:
- TDD workflow: test → implement → verify
- Auto-commit after each completed task
- Phase gates between stages

### Phase 4: Review (Skill: /solo:review)
Use `/solo:review` for quality gate:
- Run tests, check coverage
- Verify acceptance criteria from plan
- Generate ship-ready report

## Rules
- Always start in **plan mode** for Phase 2
- Commit after each completed task (Phase 3)
- If any phase fails, stop and report — don't force through
- Pass context between phases via files (plan.md, findings.md)
