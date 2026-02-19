---
name: solo-you2idea-extract
description: Extract startup ideas from YouTube videos via solograph MCP — index, search, and export to you2idea site. Multi-MCP coordination pattern (YouTube source → analysis → KB storage). Use when user says "extract ideas from YouTube", "index YouTube video", "update you2idea", "find startup ideas in video", or "sync videos to site". Do NOT use for general YouTube watching (no skill needed) or content creation (use /content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "💡"
allowed-tools: Read, Grep, Bash, Glob, Write, Edit, AskUserQuestion, mcp__solograph__source_search, mcp__solograph__source_list, mcp__solograph__source_tags, mcp__solograph__source_related, mcp__solograph__kb_search, mcp__solograph__web_search, mcp__solograph__codegraph_query
argument-hint: "[video-url or channel-name or 'deploy']"
---

# /you2idea-extract

Multi-MCP coordination skill: YouTube MCP tools → idea analysis → KB/site export.

Three modes:
- **Index**: Add video(s) to FalkorDB source graph via solograph CLI
- **Analyze**: Search indexed corpus for startup ideas, extract insights
- **Deploy**: Export FalkorDB → you2idea site (data files → R2 → Cloudflare Pages)

## MCP Tools

- `source_search(query, source="youtube")` — semantic search over indexed videos
- `source_list()` — check indexed video counts
- `source_tags()` — auto-detected topics with confidence scores
- `source_related(video_url)` — find related videos by shared tags
- `kb_search(query)` — cross-reference with solopreneur knowledge base
- `web_search(query, engines="youtube")` — discover new videos to index
- `codegraph_query(cypher)` — raw queries against YouTube graph

## Steps

### Mode 1: Index (default if URL provided)

1. **Parse input** from `$ARGUMENTS`:
   - URL (`https://youtube.com/watch?v=...`) → single video index
   - Channel name (`GregIsenberg`) → channel batch index
   - If empty, ask: "Video URL, channel name, or 'deploy'?"

2. **Index video(s)** via solograph CLI:
   ```bash
   # Single video (no SearXNG needed — direct yt-dlp)
   cd ~/startups/shared/solograph && uv run solograph-cli index-youtube -u "$URL"

   # Channel batch (needs SearXNG for discovery)
   cd ~/startups/shared/solograph && TAVILY_API_URL=http://localhost:8013 uv run solograph-cli index-youtube -c "$CHANNEL" -n 5
   ```

3. **Verify indexing** — `source_list()` to confirm new video count.

4. **Show indexed data** — `source_tags()` for topic distribution.

### Mode 2: Analyze (if query-like input)

1. **Search corpus** — `source_search(query="$ARGUMENTS", source="youtube")`.

2. **Cross-reference KB** — `kb_search(query="$ARGUMENTS")` for related opportunities.

3. **Extract insights** — for each relevant video chunk:
   - Identify the startup idea mentioned
   - Note timestamp and speaker context
   - Rate idea potential (based on specificity, market evidence, feasibility)

4. **Write insights** to `3-inbox/` using capture format or print summary.

### Mode 3: Deploy (if `$ARGUMENTS` contains "deploy" or "sync" or "update site")

1. **Check prerequisites:**
   ```bash
   # FalkorDB source graph exists?
   test -f ~/.solo/sources/youtube/graph.db && echo "graph_ok" || echo "no_graph"
   # you2idea project accessible?
   test -d ~/startups/active/you2idea && echo "project_ok" || echo "no_project"
   ```

2. **Run export pipeline** in you2idea project:
   ```bash
   cd ~/startups/active/you2idea
   make export              # FalkorDB → all-videos.json + videos.json
   make export-vectors      # FalkorDB → vectors.bin + chunks-meta.json + graph.json
   ```

3. **Fetch new transcripts** (VTT files for new videos):
   ```bash
   cd ~/startups/active/you2idea
   make fetch-transcripts   # yt-dlp → public/data/vtt/
   ```

4. **Upload to R2 CDN:**
   ```bash
   cd ~/startups/active/you2idea
   make upload              # Incremental → R2 (you2idea-data bucket)
   ```

5. **Build + deploy site:**
   ```bash
   cd ~/startups/active/you2idea
   make build && make deploy  # Astro → Cloudflare Pages
   ```

6. **Report results** — video count, file sizes, deploy URL.

**Shortcut:** `make update-all` runs entire pipeline in one command.

## Pipeline Architecture (Multi-MCP Pattern)

```
YouTube (yt-dlp)
  → FalkorDB source graph (solograph MCP: source_search, source_tags)
    → Export scripts (FalkorDB → JSON + vectors)
      → R2 CDN (cdn.you2idea.com)
        → Astro SSG/SSR site (you2idea.com)
```

MCP tools provide the **query layer** over the pipeline:
- Before indexing: `web_search(engines="youtube")` discovers videos
- After indexing: `source_search` finds relevant chunks
- Cross-project: `kb_search` connects ideas to existing opportunities

## Common Issues

### solograph CLI not found
**Cause:** solograph package not installed or not in PATH.
**Fix:** `cd ~/startups/shared/solograph && uv sync`. CLI is at `uv run solograph-cli`.

### SearXNG unavailable for channel indexing
**Cause:** SSH tunnel not active. Channel mode needs SearXNG for video discovery.
**Fix:** Run `make search-tunnel` in solopreneur. Or use URL mode (`-u`) which bypasses SearXNG.

### Export fails with "no graph"
**Cause:** FalkorDB source graph doesn't exist at `~/.solo/sources/youtube/graph.db`.
**Fix:** Index at least one video first: `solograph-cli index-youtube -u "VIDEO_URL"`.

### R2 upload fails
**Cause:** rclone not configured or wrangler not authenticated.
**Fix:** Run `~/startups/active/you2idea/scripts/setup-rclone-r2.sh` or `wrangler login`.
