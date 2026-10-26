# Delivery — one master, a file per door

Render one archival master, then derive each platform file from it. Re-encode the picture only where
a door requires it. After every render, `ffprobe` duration, codec and audio length against the
master: a silently short file is a render defect, not "how it came out".

## Copy first, encode only what changed

Before any render, ask what actually changes in the picture. If nothing does (a full recording, a
trim, a muted line, loudness, an outro, chapters), copy the video stream and touch only the audio:

```bash
ffmpeg -i rec.MP4 -t 2086 -map 0:v:0 -map 0:a:0 -c:v copy \
  -af "volume=enable='between(t,1073.5,1077.6)':volume=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000" \
  -c:a aac -b:a 192k -movflags +faststart out.mp4
```

Then add the outro with the concat demuxer (below), also without re-encoding. `-map 0:v:0 -map 0:a:0`
drops the camera's extra data and thumbnail streams. Measured on 1080p talks read from an SD card,
both jobs running at once: the hardware HEVC re-encode with a 1440p upscale ran at 1.2x realtime (4x
alone) for a file 2.4x smaller; the stream copy ran at 4.4x realtime, limited by the card, not the CPU.
The upscale buys a better YouTube transcode tier, which a lecture from the back of a room does not need. Re-encode when the picture changes: a crop, a vertical cut,
burned captions, cuts mid-GOP that must be frame-exact, or a file too big for the upload link (copy
uploads more bytes: at 15 Mbit/s up, every extra 6 GB costs ~55 minutes, so on a slow link measure both).

Pipeline the steps: start uploading each file as soon as it is ready instead of after the whole batch.

## Recipes

**Upload master, HEVC on the Mac's hardware encoder** (36 min: 1.6 GB vs 3.2 GB for x264 crf 18):

```bash
ffmpeg -i film.mov -c:v hevc_videotoolbox -q:v 62 -tag:v hvc1 -pix_fmt yuv420p \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a aac -b:a 256k -movflags +faststart film.mp4
```

Elsewhere: `-c:v libx265 -crf 22 -tag:v hvc1`. `-tag:v hvc1` is what makes Apple players accept it.

**YouTube, 1440p from 1080p.** YouTube serves a 1080p upload at ~3.5 Mbps AVC; the 1440p tier is
encoded in VP9/AV1 with more bits. The upscale adds no detail, it buys a better transcode. Measured:
HEVC at 16 Mbps is 2.6x smaller than x264 crf 18 with no visible difference after YouTube's pass.

```bash
ffmpeg -i film.mp4 -vf "scale=2560:1440:flags=lanczos" \
  -c:v hevc_videotoolbox -b:v 16M -tag:v hvc1 -pix_fmt yuv420p \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a copy -movflags +faststart film.yt1440.mp4
```

Subtitles go up as `.srt` tracks per language, never burned: a long video has a track picker.

**Telegram and messengers: h264.** Some Android phones have no HEVC decoder, and a file there
downloads whole. 1080p at crf 21 fits ~40 minutes into the 2 GB limit.

```bash
ffmpeg -i film.mp4 -c:v libx264 -preset medium -crf 21 -pix_fmt yuv420p -c:a copy -movflags +faststart film.tg.mp4
```

**Vertical 9:16 from horizontal, blurred background** (whole picture, nothing lost, picture takes
~32% of the height; centred at 34% of the height because the platform UI covers the bottom):

```bash
ffmpeg -i film.mp4 -filter_complex "[0:v]split=2[bg][fg];\
[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=28[bgb];\
[fg]scale=1080:-2[fgs];[bgb][fgs]overlay=0:652-h/2,setsar=1,ass=film.ass" \
  -c:v libx264 -crf 20 -c:a copy -movflags +faststart film.reels.mp4
```

**Vertical crop** (`x` is a constant or an expression; for face following, feed it a smoothed x per
time from any face detector):

```bash
ffmpeg -i film.mp4 -vf "crop=w='min(iw,ih*1080/1920)':h=ih:x='(iw-ow)/2':y=0,scale=1080:1920,setsar=1" ...
```

Centre crop throws away 68% of the width. On a 20 s clip with the face off-centre, following kept 31
of 37 faces, the centre crop 5. Move the window slowly (≤ 2% of width per step, a quarter of the
remaining distance at most) and do not move it on frames with no face, or every street cutaway
inside a conversation drags it back to the centre. Native vertical phone clips go untouched.

**Burned subtitles** only for feeds (muted autoplay). The `ass` filter needs ffmpeg built with
libass, and **Homebrew's default `ffmpeg` is not** (checked 2026-10-25: the recipe above fails with
`No option name near 'film.ass'`). The same build also lacks `drawtext` (no freetype), so
labelled contact sheets fail too. Check with `ffmpeg -filters | grep -wE 'ass|drawtext'`; on a Mac use
`brew install ffmpeg-full` (`/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg`). Without subtitles, drop
`,ass=…` and the stock build works. Keep text above the bottom ~15% of the frame.

**Swap audio, keep the picture:** `ffmpeg -i film.mp4 -i new.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k out.mp4`.
Re-encoding video to change audio is a defect in the recipe.

**Outro card without re-encoding the film:** encode the card with the film's exact codec, size,
fps, pixel format, audio sample rate and channel count, then join with the concat demuxer and
stream copy. Compare first, the two lines must match:

```bash
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt,sample_rate,channels -of csv=p=0 film.mp4
```

A mismatch does not error, it lies: a 6 s film + 2 s card with 48 kHz audio against the film's
44.1 kHz came out 8.71 s long with stream copy and a clean decode; matched, 8.02 s.

```bash
printf "file '%s'\nfile '%s'\n" "$PWD/film.mp4" "$PWD/card.mp4" > list.txt
ffmpeg -f concat -safe 0 -i list.txt -c copy film.outro.mp4
```

Then decode a few seconds across the seam (`-ss <join-2> -t 4 -f null -`); if it errors, fall back
to the concat *filter* (a full re-encode) and say so. Better still: make the card the second input
of the concat filter in the same pass that encodes the platform file, zero extra generations.

## Around the file

- **Cover:** the best frame chosen by eye, a big title, and city/region as badges on the image
  (that is search on YouTube). Title = the search query + a concrete detail.
- **The real shooting date in every description.** A week in, nobody can tell the days apart.
- **Publish private, watch on a phone, then public.**
- YouTube "related video" links on Shorts: the API accepts the field and does not save it; set it in
  Studio by hand.
- **Archive after the films are out, never mid-edit.** Move sources and outputs to cloud storage
  together with the analysis sidecars, so a later trip film needs no re-analysis.
