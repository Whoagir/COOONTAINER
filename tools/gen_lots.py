#!/usr/bin/env python3
"""COOONTAINER lot preset generator.

Reads hand-authored lots from tools/content/lots.py and writes Godot 4
LotPreset text resources to data/lots/<id>.tres.

Run from the project root:  py tools\\gen_lots.py

Validates every item_id against data/items/*.tres (plus Registry cash_*),
checks each spawn sits inside its cell, and warns on AABB gaps < 0.12 m.
Hard errors (unknown ids, out of bounds, true interpenetration) abort the write.
"""
from __future__ import annotations

import csv
import importlib.util
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "content"
OUT_LOTS = ROOT / "data" / "lots"
ITEMS_DIR = ROOT / "data" / "items"
ARCH_CSV = SRC / "archetypes.csv"
ITEMS_CSV = SRC / "items.csv"

DISTRICT = {"TRAILER_PARK": 0, "HANGAR": 1, "STORAGE": 2, "GARAGES": 3, "PORT": 4}
LOT_KIND = {"BAG": 0, "LOCKER": 1, "STORAGE": 2, "GARAGE": 3, "PORT": 4}
INFO_MODE = {"DOOR15": 0, "SLIT": 1, "PHOTOS": 2, "DOCS": 3, "TALE": 4}
PACING = {"LEAN": 0, "JACKPOT": 1, "BUST": 2}

CELL_SIZE = {
    "BAG": (1.5, 1.2, 1.5),
    "LOCKER": (1.0, 2.0, 1.0),
    "STORAGE": (3.0, 2.5, 3.0),
    "GARAGE": (5.0, 3.0, 6.0),
    "PORT": (2.3, 2.4, 6.0),
}

# Registry synthesizes these even if no .tres exists.
CASH_IDS = {f"cash_{n}" for n in (1, 5, 10, 20, 50, 100, 500)}
CASH_DIMS = (0.156, 0.002, 0.066)
CASH_VALUE = {f"cash_{n}": n for n in (1, 5, 10, 20, 50, 100, 500)}

# Campaign EV (§ task): win 60% of bids, vendor 0.6×, lose 15% of fragile value.
WIN_RATE = 0.60
VENDOR = 0.60
BREAK_FRAGILE = 0.15

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def fnum(v: float) -> str:
    s = f"{float(v):.4f}".rstrip("0").rstrip(".")
    if s in ("", "-0"):
        s = "0"
    if "." not in s:
        s += ".0"
    return s


def gstr(s: str) -> str:
    s = (s or "").replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
    return f'"{s}"'


def gbool(v) -> str:
    return "true" if v else "false"


def garr_str(vals) -> str:
    return "Array[String]([" + ", ".join(gstr(str(v)) for v in vals) + "])"


def gvec3(x, y, z) -> str:
    return f"Vector3({fnum(x)}, {fnum(y)}, {fnum(z)})"


def yrot_xform(x: float, y: float, z: float, deg: float) -> str:
    th = math.radians(deg)
    c, s = math.cos(th), math.sin(th)
    return (
        f"Transform3D({fnum(c)}, 0, {fnum(-s)}, 0, 1.0, 0, "
        f"{fnum(s)}, 0, {fnum(c)}, {fnum(x)}, {fnum(y)}, {fnum(z)})"
    )


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
        for raw in reader:
            if not raw or all(not c.strip() for c in raw):
                continue
            if raw[0].lstrip().startswith("#"):
                continue
            if header is None:
                header = [h.strip() for h in raw]
                continue
            row = {h: (raw[i].strip() if i < len(raw) else "") for i, h in enumerate(header)}
            rows.append(row)
    return rows


def load_archetypes() -> dict[str, dict]:
    out = {}
    for r in read_csv(ARCH_CSV):
        aid = r["id"]
        out[aid] = {
            "id": aid,
            "size_class": (r.get("size_class") or "ONE_HAND").upper(),
            "dims": (float(r["dx"] or 0.3), float(r["dy"] or 0.3), float(r["dz"] or 0.3)),
        }
    return out


def load_item_catalog(archs: dict[str, dict]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for r in read_csv(ITEMS_CSV):
        iid = r["id"]
        if not iid:
            continue
        facets = {p.strip() for p in (r.get("facets") or "").split("|") if p.strip()}
        try:
            scale = float(r["scale"]) if r.get("scale") else 1.0
        except ValueError:
            scale = 1.0
        if scale <= 0:
            scale = 1.0
        try:
            value = int(float(r["value_base"]))
        except (ValueError, TypeError):
            value = 0
        arch_id = r.get("archetype_id") or "box_small"
        dims = archs.get(arch_id, {}).get("dims", (0.3, 0.3, 0.3))
        out[iid] = {
            "id": iid,
            "archetype_id": arch_id,
            "value_base": value,
            "facets": facets,
            "scale": scale,
            "dims": (dims[0] * scale, dims[1] * scale, dims[2] * scale),
            "size_class": archs.get(arch_id, {}).get("size_class", "ONE_HAND"),
            "tags": [p.strip() for p in (r.get("tags") or "").split("|") if p.strip()],
        }
    for cid, val in CASH_VALUE.items():
        out[cid] = {
            "id": cid,
            "archetype_id": "bill",
            "value_base": val,
            "facets": {"DOCUMENT"},
            "scale": 1.0,
            "dims": CASH_DIMS,
            "size_class": "POCKET",
            "tags": [],
        }
    return out


def tres_ids_on_disk() -> set[str]:
    if not ITEMS_DIR.exists():
        return set()
    return {p.stem for p in ITEMS_DIR.glob("*.tres")}


def load_source() -> list[dict]:
    path = SRC / "lots.py"
    if not path.exists():
        err(f"missing source table {path}")
        return []
    spec = importlib.util.spec_from_file_location("cooon_lots", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    lots = list(getattr(mod, "LOTS", []))
    if not lots:
        err("tools/content/lots.py: LOTS is empty")
    return lots


def footprint(dx: float, dz: float, deg: float) -> tuple[float, float]:
    th = math.radians(deg)
    c, s = abs(math.cos(th)), abs(math.sin(th))
    hx, hz = dx * 0.5, dz * 0.5
    return hx * c + hz * s, hx * s + hz * c


def spawn_aabb(sp: dict, item: dict) -> tuple[float, float, float, float, float, float]:
    dx, dy, dz = item["dims"]
    hx, hz = footprint(dx, dz, sp["rot_y"])
    x, y, z = sp["x"], sp["y"], sp["z"]
    return x - hx, x + hx, y, y + dy, z - hz, z + hz


def gap_1d(a0: float, a1: float, b0: float, b1: float) -> float:
    if a1 < b0:
        return b0 - a1
    if b1 < a0:
        return a0 - b1
    return 0.0  # overlap / touch


def expected_net(value: int, fragile: int, min_bid: int) -> float:
    surviving = value - BREAK_FRAGILE * fragile
    return WIN_RATE * (VENDOR * surviving - min_bid)


def validate_lot(lot: dict, catalog: dict[str, dict], disk_ids: set[str]) -> dict:
    lid = lot.get("id", "?")
    kind = lot.get("kind", "")
    district = lot.get("district", "")
    info = lot.get("info", "")
    pacing = lot.get("pacing", "")
    if district not in DISTRICT:
        err(f"{lid}: unknown district {district}")
    if kind not in LOT_KIND:
        err(f"{lid}: unknown kind {kind}")
    if info not in INFO_MODE:
        err(f"{lid}: unknown info_mode {info}")
    if pacing not in PACING:
        err(f"{lid}: unknown pacing {pacing}")

    expected_id = f"{district.lower()}_{int(lot.get('order', 0)):02d}"
    if district != "TRAILER_PARK" and lid != expected_id:
        err(f"{lid}: id must be <district>_<NN> matching order, expected {expected_id}")

    cell = lot.get("cell") or CELL_SIZE.get(kind)
    if not cell:
        err(f"{lid}: no cell size")
        cell = (3.0, 2.5, 3.0)
    cx, cy, cz = cell
    hx, hz = cx * 0.5, cz * 0.5

    unknown: list[str] = []
    value = 0
    fragile = 0
    count = 0
    aabbs: list[tuple[str, tuple[float, float, float, float, float, float]]] = []

    def consume(iid: str, where: str, check_bounds: bool, sp: dict | None) -> None:
        nonlocal value, fragile, count
        count += 1
        if iid not in disk_ids and iid not in CASH_IDS:
            unknown.append(f"{iid} ({where})")
            return
        item = catalog.get(iid)
        if item is None:
            unknown.append(f"{iid} ({where}, no catalog row)")
            return
        value += item["value_base"]
        if "FRAGILE" in item["facets"]:
            fragile += item["value_base"]
        if check_bounds and sp is not None:
            x0, x1, y0, y1, z0, z1 = spawn_aabb(sp, item)
            pad = 0.002
            if x0 < -hx - pad or x1 > hx + pad or z0 < -hz - pad or z1 > hz + pad:
                err(
                    f"{lid}: {iid} @ ({sp['x']:.2f},{sp['y']:.2f},{sp['z']:.2f}) "
                    f"rot={sp['rot_y']:.0f} AABB x[{x0:.2f},{x1:.2f}] z[{z0:.2f},{z1:.2f}] "
                    f"outside cell ±{hx:.2f}/±{hz:.2f}"
                )
            if y0 < -0.01 or y1 > cy + 0.02:
                err(
                    f"{lid}: {iid} y[{y0:.2f},{y1:.2f}] outside cell height 0..{cy:.2f}"
                )
            aabbs.append((iid, (x0, x1, y0, y1, z0, z1)))

    for i, sp in enumerate(lot.get("spawns") or []):
        iid = sp.get("item_id", "")
        consume(iid, f"spawn[{i}]", True, sp)
        nested = sp.get("nested") or []
        if len(nested) > 2:
            err(f"{lid}: spawn[{i}] {iid} nested depth {len(nested)} > 2")
        for n in nested:
            consume(n, f"spawn[{i}].nested of {iid}", False, None)

    if unknown:
        err(f"{lid}: unknown item id(s): {', '.join(unknown)}")

    # Overlaps — skip deliberate vertical stacks (contact on Y, overlap on XZ).
    for i in range(len(aabbs)):
        id_a, a = aabbs[i]
        for j in range(i + 1, len(aabbs)):
            id_b, b = aabbs[j]
            gx = gap_1d(a[0], a[1], b[0], b[1])
            gy = gap_1d(a[2], a[3], b[2], b[3])
            gz = gap_1d(a[4], a[5], b[4], b[5])
            stacked = gy <= 0.03 and (abs(a[2] - b[3]) <= 0.03 or abs(b[2] - a[3]) <= 0.03)
            if gx == 0.0 and gz == 0.0 and gy == 0.0 and not stacked:
                # true 3D penetration
                pen_x = min(a[1], b[1]) - max(a[0], b[0])
                pen_y = min(a[3], b[3]) - max(a[2], b[2])
                pen_z = min(a[5], b[5]) - max(a[4], b[4])
                if min(pen_x, pen_y, pen_z) > 0.02:
                    err(
                        f"{lid}: overlap {id_a} vs {id_b} "
                        f"pen=({pen_x:.2f},{pen_y:.2f},{pen_z:.2f})"
                    )
                    continue
            horiz = math.hypot(gx, gz) if (gx > 0 or gz > 0) else 0.0
            # "closer than 0.12 m": smallest separating gap on XZ while they share Y
            if gy == 0.0 and not stacked:
                sep = min(gx, gz) if (gx > 0 and gz > 0) else (gx if gx > 0 else gz)
                if 0.0 < sep < 0.12:
                    warn(f"{lid}: {id_a} vs {id_b} gap {sep:.3f} m < 0.12")
                elif gx == 0.0 and gz == 0.0:
                    warn(f"{lid}: {id_a} vs {id_b} touching in XZ (gap 0)")

    photos = lot.get("photos") or []
    spawn_ids = {s["item_id"] for s in lot.get("spawns") or []}
    for nlist in (s.get("nested") or [] for s in lot.get("spawns") or []):
        spawn_ids.update(nlist)
    if info == "PHOTOS":
        if len(photos) < 2:
            warn(f"{lid}: PHOTOS lot should list photo_item_ids")
        lies = [p for p in photos if p not in spawn_ids]
        if len(lies) < 1:
            warn(f"{lid}: PHOTOS should include 1–2 items that are NOT in the lot")
        for p in photos:
            if p not in disk_ids and p not in CASH_IDS:
                err(f"{lid}: photo_item_id unknown {p}")

    if not lot.get("docs_ru") or not lot.get("docs_en"):
        err(f"{lid}: needs docs_ru and docs_en (preview copy, all lots)")
    if not lot.get("tale_ru") or not lot.get("tale_en"):
        err(f"{lid}: needs tale_ru and tale_en (preview copy, all lots)")

    min_bid = int(lot.get("min_bid", 0))
    if pacing == "BUST" and value >= min_bid:
        warn(f"{lid}: bust value_base ${value} >= min_bid ${min_bid} (should be trash vs start)")

    order = int(lot.get("order", 0))
    wave2 = (
        (district == "HANGAR" and order > 8)
        or (district == "STORAGE" and order > 12)
        or (district == "GARAGES" and order > 8)
        or (district == "PORT" and order > 6)
    )
    if wave2:
        if kind == "BAG" and not (8 <= count <= 14):
            warn(f"{lid}: BAG item count {count} not in 8–14")
        elif kind == "LOCKER" and not (8 <= count <= 14):
            warn(f"{lid}: LOCKER item count {count} not in 8–14")
        elif kind == "STORAGE" and not (18 <= count <= 35):
            warn(f"{lid}: STORAGE item count {count} not in 18–35")
        elif kind == "GARAGE" and not (30 <= count <= 45):
            warn(f"{lid}: GARAGE item count {count} not in 30–45")
        elif kind == "PORT" and not (40 <= count <= 60):
            warn(f"{lid}: PORT item count {count} not in 40–60")

    net = expected_net(value, fragile, min_bid)
    return {
        "id": lid,
        "district": district,
        "kind": kind,
        "pacing": pacing,
        "info": info,
        "count": count,
        "value": value,
        "fragile": fragile,
        "min_bid": min_bid,
        "net": net,
        "order": int(lot.get("order", 0)),
        "joke": lot.get("joke") or "",
    }


def write_lot(lot: dict) -> None:
    kind = lot["kind"]
    cell = lot.get("cell") or CELL_SIZE[kind]
    spawns = lot.get("spawns") or []
    subs: list[tuple[str, list[tuple[str, str]]]] = []
    for i, sp in enumerate(spawns, start=1):
        sid = f"s{i}"
        kv = [
            ("item_id", gstr(sp["item_id"])),
            ("xform", yrot_xform(sp["x"], sp["y"], sp["z"], sp["rot_y"])),
            ("nested", garr_str(sp.get("nested") or [])),
            ("locked_override", str(int(sp.get("locked", -1)))),
            ("dirt_override", fnum(float(sp.get("dirt", -1.0)))),
        ]
        subs.append((sid, kv))

    steps = 2 + len(subs)
    out = [
        f'[gd_resource type="Resource" script_class="LotPreset" load_steps={steps} format=3]',
        "",
        '[ext_resource type="Script" path="res://core/LotPreset.gd" id="1"]',
        '[ext_resource type="Script" path="res://core/LotSpawn.gd" id="2"]',
        "",
    ]
    for sid, kv in subs:
        out.append(f'[sub_resource type="Resource" id="{sid}"]')
        out.append('script = ExtResource("2")')
        for k, v in kv:
            out.append(f"{k} = {v}")
        out.append("")
    spawn_ref = "Array[Resource]([" + ", ".join(f'SubResource("{sid}")' for sid, _ in subs) + "])"
    props = [
        ("id", gstr(lot["id"])),
        ("district_id", str(DISTRICT[lot["district"]])),
        ("lot_kind", str(LOT_KIND[kind])),
        ("min_bid", str(int(lot["min_bid"]))),
        ("info_mode", str(INFO_MODE[lot["info"]])),
        ("preview_seconds", fnum(float(lot["preview"]))),
        ("clearout_seconds", fnum(float(lot["clearout"]))),
        ("lock_chance", fnum(float(lot.get("lock_chance", 0.0)))),
        ("spawn_list", spawn_ref),
        ("pacing_tag", str(PACING[lot["pacing"]])),
        ("broom_required", gbool(lot.get("broom", False))),
        ("hunters_count", str(int(lot.get("hunters", 6)))),
        ("order", str(int(lot["order"]))),
        ("tale_ru", gstr(lot.get("tale_ru", ""))),
        ("tale_en", gstr(lot.get("tale_en", ""))),
        ("docs_ru", gstr(lot.get("docs_ru", ""))),
        ("docs_en", gstr(lot.get("docs_en", ""))),
        ("photo_item_ids", garr_str(lot.get("photos") or [])),
        ("cell_size", gvec3(*cell)),
        ("dark", gbool(lot.get("dark", False))),
    ]
    out.append("[resource]")
    out.append('script = ExtResource("1")')
    for k, v in props:
        out.append(f"{k} = {v}")
    out.append("")
    write_file(OUT_LOTS / f"{lot['id']}.tres", "\n".join(out))


def print_summary(stats: list[dict]) -> None:
    print()
    print(
        f"{'id':<14} {'n':>3} {'value':>7} {'frag':>6} {'bid':>6} {'net':>8} {'tag':<8} info"
    )
    print("-" * 72)
    by_d: dict[str, list[dict]] = defaultdict(list)
    for s in stats:
        print(
            f"{s['id']:<14} {s['count']:3d} {s['value']:7d} {s['fragile']:6d} "
            f"{s['min_bid']:6d} {s['net']:8.0f} {s['pacing']:<8} {s['info']}"
        )
        by_d[s["district"]].append(s)
    print("-" * 72)
    grand_v = grand_bid = 0
    grand_net = 0.0
    grand_n = 0
    for d in ("HANGAR", "STORAGE", "GARAGES", "PORT"):
        arr = by_d.get(d, [])
        if not arr:
            continue
        v = sum(x["value"] for x in arr)
        b = sum(x["min_bid"] for x in arr)
        n = sum(x["net"] for x in arr)
        c = sum(x["count"] for x in arr)
        tags = Counter(x["pacing"] for x in arr)
        print(
            f"  {d:<10} lots={len(arr):2d} items={c:4d}  value=${v:<7d}  "
            f"min_bid=${b:<6d}  expected_net=${n:,.0f}  "
            f"L{tags.get('LEAN', 0)}/J{tags.get('JACKPOT', 0)}/B{tags.get('BUST', 0)}"
        )
        grand_v += v
        grand_bid += b
        grand_net += n
        grand_n += c
    print("-" * 72)
    print(
        f"  CAMPAIGN   lots={len(stats):2d} items={grand_n:4d}  value=${grand_v:<7d}  "
        f"min_bid=${grand_bid:<6d}  projected profit=${grand_net:,.0f}"
    )
    print(
        f"  formula    win={WIN_RATE:.0%} × (vendor {VENDOR:.0%} × (value − "
        f"{BREAK_FRAGILE:.0%}×fragile) − min_bid)   5h wave, house $25k"
    )
    tags = Counter(x["pacing"] for x in stats)
    tot = max(len(stats), 1)
    print(
        f"  pacing     lean={tags.get('LEAN', 0)} ({100 * tags.get('LEAN', 0) / tot:.0f}%)  "
        f"jackpot={tags.get('JACKPOT', 0)} ({100 * tags.get('JACKPOT', 0) / tot:.0f}%)  "
        f"bust={tags.get('BUST', 0)} ({100 * tags.get('BUST', 0) / tot:.0f}%)   "
        f"target ≈60/25/15"
    )
    modes = Counter(x["info"] for x in stats)
    print("  info_mode  " + "  ".join(f"{k}={v}" for k, v in sorted(modes.items())))


def check_campaign_rules(lots: list[dict], stats: list[dict]) -> None:
    if not (68 <= len(lots) <= 72):
        err(f"need 68–72 presets (5h campaign), got {len(lots)}")
    by_d: dict[str, list[dict]] = defaultdict(list)
    for lot in lots:
        by_d[lot.get("district", "?")].append(lot)
    for d, arr in by_d.items():
        arr = sorted(arr, key=lambda x: int(x.get("order", 0)))
        prev_j = False
        modes = set()
        for lot in arr:
            is_j = lot.get("pacing") == "JACKPOT"
            if is_j and prev_j:
                err(f"{d}: two jackpots in a row ({lot['id']})")
            prev_j = is_j
            modes.add(lot.get("info"))
        missing = sorted(set(INFO_MODE) - modes)
        if missing:
            err(f"{d}: info_mode missing {missing} (need all five)")
    hang = [l for l in lots if l.get("district") == "HANGAR"]
    store = [l for l in lots if l.get("district") == "STORAGE"]
    garage = [l for l in lots if l.get("district") == "GARAGES"]
    port = [l for l in lots if l.get("district") == "PORT"]
    if len(hang) != 14:
        err(f"hangar should be hangar_01..14, got {len(hang)}")
    if len(store) != 22:
        err(f"storage should be storage_01..22, got {len(store)}")
    if len(garage) != 18:
        err(f"garages should be garages_01..18, got {len(garage)}")
    if len(port) != 14:
        err(f"port should be port_01..14, got {len(port)}")
    if sum(1 for l in hang if l.get("pacing") == "BUST") < 3:
        err("hangar needs at least 3 bust lots")
    if sum(1 for l in hang if l.get("pacing") == "JACKPOT") < 2:
        err("hangar needs at least 2 jackpots")
    if sum(1 for l in store if l.get("kind") == "LOCKER") < 2:
        err("storage needs at least 2 LOCKER lots")
    broom_s = sum(1 for l in store if l.get("broom"))
    if broom_s < 5:
        err(f"storage broom_required should be ~25% (≥5), got {broom_s}")
    if sum(1 for l in store if l.get("dark")) < 3:
        err("storage needs dark=true on at least 3 lots")
    broom_g = sum(1 for l in garage if l.get("broom"))
    if broom_g < 4:
        err(f"garages broom_required should be ~25% (≥4), got {broom_g}")
    broom_p = sum(1 for l in port if l.get("broom"))
    if broom_p < 3:
        err(f"port broom_required should be ~25% (≥3), got {broom_p}")
    if sum(1 for l in port if l.get("pacing") == "JACKPOT") < 3:
        err("port needs at least 3 jackpots")
    if sum(1 for l in port if l.get("pacing") == "BUST") < 2:
        err("port needs at least 2 busts")
    jokes = [l.get("joke") for l in lots if l.get("joke")]
    if len(jokes) < 20:
        warn(f"only {len(jokes)} lots marked with a joke arrangement (need ≥20)")


def main() -> int:
    archs = load_archetypes()
    catalog = load_item_catalog(archs)
    disk_ids = tres_ids_on_disk()
    lots = load_source()
    stats: list[dict] = []
    seen: set[str] = set()
    for lot in lots:
        lid = lot.get("id", "")
        if lid in seen:
            err(f"duplicate lot id {lid}")
        seen.add(lid)
        stats.append(validate_lot(lot, catalog, disk_ids))
    check_campaign_rules(lots, stats)

    if errors:
        print(f"{len(errors)} error(s), nothing written:")
        for e in errors:
            print("  ERROR " + e)
        for w in warnings:
            print("  warn  " + w)
        return 1

    removed = clean_dir(OUT_LOTS)
    for lot in lots:
        write_lot(lot)
    print(f"removed {removed} old .tres; wrote lots={len(lots)} → {OUT_LOTS}")
    for w in warnings:
        print("  warn  " + w)
    print_summary(stats)
    jokes = [(l["id"], l.get("joke", "")) for l in lots if l.get("joke")]
    if jokes:
        print()
        print("joke arrangements:")
        for lid, joke in jokes:
            print(f"  {lid}: {joke}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
