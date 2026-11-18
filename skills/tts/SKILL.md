---
name: solo-tts
description: Generate speech locally on the Apple GPU — clone a voice from a 10-60 s clip, read a line or a whole voice-over script in 30-43 languages (English, Russian, Turkish, German, Spanish, French…), Russian with controllable stress, cleaned of model hiss; nothing is uploaded. Use when user says "озвучь", "сгенерируй голос", "клонируй голос", "сделай озвучку", "голос для ролика", "text to speech", "voice-over", "clone my voice", "TTS", or a video, reel or demo needs narration in someone's voice. Do NOT use for transcripts or subtitles from a recording (use /transcribe) or for pulling a voice out of a mixed track (use /stem-split).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🗣️"
---

# tts — local text to speech with voice cloning, GPU first

One reference clip + text becomes a `.wav`/`.mp3` in that voice. Weights download once to the
Hugging Face cache; text and voice never leave the machine. The counterpart of `/transcribe`, which
is also how to check the result (read the clip back and compare with the script).

## Pick the model

| Model (`--model`) | Size, peak RAM | Speed (M5, idle) | Use it for |
|---|---|---|---|
| `voxcpm2` (default), mlx-community/VoxCPM2-4bit | 2.3 GB, 5.2-5.9 GB | RTF 0.56-0.75 | Best clones: clean in English, Turkish and Russian from both a 27 s mic test and a 25 s phone clip; 48 kHz; 30 languages |
| `zonos3`, mlx-community/ZONOS3-Mini | 1.4 GB, 2.6-3.8 GB | RTF 0.17-0.29 | Fast drafts, 43 languages, reference in the same language. Output is band-limited to ~8 kHz, and it copies the pauses of its reference |
| `shtorm-ru`, Shtorm-VoxCPM2-RU (built once) | 2.3 GB, 5.5 GB | same as voxcpm2 | Russian where stress matters: `зам+ок` / `з+амок`, `м+ука` / `мук+и` |

Apache-2.0 all three. RTF = seconds of compute per second of speech; with other ML jobs on the
machine it rose to 1.2-1.9 and once to 6 (swap). Under 32 GB, run one model at a time.

```bash
S=${CLAUDE_PLUGIN_ROOT}/skills/tts/scripts
uv run $S/tts_mlx.py --ref me.wav --text "Hi, welcome back to the channel." -o hi.wav
uv run $S/tts_mlx.py --ref me.wav --file script.txt -o voiceover.mp3     # by sentence, one file
uv run $S/tts_mlx.py --ref me.wav --samples en,ru,tr,de -o compare.mp3   # one voice, several languages
uv run $S/tts_mlx.py --model zonos3 --lang tr --ref me.wav --text "Merhaba!" -o tr.wav
uv run $S/tts_mlx.py --describe "calm, deep male voice" --text "No reference needed." -o v.wav
uv run $S/convert_shtorm_ru.py                                           # once, for shtorm-ru
uv run $S/tts_mlx.py --model shtorm-ru --ref me.wav --text "Он откр+ыл зам+ок." -o ru.wav
uv run $S/denoise.py ref.m4a                                             # clean a reference first
```

PEP 723 headers carry the dependencies, so `uv run` needs no venv. `--file` splits on sentences
(blank line = new chunk), speaks every chunk with the same seed and reference, and joins them with
0.3 s gaps. A built-in guard stops the process below 15% free memory (`--min-free`).

## The reference clip decides the result

- **10-60 s of one speaker, continuous speech, no music.** Language does not have to match: an
  English clip gave clean Russian and Turkish.
- **Its room and its pauses come along.** Every clone copied the reference's noise floor (a phone
  clip at -52 dB gave clones at -50 dB; after `denoise.py`, -77 dB and -58...-63 dB). ZONOS3 copied
  a halting mic test's pauses: speech twice as slow, and its Russian line came out as noise until
  the silence was cut. VoxCPM2 read the same clip normally.
- **Steady tones in the clip survive cleaning.** Lines at 2.7/3.5/5.3 kHz appeared in clones from
  both models, so they came from the microphone; only a better recording removes them.
- Record one on a Mac: `ffmpeg -f avfoundation -i ":0" -t 50 -ac 1 -ar 48000 ref.wav`
  (`ffmpeg -f avfoundation -list_devices true -i ""` lists the inputs).

## Gotchas

- **Never join clips with an ffmpeg `anullsrc` gap + `concat`.** lavfi hands anullsrc in as
  `pcm_u8`, concat negotiates the whole graph down to it, and the output is 8-bit: 170 sample levels
  in 10 s, a -46 dB hiss over clips that were -71 dB. It sounded like a noisy model. Join in numpy
  and encode once (the script does), or force `aformat=sample_fmts=fltp` on every branch.
- **VoxCPM2 hisses on its own**: a flat band from 16 to 20 kHz and a bed between words that the
  reference does not have. The default clean-up (13-15 kHz cosine low-pass, then DeepFilterNet 3,
  ~2 s per clip) removes both; `--raw` skips it.
- **ZONOS3 garbles lines whose language differs from the reference.** With a Turkish clip,
  "Hello there." came out as "Ah, yeah. Ee Ee Ee…" and "Hello there, it is nice to meet you" as
  "You, well, dear, it's nice…"; the same lines from an English clip, and from VoxCPM2 with the
  Turkish clip, were right. Give ZONOS3 a same-language reference and read its output back.
- **More diffusion steps or a bigger quant are not the hiss fix**: in the 4-bit build only the
  language models are quantized, the AudioVAE decoder is full precision.
- **Russian without stress marks guesses, and can mishear itself.** Base VoxCPM2 read
  «и с парой» as «из пары» in both voices; the stress-mark model with marks read it right. Marking
  rules (model card): `+` before the stressed vowel, nothing on one-syllable words, nothing on `ё`,
  numbers and dates spelled out. Unmarked text reads like plain VoxCPM2. An automatic marker
  (RUAccent) exists; this skill does not drive it yet.
- **Whisper cannot check stress**: it writes «замок» either way. A read-back proves the words, not
  the accent; ears do.
- **`hf download` can stall** (xet, a few hundred KB then nothing). Plain HTTP with byte ranges
  works; through a VPN one connection gave ~1 MB/s and eight gave 6.5 MB/s.

## Check the result

```bash
uv run ${CLAUDE_PLUGIN_ROOT}/skills/transcribe/scripts/transcribe_mlx.py out.wav --languages ru
ffmpeg -i out.wav -lavfi showspectrumpic=s=1400x360:legend=1:scale=log spec.png   # look at the pauses
```

Words read back almost verbatim are the bar; on the spectrogram the gaps between words should be
dark and nothing should sit flat above 16 kHz. Read back one language per file: on a joined
`--samples en,ru,tr` file the 1 s gaps were too short for transcribe's chunking, and the English
part vanished from the transcript although it was in the audio.

## Consent

Clone only a voice whose owner agreed, and only for what they agreed to: consent for an assistant
is not consent for public videos. Keep other people's reference clips local; never send them to a
shared cloud GPU (Kaggle, Colab) to save time.

## Not covered yet

mlx-audio 0.6.6 ships ~40 other TTS models (Kokoro, Qwen3-TTS, Chatterbox, Fish, Pocket TTS,
OmniVoice, Higgs Audio…); `--model <repo id>` loads them, untested here. Real-time speech-to-speech
(Haru-4B, Moshi) needs 10+ GB and froze a 32 GB laptop: run those on a cloud GPU.
