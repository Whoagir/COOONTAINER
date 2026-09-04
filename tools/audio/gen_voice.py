"""Generate NPC voice lines with Piper (neural TTS, offline) from tools/audio/phrases.json.

Output: audio/voice/<ru|en>/<group>/<category>_NN.wav  (PCM 16-bit mono 22050 Hz)

Every NPC gets a voice picked by character and sex — the old SAPI pass ran the whole cast
through one robotic voice (Irina for RU, Zira/David for EN).  Godot still re-randomizes pitch
at runtime (AudioBus.npc_shout), so lines stay raw here.

Voices live in tools/audio/piper_voices (not in git — see README in that folder):
    py -m piper.download_voices ru_RU-dmitri-medium ru_RU-ruslan-medium ru_RU-irina-medium \
        en_US-ryan-high en_US-joe-medium en_US-amy-medium --data-dir tools/audio/piper_voices

Usage:
    py tools/audio/gen_voice.py                  # everything
    py tools/audio/gen_voice.py --group cop      # one group
    py tools/audio/gen_voice.py --lang en        # one language
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHRASES = Path(__file__).parent / "phrases.json"
VOICE_DIR = Path(__file__).parent / "piper_voices"
# espeak-ng (C library) cannot open non-ASCII paths, and the site-packages copy sits under the
# user profile — which is Cyrillic on this machine.  Keep an ASCII-path copy next to the models.
ESPEAK_DIR = Path(__file__).parent / ".espeak" / "espeak-ng-data"
OUT_ROOT = ROOT / "audio" / "voice"

M_LOUD, M_CALM, F_ONE = "ru_RU-dmitri-medium", "ru_RU-ruslan-medium", "ru_RU-irina-medium"
EN_M_LOUD, EN_M_CALM, EN_F = "en_US-ryan-high", "en_US-joe-medium", "en_US-amy-medium"

# group -> (sex, ru model, en model, length_scale, volume).  length_scale > 1 is slower.
CAST: dict[str, tuple[str, str, str, float, float]] = {
    "auctioneer":       ("m", M_LOUD, EN_M_LOUD, 0.82, 1.0),   # тараторит на весь ангар
    "hunter":           ("m", M_CALM, EN_M_CALM, 0.95, 1.0),
    "hunter_m2":        ("m", M_LOUD, EN_M_LOUD, 0.92, 1.0),  # вторая половина хантеров
    "hunter_f":         ("f", F_ONE, EN_F, 0.95, 1.0),          # Тётя Зина
    "caretaker":        ("m", M_CALM, EN_M_CALM, 0.95, 1.0),
    "cop":              ("m", M_LOUD, EN_M_LOUD, 0.98, 1.0),
    "dealer":           ("f", F_ONE, EN_F, 0.95, 1.0),          # крупье
    "locksmith":        ("m", M_CALM, EN_M_CALM, 1.05, 1.0),
    "car_dealer":       ("m", M_LOUD, EN_M_LOUD, 0.85, 1.0),
    "firefighter":      ("m", M_LOUD, EN_M_LOUD, 0.86, 1.0),
    "janitor_boss":     ("f", F_ONE, EN_F, 1.0, 1.0),
    "vendor_tiny":      ("m", M_CALM, EN_M_CALM, 1.0, 1.0),     # Петрович
    "vendor_antique":   ("m", M_LOUD, EN_M_LOUD, 1.14, 1.0),    # цедит слова
    "vendor_household": ("f", F_ONE, EN_F, 0.95, 1.0),
    "vendor_tech":      ("m", M_LOUD, EN_M_LOUD, 0.9, 1.0),
    "vendor_dark":      ("m", M_CALM, EN_M_CALM, 1.2, 0.75),    # шепчет
}

# группы, которых нет в phrases.json — берут реплики соседа, но своим голосом
ALIASES = {"hunter_f": "hunter", "hunter_m2": "hunter"}


def load_voice(model: str, cache: dict):
    if model not in cache:
        path = VOICE_DIR / f"{model}.onnx"
        if not path.exists():
            sys.exit(f"нет модели {path}\nскачай: py -m piper.download_voices {model} --data-dir {VOICE_DIR}")
        from piper import PiperVoice

        cache[model] = PiperVoice.load(str(path), espeak_data_dir=str(ESPEAK_DIR))
    return cache[model]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--group", default="")
    ap.add_argument("--lang", default="", choices=["", "ru", "en"])
    ap.add_argument("--no-trim", action="store_true")
    args = ap.parse_args()

    from piper import SynthesisConfig

    phrases = json.loads(PHRASES.read_text(encoding="utf-8"))
    langs = [args.lang] if args.lang else ["ru", "en"]
    cache: dict = {}
    written = 0

    for group, (sex, ru_model, en_model, length, volume) in CAST.items():
        if args.group and group != args.group:
            continue
        src = ALIASES.get(group, group)
        if src not in phrases:
            print(f"[skip] {group}: нет фраз для '{src}' в phrases.json")
            continue
        for lang in langs:
            model = ru_model if lang == "ru" else en_model
            voice = load_voice(model, cache)
            cfg = SynthesisConfig(length_scale=length, volume=volume, normalize_audio=True)
            out_dir = OUT_ROOT / lang / group
            out_dir.mkdir(parents=True, exist_ok=True)
            for category, by_lang in phrases[src].items():
                lines = by_lang.get(lang, [])
                for i, text in enumerate(lines, start=1):
                    path = out_dir / f"{category}_{i:02d}.wav"
                    with wave.open(str(path), "wb") as f:
                        voice.synthesize_wav(text, f, syn_config=cfg)
                    written += 1
            print(f"[{lang}] {group:17s} {sex}  {model}")

    if not args.no_trim:
        sys.argv = [sys.argv[0], str(OUT_ROOT)]
        trim = Path(__file__).parent / "trim_voice.py"
        exec(compile(trim.read_text(encoding="utf-8"), str(trim), "exec"), {"__name__": "__main__", "__file__": str(trim)})

    print(f"готово: {written} файлов в {OUT_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
