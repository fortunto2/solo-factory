#!/bin/bash
# Run a local folder on Kaggle as a private script kernel and fetch what it leaves behind.
#
#   kaggle-run.sh DIR [ACCEL] [--dry]
#     ACCEL: none (CPU, default) | NvidiaTeslaT4 (2x T4) | NvidiaTeslaP100 | TpuV5E8 | TpuV6E8
#
# DIR holds run.sh (entry point, cwd /kaggle/working) and the small files it needs. They are
# inlined into one generated kernel, so there is no upload step. Bigger inputs go in a Kaggle
# dataset (KAGGLE_DATASETS) or the output of an earlier kernel (KAGGLE_KERNELS), both mounted
# read-only under /kaggle/input/<slug>/.
# Output: DIR/out/<accel>/ = /kaggle/working after the run, plus run.log. --dry builds only.
#
# Env: KAGGLE_PREFIX=run          kernel slug = <prefix>-<dir name>-<accel>
#      KAGGLE_INTERNET=0|1        pip installs, model downloads (phone-verified account)
#      KAGGLE_DATASETS=a/b,c/d    dataset_sources
#      KAGGLE_KERNELS=me/prev     kernel_sources: resume from an earlier run's checkpoints
#      KAGGLE_TIMEOUT=SECONDS     cap the run
#      KAGGLE_INLINE_MAX=5000000  refuse to inline more bytes than this
#      KAGGLE_BUILD=DIR           where the kernel is generated (default: DIR/out/.kernel)
# Login once: uv tool install kaggle && kaggle auth login (browser).

set -euo pipefail
DRY=""; ARGS=()
for a in "$@"; do if [ "$a" = --dry ]; then DRY=--dry; else ARGS+=("$a"); fi; done
DIR="$(cd "${ARGS[0]:?usage: kaggle-run.sh DIR [ACCEL] [--dry]}" && pwd)"
ACCEL="${ARGS[1]:-none}"
NAME="$(basename "$DIR" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9-]/-/g')"
TAG="$(echo "$ACCEL" | tr 'A-Z' 'a-z')"
SLUG="${KAGGLE_PREFIX:-run}-$NAME-$TAG"
BUILD="${KAGGLE_BUILD:-$DIR/out/.kernel}/$SLUG"
OUT="$DIR/out/$TAG"
[ -f "$DIR/run.sh" ] || { echo "no run.sh in $DIR" >&2; exit 2; }

if [ "$DRY" = --dry ]; then KUSER="${KAGGLE_USER:-you}"
else KUSER="$(kaggle config view 2>/dev/null | awk -F': *' '/username/ {print $2; exit}')"; fi
[ -n "$KUSER" ] && [ "$KUSER" != None ] || { echo "not logged in: kaggle auth login" >&2; exit 2; }

rm -f "$BUILD"/kernel.py "$BUILD"/kernel-metadata.json
mkdir -p "$BUILD" "$OUT"
python3 - "$DIR" "$BUILD" "$KUSER/$SLUG" "$SLUG" "$ACCEL" <<'EOF'
import base64, json, os, pathlib, sys
src, build, kid, title, accel = sys.argv[1:]
src, build = pathlib.Path(src), pathlib.Path(build)
paths = [p for p in sorted(src.rglob("*"))
         if p.is_file() and "out" not in p.relative_to(src).parts]
size = sum(p.stat().st_size for p in paths)
limit = int(os.environ.get("KAGGLE_INLINE_MAX", 5_000_000))
if size > limit:
    sys.exit(f"{size} bytes to inline > {limit}: put the data in a dataset (KAGGLE_DATASETS)")
files = {str(p.relative_to(src)): base64.b64encode(p.read_bytes()).decode() for p in paths}
(build / "kernel.py").write_text(f'''import base64, os, pathlib, subprocess, sys
FILES = {json.dumps(files)}
os.chdir("/kaggle/working")
for name, data in FILES.items():
    p = pathlib.Path(name); p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(base64.b64decode(data))
with open("run.log", "wb") as log:
    rc = subprocess.call("set -o pipefail; bash run.sh 2>&1 | tee /dev/stderr",
                         shell=True, executable="/bin/bash", stdout=log)
for name in FILES:  # keep only what run.sh produced
    pathlib.Path(name).unlink(missing_ok=True)
sys.exit(rc)
''')
split = lambda v: [s for s in os.environ.get(v, "").split(",") if s]
json.dump({"id": kid, "title": title, "code_file": "kernel.py", "language": "python",
           "kernel_type": "script", "is_private": True,
           "enable_gpu": accel.startswith("Nvidia"), "enable_tpu": accel.startswith("Tpu"),
           "enable_internet": os.environ.get("KAGGLE_INTERNET") == "1",
           "dataset_sources": split("KAGGLE_DATASETS"), "competition_sources": [],
           "kernel_sources": split("KAGGLE_KERNELS")},
          open(build / "kernel-metadata.json", "w"), indent=1)
print(f"built {build}/kernel.py: {len(files)} files, {size} bytes inlined")
EOF
[ "$DRY" = --dry ] && exit 0

push=(kaggle kernels push -p "$BUILD")
[ "$ACCEL" = none ] || push+=(--accelerator "$ACCEL")
[ -z "${KAGGLE_TIMEOUT:-}" ] || push+=(-t "$KAGGLE_TIMEOUT")
"${push[@]}"

rc=0
while :; do
  st="$(kaggle kernels status "$KUSER/$SLUG" 2>&1 | tail -1)"
  case "$(echo "$st" | tr 'A-Z' 'a-z')" in
    *complete*) break ;;
    *error*|*cancel*) echo "$st" >&2; rc=1; break ;;
  esac
  sleep 30
done
kaggle kernels output "$KUSER/$SLUG" -p "$OUT" -o -q
echo "$st"
echo "output: $OUT"
ls "$OUT"
exit "$rc"
