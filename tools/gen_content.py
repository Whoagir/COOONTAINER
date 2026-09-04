#!/usr/bin/env python3
"""COOONTAINER content generator.

Reads hand-authored source tables in tools/content/ and writes Godot 4 text resources:

  tools/content/archetypes.csv -> data/archetypes/<id>.tres   (Archetype)
  tools/content/items.csv      -> data/items/<id>.tres        (ItemDef, LootRef sub-resources)
  tools/content/hunters.json   -> data/hunters/<id>.tres      (AuctionBrain)
  tools/content/vendors.json   -> data/vendors/<id>.tres      (VendorDef)

Run from the project root:  py tools\\gen_content.py
Exit code 1 if validation found hard errors (nothing is written in that case).
"""
from __future__ import annotations

import csv
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "content"
OUT_ARCH = ROOT / "data" / "archetypes"
OUT_ITEMS = ROOT / "data" / "items"
OUT_HUNTERS = ROOT / "data" / "hunters"
OUT_VENDORS = ROOT / "data" / "vendors"

# ---- enums (mirror core/types.gd) -------------------------------------------------------------
SIZE_CLASS = {"POCKET": 0, "ONE_HAND": 1, "TWO_HAND": 2, "TEAM": 3, "VEHICLE": 4}
FACET = {
    "FRAGILE": 0, "DIRTYABLE": 1, "CONTAINER": 2, "SHAKE_OUT": 3, "LOCKED": 4, "WEARABLE": 5,
    "LIQUID": 6, "ALIVE": 7, "DOCUMENT": 8, "PATCHABLE": 9, "WEAPON": 10, "ILLEGAL": 11,
    "HEAVY_CHEAP": 12, "HEAVY_EXPENSIVE": 13,
}
LIQUID = {"none": 0, "": 0, "whiskey": 1, "paint": 2, "glue": 3, "oil": 4, "gasoline": 5, "water": 6}
VENDOR_TYPE = {"ANTIQUE": 0, "HOUSEHOLD": 1, "TECH": 2, "DARK": 3}
PHOBIA = {"NONE": 0, "MOUSE": 1, "TAPE": 2, "PAINT": 3, "WET": 4, "FIRE": 5, "HAMSTER": 6}
VENDOR_IDS = ["vendor_tiny", "vendor_antique", "vendor_household", "vendor_tech", "vendor_dark"]
CASH_IDS = {f"cash_{n}" for n in (1, 5, 10, 20, 50, 100, 500)}
REQUIRED_TOOLS = {
    "tool_flashlight": "flashlight", "tool_rag": "rag", "tool_bucket": "bucket", "tool_tape": "tape",
    "tool_lockpick": "lockpick", "tool_lighter": "lighter", "tool_matches": "matches",
    "tool_plank": "plank", "tool_nails": "nail", "tool_broom": "broom", "tool_phone": "phone",
}
HERO_ITEMS = {
    "plasma_55": "hero_plasma", "hamster_boris": "hero_hamster", "safe_old": "hero_safe",
    "gun_gag": "hero_gag_gun", "bag_work": "hero_bag", "costume_clown": "hero_costume_clown",
    "costume_unicorn": "hero_costume_unicorn",
}

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


# ---- .tres helpers ----------------------------------------------------------------------------
def fnum(v: float) -> str:
    s = f"{float(v):.4f}".rstrip("0").rstrip(".")
    if s in ("", "-0"):
        s = "0"
    if "." not in s:
        s += ".0"
    return s


def gstr(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
    return f'"{s}"'


def gbool(v) -> str:
    return "true" if truthy(v) else "false"


def truthy(v) -> bool:
    if isinstance(v, bool):
        return v
    if v is None:
        return False
    return str(v).strip().lower() in ("1", "true", "yes", "y", "x")


def gcolor(hex_or_tuple, default="ffffff") -> str:
    if isinstance(hex_or_tuple, (list, tuple)):
        r, g, b = hex_or_tuple[:3]
        a = hex_or_tuple[3] if len(hex_or_tuple) > 3 else 1.0
        return f"Color({fnum(r)}, {fnum(g)}, {fnum(b)}, {fnum(a)})"
    h = (hex_or_tuple or default).strip().lstrip("#")
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    if len(h) not in (6, 8):
        raise ValueError(f"bad color '{hex_or_tuple}'")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255.0 if len(h) == 8 else 1.0
    return f"Color({fnum(r)}, {fnum(g)}, {fnum(b)}, {fnum(a)})"


def garr_int(vals) -> str:
    return "Array[int]([" + ", ".join(str(int(v)) for v in vals) + "])"


def garr_str(vals) -> str:
    return "Array[String]([" + ", ".join(gstr(str(v)) for v in vals) + "])"


def gvec3(x, y, z) -> str:
    return f"Vector3({fnum(x)}, {fnum(y)}, {fnum(z)})"


def tres(script_class: str, script_path: str, props: list[tuple[str, str]],
         extra_ext: list[tuple[str, str]] | None = None, subs: list[tuple[str, list[tuple[str, str]]]] | None = None) -> str:
    """Build a .tres text. extra_ext: [(id, path)], subs: [(sub_id, [(k, v)])] (sub script = ext id "2")."""
    extra_ext = extra_ext or []
    subs = subs or []
    steps = 1 + 1 + len(extra_ext) + len(subs)
    out = [f'[gd_resource type="Resource" script_class="{script_class}" load_steps={steps} format=3]', ""]
    out.append(f'[ext_resource type="Script" path="{script_path}" id="1"]')
    for eid, path in extra_ext:
        out.append(f'[ext_resource type="Script" path="{path}" id="{eid}"]')
    out.append("")
    for sid, kv in subs:
        out.append(f'[sub_resource type="Resource" id="{sid}"]')
        out.append('script = ExtResource("2")')
        for k, v in kv:
            out.append(f"{k} = {v}")
        out.append("")
    out.append("[resource]")
    out.append('script = ExtResource("1")')
    for k, v in props:
        out.append(f"{k} = {v}")
    out.append("")
    return "\n".join(out)


def write_file(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def clean_dir(path: Path) -> int:
    n = 0
    if path.exists():
        for f in path.glob("*.tres"):
            f.unlink()
            n += 1
    return n


def read_csv(path: Path) -> list[dict]:
    rows = []
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = None
        for lineno, raw in enumerate(reader, start=1):
            if not raw or all(not c.strip() for c in raw):
                continue
            if raw[0].lstrip().startswith("#"):
                continue
            if header is None:
                header = [h.strip() for h in raw]
                continue
            if len(raw) != len(header):
                err(f"{path.name}:{lineno}: expected {len(header)} columns, got {len(raw)} (id={raw[0]!r})")
                continue
            row = {h: c.strip() for h, c in zip(header, raw)}
            row["_line"] = lineno
            rows.append(row)
    return rows


def split_pipe(s: str) -> list[str]:
    return [p.strip() for p in s.split("|") if p.strip()] if s else []


def ffloat(s: str, default: float) -> float:
    s = (s or "").strip()
    return float(s) if s else default


def fint(s: str, default: int) -> int:
    s = (s or "").strip()
    return int(float(s)) if s else default


# ---- archetypes --------------------------------------------------------------------------------
def load_archetypes() -> dict[str, dict]:
    rows = read_csv(SRC / "archetypes.csv")
    out: dict[str, dict] = {}
    for r in rows:
        aid = r["id"]
        if not aid:
            err(f"archetypes.csv:{r['_line']}: empty id")
            continue
        if aid in out:
            err(f"archetypes.csv:{r['_line']}: duplicate archetype id {aid}")
            continue
        size = r.get("size_class", "ONE_HAND").upper() or "ONE_HAND"
        if size not in SIZE_CLASS:
            err(f"archetypes.csv:{r['_line']}: bad size_class {size}")
            continue
        a = {
            "id": aid,
            "builder": r.get("builder") or aid,
            "size_class": size,
            "dims": (ffloat(r.get("dx"), 0.3), ffloat(r.get("dy"), 0.3), ffloat(r.get("dz"), 0.3)),
            "mass": ffloat(r.get("mass"), 1.0),
            "shards": fint(r.get("shards"), 5),
            "container": truthy(r.get("container")),
            "capacity": fint(r.get("capacity"), 3),
            "cloth": truthy(r.get("cloth")),
            "light": truthy(r.get("light_fixture")),
            "base_color": r.get("base_color") or "cccccc",
            "secondary_color": r.get("secondary_color") or "666666",
            "friction": ffloat(r.get("friction"), 0.8),
            "bounce": ffloat(r.get("bounce"), 0.05),
        }
        if not 3 <= a["shards"] <= 8:
            warn(f"archetype {aid}: shard_count {a['shards']} outside 3..8")
        out[aid] = a
    return out


def write_archetype(a: dict) -> None:
    props = [
        ("id", gstr(a["id"])),
        ("builder", gstr(a["builder"])),
        ("shard_count", str(a["shards"])),
        ("size_class", str(SIZE_CLASS[a["size_class"]])),
        ("mass_default", fnum(a["mass"])),
        ("dims", gvec3(*a["dims"])),
        ("cloth", gbool(a["cloth"])),
        ("container", gbool(a["container"])),
        ("container_capacity", str(a["capacity"])),
        ("light_fixture", gbool(a["light"])),
        ("base_color", gcolor(a["base_color"])),
        ("secondary_color", gcolor(a["secondary_color"])),
        ("friction", fnum(a["friction"])),
        ("bounce", fnum(a["bounce"])),
    ]
    write_file(OUT_ARCH / f"{a['id']}.tres", tres("Archetype", "res://core/Archetype.gd", props))


# ---- items -------------------------------------------------------------------------------------
ITEM_COLUMNS = [
    "id", "name_ru", "name_en", "archetype_id", "facets", "value_base", "mass_override", "liquid_id",
    "liquid_amount", "flammable", "illegal", "dusty_default", "nest_loot", "vendor_affinity",
    "wearable_slot", "break_threshold", "color", "scale", "tags", "lore_ru", "lore_en",
]


def norm_vendor(v: str) -> str:
    v = v.strip()
    if not v:
        return ""
    return v if v.startswith("vendor_") else f"vendor_{v}"


def default_break(facets: set[int]) -> float:
    if FACET["FRAGILE"] in facets:
        return 4.5
    if FACET["HEAVY_CHEAP"] in facets or FACET["HEAVY_EXPENSIVE"] in facets:
        return 60.0
    return 25.0


def default_vendors(facets: set[int], tags: list[str], illegal: bool) -> list[str]:
    out: list[str] = []
    if illegal or FACET["WEAPON"] in facets:
        out.append("vendor_dark")
    if FACET["FRAGILE"] in facets or FACET["DOCUMENT"] in facets:
        out.append("vendor_antique")
    if any(t in tags for t in ("electronics", "tech")):
        out.append("vendor_tech")
    if FACET["CONTAINER"] in facets or FACET["DIRTYABLE"] in facets:
        out.append("vendor_household")
    if not out:
        out.append("vendor_tiny")
    return out


def load_items(archs: dict[str, dict]) -> list[dict]:
    rows = read_csv(SRC / "items.csv")
    if rows:
        missing = [c for c in ITEM_COLUMNS if c not in rows[0]]
        if missing:
            err(f"items.csv: missing columns {missing}")
            return []
    items: list[dict] = []
    seen: set[str] = set()
    for r in rows:
        iid = r["id"]
        line = r["_line"]
        if not iid:
            err(f"items.csv:{line}: empty id")
            continue
        if iid in seen:
            err(f"items.csv:{line}: duplicate item id {iid}")
            continue
        if iid.startswith("cash_"):
            err(f"items.csv:{line}: cash_* items are generated by Registry, remove {iid}")
            continue
        seen.add(iid)
        facets: list[int] = []
        for fname in split_pipe(r["facets"]):
            if fname not in FACET:
                err(f"items.csv:{line}: unknown facet {fname}")
            elif FACET[fname] not in facets:
                facets.append(FACET[fname])
        fset = set(facets)
        liquid_name = (r["liquid_id"] or "none").lower()
        if liquid_name not in LIQUID:
            err(f"items.csv:{line}: unknown liquid {liquid_name}")
            liquid_name = "none"
        liquid = LIQUID[liquid_name]
        if liquid and FACET["LIQUID"] not in fset:
            facets.append(FACET["LIQUID"])
            fset.add(FACET["LIQUID"])
        illegal = truthy(r["illegal"]) or FACET["ILLEGAL"] in fset
        if illegal and FACET["ILLEGAL"] not in fset:
            facets.append(FACET["ILLEGAL"])
            fset.add(FACET["ILLEGAL"])
        tags = split_pipe(r["tags"])
        nest: list[tuple[str, float, int, int]] = []
        for spec in split_pipe(r["nest_loot"]):
            parts = spec.split(":")
            if not 1 <= len(parts) <= 4:
                err(f"items.csv:{line}: bad nest_loot entry '{spec}'")
                continue
            lid = parts[0]
            ch = float(parts[1]) if len(parts) > 1 and parts[1] else 1.0
            mn = int(parts[2]) if len(parts) > 2 and parts[2] else 1
            mx = int(parts[3]) if len(parts) > 3 and parts[3] else mn
            if mx < mn:
                mx = mn
            nest.append((lid, ch, mn, mx))
        vendors = [norm_vendor(v) for v in split_pipe(r["vendor_affinity"])]
        if not vendors:
            vendors = default_vendors(fset, tags, illegal)
        for v in vendors:
            if v not in VENDOR_IDS:
                err(f"items.csv:{line}: unknown vendor {v}")
        try:
            value = int(float(r["value_base"]))
        except ValueError:
            err(f"items.csv:{line}: bad value_base {r['value_base']!r}")
            value = 1
        color = r["color"].strip()
        if color:
            try:
                gcolor(color)
            except ValueError as e:
                err(f"items.csv:{line}: {e}")
                color = ""
        wearable = r["wearable_slot"] or ("body" if FACET["WEARABLE"] in fset else "none")
        if FACET["WEARABLE"] in fset and wearable == "none":
            wearable = "body"
        item = {
            "id": iid,
            "line": line,
            "name_ru": r["name_ru"],
            "name_en": r["name_en"],
            "archetype_id": r["archetype_id"],
            "facets": facets,
            "value_base": value,
            "mass_override": ffloat(r["mass_override"], 0.0),
            "liquid_id": liquid,
            "liquid_amount": ffloat(r["liquid_amount"], 1.0),
            "flammable": truthy(r["flammable"]) or liquid in (LIQUID["gasoline"],),
            "illegal": illegal,
            "dusty_default": ffloat(r["dusty_default"], 0.0),
            "nest_loot": nest,
            "vendor_affinity": vendors,
            "wearable_slot": wearable,
            "break_threshold": ffloat(r["break_threshold"], default_break(fset)),
            "color": color,
            "scale": ffloat(r["scale"], 1.0),
            "tags": tags,
            "lore_ru": r["lore_ru"],
            "lore_en": r["lore_en"],
        }
        if item["archetype_id"] not in archs:
            err(f"items.csv:{line}: item {iid} -> unknown archetype {item['archetype_id']}")
        for nm, val in (("name_ru", item["name_ru"]), ("name_en", item["name_en"])):
            if not val:
                err(f"items.csv:{line}: {iid} has empty {nm}")
            elif len(val) > 28:
                warn(f"items.csv:{line}: {iid} {nm} is {len(val)} chars (>28): {val}")
        if item["dusty_default"] > 0 and FACET["DIRTYABLE"] not in fset:
            warn(f"items.csv:{line}: {iid} is dusty but not DIRTYABLE (cannot be scrubbed clean)")
        if nest and not (FACET["CONTAINER"] in fset or FACET["SHAKE_OUT"] in fset or archs.get(item["archetype_id"], {}).get("container")):
            warn(f"items.csv:{line}: {iid} has nest_loot but is not CONTAINER/SHAKE_OUT and archetype is not a container")
        items.append(item)
    return items


def validate_items(items: list[dict], archs: dict[str, dict]) -> None:
    by_id = {i["id"]: i for i in items}
    # nest references + depth + size compatibility
    for it in items:
        a = archs.get(it["archetype_id"])
        for lid, ch, mn, mx in it["nest_loot"]:
            if lid in CASH_IDS:
                continue
            child = by_id.get(lid)
            if child is None:
                err(f"item {it['id']}: nest_loot references unknown item {lid}")
                continue
            if lid == it["id"]:
                err(f"item {it['id']}: nests itself")
            ca = archs.get(child["archetype_id"])
            if a and ca:
                ps, cs = SIZE_CLASS[a["size_class"]], SIZE_CLASS[ca["size_class"]]
                if not (cs < ps or cs == 0):
                    warn(f"item {it['id']} ({a['size_class']}) cannot physically hold {lid} ({ca['size_class']})")
            if not 0.0 < ch <= 1.0:
                warn(f"item {it['id']}: nest chance {ch} for {lid} outside (0,1]")

    def depth(iid: str, seen: tuple) -> int:
        it = by_id.get(iid)
        if it is None or not it["nest_loot"]:
            return 0
        if iid in seen:
            err(f"nest_loot cycle: {' -> '.join(seen + (iid,))}")
            return 0
        return 1 + max(depth(l[0], seen + (iid,)) for l in it["nest_loot"])

    for it in items:
        d = depth(it["id"], ())
        if d > 2:
            err(f"item {it['id']}: nesting depth {d} > 2 (max is suitcase -> book -> cash)")
    # required tools and heroes
    for tid, tag in REQUIRED_TOOLS.items():
        it = by_id.get(tid)
        if it is None:
            err(f"missing required tool item {tid}")
        elif tag not in it["tags"]:
            err(f"tool {tid} must have tag '{tag}'")
    for hid, harch in HERO_ITEMS.items():
        it = by_id.get(hid)
        if it is None:
            err(f"missing hero item {hid}")
        elif it["archetype_id"] != harch:
            err(f"hero item {hid} must use archetype {harch}, has {it['archetype_id']}")
    for hero_arch in HERO_ITEMS.values():
        if hero_arch not in archs:
            err(f"missing hero archetype {hero_arch}")
    if "bill" not in archs:
        warn("no 'bill' archetype in archetypes.csv (Registry will synthesize one)")


def write_item(it: dict) -> None:
    subs: list[tuple[str, list[tuple[str, str]]]] = []
    for i, (lid, ch, mn, mx) in enumerate(it["nest_loot"], start=1):
        subs.append((f"lr{i}", [
            ("item_id", gstr(lid)),
            ("chance", fnum(ch)),
            ("count_min", str(mn)),
            ("count_max", str(mx)),
        ]))
    props: list[tuple[str, str]] = [
        ("id", gstr(it["id"])),
        ("name_ru", gstr(it["name_ru"])),
        ("name_en", gstr(it["name_en"])),
        ("archetype_id", gstr(it["archetype_id"])),
        ("facets", garr_int(it["facets"])),
        ("value_base", str(it["value_base"])),
        ("mass_override", fnum(it["mass_override"])),
        ("liquid_id", str(it["liquid_id"])),
        ("liquid_amount", fnum(it["liquid_amount"])),
        ("flammable", gbool(it["flammable"])),
        ("illegal", gbool(it["illegal"])),
        ("dusty_default", fnum(it["dusty_default"])),
    ]
    if subs:
        props.append(("nest_loot", "Array[Resource]([" + ", ".join(f'SubResource("{sid}")' for sid, _ in subs) + "])"))
    props += [
        ("vendor_affinity", garr_str(it["vendor_affinity"])),
        ("wearable_slot", gstr(it["wearable_slot"])),
        ("break_threshold", fnum(it["break_threshold"])),
        ("color", gcolor(it["color"] or "ffffff")),
        ("scale", fnum(it["scale"])),
        ("tags", garr_str(it["tags"])),
        ("lore_ru", gstr(it["lore_ru"])),
        ("lore_en", gstr(it["lore_en"])),
    ]
    extra = [("2", "res://core/LootRef.gd")] if subs else []
    write_file(OUT_ITEMS / f"{it['id']}.tres", tres("ItemDef", "res://core/ItemDef.gd", props, extra, subs))


# ---- hunters -----------------------------------------------------------------------------------
def write_hunters() -> int:
    data = json.loads((SRC / "hunters.json").read_text(encoding="utf-8"))
    ids: set[str] = set()
    n = 0
    for h in data:
        hid = h["id"]
        if hid in ids:
            err(f"hunters.json: duplicate id {hid}")
            continue
        ids.add(hid)
        for key in ("catchphrases_ru", "catchphrases_en"):
            if len(h.get(key, [])) < 5:
                warn(f"hunter {hid}: {key} has fewer than 5 lines")
        props = [
            ("id", gstr(hid)),
            ("name_ru", gstr(h["name_ru"])),
            ("name_en", gstr(h["name_en"])),
            ("nickname_ru", gstr(h["nickname_ru"])),
            ("nickname_en", gstr(h["nickname_en"])),
            ("estimate_error", fnum(h["estimate_error"])),
            ("greed", fnum(h["greed"])),
            ("bluff_chance", fnum(h["bluff_chance"])),
            ("setup_chance", fnum(h["setup_chance"])),
            ("patience", fnum(h["patience"])),
            ("aggression", fnum(h["aggression"])),
            ("brawl_temper", fnum(h["brawl_temper"])),
            ("info_sensitivity", fnum(h["info_sensitivity"])),
            ("body_color", gcolor(h["body_color"])),
            ("hat", gbool(h.get("hat", False))),
            ("bald", gbool(h.get("bald", False))),
            ("voice_pitch", fnum(h.get("voice_pitch", 1.0))),
            ("voice_group", gstr(h.get("voice_group", "hunter"))),
            ("catchphrases_ru", garr_str(h["catchphrases_ru"])),
            ("catchphrases_en", garr_str(h["catchphrases_en"])),
            ("height", fnum(h.get("height", 1.75))),
            ("fatness", fnum(h.get("fatness", 1.0))),
        ]
        write_file(OUT_HUNTERS / f"{hid}.tres", tres("AuctionBrain", "res://core/AuctionBrain.gd", props))
        n += 1
    expected = {f"hunter_{i:02d}" for i in range(1, 9)}
    if ids != expected:
        err(f"hunters.json: ids must be exactly hunter_01..hunter_08, got {sorted(ids)}")
    return n


# ---- vendors -----------------------------------------------------------------------------------
def write_vendors() -> int:
    data = json.loads((SRC / "vendors.json").read_text(encoding="utf-8"))
    ids: set[str] = set()
    n = 0
    for v in data:
        vid = v["id"]
        if vid in ids:
            err(f"vendors.json: duplicate id {vid}")
            continue
        ids.add(vid)
        vt = v["vendor_type"].upper()
        if vt not in VENDOR_TYPE:
            err(f"vendor {vid}: bad vendor_type {vt}")
            continue
        phobias = []
        for p in v.get("phobias", []):
            if p.upper() not in PHOBIA:
                err(f"vendor {vid}: bad phobia {p}")
            else:
                phobias.append(PHOBIA[p.upper()])
        fav = [FACET[f] for f in v.get("favorite_facets", [])]
        hate = [FACET[f] for f in v.get("hated_facets", [])]
        req = v.get("unlock_requires_vendor", "")
        if req and req not in VENDOR_IDS:
            err(f"vendor {vid}: unlock_requires_vendor {req} unknown")
        for key in ("greet", "scream", "deal", "reject", "phobia"):
            for lang in ("ru", "en"):
                if len(v.get(f"lines_{key}_{lang}", [])) < 5:
                    warn(f"vendor {vid}: lines_{key}_{lang} has fewer than 5 lines")
        props = [
            ("id", gstr(vid)),
            ("name_ru", gstr(v["name_ru"])),
            ("name_en", gstr(v["name_en"])),
            ("vendor_type", str(VENDOR_TYPE[vt])),
            ("phobias", garr_int(phobias)),
            ("favorite_facets", garr_int(fav)),
            ("hated_facets", garr_int(hate)),
            ("base_multiplier", fnum(v["base_multiplier"])),
            ("buys_illegal", gbool(v.get("buys_illegal", False))),
            ("calls_police_on_illegal", gbool(v.get("calls_police_on_illegal", True))),
            ("green_zone_base", fnum(v.get("green_zone_base", 0.35))),
            ("greed", fnum(v.get("greed", 0.5))),
            ("unlock_cost", str(int(v.get("unlock_cost", 0)))),
            ("unlock_requires_vendor", gstr(req)),
            ("body_color", gcolor(v["body_color"])),
            ("voice_pitch", fnum(v.get("voice_pitch", 1.0))),
        ]
        for key in ("greet", "scream", "deal", "reject", "phobia"):
            for lang in ("ru", "en"):
                k = f"lines_{key}_{lang}"
                props.append((k, garr_str(v.get(k, []))))
        write_file(OUT_VENDORS / f"{vid}.tres", tres("VendorDef", "res://core/VendorDef.gd", props))
        n += 1
    if ids != set(VENDOR_IDS):
        err(f"vendors.json: ids must be exactly {VENDOR_IDS}, got {sorted(ids)}")
    return n


# ---- report ------------------------------------------------------------------------------------
def report(items: list[dict], archs: dict[str, dict]) -> None:
    tiers = [("$1-15", 1, 15), ("$15-60", 16, 60), ("$60-250", 61, 250), ("$250-1500", 251, 1500), ("$1500-5000", 1501, 5000)]
    total = len(items)
    print(f"items: {total}")
    for name, lo, hi in tiers:
        n = sum(1 for i in items if lo <= i["value_base"] <= hi)
        print(f"  {name:>11}: {n:4d}  ({100.0 * n / max(1, total):4.1f}%)")
    over = [i["id"] for i in items if i["value_base"] > 5000 or i["value_base"] < 1]
    if over:
        warn(f"values outside $1..$5000: {over}")
    builder_use: Counter = Counter()
    for it in items:
        a = archs.get(it["archetype_id"])
        if a:
            builder_use[a["builder"]] += 1
    all_builders = sorted({a["builder"] for a in archs.values()})
    under = [b for b in all_builders if builder_use[b] < 3]
    print(f"archetypes: {len(archs)}  builders: {len(all_builders)}  builders used <3 times: {under if under else 'none'}")
    facet_use: Counter = Counter()
    for it in items:
        for f in it["facets"]:
            facet_use[f] += 1
    inv = {v: k for k, v in FACET.items()}
    print("facets: " + ", ".join(f"{inv[k]}={facet_use[k]}" for k in sorted(facet_use)))
    print(f"jackpots (>=1500): {[i['id'] for i in items if i['value_base'] >= 1500]}")


def main() -> int:
    archs = load_archetypes()
    items = load_items(archs)
    validate_items(items, archs)
    # hunters/vendors are validated while writing; do a dry parse first for hard errors
    try:
        json.loads((SRC / "hunters.json").read_text(encoding="utf-8"))
        json.loads((SRC / "vendors.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        err(f"json: {e}")
    if errors:
        print(f"{len(errors)} error(s), nothing written:")
        for e in errors:
            print("  ERROR " + e)
        for w in warnings:
            print("  warn  " + w)
        return 1
    removed = sum(clean_dir(p) for p in (OUT_ARCH, OUT_ITEMS, OUT_HUNTERS, OUT_VENDORS))
    for a in archs.values():
        write_archetype(a)
    for it in items:
        write_item(it)
    nh = write_hunters()
    nv = write_vendors()
    if errors:
        for e in errors:
            print("  ERROR " + e)
    for w in warnings:
        print("  warn  " + w)
    print(f"removed {removed} old .tres; wrote archetypes={len(archs)} items={len(items)} hunters={nh} vendors={nv}")
    report(items, archs)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
