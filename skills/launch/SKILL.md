---
name: solo-launch
description: Use when "launch plan", "go-to-market", "GTM strategy", "how to launch", "launch checklist", "growth plan", or product is built and needs distribution strategy. Do NOT use for content generation (/content-gen) or SEO audit (/seo-audit).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🚀"
allowed-tools: Read, Grep, Glob, Write, AskUserQuestion, WebSearch, WebFetch, mcp__solograph__kb_search, mcp__solograph__web_search, mcp__solograph__project_info
argument-hint: "[project-name]"
---

# /launch

Generate a go-to-market launch strategy that ties together all promotion skills into a unified plan. Reads PRD and research data, defines the beachhead, maps channels, validates pricing against manifesto principles, and produces an actionable launch checklist.

**Philosophy:** Launch is not a single event — it's a sequence of small bets. Each channel is an experiment. Measure before scaling. Reference: manifesto principle "Money without overheating — revenue before automation, scale what works."

## MCP Tools (use if available)

- `kb_search(query)` — find launch methodology, past launches
- `web_search(query)` — research channels, communities, pricing benchmarks
- `project_info(name)` — get project stack and status

If MCP tools are not available, fall back to Glob + Grep + WebSearch.

## Steps

1. **Parse project** from `$ARGUMENTS`.
   - Read `docs/prd.md` — features, ICP, pricing, acceptance criteria
   - Read `docs/research.md` — competitors, personas, market size, pain points
   - Read `CLAUDE.md` — stack, deploy target
   - If none found: ask via AskUserQuestion

2. **Validate beachhead segment:**

   Check if PRD has a beachhead section (added by `/validate`). If not, define it now:
   - **Segment:** narrow, specific group (not "everyone who needs X")
   - **Size estimate:** how many people in this segment?
   - **Reachability:** where do they gather online? (specific subreddit, community, newsletter)
   - **Willingness to pay:** evidence from research.md or competitor pricing
   - **Why first:** why this segment before others?

3. **Pricing validation** against manifesto:

   Read pricing from PRD. Check against principles in `templates/principles/manifest.md`:

   | Check | Pass/Fail | Notes |
   |-------|-----------|-------|
   | Does it cost to run? (server, API, storage) | — | If no → should be free or one-time |
   | Subscription justified? | — | Only if ongoing costs exist |
   | Is pricing transparent? | — | No hidden fees, clear what you get |
   | Lock-in risk? | — | Can user export data? Own their content? |
   | Subscription fatigue check | — | Is there a one-time alternative? |

   If pricing conflicts with principles, flag it and suggest alternatives.

4. **Channel mapping** (3-5 channels, ordered by effort):

   For each channel, define:

   | Channel | Effort | Cost | Timeline | Expected Result | Skill |
   |---------|--------|------|----------|----------------|-------|
   | ProductHunt | Medium | Free | Day 1 | 200-500 visits, feedback | `/community-outreach` |
   | Reddit (specific subs) | Low | Free | Week 1 | 50-100 visits, pain validation | `/community-outreach` |
   | SEO / Content | Medium | Free | Month 1-3 | Organic traffic baseline | `/seo-audit` + `/landing-gen` |
   | Twitter/LinkedIn | Low | Free | Ongoing | Network effect, credibility | `/content-gen` |
   | Paid (if justified) | High | $50-200 | After organic validates | Scale what works | — |

   Rules:
   - Start with free channels — paid only after organic validates demand
   - One channel at a time — don't spread thin (manifesto: "wip = 1")
   - Measure each channel before adding the next
   - Offline-first products: app store optimization (ASO) over web marketing

5. **Launch timeline** (4-week plan):

   ```
   Week 0 (pre-launch):
   - [ ] /landing-gen — landing page with email capture
   - [ ] /seo-audit — baseline SEO score
   - [ ] /metrics-track — PostHog events wired

   Week 1 (soft launch):
   - [ ] /community-outreach — 3-5 value-first posts in target communities
   - [ ] /content-gen — LinkedIn post + Twitter thread
   - [ ] Collect feedback, fix critical issues

   Week 2 (public launch):
   - [ ] ProductHunt launch (if web/SaaS)
   - [ ] App Store submission (if iOS)
   - [ ] /video-promo — demo video for landing page
   - [ ] Monitor metrics daily

   Week 3-4 (iterate):
   - [ ] Review metrics — kill/iterate/scale decision
   - [ ] Double down on best-performing channel
   - [ ] /content-gen — release notes for updates
   - [ ] Second community push based on feedback
   ```

   Adapt timeline to product type (iOS has App Store review delays, web can launch same day).

6. **Growth loops** (sustainable, not hacks):

   Design 1-2 growth loops appropriate to the product:

   **Content loop:** User creates → content is public/shareable → new users discover → they create
   **Referral loop:** User gets value → shares with peer → peer signs up → both benefit
   **SEO loop:** Solve problem → write about it → rank → new users find solution → they use product
   **Tool loop:** Free tool solves adjacent problem → captures intent → funnels to main product

   Rules:
   - Loop must be natural, not forced (no "share to unlock" dark patterns — manifesto: against exploitation)
   - Loop must benefit the user, not just the product
   - Offline-first products: growth through quality and word-of-mouth, not viral mechanics

7. **Launch risks** (from research.md + pre-mortem thinking):

   - **Timing risk:** is a competitor about to launch? Big industry event?
   - **Pricing risk:** will users pay at this price point? Evidence?
   - **Channel risk:** if primary channel fails, what's the backup?
   - **Technical risk:** can the product handle 10x traffic? (serverless = yes, VPS = plan)

8. **Write launch strategy** to `docs/launch-strategy.md`:

   ```markdown
   ---
   type: launch-strategy
   status: draft
   title: "Launch Strategy — {Project Name}"
   created: {YYYY-MM-DD}
   tags: [{project}, launch, gtm]
   ---

   # Launch Strategy: {Project Name}

   ## Beachhead Segment
   {from step 2}

   ## Pricing
   {from step 3, with manifest alignment}

   ## Channels
   {table from step 4}

   ## Timeline
   {4-week plan from step 5}

   ## Growth Loops
   {from step 6}

   ## Risks
   {from step 7}

   ## Launch Checklist
   - [ ] Landing page live (`/landing-gen`)
   - [ ] SEO baseline checked (`/seo-audit`)
   - [ ] Metrics wired (`/metrics-track`)
   - [ ] Content pack ready (`/content-gen`)
   - [ ] Community posts drafted (`/community-outreach`)
   - [ ] Demo video planned (`/video-promo`)
   - [ ] Privacy policy published (`/legal`)
   - [ ] Kill/iterate/scale thresholds defined

   ---
   *Generated by /launch. Review and adapt before executing.*
   ```

9. **Output summary:**
   - Beachhead segment (one line)
   - Recommended pricing model
   - Top 3 channels with timeline
   - Growth loop type
   - Path to generated launch-strategy.md
   - Suggested next step: run the skills from the checklist

## Notes

- This skill is a strategic planner — it doesn't execute. Run the referenced skills to produce actual content
- Launch strategy should be revisited after Week 2 metrics review
- For products with no cloud component (offline-first), skip paid channels and focus on ASO + community

## Common Issues

### No PRD found
**Cause:** Haven't run `/validate` yet.
**Fix:** Run `/validate <idea>` first to generate PRD with ICP, pricing, and features.

### Pricing conflicts with manifesto
**Cause:** Product uses subscription model but has no running costs.
**Fix:** This is intentional — the skill flags it. Consider one-time purchase or freemium instead.

### Beachhead too broad
**Cause:** "Everyone who uses X" is not a beachhead.
**Fix:** Narrow to a specific community, profession, or behavior pattern. You should be able to find them in one place.
