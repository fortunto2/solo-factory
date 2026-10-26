# Intake: one batch of questions, then a brief

**When:** before any copy or markup. **Inputs:** `docs/prd.md`, `README.md`, `docs/research.md`
if they exist. **Output:** the brief at the top of `docs/landing-content.md` (template in
SKILL.md), with every assumption marked.

A landing page wins one intent: **one offer, one audience, one primary action.** Everything in
the intake exists to pin those three down, plus what the visitor already believes when they
arrive. A homepage can serve several intents; a landing page that tries is a homepage.

## 1. Fill what the documents already answer

Read first, ask second. Most of the brief comes free from the PRD and research:

| Brief field | Where it usually is |
|---|---|
| Problem, solution, ICP | PRD: problem statement, target user |
| Features to turn into benefits | PRD: MVP scope, top 3-4 features |
| Competitors and their claims | `research.md`: competitor table |
| Pain in the visitor's own words | `research.md`: Reddit/HN quotes, reviews |
| Pricing, free tier, trial | PRD: monetization |
| Platform and store links | README, App Store / Play listing |

## 2. Ask the rest in ONE batch

One `AskUserQuestion` call with only the gaps, never a question per turn. Typical gaps:

1. **The one action.** Trial, purchase, waitlist, download, demo call. What counts as a
   conversion (click, signup, payment)?
2. **The offer, exactly.** What do they get, at what price, on which platforms?
3. **Traffic source.** Paid ads, search, social post, email to known users, App Store search.
   This decides the headline (see "message match" below).
4. **What the visitor knows on arrival.** Never heard of the category, knows the category but
   not you, or comparing you with a named competitor.
5. **Top three objections.** Why someone who needs this still would not convert today.
6. **Proof you actually have.** Real numbers, quotes you have permission to use, store rating,
   press, a public repo, the maker's own name. "None yet" is a valid answer and changes the page.
7. **Risk reversal you can honour.** Free tier, trial length, no card, cancel anytime, refund
   window. Only terms that are true.
8. **Assets.** Screenshots, a 10-second screen recording, device frames, logo, brand colour.
9. **Voice and languages.** Casual or professional; which locales ship on day one.
10. **Mode and deadline.** Fake-door test (hero, CTA, email capture: about two hours) or the full
    page.

If an answer does not come, assume, write the assumption into the brief in one line marked
`(assumed)`, and keep going. A stalled intake costs more than a wrong default you can change.

## 3. Message match

The hero promises what the visitor clicked on.

- **Paid ad:** the headline repeats the ad's promise in the ad's words, and the visual tone
  matches. A visitor who sees a different promise thinks they landed on the wrong page.
- **Search:** the headline answers the query's intent; "X vs Y" queries want layout D.
- **Social post or email to known users:** they already know you; skip the category explainer
  and go straight to the offer (layout C).
- **App Store search:** the page is a second chance for people who did not install; mirror the
  store listing's title and first screenshot.

## 4. Pick a layout type and say why

| Type | Use when |
|---|---|
| **A. Classic hero and sections** | One screenshot explains the product. The default. |
| **B. Long-form story** | The visitor has to be taught the category or talked out of real scepticism. |
| **C. Minimal conversion** | High-intent traffic (email, waitlist, download, fake-door test). Hero, one proof, risk reversal, CTA. |
| **D. Comparison** | Search intent names an alternative ("X vs Y", "best X for Y"). Needs an honest table, including where the competitor wins. |
| **E. App page** | A mobile app. Store badges as the CTA, device-framed screenshots, Smart App Banner, rating only from the store. |

Write the pick and one line of reasoning into the brief.

## 5. Forced reasoning before copy

Still required, in the brief, before any headline:

- **Primary conversion:** the ONE action.
- **Objections → trust signal:** for each of the top three, the proof or reversal that answers
  it. An objection with no answer becomes an FAQ entry, never silence.
- **Above the fold:** promise, how, CTA, one proof signal, visual. Nothing else.

*Intake structure and the A-D layout taxonomy adapted from elayadesign/ai-design-skills (MIT);
see THIRD-PARTY.md.*
