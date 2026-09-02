#!/usr/bin/env python3
"""Brainstorm catalog: what shows up in storage auctions.

Generates ~5000 conceptual finds, scores by friendslop-fun, drops ids already
in items.csv, writes tools/content/storage_finds_catalog.csv + top100 report.

  py tools/content/gen_storage_catalog.py
"""
from __future__ import annotations

import csv
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ITEMS_CSV = ROOT / "items.csv"
OUT = ROOT / "storage_finds_catalog.csv"
TOP = ROOT / "storage_finds_top100.txt"

# Nouns you actually find in abandoned units / estate sales / garage auctions.
NOUNS = [
    "toaster", "blender", "coffee maker", "snow globe", "vinyl record", "turntable",
    "accordion", "harmonica", "microscope", "telescope", "hair dryer", "clothes iron",
    "waffle iron", "juicer", "gramophone", "cash register", "abacus", "hourglass",
    "bowling pin", "helmet", "megaphone", "aquarium", "terrarium", "typewriter ribbon",
    "slide projector", "film reel", "overhead projector", "fax machine", "pager",
    "answering machine", "rotary phone", "payphone handset", "walkie-talkie",
    "CB radio", "police scanner", "metal detector", "Geiger counter", "compass",
    "sextant", "binoculars", "opera glasses", "kaleidoscope", "magic lantern",
    "slide rule", "drafting set", "T-square", "protractor set", "globe stand",
    "desk bell", "hotel key board", "room number plate", "do not disturb sign",
    "neon beer sign", "marquee letter", "jukebox", "pinball backglass", "arcade stick",
    "poker chip rack", "roulette wheel toy", "slot machine bank", "pull-tab opener",
    "cigar humidor", "pipe rack", "ashtray tower", "matchbook collection",
    "flask engraved", "shot glass set", "decanter", "corkscrew fancy", "wine thief",
    "cheese board", "mortar pestle", "meat grinder", "hand mixer", "egg beater",
    "pressure cooker", "fondue set", "raclette grill", "hot plate", "camping stove",
    "thermos giant", "ice cream maker", "popcorn machine", "cotton candy spinner",
    "bread machine", "rice cooker", "slow cooker", "instant pot clone", "air fryer",
    "deep fryer", "sandwich press", "panini press", "crepe maker", "donut maker",
    "chocolate fountain", "fondant kit", "candy thermometer", "kitchen scale",
    "spice rack full", "tea tin set", "coffee grinder", "espresso portafilter",
    "milk frother", "soda siphon", "seltzer bottle", "beer growler", "keg tap",
    "wine barrel bung", "cork collection", "label maker", "rubber stamp set",
    "wax seal kit", "fountain pen", "dip pen set", "ink well", "blotter pad",
    "ledger book", "addressograph", "check writer", "coin sorter", "bill counter",
    "safe dial practice", "padlock collection", "chain and lock", "bike lock",
    "handcuff prop", "nightstick foam", "badge replica", "whistle referee",
    "stopwatch", "kitchen timer", "egg timer", "sand timer giant", "alarm clock windup",
    "cuckoo nest empty", "mantel clock", "ship clock", "world time clock",
    "barometer", "hygrometer", "weather house", "rain gauge", "wind vane toy",
    "lawn flamingo pair", "garden gnome army", "bird bath", "wind chime",
    "dreamcatcher", "incense burner", "singing bowl", "prayer beads", "rosary",
    "crucifix wall", "mezuzah", "lucky cat", "buddha fat", "jade cabbage",
    "crystal cluster", "geode half", "fossil ammonite", "shark tooth jar",
    "butterfly case", "beetle pins", "taxidermy squirrel", "deer antler",
    "moose plaque", "fish mount", "boar tusk", "snake skin shed", "turtle shell",
    "human anatomy model", "skeleton half", "skull candle holder", "medical dummy",
    "dentist chair lamp", "otoscope", "stethoscope", "blood pressure cuff",
    "syringe prop", "pill bottle empty", "mortar pharmacy", "apothecary jar",
    "lab flask", "bunsen burner", "test tube rack", "petri dishes", "centrifuge toy",
    "robot vacuum dead", "roomba shell", "fax toner", "printer carcass",
    "scanner flatbed", "copy machine panel", "CRT green terminal", "dot matrix",
    "punch card deck", "floppy box", "ZIP drive", "SyQuest cartridge", "DAT tape",
    "Betamax stack", "LaserDisc", "MiniDisc player", "Discman", "Walkman",
    "iPod classic", "Zune", "Game Boy", "Sega Genesis", "Atari 2600",
    "Nintendo Power Glove", "VR headset dusty", "drone crashed", "RC helicopter",
    "model airplane", "model train set", "slot car track", "Lego bin mystery",
    "action figure mint", "action figure loose", "Barbie head only", "Ken torso",
    "G.I. Joe footlocker", "Transformers incomplete", "Pokemon cards binder",
    "Magic cards bulk", "baseball cards shoe box", "comic longbox", "manga stack",
    "yearbook signed", "scrapbook wedding", "photo album mold", "polaroid pack expired",
    "camera bag empty", "lens dusty", "flash bulb box", "light meter", "tripod broken",
    "softbox stand", "backdrop roll", "mannequin hand", "wig stand", "sewing form",
    "dress form", "hat box tower", "shoe tree pair", "boot jack", "shoe polish kit",
    "tuxedo bag", "wedding dress boxed", "prom dress bag", "military uniform",
    "scout sash", "band jacket", "cheer megaphone", "mascot head", "foam finger",
    "stadium seat", "jersey framed", "signed basketball", "hockey puck signed",
    "golf club set", "putter novelty", "tennis racket wood", "badminton set",
    "croquet mallet", "bocce ball", "lawn dart banned", "horseshoe set",
    "frisbee glow", "boomerang", "yo-yo collection", "kendama", "hacky sack jar",
    "juggling clubs", "unicycle", "pogo stick", "stilts pair", "trampoline mini",
    "exercise bike", "row machine", "ab roller", "shake weight", "thigh master",
    "jump rope weighted", "resistance bands", "yoga block", "meditation cushion",
    "massage chair pad", "foot spa", "heating pad", "ice pack novelty",
    "vaporizer antique", "humidifier fish", "dehumidifier dead", "space heater",
    "box fan", "tower fan", "ceiling fan blade", "window AC unit", "swamp cooler",
    "extension cord nest", "power strip fire", "surge protector fried", "UPS battery",
    "car battery", "jumper cables", "tire iron", "hubcap chrome", "license plate",
    "vanity plate", "bumper sticker sheet", "trailer hitch ball", "tow strap",
    "ratchet strap pack", "moving blanket", "furniture dolly", "hand truck",
    "pallet jack toy", "forklift key", "warehouse clipboard", "time clock",
    "punch card rack", "name tag maker", "lanyard bin", "visitor badge gun",
    "security camera dummy", "VHS security tapes", "DVR dusty", "alarm keypad",
    "motion sensor", "doorbell wireless", "intercom handset", "gate remote",
    "garage opener", "key cabinet", "master key blank", "locksmith picks set",
    "bolt cutters", "angle grinder", "circular saw", "jigsaw", "router wood",
    "lathe mini", "drill press", "bench vise", "anvil mini", "blacksmith tongs",
    "welding mask", "torch kit", "propane tank empty", "oxygen bottle prop",
    "fire extinguisher", "smoke alarm chirp", "CO detector", "first aid antique",
    "stretcher fold", "crutches pair", "wheelchair fold", "walker wheels",
    "bedpan", "commode chair", "hospital tray", "IV stand", "defibrillator prop",
    "trophy bowling", "trophy spelling", "plaque employee month", "ribbon blue",
    "medal box", "certificate laminated", "diploma blank", "nameplate desk",
    "executive toy", "newton cradle", "lava lamp", "plasma ball", "mood light",
    "fiber optic lamp", "disco ball mini", "strobe light", "fog machine",
    "bubble machine", "confetti cannon", "party popper crate", "piñata empty",
    "balloon animal kit", "clown nose jar", "whoopee cushion pack", "fake vomit",
    "rubber chicken", "hand buzzer", "joy buzzer box", "sneezing powder",
    "itching powder", "smoke bombs novelty", "stink bomb pack", "fake dog poop",
    "whoopee remote", "prank call book", "gag teeth", "arrow through head",
    "novelty glasses", "x-ray specs", "hypno spiral", "magic set kids",
    "top hat rabbit", "wand sparkly", "cape velvet", "mask Venetian",
    "mask hockey", "mask gas antique", "gas mask toy", "scuba mask",
    "snorkel set", "flippers", "life vest", "inner tube", "pool noodle bin",
    "beach umbrella", "coolers full of sand", "sandcastle mold", "metal detector sand",
    "kite broken", "parachute toy", "model rocket", "fireworks illegal",
    "sparkler box", "roman candle", "smoke grenade novelty", "flare gun prop",
    "signal mirror", "survival kit", "MREs expired", "canteen army",
    "mess kit", "entrenching tool", "bayonet dull", "ammo can empty",
    "shell casing jar", "bullet belt dummy", "grenade paperweight", "tank model",
    "ship in bottle", "bottle ship broken", "anchor paperweight", "life ring",
    "porthole frame", "captain hat", "eyepatch silk", "treasure map fake",
    "chest empty", "doubloon plastic", "compass brass", "spyglass brass",
    "cutlass foam", "cannonball iron", "powder horn", "flintlock replica",
    "samurai sword wall", "katana display", "shuriken set", "nunchaku foam",
    "bo staff", "training dummy", "punching bag", "speed bag", "gloves boxing",
    "mouthguard case", "cup athletic", "cleats muddy", "shin guards",
    "skate helmet", "knee pads", "elbow pads", "wrist guards", "mouthpiece",
    "chess set ivory fake", "checkers set", "backgammon board", "mahjong set",
    "dominoes bone", "dice casino", "dice fuzzy", "poker table felt",
    "chip carousel", "card shuffler", "dealer shoe", "blackjack table toy",
    "ouija board", "tarot deck", "crystal ball", "pendulum kit", "rune stones",
    "incense skull", "ouija planchette", "spirit board cheap", "ghost detector",
    "EMF meter toy", "EVP recorder", "night vision goggles", "IR thermometer",
    "thermal camera toy", "bodycam fake", "dashcam", "action cam cracked",
    "gopro mount only", "selfie stick", "ring light", "teleprompter DIY",
    "podcast mic", "boom arm", "pop filter", "MIDI keyboard", "drum pad",
    "guitar pedalboard", "amp head", "cabinet speaker", "PA speaker",
    "mixing board", "equalizer rack", "rackmount empty", "patch bay",
    "XLR snake", "mic stand", "music stand", "metronome windup", "tuning fork",
    "violin case empty", "cello broken", "ukulele", "banjo", "mandolin",
    "harmonica chrome", "kazoo set", "recorder plastic", "flute school",
    "clarinet", "saxophone dented", "trombone slide", "tuba kids",
    "triangle music", "cymbal cracked", "cowbell", "tambourine", "maracas",
    "bongo pair", "conga", "djembe", "steel drum", "xylophone kids",
    "glockenspiel", "kalimba", "music box ballerina", "player piano roll",
    "organ pedal", "church hymnal", "choir robe", "conductor baton",
    "score sheet stack", "fake book jazz", "sheet music binder",
    "cookbook stained", "recipe box", "index cards recipes", "menu diner",
    "napkin dispenser", "salt pepper set", "ketchup pump", "straw dispenser",
    "toothpick dispenser", "sugar caddy", "creamer cow", "butter dish",
    "egg cup set", "toast rack", "muffin tin", "bundt pan", "springform",
    "cookie cutter tin", "rolling pin", "pastry blender", "pie weights",
    "cake stand", "cake topper bride", "wedding cake knife", "champagne flutes",
    "toasting goblets", "unity candle", "guest book", "place card holder",
    "ring pillow", "garter", "veil boxed", "boutonniere dried",
    "baby shoes bronze", "birth certificate frame", "ultrasound photo",
    "pacifier collection", "bottle warmer", "breast pump", "diaper genie",
    "crib mobile", "baby monitor CRT", "night light moon", "sound machine",
    "potty chair", "step stool kids", "booster seat", "car seat expired",
    "stroller fold", "umbrella stroller", "baby carrier", "sling wrap",
    "high chair", "playpen", "exersaucer", "jumperoo", "walker banned",
    "swing cradle", "bassinet", "changing table", "wipe warmer",
    "sterilizer", "bottle brush set", "formula can empty", "baby food jars",
    "sippy cup bin", "plate divider kids", "utensil set kids", "bib stack",
    "onesie mystery", "blanket security", "lovey missing eye", "rattle keys",
    "teething ring", "activity gym", "stacking rings", "shape sorter",
    "busy board", "abacus kids", "flash cards", "alphabet blocks",
    "chalkboard easel", "magnetic letters", "felt board", "puppet theater",
    "hand puppets", "marionette", "ventriloquist dummy", "sock puppet kit",
    "magic 8 ball", "fortune teller fish", "cootie catcher pack", "paper fortune",
    "spinner fidget giant", "stress ball face", "putty thinking", "slime jar",
    "kinetic sand", "moon sand", "playdough dried", "modeling clay",
    "pottery wheel", "kiln mini", "glaze bottles", "ceramics greenware",
    "paint by numbers", "paint set oils", "acrylic set", "watercolor tin",
    "easel collapsible", "canvas blank", "canvas failed", "palette knife set",
    "airbrush kit", "stencil pack", "spray paint crate", "marker bin",
    "calligraphy set", "brush roll", "ink stone", "sumi kit",
    "origami paper", "scrapbook kit", "die cut machine", "laminator",
    "button maker", "badge press", "embosser seal", "notary stamp fake",
    "passport stamp kit", "visa stamp toy", "customs form pad",
    "airline sick bag", "barf bag signed", "life vest airline", "oxygen mask demo",
    "tray table", "headrest cover stack", "boarding pass printer",
    "baggage scale", "luggage strap", "suitcase spinner dead", "duffel army",
    "garment bag", "hat box leather", "trunk steamer", "trunk travel",
    "footlocker camp", "ammo crate wood", "sea chest", "hope chest",
    "cedar chest", "blanket chest", "toy chest", "storage ottoman",
    "hamper laundry", "ironing board", "sleeve board", "pressing cloth",
    "starch spray", "lint roller pack", "sweater stone", "fabric shaver",
    "sewing basket", "pin cushion tomato", "thimble set", "thread rack",
    "button tin", "zipper bag", "elastic spool", "bias tape",
    "pattern envelope", "dress form adjustable", "hemming bird", "seam ripper jar",
    "embroidery hoop", "cross stitch kit", "latch hook kit", "macrame plant",
    "yarn skein bin", "knitting needles", "crochet hook set", "loom mini",
    "spinning wheel", "drop spindle", "carding brushes", "fleece raw",
    "quilt unfinished", "quilt frame", "batting roll", "backing fabric",
    "pillow form", "cushion insert", "throw blanket", "afghan granny",
    "doily stack", "table runner", "placemat set", "coaster cork",
    "napkin rings", "candle sticks brass", "candelabra", "menorah",
    "oil lamp glass", "lantern railroad", "lantern camping", "torch tiki",
    "citronella bucket", "bug zapper", "fly swatter set", "mousetrap pack",
    "rat trap", "glue trap unused", "ultrasonic pest", "flea bomb empty",
    "roach motel", "ant bait", "slug pellets", "garden hose kinked",
    "sprinkler oscillating", "soaker hose", "watering can", "hose nozzle",
    "hose reel", "spigot key", "pipe wrench", "plunger deluxe",
    "toilet auger", "snake drain", "closet flange", "toilet seat gold",
    "bidet attachment", "shower head rain", "shower caddy", "soap dish shell",
    "toothbrush holder", "razor safety", "straight razor", "shaving brush",
    "shaving mug", "aftershave splash", "cologne splash", "deodorant stone",
    "perfume atomizer", "powder puff", "compact mirror", "lipstick bullet",
    "makeup case", "eyelash curler", "tweezers gold", "nail kit",
    "manicure set", "pedicure tub", "callus grater", "pumice stone",
    "loofah on stick", "back scrubber", "bath bomb crate", "bubble bath jug",
    "rubber duck army", "bath thermometer", "bath pillow", "shower radio",
    "waterproof radio", "soap on a rope", "hotel soap crate", "shampoo sample bin",
    "conditioner gallon", "mouthwash novelty", "floss dispenser", "tongue scraper",
    "water pik", "electric toothbrush", "toothbrush travel", "denture cup",
    "denture adhesive", "retainer case", "mouthguard sports", "night guard",
    "earplugs jar", "eye mask sleep", "white noise machine", "CPAP machine",
    "nebulizer", "inhaler spacer", "peak flow meter", "glucose meter",
    "pulse oximeter", "thermometer ear", "forehead thermometer", "fever strip",
    "hot water bottle", "ice bag rubber", "heating lamp", "red light panel",
    "tanning lamp", "UV nail lamp", "blacklight", "grow light",
    "plant grow tent", "hydroponics tray", "nutrient bottles", "pH meter",
    "soil tester", "seed vault", "seed packets", "bulb mesh bag",
    "orchid pot", "bonsai tools", "pruning shears", "grafting knife",
    "rooting hormone", "mister bottle", "humidity tray", "grow journal",
    "beekeeping veil", "hive frame", "honey extractor toy", "smoker bee",
    "chicken feeder", "egg incubator", "egg candler", "brooder lamp",
    "dog crate", "cat tree", "litter genie", "aquarium filter",
    "protein skimmer", "air stone pack", "heater aquarium", "chiller unit",
    "UV sterilizer", "algae scraper", "fish net", "gravel vacuum",
    "coral frag rack", "live rock dry", "salt mix bucket", "refractometer",
    "hydrometer", "test kit water", "fish food tin", "brine shrimp hatchery",
    "hamster wheel", "hamster ball", "chew stick pack", "water bottle sipper",
    "guinea pig castle", "rabbit hutch door", "ferret hammock", "bird swing",
    "cuttlebone", "millet spray", "parrot perch", "flight harness",
    "lizard hide", "heat rock", "UVB bulb", "cricket keeper",
    "mealworm farm", "snake hook", "tongs feeding", "scale weighing pets",
    "microchip scanner", "pet ID tag engraver", "leash retractable", "harness dog",
    "muzzle soft", "cone of shame", "elizabethan collar", "pet stairs",
    "pet stroller", "bike trailer pet", "car seat pet", "seat belt pet",
    "GPS tracker pet", "bark collar", "ultrasonic trainer", "clicker training",
    "treat pouch", "agility tunnel", "weave poles", "teeter board",
    "frisbee dog", "chuckit launcher", "kong dirty", "rope toy frayed",
    "squeaky toy flat", "laser pointer", "feather wand", "catnip pillow",
    "scratching post", "cardboard condo", "window perch", "catio panel",
]

ADJECTIVES = [
    "rusty", "dusty", "cracked", "mint", "cursed", "holy", "fake", "signed",
    "Soviet", "motel", "wedding", "divorce", "garage", "estate", "foreclosure",
    "hoarder", "grandma", "grandpa", "teen", "office", "church", "school",
    "army", "navy", "band", "casino", "diner", "hospital", "lab", "studio",
    "basement", "attic", "storage", "port", "customs", "evidence", "lost-found",
    "pink", "gold", "chrome", "neon", "velvet", "plastic", "ceramic", "glass",
    "broken", "leaky", "sticky", "smelly", "burnt", "frozen", "wet", "bloody",
    "lucky", "unlucky", "cursed-twice", "haunted", "blessed", "banned", "illegal",
    "counterfeit", "replica", "prototype", "limited", "numbered", "one-of-one",
    "bootleg", "imported", "export-only", "recall", "expired", "unopened",
    "half-used", "mystery", "unlabeled", "handwritten", "engraved", "dedicated",
    "to-mom", "to-boss", "participation", "employee-of-month", "retirement",
    "novelty", "gag", "adult", "kids", "tiny", "giant", "life-size", "mini",
]

CONTEXTS = [
    "in a trash bag", "wrapped in newspaper", "in a sock", "taped shut",
    "with a note", "with a receipt", "with a lawsuit", "with a photo",
    "with mouse droppings", "with a dead battery", "with no power cord",
    "with the wrong remote", "with instructions missing page 2", "still beeping",
    "full of sand", "full of glitter", "full of rice", "full of coins",
    "smelling of smoke", "smelling of perfume", "smelling of fish",
    "labeled FREE", "labeled DO NOT SELL", "labeled EVIDENCE", "labeled MOM",
    "from a divorce", "from a raid", "from a flood", "from a fire sale",
    "won at carnival", "won at casino", "stolen then returned", "never opened",
    "opened once", "glued shut", "welded shut", "padlocked", "zip-tied",
]


def existing_ids() -> set[str]:
    ids: set[str] = set()
    with ITEMS_CSV.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            iid = (row.get("id") or "").strip()
            if iid and not iid.startswith("#"):
                ids.add(iid)
                ids.add(iid.replace("_", " "))
                for part in iid.split("_"):
                    if len(part) > 3:
                        ids.add(part)
    return ids


def fun_score(noun: str, adj: str, ctx: str) -> int:
    s = 40
    funny_adj = {
        "cursed", "haunted", "divorce", "evidence", "bloody", "smelly", "gag",
        "counterfeit", "bootleg", "participation", "employee-of-month", "recall",
        "illegal", "banned", "one-of-one", "to-boss", "motel", "hoarder",
    }
    funny_noun = {
        "snow globe", "rubber chicken", "ventriloquist dummy", "whoopee cushion pack",
        "taxidermy squirrel", "ouija board", "lava lamp", "cash register", "accordion",
        "gramophone", "aquarium", "mascot head", "denture cup", "bedpan",
        "fake dog poop", "arrow through head", "ship in bottle", "hourglass",
        "bowling pin", "megaphone", "toaster", "waffle iron", "harmonica",
    }
    funny_ctx = {
        "with a lawsuit", "labeled EVIDENCE", "from a divorce", "from a raid",
        "still beeping", "full of glitter", "in a sock", "smelling of fish",
        "won at casino", "stolen then returned", "welded shut",
    }
    if adj in funny_adj:
        s += 25
    if noun in funny_noun:
        s += 20
    if ctx in funny_ctx:
        s += 20
    if "glass" in noun or "crystal" in noun or "aquarium" in noun or "snow" in noun:
        s += 10  # shatter potential
    if "fake" in adj or "replica" in adj:
        s += 8
    # stable jitter so ranking is repeatable
    h = int(hashlib.md5(f"{noun}|{adj}|{ctx}".encode()).hexdigest()[:6], 16)
    s += h % 15
    return s


def slug(noun: str, adj: str) -> str:
    raw = f"{adj}_{noun}".lower().replace(" ", "_").replace("-", "_")
    out = []
    for ch in raw:
        if ch.isalnum() or ch == "_":
            out.append(ch)
    s = "".join(out)
    while "__" in s:
        s = s.replace("__", "_")
    return s[:40]


def main() -> None:
    exist = existing_ids()
    rows: list[dict] = []
    seen: set[str] = set()
    # ~5000: cycle nouns × adj × contexts with stride
    i = 0
    while len(rows) < 5000:
        noun = NOUNS[i % len(NOUNS)]
        adj = ADJECTIVES[(i * 7) % len(ADJECTIVES)]
        ctx = CONTEXTS[(i * 13) % len(CONTEXTS)]
        sid = slug(noun, adj)
        key = f"{sid}|{ctx}"
        i += 1
        if key in seen:
            continue
        seen.add(key)
        # skip if too close to existing item id tokens
        if sid in exist or any(sid.startswith(e) or e.startswith(sid) for e in exist if len(e) > 8):
            continue
        score = fun_score(noun, adj, ctx)
        rows.append({
            "rank_key": score,
            "id_suggest": sid,
            "noun": noun,
            "adjective": adj,
            "context": ctx,
            "shatter": "yes" if any(k in noun for k in ("glass", "globe", "aquarium", "crystal", "hourglass", "vase", "lamp")) or adj in ("cracked", "glass", "ceramic") else "maybe",
            "fun_score": score,
        })

    rows.sort(key=lambda r: (-r["fun_score"], r["id_suggest"]))
    with OUT.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["fun_score", "id_suggest", "noun", "adjective", "context", "shatter"])
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in w.fieldnames})

    top = rows[:100]
    with TOP.open("w", encoding="utf-8") as f:
        f.write(f"Top 100 of {len(rows)} catalog finds (existing filtered).\n")
        f.write("Implemented separately in items.csv wave3 block — not auto-imported.\n\n")
        for n, r in enumerate(top, 1):
            f.write(f"{n:3d}. [{r['fun_score']:3d}] {r['id_suggest']:40s}  shatter={r['shatter']:5s}  {r['context']}\n")
    print(f"wrote {len(rows)} rows -> {OUT}")
    print(f"wrote top 100 -> {TOP}")


if __name__ == "__main__":
    main()
