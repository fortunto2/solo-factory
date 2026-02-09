---
name: solo-validate
description: Score idea through POТОК, pick stack, generate PRD — go or kill in 5 min
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__codegraph__kb_search, mcp__codegraph__project_info
argument-hint: "[idea name or description]"
---

# /validate

Validate a startup idea end-to-end: search KB for related docs, run ПОТОК analysis, pick a stack, generate a PRD.

## MCP Tools (use if available)

If MCP tools are available, prefer them over CLI:
- `kb_search(query, n_results)` — search knowledge base for related docs
- `project_info()` — list active projects with stacks

If MCP tools are not available, fall back to Grep/Glob or CLI commands.

## Steps

1. **Parse the idea** from `$ARGUMENTS`. If empty, ask the user what idea they want to validate.

2. **Search for related knowledge:**
   If MCP `kb_search` tool is available, use it directly:
   - `kb_search(query="<idea keywords>", n_results=5)`
   Otherwise search locally:
   - Grep for idea keywords in `.md` files across the project and knowledge base
   Summarize any related documents found (existing ideas, frameworks, opportunities).

3. **Deep research (optional):** Check if `research.md` exists for this idea (look in `3-opportunities/<project-name>/` or `docs/`).
   - If it exists: read it and use findings to inform ПОТОК analysis and PRD filling (competitors, pain points, market size).
   - If it does not exist: ask the user if they want to run deep research first. If yes, tell them to run `/research <idea>` and come back. If no, continue without it.

4. **Alignment check:** Look for core principles docs (search for `manifest.md` or use `kb_search(query="manifest principles")`). Verify the idea aligns with:
   - Privacy-first / offline-first?
   - One pain -> one feature -> launch?
   - AI as foundation?
   - Speed over perfection?

5. **ПОТОК analysis:** Walk the idea through 6 layers. For each layer, provide a brief assessment:

   - **Layer 1 - Epistemological:** Is this within the circle of competence? What assumptions are unproven?
   - **Layer 2 - Temporal:** What's the time horizon? Is it Lindy-compliant?
   - **Layer 3 - Action:** What's the minimum viable action? Second-order effects?
   - **Layer 4 - Stakes:** What's the risk/reward asymmetry? Survivable downside?
   - **Layer 5 - Social:** Reputation impact? Network effects?
   - **Layer 6 - Meta:** Does this pass the mortality filter? Worth the finite time?

6. **Stack selection:** Ask the user which tech stack to use.
   If MCP `project_info` is available, show detected stacks from active projects as reference.
   Common stacks:
   - `ios-swift` — SwiftUI, CoreML, StoreKit 2
   - `nextjs-supabase` — Next.js, React, Tailwind, Supabase
   - `python-api` — FastAPI, SQLAlchemy, PostgreSQL
   - `kotlin-android` — Jetpack Compose, Room
   - `cloudflare-workers` — Hono, D1, edge-first
   - `astro-static` — Astro, Cloudflare Pages
   - `python-ml` — uv, Pydantic, ChromaDB, MLX

7. **Generate PRD:** Create a PRD document at `3-opportunities/<project-name>/prd.md` (or `docs/prd.md` if not in solopreneur KB). Use a kebab-case project name derived from the idea. Include:
   - **Problem:** Based on the idea and ПОТОК analysis
   - **Solution:** Core feature set (keep it minimal — one pain, one feature)
   - **Target Market:** Who has this pain? (use research.md pain points if available)
   - **Tech Stack:** Selected stack with key packages
   - **Architecture Principles:** SOLID, DRY, KISS, schemas-first
   - **Success Metrics:** How to measure if it works

8. **Output summary:**
   - Idea name and one-liner
   - Opportunity score (0-10) based on the analysis
   - Key risk and key advantage
   - Path to generated PRD
   - Recommended next action
