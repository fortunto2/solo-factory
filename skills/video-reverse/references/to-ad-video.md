# Breakdown to ad-video: remake a competitor ad for our product

The goal is an ad of our own with the competitor's structure, not a copy of the competitor's pictures.
`solo:ad-video` keeps the rules (product only from real footage or its 3D model; every cut on a beat; quality
gate). This file maps the breakdown onto it.

1. **Break down 2-3 ads that already run for a long time** (an ad that has run for months is one that works).
   Get the original files, not screen captures of a feed: re-encoding lowers the tools' accuracy.
2. **Shot list from the timeline.** `scripts/shotlist.py <out> --beats-bpm <bpm>` gives the table in ad-video's
   format. Fill Direction (section 3 of ad-video) and Caption yourself. Take the tempo from `video/sound.md`
   (BPM) when the original has music; otherwise pick one with whole frames per beat.
3. **Keep** from the original: the number of shots, their lengths, what the first second shows, where the
   caption changes (`video/packaging.md`, `packaging/overlays.ass` has timings), cut rhythm
   (`video/rhythm.md`), the story shape (`video/content.md`: hook, proof, call to action).
4. **Swap** the product, the place and the people. Per shot, by source label:
   - `real` in the original -> real footage of our product (`video/remake.md` lists the "real material" shots
     the original files were needed for; for us that is our own footage list, not theirs);
   - `render` -> our 3D model, front and top faces only in a close-up;
   - `generated` -> a generated shot with our product kept small, or pasted back per frame, per
     ad-video's Seedance reference.
5. **Do not take** their footage, music, voice, characters or lettering. The breakdown is a structure study.
6. **Gate.** Run ad-video's quality gate and critic on our cut, and compare the first-second frame with the
   original's by eye. New ads go live paused as an A/B arm against what runs.

If the breakdown's confidence on a shot is low (flag `low confidence`), look at its frame before planning
around its "made~" label: a wrong source label sends the remake down the wrong route (filmed, not render).
