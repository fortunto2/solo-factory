# 04 · Live capture: talks, mentors, demos

- **When:** keynotes, panels, mentor rounds, and above all the finalist demos and Q&A.
- **Inputs:** a running supervox recording (`/supervox`), optionally a camera on the screen.
- **Output files:** the supervox session folder (stream, panel versions, frames), linked or copied
  into `docs/live/`; `docs/live/finalists.md` at the end.

## Listening

Use `/supervox`: the Monitor loop runs in the **main session** on the live jsonl, batches of about
40 seconds, the panel rewritten each time. Its "finalists / demo day" mode gives one block per team.
For a hackathon, keep each block in this shape:

```markdown
### 3. <name as heard> / <second hearing> (t=28:13) · <repo if known>
- Idea: one line, in the team's words where possible
- Stack: models, frameworks, hardware, as said
- Demo: what was shown working, what was a slide
- Claims: numbers with t= ("$300k per outage", t=34:57), all "as claimed"
- Judges' Q&A: question → answer, one line each
- Critique: the gap a judge would find (max 2)
```

What worked and what did not:

- **Team names come out mangled**, and finalists are usually read twice (announcement, then the
  pitch). Record both hearings; stage 05 resolves them against repos.
- **Placement beats the model.** A laptop mic in the audience picks up the neighbours, not the
  stage. Put the laptop next to a PA loudspeaker.
- **Private conversations never go into notes.** A mentor talk with the user becomes lessons and
  follow-ups, with no verbatim quotes. Public stage talk can be paraphrased.
- After the demos, add your ranking against the stated criteria, marked as yours, and a list of
  names to look up.

## Camera on the slides

Slide text is the best source for team names, repo QR codes and numbers. A laptop webcam from the
audience is too far away to read it.

- A **UVC camera with pan, tilt and zoom** (a gimbal camera in webcam mode works) zoomed about 4x
  on the screen reads slide text from the back half of a room.
- Control: on macOS a UVC control CLI (uvc-util or similar), on Linux `v4l2-ctl -c
  zoom_absolute=…,pan_absolute=…,tilt_absolute=…`. List the controls the camera exposes before
  scripting; names and ranges differ per device.
- **These cameras drop the stream and reset zoom about once a minute.** A long-running capture
  then films a wide shot of the room. What works: one fresh capture session per frame, and
  re-apply pan, tilt and zoom right before each frame.
- Keep the target in a small state file (`ptz.json`: device, pan, tilt, zoom) so the loop and the
  user re-aim the same way, and a frame index next to it.
- One frame every 10 seconds is enough for slides. Frames go into the session folder, named by
  time (`f_<HH-MM-SS>.jpg`) so they line up with `t=` in the transcript.

```bash
# macOS, one frame; device index from: ffmpeg -f avfoundation -list_devices true -i ""
ffmpeg -loglevel error -f avfoundation -framerate 30 -video_size 1920x1080 -i "<index>" \
  -frames:v 1 -y "frames/f_$(date +%H-%M-%S).jpg"
```

Look at the first frames yourself before trusting the loop: focus, exposure on a bright
projector, and whether the zoom actually stuck.

## `docs/live/finalists.md`

After the awards (or when the room empties): one row per team.

| # | Name as heard (both) | Track | Idea | Stack | Q&A in one line | Repo (stage 05) | Award |
|---|---|---|---|---|---|---|---|

Award says "not stated" unless it was announced while you listened or is on the event page.
