---
name: solo-customer-finder
description: Use when "find first customers", "первые клиенты", "early adopters", "design partners", "who would buy this", "prospect list", or need an evidence-backed shortlist of potential first customers from public signals. Do NOT use for community thread replies (/community-outreach), market research (/research), or GTM strategy (/launch).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  adapted-from: https://github.com/Kappaemme-git/codex-first-customer-finder-skill (MIT)
  openclaw:
    emoji: "🎯"
allowed-tools: Read, Grep, Glob, Write, WebSearch, WebFetch, AskUserQuestion, mcp__searxng__web_search, mcp__searxng__web_extract, mcp__solograph__kb_search, mcp__solograph__project_info
argument-hint: "<project-name, URL or idea> [quick|deep|b2b|design-partners|community]"
---

# /customer-finder

Turn a product URL or idea into a short, evidence-backed list of plausible FIRST customers. Every prospect must link to a public pain/demand/timing signal — a company that merely matches the industry is NOT a prospect. Output is a research hypothesis, not a customer database.

Difference from `/community-outreach`: that skill finds *threads* to reply in; this one finds *named prospects* (companies, projects, public professionals) with scores and outreach openers.

## MCP Tools (use if available)

- `web_search(query, engines, include_raw_content)` — SearXNG with engine routing (Reddit, HN, GitHub)
- `web_extract(url, size, page)` — one page as clean markdown, paginated for long docs
- `kb_search(query)` — prior research in KB
- `project_info(name)` — project details

Fallback: WebSearch/WebFetch.

## Steps

1. **Product brief.** Parse `$ARGUMENTS` (project slug, URL, or idea + optional mode). Read `docs/prd.md` and `docs/research.md` if present — reuse ICP, pain points, competitors instead of re-deriving. Define: product + promised outcome, primary user vs economic buyer, urgent job-to-be-done, current workaround, adoption trigger, geography/language, disqualifiers. One primary ICP + one adjacent. Don't start searching until the brief is specific enough to REJECT weak matches. Ask one question via AskUserQuestion only if ambiguity would change the search.

2. **Query buckets.** Search several angles, not one query repeated (adapt wording to the audience's language):
   - **Explicit demand:** "looking for", "recommend a tool", "alternative to", "does anything exist"
   - **Pain:** "takes hours", "manual", "frustrating", "keeps breaking"
   - **Workaround:** spreadsheets, copy-paste, scripts, VAs, repeated manual steps
   - **Switching:** cancellation, migration, missing feature, pricing complaints
   - **Timing:** launch, hiring, expansion, new regulation/integration relevant to the product

3. **Search public sources** (parallel): forums/Reddit, HN, product & marketplace reviews, GitHub issues and feature requests, public company pages / job posts / changelogs, "looking for a tool" posts. Open the original page — never qualify from a search snippet. Record: source URL, type, visible date (or "date unavailable"), exact evidence quote (minimal) or paraphrase.

4. **Qualify and score** each prospect 0-5 per dimension:

   ```text
   score = pain_strength/5*25 + product_fit/5*25 + timing/5*20
         + reachability/5*15 + evidence_quality/5*15
   ```

   80-100 strong candidate · 65-79 promising, validate fast · 50-64 missing a material signal · <50 drop from shortlist.

   Stage labels: **high-intent** (publicly requesting/switching) · **problem-aware** (describes the pain) · **trigger-present** (business event makes product relevant) · **potential-fit** (ICP match, thin evidence — keep OUT of primary shortlist). Old signals: keep if explicit, but cut timing score and label the date. Dedupe.

5. **Draft openers — never send.** Per prospect, one opener ≤90 words on the channel already associated with the source: (1) mention the public context naturally, (2) connect to the exact problem, (3) product in one sentence, (4) one low-friction question. No fake familiarity, no unrelated personal details. Do not send, follow, comment, or create CRM records — drafts only.

6. **Write report** to `docs/customers.md`:

   ```markdown
   # First Customers: {Project}

   **Generated:** {YYYY-MM-DD} · **Mode:** {mode}

   ## Verdict
   {Are there reachable early-customer signals? 2-3 sentences.}

   ## ICP
   Buyer / job / trigger / disqualifiers. Adjacent ICP one line.

   ## Top Prospect
   {Strongest evidence-backed candidate and why NOW.}

   ## Shortlist
   | # | Prospect | Score | Stage | Signal (quote/paraphrase) | Source + date | Channel |
   |---|----------|-------|-------|---------------------------|---------------|---------|

   ### Openers
   {per prospect, ≤90 words each}

   ## Repeated Patterns
   {pains/triggers seen across prospects — feeds /launch and /landing-gen}

   ## 7-Day Manual Outreach Plan
   {low-volume sequence: which prospect, which day, which channel}

   ## Limits
   {missing evidence; what only real conversations can confirm}

   ---
   *Prospects are hypotheses from public signals — not confirmed buyers. Review before any outreach.*
   ```

7. **Summary** — verdict, top-3 prospects with scores, next action.

## Modes

- **quick** — up to 5 strong prospects
- **standard** (default) — up to 10 across several source types
- **deep** — up to 20 + repeated-pattern analysis
- **design-partners** — feedback-willing users over immediate buyers
- **b2b** — companies, public business triggers, decision roles
- **community** — explicit requests and public discussions

## Critical Rules

1. **Public signals only** — intentionally shared professional/business info. No login walls, paywalls, robots bypass, data brokers, leaked datasets, private groups, personal email/phone enrichment.
2. **No sensitive traits** — never target via health, finances, politics, religion, sexuality.
3. **Never claim interest or consent** — label everything "potential customer based on public signals".
4. **Never send** — outreach stays manual; skill produces drafts only.
5. **Evidence or out** — no cited pain/demand/timing signal → not in the primary shortlist.
6. **10 strong > 50 generic.**

## Gotchas

1. **LinkedIn is login-walled** — don't research there; use public company pages, blogs, job boards instead.
2. **Snippet ≠ evidence** — search snippets truncate and misattribute; always open the page before scoring.
3. **GitHub issues are the best B2B-dev signal** — "feature request" + "workaround" labels on competitor repos = high-intent switching prospects.
4. **Stale threads** — >12 months old: keep only explicit requests, cut timing to 1, show the date in the report.
5. **Same author ≠ same buyer** — a dev complaining on Reddit may not be the economic buyer; score reachability against the actual decision role (b2b mode).

## Common Issues

### Web search not available
**Fix:** WebSearch/WebFetch as primary. Better engine routing (Reddit/HN/GitHub) via self-hosted [SearXNG](https://github.com/fortunto2/searxng-docker-tavily-adapter) + solograph MCP.

### Everything scores <50
**Cause:** ICP too broad or product too early for public demand signals.
**Fix:** Rerun in design-partners mode (feedback-seekers score differently), or go back to `/research` — the niche may lack evidenced pain.

### Prospects are all companies with no reachable human
**Fix:** b2b mode — search job posts and changelogs for the team that owns the pain; the posting itself names the role to contact.
