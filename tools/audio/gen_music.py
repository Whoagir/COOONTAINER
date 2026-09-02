"""Procedural music loops for COOONTAINER -> audio/music/*.wav (16-bit mono 22050 Hz).

Usage:  py tools/audio/gen_music.py [name ...]
Every loop is composed in whole bars; notes that spill past the end wrap to the head
(place(..., wrap=True)) so AudioStreamWAV LOOP_FORWARD is seamless. `credits` is a
one-shot 30 s piece that resolves.
"""
from __future__ import annotations

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synthlib import *  # noqa: E402,F401,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "audio", "music")

TRACKS: dict[str, tuple[callable, str, bool]] = {}


def track(desc: str, loop: bool = True):
    def deco(fn):
        TRACKS[fn.__name__] = (fn, desc, loop)
        return fn
    return deco


# ------------------------------------------------------------------ sequencer

class Song:
    def __init__(self, bpm: float, bars: int, beats: int = 4, loop: bool = True, tail: float = 0.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.beats = beats
        self.length = bars * beats * self.beat + tail
        self.loop = loop
        self.buf = [0.0] * n_samples(self.length)
        self.rng = random.Random(bpm * 7 + bars)

    def t(self, bar: float, beat: float = 0.0) -> float:
        return (bar * self.beats + beat) * self.beat

    def put(self, sig: list[float], bar: float, beat: float = 0.0, g: float = 1.0, humanize: float = 0.0) -> None:
        st = self.t(bar, beat)
        if humanize:
            st += self.rng.uniform(-humanize, humanize)
            st = max(0.0, st)
        place(self.buf, sig, st, g, wrap=self.loop)

    def dur(self, beats: float) -> float:
        return beats * self.beat


# ------------------------------------------------------------------ instruments

def kick(sec: float = 0.35, f0: float = 150, f1: float = 42, punch: float = 1.0) -> list[float]:
    n = n_samples(sec)
    body = apply(sine(sweep(f0, f1, 0.09), sec), env_exp(n, 0.09))
    click = apply(lowpass(noise(0.02, 1.0, 1), 3000), env_exp(n_samples(0.02), 0.004))
    out = list(body)
    place(out, click, 0.0, 0.5 * punch)
    return soft_clip(out, 1.6)


def snare(sec: float = 0.25, tone: float = 190, seed: int = 2, snap: float = 1.0) -> list[float]:
    n = n_samples(sec)
    nz = apply(bandpass(noise(sec, 1.0, seed), 2400, 0.6), env_exp(n, 0.06))
    body = apply(sine(sweep(tone * 1.5, tone, 0.04), sec), env_exp(n, 0.04))
    return add(gain(nz, snap), gain(body, 0.7))


def hat(sec: float = 0.08, seed: int = 3, open_: bool = False) -> list[float]:
    d = sec * (3 if open_ else 1)
    return apply(highpass(noise(d, 1.0, seed), 6500), env_exp(n_samples(d), 0.08 if open_ else 0.012))


def clave(f: float = 2500) -> list[float]:
    n = n_samples(0.08)
    return apply(sine(f, 0.08), env_exp(n, 0.015))


def rim(seed: int = 4) -> list[float]:
    n = n_samples(0.06)
    return apply(add(bandpass(noise(0.06, 1.0, seed), 3500, 2.0), sine(900, 0.06, 0.4)), env_exp(n, 0.01))


def bass(f: float, sec: float, kind: str = "saw", cutoff: float = 500, amp: float = 0.8, rel: float = 0.08) -> list[float]:
    n = n_samples(sec)
    src = osc(kind, f, sec, amp) if kind != "sine" else add(sine(f, sec, amp), sine(f * 2, sec, amp * 0.3))
    src = lowpass(src, cutoff)
    return apply(src, env_adsr(n, 0.005, 0.05, 0.8, rel))


def uke(f: float, sec: float = 0.6, amp: float = 0.7) -> list[float]:
    return pluck(f, sec, amp, damp=0.992, brightness=0.55)


def banjo(f: float, sec: float = 0.4, amp: float = 0.7) -> list[float]:
    s = pluck(f, sec, amp, damp=0.985, brightness=0.95)
    return highpass(s, 250)


def guitar(f: float, sec: float, amp: float = 0.6) -> list[float]:
    return pluck(f, sec, amp, damp=0.997, brightness=0.4)


def organ(freqs: list[float], sec: float, amp: float = 0.25, wobble: float = 0.0, detune: float = 0.0) -> list[float]:
    """Cheesy drawbar organ: fundamentals + 2nd/3rd harmonic with slow wobble + detune."""
    n = n_samples(sec)
    out = [0.0] * n
    for k, f in enumerate(freqs):
        ph = 0.13 * k
        fn = vibrato(f * (1 + detune * (k % 2 * 2 - 1)), wobble, 5.5 + 0.3 * k)
        out = add(out, sine(fn, sec, amp, ph), sine(lambda t, fn=fn: fn(t) * 2, sec, amp * 0.45, ph),
                  sine(lambda t, fn=fn: fn(t) * 3, sec, amp * 0.2, ph), sine(lambda t, fn=fn: fn(t) * 0.5, sec, amp * 0.3, ph))
    return apply(out, env_adsr(n, 0.02, 0.05, 0.9, 0.06))


def stab(freqs: list[float], sec: float, kind: str = "saw", amp: float = 0.35, cutoff: float = 2500) -> list[float]:
    n = n_samples(sec)
    out = [0.0] * n
    for k, f in enumerate(freqs):
        out = add(out, osc(kind, f * (1 + 0.002 * (k % 2)), sec, amp))
    out = lowpass(out, cutoff)
    return apply(out, env_adsr(n, 0.005, 0.08, 0.5, 0.06))


def sax(f: float, sec: float, amp: float = 0.6) -> list[float]:
    """Sleazy sax-ish: saw + sine with scoop-in pitch, vibrato and breath."""
    n = n_samples(sec)
    fn = lambda t: f * (0.94 + 0.06 * min(1.0, t / 0.12)) * (1 + 0.012 * math.sin(TWO_PI * 5.2 * t) * min(1.0, t / 0.3))
    src = add(osc("saw", fn, sec, amp * 0.5), sine(fn, sec, amp * 0.6), sine(lambda t: fn(t) * 2, sec, amp * 0.2))
    src = formant(src, (600, 1300, 2500), 2.5, (1.0, 0.7, 0.35))
    breath = gain(bandpass(noise(sec, 1.0, 5), 2200, 0.8), amp * 0.12)
    out = add(src, breath)
    return apply(lowpass(out, 3800), env_adsr(n, 0.05, 0.1, 0.85, 0.12))


def power_chord(f: float, sec: float, amp: float = 0.5) -> list[float]:
    """Deliberately bad garage rock: detuned saws, hard clip, muddy."""
    n = n_samples(sec)
    voices = []
    for m, det in ((1.0, 1.0), (1.5, 1.004), (2.0, 0.997), (1.0, 1.009)):
        voices.append(osc("saw", f * m * det, sec, amp))
    out = add(*voices)
    out = hard_clip(gain(lowpass(out, 3200), 3.0), 0.7)
    out = apply(out, env_adsr(n, 0.005, 0.05, 0.8, 0.05))
    return highpass(out, 80)


def bell_pad(freqs: list[float], sec: float, amp: float = 0.2) -> list[float]:
    n = n_samples(sec)
    out = [0.0] * n
    for f in freqs:
        out = add(out, sine(f, sec, amp), sine(f * 2.0, sec, amp * 0.3), sine(f * 3.01, sec, amp * 0.1))
    return apply(out, env_adsr(n, 0.4, 0.3, 0.8, 0.8))


def tick(f: float = 4000) -> list[float]:
    n = n_samples(0.03)
    return apply(add(sine(f, 0.03, 0.6), highpass(noise(0.03, 0.6, 6), 5000)), env_exp(n, 0.006))


def chord_hz(root: str, kind: str) -> list[float]:
    return chord(root, kind)


# ------------------------------------------------------------------ tracks

@track("goofy upbeat ukulele-ish plucks (menu)")
def menu_loop() -> list[float]:
    s = Song(124, 8)
    prog = [("C4", "maj"), ("F4", "maj"), ("G4", "maj"), ("C4", "maj"), ("A3", "min"), ("F4", "maj"), ("G4", "maj"), ("C4", "maj")]
    for bar, (root, kind) in enumerate(prog):
        ch = chord_hz(root, kind)
        # island strum: down-down-up-up-down-up
        pattern = [(0, 1), (1, 1), (1.5, -1), (2.5, -1), (3, 1), (3.5, -1)]
        for beat, dirn in pattern:
            notes = ch if dirn > 0 else list(reversed(ch))
            for k, f in enumerate(notes):
                s.put(uke(f, 0.5, 0.5 if dirn > 0 else 0.35), bar, beat + k * 0.02, humanize=0.004)
        b = midi_of(root)
        s.put(bass(midi(b - 24), s.dur(1.5), "sine", 400, 0.7), bar, 0)
        s.put(bass(midi(b - 24 + (7 if kind == "maj" else 7)), s.dur(1.5), "sine", 400, 0.6), bar, 2)
        s.put(kick(0.3, 130, 45, 0.6), bar, 0, 0.6)
        s.put(kick(0.3, 130, 45, 0.6), bar, 2, 0.5)
        for beat in (1, 3):
            s.put(rim(7), bar, beat, 0.5)
        for beat in range(4):
            s.put(hat(0.06, 8 + beat), bar, beat + 0.5, 0.25)
    # goofy whistle-ish melody (sine with vibrato) on bars 4-7
    mel = [(4, 0, "E5", 1), (4, 1, "G5", 1), (4, 2, "A5", 2), (5, 0, "G5", 1), (5, 1, "E5", 1), (5, 2, "C5", 2),
           (6, 0, "D5", 1), (6, 1, "E5", 1), (6, 2, "D5", 1), (6, 3, "B4", 1), (7, 0, "C5", 3)]
    for bar, beat, nm, beats in mel:
        d = s.dur(beats) * 0.9
        m = apply(sine(vibrato(note(nm), 0.01, 6.0), d, 0.3), env_adsr(n_samples(d), 0.03, 0.05, 0.8, 0.1))
        s.put(m, bar, beat)
    return finish_loop(soft_clip(s.buf, 1.2), -3.0, 0.02)


@track("lazy trailer-park country shuffle (hub)")
def hub_loop() -> list[float]:
    s = Song(92, 6)
    prog = [("G3", "maj"), ("C4", "maj"), ("G3", "maj"), ("D4", "maj"), ("C4", "maj"), ("D4", "dom7")]
    for bar, (root, kind) in enumerate(prog):
        ch = chord_hz(root, kind)
        b = midi_of(root)
        # boom-chick: bass on 1 & 3, chord strum on 2 & 4 with shuffle
        s.put(bass(midi(b - 12), s.dur(1.2), "tri", 600, 0.8), bar, 0)
        s.put(bass(midi(b - 12 + 7), s.dur(1.2), "tri", 600, 0.7), bar, 2)
        for beat in (1, 3):
            for k, f in enumerate(ch):
                s.put(guitar(f, 0.7, 0.4), bar, beat + k * 0.025, humanize=0.006)
            # shuffle upstroke
            for k, f in enumerate(reversed(ch)):
                s.put(guitar(f, 0.4, 0.22), bar, beat + 0.66 + k * 0.02)
        s.put(kick(0.3, 120, 50, 0.4), bar, 0, 0.5)
        s.put(kick(0.3, 120, 50, 0.4), bar, 2, 0.4)
        s.put(snare(0.2, 200, 9, 0.5), bar, 1, 0.35)
        s.put(snare(0.2, 200, 10, 0.5), bar, 3, 0.35)
        for beat in range(4):
            s.put(hat(0.05, 11 + beat), bar, beat + 0.66, 0.18)
    # slide-guitar-ish lazy lick (pitch-bent saw, lowpassed)
    licks = [(1, 2, "B4", "D5", 1.5), (3, 2, "E5", "D5", 1.5), (5, 0, "F#5", "G5", 3)]
    for bar, beat, a, b_, beats in licks:
        d = s.dur(beats)
        f = sweep(note(a), note(b_), d * 0.4)
        lk = apply(lowpass(osc("saw", lambda t, f=f: f(t) * (1 + 0.008 * math.sin(TWO_PI * 5 * t)), d, 0.35), 1800), env_adsr(n_samples(d), 0.05, 0.1, 0.7, 0.2))
        s.put(lk, bar, beat)
    return finish_loop(soft_clip(s.buf, 1.2), -3.0, 0.02)


@track("fast tense banjo-ish pulse with rising tension (auction)")
def auction_loop() -> list[float]:
    s = Song(150, 8)
    # Em pedal with chromatic rising bass — tension climbs then resets
    roots = ["E3", "E3", "F3", "F3", "F#3", "F#3", "G3", "B3"]
    kinds = ["min", "min", "dim", "dim", "dim", "dim", "min", "dom7"]
    for bar, (root, kind) in enumerate(zip(roots, kinds)):
        ch = chord_hz(root, kind)
        b = midi_of(root)
        # banjo roll: 16ths cycling through the chord tones
        roll = [ch[0], ch[1], ch[2], ch[1] * 2, ch[0] * 2, ch[2], ch[1], ch[0] * 2] * 2
        for k, f in enumerate(roll):
            s.put(banjo(f, 0.25, 0.45 + 0.05 * (bar / 8)), bar, k * 0.25, humanize=0.003)
        for beat in range(4):
            s.put(bass(midi(b - 12), s.dur(0.4), "square", 450, 0.6, 0.03), bar, beat)
            s.put(kick(0.2, 140, 55, 0.8), bar, beat, 0.6)
        for beat in range(4):
            s.put(hat(0.04, 20 + beat), bar, beat + 0.5, 0.3)
        s.put(snare(0.15, 220, 21, 0.9), bar, 1, 0.5)
        s.put(snare(0.15, 220, 22, 0.9), bar, 3, 0.5)
        if bar >= 4:
            s.put(snare(0.12, 220, 23, 0.9), bar, 3.5, 0.35)
    # rising tension: tremolo string-ish saw climbing through the loop
    for bar in range(8):
        f = midi(52 + bar)  # E3 upward
        d = s.dur(4)
        trem = [0.6 + 0.4 * math.sin(TWO_PI * 12 * (i / SR)) for i in range(n_samples(d))]
        st = mul(lowpass(add(osc("saw", f * 2, d, 0.18), osc("saw", f * 2 * 1.006, d, 0.18)), 2200 + 200 * bar), trem)
        s.put(apply(st, env_adsr(n_samples(d), 0.05, 0.1, 0.9, 0.1)), bar, 0, 0.5 + 0.06 * bar)
    # gavel ticks
    for bar in range(8):
        s.put(clave(3000), bar, 2, 0.3)
    return finish_loop(soft_clip(s.buf, 1.3), -3.0, 0.02)


@track("frantic drum'n'bass-lite with ticking clock (clearout)")
def clearout_loop() -> list[float]:
    s = Song(172, 8)
    roots = ["A2", "A2", "C3", "C3", "G2", "G2", "F2", "E2"]
    for bar, root in enumerate(roots):
        b = midi_of(root)
        # amen-ish break pattern (16ths)
        kicks = [0, 2.5, 4, 6.5, 10, 12.5] if bar % 2 == 0 else [0, 2.5, 4, 7, 10, 11, 12.5]
        snares = [4, 9, 11, 14] if bar % 2 == 0 else [4, 9, 12, 14, 15]
        for k in kicks:
            s.put(kick(0.25, 160, 48, 1.0), bar, k / 4, 0.75)
        for k in snares:
            s.put(snare(0.18, 240, 30 + int(k), 1.0), bar, k / 4, 0.55)
        for k in range(16):
            s.put(hat(0.03, 40 + k, open_=(k % 4 == 2)), bar, k / 4, 0.22 if k % 2 == 0 else 0.13)
        # reese bass: two detuned saws, lowpassed, long notes
        d = s.dur(4)
        reese = lowpass(add(osc("saw", midi(b), d, 0.5), osc("saw", midi(b) * 1.004, d, 0.5), osc("square", midi(b) / 2, d, 0.25)), 380)
        s.put(apply(reese, env_adsr(n_samples(d), 0.01, 0.1, 0.9, 0.08)), bar, 0, 0.9)
        # ticking clock: every beat, alternating tick/tock
        for beat in range(4):
            s.put(tick(4200 if beat % 2 == 0 else 3500), bar, beat, 0.6)
        # stabs
        ch = chord_hz(root[0] + str(int(root[-1]) + 2), "min")
        for beat in (1.5, 3.0):
            s.put(stab(ch, s.dur(0.5), "square", 0.2, 3000), bar, beat, 0.6)
    return finish_loop(soft_clip(s.buf, 1.4), -3.0, 0.02)


@track("stinky lounge organ with detuned wobble (casino)")
def casino_loop() -> list[float]:
    s = Song(104, 6)
    prog = [("C4", "maj7"), ("A3", "min7"), ("D4", "min7"), ("G3", "dom7"), ("D4", "min7"), ("G3", "dom7")]
    for bar, (root, kind) in enumerate(prog):
        ch = chord_hz(root, kind)
        b = midi_of(root)
        # organ pad, with wobble getting greasier as the bar goes
        s.put(organ(ch, s.dur(3.8), 0.16, wobble=0.006 + 0.001 * bar, detune=0.003), bar, 0, 0.9)
        # walking-ish lounge bass
        walk = [b - 24, b - 24 + 4, b - 24 + 7, b - 24 + 9] if kind != "dom7" else [b - 24, b - 24 + 4, b - 24 + 7, b - 24 + 10]
        for beat, nn in enumerate(walk):
            s.put(bass(midi(nn), s.dur(0.9), "sine", 350, 0.8), bar, beat)
        # cocktail drums: brushed snare feel + rim
        for beat in range(4):
            s.put(hat(0.12, 50 + beat), bar, beat, 0.12)
            s.put(hat(0.06, 60 + beat), bar, beat + 0.66, 0.1)
        s.put(rim(70), bar, 1, 0.3)
        s.put(rim(71), bar, 3, 0.3)
        s.put(kick(0.3, 110, 50, 0.3), bar, 0, 0.35)
    # cheesy organ melody with glissando fills
    mel = [(0, 0, "E5", 2), (0, 2, "G5", 1), (0, 3, "B5", 1), (1, 0, "A5", 3), (2, 0, "F5", 2), (2, 2, "A5", 2),
           (3, 0, "B4", 1.5), (3, 1.5, "D5", 2.5), (4, 0, "F5", 1.5), (4, 1.5, "E5", 1.5), (4, 3, "D5", 1), (5, 0, "B4", 4)]
    for bar, beat, nm, beats in mel:
        d = s.dur(beats) * 0.95
        s.put(organ([note(nm)], d, 0.22, wobble=0.012, detune=0.004), bar, beat, 0.8)
    return finish_loop(soft_clip(s.buf, 1.2), -3.0, 0.03)


@track("sleazy sax-ish leads over walking bass (vendor)")
def vendor_loop() -> list[float]:
    s = Song(96, 6)
    prog = [("D3", "min7"), ("G3", "dom7"), ("C3", "maj7"), ("A3", "dom7"), ("E3", "min7"), ("A3", "dom7")]
    for bar, (root, kind) in enumerate(prog):
        b = midi_of(root)
        third = 3 if "min" in kind else 4
        seventh = 10 if "7" in kind and kind != "maj7" else 11
        walk = [b - 12, b - 12 + third, b - 12 + 7, b - 12 + seventh]
        for beat, nn in enumerate(walk):
            s.put(bass(midi(nn), s.dur(0.95), "tri", 500, 0.85), bar, beat, humanize=0.008)
        for beat in range(4):
            s.put(hat(0.08, 80 + beat), bar, beat + 0.66, 0.16)
            s.put(hat(0.05, 90 + beat), bar, beat, 0.1)
        s.put(snare(0.2, 190, 100 + bar, 0.4), bar, 1, 0.25)
        s.put(snare(0.2, 190, 110 + bar, 0.4), bar, 3, 0.3)
        s.put(kick(0.3, 120, 50, 0.4), bar, 0, 0.45)
        s.put(kick(0.3, 120, 50, 0.4), bar, 2.5, 0.3)
        # comping chord stabs (muted guitar-ish)
        ch = chord_hz(root[0] + str(int(root[-1]) + 1), kind)
        for beat in (1.5, 3.5):
            for k, f in enumerate(ch):
                s.put(guitar(f, 0.25, 0.22), bar, beat + k * 0.015)
    mel = [(0, 0, "A4", 1.5), (0, 1.5, "F4", 1), (0, 2.5, "D4", 1.5), (1, 0, "F4", 2), (1, 2, "B4", 2),
           (2, 0, "E4", 3), (2, 3, "G4", 1), (3, 0, "C#5", 1.5), (3, 1.5, "A4", 2.5),
           (4, 0, "G4", 1.5), (4, 1.5, "E4", 2.5), (5, 0, "C#5", 2), (5, 2, "E5", 2)]
    for bar, beat, nm, beats in mel:
        d = s.dur(beats) * 0.92
        s.put(sax(note(nm), d, 0.45), bar, beat, 0.85, humanize=0.01)
    return finish_loop(soft_clip(s.buf, 1.2), -3.0, 0.03)


@track("deadpan cop-show funk (police)")
def police_loop() -> list[float]:
    s = Song(100, 6)
    for bar in range(6):
        root = 41 if bar % 3 != 2 else 44  # F2 / Ab2
        # funk bass riff (16ths)
        riff = [(0, 0), (0.75, 0), (1.25, 12), (1.5, 10), (2, 0), (2.75, 7), (3.25, 5), (3.5, 3)]
        for beat, iv in riff:
            s.put(bass(midi(root + iv), s.dur(0.3), "square", 900, 0.7, 0.03), bar, beat, humanize=0.005)
        s.put(kick(0.3, 150, 50, 0.9), bar, 0, 0.7)
        s.put(kick(0.3, 150, 50, 0.9), bar, 2.5, 0.6)
        s.put(snare(0.2, 200, 120 + bar, 1.0), bar, 1, 0.55)
        s.put(snare(0.2, 200, 130 + bar, 1.0), bar, 3, 0.55)
        for k in range(8):
            s.put(hat(0.04, 140 + k, open_=(k == 7)), bar, k * 0.5, 0.25 if k % 2 == 0 else 0.15)
        # wah-guitar chucks: bandpass-swept saw chords on offbeats
        ch = chord(("F3" if root == 41 else "Ab3"), "min7")
        for beat in (0.5, 1.5, 2.5, 3.5):
            d = s.dur(0.4)
            ck = stab(ch, d, "saw", 0.25, 4000)
            ck = biquad(ck, "bp", sweep(600, 2200, d), 2.0)
            s.put(ck, bar, beat, 0.7)
        # brass hit on the Ab bars
        if root == 44:
            hit = stab(chord("Ab4", "dom7"), s.dur(0.6), "saw", 0.3, 3000)
            s.put(hit, bar, 0, 0.9)
            s.put(hit, bar, 2, 0.7)
    # deadpan clav-ish melody
    mel = [(1, 0, "C5", 0.5), (1, 0.5, "Eb5", 0.5), (1, 1, "F5", 1), (2, 0, "Eb5", 0.5), (2, 0.5, "C5", 1.5),
           (4, 0, "F5", 0.5), (4, 0.5, "Ab5", 0.5), (4, 1, "G5", 1), (4, 2, "F5", 0.5), (4, 2.5, "Eb5", 0.5), (4, 3, "C5", 1)]
    for bar, beat, nm, beats in mel:
        d = s.dur(beats) * 0.85
        s.put(stab([note(nm)], d, "square", 0.3, 2500), bar, beat, 0.6)
    return finish_loop(soft_clip(s.buf, 1.3), -3.0, 0.02)


@track("sad slow mop waltz (janitor)")
def janitor_loop() -> list[float]:
    s = Song(84, 6, beats=3)
    prog = [("A3", "min"), ("D3", "min"), ("E3", "maj"), ("A3", "min"), ("F3", "maj"), ("E3", "maj")]
    for bar, (root, kind) in enumerate(prog):
        ch = chord_hz(root, kind)
        b = midi_of(root)
        s.put(bass(midi(b - 12), s.dur(1.0), "sine", 400, 0.8), bar, 0)
        for beat in (1, 2):
            for k, f in enumerate(ch):
                s.put(guitar(f, 0.8, 0.3), bar, beat + k * 0.03, humanize=0.01)
        # mop squeak on beat 1 of every other bar, drip on 3
        if bar % 2 == 0:
            sq = apply(osc("saw", lambda t: 1700 + 500 * math.sin(math.pi * t / 0.3), 0.3, 0.12), env_adsr(n_samples(0.3), 0.05, 0.05, 0.8, 0.1))
            s.put(bandpass(sq, 2000, 3.0), bar, 0.5, 0.5)
        drip = apply(sine(sweep(1200, 1800, 0.06), 0.1, 0.4), env_exp(n_samples(0.1), 0.03))
        s.put(drip, bar, 2.5, 0.35)
        s.put(kick(0.35, 100, 45, 0.2), bar, 0, 0.3)
        s.put(hat(0.1, 150 + bar), bar, 1, 0.08)
        s.put(hat(0.1, 160 + bar), bar, 2, 0.08)
    # accordion-ish sad melody (detuned squares + sines)
    mel = [(0, 0, "E5", 2), (0, 2, "C5", 1), (1, 0, "F5", 2), (1, 2, "D5", 1), (2, 0, "B4", 3),
           (3, 0, "C5", 1), (3, 1, "D5", 1), (3, 2, "E5", 1), (4, 0, "F5", 2), (4, 2, "A5", 1), (5, 0, "G#5", 2), (5, 2, "B4", 1)]
    for bar, beat, nm, beats in mel:
        d = s.dur(beats) * 0.95
        f = note(nm)
        acc = add(osc("square", f * 0.998, d, 0.12, duty=0.45), osc("square", f * 1.003, d, 0.12, duty=0.45), sine(f, d, 0.15))
        acc = lowpass(acc, 2500)
        s.put(apply(acc, env_adsr(n_samples(d), 0.08, 0.1, 0.85, 0.15)), bar, beat, 0.8)
    return finish_loop(soft_clip(s.buf, 1.2), -3.0, 0.03)


@track("deliberately bad garage rock (car)")
def car_rock_loop() -> list[float]:
    s = Song(138, 8)
    s.rng = random.Random(666)
    roots = ["E2", "E2", "A2", "A2", "E2", "E2", "G2", "A2"]
    for bar, root in enumerate(roots):
        f = note(root)
        # sloppy 8th-note power chords with random timing slop and occasional flubbed muted hit
        for k in range(8):
            slop = s.rng.uniform(-0.03, 0.03)
            if s.rng.random() < 0.12:
                s.put(gain(bandpass(noise(0.08, 1.0, 200 + k), 800, 1.0), 0.4), bar, k * 0.5 + slop, 0.6)
                continue
            s.put(power_chord(f, s.dur(0.45), 0.45), bar, k * 0.5 + slop, 0.85)
        # sloppy drums: kick 1 & 3 (drifting), snare 2 & 4 (late), crash-y hats
        s.put(kick(0.3, 160, 50, 1.0), bar, 0 + s.rng.uniform(-0.02, 0.02), 0.8)
        s.put(kick(0.3, 160, 50, 1.0), bar, 2 + s.rng.uniform(-0.02, 0.04), 0.7)
        s.put(snare(0.25, 180, 210 + bar, 1.2), bar, 1 + s.rng.uniform(0.0, 0.05), 0.65)
        s.put(snare(0.25, 180, 220 + bar, 1.2), bar, 3 + s.rng.uniform(0.0, 0.06), 0.65)
        for k in range(8):
            s.put(hat(0.08, 230 + k, open_=True), bar, k * 0.5 + s.rng.uniform(-0.02, 0.02), 0.22)
        # bass doubling root, slightly out of tune
        s.put(bass(f / 2 * 1.006, s.dur(3.8), "saw", 700, 0.8, 0.1), bar, 0, 0.9)
    # terrible solo on bars 4-7: bent saw with too much vibrato, wrong notes
    solo = [(4, 0, "E4", 1), (4, 1, "G4", 0.5), (4, 1.5, "A4", 1.5), (4, 3, "Bb4", 1), (5, 0, "B4", 2), (5, 2, "D5", 1), (5, 3, "E5", 1),
            (6, 0, "G5", 0.5), (6, 0.5, "F#5", 0.5), (6, 1, "E5", 1), (6, 2, "C#5", 2), (7, 0, "E5", 4)]
    for bar, beat, nm, beats in solo:
        d = s.dur(beats)
        f0 = note(nm) * s.rng.uniform(0.985, 1.015)
        fn = lambda t, f0=f0: f0 * (1 + 0.03 * math.sin(TWO_PI * 7 * t) * min(1.0, t / 0.15))
        lead = hard_clip(gain(lowpass(osc("saw", fn, d, 0.5), 2800), 2.5), 0.6)
        s.put(apply(lead, env_adsr(n_samples(d), 0.01, 0.05, 0.9, 0.08)), bar, beat, 0.55)
    out = hard_clip(gain(s.buf, 1.3), 0.9)
    return finish_loop(lowpass(out, 6000), -3.0, 0.02)


@track("warm 30 s credits piece, resolves", loop=False)
def credits() -> list[float]:
    s = Song(96, 12, loop=False, tail=3.0)  # 12 bars = 30 s + tail
    prog = [("C4", "maj"), ("G3", "maj"), ("A3", "min"), ("F4", "maj"), ("C4", "maj"), ("G3", "maj"),
            ("A3", "min"), ("E4", "min"), ("F4", "maj"), ("G3", "dom7"), ("C4", "maj"), ("C4", "maj")]
    for bar, (root, kind) in enumerate(prog):
        ch = chord_hz(root, kind)
        b = midi_of(root)
        last = bar >= 10
        d = s.dur(4 if not last else 8)
        s.put(bell_pad(ch, d, 0.16), bar, 0, 1.0 if not last else 0.9)
        s.put(bass(midi(b - 24), s.dur(3.5), "sine", 300, 0.7, 0.3), bar, 0)
        if not last:
            for beat in (0, 1, 2, 3):
                for k, f in enumerate(ch):
                    s.put(uke(f, 0.9, 0.3), bar, beat + k * 0.04 + (0.5 if beat % 2 else 0), humanize=0.01)
            s.put(kick(0.35, 100, 45, 0.2), bar, 0, 0.3)
            s.put(hat(0.15, 300 + bar), bar, 2, 0.08)
        else:
            for k, f in enumerate(ch):
                s.put(uke(f, 1.5, 0.35), bar, k * 0.06)
    # melody: gentle, ends on the tonic held
    mel = [(0, 0, "E5", 2), (0, 2, "G5", 2), (1, 0, "D5", 3), (2, 0, "C5", 2), (2, 2, "E5", 2), (3, 0, "A5", 3),
           (4, 0, "G5", 2), (4, 2, "E5", 1), (4, 3, "D5", 1), (5, 0, "B4", 3),
           (6, 0, "E5", 2), (6, 2, "C5", 2), (7, 0, "B4", 3), (8, 0, "A4", 2), (8, 2, "C5", 2), (9, 0, "D5", 2), (9, 2, "B4", 2),
           (10, 0, "C5", 8)]
    for bar, beat, nm, beats in mel:
        d = s.dur(beats) * 0.95
        f = note(nm)
        lead = add(sine(vibrato(f, 0.006, 5.0), d, 0.3), osc("tri", f, d, 0.12))
        s.put(apply(lowpass(lead, 3000), env_adsr(n_samples(d), 0.08, 0.1, 0.85, 0.4)), bar, beat, 0.9)
    out = reverb_lite(s.buf, 0.3, 0.0)
    # gentle final fade so the tail is silent
    return finish(soft_clip(out, 1.1), -3.0, 0.01, 2.5)


# ------------------------------------------------------------------ main

REQUIRED = ["menu_loop", "hub_loop", "auction_loop", "clearout_loop", "casino_loop", "vendor_loop", "police_loop",
            "janitor_loop", "car_rock_loop", "credits"]


def patch_import(wav_path: str, loop: bool) -> None:
    """AudioBus.play_music computes loop_end from data.size() assuming PCM16, so music must NOT be
    QOA-compressed (project default compress/mode=2). Patch the Godot .import sidecar if it exists."""
    imp = wav_path + ".import"
    if not os.path.exists(imp):
        return
    with open(imp, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    want = {"compress/mode": "0", "edit/loop_mode": "1" if loop else "0"}
    out = []
    for ln in lines:
        key = ln.split("=", 1)[0]
        if key in want:
            ln = f"{key}={want[key]}"
        out.append(ln)
    with open(imp, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def main(argv: list[str]) -> int:
    missing = [n for n in REQUIRED if n not in TRACKS]
    if missing:
        print("tracks missing:", missing)
        return 1
    names = argv or list(TRACKS.keys())
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name in names:
        fn, desc, loop = TRACKS[name]
        sig = fn()
        path = os.path.join(OUT_DIR, name + ".wav")
        size = write_wav(path, sig)
        patch_import(path, loop)
        total += size
        print(f"  {name:16s} {len(sig) / SR:6.2f}s {size // 1024:5d} KB  {'loop' if loop else 'one-shot'}  {desc}", flush=True)
    print(f"{len(names)} tracks, {total / 1024 / 1024:.2f} MB -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
