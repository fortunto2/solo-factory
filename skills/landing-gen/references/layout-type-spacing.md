# Layout, type, spacing, motion

**When:** before the first section is built. **Output:** one tokens block that every section
reads: Tailwind 4 `@theme` in the global stylesheet (both stacks ship `tailwindcss@4.1`).

Choose the values once, as a set, and make everything else resolve to them. A page where each
section picked its own padding looks assembled even when every single choice was reasonable.
Same idea as `/swiftui-design-system`, applied to the web; its "count what is there first" step
is the grep gate in `anti-patterns.md`.

Tailwind 4 accepts any multiple of 0.25rem (`p-5`, `p-13`) and any arbitrary value
(`p-[13px]`). The scales below are a convention the gate enforces, not a framework limit.

## House defaults: change them here, in one place

| Token | Default | Why |
|---|---|---|
| Typeface | One family: Geist, Manrope, or the brand's. A mono only for code or numbers | Two families is a decision to make on purpose, not by accident |
| Weights | 400 body, 500-600 UI, 600-700 headings. Never 800-900 | Black weights shout and render badly at small sizes |
| Icons | One set: Phosphor or Lucide, as SVG components | Emoji as feature icons read as a template |
| Surfaces | Three levels (base, raised, overlay), light and dark | A colour per section is a colour nobody chose |
| Backgrounds | Flat colour per surface, no gradient backgrounds | The purple-to-blue gradient is the most recognisable template tell |
| Accent | One brand colour plus its hover state | Contrast 4.5:1 for text on it |
| Motion | `cubic-bezier(0.22, 1, 0.36, 1)`, 200-800 ms | Arrives fast, settles; one curve everywhere |

The template default you never chose (Inter, Roboto, Arial in most starters) is the font to
avoid; a system stack picked deliberately for zero download is fine.

**Self-host the font.** A `<link>` to `fonts.googleapis.com` sends every visitor's IP to Google;
LG München I (20 January 2022, 3 O 17493/20) awarded damages for exactly that, and it costs a
DNS lookup and TLS handshake to a third origin. Astro: `pnpm add @fontsource-variable/manrope`,
import it once in the layout. Next.js: `next/font` downloads at build and serves from your
origin, so the browser never calls Google.

```css
@import "tailwindcss";
@import "@fontsource-variable/manrope";

@theme {
  --font-sans: "Manrope Variable", ui-sans-serif, system-ui, sans-serif;
  --ease-out-quint: cubic-bezier(0.22, 1, 0.36, 1);   /* → ease-out-quint utility */
  --color-surface: #ffffff;
  --color-surface-raised: #f6f6f7;
  --color-surface-overlay: #ececee;
  --color-fg: #0b0b0c;
  --color-fg-muted: #5c5c63;
  --color-line: #e2e2e5;
  --color-accent: #2f6df6;
  --color-accent-fg: #ffffff;
}
@media (prefers-color-scheme: dark) {
  :root {
    --color-surface: #0b0b0c;
    --color-surface-raised: #18181a;
    --color-surface-overlay: #232326;
    --color-fg: #f4f4f5;
    --color-fg-muted: #a1a1aa;
    --color-line: #2c2c30;
  }
}
```

Components use `bg-surface`, `text-fg-muted`, `border-line`: never a hex inside a component.
Dark surfaces step up in lightness, one step per level; pure `#000` only as the base, if at all.

## Type scale: Tailwind steps only

Size / line height in px: xs 12/16 · sm 14/20 · base 16/24 · lg 18/28 · xl 20/28 · 2xl 24/32 ·
3xl 30/36 · 4xl 36/40 · 5xl 48 · 6xl 60 · 7xl 72 · 8xl 96 (5xl and up: line height 1).

A landing page needs about five of them:

| Role | Mobile | Desktop |
|---|---|---|
| Hero `h1` | `text-4xl` | `md:text-6xl` (`md:text-5xl` for a long headline) |
| Section `h2` | `text-3xl` | `md:text-4xl` |
| Card `h3` | `text-xl` | `md:text-2xl` |
| Body / lead | `text-base` | `md:text-lg` for the lead paragraph |
| Meta, captions | `text-sm` | `text-sm` |
| Buttons | `text-base font-semibold` | header button `text-sm font-semibold` |

- An off-scale size (`text-[19px]`, `1.4rem`) snaps to the nearest step **below**, taking that
  step's line height with it. Tune big headings with `tracking-tight`, not with a new size.
- `text-balance` on headings, `text-pretty` on body: no single word alone on the last line.
- **Measure.** Hero heading and subheading `max-w-2xl` (672 px); body `max-w-prose` (65ch).
- **Hero line breaks** go where the thought breaks. A forced break (`<br class="hidden md:inline">`)
  only at a phrase boundary, never splitting "15 / minutes".

## Spacing: one scale

Allowed steps: `0 0.5 1 2 3 4 6 8 10 12 16 20 24` (0, 2, 4, 8, 12, 16, 24, 32, 40, 48, 64, 80,
96 px). Nothing between, nothing arbitrary: `5 7 9 11 14` and the halves `1.5 2.5 3.5` fail the
gate.

| Where | Value |
|---|---|
| Section padding | `py-16 md:py-24`; hero `pt-20 md:pt-24` |
| Page gutter | `px-4 md:px-6`, container `max-w-6xl mx-auto` |
| Heading → body | `mt-4` |
| Body → CTA | `mt-8` |
| Card grid | `gap-4 md:gap-6`; card padding `p-6` |
| Primary button | `py-3 px-6 text-base font-semibold`: 48 px tall |
| Header button | `py-2 px-4 text-sm font-semibold` |

48 px clears Apple's 44 pt touch target (WCAG 2.2 AA asks for 24 px; 44 is the one that matters
on a phone).

## Radius

Tailwind steps only: `xs 2 · sm 4 · md 6 · lg 8 · xl 12 · 2xl 16 · 3xl 24 · 4xl 32 · full`.
Two per page plus `full` for pills, e.g. cards `rounded-2xl`, controls `rounded-xl`.

**Nested shapes:** `inner = outer − gap`, applied when the gap is under 32 px and the result is
over 2 px; otherwise leave the inner shape as it is. A `rounded-2xl` (16) card with `p-2` (8)
holds a `rounded-lg` (8) image. Concentric corners are why a nested card looks machined rather
than stacked.

**Borders** go all the way round or not at all. A one-sided accent border on a card is a
template tell.

## Motion

- **One curve**, `ease-out-quint` from the theme above. Never the browser defaults (`ease`,
  `linear`, `ease-in-out`).
- **Durations:** 200-300 ms for colour and opacity on hover, 500 ms for position, 600-800 ms for
  a section reveal. Nothing under 200 ms.
- **Animate `transform` and `opacity` only.** Never `top`, `left`, `width`, `height`: each frame
  re-runs layout. Never `transition-all`, which animates whatever happens to change.
- **Reduced motion:** movement becomes a plain fade (`motion-reduce:` / the media query below).
- **Navigation:** a compact bar floating off the top edge, sized to its content, translucent over
  `backdrop-blur-md`. Mobile menu opens as a full-height panel, links arrive one after another
  (up 24 px plus fade, 60 ms apart, whole sequence capped at 400 ms), the toggle icon morphs
  between states instead of swapping.

**Section reveal, once, without hiding content from people with JS off:**

```html
<!-- in <head>, Astro: is:inline so it runs before paint -->
<script is:inline>document.documentElement.classList.add('js')</script>
```

```css
[data-reveal] { transition: opacity 700ms var(--ease-out-quint), transform 700ms var(--ease-out-quint); }
.js [data-reveal]:not(.is-in) { opacity: 0; transform: translateY(2rem); }
@media (prefers-reduced-motion: reduce) {
  .js [data-reveal]:not(.is-in) { transform: none; }
}
```

```js
const io = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
}, { rootMargin: '0px 0px -10% 0px' });
document.querySelectorAll('[data-reveal]').forEach((el) => io.observe(el));
```

Never an unthrottled `window.addEventListener('scroll')`: it runs every frame and is what makes a
landing page stutter on a mid-range phone. The statement section's word fill is the same
observer per word span with `rootMargin: '0px 0px -40% 0px'` as the trigger line.

## States

Every interactive element ships all of them:

- **Hover:** background shift or a small translate, `duration-300 ease-out-quint`.
- **Active:** `active:translate-y-px`, physical feedback.
- **Focus:** `focus-visible:ring-2 ring-accent ring-offset-2`. Required, not decoration.
- **Busy:** the button disables and says what is happening ("Joining…"); content loading uses a
  skeleton shaped like the content, not a spinner.
- **Error:** inline, next to the field, specific. Never `alert()`.

## Responsive and fast

- Mobile first. Check 360, 768 and 1280 px wide. On a 360×640 screen the hero CTA is visible
  without scrolling, and nothing scrolls sideways.
- Images: `astro:assets` `<Image>` (or `next/image`) with width and height, so nothing jumps;
  the hero image `loading="eager" fetchpriority="high"`, everything else lazy.
- Budget: LCP under 2.5 s, CLS under 0.1, INP under 200 ms (Core Web Vitals "good").
- JavaScript on a static landing page is the reveal script and the analytics counter. A
  framework island only for something interactive, like a pricing toggle.

*Type scale snapping, the spacing table, the nested-radius rule and the motion rules adapted
from elayadesign/ai-design-skills (MIT); see THIRD-PARTY.md. Values here are ours.*
