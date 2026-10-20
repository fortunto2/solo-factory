---
name: solo-creator-growth
description: Plan growth for a consumer app through short vertical video — founder-led content first, paid UGC creators only after a measured signal. Use when user says "how to market the app", "UGC", "creators", "TikTok/Reels for my app", "short-form strategy", "influencer marketing for an app", or an app works but nobody installs it. Do NOT use for a full go-to-market plan (use /launch), a single promo video script (use /video-promo), or text posts (use /content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📱"
allowed-tools: Read, Grep, Glob, Write, AskUserQuestion, WebSearch
argument-hint: "<project-name or path>"
---

# creator-growth — short vertical video for a small consumer app

Most app software can now be copied in a weekend; distribution is the moat. For consumer
apps in 2026 the channel that moves installs is short vertical video made by people on
camera (UGC). Agencies run it at scale with hundreds of paid creators. A bootstrapped app
cannot afford that, but it can run the same playbook with its founder and a few niche
accounts, and buy creators only once one format has proved it converts.

Output: `docs/marketing.md` in the project — the budget gate, formats, cadence, accounts,
in-app levers and the measurement setup, with this app's numbers in it.

## Workflow

1. **Read the app's real numbers before planning.** Funnel events (launches → core action
   → paywall shown → purchase), price after the store's cut, weekly trend. No analytics →
   the first deliverable is instrumenting that funnel, not a content plan.
2. **Apply the budget gate.** Creator retainers run ~$1,000–2,000/month each. Payback sales
   per creator per month = retainer ÷ net revenue per sale. If current sales are an order of
   magnitude below that, the plan is Phase 1 only. Write the arithmetic into the doc — it is
   the argument for *not* hiring yet.
3. **Phase 1 — founder-led and niche accounts ($0).**
   - Find the content the product already makes. Its output (a photo, a result, a
     before/after) is the hook; "made with an app on a phone" is the surprise.
   - Four formats, by what they buy: *educational* converts ("3 settings for X"), *POV* and
     *humor* get reach, *story* (one session from start to result) builds trust. Add a
     *comparison* when the app replaces something expensive.
   - Hook in the first frame — visual, text on screen, sound. Younger audiences decide in
     ~0.1 s, millennials ~0.5 s, older viewers 1–2 s.
   - Cadence 1–2 posts a day, minimum. One vertical cut repurposed to TikTok, Reels, Shorts.
   - 2–3 niche accounts, each for one audience archetype, each promoting only this app.
   - CTA in the comments ("what app is this?" → answer), link in bio. Not in every video.
   - Camera basics decide weak vs strong: depth in the background, light, energy, audio.
4. **Phase 2 — paid creators, gated on a signal.** Trigger: one video passes a set view
   threshold (e.g. 100k) **and** its campaign link shows installs. Then 3–5 micro-creators in
   the same niche, per-video ($50–200) or a bonus per views (~$1,000 per million is the
   agency norm). Retainer only once cost per install is known.
5. **In-app levers** — find the ones the product is missing:
   - A small brand credit on free exports ("Shot on <App>"), removed by the paid tier.
     Every share becomes free UGC. Disclose it on the pricing/FAQ page.
   - Output that fits a vertical feed without editing (9:16 or 3:4, not 16:9).
   - The simplest possible first screen: presets with an Auto default instead of sliders.
     A creator filming a demo needs it to work in one tap.
   - Track whether a saved/shared result carried the credit, so its effect is measurable.
6. **Measurement.** One store campaign link per platform × account. iOS:
   `https://apps.apple.com/app/apple-store/id<APP_ID>?pt=<PROVIDER_ID>&ct=<platform>-<account>&mt=8`
   (`ct` ≤ 40 chars; installs per campaign in App Store Connect → App Analytics → Sources).
   Android: a Play referrer `&referrer=utm_source%3D...`. Judge a format after a week of
   posts on installs per campaign, not views.
7. **Verify** the doc has: the payback arithmetic, the Phase 2 trigger as a number, one
   campaign link per planned account, and the in-app levers each marked done or next.

## Gotchas

- Views are attention, installs are the result. A format can go viral and convert nothing;
  only per-campaign installs separate them.
- At small volumes, percentage swings are noise and multiples are findings. Do not kill a
  format over a 20 % week.
- A brand credit nobody was told about reads as a bait-and-switch in reviews. Say it on the
  pricing page and make the paid tier remove it.
- Many accounts work because each matches a different viewer archetype — not as a spam
  multiplier. Same content cloned across accounts gets suppressed.

## Don't

- Don't hire creators on retainer before one format has shown installs. The agency's own
  advice to unfunded founders is: do it yourself first.
- Don't promote several products at once. One app per account, one app per push.
- Don't put the download ask in every video; it is what gets a video scrolled.
- Don't plan without the funnel numbers. A content plan for an app whose paywall converts at
  0 % is a plan to pay for traffic that leaks.
