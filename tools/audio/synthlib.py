"""Tiny pure-stdlib DSP toolkit shared by gen_sfx.py / gen_music.py.

Signals are plain Python lists of floats in [-1, 1]. Everything is mono at SR.
Slow-ish but the whole soundtrack renders in a couple of minutes, which is fine.
"""
from __future__ import annotations

import math
import os
import random
import struct
import wave
from array import array
from typing import Callable, Sequence

SR = 22050
TWO_PI = 2.0 * math.pi

FreqLike = float | Callable[[float], float] | Sequence[float]


def n_samples(sec: float) -> int:
    return max(1, int(round(sec * SR)))


def silence(sec: float) -> list[float]:
    return [0.0] * n_samples(sec)


def _freq_at(freq: FreqLike, n: int):
    """Return a per-sample frequency getter."""
    if callable(freq):
        return lambda i: freq(i / SR)
    if isinstance(freq, (list, tuple, array)):
        last = len(freq) - 1
        return lambda i: freq[min(i, last)]
    f = float(freq)
    return lambda i: f


def osc(kind: str, freq: FreqLike, sec: float, amp: float = 1.0, phase: float = 0.0, duty: float = 0.5) -> list[float]:
    """Phase-accumulating oscillator. kind: sine|saw|square|tri|pulse."""
    n = n_samples(sec)
    fget = _freq_at(freq, n)
    out = [0.0] * n
    ph = phase % 1.0
    sin = math.sin
    if kind == "sine":
        for i in range(n):
            out[i] = amp * sin(TWO_PI * ph)
            ph += fget(i) / SR
            if ph >= 1.0:
                ph -= 1.0
    elif kind == "saw":
        for i in range(n):
            out[i] = amp * (2.0 * ph - 1.0)
            ph += fget(i) / SR
            if ph >= 1.0:
                ph -= 1.0
    elif kind in ("square", "pulse"):
        for i in range(n):
            out[i] = amp if ph < duty else -amp
            ph += fget(i) / SR
            if ph >= 1.0:
                ph -= 1.0
    elif kind == "tri":
        for i in range(n):
            out[i] = amp * (4.0 * abs(ph - 0.5) - 1.0)
            ph += fget(i) / SR
            if ph >= 1.0:
                ph -= 1.0
    else:
        raise ValueError(kind)
    return out


def sine(freq: FreqLike, sec: float, amp: float = 1.0, phase: float = 0.0) -> list[float]:
    return osc("sine", freq, sec, amp, phase)


def saw(freq: FreqLike, sec: float, amp: float = 1.0) -> list[float]:
    return osc("saw", freq, sec, amp)


def square(freq: FreqLike, sec: float, amp: float = 1.0, duty: float = 0.5) -> list[float]:
    return osc("square", freq, sec, amp, duty=duty)


def tri(freq: FreqLike, sec: float, amp: float = 1.0) -> list[float]:
    return osc("tri", freq, sec, amp)


def noise(sec: float, amp: float = 1.0, seed: int | None = None) -> list[float]:
    rng = random.Random(seed)
    u = rng.uniform
    return [u(-amp, amp) for _ in range(n_samples(sec))]


def sweep(f0: float, f1: float, sec: float, curve: str = "exp") -> Callable[[float], float]:
    """Frequency function from f0 to f1 over sec seconds (clamped after)."""
    if curve == "exp":
        f0 = max(f0, 1e-3)
        f1 = max(f1, 1e-3)
        ratio = f1 / f0

        def f(t: float) -> float:
            k = min(1.0, max(0.0, t / sec))
            return f0 * (ratio ** k)
    else:
        def f(t: float) -> float:
            k = min(1.0, max(0.0, t / sec))
            return f0 + (f1 - f0) * k
    return f


def vibrato(base: float, depth: float, rate: float, drift: float = 0.0) -> Callable[[float], float]:
    return lambda t: base * (1.0 + depth * math.sin(TWO_PI * rate * t)) + drift * t


# ---------------------------------------------------------------- envelopes

def env_adsr(n: int, a: float, d: float, s: float, r: float, sustain_sec: float | None = None) -> list[float]:
    """Attack/decay/sustain-level/release in seconds (sustain is level 0..1)."""
    na, nd, nr = n_samples(a), n_samples(d), n_samples(r)
    if sustain_sec is None:
        ns = max(0, n - na - nd - nr)
    else:
        ns = n_samples(sustain_sec)
    env = []
    for i in range(na):
        env.append(i / na)
    for i in range(nd):
        env.append(1.0 - (1.0 - s) * (i / nd))
    env.extend([s] * ns)
    for i in range(nr):
        env.append(s * (1.0 - i / nr))
    if len(env) < n:
        env.extend([0.0] * (n - len(env)))
    return env[:n]


def env_exp(n: int, tau: float, attack: float = 0.002) -> list[float]:
    """Percussive: instant-ish attack then exponential decay with time constant tau."""
    na = max(1, n_samples(attack))
    k = -1.0 / (tau * SR)
    env = [0.0] * n
    for i in range(n):
        e = math.exp(k * i)
        if i < na:
            e *= i / na
        env[i] = e
    return env


def env_lin(n: int, points: list[tuple[float, float]]) -> list[float]:
    """Piecewise-linear envelope from (time_sec, level) breakpoints."""
    env = [0.0] * n
    pts = sorted(points)
    j = 0
    for i in range(n):
        t = i / SR
        while j + 1 < len(pts) - 1 and t > pts[j + 1][0]:
            j += 1
        t0, v0 = pts[j]
        t1, v1 = pts[min(j + 1, len(pts) - 1)]
        if t <= t0:
            env[i] = v0
        elif t >= t1:
            env[i] = v1
        else:
            env[i] = v0 + (v1 - v0) * (t - t0) / (t1 - t0)
    return env


def apply(sig: list[float], env: Sequence[float]) -> list[float]:
    m = min(len(sig), len(env))
    out = [sig[i] * env[i] for i in range(m)]
    if len(sig) > m:
        out.extend([0.0] * (len(sig) - m))
    return out


# ---------------------------------------------------------------- arithmetic

def gain(sig: list[float], g: float) -> list[float]:
    return [x * g for x in sig]


def add(*sigs: list[float]) -> list[float]:
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, x in enumerate(s):
            out[i] += x
    return out


def mul(a: list[float], b: list[float]) -> list[float]:
    return [x * y for x, y in zip(a, b)]


def concat(*sigs: list[float]) -> list[float]:
    out: list[float] = []
    for s in sigs:
        out.extend(s)
    return out


def place(dst: list[float], src: list[float], start_sec: float, g: float = 1.0, wrap: bool = False) -> None:
    """Mix src into dst at start_sec. wrap=True wraps overflow to the head (for loops)."""
    n = len(dst)
    start = int(round(start_sec * SR))
    for i, x in enumerate(src):
        j = start + i
        if j >= n:
            if not wrap:
                break
            j %= n
        elif j < 0:
            if not wrap:
                continue
            j %= n
        dst[j] += x * g


def repeat(sig: list[float], times: int) -> list[float]:
    return sig * times


def pad(sig: list[float], sec: float) -> list[float]:
    n = n_samples(sec)
    if len(sig) >= n:
        return sig[:n]
    return sig + [0.0] * (n - len(sig))


def tail(sig: list[float], sec: float) -> list[float]:
    return sig + [0.0] * n_samples(sec)


# ---------------------------------------------------------------- filters

def lowpass(sig: list[float], cutoff: FreqLike) -> list[float]:
    """One-pole LP; cutoff may be per-sample list / callable."""
    n = len(sig)
    cget = _freq_at(cutoff, n)
    out = [0.0] * n
    y = 0.0
    dt = 1.0 / SR
    for i in range(n):
        rc = 1.0 / (TWO_PI * max(20.0, cget(i)))
        a = dt / (rc + dt)
        y += a * (sig[i] - y)
        out[i] = y
    return out


def highpass(sig: list[float], cutoff: FreqLike) -> list[float]:
    lp = lowpass(sig, cutoff)
    return [x - y for x, y in zip(sig, lp)]


def biquad(sig: list[float], kind: str, freq: FreqLike, q: float = 1.0) -> list[float]:
    """RBJ biquad: lp|hp|bp|notch. Coefficients recomputed every 32 samples when freq varies."""
    n = len(sig)
    fget = _freq_at(freq, n)
    static = not callable(freq) and not isinstance(freq, (list, tuple, array))
    out = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    b0 = b1 = b2 = a1 = a2 = 0.0

    def coeffs(f: float):
        f = min(max(f, 20.0), SR * 0.45)
        w0 = TWO_PI * f / SR
        cw, sw = math.cos(w0), math.sin(w0)
        alpha = sw / (2.0 * q)
        if kind == "lp":
            _b0 = (1 - cw) / 2
            _b1 = 1 - cw
            _b2 = (1 - cw) / 2
        elif kind == "hp":
            _b0 = (1 + cw) / 2
            _b1 = -(1 + cw)
            _b2 = (1 + cw) / 2
        elif kind == "bp":
            _b0 = alpha
            _b1 = 0.0
            _b2 = -alpha
        elif kind == "notch":
            _b0 = 1.0
            _b1 = -2 * cw
            _b2 = 1.0
        else:
            raise ValueError(kind)
        _a0 = 1 + alpha
        _a1 = -2 * cw
        _a2 = 1 - alpha
        return _b0 / _a0, _b1 / _a0, _b2 / _a0, _a1 / _a0, _a2 / _a0

    if static:
        b0, b1, b2, a1, a2 = coeffs(fget(0))
    for i in range(n):
        if not static and i % 32 == 0:
            b0, b1, b2, a1, a2 = coeffs(fget(i))
        x0 = sig[i]
        y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x0
        y2, y1 = y1, y0
        out[i] = y0
    return out


def bandpass(sig: list[float], freq: FreqLike, q: float = 2.0) -> list[float]:
    return biquad(sig, "bp", freq, q)


def formant(sig: list[float], freqs: Sequence[float], q: float = 6.0, gains: Sequence[float] | None = None) -> list[float]:
    """Parallel bandpass bank — vowel-ish coloring for noise/saw sources."""
    out = [0.0] * len(sig)
    for k, f in enumerate(freqs):
        g = gains[k] if gains else 1.0
        bp = biquad(sig, "bp", f, q)
        for i, x in enumerate(bp):
            out[i] += x * g
    return out


def soft_clip(sig: list[float], drive: float = 2.0) -> list[float]:
    th = math.tanh
    return [th(x * drive) for x in sig]


def hard_clip(sig: list[float], level: float = 0.8) -> list[float]:
    return [max(-level, min(level, x)) for x in sig]


def bitcrush(sig: list[float], bits: int = 6) -> list[float]:
    steps = float(2 ** bits)
    return [round(x * steps) / steps for x in sig]


def comb_delay(sig: list[float], delay_sec: float, feedback: float = 0.4, mix: float = 0.4, tail_sec: float = 0.0) -> list[float]:
    """Cheap echo. tail_sec appends room for the echoes to ring out."""
    n = len(sig) + n_samples(tail_sec)
    d = n_samples(delay_sec)
    out = [0.0] * n
    buf = [0.0] * n
    for i in range(n):
        x = sig[i] if i < len(sig) else 0.0
        y = x + (buf[i - d] * feedback if i >= d else 0.0)
        buf[i] = y
        out[i] = x * (1.0 - mix) + y * mix
    return out


def reverb_lite(sig: list[float], amount: float = 0.25, tail_sec: float = 0.4) -> list[float]:
    """Four detuned combs → very small-room smear. Keeps it dry-ish (cartoon SFX)."""
    n = len(sig) + n_samples(tail_sec)
    src = sig + [0.0] * (n - len(sig))
    out = list(src)
    for d, fb in ((0.0297, 0.55), (0.0371, 0.5), (0.0411, 0.45), (0.0437, 0.4)):
        dn = n_samples(d)
        buf = [0.0] * n
        for i in range(n):
            y = src[i] + (buf[i - dn] * fb if i >= dn else 0.0)
            buf[i] = y
            out[i] += (y - src[i]) * amount * 0.5
    return out


# ---------------------------------------------------------------- pluck (Karplus-Strong)

def pluck(freq: float, sec: float, amp: float = 1.0, damp: float = 0.996, brightness: float = 0.5, seed: int | None = None) -> list[float]:
    """Karplus-Strong string. brightness 0..1 → initial noise LP amount."""
    n = n_samples(sec)
    period = max(2, int(round(SR / freq)))
    rng = random.Random(seed if seed is not None else int(freq * 1000))
    buf = [rng.uniform(-1.0, 1.0) for _ in range(period)]
    # initial lowpass for a softer pick
    if brightness < 1.0:
        a = 0.2 + 0.8 * brightness
        y = 0.0
        for i in range(period):
            y += a * (buf[i] - y)
            buf[i] = y
    out = [0.0] * n
    idx = 0
    for i in range(n):
        cur = buf[idx]
        nxt = buf[(idx + 1) % period]
        out[i] = cur * amp
        buf[idx] = damp * 0.5 * (cur + nxt)
        idx = (idx + 1) % period
    return out


# ---------------------------------------------------------------- finishing

def fade(sig: list[float], fin: float = 0.003, fout: float = 0.01) -> list[float]:
    n = len(sig)
    ni, no = min(n // 2, n_samples(fin)), min(n // 2, n_samples(fout))
    out = list(sig)
    for i in range(ni):
        out[i] *= i / ni
    for i in range(no):
        out[n - 1 - i] *= i / no
    return out


def normalize(sig: list[float], db: float = -3.0) -> list[float]:
    peak = max((abs(x) for x in sig), default=0.0)
    if peak < 1e-9:
        return list(sig)
    target = 10.0 ** (db / 20.0)
    g = target / peak
    return [x * g for x in sig]


def dc_remove(sig: list[float]) -> list[float]:
    if not sig:
        return sig
    m = sum(sig) / len(sig)
    return [x - m for x in sig]


def make_loop(sig: list[float], xfade_sec: float = 0.05) -> list[float]:
    """Seamless loop: crossfade the last xfade into the first, then drop the tail."""
    n = len(sig)
    x = min(n // 4, n_samples(xfade_sec))
    if x <= 0:
        return list(sig)
    body = sig[: n - x]
    tail_part = sig[n - x:]
    for i in range(x):
        k = i / x
        body[i] = body[i] * k + tail_part[i] * (1.0 - k)
    return body


def write_wav(path: str, sig: list[float], stereo_right: list[float] | None = None, sr: int = SR) -> int:
    """Write 16-bit PCM WAV. Returns byte size."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    frames = array("h")
    if stereo_right is None:
        for x in sig:
            v = int(max(-1.0, min(1.0, x)) * 32767.0)
            frames.append(v)
        ch = 1
    else:
        m = min(len(sig), len(stereo_right))
        for i in range(m):
            frames.append(int(max(-1.0, min(1.0, sig[i])) * 32767.0))
            frames.append(int(max(-1.0, min(1.0, stereo_right[i])) * 32767.0))
        ch = 2
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(frames.tobytes())
    return os.path.getsize(path)


def finish(sig: list[float], db: float = -3.0, fin: float = 0.003, fout: float = 0.01) -> list[float]:
    return normalize(fade(dc_remove(sig), fin, fout), db)


def finish_loop(sig: list[float], db: float = -3.0, xfade: float = 0.03) -> list[float]:
    """Normalize and make loop-seamless (no edge fades — those would click on wrap)."""
    return make_loop(normalize(dc_remove(sig), db), xfade)


# ---------------------------------------------------------------- music helpers

def midi(n: float) -> float:
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


NOTE_NAMES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
              "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def note(name: str) -> float:
    """'A4' → Hz, 'C#3' → Hz."""
    octave = int(name[-1])
    key = name[:-1]
    return midi(12 * (octave + 1) + NOTE_NAMES[key])


def chord(root: str, kind: str = "maj") -> list[float]:
    r = midi_of(root)
    ivs = {"maj": (0, 4, 7), "min": (0, 3, 7), "dom7": (0, 4, 7, 10), "min7": (0, 3, 7, 10),
           "maj7": (0, 4, 7, 11), "dim": (0, 3, 6), "pow": (0, 7, 12), "sus2": (0, 2, 7), "maj6": (0, 4, 7, 9),
           "min6": (0, 3, 7, 9), "9": (0, 4, 7, 10, 14)}[kind]
    return [midi(r + i) for i in ivs]


def midi_of(name: str) -> int:
    octave = int(name[-1])
    return 12 * (octave + 1) + NOTE_NAMES[name[:-1]]
