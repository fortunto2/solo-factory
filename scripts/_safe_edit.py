#!/usr/bin/env python3
"""Editing somebody's file in place, and putting it back even when killed.

Two tools here do it: `mutate` swaps one line of a subject, `witness` swaps a whole
implementation AND rewrites the test file. Both restore in `finally`, which covers
exceptions and Ctrl-C and covers neither SIGTERM nor SIGKILL. Measured on both — a
timeout mid-run left `if True:  # mutant` in one and a single-assertion witness in
the other, silently. A command timeout, a cancelled CI job and a closed terminal are
all SIGTERM, and these tools are by definition pointed at the file somebody is
editing.

One implementation, not two. The crumb format and its three-outcome recovery were
specified by @nadir-codex (#26761) after @kolpaq (#26742) found that the crumb
protecting the subject was not itself protected; a second copy of that would be the
two-places-disagreeing defect this repository has spent a week on.
"""

from __future__ import annotations

import hashlib
import os
import signal
import sys
from contextlib import contextmanager
from pathlib import Path

CRUMB_V = "solo-mutate-crumb v1"


def write_crumb(crumb: Path, target: Path, original: str) -> None:
    """Write the crumb atomically: temp, fsync, rename. Never truncate in place.

    *Named* by @kolpaq (#26742): the crumb protects the subject, and nothing was
    protecting the crumb. A SIGKILL landing mid-write leaves a file that EXISTS and
    is short, and the recovery instruction this tool prints — `mv crumb target` —
    would then install a truncated original over a working file. The fix is the
    protection applied one level down: write elsewhere, and let rename be the only
    step that commits.

    The header carries what @nadir-codex (#26761) specified: a version, the target
    it belongs to, the payload length and its digest. Recovery that cannot check
    those has no way to tell a complete record from half of one.
    """
    payload = original.encode("utf-8")
    header = (
        f"{CRUMB_V} {target.name} {hashlib.sha256(payload).hexdigest()} "
        f"{len(payload)}\n"
    ).encode()
    tmp = crumb.with_suffix(crumb.suffix + ".tmp")
    with open(tmp, "wb") as fh:
        fh.write(header + payload)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, crumb)
    # SURVIVING MUTANT, named rather than hidden: removing the fsync above kills no
    # test. It guards a power loss — bytes acknowledged by the OS but not on the
    # platter — and that is not observable from userspace without pulling the plug.
    # The kill-a-process probes cannot see it, and no test here claims to.
    #
    # The rename is durable only once the DIRECTORY entry is. Skipped where the
    # platform will not let us open a directory, which is stated rather than assumed.
    try:
        dfd = os.open(crumb.parent, os.O_RDONLY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except OSError:
        pass


def read_crumb(crumb: Path, target: Path) -> tuple[str | None, str]:
    """(original, state). state is `absent`, `valid`, or a reason it is CORRUPT.

    Three outcomes, never two. *Named* by @nadir-codex (#26761): a partial record
    treated as "no crumb" turns a crash into a silent skip of recovery, at exactly
    the moment recovery is the only thing left.
    """
    if not crumb.is_file():
        return None, "absent"
    raw = crumb.read_bytes()
    head, sep, payload = raw.partition(b"\n")
    if not sep:
        return None, "the record has no header line — it was cut before the newline"
    parts = head.decode("utf-8", "replace").split()
    if len(parts) != 5 or " ".join(parts[:2]) != CRUMB_V:
        return None, f"unrecognised header {head[:60]!r}"
    _, _, name, digest, length = parts
    if name != target.name:
        return None, f"the record belongs to {name}, not {target.name}"
    if not length.isdigit() or int(length) != len(payload):
        return None, (
            f"the record claims {length} payload bytes and holds {len(payload)} — "
            f"it was cut mid-write"
        )
    if hashlib.sha256(payload).hexdigest() != digest:
        return None, "the payload does not match its digest"
    return payload.decode("utf-8"), "valid"


@contextmanager
def protect(paths: list[Path], label: str = "run"):
    """Guard every file in `paths` for the duration of the block.

    Crumbs are written before the first edit and removed only after every file is
    verifiably back. SIGTERM and SIGINT restore and exit 130; SIGKILL cannot be
    caught, and for that the crumbs are the whole defence — a later run reads them
    and refuses.

    Yields nothing: the caller edits the files as before. What changes is what is
    left behind when the process does not reach the end of the block.
    """
    originals = {p: p.read_text() for p in paths}
    crumbs = {p: crumb_for(p) for p in paths}

    def restore_all() -> bool:
        ok = True
        for p, text in originals.items():
            try:
                p.write_text(text)
                ok = ok and p.read_text() == text
            except OSError:
                ok = False
        return ok

    def on_signal(signum, _frame):
        done = restore_all()
        if done:
            for c in crumbs.values():
                c.unlink(missing_ok=True)
        print(
            f"\n  interrupted by signal {signum} — "
            + ("restored" if done else "RESTORE FAILED, see the .mutate-original files")
            + f" ({label})",
            file=sys.stderr,
        )
        raise SystemExit(130)

    previous = [
        (s, signal.signal(s, on_signal)) for s in (signal.SIGTERM, signal.SIGINT)
    ]
    for p in paths:
        write_crumb(crumbs[p], p, originals[p])
    try:
        yield
    finally:
        # No `return` here — a return in finally swallows the exception that brought
        # us here and reports a restore failure as the cause.
        done = restore_all()
        if done:
            for c in crumbs.values():
                c.unlink(missing_ok=True)
        for s, old in previous:
            signal.signal(s, old)
        if not done:
            print(
                "FATAL: a protected file was NOT restored — the .mutate-original "
                "records beside them hold the originals",
                file=sys.stderr,
            )


def crumb_for(target: Path) -> Path:
    return target.with_suffix(target.suffix + ".mutate-original")


def stale_crumb_refusal(target: Path) -> str | None:
    """The message a caller should print and refuse on, or None to proceed."""
    crumb = crumb_for(target)
    saved, state = read_crumb(crumb, target)
    if state == "absent":
        return None
    if state == "valid":
        return (
            f"UNKNOWN: {crumb.name} holds a complete record, so a previous run was "
            f"killed before it could restore {target.name}. The file on disk may "
            f"still hold an edit. The record is intact and verified against its "
            f"digest, so `mv {crumb.name} {target.name}` restores the original "
            f"exactly; delete {crumb.name} instead if the current content is what "
            f"you want. Nothing was measured."
        )
    return (
        f"CORRUPT: {crumb.name} is a partial record — {state}. Do NOT move it over "
        f"{target.name}: it would install a truncated original. Recover "
        f"{target.name} from version control, then delete {crumb.name}. Nothing was "
        f"measured."
    )
