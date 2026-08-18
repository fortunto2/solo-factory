---
name: solo-model-shrink
description: Take a trained neural model to devices — ONNX export, int8 quantization, Core ML conversion, on-device benchmarking, download-on-demand delivery. Use when user says "сожми модель", "quantize the model", "convert to Core ML / ONNX", "model is too big for the app", "run the model on iPhone/Android/web", or an ML feature needs to ship inside a mobile/web app. Do NOT use for training or fine-tuning models, or for LLM API integration (that's app plumbing, not model porting).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📦"
---

# model-shrink — ship a trained model to phones and browsers

A PyTorch checkpoint becomes: an eval, an ONNX int8 file (web/Android), a Core
ML package (Apple), an on-device number, and a download-on-demand delivery.
Every step below was paid for once; the order is the method.

## Workflow

1. **Eval before anything.** Ground truth + one scalar metric (F-measure,
   accuracy — whatever the task has) + a script that runs any model variant
   against it. Every later decision — quantize? fp16? distill? — is this
   script's output, never a guess. Keep 5–10 held-out samples as a smoke set.
2. **Export ONNX at a fixed shape** (`torch.onnx.export`, one export per batch
   size — see Gotchas). Verify against the original: max abs diff and the eval
   score. `onnxruntime` CPU is the portable baseline: web (`onnxruntime-web`
   WASM), Android (ORT mobile), desktop.
3. **Quantize weights to int8** (`onnxruntime.quantization` /
   `ct.optimize.coreml.linear_quantize_weights`). Weights-only int8 is usually
   free — measured twice on a 20M-param transformer: F 0.872→0.871 (ONNX) and
   0.864→0.863 (Core ML), 4x smaller. Re-run the eval anyway; "usually" is not
   "always".
4. **Apple: convert to native Core ML** (`coremltools`), never the ORT Core ML
   execution provider (see Don't). Conversion of transformer-ish models fails
   on Python-int shape math; the fixes that work:
   - Replace einops layers/`rearrange` with explicit `permute`/`reshape`.
   - Bake shapes as constants: capture `tuple(int(s) for s in x.shape)` on a
     module attribute during a warm eager pass, use those ints in `forward` —
     the trace then contains zero `aten::size`/`aten::Int` ops. Fixed export
     shape makes this sound.
   - Derive dims from weights (`linear.out_features`), not from tensors.
   - After EVERY replacement: run the model, assert max abs diff ≈ 0 vs the
     original. A stack of "obviously equivalent" rewrites drifts; a stack of
     asserted ones doesn't.
5. **Identify failing ops by graph census, not by reading code.** When the
   converter names a node (`blocks/0/partial/76`), dump `ts.inlined_graph`,
   filter nodes by scope and kind (`aten::Int`, `aten::size`,
   `prim::NumToTensor`), and match. The class you *think* is in the call path
   may be a similarly-named neighbour that is never called — a patch that
   changes nothing (diff 0.000e+00 because the code never ran) looks exactly
   like a patch that is perfectly equivalent.
6. **Benchmark on the target device**, with the model's native window size and
   deterministic non-zero input. Compare compute units (`cpuOnly`, GPU, ANE)
   per model — a rotary-attention transformer measured 2x FASTER on iPhone CPU
   than on the ANE, and the ANE's first load cost 43s of one-time compilation.
   Dev-machine numbers do not transfer; a busy dev machine's numbers don't
   even reproduce.
7. **Deliver as a download, not in the bundle.** Tens of MB belong in a
   FaceModelStore-style on-demand store: download → `MLModel.compileModel` →
   Application Support (excluded from backups) → validate by loading before
   declaring installed. An `.mlpackage` is a *directory*: host it as its files
   under one base URL (Manifest.json, Data/com.apple.CoreML/model.mlmodel,
   Data/com.apple.CoreML/weights/weight.bin) and pin that list with a test.
8. **Leave a bench door open**: a debug HTTP endpoint in the app that loads
   the installed model and times N predicts turns every future variant into a
   one-curl measurement on a real device over Wi-Fi.

## Gotchas

- **ONNX tracing bakes batch size and lies silently.** A model traced at
  batch 1 accepts `(4, N, D)` and returns garbage shaped like an answer (four
  sequences fused into one attention pass) — wrong result, not an error.
  One export per batch size, or stay at batch 1.
- **Version pairs are load-bearing**: coremltools supports a narrow torch
  range (e.g. torch 2.7.x + coremltools 9.0), and torchaudio must match torch
  to the minor or imports die with ABI errors. Pin the pair in a dedicated
  venv and write it in the doc.
- **Unsubstituted build variables pass URL parsing.** `$(MODEL_URL)` left in
  Info.plist is non-empty and `URL(string:)` accepts it — the download then
  fails at runtime with a nonsense error. Reject any value containing `$(`.
- **Batching probably doesn't help** on-device inference (measured 0.91–1.01x)
  and an unshuffled benchmark invents speedups from machine-load drift —
  interleave variants within each round.
- **fp16 conversion may fail where int8 succeeds** (Cast nodes in attention);
  int8 is smaller anyway. Don't fight fp16 for its own sake.

## Don't

- **Don't use ONNX Runtime's Core ML execution provider.** Measured: 11x
  slower than ORT CPU on the same model, plus a memory leak that grew to 41 GB
  over repeated runs. Native coremltools conversion of the same model ran 7x
  faster than ORT CPU. The EP's failure mode — graph split across
  unsupported ops, tensors ping-ponging between CPU and ANE — is structural.
- **Don't start with distillation.** A converted+quantized original at 20 MB
  delivered on demand ships today; a distilled student is weeks of teacher
  infrastructure. Distill only after conversion is proven impossible or the
  size budget is single-digit MB.
- **Don't tune performance from a laptop.** Simulators lack hardware codecs,
  ANEs differ per chip, and a loaded machine turns 14s into 29s with no code
  change. One number from the target device beats twenty from the Mac.
