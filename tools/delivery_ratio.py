#!/usr/bin/env python3
"""delivery_ratio.py — measure how much real audio a capture actually contains.

Motivation (see docs/AUDIO-INVESTIGATION.md): when a virtual audio device
(PulseAudio null sink, ALSA null/file) is fed by a producer that cannot keep
up in real time — e.g. a game running under QEMU TCG emulation — the device
keeps its wall-clock schedule by inserting *digital silence* (exact 0.0
samples). The resulting file has the correct total duration, so duration
alone is a misleading quality metric: a 60 s capture may contain only ~24 s
of actual music, time-stretched by silence (and, once the engine's play
cursor overtakes its write cursor, with chunks genuinely skipped).

This tool quantifies that with the **delivery ratio**:

    delivery_ratio = music_seconds / total_seconds

where a *gap* is a maximal run of exact-zero frames at least --gap-ms long,
and music_seconds = total_seconds - (sum of all gap lengths). Genuine music
essentially never contains long runs of exact 0.0 in both channels, while
device-inserted silence always does, so the separation is reliable.

Input format: raw float32le PCM (default: stereo, 48000 Hz), e.g. a parec
monitor capture of a PulseAudio sink:
    parec -d <sink>.monitor --file-format=raw ...   (float32le by request)

Usage:
    python3 tools/delivery_ratio.py CAPTURE.raw [--gap-ms 5] [--rate 48000]
                                                [--channels 2]

Exit status is 0 on success, 2 on a malformed input file.
"""

import argparse
import sys

import numpy as np


def measure(path: str, rate: int, channels: int, gap_ms: float) -> dict:
    data = np.fromfile(path, dtype="<f4")
    frame_floats = channels  # float32 values per frame
    if data.size % frame_floats != 0:
        raise ValueError(
            f"file size {data.size * 4} bytes is not a whole number of "
            f"{channels}-channel float32 frames"
        )
    frames = data.reshape(-1, channels)
    total_frames = frames.shape[0]
    if total_frames == 0:
        raise ValueError("empty capture")

    # A frame counts as silence only if EVERY channel is exactly 0.0:
    # that is what a virtual device inserts, and real program material
    # (even a quiet passage) does not produce it in both channels at once.
    silent = np.all(frames == 0.0, axis=1)

    # Find maximal runs of silent frames via edge detection.
    padded = np.concatenate(([False], silent, [False]))
    edges = np.diff(padded.view(np.int8))
    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)  # exclusive
    run_lengths = ends - starts

    gap_threshold = max(1, int(round(gap_ms * rate / 1000.0)))
    gaps = run_lengths[run_lengths >= gap_threshold]
    gap_frames = int(gaps.sum())
    music_frames = total_frames - gap_frames

    total_s = total_frames / rate
    music_s = music_frames / rate
    return {
        "total_seconds": total_s,
        "music_seconds": music_s,
        "gap_seconds": gap_frames / rate,
        "gap_count": int(gaps.size),
        "longest_gap_seconds": (gaps.max() / rate) if gaps.size else 0.0,
        "gap_threshold_frames": gap_threshold,
        "delivery_ratio": music_s / total_s if total_s else 0.0,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Measure the delivery ratio of a raw float32 PCM capture "
        "(how much of it is real audio vs device-inserted silence).",
    )
    ap.add_argument("file", help="raw float32le capture file")
    ap.add_argument(
        "--gap-ms",
        type=float,
        default=5.0,
        help="minimum exact-silence run length counted as a gap, in "
        "milliseconds (default: 5)",
    )
    ap.add_argument("--rate", type=int, default=48000, help="sample rate (default: 48000)")
    ap.add_argument("--channels", type=int, default=2, help="channel count (default: 2)")
    args = ap.parse_args(argv)

    try:
        r = measure(args.file, args.rate, args.channels, args.gap_ms)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(f"file:            {args.file}")
    print(f"format:          float32le, {args.channels} ch, {args.rate} Hz")
    print(f"gap threshold:   {args.gap_ms:g} ms ({r['gap_threshold_frames']} frames)")
    print(f"total:           {r['total_seconds']:.2f} s")
    print(f"music (non-gap): {r['music_seconds']:.2f} s")
    print(f"gaps:            {r['gap_count']} runs, {r['gap_seconds']:.2f} s total, "
          f"longest {r['longest_gap_seconds']:.3f} s")
    print(f"delivery ratio:  {r['delivery_ratio']:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
