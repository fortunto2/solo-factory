# you2idea Pipeline Details

## Data Flow

```
solograph-cli index-youtube              [Index videos → FalkorDB]
  ↓ (export-data.py)
make export                             [FalkorDB → all-videos.json + videos.json]
  ↓ (export-vectors.py)
make export-vectors                     [FalkorDB → vectors.bin + chunks-meta.json + graph.json]
  ↓ (fetch-transcripts.py)
make fetch-transcripts                  [Download VTT via yt-dlp → public/data/vtt/]
  ↓ (upload-r2.sh)
make upload                             [Upload to R2 CDN (incremental)]
  ↓
make build                              [Astro SSG/SSR build]
  ↓
make deploy                             [Cloudflare Pages deploy]
```

## Source store (YouTube)

Since 26 Oct 2026 solograph keeps sources in SQLite, not FalkorDB: `~/.solo/sources/search.db`
holds an FTS5 index of transcript chunks (documents keyed `youtube/<id>`), plus `videos`
(id, title, channel, created, duration, chapters) and `video_tags` (video, tag, weight).
Query it with the MCP tool `source_search` (a query, `related=` a video, or nothing for
the sources and topics) or with `sqlite3` against those two tables.

**`export-data.py` and `export-vectors.py` in the you2idea repo read the old FalkorDB
graph and have not been ported.** The graph and its embeddings are deleted; the export
needs rewriting against `search.db` (and `vectors.bin` has no source any more).

## Export Output Files

| File | Size | Content |
|------|------|---------|
| `all-videos.json` | ~680KB | All videos with chapters (search index) |
| `videos.json` | ~33KB | Channels + recent + stats (UI data) |
| `vectors.bin` | ~16MB | Float32 embeddings (N × 384) |
| `chunks-meta.json` | ~5MB | Chunk text + video metadata |
| `graph.json` | ~200KB | Channels, tags, edges, related videos |
| `vtt/*.vtt` | ~150MB total | Raw VTT subtitles (727 files) |
