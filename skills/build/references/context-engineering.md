# Context Engineering Rules

Follow these rules to keep context healthy throughout long build sessions.

## Observation Masking

Large tool outputs destroy context quality. When output exceeds ~50 lines or ~2000 chars:
1. Write full output to a scratch file: `scratch/{tool}_{task}.txt` (create `scratch/` dir if needed)
2. Keep only a 5-10 line summary in conversation (errors, counts, key paths)
3. Reference: `[Full output in scratch/{file}]`

Apply to: test suite results, build logs, large grep results, verbose git diffs.

## Attention Positioning

Place information where the model pays most attention:
- **START of context:** current task description, error messages to fix
- **MIDDLE:** detailed history, reference docs (lowest attention zone)
- **END:** next steps, acceptance criteria, plan status

## Plan Recitation

At the START of each task iteration, re-read plan.md to find the current task. This prevents task drift in long sessions. Also re-read after errors and after phase completion.

## Keep Test Output Concise

When running tests, pipe through `head -50` or use `--reporter=dot` / `-q` flag. Thousands of test lines pollute context. Only show failures in detail. If output is large, use observation masking (write to `scratch/`, keep summary).
