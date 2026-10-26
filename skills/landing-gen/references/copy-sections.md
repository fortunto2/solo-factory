# Copy, section by section

**When:** after the brief. **Inputs:** the brief (action, offer, ICP, source, objections, proof
on hand, layout type). **Output:** outline plus finished copy for every section, written into
`docs/landing-content.md` **before** any markup.

## The page, top to bottom

**Above the fold: the promise**

1. **Headline.** The outcome, for a named audience. 6-12 words.
2. **Subheadline.** What it is and how it gets them there. One or two sentences, 15-25 words.
3. **Primary CTA.** A verb plus what they get.
4. **One proof signal** beside the CTA, and only a real one (see "Sample vs shipped").
5. **Visual.** The product doing the thing: a screenshot, a 10-second loop, a device frame. An
   abstract illustration only when there is nothing to show yet.

**Mid page: the argument**

6. **Problem to solution.** One section. The pain in the visitor's words, lifted from the
   quotes in `research.md`, then the turn.
7. **Benefits.** Three to five, each an outcome (format below).
8. **How it works.** Three steps, each starting with a verb.
9. **Proof.** Quotes, a case, numbers. Put each piece beside the claim it supports rather than
   parking all of it in one block at the bottom.
10. *(Optional)* **Statement section.** One line of the core benefit in large type (`text-4xl`
    to `text-6xl`, two lines or more), on its own mid page, not stacked under the hero. A
    word-by-word fill on scroll suits it: words start at about 30% opacity and reach full
    colour in reading order as they cross a trigger line (IntersectionObserver per word, off
    under reduced motion, see `layout-type-spacing.md`).

**Bottom: objections**

11. **FAQ.** Six to twelve, each one answering an objection from the brief: price, what
    happens to my data, which platforms, can I cancel, why not {competitor}. Plain question
    and answer, so answer engines can lift it; the same text goes into FAQPage JSON-LD
    (`ship.md`). For a high-friction offer, move the FAQ up, right after proof.
12. **Risk reversal.** At least one of: free tier, trial, no card, cancel anytime, refund
    window. True terms only.
13. **Final CTA.** The hero's verb and promise again, word for word on the button.

**Footer:** privacy, terms, contact, store badges for apps.

Layout C keeps 1-5, 12 and 13. Layout D inserts a comparison table after 7. Layout E uses store
badges as the CTA and device-framed screenshots as 5 and 8.

## Build order

Hero, then benefits, how it works, proof, FAQ, final CTA. One section per iteration, each
reviewed before the next. Never regenerate the whole page to change one part: the diff stops
being reviewable and sections that were right drift.

## Hero

**Headline formulas.** Pick from the brief, not from the list:

- "{Outcome} without {pain}"
- "The {category} for {audience}"
- "{Result} in {time}"
- Paid traffic: the ad's promise in the ad's words (message match, `intake.md`).

**CTA.** Verb plus what they get: "Start free trial", "Get the app", "Join the waitlist",
"Book a 15-minute demo". Never "Learn more" or "Submit"; "Get started" alone names no outcome.
One primary CTA above the fold. A secondary link ("See how it works") is visually subordinate,
never a second button of equal weight.

## A/B headline variants (five)

Five distinct approaches, so a test compares ideas rather than synonyms:

1. Pain: "Tired of {problem}?"
2. Benefit: "{Outcome} without {hassle}"
3. Curiosity: "The {adjective} way to {action}"
4. Social proof: "Join {N} {users} who {outcome}", only with a real N
5. Direct: "{Product}: {one-line value prop}"

Test two or three before launch (SKILL.md, gotcha 5); the winner goes in the hero.

## Benefits

Bold the outcome, then the detail that makes it believable:

> **Reports in 15 minutes, not four hours.** Pulls the week's numbers from Stripe and Sheets
> every Monday at 9:00.

Translate each PRD feature into what the visitor gets:

| Feature (what it does) | Benefit (what it means for them) |
|---|---|
| On-device processing | Your photos never leave the phone |
| Offline mode | Works on the plane and in the basement |
| One-click export | The report is ready before the meeting |

**Specific beats vague, and measured beats specific.** "Save time and streamline your workflow"
says nothing. "Cut weekly reporting from 4 hours to 15 minutes" says something, but only if
someone measured it. Unmeasured, say what it does: "One button exports the week's report."

## Sample vs shipped

Two different jobs, two rules:

- **Mockup or preview.** Content must read like a real product: no lorem, no "Your headline
  here". Names that fit the audience and region, numbers that look measured rather than
  "10,000+", dates that vary down a list, company names that sound like the industry. Mark
  every invented item `[SAMPLE]` in the content file and in the markup.
- **Shipped page.** Every `[SAMPLE]` is replaced by a real item or deleted. Invented
  testimonials, logos, user counts and ratings on a live page are fabricated reviews; the US
  FTC rule on fake reviews and testimonials (16 CFR Part 465, in force since 21 October 2024)
  fines them per violation. No real proof yet: "Built by {maker}", a real screenshot, a public
  repo, an honest changelog. The grep gate in `anti-patterns.md` fails on any `[SAMPLE]` left.

## Microcopy

- Sentence case for headings and buttons.
- Confirmations are calm and specific: "You're on the list. One email when the beta opens."
- Errors say what failed and what to do: "That email is missing the part after @."
- No exclamation marks, no "Oops", no cute interjections.

## Voice

Draft, then run `/humanize` over the copy: em dashes, stock phrases, inflated adjectives,
reflexive triplets. Words that carry nothing on a landing page: revolutionize, supercharge,
seamless, cutting-edge, effortless, next level, unlock, empower, world-class, game-changer,
harness the power. Replace each with what the product actually does.

*Page structure, build order and the content-realism checks adapted from
elayadesign/ai-design-skills (MIT), which credits Leonxlnx/taste-skill (MIT) for the realism
ideas; the shipped-page rule is ours. See THIRD-PARTY.md.*
