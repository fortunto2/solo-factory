---
name: solo-video-edit
description: Edit real footage into a film with the agent as the editor — read the day's speech as text, write the cut as a script, lay cutaways that match the words, score it, strip other people's music, and render masters for YouTube, Reels and messengers with ffmpeg. Use when user says "смонтируй", "сделай ролик из этих видео", "трейлер дня", "влог", "cut this footage", "edit my trip videos", "make a film from these clips", or drops a folder of clips expecting a film. Do NOT use for planning a product promo from scratch (use /video-promo) or for uploading and channel analytics (use /youtube-channel).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.4"
  openclaw:
    emoji: "🎬"
---

# video-edit — footage to a film, the agent as editor

A folder of clips becomes a trailer, a longer episode, or a film of a whole trip. The tools do the
boring part (shots, quality, beats, speech); the agent picks the story; the person judges. Every
rule below was paid for by a cut someone called boring or broken. If the project has its own
editing skill, that one holds the commands; this one holds the rules.

## Workflow

1. **Analyse once, store beside the sources.** Shots, frame quality, beats, speech with word
   timings. Write the results as sidecar files next to each clip (`clip.mp4` → `clip.analysis.json`),
   so a month later a long film needs no re-analysis. Take shooting time from container metadata
   (`ffprobe -show_entries format_tags=creation_time`), never from file names: camera clocks drift.
   Tools: any shot detector + whisper-family STT; `npm i life2film-engine` (WASM) covers beats,
   shots and frame scores on-device.
2. **The day as one text file.** All speech in shooting order, numbered by clip and sentence. Read
   it like a scriptwriter and propose the story before touching a timeline.
3. **Write the cut as a script, not a timeline.** A small JSON: which sentences of which clip are
   said, which shot covers which line, which silent walks keep their own sound, what the cold open
   is. Render from it. A complaint ("X is mentioned, never shown") becomes a one-line edit.
4. **Voice as one continuous track, pictures on top.** Cut the audio from the same pieces as the
   picture, quantised to frames; check that film length equals voice length (drift > 1 frame = bug).
5. **Look before you render, every time** (see Eyes below), then render, then check with `ffprobe`
   that duration, codec and audio length match the plan.
6. **Masters per platform** from one archival master (`references/delivery.md`). Publish private, watch on a
   phone, then public.

## Editorial rules

- **The cutaway shows what is being said, from the same place and time** (within minutes of the
  line), never from a scene the story has not reached or has left.
- **Never cover a shot where lips move.** It reads as broken sync. Cutaways go into silent windows.
- **A mentioned object must be seen**, ideally just before the line about it.
- **Cold open, then hook.** 8–10 s of the best frames, then one line with a twist. The hook is
  **hand-picked from a contact sheet**: automatic ranking picks sharp and colourful (an empty path
  through trees), which is what people scroll past. Fire, water, neon, night, motion toward the
  camera, a face with an expression, the film's object.
- **Scenes, not best phrases.** A conversation goes in whole: lead-in, the talk, the reaction. A
  "best line" without its lead-in confuses anyone who did not see what was cut.
- **Find promise → payoff pairs** in the transcripts ("tomorrow we'll buy…" → the purchase) and
  keep both halves; they are the thread of a multi-day film.
- **Trim filler words at the ends of a line**; mid-line only when the join lands in silence.
- **Take something from every clip.** The person filmed it, so it mattered. After the cut, list the
  clips that did not make it, each with a reason.
- **Live music in frame is one continuous span** with picture cuts on top. Cut per shot and the beat
  restarts at every cut.
- **Length follows the material.** Cut stammers and repeats, not thoughts. Don't stretch to a target.

## Eyes — numbers miss what a glance catches

- **Read the whole film as text** in order before rendering: does each line make sense to someone
  who did not see the cut material?
- **A sheet of every cutaway with its line under it.** Measured once: 12 of 54 automatic cutaways
  were off topic (a frame upside down, a car over a line about a garage).
- **A storyboard grid, one frame per shot.** Catches "same face ten times" that every metric passed.
- **A critic subagent, two passes minimum.** Pass one finds repeats and sagging scenes, pass two the
  lines cut mid-word at joins.

## Sound

Score written to the cut, a hole in it (not ducking) wherever something plays live, live music as
one continuous span, other people's music stripped with Demucs before upload, chapters levelled to
−16 LUFS. Rules, numbers and commands: `references/sound.md`.

## Delivery

One archival master, a file per door: HEVC for upload (36 min = 1.6 GB vs 3.2 GB x264), YouTube in
1440p even from 1080p, h264 for messengers, native vertical untouched or a face-following 9:16
window with burned subtitles for feeds. ffmpeg recipes, the outro card without re-encoding, cover and
archive rules: `references/delivery.md`.

## Gotchas

- Analysis written into a symlinked subset folder ends up beside the links, not the originals —
  resolve symlinks before writing sidecars.
- Never leave a rendered film inside the source folder: the next run treats it as one more clip.
- STT turns unknown names into celebrities. Keep a per-trip glossary and fix transcripts once.
- A long trip film is cut from the finished day films (colour, sync, subtitles already fixed), one
  file per chapter cached by its inputs, so a critic note re-renders one chapter, not an hour.
- Put the real shooting date in every description; a week in, nobody can tell the days apart.
- Archive sources to cloud storage **after** the films are out, never mid-edit, with the sidecars.

## Don't

- Don't trust an automatic hook, cover frame or cutaway list without looking at it.
- Don't re-encode video to change audio, trim, mute or add an outro: copy the stream (`references/delivery.md`, "Copy first").
- Don't crop horizontal footage blindly to 9:16.
- Don't chop live music per shot, or duck the score under it.
- Don't render before reading the cut as text.
