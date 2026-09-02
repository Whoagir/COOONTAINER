# COOONTAINER — hand-authored lot presets (§8).
# Not a cell generator. Every spawn has an explicit local transform
# (metres, floor centre, +Z = opening / crowd).
#
# =============================================================================
# CAMPAIGN ARITHMETIC  (HOUSE_PRICE = $25 000, target ~5 h)
# =============================================================================
# Assumptions (from the brief):
#   win_rate        W = 0.60     player wins ~60% of lots they bid on
#   vendor          V = 0.60     sells at ~0.6× value_base
#   fragile break   B = 0.15     lose 15% of FRAGILE value on the haul
#   expected_net    = W * (V * (value_base − B * fragile) − min_bid)
#
# A competent party plays one full pass of hangar_01..14 + storage_01..22
# + garages_01..18 + port_01..14 (~68 lots, ~5 h). They bid on every lot
# (busts included — info_mode lies enough that a bust still eats a paddle).
#
# Wave 1 (01..) is frozen. Wave 2 APPENDs higher `order` and continues
# each district's L/J/B curve. Never two jackpots in a row.
# Pacing target ≈ 60% lean / 25% jackpot / 15% bust.
#
# Jackpots hide value (low min_bid + a hero). Busts invert it (high
# min_bid, junk, dirt, the occasional mouse).
# =============================================================================

from __future__ import annotations


def S(item_id: str, x: float, y: float, z: float, rot: float = 0.0,
      nested=None, locked: int = -1, dirt: float = -1.0) -> dict:
    return {
        "item_id": item_id,
        "x": float(x), "y": float(y), "z": float(z),
        "rot_y": float(rot),
        "nested": list(nested or []),
        "locked": int(locked),
        "dirt": float(dirt),
    }


def stack_y(item_id: str, x: float, z: float, n: int, dy: float,
            rot: float = 0.0, y0: float = 0.0, **kw) -> list:
    return [S(item_id, x, y0 + i * dy, z, rot + (i % 3 - 1) * 4, **kw) for i in range(n)]


def mug_locker_forty() -> list:
    """8 stacks × 5 cups. Locker 1.0×1.0 floor, cups 9 cm, 0.19 m XZ gap."""
    cols = [
        (-0.28, -0.28), (0.00, -0.28), (0.28, -0.28),
        (-0.28,  0.00),                 (0.28,  0.00),
        (-0.28,  0.28), (0.00,  0.28), (0.28,  0.28),
    ]
    out = []
    for i, (x, z) in enumerate(cols):
        out.extend(stack_y("cup_soviet_gold", x, z, 5, 0.10, rot=12 if i % 2 else -8))
    return out


def brick_stack(origin, nx: int, ny: int, nz: int,
                step=(0.42, 0.065, 0.30), rot: float = 0.0,
                item_id: str = "brick_red") -> list:
    """Regular brick pile. Layers sit on each other (deliberate y-stack)."""
    x0, y0, z0 = origin
    sx, sy, sz = step
    out = []
    for iy in range(ny):
        for ix in range(nx):
            for iz in range(nz):
                x = x0 + ix * sx + (0.08 if iy % 2 else 0.0)
                y = y0 + iy * sy
                z = z0 + iz * sz
                out.append(S(item_id, x, y, z, rot + (ix - iz) * 3))
    return out


def box_wall_front(z: float = 1.10) -> list:
    """Three boxes + a crate across a storage door, stacked two high."""
    return [
        S("box_moving", -0.90, 0.00, z, -8, nested=["plate_ikeya", "cup_okayest"]),
        S("box_amazoom", 0.00, 0.00, z, 6, nested=["remote_universal"]),
        S("crate_fruit", 0.90, 0.00, z, 12),
        S("box_moving", -0.90, 0.38, z + 0.02, 10, nested=["vase_ikeya"]),
        S("box_small_shoes", 0.05, 0.38, z + 0.02, -14, nested=["letter_love"]),
        S("box_mystery", 0.90, 0.48, z + 0.02, 4),
    ]


LOTS: list[dict] = []

# ---------------------------------------------------------------------------
# HANGAR  bags on a table   District.HANGAR=1  LotKind.BAG
# hunters 6   preview 12–20   clearout 60–90   min_bid 5–40
# ---------------------------------------------------------------------------

LOTS.append({
    "id": "hangar_01", "district": "HANGAR", "kind": "BAG", "order": 1,
    "min_bid": 8, "info": "PHOTOS", "pacing": "LEAN",
    "preview": 14, "clearout": 70, "hunters": 6, "lock_chance": 0.05,
    "joke": "photos include a Rolecks that is not in the bag",
    "photos": ["bag_ladies_leopard", "jewelry_box_kids", "watch_rolecks_real"],
    "spawns": [
        S("bag_ladies_leopard", -0.40, 0, -0.38, 22, nested=["phone_flip", "cash_20"]),
        S("jewelry_box_kids", 0.44, 0, -0.40, -18, nested=["ring_mood"]),
        S("book_cookbook", 0.44, 0, 0.02, 82),
        S("candle_scented", -0.50, 0, 0.06, 14),
        S("duck_yellow", -0.42, 0, 0.44, -10),
        S("snowglobe_vegas", -0.08, 0, 0.48, 28),
        S("bag_tote", 0.42, 0, 0.42, -22, nested=["cash_10", "bill_coupon"]),
        S("hourglass_desk", 0.18, 0, 0.18, 8),
    ],
})

LOTS.append({
    "id": "hangar_02", "district": "HANGAR", "kind": "BAG", "order": 2,
    "min_bid": 28, "info": "TALE", "pacing": "BUST",
    "preview": 12, "clearout": 60, "hunters": 6, "lock_chance": 0.0,
    "joke": "suitcase whose only content is a single sock",
    "tale_ru": "Этот чемодан пересек три границы. Интерпол до сих пор ищет второй носок. Хозяин клялся, что внутри наследство тёти. Тётя жива и звонит каждый вторник.",
    "tale_en": "This suitcase crossed three borders. Interpol is still looking for the other sock. The owner swore auntie's fortune was inside. Auntie is alive and calls every Tuesday.",
    "spawns": [
        S("suitcase_plastic", 0.00, 0, -0.32, 8, nested=["sock_single"]),
        S("plant_pot_dead", -0.48, 0, 0.38, -22),
        S("hat_tinfoil", 0.50, 0, 0.18, 40),
        S("bill_lottery", 0.20, 0, 0.48, 6),
        S("poster_motivational", 0.00, 0, 0.50, 8),
        S("rag_dirty", -0.48, 0, 0.02, -8),
    ],
})

LOTS.append({
    "id": "hangar_03", "district": "HANGAR", "kind": "BAG", "order": 3,
    "min_bid": 10, "info": "PHOTOS", "pacing": "JACKPOT",
    "preview": 16, "clearout": 80, "hunters": 6, "lock_chance": 0.15,
    "joke": "cheap work bag; the jewelry box at the back holds grandpa's watch",
    "photos": ["bag_work", "camera_polaroid", "vase_ming", "gold_bar"],
    "spawns": [
        S("bag_work", -0.38, 0, -0.36, 18, nested=["jewelry_box_velvet", "cash_20"]),
        S("jewelry_box_music", 0.42, 0, -0.38, -12, nested=["watch_pocket"]),
        S("camera_polaroid", 0.08, 0, 0.08, 25),
        S("book_diary", -0.42, 0, 0.18, 68, nested=["cash_10"]),
        S("cup_okayest", 0.44, 0, 0.28, -6),
        S("letter_love", 0.18, 0, 0.46, 4),
    ],
})

LOTS.append({
    "id": "hangar_04", "district": "HANGAR", "kind": "BAG", "order": 4,
    "min_bid": 12, "info": "DOCS", "pacing": "LEAN",
    "preview": 15, "clearout": 72, "hunters": 6, "lock_chance": 0.0,
    "docs_ru": "ОПИСЬ (школьный рюкзак, сдал вахтёр):\n— рюкзак синий, запах буфета\n— ноутбук «МакБук» (в описи есть, в сумке нет)\n— диск «Для тебя»\n— учебник том 7, закладка — купюра\n— плакат Металликки, клейкая сторона наружу",
    "docs_en": "MANIFEST (school backpack, night guard intake):\n— blue backpack, cafeteria smell\n— MacBuk laptop (on the sheet, not in the bag)\n— a «For You» mix CD\n— encyclopedia vol. 7, bookmark is a bill\n— Metalicca poster, sticky side out",
    "spawns": [
        S("backpack_school", -0.38, 0, -0.32, 15, nested=["usb_cat_videos", "cash_5"]),
        S("boombox_90s", 0.30, 0, -0.32, -8),
        S("book_encyclopedia", 0.46, 0, 0.12, 90),
        S("tablet_kids", -0.40, 0, 0.16, 20),
        S("poster_band", 0.00, 0, 0.44, 5),
        S("toy_car_hotwheelz", 0.50, 0, 0.38, -15),
        S("cd_mixtape", -0.50, 0, 0.42, 8),
        S("cup_okayest", 0.22, 0, 0.18, 0),
    ],
})

LOTS.append({
    "id": "hangar_05", "district": "HANGAR", "kind": "BAG", "order": 5,
    "min_bid": 15, "info": "PHOTOS", "pacing": "LEAN",
    "preview": 14, "clearout": 75, "hunters": 6, "lock_chance": 0.05,
    "joke": "tourist haul; photos advertise a MacBuk that never made the flight",
    "photos": ["camera_polaroid", "suitcase_kids", "laptop_macbuk"],
    "spawns": [
        S("suitcase_kids", 0.00, 0, -0.38, 6, nested=["doll_barbee", "toy_car_hotwheelz"]),
        S("camera_polaroid", 0.44, 0, 0.00, -20),
        S("bag_tote", -0.42, 0, 0.04, 20, nested=["bill_foreign", "letter_aunt"]),
        S("plate_souvenir", 0.42, 0, 0.38, 15),
        S("cup_thermos", -0.18, 0, 0.44, -8),
        S("hat_trucker", -0.50, 0, 0.38, 25),
        S("water_bottle", 0.14, 0, 0.44, 0),
        S("perfume_cheap", 0.50, 0, 0.16, 12),
        S("necklace_macaroni", -0.42, 0, 0.28, 40),
    ],
})

LOTS.append({
    "id": "hangar_06", "district": "HANGAR", "kind": "BAG", "order": 6,
    "min_bid": 10, "info": "TALE", "pacing": "LEAN",
    "preview": 13, "clearout": 66, "hunters": 6, "lock_chance": 0.0,
    "joke": "auctioneer claims the bag belonged to the paperclip guy",
    "tale_ru": "Хозяин этой сумки изобрёл скрепку. Или утверждал. Патент приложен — на салфетке. Нокла 3310 внутри пережила три брака. Радиола не врёт, она просто молчит по-советски.",
    "tale_en": "The owner of this bag invented the paperclip. Or claimed to. Patent attached — on a napkin. The Nokla 3310 inside survived three marriages. The radio doesn't lie, it just stays quiet in Soviet.",
    "spawns": [
        S("bag_gym", -0.36, 0, -0.36, 14, nested=["tool_lighter", "cash_5"]),
        S("phone_nokla", 0.42, 0, -0.38, -8),
        S("radio_soviet", 0.30, 0, 0.10, 12),
        S("laptop_2005", -0.38, 0, 0.14, 8),
        S("radio_alarm", 0.44, 0, 0.40, -16),
        S("folder_tax_2009", -0.10, 0, 0.46, 4),
        S("remote_mystery", 0.16, 0, 0.46, -6),
        S("plant_pot_plastic", 0.00, 0, -0.06, 0),
        S("book_dummies", -0.44, 0, 0.42, 70),
    ],
})

LOTS.append({
    "id": "hangar_07", "district": "HANGAR", "kind": "BAG", "order": 7,
    "min_bid": 30, "info": "DOCS", "pacing": "BUST",
    "preview": 12, "clearout": 60, "hunters": 6, "lock_chance": 0.0,
    "joke": "inventory sheet lists a Ming vase and a gold bar; the box has a sock",
    "docs_ru": "ОПИСЬ №7 (инспектор был пьян):\n1× Ваза Мин (настоящая)\n1× Слиток золота\n1× Часы Ролеккс\n1× Носок (это правда)\nПодпись: «всё ценное, честно» — почерк плывёт.",
    "docs_en": "INVENTORY #7 (inspector was drunk):\n1× Ming vase (real)\n1× Gold bar\n1× Rolecks watch\n1× Sock (this part is true)\nSigned: «everything valuable, honest» — handwriting lists to starboard.",
    "spawns": [
        S("box_small_shoes", 0.00, 0, -0.30, 10, nested=["sock_single"]),
        S("bill_coupon", 0.36, 0, 0.14, 0),
        S("plant_pot_dead", -0.42, 0, 0.10, -12),
        S("hat_tinfoil", 0.42, 0, -0.12, 35),
        S("poster_missing_cat", 0.00, 0, 0.42, 8),
        S("candle_stub", 0.44, 0, 0.36, 0),
        S("jar_unknown_stuff", -0.40, 0, 0.38, 6),
        S("rag_dirty", -0.16, 0, 0.20, 20),
    ],
})

LOTS.append({
    "id": "hangar_08", "district": "HANGAR", "kind": "BAG", "order": 8,
    "min_bid": 18, "info": "PHOTOS", "pacing": "LEAN",
    "preview": 18, "clearout": 85, "hunters": 6, "lock_chance": 0.1,
    "photos": ["backpack_hiking", "camera_polaroid", "letter_treasure", "safe_old"],
    "spawns": [
        S("backpack_hiking", 0.00, 0, -0.36, 10, nested=["flashlight_big", "cash_20"]),
        S("camera_polaroid", 0.46, 0, 0.08, -15),
        S("canister_army_water", -0.46, 0, 0.04, 8),
        S("letter_treasure", 0.22, 0, 0.42, 4),
        S("water_bottle", -0.20, 0, 0.44, 0),
        S("hat_trucker", 0.50, 0, 0.40, 18),
        S("book_dummies", -0.46, 0, 0.40, 65),
    ],
})

# ---------------------------------------------------------------------------
# STORAGE   District.STORAGE=2   10 STORAGE + 2 LOCKER
# preview 15   clearout 120–200   hunters 6–8   lock 0.2–0.35
# broom on 4   dark on 3
# ---------------------------------------------------------------------------

LOTS.append({
    "id": "storage_01", "district": "STORAGE", "kind": "STORAGE", "order": 1,
    "min_bid": 80, "info": "DOOR15", "pacing": "LEAN",
    "preview": 15, "clearout": 140, "hunters": 6, "lock_chance": 0.22,
    "broom": False, "dark": False,
    "joke": "IKEA wobble city — every flat-pack leans a different way",
    "spawns": [
        S("dresser_ikeya", -0.80, 0, -1.10, 4, nested=["tshirt_ironic", "cash_10"]),
        S("lamp_table_banker", -0.80, 0.92, -1.10, -10),
        S("nightstand_motel", 0.20, 0, -1.15, -6, nested=["book_bible_hotel"]),
        S("fridge_mini", 1.10, 0, -1.10, 8),
        S("sewing_grandma", -0.95, 0, -0.35, 12),
        S("tv_crt_soviet", 0.15, 0, -0.40, -8),
        S("clock_cuckoo", 1.10, 0, -0.40, 6),
        S("boombox_90s", -0.95, 0, 0.30, 14),
        S("microwave_yellow", 0.00, 0, 0.28, -4),
        S("kettle_electric", 0.85, 0, 0.32, 20),
        S("plant_pot_cactus", 1.25, 0, 0.28, 0),
        S("box_moving", -0.95, 0, 1.10, -8, nested=["vase_ikeya", "cup_okayest"]),
        S("box_amazoom", -0.15, 0, 1.12, 6, nested=["remote_universal", "usb_novelty_sushi"]),
        S("chair_plastic", 0.55, 0, 1.10, 25),
        S("mop_grey", 1.20, 0, 1.20, 8),
        S("radio_soviet", 0.90, 0, -0.05, -18),
        S("statue_gnome", 1.15, 0, 0.70, 30),
    ],
})

LOTS.append({
    "id": "storage_02", "district": "STORAGE", "kind": "STORAGE", "order": 2,
    "min_bid": 90, "info": "DOOR15", "pacing": "LEAN",
    "preview": 15, "clearout": 150, "hunters": 6, "lock_chance": 0.28,
    "broom": False, "dark": True,
    "spawns": [
        S("mattress_stained", 0.00, 0, -1.00, 0),
        S("dresser_grandma", -0.85, 0, 0.25, 8, nested=["necklace_pearl_fake", "cash_20"]),
        S("suitcase_plastic", -0.85, 0.92, 0.25, -6, nested=["suit_polyester", "sock_single"]),
        S("nightstand_broken", 0.55, 0, 0.20, -12, nested=["book_bible_hotel"]),
        S("lamp_table_ugly", 0.55, 0.58, 0.20, 15),
        S("painting_motel", -1.20, 0, -0.55, 88),
        S("crate_wooden", 0.90, 0, 1.05, 10, nested=["whiskey_cheap", "vodka_standartnaya"]),
        S("pillow_flat", 0.20, 0.24, -1.00, 12),
        S("rug_doormat", 0.00, 0, 1.28, 0),
        S("typewriter_old", -0.90, 0, 1.05, -8),
        S("camera_film_old", 0.40, 0, 0.85, 22),
        S("coin_jar_pennies", -0.20, 0, 0.70, 0),
        S("globe_school", 1.15, 0, 0.20, -16),
    ],
})

LOTS.append({
    "id": "storage_03", "district": "STORAGE", "kind": "STORAGE", "order": 3,
    "min_bid": 70, "info": "DOOR15", "pacing": "JACKPOT",
    "preview": 15, "clearout": 170, "hunters": 7, "lock_chance": 0.30,
    "broom": False, "dark": False,
    "joke": "hamster Boris hidden behind a wall of boxes at the door",
    "spawns": box_wall_front(1.12) + [
        S("hamster_boris", -0.20, 0, -1.20, 20),
        S("hamster_cage_empty", 0.35, 0, -1.18, -8),
        S("box_small_cigar", -1.15, 0, -1.15, 12, nested=["usb_crypto", "cash_50"]),
        S("suitcase_leather", 1.05, 0, -1.10, 0, nested=["book_hollow", "cash_100"], locked=1),
        S("letter_ransom", -0.55, 0, -0.70, 6),
        S("bag_tote", -1.10, 0, -0.50, 18, nested=["cash_20"]),
        S("plant_pot_dead", 1.20, 0, -0.45, 0),
    ],
})

LOTS.append({
    "id": "storage_04", "district": "STORAGE", "kind": "LOCKER", "order": 4,
    "min_bid": 110, "info": "DOCS", "pacing": "LEAN",
    "preview": 15, "clearout": 130, "hunters": 6, "lock_chance": 0.32,
    "broom": False, "dark": False,
    "docs_ru": "ЛОКЕР 04. Сдал охранник ночной смены.\nЯщик красный. Бумбокс золотой (он думал — краска).\nЗеркалка «Кэнун» на дне, под худи.\nВ описи ещё «катана» — в локер не влезла, ушла в другой район.",
    "docs_en": "LOCKER 04. Night-shift guard intake.\nRed toolbox. Gold boombox (he thought it was paint).\nCanun DSLR at the bottom, under a hoodie.\nManifest also lists a katana — didn't fit, walked to another district.",
    "spawns": [
        S("toolbox_red", 0.00, 0.00, -0.18, 8, nested=["hammer_rusty", "wrench_adjustable"]),
        S("boombox_gold", 0.00, 0.23, 0.00, -6),
        S("backpack_hiking", 0.00, 0.50, -0.06, 12, nested=["cash_20", "camera_dslr"]),
        S("jacket_leather", 0.00, 1.06, 0.08, 6),
        S("hat_fedora", 0.00, 1.16, -0.22, 25),
        S("shoe_boots_cowboy", 0.00, 1.16, 0.22, -15),
        S("whiskey_single_malt", 0.30, 0.00, 0.30, 0),
        S("watch_kasio", -0.30, 0.00, 0.30, 40),
    ],
})

LOTS.append({
    "id": "storage_05", "district": "STORAGE", "kind": "STORAGE", "order": 5,
    "min_bid": 220, "info": "TALE", "pacing": "BUST",
    "preview": 15, "clearout": 160, "hunters": 6, "lock_chance": 0.20,
    "broom": True, "dark": False,
    "joke": "mattress against the back wall, empty boxes, broom tax on nothing",
    "tale_ru": "Тут жил фокусник. Обещал распилить ячейку и достать голубя. Голубя нет. Ячейку распилил кто-то другой. Смотритель просит метлу — иначе залог.",
    "tale_en": "A magician lived here. Promised to saw the unit and pull out a dove. No dove. Someone else sawed the unit. Caretaker wants a broom or he keeps the deposit.",
    "spawns": [
        S("mattress_stained", 0.00, 0, -1.00, 0),
        S("pillow_flat", 0.35, 0.24, -0.95, 18),
        S("box_moving", -0.90, 0, 1.10, 8),
        S("box_amazoom", 0.05, 0, 1.12, -6),
        S("crate_fruit", 0.95, 0, 1.08, 12),
        S("plant_pot_dead", -1.20, 0, -0.20, 0),
        S("plant_pot_dead", 1.20, 0, -0.25, 8),
        S("gold_bar_painted", 0.00, 0, 0.40, 4),
        S("brick_red", -0.35, 0, 0.55, -10),
        S("brick_red", 0.35, 0, 0.50, 12),
        S("rag_dirty", -0.70, 0, 0.70, 20),
        S("mop_gross", 1.25, 0, 0.70, 6),
        S("bucket_kfs", -1.15, 0, 0.70, 0),
        S("chair_plastic", -0.70, 0, 0.15, 22),
    ],
})

LOTS.append({
    "id": "storage_06", "district": "STORAGE", "kind": "LOCKER", "order": 6,
    "min_bid": 85, "info": "DOOR15", "pacing": "LEAN",
    "preview": 15, "clearout": 120, "hunters": 6, "lock_chance": 0.25,
    "broom": False, "dark": False,
    "joke": "locker containing nothing but 40 identical gold-rim teacups",
    "spawns": mug_locker_forty(),
})

LOTS.append({
    "id": "storage_07", "district": "STORAGE", "kind": "STORAGE", "order": 7,
    "min_bid": 65, "info": "PHOTOS", "pacing": "JACKPOT",
    "preview": 15, "clearout": 180, "hunters": 7, "lock_chance": 0.33,
    "broom": True, "dark": True,
    "joke": "maybe-master painting face to the wall behind a junk pile",
    "photos": ["painting_motel", "lamp_table_ugly", "plasma_55", "gold_bar"],
    "spawns": [
        S("box_moving", -0.85, 0, 1.10, 10, nested=["cup_okayest"]),
        S("crate_wooden", 0.10, 0, 1.12, -8, nested=["whiskey_cheap"]),
        S("box_amazoom", 0.95, 0, 1.08, 6),
        S("mattress_kids", 0.20, 0, 0.20, 90),
        S("painting_maybe_master", 0.00, 0, -1.20, 4),
        S("painting_motel", -1.15, 0, -0.40, 86),
        S("lamp_table_tiffany", 0.95, 0, -1.05, -12),
        S("nightstand_deco", -0.95, 0, -1.05, 8, nested=["letter_love", "watch_kasio"]),
        S("jewelry_box_velvet", -0.95, 0.58, -1.05, 14, nested=["ring_class"]),
        S("book_first_edition", 0.55, 0, -0.55, 70),
        S("rag_dirty", 1.15, 0, 0.40, 20),
        S("bucket_kfs", 1.20, 0, 0.75, 0),
        S("tool_broom", 1.25, 0, 0.15, 8),
    ],
})

LOTS.append({
    "id": "storage_08", "district": "STORAGE", "kind": "STORAGE", "order": 8,
    "min_bid": 130, "info": "DOOR15", "pacing": "LEAN",
    "preview": 15, "clearout": 175, "hunters": 7, "lock_chance": 0.26,
    "broom": True, "dark": False,
    "spawns": [
        S("shelf_garage", -1.00, 0, -1.10, 0),
        S("toolbox_grandpa", -1.00, 1.22, -1.10, 8, nested=["wrench_monkey", "cash_50"]),
        S("toolbox_red", 0.15, 0, -1.10, -10, nested=["hammer_rusty", "tool_nails"]),
        S("engine_lawnmower", 1.05, 0, -1.00, 15),
        S("drill_cordless", -0.70, 0, -0.50, 20),
        S("paint_red", -0.20, 0, -0.45, 0),
        S("paint_blue", 0.20, 0, -0.45, 8),
        S("paint_gold", 0.60, 0, -0.20, -6),
        S("gasoline_canister", 1.15, 0, -0.35, 12),
        S("tire_bald", -1.05, 0, 0.35, 10),
        S("tire_bald", -1.05, 0.24, 0.38, -8),
        S("oil_jug_engine", -0.50, 0, 0.35, 18),
        S("wrench_giant", 0.15, 0, 0.35, 40),
        S("box_moving", -0.95, 0, 1.10, 6, nested=["tape_colored", "tool_plank"]),
        S("crate_military", 0.15, 0, 1.08, -4, nested=["gun_gag_cap", "tool_matches"], locked=1),
        S("chair_plastic", 1.05, 0, 1.05, 22),
        S("fan_industrial", 1.15, 0, 0.20, 8),
    ],
})

LOTS.append({
    "id": "storage_09", "district": "STORAGE", "kind": "STORAGE", "order": 9,
    "min_bid": 100, "info": "DOOR15", "pacing": "LEAN",
    "preview": 15, "clearout": 165, "hunters": 7, "lock_chance": 0.24,
    "broom": False, "dark": False,
    "joke": "grandma unit: dresser with a suitcase on top, samovar, letters to Santa from a 43-year-old",
    "spawns": [
        S("mattress_memory", 0.00, 0, -1.00, 0),
        S("dresser_grandma", -0.85, 0, 0.20, 6, nested=["frame_photo_wedding", "necklace_pearl_fake"]),
        S("suitcase_leather", -0.85, 0.92, 0.20, -8, nested=["rag_silk", "letter_love"], locked=0),
        S("kettle_samovar", 0.70, 0, 0.15, 10),
        S("teapot_silver", 1.15, 0, 0.20, -6),
        S("nightstand_deco", 1.10, 0, 0.85, 12, nested=["letter_to_santa"]),
        S("lamp_table_banker", 1.10, 0.58, 0.85, 8),
        S("fur_coat", -1.15, 0, 0.85, 18),
        S("painting_stern_portrait", 1.28, 0, -0.50, 90),
        S("globe_bar", 0.15, 0, 0.70, -14, nested=["glass_shot_set", "cash_20"]),
        S("book_cookbook", -0.40, 0, 1.15, 75),
        S("teapot_grandma", 0.20, 0, 1.18, 8),
        S("cup_soviet_gold", 0.45, 0, 1.18, 0),
        S("cup_soviet_gold", 0.60, 0, 1.12, 8),
        S("frame_photo_family", -0.85, 0, 1.20, 12),
        S("plant_pot_bonsai", 0.90, 0, 1.20, 0),
    ],
})

LOTS.append({
    "id": "storage_10", "district": "STORAGE", "kind": "STORAGE", "order": 10,
    "min_bid": 250, "info": "DOCS", "pacing": "BUST",
    "preview": 15, "clearout": 155, "hunters": 6, "lock_chance": 0.35,
    "broom": True, "dark": True,
    "joke": "docs list real Ming and Rolecks; the cell is painted bricks and a fake vase",
    "docs_ru": "ЯЧЕЙКА 10 — АНТИКВАРИАТ (печать «проверено» кривая):\nВаза Мин — 1\nЧасы Ролекс настоящие — 1\nСлиток — 2\nКартина неизвестного мастера — 1\nПримечание: не включать свет, портит патину.",
    "docs_en": "UNIT 10 — ANTIQUES (the «verified» stamp is crooked):\nMing vase — 1\nGenuine Rolecks — 1\nGold bar — 2\nUnknown master painting — 1\nNote: do not turn the light on, it ruins the patina.",
    "spawns": [
        S("vase_ming_fake", 0.00, 0, -1.10, 8),
        S("gold_bar_painted", -0.40, 0, -0.70, 4),
        S("gold_bar_painted", 0.40, 0, -0.65, -6),
        S("gold_bar_painted", 0.00, 0.07, -0.68, 10),
        S("watch_rolecks_fake", 0.55, 0, -1.15, 20),
        S("painting_kid", -1.15, 0, -0.30, 85),
        S("brick_red", -0.90, 0, 0.40, 0),
        S("brick_red", -0.50, 0, 0.45, 8),
        S("brick_red", -0.10, 0, 0.42, -6),
        S("brick_red", 0.30, 0, 0.48, 12),
        S("brick_red", 0.70, 0, 0.40, -8),
        S("brick_lego_giant", 1.10, 0, 0.50, 4),
        S("safe_empty_open", 0.90, 0, -1.05, 10, nested=["letter_debt"]),
        S("mirror_cracked", -1.15, 0, 1.00, 88),
        S("plant_pot_dead", 1.20, 0, 1.10, 0),
        S("rag_dirty", -0.80, 0, 1.15, 16),
        S("tool_broom", 1.28, 0, 0.20, 6),
    ],
})

LOTS.append({
    "id": "storage_11", "district": "STORAGE", "kind": "STORAGE", "order": 11,
    "min_bid": 80, "info": "DOOR15", "pacing": "JACKPOT",
    "preview": 15, "clearout": 190, "hunters": 8, "lock_chance": 0.34,
    "broom": False, "dark": False,
    "joke": "oak dresser looks boring from the door; diamond ring is in the back drawer",
    "spawns": [
        S("box_moving", -0.90, 0, 1.12, 8, nested=["plate_ikeya"]),
        S("box_moving", 0.00, 0, 1.14, -6),
        S("box_amazoom", 0.90, 0, 1.10, 10, nested=["usb_bent"]),
        S("chair_office", -1.10, 0, 0.40, 18),
        S("dresser_oak", 0.00, 0, -1.10, 2, nested=["ring_diamond", "necklace_pearl"]),
        S("jewelry_box_music", 0.35, 0.92, -1.10, -12, nested=["ring_wedding"]),
        S("lamp_table_tiffany", -0.35, 0.92, -1.05, 8),
        S("bookshelf_oak", 1.20, 0, -0.15, 90),
        S("book_first_edition", 0.55, 0, -0.35, 8),
        S("book_spellbook", 0.55, 0.06, -0.10, -6),
        S("nightstand_deco", -1.15, 0, -1.05, 10, nested=["watch_pocket"]),
        S("perfume_vintage", -1.15, 0.58, -1.05, 0),
        S("statue_david", 1.20, 0, 0.40, 16),
    ],
})

LOTS.append({
    "id": "storage_12", "district": "STORAGE", "kind": "STORAGE", "order": 12,
    "min_bid": 150, "info": "DOOR15", "pacing": "LEAN",
    "preview": 15, "clearout": 200, "hunters": 8, "lock_chance": 0.22,
    "broom": False, "dark": False,
    "spawns": [
        S("guitar_acoustic", -1.10, 0, -1.00, 18),
        S("guitar_electric_pink", 1.10, 0, -1.00, -14),
        S("keyboard_synth_80s", 0.00, 0, -1.15, 4),
        S("drum_snare", -0.70, 0, -0.45, 10),
        S("drum_bongo", 0.70, 0, -0.45, -8),
        S("boombox_gold", 0.00, 0, -0.40, 6),
        S("trumpet_gold", 1.15, 0, -0.35, 70),
        S("suitcase_plastic", -1.05, 0, 0.35, 12, nested=["cassette_mixtape", "cd_mixtape"]),
        S("cd_gold_record", 0.15, 0, 0.30, 8),
        S("ball_disco", 0.95, 0, 0.40, 0),
        S("cassette_vhs_wedding", -0.40, 0, 0.40, 12),
        S("poster_movie_1st", 1.20, 0, 0.85, 88),
        S("lamp_table_lava", 0.40, 0, 0.85, 8),
    ],
})

# ---------------------------------------------------------------------------
# GARAGES   District.GARAGES=3   LotKind.GARAGE   5×3×6
# preview 20–30   clearout 240–330   hunters 7–8   min_bid 300–2500
# TEAM furniture required
# ---------------------------------------------------------------------------

LOTS.append({
    "id": "garages_01", "district": "GARAGES", "kind": "GARAGE", "order": 1,
    "min_bid": 400, "info": "SLIT", "pacing": "LEAN",
    "preview": 22, "clearout": 250, "hunters": 7, "lock_chance": 0.15,
    "joke": "junk piled at the door; the leather sofa and china are at the back",
    "spawns": [
        S("sofa_leather", 0.00, 0, -2.40, 4),
        S("dresser_oak", -2.05, 0, -1.10, 90, nested=["letter_love", "cash_20"]),
        S("fridge_retro", 2.00, 0, -1.90, -6, nested=["jar_pickles", "whiskey_cheap"]),
        S("wardrobe_ikeya", 2.00, 0, 0.15, 90, nested=["hoodie_grey", "shirt_hawaiian"]),
        S("chandelier_crystal", 0.10, 0, -0.90, 12),
        S("plate_stack_china", -1.70, 0, -0.20, 8),
        S("teapot_silver", -1.15, 0, -0.20, -10),
        S("bicycle_racing", -1.90, 0, 1.70, 0),
        S("sewing_singher", 1.70, 0, 1.00, 14),
        S("typewriter_old", 1.65, 0, 1.65, -8),
        S("camera_dslr", 1.20, 0, 1.70, 22),
        S("lamp_floor_deco", 2.10, 0, -0.70, 8),
        S("mirror_baroque", 2.25, 0, 1.60, 90),
        S("microwave_new", 0.40, 0, 0.20, -12),
        S("toolbox_red", -0.40, 0, 0.25, 10, nested=["hammer_rusty", "wrench_adjustable"]),
        S("box_moving", -1.00, 0, 2.20, 8, nested=["cup_okayest", "vase_ikeya"]),
        S("box_amazoom", 0.10, 0, 2.25, -6, nested=["remote_tv"]),
        S("crate_fruit", 1.10, 0, 2.20, 12),
        S("tire_bald", 1.90, 0, 2.25, 6),
    ],
})

LOTS.append({
    "id": "garages_02", "district": "GARAGES", "kind": "GARAGE", "order": 2,
    "min_bid": 500, "info": "SLIT", "pacing": "LEAN",
    "preview": 24, "clearout": 260, "hunters": 7, "lock_chance": 0.18,
    "joke": "plywood throne facing a bronze statue like a garage parliament",
    "spawns": [
        S("piano_upright", -0.80, 0, -2.35, 6),
        S("sofa_velvet", 0.90, 0, -2.35, -4),
        S("bookshelf_oak", -2.10, 0, -0.80, 90),
        S("clock_grandfather_fake", 2.15, 0, -2.30, 4),
        S("statue_bronze", 0.15, 0, -1.20, 16),
        S("chair_throne", -1.60, 0, -0.20, 8),
        S("chair_antique", 1.20, 0, -0.40, -12),
        S("typewriter_writer", 0.20, 0, -0.15, 10),
        S("globe_bar", 2.05, 0, 0.20, -8, nested=["glass_shot_set"]),
        S("lamp_table_tiffany", -1.90, 0, 0.50, 14),
        S("mirror_baroque", 2.20, 0, 0.80, 90),
        S("plate_stack_china", -1.80, 0, 1.10, 0),
        S("bust_beethoven", 1.80, 0, 1.10, 20),
        S("box_moving", -0.90, 0, 2.20, 8),
        S("box_moving", 0.20, 0, 2.22, -6, nested=["book_romance"]),
        S("crate_wine", 1.20, 0, 2.15, 10, nested=["cognac_armenian", "champagne_fake"]),
        S("painting_dogs_poker", -2.20, 0, 1.60, 88),
        S("rug_bearskin", 0.10, 0, 0.70, 12),
    ],
})

LOTS.append({
    "id": "garages_03", "district": "GARAGES", "kind": "GARAGE", "order": 3,
    "min_bid": 350, "info": "SLIT", "pacing": "JACKPOT",
    "preview": 28, "clearout": 300, "hunters": 8, "lock_chance": 0.20,
    "joke": "slit shows moving boxes; the grand piano and 50-year whiskey sit at the back wall",
    "spawns": [
        S("piano_grand", 0.00, 0, -2.30, 4),
        S("whiskey_50yo", -1.40, 0, -2.40, 8),
        S("bust_marble", 1.50, 0, -2.35, -10),
        S("chandelier_grand", 0.00, 0, -1.20, 18),
        S("dresser_oak", -2.05, 0, -0.60, 90, nested=["book_first_edition", "cash_100"]),
        S("coin_jar_gold", -2.00, 0.92, -0.60, 6),
        S("table_poker", 0.20, 0, 0.10, 8),
        S("lamp_table_tiffany", 0.40, 0.78, 0.10, -12),
        S("necklace_gold_chain", 0.00, 0.78, 0.25, 30),
        S("vase_greek_amphora", 1.90, 0, -0.80, 6),
        S("teapot_silver", 2.00, 0, -0.30, 14),
        S("rug_persian", 0.10, 0, 1.20, 6),
        S("safe_hotel", 2.05, 0, 1.80, 10, nested=["cash_100", "watch_rolecks_fake"], locked=1),
        S("box_moving", -1.10, 0, 2.25, 8, nested=["plate_ikeya"]),
        S("box_moving", 0.00, 0, 2.28, -6),
        S("box_amazoom", 1.10, 0, 2.22, 10),
        S("crate_fruit", -2.00, 0, 2.20, 12),
        S("plant_pot_plastic", 2.10, 0, 2.20, 0),
    ],
})

LOTS.append({
    "id": "garages_04", "district": "GARAGES", "kind": "GARAGE", "order": 4,
    "min_bid": 450, "info": "DOCS", "pacing": "LEAN",
    "preview": 24, "clearout": 270, "hunters": 7, "lock_chance": 0.22,
    "joke": "Narnia wardrobe: no back panel, just the garage wall",
    "docs_ru": "ГАРАЖ 04 — МАСТЕРСКАЯ (опись на масляной бумаге):\nМотор V8 хромированный — 1\nХолодильник умный (знает ваши грехи) — 1\nПлазма 55 — 1\nШкаф «Нарния» — задней стенки нет, дальше стена\nВертолёт — нет. Кто-то дописал карандашом.",
    "docs_en": "GARAGE 04 — WORKSHOP (manifest on oily paper):\nChrome V8 engine — 1\nSmart fridge (knows your sins) — 1\n55-inch plasma — 1\nNarnia wardrobe — no back panel, just the wall\nHelicopter — no. Someone added that in pencil.",
    "spawns": [
        S("engine_v8", -1.60, 0, -2.30, 12),
        S("fridge_smart", 2.00, 0, -2.20, -6),
        S("wardrobe_narnia", 2.00, 0, -0.40, 90, nested=["jacket_leather", "costume_santa"]),
        S("sofa_sagging", 0.20, 0, -2.35, 4),
        S("plasma_55", 0.10, 0, -1.20, 8),
        S("dresser_ikeya", -2.05, 0, -0.50, 90, nested=["tshirt_band"]),
        S("laptop_macbuk", -2.00, 0.92, -0.50, 16),
        S("monitor_ultrawide", 1.60, 0, 0.50, 6),
        S("camera_dslr", 1.10, 0, 0.70, -18),
        S("toolbox_grandpa", -1.70, 0, 0.40, 10, nested=["drill_cordless", "cash_50"]),
        S("bicycle_racing", -1.80, 0, 1.60, 20),
        S("tire_racing", 1.80, 0, 1.10, 8),
        S("tire_bald", -0.20, 0, 1.50, -6),
        S("oil_jug_engine", 0.40, 0, 0.80, 14),
        S("gasoline_canister", -0.20, 0, 0.85, 8),
        S("box_moving", -0.80, 0, 2.25, 6),
        S("crate_military", 0.40, 0, 2.20, -8, nested=["gun_gag_cap", "tool_matches"], locked=1),
        S("fan_industrial", 2.05, 0, 2.20, 10),
    ],
})

LOTS.append({
    "id": "garages_05", "district": "GARAGES", "kind": "GARAGE", "order": 5,
    "min_bid": 1100, "info": "TALE", "pacing": "BUST",
    "preview": 20, "clearout": 240, "hunters": 7, "lock_chance": 0.10,
    "joke": "slit flashes gold-painted bricks; the rest is a sagging sofa and a smelly fridge",
    "tale_ru": "Хозяин сказал: «там золото Форта Нокс». Он имел в виду краску «золото» из ларька. Диван помнит четыре семьи. Холодильник помнит рыбу 2009 года. Метлу не оставляйте — не поможет.",
    "tale_en": "Owner said: «Fort Knox gold in there». He meant gold paint from a kiosk. The sofa remembers four families. The fridge remembers a fish from 2009. Don't leave a broom — it won't help.",
    "spawns": [
        S("sofa_sagging", 0.00, 0, -2.40, 4),
        S("fridge_smelly", 2.00, 0, -2.10, -8, nested=["jar_pickles", "jar_unknown_stuff"]),
        S("mattress_stained", -1.50, 0, 0.80, 0),
        S("wardrobe_ikeya", 2.05, 0, -0.40, 90),
        S("clock_grandfather_broken", -2.15, 0, -1.80, 4),
        S("barrel_rusty", 1.70, 0, 0.80, 10),
        S("barrel_rusty", 0.70, 0, 0.80, -6),
        S("gold_bar_painted", -0.40, 0, 1.80, 4),
        S("gold_bar_painted", 0.00, 0, 1.85, -8),
        S("gold_bar_painted", 0.40, 0, 1.78, 12),
        S("gold_bar_painted", 0.00, 0.08, 1.82, 6),
        S("brick_red", -1.00, 0, 2.20, 0),
        S("brick_red", -0.55, 0, 2.22, 8),
        S("brick_red", 0.55, 0, 2.18, -6),
        S("brick_red", 1.00, 0, 2.20, 10),
        S("anvil_cartoon", 0.00, 0, 0.40, 14),
        S("plant_pot_dead", -2.15, 0, 2.15, 0),
        S("mop_gross", 2.15, 0, 2.10, 6),
    ],
})

LOTS.append({
    "id": "garages_06", "district": "GARAGES", "kind": "GARAGE", "order": 6,
    "min_bid": 550, "info": "SLIT", "pacing": "LEAN",
    "preview": 26, "clearout": 280, "hunters": 8, "lock_chance": 0.16,
    "spawns": [
        S("wardrobe_antique", -1.90, 0, -2.20, 0, nested=["suit_pinstripe", "hat_top"]),
        S("sofa_velvet", 0.40, 0, -2.40, -4),
        S("fridge_retro", 2.00, 0, -2.20, 6),
        S("dresser_oak", 2.00, 0, -0.40, 90, nested=["cash_50", "frame_photo_wedding"]),
        S("clock_grandfather_fake", -2.15, 0, 0.20, 4),
        S("chandelier_crystal", 0.10, 0, -1.10, 16),
        S("painting_black_square", -2.20, 0, -0.70, 88),
        S("plate_stack_china", 1.70, 0, 0.50, 0),
        S("teapot_silver", 1.20, 0, 0.90, -8),
        S("rug_persian", 0.10, 0, 0.30, 8),
        S("sewing_singher", -1.70, 0, 0.80, 12),
        S("typewriter_old", -1.65, 0, 1.30, 10),
        S("globe_bar", 2.00, 0, 1.20, -14, nested=["cash_20"]),
        S("bicycle_kids", 0.10, 0, 1.70, 90),
        S("box_moving", -0.70, 0, 2.25, 8, nested=["toy_car_hotwheelz"]),
        S("chest_grandma", 0.50, 0, 2.15, -6, nested=["letter_love", "rag_silk"]),
        S("plant_pot_bonsai", 2.10, 0, 2.15, 0),
        S("lamp_floor_deco", -2.15, 0, 2.10, 8),
    ],
})

LOTS.append({
    "id": "garages_07", "district": "GARAGES", "kind": "GARAGE", "order": 7,
    "min_bid": 400, "info": "PHOTOS", "pacing": "JACKPOT",
    "preview": 30, "clearout": 320, "hunters": 8, "lock_chance": 0.18,
    "joke": "wall of bricks at the door; the only thing that isn't a brick is a $2500 signed guitar (and a Rolecks in the toolbox)",
    "photos": ["guitar_signed", "brick_red", "plasma_55"],
    "spawns": brick_stack((-1.30, 0.0, 2.05), 6, 3, 2, (0.44, 0.065, 0.32), rot=4)
    + brick_stack((-1.90, 0.0, 0.40), 3, 2, 3, (0.44, 0.065, 0.32), rot=-6)
    + [
        S("guitar_signed", 0.90, 0, -2.40, 22),
        S("toolbox_grandpa", -1.90, 0, -2.30, 10, nested=["watch_rolecks_real", "cash_500"], locked=1),
        S("safe_old", 1.80, 0, -2.30, -8, nested=["cash_500", "coin_jar_gold"], locked=1),
        S("bust_marble", 0.00, 0, -2.35, 12),
        S("dresser_oak", 2.05, 0, -0.70, 90),
        S("anvil_iron", -2.05, 0, -1.20, 8),
        S("engine_block", 2.00, 0, 0.70, 14),
    ],
})

LOTS.append({
    "id": "garages_08", "district": "GARAGES", "kind": "GARAGE", "order": 8,
    "min_bid": 600, "info": "SLIT", "pacing": "LEAN",
    "preview": 26, "clearout": 310, "hunters": 8, "lock_chance": 0.15,
    "spawns": [
        S("sofa_leather", 0.10, 0, -2.40, 4),
        S("fridge_smart", 2.00, 0, -2.20, -6),
        S("wardrobe_narnia", 2.00, 0, -0.30, 90, nested=["hoodie_grey"]),
        S("clock_grandfather_antique", -2.15, 0, -2.20, 4),
        S("dresser_oak", -2.05, 0, -0.50, 90, nested=["cash_20"]),
        S("chandelier_grand", 0.00, 0, -1.15, 14),
        S("statue_bronze", 1.50, 0, -1.10, 10),
        S("mirror_baroque", 2.20, 0, 1.00, 90),
        S("piano_ruined", 0.15, 0, 0.40, 8),
        S("laptop_macbuk", -2.00, 0.92, -0.50, 12),
        S("plate_stack_wedding", 1.70, 0, 0.70, 0),
        S("rug_persian", 0.10, 0, 1.30, 6),
        S("bicycle_tandem", -1.60, 0, 1.60, 0),
        S("box_moving", -0.60, 0, 2.25, 8),
        S("crate_wine", 0.50, 0, 2.18, -6, nested=["whiskey_single_malt"]),
        S("plant_pot_bonsai", 2.10, 0, 2.15, 0),
    ],
})

# ---------------------------------------------------------------------------
# PORT   District.PORT=4   LotKind.PORT   2.3×2.4×6
# Slots along +Z every ~0.80 m. Wide TEAM items sit alone on a slot.
# preview 25–40   clearout 300–420   hunters 8   min_bid 1200–6000
# ---------------------------------------------------------------------------

LOTS.append({
    "id": "port_01", "district": "PORT", "kind": "PORT", "order": 1,
    "min_bid": 1500, "info": "PHOTOS", "pacing": "LEAN",
    "preview": 28, "clearout": 320, "hunters": 8, "lock_chance": 0.20,
    "photos": ["wardrobe_antique", "chandelier_grand", "vase_ming", "hamster_boris"],
    "spawns": [
        S("sofa_velvet", 0.00, 0, -2.50, 0),
        S("wardrobe_antique", 0.50, 0, -1.25, 90, nested=["suit_pinstripe", "hat_top"]),
        S("statue_bronze", -0.70, 0, -1.25, 12),
        S("chandelier_crystal", 0.00, 0, 0.00, 8),
        S("fridge_retro", 0.55, 0, 1.10, -6, nested=["jar_pickles"]),
        S("bust_marble", -0.70, 0, 1.10, 10),
        S("chest_pirate", -0.55, 0, 1.90, 8, nested=["letter_treasure", "cash_100"], locked=1),
        S("plate_stack_china", 0.60, 0, 1.90, 0),
        S("typewriter_writer", -0.55, 0, 2.50, 12),
        S("camera_dslr", 0.60, 0, 2.50, -16),
        S("coin_jar_gold", 0.00, 0, 2.50, 6),
        S("book_first_edition", -0.55, 0.45, 1.90, 8),
        S("lamp_table_tiffany", 0.60, 0.14, 1.90, 10),
        S("bat_signed", 1.05, 0, 0.00, 40),
        S("cd_gold_record", -0.92, 0, 0.00, 8),
        S("shoe_sneaker_rare", 1.05, 0, -2.50, -12),
        S("necklace_gold_chain", -1.05, 0, -2.50, 25),
        S("jar_elvis_tooth", -1.00, 0, -1.80, 0),
    ],
})

LOTS.append({
    "id": "port_02", "district": "PORT", "kind": "PORT", "order": 2,
    "min_bid": 1200, "info": "PHOTOS", "pacing": "JACKPOT",
    "preview": 36, "clearout": 400, "hunters": 8, "lock_chance": 0.25,
    "joke": "legendary: safe with $2000 cash plus the real Ming vase, gold bar, and a Rolecks — junk piled at the door",
    "photos": ["box_moving", "vase_ming_fake", "plasma_55", "hamster_boris"],
    "spawns": [
        S("safe_old", 0.00, 0, -2.50, 0, nested=["cash_500", "cash_500"], locked=1),
        S("vase_ming", 0.00, 0.72, -2.50, 14),
        S("cash_500", -0.35, 0.72, -2.35, 8),
        S("cash_500", 0.35, 0.72, -2.35, -8),
        S("gold_bar", -0.75, 0, -2.50, 4),
        S("watch_rolecks_real", 0.75, 0, -2.50, 18),
        S("painting_maybe_master", 0.00, 0, -1.70, 4),
        S("whiskey_50yo", -0.70, 0, -1.70, 8),
        S("coin_jar_gold", 0.70, 0, -1.70, 6),
        S("usb_crypto", -0.70, 0, -0.95, 0),
        S("ring_diamond", 0.70, 0, -0.95, 40),
        S("necklace_pearl", 0.00, 0, -0.95, 20),
        S("bust_marble", -0.70, 0, -0.20, 10),
        S("book_first_edition", 0.70, 0, -0.20, 70),
        S("chandelier_grand", 0.00, 0, 0.80, 8),
        S("wardrobe_antique", 0.50, 0, 2.10, 90, nested=["fur_coat", "hat_top"]),
        S("box_moving", -0.75, 0, 2.55, 8, nested=["cup_okayest"]),
        S("box_moving", -0.75, 0.35, 2.55, -6),
    ],
})

LOTS.append({
    "id": "port_03", "district": "PORT", "kind": "PORT", "order": 3,
    "min_bid": 1800, "info": "DOCS", "pacing": "LEAN",
    "preview": 30, "clearout": 360, "hunters": 8, "lock_chance": 0.22,
    "joke": "shipping manifest lists a helicopter and a car; the container has a sofa and a chandelier",
    "docs_ru": "КОНОСАМЕНТ / BILL OF LADING 7741-П\nПункт: Одесса → сюда\n1× Вертолёт (разобран) — НЕТ\n1× Автомобиль «Волга» — НЕТ\n1× Рояль — тоже нет, есть шкаф\n1× Люстра дворцовая — да, она\n1× Бюст «римский» — да\nПечать: «не трясти». Контейнер всю дорогу трясли.",
    "docs_en": "BILL OF LADING 7741-P\nRoute: Odessa → here\n1× Helicopter (disassembled) — NO\n1× Volga automobile — NO\n1× Grand piano — also no, there's a wardrobe\n1× Palace chandelier — yes, that one\n1× «Roman» bust — yes\nStamp: «do not shake». They shook it the whole way.",
    "spawns": [
        S("sofa_velvet", 0.00, 0, -2.50, 0),
        S("wardrobe_antique", 0.50, 0, -1.25, 90, nested=["suit_pinstripe"]),
        S("statue_bronze", -0.70, 0, -1.25, 12),
        S("chandelier_crystal", 0.00, 0, 0.00, 8),
        S("fridge_smart", 0.55, 0, 1.10, -6),
        S("bust_marble", -0.70, 0, 1.10, 10),
        S("clock_grandfather_antique", 0.00, 0, 1.90, 0),
        S("typewriter_writer", -0.55, 0, 2.50, 12),
        S("camera_dslr", 0.60, 0, 2.50, -16),
        S("coin_jar_gold", 0.00, 0, 2.50, 6),
        S("book_first_edition", -1.00, 0, 1.90, 8),
        S("painting_black_square", 0.00, 0, -1.80, 4),
        S("trumpet_gold", -0.85, 0, 0.00, 70),
        S("jar_elvis_tooth", 1.00, 0, 0.00, 0),
        S("bat_signed", 1.05, 0, -2.50, 40),
        S("shoe_sneaker_rare", -1.05, 0, -2.50, -12),
    ],
})

LOTS.append({
    "id": "port_04", "district": "PORT", "kind": "PORT", "order": 4,
    "min_bid": 3200, "info": "TALE", "pacing": "BUST",
    "preview": 25, "clearout": 300, "hunters": 8, "lock_chance": 0.05,
    "joke": "container full of bricks and one lonely sneaker (the flip-flop we don't have)",
    "tale_ru": "Контейнер упал с грузовика в Дубае. Грузовик вёз шлёпанцы султана. До нас доехал один. Остальное — кирпичи. Таможня поставила печать «стройматериалы» и рассмеялась.",
    "tale_en": "This container fell off a truck in Dubai. The truck was carrying the Sultan's flip-flops. One sneaker made it. The rest is bricks. Customs stamped «building materials» and laughed.",
    "spawns": brick_stack((-0.50, 0.0, -2.40), 3, 3, 6, (0.44, 0.065, 0.72), rot=2)
    + [
        S("shoe_sneaker_single", 0.15, 0, 2.50, 35),
    ],
})

LOTS.append({
    "id": "port_05", "district": "PORT", "kind": "PORT", "order": 5,
    "min_bid": 1600, "info": "SLIT", "pacing": "JACKPOT",
    "preview": 38, "clearout": 410, "hunters": 8, "lock_chance": 0.28,
    "joke": "clown-costumed mannequin standing right at the container door to scare the winner",
    "spawns": [
        S("mannequin_creepy", 0.00, 0, 2.50, 180),
        S("costume_clown", 0.70, 0, 2.35, 170),
        S("shoe_clown", -0.70, 0, 2.45, 20),
        S("painting_sad_clown", 0.00, 0, 1.70, 4),
        S("box_moving", -0.55, 0, 0.95, 8),
        S("crate_fruit", 0.55, 0, 0.95, -8),
        S("chandelier_crystal", 0.00, 0, 0.10, 10),
        S("wardrobe_antique", 0.50, 0, -1.00, 90, nested=["fur_coat"]),
        S("bust_marble", -0.70, 0, -1.00, 12),
        S("painting_maybe_master", 0.00, 0, -1.72, 4),
        S("usb_crypto", -1.00, 0, -1.50, 0),
        S("ring_diamond", 1.00, 0, -1.50, 40),
        S("gold_bar", -0.75, 0, -2.50, 4),
        S("gold_bar", 0.75, 0, -2.50, -4),
        S("safe_old", 0.00, 0, -2.50, 0, nested=["cash_500", "cash_500"], locked=1),
        S("watch_rolecks_real", 0.00, 0.72, -2.50, 16),
        S("whiskey_50yo", -0.70, 0, -2.00, 8),
        S("vase_ming", 0.70, 0, -2.00, 10),
    ],
})

LOTS.append({
    "id": "port_06", "district": "PORT", "kind": "PORT", "order": 6,
    "min_bid": 2000, "info": "PHOTOS", "pacing": "LEAN",
    "preview": 32, "clearout": 380, "hunters": 8, "lock_chance": 0.20,
    "photos": ["chandelier_grand", "wardrobe_antique", "vase_ming", "hamster_boris"],
    "spawns": [
        S("sofa_velvet", 0.00, 0, -2.50, 0),
        S("gold_bar", -0.50, 0.85, -2.50, 4),
        S("gold_bar", 0.50, 0.85, -2.50, -4),
        S("wardrobe_antique", 0.50, 0, -1.25, 90, nested=["suit_pinstripe"]),
        S("statue_bronze", -0.70, 0, -1.25, 12),
        S("chandelier_crystal", 0.00, 0, 0.00, 8),
        S("fridge_smart", 0.55, 0, 1.10, -6),
        S("bust_marble", -0.70, 0, 1.10, 10),
        S("piano_upright", 0.00, 0, 1.90, 0),
        S("typewriter_writer", -0.55, 0, 2.55, 12),
        S("camera_dslr", 0.60, 0, 2.55, -16),
        S("book_first_edition", 0.00, 0, 2.55, 8),
        S("coin_jar_gold", -1.00, 0, 0.00, 6),
        S("necklace_pearl", 1.00, 0, 0.00, 25),
        S("bat_signed", 1.05, 0, -2.50, 40),
        S("shoe_sneaker_rare", -1.05, 0, -2.50, -10),
    ],
})


def _load_wave2() -> None:
    """Append hangar_09.. / storage_13.. / garages_09.. / port_07.. and fill empty TALE/DOCS."""
    import importlib.util
    import os

    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lots_wave2.py")
    spec = importlib.util.spec_from_file_location("cooon_lots_wave2", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    LOTS.extend(mod.build_more(S, stack_y, brick_stack, box_wall_front))
    for lot in LOTS:
        fill = mod.PREVIEW_FILL.get(lot["id"], {})
        for key in ("tale_ru", "tale_en", "docs_ru", "docs_en"):
            if fill.get(key) and not lot.get(key):
                lot[key] = fill[key]


_load_wave2()
