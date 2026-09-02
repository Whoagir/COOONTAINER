"""Post-process SAPI voice WAVs in place: trim silence, normalize to -3 dBFS, tiny fades.

Usage:  py tools/audio/trim_voice.py [audio/voice]
Called automatically at the end of gen_voice.ps1. Pure stdlib.
"""
from __future__ import annotations

import math
import os
import struct
import sys
import wave
from array import array

THRESH = 0.012      # linear amplitude considered "silence"
PAD_SEC = 0.03      # keep this much silence on both sides
FADE_SEC = 0.006
TARGET_DB = -3.0


def process(path: str) -> tuple[int, int]:
    with wave.open(path, "rb") as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2 or ch != 1:
        return os.path.getsize(path), os.path.getsize(path)
    before = len(raw) + 44
    a = array("h")
    a.frombytes(raw)
    peak = max((abs(v) for v in a), default=0)
    if peak == 0:
        return before, before
    th = int(THRESH * 32767)
    first = next((i for i, v in enumerate(a) if abs(v) > th), 0)
    last = next((i for i in range(len(a) - 1, -1, -1) if abs(a[i]) > th), len(a) - 1)
    pad = int(PAD_SEC * sr)
    s, e = max(0, first - pad), min(len(a), last + pad + 1)
    seg = a[s:e]
    g = (10 ** (TARGET_DB / 20.0)) * 32767.0 / peak
    nf = int(FADE_SEC * sr)
    out = array("h")
    m = len(seg)
    for i, v in enumerate(seg):
        x = v * g
        if i < nf:
            x *= i / nf
        if m - 1 - i < nf:
            x *= (m - 1 - i) / nf
        out.append(int(max(-32767.0, min(32767.0, x))))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(out.tobytes())
    return before, os.path.getsize(path)


def main(argv: list[str]) -> int:
    root = argv[0] if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "audio", "voice")
    total_b = total_a = count = 0
    for dp, _, files in os.walk(root):
        for f in files:
            if f.lower().endswith(".wav"):
                b, a = process(os.path.join(dp, f))
                total_b += b
                total_a += a
                count += 1
    print(f"trimmed {count} voice files: {total_b / 1048576:.2f} MB -> {total_a / 1048576:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
