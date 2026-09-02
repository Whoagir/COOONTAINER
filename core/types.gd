class_name Types
## Канонические enum'ы игры (§7, §8, §5 ТЗ). Всё остальное ссылается сюда.

enum SizeClass { POCKET, ONE_HAND, TWO_HAND, TEAM, VEHICLE }

enum Facet {
	FRAGILE, DIRTYABLE, CONTAINER, SHAKE_OUT, LOCKED, WEARABLE, LIQUID, ALIVE,
	DOCUMENT, PATCHABLE, WEAPON, ILLEGAL, HEAVY_CHEAP, HEAVY_EXPENSIVE,
}

enum LiquidId { NONE, WHISKEY, PAINT, GLUE, OIL, GASOLINE, WATER }

enum Integrity { WHOLE, CHIPPED, SHARDS }

enum LotKind { BAG, LOCKER, STORAGE, GARAGE, PORT }

enum InfoMode { DOOR15, SLIT, PHOTOS, DOCS, TALE }

enum PacingTag { LEAN, JACKPOT, BUST }

enum VendorType { ANTIQUE, HOUSEHOLD, TECH, DARK }

enum Phobia { NONE, MOUSE, TAPE, PAINT, WET, FIRE, HAMSTER }

## §5 — режимы InWorld.
enum WorldMode { TRAILER_HUB, TRAVEL, AUCTION, CLEAR_OUT, VENDOR, CASINO, POLICE_CUSTODY, JANITOR_JOB, DEAD, CREDITS }

enum District {
	TRAILER_PARK, HANGAR, STORAGE, GARAGES, PORT, CAR_MARKET, VENDORS, LOCKSMITH, CASINO, POLICE,
}

enum PoliceTrigger { ILLEGAL_SALE, THREAT, BRAWL, CAR_THEFT, OVERTIME, BLACKLIST_ENTRY, ARSON }

## Физические слои (project.godot → layer_names).
const L_WORLD := 1 << 0
const L_PLAYER := 1 << 1
const L_ITEM := 1 << 2
const L_SHARD := 1 << 3
const L_VEHICLE := 1 << 4
const L_NPC := 1 << 5
const L_LIQUID := 1 << 6
const L_TRIGGER := 1 << 7
const L_RAGDOLL := 1 << 8

const FACET_NAMES := {
	Facet.FRAGILE: "FRAGILE", Facet.DIRTYABLE: "DIRTYABLE", Facet.CONTAINER: "CONTAINER",
	Facet.SHAKE_OUT: "SHAKE_OUT", Facet.LOCKED: "LOCKED", Facet.WEARABLE: "WEARABLE",
	Facet.LIQUID: "LIQUID", Facet.ALIVE: "ALIVE", Facet.DOCUMENT: "DOCUMENT",
	Facet.PATCHABLE: "PATCHABLE", Facet.WEAPON: "WEAPON", Facet.ILLEGAL: "ILLEGAL",
	Facet.HEAVY_CHEAP: "HEAVY_CHEAP", Facet.HEAVY_EXPENSIVE: "HEAVY_EXPENSIVE",
}

static func facet_from_string(s: String) -> int:
	for k in FACET_NAMES:
		if FACET_NAMES[k] == s:
			return k
	return -1

static func liquid_from_string(s: String) -> int:
	match s.to_lower():
		"whiskey", "whisky", "cognac", "alcohol": return LiquidId.WHISKEY
		"paint": return LiquidId.PAINT
		"glue": return LiquidId.GLUE
		"oil": return LiquidId.OIL
		"gasoline", "gas", "petrol": return LiquidId.GASOLINE
		"water": return LiquidId.WATER
	return LiquidId.NONE

static func size_from_string(s: String) -> int:
	match s.to_upper():
		"POCKET": return SizeClass.POCKET
		"ONE_HAND": return SizeClass.ONE_HAND
		"TWO_HAND": return SizeClass.TWO_HAND
		"TEAM": return SizeClass.TEAM
		"VEHICLE": return SizeClass.VEHICLE
	return SizeClass.ONE_HAND

static func liquid_color(id: int) -> Color:
	match id:
		LiquidId.WHISKEY: return Color(0.72, 0.42, 0.12, 0.85)
		LiquidId.PAINT: return Color(0.9, 0.15, 0.55, 1.0)
		LiquidId.GLUE: return Color(0.95, 0.95, 0.85, 0.9)
		LiquidId.OIL: return Color(0.08, 0.07, 0.05, 0.95)
		LiquidId.GASOLINE: return Color(0.75, 0.7, 0.3, 0.6)
		LiquidId.WATER: return Color(0.4, 0.6, 0.9, 0.5)
	return Color(1, 1, 1, 0.5)

static func liquid_flammable(id: int) -> bool:
	return id == LiquidId.GASOLINE or id == LiquidId.OIL or id == LiquidId.WHISKEY

static func liquid_slip(id: int) -> float:
	match id:
		LiquidId.OIL: return 1.0
		LiquidId.GLUE: return -1.0 # клей: наоборот, липнет
		LiquidId.WATER: return 0.5
		LiquidId.WHISKEY: return 0.4
		LiquidId.PAINT: return 0.3
		LiquidId.GASOLINE: return 0.5
	return 0.0
