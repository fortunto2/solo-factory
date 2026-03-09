# Context Engineering Principles

Practical rules for managing LLM context windows in agent workflows. Based on research from Agent-Skills-for-Context-Engineering (Muratcan Koylan, 2025).

## Attention Budget

Models have finite attention across context. Not all tokens are equal:

- **Lost-in-middle effect:** content in the middle of context gets 10-40% less recall
- **U-shaped attention:** beginning and end of context get highest attention
- **Rule:** place current task at the START, next steps at the END, detailed history in the MIDDLE

## Progressive Disclosure

Load context in layers — never dump everything at once:

1. **Static** (always loaded): skill name + 1-sentence description
2. **On-demand** (loaded when activated): full SKILL.md content
3. **Just-in-time** (loaded when needed): references/*.md, source files

## Observation Masking

Large tool outputs destroy context quality. Mask them:

```
IF output > 50 lines OR > 2000 chars:
  1. Write full output to scratch/{tool}_{context}.txt
  2. Extract key info (errors, counts, paths) into 5-10 line summary
  3. Keep only summary in conversation context
  4. Reference: "[Full output in scratch/{file}. Summary: ...]"
```

Apply to: test results, build logs, grep results, git diffs, API responses.

## Plan Recitation

Long-running agents lose track of the plan. Recite it:

- **At loop start:** re-read plan.md, find current task
- **After errors:** re-read plan.md to avoid drifting from original intent
- **After phase completion:** re-read plan.md to confirm next phase

This is the "todo.md pattern" from Manus — proven to reduce task drift.

## Compaction Triggers

Start compressing context before it's too late:

- **70% utilization:** begin summarizing completed work
- **80% utilization:** aggressively mask old tool outputs
- **90% utilization:** structured summary of entire session

## Structured Context Handoff

When passing context between skills (plan → build → review), use 5 sections:

```markdown
## Session Intent
What we're trying to accomplish (1 sentence)

## Files Modified
- path/to/file.ts — what changed and why

## Decisions Made
- Chose X over Y because Z

## Current State
What's working, what's broken, what's blocked

## Next Steps
Ordered list of what to do next
```

## Architectural Reduction

Fewer tools = better agent performance (Vercel d0 case: 17→2 tools, +20% success, 3.5x faster):

- Prefer `bash` + `grep` + `read` over specialized exploration tools
- If an engineer can't decide which tool to use, the agent can't either
- Before adding a tool, ask: "can the model do this with existing tools?"

## Token Economics

Multi-agent workflows cost more. Budget accordingly:

- Single agent: 1x baseline tokens
- Multi-agent (orchestrator + workers): ~15x tokens
- Use sub-agents for **context isolation**, not role-play
- `forward_message` pattern: sub-agent returns result directly, avoids "telephone game"

## Degradation Thresholds

Known model degradation points (approximate):

| Model | Onset | Severe |
|-------|-------|--------|
| Claude Sonnet 4.5 | ~80K tokens | ~150K tokens |
| Claude Opus 4.6 | ~100K tokens | ~180K tokens |

## References

- [Agent-Skills-for-Context-Engineering](https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering) — 13 skills
- Vercel d0 architectural reduction case study
- Manus KV-cache and plan recitation patterns
- [Meta Context Engineering via Agentic Skill Evolution](https://arxiv.org/pdf/2601.21557) — Peking University (2026)
