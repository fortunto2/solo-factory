---
name: solo-kaggle-gpu
description: Run GPU or TPU work for free on Kaggle from the terminal — push a local folder as a private kernel on 2x T4, P100 or TPU v5e-8, wait, pull the outputs back. Use when user says "обучи модель", "нужен GPU", "посчитать на видеокарте", "бесплатный GPU", "train a model", "fine-tune", "CUDA kernel", "run it on kaggle", "колаб", or a job is GPU-shaped and the Mac has no CUDA or is too slow. Do NOT use for CPU-bound jobs or private data (keep both local), or for exporting trained weights to devices (use /model-shrink).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🎮"
---

# kaggle-gpu — free NVIDIA and TPU time, one command per run

Kaggle gives every phone-verified account about 30 GPU hours a week (two T4s or one
P100) plus TPU time, and its CLI can push a script, run it headless and download what it
wrote. That makes it the default for anything that needs CUDA and fits in 12 hours:
training and fine-tuning, a custom CUDA kernel, batch inference, embeddings over a corpus.
Colab's free tier has no headless run from a CLI, so it is for hand-driven notebooks only.

## When it pays, and when it does not

| Job | Kaggle? | Why |
|---|---|---|
| Train or fine-tune a model, batch inference, embeddings | yes | 2x T4 (15 GB each), PyTorch/JAX in the image |
| Custom CUDA kernel | yes | `nvcc` 12.8 and `g++` 13.3 are there |
| CPU-bound job (C++ DP, search, compile farm) | **no** | 4 vCPU = 2 physical Xeon cores at 2.2 GHz; one Apple M5 core does the work of ~2.4 of them |
| Anything with personal, client or secret data | **no** | private kernels are still Google's machines |
| Over 12 h in one go | only with checkpoints | session cap; chain runs (below) |
| Speech-to-text on a Mac | no | local Apple GPU (/transcribe) is fast and keeps audio local |

Measured with `scripts/kaggle-run.sh` on 2026-10-29 (`run.sh` probe: `nproc`, cgroup quota,
`free`, `nvidia-smi`, a 10 s busy loop on every core):

| Runtime | CPU | RAM | Accelerator | Busy loop, all cores |
|---|---|---|---|---|
| CPU (`none`) | 4 vCPU Xeon 2.2 GHz, quota 4.0 | 31 GB | none | 115M (M5: 70M per core) |
| `NvidiaTeslaT4` | 4 vCPU Xeon 2.0 GHz | 31 GB | 2x Tesla T4, 15 GB each, CUDA 12.8 | 142M |
| `TpuV5E8` | first request sat in QUEUED for 20+ min | | | |

Reported, not measured here: ~30 GPU h/week (floats; the real number is on
kaggle.com/settings), 12 h sessions for CPU/GPU and 9 h for TPU, 20 GB in `/kaggle/working`.
Two GPU kernels at once drain the weekly quota twice as fast.

## One-time setup

```bash
uv tool install kaggle      # CLI 2.x
kaggle auth login           # opens the browser; token lands in ~/.kaggle/credentials.json
kaggle config view          # prints the username: login worked
```

GPU, TPU and internet inside a kernel need a phone-verified account (kaggle.com/settings).
Never paste a token into chat or a file in a repo: `auth login` stores it for you.

## Run

Put the job in a folder with `run.sh` as its entry point. It runs in `/kaggle/working`;
whatever it leaves there comes back.

```bash
S=${CLAUDE_PLUGIN_ROOT}/skills/kaggle-gpu/scripts/kaggle-run.sh
$S jobs/probe                    # CPU
$S jobs/train NvidiaTeslaT4      # 2x T4
$S jobs/train NvidiaTeslaT4 --dry  # build the kernel, push nothing
```

The script inlines every file of the folder (except `out/`) into one generated kernel
(cap 5 MB, `KAGGLE_INLINE_MAX`), pushes it as **private**, polls the status every 30 s,
downloads the output to `<folder>/out/<accel>/` with `run.log`, and exits non-zero if the
run failed. Kernel slug: `<KAGGLE_PREFIX:-run>-<folder>-<accel>`; pushing again makes a new
version of the same kernel.

| Env | Effect |
|---|---|
| `KAGGLE_INTERNET=1` | `pip install`, Hugging Face downloads |
| `KAGGLE_DATASETS=user/slug,...` | inputs too big to inline, mounted at `/kaggle/input/<slug>/` (create once: `kaggle datasets create -p dir`) |
| `KAGGLE_KERNELS=user/prev-slug` | an earlier run's output mounted read-only, to resume from its checkpoints |
| `KAGGLE_TIMEOUT=SECONDS` | cap the run |
| `KAGGLE_PREFIX=train-p2` | a distinct slug per leg of a chained run |

## Training longer than one session

1. `run.sh` saves a checkpoint to `/kaggle/working/ckpt/` every 30-60 minutes and on SIGTERM,
   and resumes from `/kaggle/input/<prev-slug>/ckpt/` when that exists.
2. Leg 1: `KAGGLE_PREFIX=train-p1 $S jobs/train NvidiaTeslaT4`.
3. Leg 2: `KAGGLE_PREFIX=train-p2 KAGGLE_KERNELS=<user>/train-p1-train-nvidiateslat4 $S jobs/train NvidiaTeslaT4`.

Use both T4s: `torchrun --nproc_per_node=2 train.py`, or split a CUDA job by device.
(Chaining through `kernel_sources` follows Kaggle's documented mount layout and has not been
exercised by this skill yet: check `ls /kaggle/input` in the first chained run.)

## Verify

- `run.log` ends the way `run.sh` meant it to, and the script printed `KernelWorkerStatus.COMPLETE`.
- First run on a new kind of job: put `nvidia-smi` and `python -c "import torch; print(torch.cuda.device_count())"` at the top of `run.sh`; a kernel pushed without the accelerator flag silently runs on CPU.
- Status by hand: `kaggle kernels status <user>/<slug>`; logs and files: `kaggle kernels output <user>/<slug> -p dir`.

## Gotchas

- TPU v5e-8 can sit in `QUEUED` for a long time; GPU runs started within a minute here.
- `kaggle kernels status` prints `KernelWorkerStatus.QUEUED|RUNNING|COMPLETE|ERROR`; the script matches the last word.
- Inlined files live in the kernel's source on Kaggle. Keep keys out; if a run truly needs one, use Kaggle Secrets (`kaggle_secrets.UserSecretsClient`), set in the web editor.
- Mining or other ToS-banned work gets the account blocked; ordinary research and training is what the quota is for.
