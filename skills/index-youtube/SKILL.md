---
name: solo-index-youtube
description: Index YouTube channel videos and transcripts into FalkorDB source graph for semantic search. Use when user says "index YouTube", "add YouTube channel", "update video index", or "index transcripts". Requires yt-dlp and SearXNG tunnel active.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
argument-hint: "[channel handles or 'all']"
---

# /index-youtube

Index YouTube video transcripts into FalkorDB source vectors via solograph CLI.

## Prerequisites

Check that yt-dlp and SearXNG are available:

```bash
which yt-dlp || echo "MISSING: brew install yt-dlp"
curl -sf http://localhost:8013/health && echo "searxng_ok" || echo "MISSING: make search-tunnel (in solopreneur)"
```

If SearXNG is down, tell the user to run `make search-tunnel` in solopreneur first.

## Arguments

Parse `$ARGUMENTS` for channel handles or "all":
- If empty or "all": index all channels from channels.yaml
- If one or more handles: index only those channels (e.g. "GregIsenberg ycombinator")

## Execution

Run the solograph CLI command:

```bash
# Single channel
TAVILY_API_URL=http://localhost:8013 uv run --project ~/startups/shared/solograph solograph-cli index-youtube -c GregIsenberg -n 10

# Multiple channels
TAVILY_API_URL=http://localhost:8013 uv run --project ~/startups/shared/solograph solograph-cli index-youtube -c GregIsenberg -c ycombinator -n 10

# All channels (from channels.yaml)
TAVILY_API_URL=http://localhost:8013 uv run --project ~/startups/shared/solograph solograph-cli index-youtube -n 10

# Dry run (parse only, no DB writes)
TAVILY_API_URL=http://localhost:8013 uv run --project ~/startups/shared/solograph solograph-cli index-youtube --dry-run
```

Or via solopreneur Makefile:
```bash
cd ~/startups/solopreneur && make index-youtube CHANNELS=GregIsenberg LIMIT=10
```

## Verification

After indexing, verify the results:

```bash
# Check source list for youtube entry
TAVILY_API_URL=http://localhost:8013 uv run --project ~/startups/shared/solograph solograph-cli source-list

# Search indexed content
TAVILY_API_URL=http://localhost:8013 uv run --project ~/startups/shared/solograph solograph-cli source-search "startup idea" --source youtube
```

## Output

Report to the user:
1. Number of videos indexed
2. Number of chunks created
3. How many had chapter markers
4. How many were skipped (already indexed or no transcript)

## Common Issues

### "MISSING: brew install yt-dlp"
**Cause:** yt-dlp not installed.
**Fix:** Run `brew install yt-dlp` (macOS) or `pip install yt-dlp`.

### SearXNG health check fails
**Cause:** SSH tunnel not active.
**Fix:** Run `make search-tunnel` in solopreneur first. For direct URL mode (`-u`), SearXNG is not needed.

### Videos skipped (no transcript)
**Cause:** Video has no auto-generated or manual subtitles.
**Fix:** This is expected — some videos lack transcripts. Check `~/.solo/sources/youtube/vtt/` for cached VTT files.
