---
name: solo-knowledge
description: Use when needing methodology reference, asking about principles, harness engineering, SGR, launch playbook, agent memory, decision frameworks, or any topic covered in the solopreneur knowledge base. Also use when the user asks "what do we know about X" or "how does our methodology handle X".
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Read, WebFetch, Grep, Glob
argument-hint: "<question or topic>"
---

# /knowledge

Answer questions using the solopreneur knowledge base. Loads the site index via llms.txt, finds relevant pages, fetches and synthesizes answers.

**Source:** [rustman.org/llms.txt](https://rustman.org/llms.txt) — full index of all published content.

## How It Works

The knowledge base is a static site (rustman.org) with 60+ pages organized as:
- **Posts** — pillar articles (manifesto, STREAM framework, harness engineering, agent memory, context graphs, launch playbook)
- **Wiki** — compiled knowledge pages (concepts, summaries, catalogs)
- **Projects** — build-in-public case studies
- **Skills** — solo-factory executable skills documentation
- **Stacks** — technology stack templates

All content indexed in `llms.txt` — a machine-readable map with titles, URLs, and descriptions.

## Steps

1. **Load index** — fetch `https://rustman.org/llms.txt` via WebFetch (or read from `references/llms-snapshot.txt` if offline)

2. **Parse question** from `$ARGUMENTS`:
   - If empty: show available topics from the index
   - If topic: find matching pages by keyword in titles/descriptions

3. **Fetch relevant pages** — for each match (max 3), fetch the full page:
   ```
   WebFetch https://rustman.org/wiki/{slug}
   ```
   Or read locally if in solopreneur repo:
   ```
   Read wiki/{slug}.md
   ```

4. **Synthesize answer** — combine information from fetched pages:
   - Answer the question directly
   - Cite sources with links
   - Note related pages for deeper reading
   - If the answer contradicts or extends existing knowledge, note that

5. **Suggest follow-up** — based on wikilinks in the fetched pages, suggest related topics.

## Usage Examples

```
/knowledge "how does harness engineering work?"
→ Fetches harness-engineering post + wiki summary, synthesizes key concepts

/knowledge "what's our approach to agent memory?"
→ Fetches agent-memory-architecture post + mempalace page, compares approaches

/knowledge "what stacks do we support?"
→ Lists all 9 stack templates with tech details

/knowledge "how to validate a startup idea?"
→ Fetches launch-playbook + SEED scoring + validation hub
```

## Offline Mode

If WebFetch is unavailable, the skill falls back to:
1. Local wiki files: `Grep "topic" wiki/` + `Read wiki/{match}.md`
2. Snapshot in `references/llms-snapshot.txt`

## Key References

- `references/llms-snapshot.txt` — cached copy of llms.txt (update with: `curl -s https://rustman.org/llms.txt > references/llms-snapshot.txt`)

## Content Domains

| Domain | Key Pages | Depth |
|--------|----------|-------|
| **Philosophy** | Manifesto, STREAM framework, antifragile design | Deep |
| **Launch** | Launch playbook, SEED scoring, kill/iterate/scale | Deep |
| **Engineering** | SGR, dev principles, CLI-first, privacy architecture | Deep |
| **AI Agents** | Harness engineering, agent memory, context graphs, RAG patterns | Very deep |
| **Tools** | Agent toolkit landscape, benchmarks, LLM providers | Catalog |
| **Projects** | 12 open source projects with case studies | Medium |
| **Skills** | 30 solo-factory skills with full documentation | Reference |
