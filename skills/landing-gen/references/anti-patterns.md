# Anti-patterns, the grep gate, the checklist

**When:** after every section, and once more before deploy. **Output:** an empty gate and a
ticked checklist in the summary.

## What makes a landing page fail

**Strategy**
- Two or three equal-weight CTAs above the fold. The visitor picks none.
- A vague promise: "streamline", "optimize", "all-in-one platform".
- A feature list with no outcome attached to any feature.
- Proof parked at the bottom, far from the claim it supports.
- A headline that does not match the ad or query that brought the visitor.
- Objections left unanswered because they are uncomfortable. They become FAQ entries.

**Honesty**
- Invented testimonials, customer logos, user counts or ratings on a live page (fabricated
  reviews, see `copy-sections.md`, "Sample vs shipped").
- Empty social-proof slots ("Join 0 users", three grey avatars). Remove the section instead.
- An Offer or rating in JSON-LD with no source behind it.
- A risk reversal the business cannot honour.

**Visual**
- Sizes, gaps and radii picked by eye: `text-[19px]`, `p-[13px]`, `gap-7`.
- Gradient backgrounds, one-sided card borders, emoji as feature icons.
- Two typefaces by accident, black (900) weights.
- Browser default easing, `transition-all`, animating `top`/`width`.
- A scroll listener that runs every frame.
- Content hidden until JS runs, so it never appears when JS is off.

**Privacy and shipping**
- A PostHog, Google Analytics, Tag Manager or Facebook snippet on a "privacy-first" page.
- Fonts from `fonts.googleapis.com`.
- A cookie banner for a counter that sets no cookie.
- `href="#"` buttons, a missing 404, no legal links in the footer.

**Process**
- Regenerating the whole page to change one section.
- Shipping copy that never went through `/humanize`.

## The grep gate

Run from the project root. **Every block must print nothing.** Each line is a known failure;
fix it or say in the summary why it stays.

```bash
S=src   # where pages and components live

# arbitrary values: sizes, spacing, radius, widths chosen by eye
rg -o --no-filename '\b(text|leading|tracking|p[xytrbl]?|m[xytrbl]?|gap(-[xy])?|space-[xy]|rounded(-[trbl]{1,2})?|max-w|w|h)-\[[^]]+\]' $S | sort | uniq -c | sort -rn

# spacing off the scale (allowed: 0 0.5 1 2 3 4 6 8 10 12 16 20 24)
rg -o --no-filename '\b-?(p[xytrbl]?|m[xytrbl]?|gap(-[xy])?|space-[xy])-(5|7|9|11|14|[1-3]\.5)\b' $S | sort | uniq -c

# black weights, default easing, transition-all
rg -no '\bfont-(black|extrabold)\b|\bease-(in-out|linear)\b|\btransition-all\b' $S

# em dashes and spaced en dashes in copy (run /humanize on what this finds)
rg -n '—| – ' $S

# sample content left on a page that ships
rg -n '\[SAMPLE\]|lorem ipsum|Your headline here' -i $S

# dead links
rg -no 'href="#"' $S

# trackers and third-party font CDNs
rg -no 'posthog|googletagmanager|gtag\(|google-analytics|fonts\.googleapis|fonts\.gstatic|connect\.facebook' $S
```

Checked against a planted fixture before this was published: every pattern fired on its
planted defect, and the allowed values (`px-6`, `py-24`, `max-w-2xl`) passed.

The gate cannot see nested radii, contrast, line breaks or whether a number is true. The
checklist covers those.

## Checklist

**Strategy**
- [ ] One offer, one audience, one primary action; written in the brief
- [ ] Layout type picked (A-E) with one line of why
- [ ] Hero matches the traffic source's promise
- [ ] No competing CTA above the fold; the final CTA repeats the hero's
- [ ] Each of the top three objections answered by proof, reversal or an FAQ entry
- [ ] At least one true risk reversal
- [ ] Five A/B headline variants written; two or three queued for a test

**Copy**
- [ ] Every benefit is an outcome, specific, and measured where it claims a number
- [ ] No `[SAMPLE]` left; proof is real or the section is gone
- [ ] Sentence case; calm, specific confirmations and errors
- [ ] `/humanize` run over the final copy

**Visual**
- [ ] Tokens defined once; no hex inside components
- [ ] One typeface, self-hosted; weights capped at 700
- [ ] Grep gate prints nothing
- [ ] Nested radii follow `inner = outer − gap`
- [ ] Hero heading and subheading within `max-w-2xl`, broken at phrase boundaries
- [ ] One icon set, no emoji icons, flat backgrounds
- [ ] Motion: one curve, transform/opacity only, reduced-motion fallback, reveals once
- [ ] Hover, active, focus, busy and error states on every control
- [ ] Hero CTA visible on 360×640; no horizontal scroll

**Ship**
- [ ] Title, description, canonical, OG image 1200×630, favicon
- [ ] Index or `noindex` decided
- [ ] JSON-LD: SoftwareApplication with sourced Offer (or none), FAQPage
- [ ] `robots.txt` with Content-Signal and named AI crawlers, `llms.txt`, real 404
- [ ] Counter installed, source registered, CTA events firing
- [ ] Privacy, terms, contact in the footer; no cookie banner needed
- [ ] `seo audit` and `seo agent-audit` run on the deployed URL

*Pitfall list and checklist shape adapted from elayadesign/ai-design-skills (MIT); the gate is
ours. See THIRD-PARTY.md.*
