# Ship: the parts that get forgotten

**When:** sections are built. **Output:** the page's `<head>`, JSON-LD, the files agents read, the
analytics counter with CTA events, legal links, a working form. Then verify with `/seo-cli`.

## Head

- `<title>` 50-60 chars, meta description 150-160, `<link rel="canonical">`, `<html lang>`.
- Open Graph: `og:title`, `og:description`, `og:image` (1200×630), `og:url`, `og:site_name`,
  `og:type`; `twitter:card` = `summary_large_image`.
- Favicon as SVG plus a 180×180 `apple-touch-icon`.
- Multilingual: `hreflang` per locale **and** `x-default`.
- Mobile app: `<meta name="apple-itunes-app" content="app-id=<id>">` gives Safari's Smart App
  Banner for free.

**Index or not.** An evergreen offer whose promise matches search intent: index it, link to it
from the home and feature pages. An ad-only, time-boxed or fake-door page: `noindex`, and keep it
out of the sitemap.

## JSON-LD

- **Home:** `WebSite` plus `Organization` (or `Person` for a solo maker).
- **The product:** `SoftwareApplication`, typed `MobileApplication` for a store app and
  `WebApplication` for a hosted product. Fields: `name`, `description`, `url`,
  `applicationCategory`, `operatingSystem`, `softwareVersion`, `author`, `sameAs` (store
  listing, repo).
- **Offer only from a source**, never from memory:
  - App Store / Play listing: price and currency from the listing, looked up at build
    (`https://itunes.apple.com/lookup?id=<id>` returns price, currency, version, rating).
  - A package registry (crates.io, npm, PyPI): price `0`.
  - A price the page itself states, with the URL where it is bought.
  - No source: no Offer. A guessed price is a claim an agent will repeat to a buyer.
- With an Offer, type the node `["MobileApplication", "Product"]` (or the web variant): Product
  is what a shopping agent looks for, and schema.org allows several types on one node.
- `aggregateRating` only from the store's own numbers, when its rating count is above zero.
  Never computed from quotes on the page.
- **FAQPage** from the FAQ section, same text as the page. Google has shown FAQ rich results only
  for authoritative government and health sites since August 2023; answer engines still parse
  it, so it costs nothing and helps the page get quoted.

```astro
<script type="application/ld+json" set:html={JSON.stringify(ld)} />
```

Next.js: the same object through `dangerouslySetInnerHTML={{ __html: JSON.stringify(ld) }}`.
A worked implementation of the Offer rules above: `src/lib/software-ld.ts` in
[fortunto2/rustman-blog](https://github.com/fortunto2/rustman-blog).

## Files agents read

- **`robots.txt`:** `Content-Signal` inside the `User-agent: *` group, plus the AI crawlers
  named explicitly (GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, Claude-User,
  Claude-SearchBot, PerplexityBot, Perplexity-User, Google-Extended, Applebot-Extended).
  Silence lets whoever wrote the crawler decide for you.

  ```
  User-agent: *
  Content-Signal: search=yes, ai-input=yes, ai-train=no
  Allow: /
  Sitemap: https://example.com/sitemap-index.xml
  ```

- **`llms.txt`:** what the product is, who it is for, the price, links to the pages that matter
  (format: llmstxt.org).
- **Markdown twin** of the page, negotiated on `Accept: text/markdown`. The three traps that
  break it are in `/seo-cli`, "Fixing agent-readiness".
- **A real 404.** Astro: `src/pages/404.astro`. Without a built `404.html` a static host answers
  200 with the home page for every path, and crawlers see a site of identical pages.
- **Publish only what answers.** No agent card, MCP server card, OAuth metadata or payment file
  unless that endpoint exists. A file claiming otherwise raises a checker's score and sends an
  agent to a door that does not open.

## Analytics: a counter that needs no banner

Default in this factory: **superduper-analytics**
([fortunto2/superduper-analytics](https://github.com/fortunto2/superduper-analytics), hosted at
`analytics.superduperai.co`, or self-host it). Never PostHog, never Google Analytics or Tag
Manager on a privacy-first page. One line in `<head>`:

```html
<script defer src="https://analytics.superduperai.co/sda.js" data-source="<registered-id>"></script>
```

- The `data-source` must be registered in that instance's `registry/sources.yaml`, or ingest
  refuses the events with 403.
- `page_viewed` and `page_engaged` arrive with no further code, with bots classified.
- **The conversion is an event**, named `object_verb` in the past tense:

  ```js
  sda("cta_clicked", { location: "hero" });      // and "final" on the bottom CTA
  sda("waitlist_joined", { source: "landing" });
  sda("store_badge_clicked", { store: "app_store" });
  ```

  Events are batched and sent when the page is hidden, so a click handler can fire one right
  before navigating away. Calling `sda()` before the script loads needs the one-line stub from
  the repo's `docs/install.md`.
- **Why no banner:** no cookie, no `localStorage`, no fingerprint returned to the browser. That
  stays true only while nothing else on the page sets one: no third-party pixels, no Google
  Fonts CDN, no embed that drops cookies (use a click-to-load poster for video).
- What to do with the numbers: `/metrics-track`; who came and which agents read the page:
  `seo traffic`, `seo agents`.

## Forms

- `type="email"`, `autocomplete="email"`, `required`, an inline message when it is wrong. The
  server validates again.
- A honeypot field before reaching for a CAPTCHA.
- The emails go to a table you own (Supabase in the `nextjs-supabase` stack), not to a
  third-party widget that sets cookies.
- The success state says what happens next and when.

## Legal and trust

Footer: privacy policy, terms, a real contact, the maker or company name. Generate them with
`/legal`; the privacy page says the counter is cookieless. A cookie banner is needed only when
something on the page sets a cookie, and then the first move is removing that thing.

## Accessibility

Landmarks (`header`, `nav`, `main`, `section` with a heading each, `footer`); one `h1`; a
skip-to-content link; visible focus; alt text on meaningful images and `alt=""` on decorative
ones; contrast 4.5:1 for body text, 3:1 for large; `aria-current="page"` in the nav; no
`href="#"` (link it or render it disabled).

## Verify after deploy

```bash
seo audit https://example.com          # SEO + GEO score
seo agent-audit https://example.com    # robots, Content-Signals, llms.txt, markdown twin
curl -s "https://analytics.superduperai.co/v1/stats?days=1" | jq '.sources'   # counter live?
```

Plus Lighthouse on mobile for the Core Web Vitals budget in `layout-type-spacing.md`.

*The ship list (legal links, 404, form validation, skip link, meta, alt text) adapted from
elayadesign/ai-design-skills (MIT); JSON-LD, agent-readiness and analytics are ours.*
