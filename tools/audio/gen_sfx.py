"""Generate all cartoon SFX for COOONTAINER → audio/sfx/*.wav (16-bit mono 22050 Hz).

Usage:  py tools/audio/gen_sfx.py [name ...]     (no args = everything)
Pure stdlib. Each generator returns a float list; `finish()` normalizes to -3 dBFS and
fades edges. Loops use `finish_loop()` (crossfaded wrap, no edge fade).
"""
from __future__ import annotations

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synthlib import *  # noqa: E402,F401,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "audio", "sfx")

GEN: dict[str, tuple[callable, str]] = {}


def sfx(desc: str, loop: bool = False):
    def deco(fn):
        GEN[fn.__name__] = (fn, desc, loop)
        return fn
    return deco


# ------------------------------------------------------------------ impacts

def _thump(f0: float, f1: float, sec: float, tau: float, noise_amt: float, seed: int) -> list[float]:
    body = apply(sine(sweep(f0, f1, sec * 0.6), sec), env_exp(n_samples(sec), tau))
    click = apply(lowpass(noise(sec, 1.0, seed), 1800), env_exp(n_samples(sec), tau * 0.25))
    return add(body, gain(click, noise_amt))


@sfx("soft box/bag landing on the floor")
def thud() -> list[float]:
    return finish(soft_clip(_thump(160, 55, 0.25, 0.06, 0.5, 1), 1.5))


@sfx("heavy crate slam, low boom")
def thud_heavy() -> list[float]:
    s = _thump(110, 35, 0.6, 0.16, 0.7, 2)
    rumble = apply(lowpass(noise(0.6, 1.0, 3), 140), env_exp(n_samples(0.6), 0.2))
    return finish(soft_clip(add(s, gain(rumble, 0.8)), 2.0))


@sfx("glass/metal clink")
def clink() -> list[float]:
    sec = 0.35
    out = [0.0] * n_samples(sec)
    for k, (f, g) in enumerate(((2650, 1.0), (4120, 0.6), (6300, 0.35), (1930, 0.4))):
        out = add(out, apply(sine(f * random.Random(k).uniform(0.995, 1.005), sec, g), env_exp(n_samples(sec), 0.05 + 0.02 * k)))
    return finish(add(out, apply(highpass(noise(0.02, 0.6, 4), 3000), env_exp(n_samples(0.02), 0.004))))


@sfx("wet-ish floppy landing (cloth/fish)")
def flop() -> list[float]:
    sec = 0.3
    n = n_samples(sec)
    a = apply(lowpass(noise(sec, 1.0, 5), sweep(1400, 200, 0.2)), env_exp(n, 0.05))
    b = apply(sine(sweep(220, 70, 0.15), sec), env_exp(n, 0.07))
    return finish(add(a, gain(b, 0.8)))


@sfx("wood/plastic crack")
def crack() -> list[float]:
    sec = 0.28
    n = n_samples(sec)
    rng = random.Random(6)
    out = [0.0] * n
    for k in range(5):
        st = 0.0 if k == 0 else rng.uniform(0.01, 0.12)
        burst = apply(bandpass(noise(0.08, 1.0, 10 + k), rng.uniform(900, 3200), 1.2), env_exp(n_samples(0.08), 0.012))
        place(out, burst, st, 1.0 - k * 0.12)
    body = apply(sine(sweep(300, 120, 0.1), 0.15), env_exp(n_samples(0.15), 0.03))
    return finish(add(out, gain(body, 0.5)))


@sfx("glass shatter: noise burst + descending glassy partials")
def shatter() -> list[float]:
    sec = 1.1
    n = n_samples(sec)
    rng = random.Random(7)
    out = apply(highpass(noise(sec, 1.0, 8), 1500), env_exp(n, 0.12))
    for k in range(14):
        f = rng.uniform(1800, 7500)
        st = rng.uniform(0.0, 0.45)
        d = rng.uniform(0.15, 0.5)
        part = apply(sine(sweep(f, f * rng.uniform(0.55, 0.85), d), d, 0.35), env_exp(n_samples(d), d * 0.3))
        place(out, part, st)
    # a few shards tinkling later
    for k in range(10):
        f = rng.uniform(3000, 9000)
        st = rng.uniform(0.35, 0.9)
        part = apply(sine(f, 0.12, 0.2), env_exp(n_samples(0.12), 0.03))
        place(out, part, st)
    return finish(reverb_lite(out, 0.2, 0.2))


@sfx("rubber duck / toy squeak")
def squeak() -> list[float]:
    sec = 0.3
    n = n_samples(sec)
    f = lambda t: 1100 + 700 * math.sin(math.pi * min(1.0, t / 0.25)) + 60 * math.sin(TWO_PI * 30 * t)
    a = apply(osc("square", f, sec, 0.6, duty=0.3), env_adsr(n, 0.01, 0.05, 0.7, 0.12))
    b = apply(sine(lambda t: f(t) * 2.0, sec, 0.3), env_adsr(n, 0.01, 0.05, 0.7, 0.12))
    return finish(lowpass(add(a, b), 5000))


@sfx("ignite: whoosh + crackle")
def ignite() -> list[float]:
    sec = 0.9
    n = n_samples(sec)
    whoosh = apply(bandpass(noise(sec, 1.0, 9), sweep(300, 2500, 0.4), 1.0), env_lin(n, [(0, 0), (0.15, 1), (0.5, 0.4), (0.9, 0)]))
    crk = [0.0] * n
    rng = random.Random(11)
    for k in range(30):
        st = rng.uniform(0.15, 0.85)
        p = apply(highpass(noise(0.02, 1.0, 100 + k), 2500), env_exp(n_samples(0.02), 0.004))
        place(crk, p, st, rng.uniform(0.3, 0.9))
    low = apply(lowpass(noise(sec, 1.0, 12), 250), env_lin(n, [(0, 0), (0.2, 0.8), (0.9, 0)]))
    return finish(add(whoosh, crk, gain(low, 0.7)))


@sfx("steam/extinguish hiss")
def hiss() -> list[float]:
    sec = 0.8
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 13), sweep(5000, 2200, 0.8), 0.8), env_lin(n, [(0, 0), (0.03, 1), (0.4, 0.6), (0.8, 0)]))
    return finish(a)


@sfx("duct tape rip-zip")
def tape() -> list[float]:
    sec = 0.55
    n = n_samples(sec)
    base = noise(sec, 1.0, 14)
    # ratchet-y amplitude modulation: rip is a series of micro-tears speeding up
    am = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        rate = 60 + 400 * t
        ph += rate / SR
        am[i] = 0.5 + 0.5 * (1.0 if (ph % 1.0) < 0.35 else 0.1)
    s = apply(bandpass(base, sweep(1200, 3800, 0.5), 1.5), am)
    return finish(apply(s, env_lin(n, [(0, 0), (0.02, 1), (0.45, 1), (0.55, 0)])))


def _knock(f: float, sec: float = 0.12, seed: int = 0) -> list[float]:
    n = n_samples(sec)
    a = apply(sine(sweep(f * 1.6, f, 0.03), sec), env_exp(n, 0.02))
    b = apply(bandpass(noise(sec, 1.0, seed), f * 3, 1.0), env_exp(n, 0.008))
    return add(a, gain(b, 0.8))


@sfx("hammering a nail: 3 metallic knocks")
def hammer_nail() -> list[float]:
    out = [0.0] * n_samples(0.7)
    for k in range(3):
        kn = _knock(420 + k * 40, 0.14, 20 + k)
        ring = apply(sine(3200 + k * 150, 0.14, 0.3), env_exp(n_samples(0.14), 0.03))
        place(out, add(kn, ring), k * 0.2)
    return finish(soft_clip(out, 1.4))


@sfx("locked lid rattle")
def locked_rattle() -> list[float]:
    out = [0.0] * n_samples(0.5)
    rng = random.Random(21)
    for k in range(6):
        kn = _knock(rng.uniform(600, 900), 0.06, 30 + k)
        place(out, kn, k * 0.065 + rng.uniform(0, 0.01), rng.uniform(0.6, 1.0))
    return finish(out)


@sfx("zipper opening")
def zip_open() -> list[float]:
    sec = 0.45
    n = n_samples(sec)
    base = noise(sec, 1.0, 22)
    am = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        ph += (90 + 260 * math.sin(math.pi * t / sec)) / SR
        am[i] = 1.0 if (ph % 1.0) < 0.5 else 0.15
    s = apply(bandpass(base, sweep(1800, 3200, sec), 2.0), am)
    return finish(apply(s, env_lin(n, [(0, 0), (0.03, 1), (0.4, 1), (0.45, 0)])))


@sfx("box lid opening (cardboard creak)")
def lid_open() -> list[float]:
    sec = 0.4
    n = n_samples(sec)
    creak = apply(osc("saw", lambda t: 180 + 90 * math.sin(TWO_PI * 7 * t) + 200 * t, sec, 0.5), env_lin(n, [(0, 0), (0.05, 1), (0.3, 0.6), (0.4, 0)]))
    creak = bandpass(creak, 900, 0.7)
    paper = apply(lowpass(noise(sec, 1.0, 23), 2000), env_lin(n, [(0, 0), (0.05, 0.6), (0.4, 0)]))
    return finish(add(creak, gain(paper, 0.7)))


@sfx("wooden drawer sliding + stop")
def drawer() -> list[float]:
    sec = 0.5
    n = n_samples(sec)
    slide = apply(lowpass(noise(sec, 1.0, 24), 900), env_lin(n, [(0, 0), (0.05, 0.6), (0.35, 0.6), (0.4, 0)]))
    stop = _knock(220, 0.12, 25)
    out = list(slide)
    place(out, stop, 0.36, 1.2)
    return finish(out)


@sfx("padlock click open")
def unlock() -> list[float]:
    out = [0.0] * n_samples(0.4)
    place(out, _knock(1400, 0.05, 26), 0.0, 0.7)
    place(out, _knock(900, 0.08, 27), 0.09, 1.0)
    ring = apply(sine(2400, 0.25, 0.3), env_exp(n_samples(0.25), 0.05))
    place(out, ring, 0.09)
    return finish(out)


@sfx("cartoon gulp")
def gulp() -> list[float]:
    sec = 0.35
    n = n_samples(sec)
    f = lambda t: 260 - 140 * min(1.0, t / 0.2) + (200 if t > 0.22 else 0)
    a = apply(osc("saw", f, sec, 0.6), env_lin(n, [(0, 0), (0.03, 1), (0.2, 0.7), (0.22, 0.2), (0.28, 0.8), (0.35, 0)]))
    a = formant(a, (500, 1100), 4.0)
    return finish(lowpass(a, 3000))


@sfx("cork pop")
def cork() -> list[float]:
    sec = 0.25
    n = n_samples(sec)
    pop = apply(sine(sweep(600, 180, 0.08), sec), env_exp(n, 0.03))
    air = apply(bandpass(noise(sec, 1.0, 28), 1200, 1.0), env_exp(n, 0.02))
    return finish(add(pop, gain(air, 0.6)))


@sfx("gentle tap")
def tap() -> list[float]:
    return finish(_knock(700, 0.1, 29))


@sfx("gag: loud pop + comedic boing")
def gag_bang() -> list[float]:
    out = [0.0] * n_samples(0.9)
    bang = apply(add(sine(sweep(400, 60, 0.1), 0.25), gain(lowpass(noise(0.25, 1.0, 30), 3000), 0.8)), env_exp(n_samples(0.25), 0.05))
    place(out, soft_clip(bang, 2.5), 0.0)
    # boing: wobbling pitch
    sec = 0.7
    f = lambda t: 320 * (1 + 0.45 * math.exp(-4 * t) * math.sin(TWO_PI * 11 * t)) * (1 - 0.3 * t)
    boing = apply(add(osc("square", f, sec, 0.4, duty=0.4), sine(lambda t: f(t) * 2, sec, 0.2)), env_exp(n_samples(sec), 0.2))
    place(out, lowpass(boing, 3500), 0.12)
    return finish(out)


@sfx("hand grab / rustle")
def grab() -> list[float]:
    sec = 0.18
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 31), 1500, 0.8), env_lin(n, [(0, 0), (0.02, 1), (0.1, 0.4), (0.18, 0)]))
    return finish(add(a, gain(_knock(300, 0.1, 32), 0.4)))


@sfx("throw whoosh")
def whoosh() -> list[float]:
    sec = 0.4
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 33), sweep(500, 2600, 0.25), 0.9), env_lin(n, [(0, 0), (0.12, 1), (0.4, 0)]))
    return finish(a)


@sfx("wet slap / squelch")
def squelch() -> list[float]:
    sec = 0.35
    n = n_samples(sec)
    slap = apply(lowpass(noise(sec, 1.0, 34), sweep(3000, 400, 0.2)), env_exp(n, 0.04))
    wet = [0.0] * n
    rng = random.Random(35)
    for k in range(8):
        f = rng.uniform(300, 900)
        blip = apply(sine(sweep(f, f * 0.5, 0.05), 0.06, 0.5), env_exp(n_samples(0.06), 0.015))
        place(wet, blip, rng.uniform(0.02, 0.25))
    return finish(add(slap, wet))


@sfx("liquid splash")
def splash() -> list[float]:
    sec = 0.6
    n = n_samples(sec)
    body = apply(bandpass(noise(sec, 1.0, 36), sweep(800, 2500, 0.3), 0.7), env_lin(n, [(0, 0), (0.02, 1), (0.25, 0.5), (0.6, 0)]))
    drops = [0.0] * n
    rng = random.Random(37)
    for k in range(12):
        f = rng.uniform(900, 2400)
        d = apply(sine(sweep(f, f * 1.6, 0.05), 0.06, 0.4), env_exp(n_samples(0.06), 0.015))
        place(drops, d, rng.uniform(0.1, 0.5))
    return finish(add(body, drops))


@sfx("pouring liquid")
def pour() -> list[float]:
    sec = 0.9
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 38), lambda t: 900 + 500 * math.sin(TWO_PI * 3 * t) + 400 * t, 1.2), env_lin(n, [(0, 0), (0.1, 0.9), (0.7, 1), (0.9, 0)]))
    bubbles = [0.0] * n
    rng = random.Random(39)
    for k in range(20):
        f = rng.uniform(500, 1500)
        b = apply(sine(sweep(f, f * 1.8, 0.04), 0.05, 0.3), env_exp(n_samples(0.05), 0.012))
        place(bubbles, b, rng.uniform(0.05, 0.85))
    return finish(add(a, bubbles))


@sfx("item into pocket (cloth + small thump)")
def pocket() -> list[float]:
    sec = 0.25
    n = n_samples(sec)
    cloth_ = apply(bandpass(noise(sec, 1.0, 40), 2200, 0.8), env_lin(n, [(0, 0), (0.03, 1), (0.25, 0)]))
    return finish(add(cloth_, gain(_knock(200, 0.1, 41), 0.5)))


@sfx("cloth rustle")
def cloth() -> list[float]:
    sec = 0.35
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 42), lambda t: 1800 + 900 * math.sin(TWO_PI * 5 * t), 0.7), env_lin(n, [(0, 0), (0.05, 0.8), (0.2, 1), (0.35, 0)]))
    return finish(a)


# ------------------------------------------------------------------ money / UI

def _bell(f: float, sec: float, g: float = 1.0) -> list[float]:
    n = n_samples(sec)
    return apply(add(sine(f, sec, 0.6 * g), sine(f * 2.76, sec, 0.2 * g), sine(f * 5.4, sec, 0.08 * g)), env_exp(n, sec * 0.3))


@sfx("coin: bright ding arpeggio")
def coin() -> list[float]:
    out = [0.0] * n_samples(0.6)
    for k, f in enumerate((note("E6"), note("G6"), note("B6"))):
        place(out, _bell(f, 0.4), k * 0.06)
    return finish(out)


@sfx("coin loss: sad descending")
def coin_loss() -> list[float]:
    out = [0.0] * n_samples(0.8)
    for k, f in enumerate((note("E5"), note("C5"), note("A4"), note("F4"))):
        s = apply(osc("square", f, 0.22, 0.4, duty=0.35), env_adsr(n_samples(0.22), 0.005, 0.05, 0.6, 0.08))
        place(out, lowpass(s, 3000), k * 0.15)
    return finish(out)


@sfx("cash register ka-ching")
def cash_register() -> list[float]:
    out = [0.0] * n_samples(1.0)
    place(out, _knock(600, 0.08, 43), 0.0, 0.9)
    place(out, _knock(500, 0.08, 44), 0.1, 0.9)
    ring = _bell(note("A6"), 0.7, 1.0)
    place(out, ring, 0.18)
    place(out, _bell(note("E7"), 0.5, 0.5), 0.18)
    drawer_ = apply(lowpass(noise(0.2, 1.0, 45), 1500), env_lin(n_samples(0.2), [(0, 0), (0.05, 0.7), (0.2, 0)]))
    place(out, drawer_, 0.25, 0.5)
    return finish(out)


@sfx("fanfare: short major triad blast")
def fanfare() -> list[float]:
    sec = 1.3
    out = [0.0] * n_samples(sec)
    seq = [(("C5",), 0.0, 0.12), (("C5",), 0.14, 0.12), (("C5",), 0.28, 0.12), (("C5", "E5", "G5", "C6"), 0.45, 0.8)]
    for names, st, d in seq:
        for nm in names:
            f = note(nm)
            s = apply(add(osc("saw", f, d, 0.4), osc("square", f * 1.002, d, 0.25)), env_adsr(n_samples(d), 0.01, 0.05, 0.8, 0.15))
            place(out, lowpass(s, 4000), st)
    return finish(soft_clip(out, 1.6))


@sfx("wrong! buzzer")
def buzzer() -> list[float]:
    sec = 0.5
    n = n_samples(sec)
    a = apply(add(osc("square", 110, sec, 0.5), osc("saw", 113, sec, 0.4)), env_adsr(n, 0.005, 0.05, 0.9, 0.05))
    return finish(lowpass(a, 1800))


@sfx("sonar ping / map pin")
def pin() -> list[float]:
    sec = 0.7
    n = n_samples(sec)
    a = apply(sine(sweep(1400, 1150, 0.5), sec, 0.8), env_exp(n, 0.18))
    return finish(add(a, gain(_bell(2400, 0.3, 0.3), 1.0)))


@sfx("fabric rip")
def rip() -> list[float]:
    sec = 0.4
    n = n_samples(sec)
    base = noise(sec, 1.0, 46)
    am = [0.0] * n
    ph = 0.0
    rng = random.Random(47)
    for i in range(n):
        ph += (150 + 200 * (i / n)) / SR
        am[i] = 1.0 if (ph % 1.0) < 0.6 else 0.3 + rng.uniform(0, 0.2)
    s = apply(bandpass(base, sweep(900, 2600, sec), 1.0), am)
    return finish(apply(s, env_lin(n, [(0, 0), (0.02, 1), (0.3, 1), (0.4, 0)])))


@sfx("oof! hit grunt")
def oof() -> list[float]:
    sec = 0.32
    n = n_samples(sec)
    f = lambda t: 150 - 60 * min(1.0, t / 0.3)
    src = osc("saw", f, sec, 0.8)
    v = formant(src, (600, 1000, 2500), 5.0, (1.0, 0.6, 0.25))
    v = apply(v, env_lin(n, [(0, 0), (0.02, 1), (0.15, 0.8), (0.32, 0)]))
    breath = apply(bandpass(noise(sec, 1.0, 48), 1500, 0.8), env_lin(n, [(0, 0), (0.01, 0.4), (0.32, 0)]))
    return finish(add(v, gain(breath, 0.5)))


@sfx("comedic falling scream (synthetic Wilhelm-alike)")
def death_wilhelm() -> list[float]:
    sec = 1.4
    n = n_samples(sec)
    # pitch: jump up, hold with vibrato, then fall — "aaAAaaah!"
    def f(t):
        base = 330 * (1 + 0.6 * min(1.0, t / 0.12))
        if t > 0.7:
            base *= 1.0 - 0.55 * ((t - 0.7) / 0.7) ** 1.3
        return base * (1 + 0.04 * math.sin(TWO_PI * 6.5 * t))
    src = add(osc("saw", f, sec, 0.7), osc("square", lambda t: f(t) * 1.005, sec, 0.25, duty=0.3))
    # formants slide "a" → "o" as he falls
    fm = [0.0] * n
    for k, (fa, fb, g) in enumerate(((800, 500, 1.0), (1200, 900, 0.7), (2600, 2400, 0.3))):
        fm = add(fm, gain(biquad(src, "bp", sweep(fa, fb, sec, "lin"), 5.0), g))
    env = env_lin(n, [(0, 0), (0.05, 1), (0.9, 0.9), (1.4, 0)])
    v = apply(fm, env)
    return finish(soft_clip(gain(v, 1.5), 1.8))


@sfx("2-tone police siren")
def siren() -> list[float]:
    sec = 2.0
    n = n_samples(sec)
    f = lambda t: 620 if (t % 0.5) < 0.25 else 470
    a = add(osc("square", f, sec, 0.5, duty=0.45), sine(lambda t: f(t) * 2, sec, 0.2))
    a = lowpass(a, 3500)
    return finish(apply(a, env_lin(n, [(0, 0), (0.05, 1), (1.85, 1), (2.0, 0)])))


@sfx("metal door slam")
def door_slam() -> list[float]:
    sec = 0.8
    n = n_samples(sec)
    boom = apply(sine(sweep(140, 45, 0.15), sec), env_exp(n, 0.12))
    metal = [0.0] * n
    for k, f in enumerate((730, 1180, 1960, 2870)):
        metal = add(metal, apply(sine(f, sec, 0.3 / (k + 1)), env_exp(n, 0.25 - k * 0.04)))
    click = apply(noise(0.05, 1.0, 49), env_exp(n_samples(0.05), 0.008))
    out = add(gain(boom, 1.0), metal)
    place(out, click, 0.0, 0.9)
    return finish(soft_clip(out, 1.6))


@sfx("roll-up door rumble")
def door_roll() -> list[float]:
    sec = 1.6
    n = n_samples(sec)
    rumble = apply(lowpass(noise(sec, 1.0, 50), 220), env_lin(n, [(0, 0), (0.1, 1), (1.3, 1), (1.6, 0)]))
    rattle = noise(sec, 1.0, 51)
    am = [0.6 + 0.4 * math.sin(TWO_PI * 18 * (i / SR)) for i in range(n)]
    rattle = apply(bandpass(rattle, 1400, 1.0), am)
    rattle = apply(rattle, env_lin(n, [(0, 0), (0.1, 0.5), (1.3, 0.6), (1.6, 0)]))
    stop = _knock(150, 0.2, 52)
    out = add(rumble, rattle)
    place(out, stop, 1.35, 1.5)
    return finish(soft_clip(out, 1.5))


@sfx("achievement sparkle arpeggio")
def achievement() -> list[float]:
    out = [0.0] * n_samples(1.6)
    seq = ("C5", "E5", "G5", "C6", "E6", "G6")
    for k, nm in enumerate(seq):
        place(out, _bell(note(nm), 0.9, 0.8), k * 0.08)
    place(out, _bell(note("C7"), 1.2, 0.5), 0.5)
    shimmer = apply(highpass(noise(1.0, 1.0, 53), 6000), env_lin(n_samples(1.0), [(0, 0), (0.3, 0.15), (1.0, 0)]))
    place(out, shimmer, 0.3)
    return finish(reverb_lite(out, 0.25, 0.3))


@sfx("generic 'aah!' shout burst")
def shout_generic() -> list[float]:
    sec = 0.6
    n = n_samples(sec)
    f = lambda t: 240 * (1 + 0.25 * math.sin(math.pi * min(1.0, t / 0.5))) * (1 + 0.03 * math.sin(TWO_PI * 7 * t))
    src = osc("saw", f, sec, 0.8)
    v = formant(src, (750, 1250, 2700), 5.0, (1.0, 0.7, 0.3))
    v = apply(v, env_lin(n, [(0, 0), (0.04, 1), (0.45, 0.9), (0.6, 0)]))
    return finish(soft_clip(gain(v, 1.5), 1.6))


@sfx("fire crackle loop 2 s", loop=True)
def fire_loop() -> list[float]:
    sec = 2.0
    n = n_samples(sec)
    roar = lowpass(noise(sec, 1.0, 54), lambda t: 300 + 150 * math.sin(TWO_PI * 1.3 * t))
    out = gain(roar, 0.8)
    rng = random.Random(55)
    for k in range(70):
        st = rng.uniform(0, sec)
        d = rng.uniform(0.008, 0.03)
        p = apply(highpass(noise(d, 1.0, 200 + k), rng.uniform(1500, 4000)), env_exp(n_samples(d), d * 0.25))
        place(out, p, st, rng.uniform(0.3, 1.0), wrap=True)
    return finish_loop(out, -3.0, 0.08)


# ------------------------------------------------------------------ auction

@sfx("auction gavel: sharp wood knock x3")
def hammer() -> list[float]:
    out = [0.0] * n_samples(0.9)
    for k in range(3):
        kn = _knock(260 - k * 10, 0.15, 60 + k)
        snap = apply(bandpass(noise(0.03, 1.0, 70 + k), 2500, 1.0), env_exp(n_samples(0.03), 0.006))
        place(out, add(kn, snap), k * 0.22, 1.0 + 0.1 * k)
    return finish(soft_clip(reverb_lite(out, 0.15, 0.15), 1.4))


@sfx("bidding paddle whoosh")
def paddle_up() -> list[float]:
    sec = 0.3
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 56), sweep(800, 3000, 0.2), 1.0), env_lin(n, [(0, 0), (0.08, 1), (0.3, 0)]))
    return finish(a)


def _babble(sec: float, seed: int, voices: int, f_lo: float, f_hi: float, level: float) -> list[float]:
    """Fake crowd: several formant-filtered, syllable-modulated saw voices."""
    n = n_samples(sec)
    out = [0.0] * n
    rng = random.Random(seed)
    for v in range(voices):
        base = rng.uniform(f_lo, f_hi)
        rate = rng.uniform(3.5, 6.5)
        off = rng.uniform(0, 10)
        f = lambda t, b=base, r=rate, o=off: b * (1 + 0.08 * math.sin(TWO_PI * 0.7 * (t + o)) + 0.03 * math.sin(TWO_PI * r * 0.5 * (t + o)))
        src = osc("saw", f, sec, 0.3)
        fa = rng.uniform(500, 900)
        fb = rng.uniform(1100, 1800)
        src = formant(src, (fa, fb), 4.0, (1.0, 0.6))
        am = [0.0] * n
        for i in range(n):
            t = i / SR + off
            s = math.sin(TWO_PI * rate * t)
            am[i] = max(0.0, s) ** 1.5
        # each voice talks in bursts (not constantly)
        talk = [0.0] * n
        pos = 0.0
        while pos < sec:
            d = rng.uniform(0.4, 1.4)
            on = rng.random() < 0.65
            a, b = int(pos * SR), min(n, int((pos + d) * SR))
            if on:
                for i in range(a, b):
                    talk[i] = 1.0
            pos += d
        talk = lowpass(talk, 8.0)
        out = add(out, gain(mul(mul(src, am), talk), level))
    return out


@sfx("crowd murmur loop 4 s", loop=True)
def crowd_murmur() -> list[float]:
    sec = 4.0
    bab = _babble(sec, 57, 10, 100, 240, 1.0)
    wash = gain(bandpass(noise(sec, 1.0, 58), 900, 0.5), 0.35)
    return finish_loop(add(bab, wash), -4.0, 0.25)


@sfx("crowd gasp")
def crowd_gasp() -> list[float]:
    sec = 0.9
    n = n_samples(sec)
    intake = apply(bandpass(noise(sec, 1.0, 59), sweep(600, 2200, 0.5), 0.6), env_lin(n, [(0, 0), (0.35, 1), (0.6, 0.3), (0.9, 0)]))
    voices = _babble(sec, 60, 6, 180, 300, 0.6)
    voices = apply(voices, env_lin(n, [(0, 0), (0.3, 1), (0.9, 0)]))
    return finish(add(intake, voices))


@sfx("crowd laugh: rhythmic bursts")
def crowd_laugh() -> list[float]:
    sec = 1.8
    n = n_samples(sec)
    out = [0.0] * n
    rng = random.Random(61)
    for v in range(7):
        base = rng.uniform(150, 320)
        rate = rng.uniform(4.5, 7.0)
        off = rng.uniform(0, 0.15)
        f = lambda t, b=base: b * (1 - 0.15 * t) * (1 + 0.05 * math.sin(TWO_PI * 5 * t))
        src = formant(osc("saw", f, sec, 0.4), (rng.uniform(600, 900), rng.uniform(1200, 1700)), 5.0, (1.0, 0.5))
        am = [max(0.0, math.sin(TWO_PI * rate * (i / SR - off))) ** 2 for i in range(n)]
        env = env_lin(n, [(0, 0), (0.1, 1), (1.2, 0.8), (1.8, 0)])
        out = add(out, mul(mul(src, am), env))
    return finish(soft_clip(out, 1.5))


@sfx("bid registered ding")
def bid_ding() -> list[float]:
    out = [0.0] * n_samples(0.5)
    place(out, _bell(note("A5"), 0.45), 0.0)
    place(out, _bell(note("E6"), 0.35, 0.6), 0.05)
    return finish(out)


# ------------------------------------------------------------------ casino

@sfx("roulette wheel ratchet clicks loop 3 s", loop=True)
def wheel_spin() -> list[float]:
    sec = 3.0
    n = n_samples(sec)
    out = [0.0] * n
    t = 0.0
    k = 0
    while t < sec:
        c = _knock(2600 + (k % 3) * 200, 0.02, 80 + (k % 5))
        place(out, c, t, 0.9, wrap=True)
        t += 0.045
        k += 1
    whir = gain(lowpass(noise(sec, 1.0, 62), 500), 0.25)
    return finish_loop(add(out, whir), -3.0, 0.03)


@sfx("roulette ball settles")
def wheel_stop() -> list[float]:
    out = [0.0] * n_samples(1.5)
    t = 0.0
    gap = 0.05
    k = 0
    while t < 1.2:
        place(out, _knock(2400, 0.03, 90 + k), t, 0.9)
        t += gap
        gap *= 1.22
        k += 1
    place(out, _knock(1200, 0.1, 99), t, 1.0)
    place(out, _bell(note("C6"), 0.5, 0.6), t + 0.02)
    return finish(out)


@sfx("drink glug-glug")
def drink_glug() -> list[float]:
    out = [0.0] * n_samples(0.9)
    for k in range(3):
        g = gulp()
        place(out, g, k * 0.27, 0.9 - 0.15 * k)
    return finish(out)


# ------------------------------------------------------------------ car / cops

@sfx("car engine sawtooth rumble loop 2 s", loop=True)
def car_engine_loop() -> list[float]:
    sec = 2.0
    f = lambda t: 42 * (1 + 0.04 * math.sin(TWO_PI * 1.0 * t)) * (1 + 0.01 * math.sin(TWO_PI * 13.0 * t))
    a = osc("saw", f, sec, 0.6)
    b = osc("square", lambda t: f(t) * 2.0, sec, 0.25, duty=0.3)
    rough = gain(lowpass(noise(sec, 1.0, 63), 400), 0.35)
    mixd = soft_clip(add(a, b, rough), 2.2)
    return finish_loop(lowpass(mixd, 900), -3.0, 0.15)


@sfx("cheap car horn")
def car_horn() -> list[float]:
    sec = 0.7
    n = n_samples(sec)
    a = add(osc("square", 370, sec, 0.4, duty=0.4), osc("square", 466, sec, 0.4, duty=0.4), osc("saw", 185, sec, 0.3))
    a = lowpass(a, 2500)
    return finish(apply(a, env_adsr(n, 0.02, 0.05, 0.9, 0.1)))


@sfx("tire skid")
def tire_skid() -> list[float]:
    sec = 1.0
    n = n_samples(sec)
    f = lambda t: 1900 + 300 * math.sin(TWO_PI * 9 * t) - 500 * t
    a = biquad(noise(sec, 1.0, 64), "bp", f, 8.0)
    a = add(a, gain(osc("saw", lambda t: f(t) / 2.5, sec, 0.3), 1.0))
    return finish(apply(a, env_lin(n, [(0, 0), (0.05, 1), (0.8, 0.9), (1.0, 0)])))


@sfx("bumper boing")
def bump_boing() -> list[float]:
    sec = 0.6
    n = n_samples(sec)
    f = lambda t: 180 * (1 + 0.5 * math.exp(-5 * t) * math.sin(TWO_PI * 14 * t))
    a = apply(add(sine(f, sec, 0.6), osc("tri", lambda t: f(t) * 2, sec, 0.3)), env_exp(n, 0.18))
    place(a, _knock(250, 0.1, 65), 0.0, 0.8)
    return finish(a)


@sfx("handcuffs ratchet")
def handcuffs() -> list[float]:
    out = [0.0] * n_samples(0.6)
    t = 0.0
    k = 0
    while t < 0.45:
        c = add(_knock(3500 - k * 40, 0.02, 100 + k), gain(_bell(4200, 0.05, 0.3), 1.0))
        place(out, c, t, 0.9)
        t += 0.032 - k * 0.0008
        k += 1
    place(out, _knock(1800, 0.1, 120), t, 1.0)
    return finish(out)


@sfx("jail door slam + rattle")
def jail_door() -> list[float]:
    sec = 1.4
    n = n_samples(sec)
    out = [0.0] * n
    slam = door_slam()
    place(out, slam, 0.0, 0.9)
    for k, f in enumerate((850, 1400, 2300)):
        ring = apply(sine(f, 1.0, 0.25), env_exp(n_samples(1.0), 0.35))
        place(out, ring, 0.0)
    rng = random.Random(66)
    for k in range(6):
        place(out, _knock(1300 + rng.uniform(-100, 100), 0.05, 130 + k), 0.35 + k * 0.06, 0.5 - k * 0.06)
    return finish(reverb_lite(out, 0.35, 0.3))


@sfx("police radio: static blips")
def police_radio() -> list[float]:
    sec = 1.1
    n = n_samples(sec)
    out = [0.0] * n
    place(out, apply(bandpass(noise(0.06, 1.0, 67), 1800, 1.0), env_exp(n_samples(0.06), 0.02)), 0.0)
    # garbled "voice": bitcrushed bandpassed saw with syllable AM
    v = osc("saw", lambda t: 190 + 40 * math.sin(TWO_PI * 3 * t), 0.7, 0.6)
    v = formant(v, (700, 1400), 3.0)
    am = [max(0.0, math.sin(TWO_PI * 6 * (i / SR))) ** 1.5 for i in range(n_samples(0.7))]
    v = bitcrush(mul(v, am), 5)
    v = bandpass(v, 1500, 0.7)
    place(out, v, 0.12, 0.9)
    stat = gain(bandpass(noise(0.75, 1.0, 68), 2200, 0.6), 0.12)
    place(out, stat, 0.1)
    place(out, apply(bandpass(noise(0.05, 1.0, 69), 2200, 1.0), env_exp(n_samples(0.05), 0.015)), 0.88)
    place(out, _bell(1900, 0.15, 0.4), 0.95)
    return finish(out)


@sfx("camera shutter click")
def camera_shutter() -> list[float]:
    out = [0.0] * n_samples(0.3)
    place(out, _knock(2200, 0.03, 70), 0.0, 0.8)
    place(out, apply(bandpass(noise(0.08, 1.0, 71), 3000, 0.8), env_exp(n_samples(0.08), 0.02)), 0.02, 0.6)
    place(out, _knock(1600, 0.05, 72), 0.11, 1.0)
    return finish(out)


@sfx("phone beep")
def phone_beep() -> list[float]:
    out = [0.0] * n_samples(0.5)
    for k in range(2):
        b = apply(add(sine(1200, 0.12, 0.6), sine(1600, 0.12, 0.3)), env_adsr(n_samples(0.12), 0.005, 0.02, 0.9, 0.03))
        place(out, b, k * 0.18)
    return finish(out)


# ------------------------------------------------------------------ haggle mini-game

@sfx("haggle meter tick")
def haggle_tick() -> list[float]:
    return finish(_knock(1800, 0.05, 73))


@sfx("haggle hit (success blip)")
def haggle_hit() -> list[float]:
    out = [0.0] * n_samples(0.4)
    place(out, _bell(note("C6"), 0.3, 0.8), 0.0)
    place(out, _bell(note("G6"), 0.3, 0.6), 0.06)
    return finish(out)


@sfx("haggle miss (dull thunk)")
def haggle_miss() -> list[float]:
    sec = 0.3
    n = n_samples(sec)
    a = apply(osc("square", sweep(220, 150, 0.2), sec, 0.5, duty=0.4), env_adsr(n, 0.005, 0.05, 0.6, 0.08))
    return finish(lowpass(a, 1500))


# ------------------------------------------------------------------ janitor

@sfx("broom sweep")
def broom_sweep() -> list[float]:
    sec = 0.5
    n = n_samples(sec)
    a = apply(bandpass(noise(sec, 1.0, 74), sweep(1200, 3500, 0.35), 0.6), env_lin(n, [(0, 0), (0.12, 1), (0.3, 0.7), (0.5, 0)]))
    return finish(a)


@sfx("water spray loop 1.5 s", loop=True)
def water_spray() -> list[float]:
    sec = 1.5
    a = bandpass(noise(sec, 1.0, 75), lambda t: 2800 + 300 * math.sin(TWO_PI * 2.0 * t), 0.7)
    b = gain(lowpass(noise(sec, 1.0, 76), 600), 0.3)
    return finish_loop(add(a, b), -3.0, 0.1)


@sfx("safe unlock: dial ticks + heavy bolt")
def unlock_safe() -> list[float]:
    out = [0.0] * n_samples(1.3)
    rng = random.Random(77)
    t = 0.0
    k = 0
    while t < 0.7:
        place(out, _knock(2000 + rng.uniform(-100, 100), 0.03, 140 + k), t, 0.7)
        t += rng.uniform(0.06, 0.11)
        k += 1
    bolt = add(_knock(180, 0.3, 150), gain(_thump(120, 60, 0.3, 0.08, 0.4, 151), 1.0))
    place(out, bolt, 0.8, 1.3)
    place(out, _bell(1500, 0.4, 0.3), 0.82)
    return finish(soft_clip(out, 1.4))


# ------------------------------------------------------------------ critters

@sfx("mouse squeak")
def mouse_squeak() -> list[float]:
    out = [0.0] * n_samples(0.45)
    for k in range(2):
        sec = 0.15
        f = lambda t, k=k: (3200 + 500 * k) * (1 + 0.25 * math.sin(math.pi * t / sec))
        s = apply(sine(f, sec, 0.7), env_adsr(n_samples(sec), 0.01, 0.03, 0.8, 0.06))
        place(out, s, k * 0.2)
    return finish(out)


@sfx("hamster wheel loop", loop=True)
def hamster_wheel() -> list[float]:
    sec = 1.2
    n = n_samples(sec)
    out = [0.0] * n
    t = 0.0
    k = 0
    while t < sec:
        place(out, _knock(1500 + (k % 2) * 300, 0.03, 160 + (k % 4)), t, 0.6, wrap=True)
        t += 0.1
        k += 1
    squeak_ = osc("saw", lambda t: 2400 + 200 * math.sin(TWO_PI * 5.0 * t), sec, 0.25)
    am = [0.5 + 0.5 * math.sin(TWO_PI * 5.0 * (i / SR)) for i in range(n)]
    squeak_ = bandpass(mul(squeak_, am), 2500, 3.0)
    out = add(out, squeak_)
    return finish_loop(out, -3.0, 0.05)


# ------------------------------------------------------------------ ambience

@sfx("port ambience: gulls + water, loop 4 s", loop=True)
def ambient_port() -> list[float]:
    sec = 4.0
    n = n_samples(sec)
    water = lowpass(noise(sec, 1.0, 78), lambda t: 350 + 200 * math.sin(TWO_PI * 0.25 * t))
    water = gain(water, 0.9)
    lap = gain(bandpass(noise(sec, 1.0, 79), lambda t: 1200 + 600 * math.sin(TWO_PI * 0.5 * t), 0.8), 0.25)
    out = add(water, lap)
    rng = random.Random(80)
    for k in range(5):
        st = rng.uniform(0, sec)
        d = rng.uniform(0.25, 0.45)
        base = rng.uniform(1400, 2200)
        f = lambda t, b=base, d=d: b * (1 + 0.35 * math.sin(math.pi * min(1.0, t / d))) * (1 + 0.06 * math.sin(TWO_PI * 22 * t))
        g = apply(add(osc("saw", f, d, 0.35), sine(f, d, 0.3)), env_lin(n_samples(d), [(0, 0), (0.05, 1), (d * 0.8, 0.7), (d, 0)]))
        g = bandpass(g, base * 1.3, 1.5)
        place(out, g, st, rng.uniform(0.35, 0.7), wrap=True)
    return finish_loop(out, -6.0, 0.3)


@sfx("storage unit hum loop 3 s", loop=True)
def ambient_storage() -> list[float]:
    sec = 3.0
    hum = add(sine(50, sec, 0.5), sine(100, sec, 0.25), sine(150, sec, 0.1), osc("saw", 100.3, sec, 0.06))
    flick = gain(bandpass(noise(sec, 1.0, 81), 4000, 3.0), 0.05)
    am = [0.85 + 0.15 * math.sin(TWO_PI * 0.4 * (i / SR)) for i in range(n_samples(sec))]
    return finish_loop(mul(add(hum, flick), am), -8.0, 0.3)


@sfx("desert day: warm wind + distant birds + cicadas, loop 6 s", loop=True)
def ambient_desert_day() -> list[float]:
    sec = 6.0
    n = n_samples(sec)
    wind = bandpass(noise(sec, 1.0, 82), lambda t: 420 + 180 * math.sin(TWO_PI * 0.18 * t), 0.7)
    dry = gain(highpass(noise(sec, 1.0, 83), 2800), 0.12)
    out = add(gain(wind, 0.85), dry)
    rng = random.Random(84)
    for k in range(7):
        st = rng.uniform(0, sec)
        d = rng.uniform(0.06, 0.14)
        base = rng.uniform(2200, 3800)
        f = lambda t, b=base, d=d: b * (1 + 0.18 * math.sin(math.pi * min(1.0, t / d)))
        chirp = apply(sine(f, d, 0.55), env_lin(n_samples(d), [(0, 0), (0.01, 1), (d * 0.6, 0.5), (d, 0)]))
        chirp = bandpass(chirp, base, 2.0)
        place(out, chirp, st, rng.uniform(0.18, 0.35), wrap=True)
    cic = bandpass(noise(sec, 1.0, 85), 5200, 6.0)
    am = [
        0.35 + 0.65 * (0.5 + 0.5 * math.sin(TWO_PI * 48 * (i / SR))) * (0.7 + 0.3 * math.sin(TWO_PI * 0.35 * (i / SR)))
        for i in range(n)
    ]
    out = add(out, gain(apply(cic, am), 0.18))
    return finish_loop(out, -13.0, 0.35)


@sfx("night: crickets + low wind + distant dog, loop 6 s", loop=True)
def ambient_night() -> list[float]:
    sec = 6.0
    n = n_samples(sec)
    wind = gain(lowpass(noise(sec, 1.0, 86), lambda t: 220 + 80 * math.sin(TWO_PI * 0.15 * t)), 0.55)
    hum = add(sine(55, sec, 0.18), sine(110, sec, 0.07))
    out = add(wind, hum)
    crick = bandpass(noise(sec, 1.0, 87), 4000, 4.0)
    am = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        rate = 2.5 + 0.18 * math.sin(TWO_PI * 0.11 * t)
        ph += rate / SR
        am[i] = 1.0 if (ph % 1.0) < 0.18 else 0.04
    out = add(out, gain(apply(crick, am), 0.45))
    bark_sec = 0.35
    bark_f = lambda t: 280 * (1 + 0.35 * math.sin(math.pi * min(1.0, t / 0.18))) * (1 - 0.25 * t)
    bark = apply(
        formant(osc("saw", bark_f, bark_sec, 0.5), (500, 1100), 4.0, (1.0, 0.5)),
        env_lin(n_samples(bark_sec), [(0, 0), (0.03, 1), (0.18, 0.7), (0.35, 0)]),
    )
    place(out, lowpass(bark, 1400), 2.4, 0.28, wrap=True)
    return finish_loop(out, -13.0, 0.35)


@sfx("town: distant road hum + car pass + horn, loop 5 s", loop=True)
def ambient_town() -> list[float]:
    sec = 5.0
    n = n_samples(sec)
    road = lowpass(noise(sec, 1.0, 88), 280)
    swell = [0.55 + 0.45 * (0.5 + 0.5 * math.sin(TWO_PI * 0.22 * (i / SR))) for i in range(n)]
    out = apply(road, swell)
    pass_d = 1.6
    car = apply(
        bandpass(noise(pass_d, 1.0, 89), lambda t: 380 + 220 * math.sin(math.pi * t / pass_d), 1.2),
        env_lin(n_samples(pass_d), [(0, 0), (0.5, 0.7), (1.1, 1.0), (1.6, 0)]),
    )
    place(out, car, 1.8, 0.4, wrap=True)
    horn_d = 0.45
    horn = apply(
        add(osc("square", 370, horn_d, 0.25, duty=0.4), osc("square", 466, horn_d, 0.22, duty=0.4)),
        env_adsr(n_samples(horn_d), 0.03, 0.05, 0.7, 0.12),
    )
    place(out, lowpass(horn, 1800), 3.4, 0.18, wrap=True)
    return finish_loop(out, -14.0, 0.3)


@sfx("hangar: empty metal hall rumble + fluorescent buzz, loop 4 s", loop=True)
def ambient_hangar() -> list[float]:
    sec = 4.0
    n = n_samples(sec)
    rumble = gain(lowpass(noise(sec, 1.0, 90), lambda t: 90 + 40 * math.sin(TWO_PI * 0.12 * t)), 0.9)
    buzz = add(sine(100, sec, 0.22), sine(200, sec, 0.08), sine(300, sec, 0.04), osc("saw", 100.2, sec, 0.03))
    flick = gain(bandpass(noise(sec, 1.0, 91), 4500, 4.0), 0.04)
    air = gain(bandpass(noise(sec, 1.0, 92), lambda t: 500 + 250 * math.sin(TWO_PI * 0.2 * t), 0.6), 0.28)
    am = [0.88 + 0.12 * math.sin(TWO_PI * 0.28 * (i / SR)) for i in range(n)]
    return finish_loop(mul(add(rumble, buzz, flick, air), am), -14.0, 0.3)


@sfx("casino: muffled slots + murmur + coins, loop 5 s", loop=True)
def ambient_casino() -> list[float]:
    sec = 5.0
    bab = gain(_babble(sec, 93, 7, 110, 220, 0.55), 0.55)
    wash = gain(bandpass(noise(sec, 1.0, 94), 800, 0.45), 0.22)
    out = add(bab, wash)
    rng = random.Random(95)
    for k in range(8):
        st = rng.uniform(0, sec)
        f = rng.choice((note("E6"), note("G6"), note("C6"), note("A5"), note("B5")))
        place(out, lowpass(_bell(f, 0.28, rng.uniform(0.25, 0.45)), 2200), st, rng.uniform(0.18, 0.35), wrap=True)
    for k in range(10):
        st = rng.uniform(0, sec)
        d = 0.06
        clink_ = apply(
            add(sine(rng.uniform(2800, 5200), d, 0.5), sine(rng.uniform(4200, 7000), d, 0.25)),
            env_exp(n_samples(d), 0.012),
        )
        place(out, clink_, st, rng.uniform(0.12, 0.28), wrap=True)
    return finish_loop(lowpass(out, 3500), -13.0, 0.3)


@sfx("cozy campfire crackle loop 4 s", loop=True)
def campfire_loop() -> list[float]:
    sec = 4.0
    bed = lowpass(noise(sec, 1.0, 96), lambda t: 240 + 90 * math.sin(TWO_PI * 0.7 * t))
    mid = gain(bandpass(noise(sec, 1.0, 97), lambda t: 900 + 300 * math.sin(TWO_PI * 1.1 * t), 0.8), 0.35)
    out = add(gain(bed, 0.55), mid)
    rng = random.Random(98)
    for k in range(110):
        st = rng.uniform(0, sec)
        d = rng.uniform(0.006, 0.022)
        p = apply(highpass(noise(d, 1.0, 300 + k), rng.uniform(1800, 5000)), env_exp(n_samples(d), d * 0.2))
        place(out, p, st, rng.uniform(0.45, 1.15), wrap=True)
    return finish_loop(out, -12.0, 0.12)


@sfx("wind gust whoosh 2 s")
def wind_gust() -> list[float]:
    sec = 2.0
    n = n_samples(sec)
    cutoff = lambda t: 280 + 1600 * math.sin(math.pi * min(1.0, t / sec))
    whoosh = apply(bandpass(noise(sec, 1.0, 99), cutoff, 0.85), env_lin(n, [(0, 0), (0.35, 0.55), (0.85, 1.0), (1.5, 0.45), (2.0, 0)]))
    low = apply(lowpass(noise(sec, 1.0, 100), 180), env_lin(n, [(0, 0), (0.4, 0.6), (1.4, 0.4), (2.0, 0)]))
    return finish(add(whoosh, gain(low, 0.7)), -8.0)


# ------------------------------------------------------------------ main

REQUIRED = [
    "thud", "thud_heavy", "clink", "flop", "crack", "shatter", "squeak", "ignite", "hiss", "tape", "hammer_nail",
    "locked_rattle", "zip_open", "lid_open", "drawer", "unlock", "gulp", "cork", "tap", "gag_bang", "grab", "whoosh",
    "squelch", "splash", "pour", "pocket", "cloth", "coin", "coin_loss", "cash_register", "fanfare", "buzzer", "pin",
    "rip", "oof", "death_wilhelm", "siren", "door_slam", "door_roll", "achievement", "shout_generic", "fire_loop",
    "hammer", "paddle_up", "crowd_murmur", "crowd_gasp", "crowd_laugh", "bid_ding", "wheel_spin", "wheel_stop",
    "car_engine_loop", "car_horn", "tire_skid", "bump_boing", "handcuffs", "jail_door", "police_radio",
    "camera_shutter", "phone_beep", "haggle_tick", "haggle_hit", "haggle_miss", "broom_sweep", "water_spray",
    "unlock_safe", "drink_glug", "mouse_squeak", "hamster_wheel", "ambient_port", "ambient_storage",
    "ambient_desert_day", "ambient_night", "ambient_town", "ambient_hangar", "ambient_casino",
    "campfire_loop", "wind_gust",
]


def write_readme(entries: list[tuple[str, str, bool, float, int]]) -> None:
    lines = [
        "# audio/sfx",
        "",
        "Generated by `py tools/audio/gen_sfx.py` — do not edit WAVs by hand, edit the generator.",
        "Format: PCM 16-bit mono 22050 Hz, peak ≈ -3 dBFS. Played via `AudioBus.play_at(name, pos)` /",
        "`AudioBus.play_ui(name)`; the bus randomizes pitch at runtime. Loops marked `loop` are crossfaded",
        "so `AudioStreamWAV.loop_mode = LOOP_FORWARD` wraps seamlessly.",
        "",
        "| name | loop | sec | KB | description |",
        "|---|---|---|---|---|",
    ]
    for name, desc, loop, sec, size in entries:
        lines.append(f"| `{name}` | {'loop' if loop else ''} | {sec:.2f} | {size // 1024} | {desc} |")
    lines.append("")
    with open(os.path.join(OUT_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main(argv: list[str]) -> int:
    missing = [n for n in REQUIRED if n not in GEN]
    if missing:
        print("generators missing for:", missing)
        return 1
    names = argv or list(GEN.keys())
    os.makedirs(OUT_DIR, exist_ok=True)
    entries = []
    total = 0
    for name in names:
        fn, desc, loop = GEN[name]
        random.seed(hash(name) & 0xFFFF)
        sig = fn()
        path = os.path.join(OUT_DIR, name + ".wav")
        size = write_wav(path, sig)
        total += size
        entries.append((name, desc, loop, len(sig) / SR, size))
        print(f"  {name:20s} {len(sig) / SR:5.2f}s {size // 1024:5d} KB")
    if not argv:
        write_readme(entries)
    print(f"{len(entries)} files, {total / 1024 / 1024:.2f} MB -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
