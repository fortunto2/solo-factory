---
name: solo-validate
description: Score startup idea through S.E.E.D. niche check + STREAM 6-layer analysis, auto-pick stack, and generate PRD with acceptance criteria. Use when user says "validate idea", "score this idea", "should I build this", "go or kill", "generate PRD", or "evaluate opportunity". Do NOT use for deep research (use /research first) or decision-only framework (use /stream).
license: MIT
metadata:
  author: fortunto2
  version: "1.6.0"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__kb_search, mcp__solograph__project_info
argument-hint: "[idea name or description]"
---

# /validate

Validate a startup idea end-to-end: search KB for related docs, run STREAM analysis, pick a stack, generate a PRD.

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

3. **Deep research (optional):** Check if `research.md` exists for this idea (look in `4-opportunities/<project-name>/` or `docs/`).
   - If it exists: read it and use findings to inform STREAM analysis and PRD filling (competitors, pain points, market size).
   - If it does not exist: ask the user if they want to run deep research first. If yes, tell them to run `/research <idea>` and come back. If no, continue without it.

4. **Alignment check:** Look for core principles docs (search for `manifest.md` or use `kb_search(query="manifest principles")`). Verify the idea aligns with:
   - Privacy-first / offline-first?
   - One pain -> one feature -> launch?
   - AI as foundation?
   - Speed over perfection?

5. **S.E.E.D. niche check** (quick, before deep analysis):

   Score the idea on four dimensions:
   - **S — Searchability:** Can you rank? Forums/Reddit in top-10, few fresh giants, no video blocks?
   - **E — Evidence:** Real pain with real quotes/URLs? Or hypothetical?
   - **E — Ease:** MVP in 1-2 days on existing stack? No heavy dependencies?
   - **D — Demand:** Long-tail keywords exist? Clear monetization path?

   **Kill flags** (stop immediately if any):
   - Top-10 SERP dominated by media giants or encyclopedias
   - Fresh competing content (<60 days old) already covers it well
   - No evidence of real user pain (only founder's hypothesis)
   - MVP needs >1 week even on best-fit stack

   If any kill flag triggers → recommend KILL with explanation. Don't proceed to STREAM.

6. **STREAM analysis:** Walk the idea through 6 layers. For each layer, provide a brief assessment:

   - **Layer 1 - Epistemological:** Is this within the circle of competence? What assumptions are unproven?
   - **Layer 2 - Temporal:** What's the time horizon? Is it Lindy-compliant?
   - **Layer 3 - Action:** What's the minimum viable action? Second-order effects?
   - **Layer 4 - Stakes:** What's the risk/reward asymmetry? Survivable downside?
   - **Layer 5 - Social:** Reputation impact? Network effects?
   - **Layer 6 - Meta:** Does this pass the mortality filter? Worth the finite time?

7. **Stack selection:** Auto-detect from research data, then confirm or ask.

   **Auto-detection rules** (from `research.md` `product_type` field or idea keywords):
   - `product_type: ios` → `ios-swift`
   - `product_type: android` → `kotlin-android`
   - `product_type: web` + mentions AI/ML → `nextjs-supabase` (or `nextjs-ai-agents`)
   - `product_type: web` + landing/static → `astro-static`
   - `product_type: web` + content site + needs SSR for some pages (CDN data, transcripts, dynamic) → `astro-hybrid`
   - `product_type: web` (default) → `nextjs-supabase`
   - `product_type: api` → `python-api`
   - `product_type: cli` + Python keywords → `python-ml`
   - `product_type: cli` + JS/TS keywords → `nextjs-supabase` (monorepo)
   - Edge/serverless keywords → `cloudflare-workers`

   If auto-detected with high confidence, state the choice and proceed.
   If ambiguous (e.g., could be web or mobile), ask via AskUserQuestion with the top 2-3 options.
   If MCP `project_info` is available, show user's existing stacks as reference.

8. **Generate PRD:** Create a PRD document at `4-opportunities/<project-name>/prd.md` (or `docs/prd.md` if not in solopreneur KB). Use a kebab-case project name derived from the idea.

   **PRD must pass Definition of Done:**
   - [ ] Problem statement ≥ 30 words (who suffers, when, why now)
   - [ ] ICP + JTBD — target segment + 2-3 jobs-to-be-done
   - [ ] 3-5 features, each with measurable acceptance criteria
   - [ ] 3-5 KPIs with units (daily/weekly) and target values
   - [ ] 3-5 risks with mitigation plans
   - [ ] Tech stack with key packages
   - [ ] Architecture principles (SOLID, DRY, KISS, schemas-first)
   - [ ] Evidence-first — numbers/claims have source URLs (from research.md if available)

9. **Output summary:**
   - Idea name and one-liner
   - S.E.E.D. score (S/E/E/D each rated low/medium/high)
   - Opportunity score (0-10) based on STREAM + S.E.E.D.
   - Key risk and key advantage
   - Path to generated PRD
   - **Recommended next action** (one of):
     - `/research <idea>` — if evidence is weak, get data first
     - `/scaffold <name> <stack>` — if validated, build it
     - **Fake-Door Test** — if uncertain, spend $20 on a landing stub before coding
     - **KILL** — if score < 5 or kill flags triggered

## Common Issues

### S.E.E.D. kill flag triggered
**Cause:** Idea fails basic niche viability (SERP dominated, no evidence, MVP too complex).
**Fix:** This is by design — kill flags save time. Consider pivoting the idea or running `/research` for deeper evidence.

### No research.md found
**Cause:** Skipped `/research` step.
**Fix:** Skill asks if you want to research first. For stronger PRDs, run `/research <idea>` before `/validate`.

### Stack auto-detection wrong
**Cause:** Ambiguous product type (could be web or mobile).
**Fix:** Skill asks via AskUserQuestion when ambiguous. Specify product type explicitly in the idea description.
