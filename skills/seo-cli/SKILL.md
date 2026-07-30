---
name: solo-seo-cli
description: Manage SEO for all sites via the `seo` CLI — audit pages (SEO+GEO score), check Search Console analytics, submit sitemaps, ping IndexNow, inspect indexing, track positions. Covers Google, Bing, Yandex. Use when the user asks about search performance, indexing, sitemap submission, SEO/GEO score, or wants to fix a site's SEO. Do NOT use for writing landing copy (/landing-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🔍"
allowed-tools: Read, Grep, Bash, Glob, Edit, Write, WebFetch
argument-hint: "[url]"
---

# SEO CLI Skill

Unified search engine management and SEO/GEO auditing for all configured sites.

## Running it

`seo` is installed globally as a wrapper at `~/.local/bin/seo`. Just call it:

```bash
seo audit https://example.com
```

If the command is missing, recreate the wrapper (the project keeps `cli.py` and `config.yaml` side
by side and is **not** packaged for `uv tool install` — a global install fails with
`ModuleNotFoundError: No module named 'cli'`):

```bash
cat > ~/.local/bin/seo <<'EOF'
#!/bin/sh
SEO_HOME="$HOME/startups/shared/seo-cli"
exec "$SEO_HOME/.venv/bin/python" "$SEO_HOME/cli.py" "$@"
EOF
chmod +x ~/.local/bin/seo
```

Source lives in `~/startups/shared/seo-cli/`. Do **not** build a `SEO=...` shell variable holding
two words — in zsh it is not word-split and the call fails.

## Commands

### Audit — SEO+GEO health check
```bash
# Summary table across ALL sites (fast, no PageSpeed)
seo audit

# Detailed single-site audit with PageSpeed + keywords
seo audit https://superduperai.co
```

### Report — search analytics + opportunities across all sites
```bash
seo report
```

### Analytics — search performance last 28 days
```bash
seo analytics
```

### Inspect URL — check indexing status
```bash
seo inspect https://superduperai.co/blog/veo3
```

### Submit sitemaps — push to Google + Bing + Yandex
```bash
seo submit
```

### Ping IndexNow — instant notify Bing + Yandex + Naver + Seznam
```bash
seo ping
```

### Reindex — instant reindex via Google Indexing API + IndexNow
```bash
seo reindex https://superduperai.co/blog/new-post
```

### Status — overview of all sites and engines
```bash
seo status
```

## Configured Sites

Sites with local paths, framework, and hosting are in `config.yaml`. To find a project path:
```python
import yaml
cfg = yaml.safe_load(open("/Users/rustam/startups/shared/seo-cli/config.yaml"))
for s in cfg["sites"]:
    print(f"{s['name']:15s} {s.get('path', '?'):50s} {s.get('framework', '?'):8s} {s.get('hosting', '?')}")
```

Or just read `config.yaml` — each site has `path`, `framework`, `hosting` fields.

## The four fixes that move the score most

Field-tested on a fresh Astro site: **90% → 96%** in one pass. Check these before anything else.

**1. Internal links causing 308 redirects.** Most static hosts serve `/about/` and 308-redirect
`/about`. If the markup links to the unslashed form, every internal link costs a redirect hop and
the audit reports broken links. Make the path helper emit a trailing slash, and check the URLs
inside JSON-LD too — they are easy to miss:

```bash
for u in /about /studio /privacy; do
  printf "%-12s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' "https://example.com$u")"
done   # anything other than 200 means the link in your markup is wrong
```

**2. `robots.txt` and `sitemap.xml` that return 200 but are not files.** SPA-style hosts answer
every unknown path with the home page, so a naive check passes while crawlers get HTML. Verify the
body, not the status code:

```bash
curl -s --compressed https://example.com/robots.txt | head -3
```

For Astro use `@astrojs/sitemap` with the `i18n` option — it emits hreflang alternates for free.

**3. `hreflang="x-default"`.** Multi-language sites almost always ship the per-language tags and
forget the fallback for everyone else.

**4. `og:url` and `og:site_name`.** Usually missing when og:title/description were added by hand.

⚠️ Cloudflare caches a missing file's fallback. After adding `robots.txt` or `llms.txt` to a site
that previously 200'd them as HTML, the old body can persist — verify with a cache-buster
(`?v=1`) before believing the deploy failed.

## Audit Categories & How to Fix

When the audit shows failures, here's what to do for each category:

### SEO Basics (title, desc, h1, canonical, viewport, hreflang)
- **Missing title/description**: Edit the page's `<head>` or metadata export. In Next.js → `export const metadata` or `generateMetadata()`. In Astro → `<head>` in layout.
- **Missing H1**: Add `<h1>` tag to the page content (exactly one per page).
- **Missing canonical**: Add `<link rel="canonical">` or set in framework metadata config.
- **Missing hreflang**: Add `<link rel="alternate" hreflang="...">` tags for each language version. Only needed for multi-language sites.

### Open Graph (og:title, og:description, og:image, twitter:card)
- **Missing og:image**: Create 1200x630 social preview image, place in `public/images/og/`. Set via `openGraph.images` in metadata (Next.js) or `<meta property="og:image">` (Astro).
- **Missing og:tags**: Set in page metadata. Most frameworks auto-generate from page metadata config.

### Structured Data (JSON-LD)
- **No JSON-LD**: Add `<script type="application/ld+json">` to the page. Minimum: `WebSite` + `Organization` schema on homepage.
- **Fix template** (Next.js):
  ```jsx
  <script type="application/ld+json" dangerouslySetInnerHTML={{__html: JSON.stringify({
    "@context": "https://schema.org",
    "@type": "WebSite",
    "name": "Site Name",
    "url": "https://example.com"
  })}} />
  ```
- **Fix template** (Astro):
  ```astro
  <script type="application/ld+json" set:html={JSON.stringify({
    "@context": "https://schema.org",
    "@type": "WebSite",
    "name": "Site Name",
    "url": "https://example.com"
  })} />
  ```
- Add `FAQPage`, `Article`, `Product`, or `SoftwareApplication` schema where relevant for AI citations.

### Files (robots.txt, sitemap.xml, favicon)
- **Missing robots.txt**: Create `public/robots.txt`. Minimum: `User-agent: *\nAllow: /\nSitemap: https://domain/sitemap.xml`
- **Missing sitemap**: Next.js → create `app/sitemap.ts`. Astro → `@astrojs/sitemap` integration.
- **Missing favicon**: Place `favicon.ico` in `public/`.

### GEO — AI/LLM Optimization
- **Missing llms.txt**: Create `public/llms.txt` — plain text describing what the site/product does, for AI agents. See llmstxt.org.
- **Missing llms-full.txt**: Optional detailed version with full docs/features.
- **AI bots blocked**: Check `robots.txt` for `Disallow` rules targeting GPTBot, ChatGPT-User, Claude-Web, etc. Remove blocks to allow AI indexing.
- **Missing markdown content**: Serve content as `.md` endpoints for LLM consumption.
- **Missing rich schema**: Add FAQ, Article, Product, SoftwareApplication schema — AI engines use structured data for citations.

## Auto-Fix Workflow

When user asks to fix SEO/GEO issues:

1. Run `seo audit` to get current scores across all sites
2. For each failing check, navigate to the project directory (see table above)
3. Apply fixes directly in the source code:
   - Read the relevant layout/page file first
   - Make minimal targeted edits
   - Prefer framework-native metadata APIs over raw HTML
4. After fixes, commit with message like "Improve SEO: add JSON-LD schema, og:image"
5. Re-run `seo audit` to verify improvement

Priority order for fixes:
1. **Title, description, H1** — basic SEO, biggest impact
2. **JSON-LD schema** — critical for both Google rich results and AI citations
3. **og:image** — social sharing and link previews
4. **llms.txt** — AI agent discovery
5. **hreflang** — only for multi-language sites

## Engine Coverage

| Action | Google | Bing | Yandex | Naver/Seznam |
|--------|--------|------|--------|--------------|
| `audit` | - | - | - | - |
| `report` | via SA | - | - | - |
| `analytics` | via SA | - | via OAuth | - |
| `inspect` | via SA | - | - | - |
| `submit` | via SA | via API key | via OAuth | - |
| `ping` | **not supported** | via IndexNow | via IndexNow | via IndexNow |
| `reindex` | via Indexing API | via IndexNow | via IndexNow | via IndexNow |

**Important:** Google does NOT support IndexNow. Use `submit` for Google, `ping` for the rest.

## Credentials

- **Google:** Service account at `~/.config/seo-cli/service-account.json`
- **IndexNow:** Key in config.yaml, verification files in each site's `public/` directory
- **Bing/Yandex:** Not yet configured (keys go in config.yaml)

## When to Use

- User asks "how is SEO doing" / "check scores" / "audit sites" → run `audit`
- User asks "check search traffic" / "analytics" → run `analytics` or `report`
- User asks "is this page indexed" → run `inspect <url>`
- User deployed new content → run `submit` + `ping`
- User asks "fix SEO" / "improve scores" → run `audit`, then fix issues in project source
- User asks "SEO status" → run `status`
- After adding new pages/sitemap → run `ping` for instant indexing
