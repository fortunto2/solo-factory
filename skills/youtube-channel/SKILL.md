---
name: solo-youtube-channel
description: Run a solo founder's YouTube channel from the terminal — upload through the YouTube Data API, subtitles as tracks, thumbnails, publish, bulk hide, link Shorts to the long video, and read the YouTube Analytics API into conclusions. Use when user says "upload to YouTube", "publish the video", "make shorts and post them", "hide these videos", "channel analytics", "what works on my channel", "is the API quota reset", or hands a finished mp4 for a channel. Do NOT use for planning a promo video script (use /video-promo) or for text posts (use /content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📺"
---

# youtube-channel — publish and measure a channel from the CLI

General principles for running a YouTube channel with an agent: what to check
before an upload, how the API behaves, how Shorts and long videos feed each
other, and how to turn analytics into decisions. Learned on a real channel
over a month of daily uploads; every rule below cost a mistake first.

## Workflow

1. **Auth once.** Google Cloud project → enable *YouTube Data API v3* and
   *YouTube Analytics API* → OAuth client (Desktop app) → token with scopes
   `youtube.upload`, `youtube`, `youtube.force-ssl` (the last one is needed for
   caption tracks). The `youtube` scope is enough for Analytics reports.
   `gcloud services enable youtubeanalytics.googleapis.com --project <id>`.
2. **Gate the file before the first byte** (cheap checks first, upload last):
   title ≤ 100 chars, description file exists, thumbnail extracted, playlist
   resolved, caption files parse, branded outro present if the channel uses
   one, third-party music checked for Content ID.
3. **Upload private → look → publish.** Unverified API projects force uploads
   to private anyway; a `videos.update` of `status.privacyStatus` opens it.
4. **Link** the Short and the long video both ways (see below).
5. **Measure** after ~48 h with the Analytics API, not by eye.

## The API, measured

- **Quota:** 10,000 units/day, reset at **midnight Pacific**. `videos.insert`
  1600, `captions.insert` ~400, thumbnail/playlist/update ~50. That is 5–6
  uploads a day in practice — plan a batch of Shorts against it and push the
  rest to tomorrow instead of failing mid-batch.
- **Testing-mode OAuth apps expire refresh tokens in 7 days** (`invalid_grant`).
  Re-run the browser auth, or move the app to production.
- **`relatedVideoId` ("Related video" on a Short) is accepted with 200 and not
  saved.** Set it by hand in Studio. A success code is not a write.
- **A title over 100 characters is `invalidTitle`** and creates nothing.
- **Analytics lags ~2 days** for day-level data. For a video published today,
  read `statistics.viewCount` from the Data API instead.
- To hide in bulk: set `privacyStatus` to `unlisted` (gone from the channel and
  the feed, links still work, reversible). Prefer it over delete.

## Subtitles and language

- Long videos: captions as **tracks** (`.srt` per language), never burned —
  viewers pick a language and search indexes the words.
- Shorts: captions **burned in** — nobody turns on a track in the feed. Two
  languages if the audience is split: big 1–2-word captions centred, the
  translation as a smaller line below.
- Title in the language of the audience the video is *for*, not the one the
  creator speaks.

## Shorts that get watched

- One concrete thing + a number or a surprise, 25–40 s, a hook line on top
  for the whole duration.
- **Close framing beats everything.** A lecture filmed from the back of the
  room (two small figures) got 8–49 views with a 6–8 s average view; the same
  channel's close-framed Shorts got 1,000–1,800. The feed decides in the first
  second.
- If the camera pans inside the clip, a fixed crop misses — use the full frame
  scaled to width.
- Speech-to-text splits numbers into tokens ("1" ".4", "308" ",000"); glue them
  before rendering word captions.
- End every Short with the brand outro and a link to the long video in the
  description.

## Shorts → long video

Shorts bring reach; long videos bring subscribers. On the measured channel,
Shorts were 88% of views but gave 6 of 25 new subscribers, and ~1.5% of Shorts
views reached another video on the channel. So every time:

1. Link to the long video in the Short's description.
2. A "Shorts from this video" block with links in the long video's description.
3. "Related video" on the Short — by hand in Studio.
4. Long videos of the same event link to each other.

## Reading analytics into decisions

Pull with `youtubeAnalytics.reports.query(ids='channel==MINE', …)`:
totals; `creatorContentType` (shorts vs videoOnDemand); `insightTrafficSourceType`;
`country`; `ageGroup,gender`; per `video` with `averageViewDuration`,
`averageViewPercentage`, `subscribersGained`; per `day` to see bursts.

Report in this order: numbers (views, watch hours, subscribers, shares by
type) → what works and what does not, named videos with their numbers → 3–4
actions. Look for: which *series* produced the bursts, which videos have a low
average view (the hook or the framing failed), which long videos converted to
subscribers. Say "probably" where the data does not show a cause.

## Gotchas

- A Short that lists 0 views an hour after publish is normal; judge at 48 h.

## Don't

- Don't delete a weak video — unlist it; deletion loses the URL and the stats.
- Don't publish a full-day archive publicly; it dilutes the channel's
  retention. Keep it unlisted.
- Don't trust a 200 from the API as proof a field was saved — read it back.
