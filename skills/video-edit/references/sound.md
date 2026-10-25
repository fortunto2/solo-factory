# Sound — the score, live music, other people's music

## A score written to the cut

- Chord changes land on the beat nearest a cut, not on a bar grid. Parts of a film may run at
  different tempos, with part boundaries on cuts too.
- Sidechain the score to the voice track so it steps back under speech by itself.
- **Mood is scale degrees, not tempo.** A "major" score came out sad at the right BPM because of its
  chords. Solitary walks: major sevenths, a minor sixth. Light family films: triads with an added
  sixth, no minor chord.
- Mix the score ~15 dB under the voice for talk films; "barely audible, and not everywhere".
- If someone plays in the footage, the harmony can be lifted from the recording (audio-to-MIDI) and
  fed to the score. On noisy street audio, expect the key and chords back, not the melody: three
  models agreed on the key and disagreed on the tune.

## Live music in the frame

- **One continuous span of the clip's audio under the whole scene**, picture cuts on top. Cut it per
  shot and the beat restarts at every cut.
- **A hole in the score, not ducking.** Inside the window the score sits at −91 dB, against −13.6 at
  full level. Ducking is audible; a hole is not. The same goes for a punchline that lives in a
  reaction, a knock, a laugh: silence in the score there.
- Live music the trip was for gets 20–30 s of its own, not one line of the MC.

## Other people's music — clean before upload

Car radio, shop speakers, festival stages: Content ID. Measured on one episode: 10 claims, ~4 min of
songs, four claims blocking the video in two countries (21% of that channel's audience). A claim is
not a strike, but you do not choose the block.

```bash
ffmpeg -i film.mp4 -vn -ac 2 -ar 44100 film_audio.wav
demucs -o stems -d mps film_audio.wav          # 4 stems, ~4 min per 20 min of audio (Apple Silicon)
```

Stems in detail, GPU flag and install: the `/stem-split` skill. Not installed: `uvx --python 3.11 demucs …` runs it without an install (checked 2026-10-25,
stems land in `stems/htdemucs/<name>/{vocals,drums,bass,other}.wav`).

1. **Detect music on drums + bass.** Demucs puts the engine, wind and city into `other`; radio has a
   rhythm section. A detector on the no-vocals stem was blind: road noise is louder than the music
   almost everywhere. Threshold the drums+bass RMS per second, merge windows closer than a few
   seconds, print the map (dry run) before changing anything.
2. **Inside the windows: the whole vocal stem + your score.** Do not gate the voice by subtitle
   windows: STT misses exclamations and emotion (31 s of loud speech lived outside the subtitles on
   one film). The singer's ghost stays 5–10 dB under the speaker and disappears under the score.
   Outside the windows, keep the original audio sample for sample.
3. **Rebuild audio only**, `-map 0:v -c:v copy`.
4. **The platform's claims are a check, not the map.** Content ID sees a subset; clean all the
   detector found, then confirm its windows cover the claimed time codes.

An already published video whose claim restricts nothing: leave it. Re-upload only for a block or
lost monetisation; a fresh private video is cheaper to rebuild than to fix with the platform's
"erase song", which takes days and cuts the whole segment, speech included. Where there is no
monetisation (an Instagram trailer), radio may stay.

## Levels

Level each chapter of a long film to −16 LUFS; unlevelled neighbours differed by 9 dB.

```bash
ffmpeg -i chapter.mp4 -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:v copy chapter.lv.mp4
```

For exact results run loudnorm twice (measure with `print_format=json`, then apply the measured
values).
