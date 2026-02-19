---
name: solo-pipeline
description: Launch automated multi-skill pipeline that chains skills into a loop. Use when user says "run pipeline", "automate research to PRD", "full pipeline", "research and validate", "scaffold to build", "loop until done", or "chain skills". Do NOT use for single skills (use the skill directly).
license: MIT
metadata:
  author: fortunto2
  version: "1.2.0"
  openclaw:
    emoji: "🔄"
allowed-tools: Bash, Read, Write, AskUserQuestion
argument-hint: "research <idea> | dev <name> <stack> [--feature desc]"
---

# /pipeline

Launch an automated multi-skill pipeline. The Stop hook chains skills automatically — no manual invocation needed between stages.

## Available Pipelines

### Research Pipeline
`/pipeline research "AI therapist app"`

Chains: `/research` -> `/validate`
Produces: `research.md` -> `prd.md`

### Dev Pipeline
`/pipeline dev "project-name" "stack"`
`/pipeline dev "project-name" "stack" --feature "user onboarding"`

Chains: `/scaffold` -> `/setup` -> `/plan` -> `/build`
Produces: full project with workflow, plan, and implementation

## Steps

### 1. Parse Arguments

Extract from `$ARGUMENTS`:
- Pipeline type: first word (`research` or `dev`)
- Remaining args: passed to the launcher script

If no arguments or unclear, ask:

```
Which pipeline do you want to run?

1. Research Pipeline — /research → /validate (idea to PRD)
2. Dev Pipeline — /scaffold → /setup → /plan → /build (PRD to running code)
```

### 2. Confirm with User

Show what will happen:

```
Pipeline: {type}
Stages: {stage1} → {stage2} → ...
Idea/Project: {name}

This will run multiple skills automatically. Continue?
```

Ask via AskUserQuestion.

### 3. Run Launcher Script

Determine the plugin root (where this skill lives):
- Check if `${CLAUDE_PLUGIN_ROOT}` is set (plugin context)
- Otherwise find `solo-factory/scripts/` relative to project

```bash
# Research pipeline
${CLAUDE_PLUGIN_ROOT}/scripts/solo-research.sh "idea name" [--project name] --no-dashboard

# Dev pipeline
${CLAUDE_PLUGIN_ROOT}/scripts/solo-dev.sh "project-name" "stack" [--feature "desc"] --no-dashboard
```

**Always pass `--no-dashboard`** when running from within Claude Code skill context (tmux is for terminal use only).

### 4. Start First Stage

After the script creates the state file, immediately run the first stage's skill.
The Stop hook will handle subsequent stages automatically.

For research pipeline: Run `/research "idea name"`
For dev pipeline: Run `/scaffold project-name stack`

### 5. Pipeline Completion

When all stages are done, output:
```
<solo:done/>
```

The Stop hook checks for this signal and cleans up the state file.

## State File

Location: `~/.solo/pipelines/solo-pipeline-{project}.local.md`
Log file: `~/.solo/pipelines/solo-pipeline-{project}.log`

Format: YAML frontmatter with stages list, `project_root`, and `log_file` fields.
The Stop hook reads this file on every session exit attempt.

To cancel a pipeline manually: `rm ~/.solo/pipelines/solo-pipeline-{project}.local.md`

## Monitoring

### tmux Dashboard (terminal use)

When launched from terminal (without `--no-dashboard`), a tmux dashboard opens automatically with:
- Pane 0: work area
- Pane 1: `tail -f` on log file
- Pane 2: live status display (refreshes every 2s)

Manual dashboard commands:
```bash
# Create dashboard for a pipeline
solo-dashboard.sh create <project>

# Attach to existing dashboard
solo-dashboard.sh attach <project>

# Close dashboard
solo-dashboard.sh close <project>
```

### Manual Monitoring

```bash
# Colored status display
solo-pipeline-status.sh              # all pipelines
solo-pipeline-status.sh <project>    # specific pipeline

# Auto-refresh
watch -n2 -c solo-pipeline-status.sh

# Log tail
tail -f ~/.solo/pipelines/solo-pipeline-<project>.log
```

### Real-time Tool Visibility

The pipeline uses `--output-format stream-json` piped through `solo-stream-fmt.py` — tool calls appear in real-time with colored icons:

```
  📖 Read ~/startups/solopreneur/4-opportunities/jarvis/research.md
  🔍 Glob "*.md" ~/startups/active/jarvis/
  💻 Bash npm test
  🌐 WebSearch voice AI agent developer tools 2026
  🤖 Task [Explore] Research task
  🔌 kb_search jarvis voice agent
```

Disable colors: `--no-color`. Disable sound effects: `--no-sound`.

### 8-bit Background Music

Chiptune background music plays automatically during pipeline runs (pentatonic melodies, square waves, 140 BPM). Stops on completion. Volume: 0.08 (very quiet).

Manual control: `solo-chiptune.sh start|stop|status [--volume 0.1] [--bpm 140]`

### Session Reuse

Re-running a pipeline reuses the existing tmux session:
- All panes are cleared (Ctrl-C + clear)
- Log tail and status watch restart fresh
- No need to close/recreate — just run the same command again

### Log Format

```
[22:30:15] START    | jarvis | stages: research -> validate | max: 5
[22:30:16] STAGE    | iter 1/5 | stage 1/2: research
[22:30:16] INVOKE   | /research "Jarvis voice AI agent"
[22:35:42] CHECK    | research | .../research.md -> FOUND
[22:35:42] STAGE    | iter 2/5 | stage 2/2: validate
[22:35:42] INVOKE   | /validate "Jarvis voice AI agent"
[22:40:10] CHECK    | validate | .../prd.md -> FOUND
[22:40:10] DONE     | All stages complete! Promise detected.
[22:40:10] FINISH   | Duration: 10m
```

## Critical Rules

1. **Always confirm** before starting a pipeline.
2. **Don't skip stages** — the hook handles progression.
3. **Cancel = delete state file** — tell users this if they want to stop.
4. **Max iterations** prevent infinite loops (default 5 for research, 15 for dev).
5. **Use `--no-dashboard`** when running from within Claude Code skill context.
