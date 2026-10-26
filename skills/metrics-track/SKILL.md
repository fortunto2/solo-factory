---
name: solo-metrics-track
description: Use when "set up metrics", "track KPIs", "analytics events", "what to count", "funnel analysis", "when to kill or scale", "success metrics", or need analytics plan. Do NOT use for SEO metrics (/seo-audit).
license: MIT
metadata:
  author: fortunto2
  version: "1.3.0"
  openclaw:
    emoji: "📈"
allowed-tools: Read, Grep, Glob, Write, AskUserQuestion, mcp__solograph__kb_search
argument-hint: "<project-name>"
---

# /metrics-track

Set up a metrics tracking plan for a project. Defines the event funnel for [superduper-analytics](https://github.com/fortunto2/superduper-analytics) (a self-hosted, cookieless event counter on Cloudflare, one schema for web and apps), KPI benchmarks, and kill/iterate/scale decision thresholds based on lean startup principles.

## MCP Tools (use if available)

- `kb_search(query)` — find analytics patterns, past funnels, measured benchmarks

If MCP tools are not available, fall back to Grep + Read.

## Methodology Reference

This skill implements metrics tracking based on lean startup principles:
- **Relative metrics vs niche benchmarks** — compare against your own trajectory, not vanity averages
- **Kill/iterate/scale decision rules** — data-driven thresholds for product decisions (see step 7 below)

## Steps

1. **Parse project** from `$ARGUMENTS`.
   - Read PRD for features, ICP, monetization model.
   - Read CLAUDE.md for stack (iOS/Web/both).
   - If empty: ask via AskUserQuestion.

2. **Detect platform:**
   - Web → the `sda.js` tag (one line in `<head>`) + `sda("event_name", props, metrics)` calls
   - iOS / macOS → the [SuperDuperAnalytics](https://github.com/fortunto2/superduperai-analytics-swift) SPM package, `Analytics.track(...)`
   - Android, KMP, Python, server → no client exists; POST events to the ingest endpoint (contract in the repo README and `src/schema.ts`), `platform` set to `android` / `server`
   - Web + app → register ONE source id for both, so a landing visit and an app launch are compared without a join. There is no per-person link between them, by design (see Notes)

3. **Check what is already wired:**
   - `seo products` lists every registered source and whether its counter reports. A product with no counter reads as zero traffic for reasons unrelated to how it is doing
   - Grep the project for `sda.js`, `sda(`, `Analytics.track`, and for leftovers (`posthog`, `gtag(`, `googletagmanager`). Legacy sites may still have Google Analytics; `seo ga` reads it, but don't add it to new ones
   - If MCP available: `kb_search("analytics events funnel")` for past funnels

4. **Define event funnel** based on PRD features:

   Standard funnel: `Awareness → Acquisition → Activation → Revenue → Retention → Referral`

   See `references/kpi-benchmarks.md` for the full event table, KPI thresholds, code snippets, and A/B test template. Adapt events to the specific product. Keep it to about ten event names per product: it is a counter, not session replay.

5. **Forced reasoning — metrics selection:**
   Before defining KPIs, write out:
   - **North Star Metric:** The ONE number that matters most (e.g., "weekly active users who completed core action")
   - **Leading indicators:** What predicts the North Star? (e.g., "activation rate D1")
   - **Lagging indicators:** What confirms success? (e.g., "MRR", "retention D30")
   - **Vanity metrics to AVOID:** (e.g., total downloads without activation)

6. **Set KPI benchmarks** per stage:

   Use thresholds from `references/kpi-benchmarks.md` as starting point. Adjust for product type (B2B has lower volume/higher conversion, B2C mobile has higher volume/lower retention).

7. **Define decision rules** — use kill/iterate/scale framework from `references/kpi-benchmarks.md`. Adapt thresholds to project-specific values from step 6.

8. **Generate implementation snippets** — use platform-specific examples from `references/kpi-benchmarks.md`. Adapt event names and properties to the funnel defined in step 4.

9. **A/B Test Analysis Template** — copy template from `references/kpi-benchmarks.md` into the metrics plan. Include decision rules (SHIP / KEEP / EXTEND / INCONCLUSIVE).

10. **Write metrics plan** to `docs/metrics-plan.md`:

   ```markdown
   # Metrics Plan: {Project Name}

   **Generated:** {YYYY-MM-DD}
   **Platform:** {iOS / Web / Both}
   **North Star:** {north star metric}

   ## Event Funnel

   | Stage | Event | Properties |
   |-------|-------|------------|
   {event table from step 4}

   ## KPIs & Thresholds

   | KPI | Target | Kill | Scale |
   |-----|--------|------|-------|
   {benchmark table from step 6}

   ## Decision Rules

   {framework from step 7}

   ## Implementation

   ### superduper-analytics setup
   - Source id: {id} (one commit to `registry/sources.yaml`; unregistered ids are refused with 403)
   - Client: {sda.js tag / SuperDuperAnalytics SPM / POST to the ingest endpoint}
   - Identity: anonymous only (web: edge-derived, rotates daily; apps: install-scoped UUID)
   - Store side: App Store `ct` campaign tokens / Play `referrer` UTM on every store link

   ### Code Snippets
   {snippets from step 8}

   ## A/B Test Template
   {template from step 9}

   ## Reading it
   - Traffic, people vs bots: `seo traffic --days 7`
   - Which pages make people act: `seo conversion --days 28`
   - Do app users come back: `seo retention --days 28` (apps only; the web id dies at midnight UTC by design)
   - Installs, purchases, subscriptions per campaign: App Store Connect / Play Console, by `ct` / UTM

   ---
   *Generated by /metrics-track. Implement events, then review weekly.*
   ```

11. **Output summary** — North Star metric, key thresholds, first event to implement, A/B template included.

## Notes

- Event names: `object_verb`, past tense, snake_case (`page_viewed`, `photo_exported`). Props are strings, metrics are numbers
- No cookie, no `localStorage`, nothing returned to the browser, so no consent banner. That stays true only while nothing else on the page sets one
- No `identify()`. Linking one visitor to one install needs a cross-site identifier, which is exactly what this setup refuses. The funnel is aggregate: landing visits and store clicks from the counter, installs and purchases from the store's campaign report
- Retention is an app metric here. Web returning visitors are invisible by design
- Errors and crashes are not analytics: App Store Connect crashes + MetricKit, Play Console Android vitals, Workers Logs. No third-party telemetry SDK
- Review weekly, make the kill/iterate/scale decision monthly

## Common Issues

### Wrong platform detected
**Cause:** Project has both web and iOS indicators.
**Fix:** Skill checks package manifests. If both exist, it generates cross-platform identity setup. Verify the detected platform in the output.

### KPI thresholds too aggressive
**Cause:** Default thresholds are industry averages.
**Fix:** Adjust thresholds in `docs/metrics-plan.md` based on your niche. B2B typically has lower volume but higher conversion.

### Counter not in project
**Cause:** Metrics plan generated but nothing sends events.
**Fix:** This skill generates the PLAN only. Web: add the `sda.js` tag (`docs/install.md` in https://github.com/fortunto2/superduper-analytics). iOS: add the SPM package https://github.com/fortunto2/superduperai-analytics-swift. Then register the source id and check `seo products`.

### Events sent, nothing arrives
**Cause:** The source id is not in `registry/sources.yaml` (403), or the request came from an origin the registry does not list (dev server, preview deploy: dropped silently, by design).
**Fix:** Register the id, deploy, and test from the production host.
