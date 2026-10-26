---
name: solo-landing-gen
description: Turn a PRD into a landing page that converts and ships honest. One batch of intake questions, section-by-section copy with A/B headlines, a type, spacing, radius and motion system on Tailwind steps, a grep gate, then SEO with JSON-LD, agent-readiness files and a cookieless analytics counter. Use when user says "create landing page", "сделай лендинг", "landing page design", "сверстай лендинг", "лендинг для приложения", "write landing copy", "hero section", "A/B headlines", "landing content", or needs a marketing page from a PRD. Do NOT use for auditing a live site's SEO (use /seo-audit), social media posts (use /content-gen), or dense B2B app screens and dashboards.
license: MIT
metadata:
  author: fortunto2
  version: "1.2.0"
  openclaw:
    emoji: "🛬"
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, AskUserQuestion, mcp__solograph__kb_search, mcp__solograph__project_info, mcp__searxng__web_search
argument-hint: "<project-name>"
---

# /landing-gen

One page, one offer, one audience, one primary action. This skill takes a project's PRD to a
landing page that says one thing, is set on a system rather than by eye, and ships with the parts
that usually get forgotten: honest proof, JSON-LD, the files agents read, and a counter that
needs no cookie banner. With astro-static or Next.js it builds the page; otherwise it writes the
content file.

## Stages

Load only the reference for the stage you are in. Each opens with When / Inputs / Output.

| # | Stage | Output | Read |
|---|---|---|---|
| 1 | Intake | Brief: action, offer, ICP, traffic source, objections, proof on hand, layout type A-E | `references/intake.md` |
| 2 | Copy | Outline, hero, 5 A/B headlines, benefits, how it works, proof, FAQ, final CTA | `references/copy-sections.md` |
| 3 | Visual system | One tokens block (font, type scale, spacing, radius, surfaces, motion), then sections one by one | `references/layout-type-spacing.md` |
| 4 | Ship | Head and OG, JSON-LD with sourced Offer, robots/llms.txt/404, counter and CTA events, legal, form | `references/ship.md` |
| 5 | Check | Grep gate prints nothing, checklist ticked, `/humanize`, `seo audit`, `seo agent-audit` | `references/anti-patterns.md` |

## MCP tools (use if available)

- `kb_search(query)`: related methodology (conversion, copywriting)
- `project_info(name)`: project stack and details
- `web_search(query)`: competitor landing pages

Without MCP, fall back to Glob + Grep + Read.

## Steps

1. **Parse the project** from `$ARGUMENTS`. Read `docs/prd.md`, `README.md`, `docs/research.md`.
   Nothing there: run `/validate` first, or take the product description from the user.
2. **Detect the stack.** `astro.config.*` → astro-static: `src/pages/index.astro` plus one
   component per section. `next.config.*` → a Next.js route. Neither: content only.
3. **Intake** (`intake.md`). Fill the brief from the documents, ask only the gaps in ONE
   `AskUserQuestion` batch, mark unanswered fields `(assumed)` and keep going. Pick the layout
   type and the mode: fake-door (hero, CTA, email capture, about two hours) or the full page.
4. **Forced reasoning**, written into the brief before any headline: the ONE conversion, each
   top objection with the proof or reversal that answers it, what sits above the fold.
5. **Competitor landings** (optional, with search available): top three pages, their headline
   patterns, CTA wording, proof types, and the positioning gap they leave.
6. **Copy** (`copy-sections.md`). The whole outline and all copy go into
   `docs/landing-content.md` before any markup.
7. **Build** (`layout-type-spacing.md`). Tokens first, then hero, benefits, how it works, proof,
   FAQ, final CTA, one section per iteration. Never regenerate the whole page to change a part.
8. **Ship** (`ship.md`): head, JSON-LD, agent files, counter with CTA events, footer, form.
9. **Check** (`anti-patterns.md`): the gate must print nothing; `/humanize` the copy; after
   deploy, `seo audit` and `seo agent-audit` on the live URL (`/seo-cli`).
10. **Summary:** headline, CTA, layout type, assumptions made, gate result, next steps.

## Rules that hold in every stage

- **One action.** A second CTA is a subordinate link, never an equal button.
- **Proof is real or absent.** Invented quotes, logos, counts or ratings never reach a page that
  ships; sample content is marked `[SAMPLE]` and the gate fails on it.
- **Copy reads like a person.** No em dashes, no stock inflation, specific over vague, measured
  over specific (`/humanize`).
- **Privacy-first.** A cookieless counter (superduper-analytics by default, never PostHog or GA),
  self-hosted fonts, no third-party pixels. Then no cookie banner is needed and the privacy page
  can say so (`/legal`).
- **Values come from tokens.** Every size, gap and radius is a scale step; an arbitrary value is
  a gate failure, not a style choice.

## Output: `docs/landing-content.md`

```markdown
# Landing Page Content: {Project Name}

**Generated:** {YYYY-MM-DD}
**Primary action:** {action} · **ICP:** {persona} · **Traffic:** {source}
**Layout:** {A-E}, because {one line} · **Mode:** {fake-door | full}
**Assumed:** {fields marked (assumed), or "none"}

## Brief
Objections → answers: {objection → proof / reversal / FAQ}

## Hero
**Headline:** {headline}
**Subheadline:** {subheadline}
**CTA:** {button text} · **Proof signal:** {real item or "none yet"}
**Visual:** {what is shown}

## A/B Headlines
1. {pain} 2. {benefit} 3. {curiosity} 4. {social proof, real N only} 5. {direct}

## Benefits
## How it works
## Proof
## FAQ
## Risk reversal
## Final CTA

## SEO and JSON-LD
{title, description, index/noindex, JSON-LD types and Offer source}

## Analytics events
{event names and where they fire}

---
*Generated by /landing-gen. Replace every [SAMPLE], run the gate, then publish.*
```

## Notes

- Fake-door test: hero, CTA and email capture are enough; `noindex` it.
- Headlines are testable: run two or three variants, not one.
- Works with `/seo-audit` and `/seo-cli`: generate, deploy, then audit the live page.

## Gotchas

1. **Hero CTA must be above the fold** — if users need to scroll to find the primary action, conversion drops 40%+. Hero = headline + subheadline + CTA button + visual. Nothing else.
2. **Too many CTAs = decision paralysis** — one primary CTA per page. Secondary actions (learn more, see pricing) should be visually subordinate. Never put 3 equal-weight buttons side by side.
3. **Social proof placeholders hurt more than no social proof** — "Join 0 users" or empty testimonial slots signal "nobody uses this". Remove social proof section entirely until you have real data. Use "Built by {founder name}" instead.
4. **OG image is required for social sharing** — without `og:image`, links shared on Twitter/LinkedIn/Slack show a blank preview. Use 1200x630px. Test with https://cards-dev.twitter.com/validator.
5. **A/B test headlines BEFORE launch** — don't pick one headline and ship. Use Google Ads ($20/day for 3 days) to test 3-5 variants against each other. The winner goes on the landing page.
6. **Fonts from Google's CDN leak every visitor's IP.** A German court awarded damages for it
   (LG München I, 3 O 17493/20, January 2022). Self-host: Fontsource in Astro, `next/font` in
   Next.js.
7. **A reveal animation can hide the page.** Content set to `opacity: 0` in CSS stays invisible
   when JS fails or is off. Hide only under a `.js` class set inline in `<head>`.
8. **An Offer with no source is a claim agents repeat.** Price and rating in JSON-LD come from
   the store listing, a registry or the page itself, or they are left out.

## Common Issues

### No PRD or product info found
**Cause:** Project lacks `docs/prd.md` or a README with a product description.
**Fix:** Run `/validate` to generate the PRD first, or provide a README with problem, solution, features.

### Headlines too generic
**Cause:** Weak problem statement or no competitor differentiation.
**Fix:** Add `research.md` with competitive analysis and real user quotes. Specific pain produces specific headlines.

### Stack not detected for page scaffolding
**Cause:** No `astro.config.*` or `next.config.*` found.
**Fix:** The skill writes content-only markdown. To get page files, use the astro-static or nextjs-supabase stack.

### The gate flags a value the design really needs
**Cause:** A one-off size, such as a hero illustration's exact width.
**Fix:** Put it in the tokens block as a named value and use the token; the gate checks classes,
so a named token passes and stays findable.

## Credits

Intake structure, the A-D layout taxonomy, page structure, type-scale snapping, the spacing
table, the nested-radius rule, motion and state rules, and the checklist shape were adapted from
[`landing-page-design`](https://github.com/elayadesign/ai-design-skills/tree/main/skills/landing-page-design)
by Elaya (MIT, Copyright (c) 2026 Elaya), rewritten for this skill's conventions. See
[THIRD-PARTY.md](../../THIRD-PARTY.md).
