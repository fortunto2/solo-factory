// node beats.mjs song.mp3 > beats.json
// Needs: npm i life2film-engine, ffmpeg on PATH. Output (seconds):
// { bpm, confidence, pulse_strength, beats[], downbeats[], sections[{start,end,label,mean_energy}] }
import init, { detect_beats } from 'life2film-engine';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

const require = createRequire(import.meta.url);
await init({ module_or_path: readFileSync(require.resolve('life2film-engine/va_wasm_bg.wasm')) });

const SR = 22050;
const raw = execFileSync('ffmpeg', ['-v', 'error', '-i', process.argv[2], '-ac', '1', '-ar', String(SR), '-f', 'f32le', '-'], { maxBuffer: 1 << 30 });
const mono = new Float32Array(raw.buffer, raw.byteOffset, raw.byteLength / 4);
const { bpm, beats, confidence, pulse_strength, downbeats } = JSON.parse(detect_beats(mono, SR, null));
const dur = mono.length / SR;

// Sections: RMS per window of 4 downbeats (a phrase), normalised to the loudest phrase.
// energy >= 0.6 of the loudest = chorus, else verse. Adjacent phrases with the same label merge.
const marks = [0, ...(downbeats ?? []).filter((t) => t > 0.5)];
if (marks[marks.length - 1] < dur - 0.5) marks.push(dur);
const win = [];
for (let i = 0; i < marks.length - 1; i += 4) win.push([marks[i], marks[Math.min(i + 4, marks.length - 1)]]);
const rms = win.map(([a, b]) => {
  const s = Math.floor(a * SR), e = Math.min(Math.floor(b * SR), mono.length);
  let sum = 0;
  for (let i = s; i < e; i++) sum += mono[i] * mono[i];
  return Math.sqrt(sum / Math.max(1, e - s));
});
const max = Math.max(...rms, 1e-9);
const sections = [];
win.forEach(([a, b], i) => {
  const e = rms[i] / max;
  const label = e >= 0.6 ? 'chorus' : 'verse';
  const last = sections[sections.length - 1];
  if (last && last.label === label) { last.end = b; last.n++; last.sum += e; }
  else sections.push({ start: a, end: b, label, n: 1, sum: e });
});
for (const s of sections) { s.mean_energy = +(s.sum / s.n).toFixed(2); delete s.n; delete s.sum; }
console.log(JSON.stringify({ bpm, confidence, pulse_strength, beats, downbeats: downbeats ?? [], sections }));
