# Review: the agent is the vision model

Upstream's own review rules are in Chinese (`skills/rea-video/references/review.md` in the repo); this is
what applies when no vision-model key is configured, as run.

## Commands

```bash
rea-video review "$O"        # 0.1 s; writes $O/review_tasks.json and $O/review_answers.json
```

`review_tasks.json` has `instructions`, per shot an `images.sheet` (key frames of the shot, enough on its
own), `tool` (its verdict, runner-up, evidence), `priority` (high = low confidence, close runner-up) and a
`zoom_cmd` to zoom a time range (`rea-video tiles ref.mp4 --start S --end E --every 0.1 -o check.jpg`).

## Fill per shot in review_answers.json

| Field | Value |
|---|---|
| `label_probs` | probabilities over live_action, ai_video, avatar, cg_3d, code_render, screen_capture, still_motion, static_hold, anim_2d, stop_motion, film_footage; sum 1; leave `{}` for a shot you did not look at |
| `image_source` | one of `ai_image`, `photo`, `graphic`, `screenshot`, `unknown` |
| `evidence` | what you actually see (noise, hands, text, physics); not what the tool said |
| `description` | one line, different per shot |
| `narrative` | `role` (hook, context, proof, turn, conclusion, call to action, mood) and `point` |
| `performance`, `aspects`, `embedded_assets`, top-level `cast`, `story` | when a person acts, for light and camera, for real assets, for the character sheet |

Then `rea-video apply-review "$O" --by agent --lang en` prints which shots changed label.

## Rules that held

- Look at the frames before the verdict. Style alone decides nothing: a cartoon look is AI or Blender.
- Hard evidence beats looks: AIGC tags in metadata, 24 to 30 fps duplicate-frame cadence.
- Missing metadata is not proof of "not AI": platforms strip it.
- Old, low-resolution or re-encoded footage reads as "3D / flat colour" to the pixel statistics. A real
  person, natural hand motion and optical blur overrule it.
- A single continuous real-looking or handmade clip with no AIGC tag and no repeated frames is often called
  AI by the tools: with no clear AI artefact (warped hands, boiling texture, garbled text), keep confidence
  at 0.7 or lower and list evidence both ways.
- If you cannot read images at all, do not overrule the tool: list its low-confidence shots as open
  questions and write "no vision model, picture not viewed" in the verdict.
