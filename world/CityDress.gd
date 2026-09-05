class_name CityDress
extends Node
## Дожимка картинки: город собран из примитивов с плоскими цветами — на старте навешиваем
## сгенерированные текстуры и чиним UV, чтобы не было «пластилина».
## Классификация по ГЕОМЕТРИИ (пол/стена/крыша/дорога) + район + исходный цвет,
## потому что имена узлов в сценах районов генерические («M»).
## Ничего не двигает и не ломает коллизии — только материалы. Дешёво для слабого ПК.

const TEX := "res://assets/textures/"

## Пол трейлера над землёй. Под эту высоту собраны trailer_rig.glb (колёса, юбка, дышло)
## и trailer_steps.glb (площадка вровень с полом); TrailerPark.tscn/Trailer поднят на неё же.
const TRAILER_LIFT := 0.85
const BILLBOARD_TEX := ["ad_pricebot", "ad_casino", "ad_carmarket", "tex_poster_auction", "tex_flyer_hamster"]

## районы с крышей — пол внутри бетонный, стены интерьерные
const INDOOR := [Types.District.HANGAR, Types.District.STORAGE, Types.District.GARAGES, Types.District.CASINO,
	Types.District.POLICE, Types.District.VENDORS, Types.District.LOCKSMITH]

## стены по районам: {tex, uv, lighten}
const WALLS := {
	Types.District.TRAILER_PARK: {"tex": "tex_trailer_siding", "uv": 4.2, "lighten": 0.6},
	Types.District.HANGAR: {"tex": "tex_wall_exterior", "uv": 5.0, "lighten": 0.8},
	Types.District.STORAGE: {"tex": "tex_wall_interior", "uv": 3.2, "lighten": 0.85},
	Types.District.GARAGES: {"tex": "tex_concrete", "uv": 3.5, "lighten": 0.75},
	Types.District.PORT: {"tex": "tex_corrugated", "uv": 3.0, "lighten": 0.5},
	Types.District.CAR_MARKET: {"tex": "tex_wall_exterior", "uv": 4.0, "lighten": 0.7},
	Types.District.VENDORS: {"tex": "tex_wall_interior", "uv": 3.0, "lighten": 0.8},
	Types.District.LOCKSMITH: {"tex": "tex_wall_exterior", "uv": 3.5, "lighten": 0.75},
	Types.District.CASINO: {"tex": "tex_wall_interior", "uv": 3.0, "lighten": 0.4},
	Types.District.POLICE: {"tex": "tex_wall_exterior", "uv": 4.0, "lighten": 0.85},
}

## Крытые районы внутри тёмные: дешёвые бестеневые заливки у потолка, чтобы было видно барахло.
## Тёмные ячейки (LotAnchor.dark) НЕ подсвечиваем — там фонарик (§6.1).
const INTERIOR_FILL := {
	Types.District.HANGAR: {"h": 7.0, "r": 30.0, "n": 4, "c": Color(1.0, 0.93, 0.8), "e": 1.5},
	Types.District.STORAGE: {"h": 3.2, "r": 22.0, "n": 4, "c": Color(0.95, 0.95, 1.0), "e": 1.1},
	Types.District.GARAGES: {"h": 3.4, "r": 20.0, "n": 3, "c": Color(1.0, 0.9, 0.75), "e": 1.2},
	Types.District.CASINO: {"h": 3.6, "r": 16.0, "n": 3, "c": Color(1.0, 0.5, 0.45), "e": 1.6},
	Types.District.POLICE: {"h": 3.4, "r": 16.0, "n": 3, "c": Color(0.85, 0.9, 1.0), "e": 1.2},
	Types.District.VENDORS: {"h": 3.2, "r": 18.0, "n": 3, "c": Color(1.0, 0.92, 0.8), "e": 1.0},
	Types.District.PORT: {"h": 5.0, "r": 24.0, "n": 2, "c": Color(0.9, 0.95, 1.0), "e": 0.8},
	Types.District.LOCKSMITH: {"h": 2.8, "r": 8.0, "n": 1, "c": Color(1.0, 0.95, 0.85), "e": 0.9},
}

static var _cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
var dressed := 0
var lights := 0
var labels_fixed := 0


func system_name() -> String:
	return "CityDress"


func _ready() -> void:
	await get_tree().process_frame
	var w := Game.world
	if w == null or w.city == null:
		return
	_walk(w.city, -1, 0)
	var t0 := Time.get_ticks_msec()
	var terrain: GDScript = load("res://world/Terrain.gd") # через load: кэш классов редактора может отставать
	dressed += int(terrain.dress(w)) # гранёная земля с выбоинами + галька/кирпичи (после _walk: материалы уже стоят)
	if OS.is_debug_build():
		print("[CityDress] terrain %d ms" % (Time.get_ticks_msec() - t0))
	_dress_billboards(w.city)
	_fill_interiors(w)
	_light_campfire(w)
	_rig_trailer(w)
	if ResourceLoader.exists("res://world/districts/Interiors.gd"):
		var scr: GDScript = load("res://world/districts/Interiors.gd")
		if scr and scr.has_method("dress"):
			dressed += int(scr.dress(w)) # обстановка внутри районов (шкафы, автоматы, барахло)
	if OS.is_debug_build():
		print("[CityDress] materials upgraded: %d, fill lights: %d, labels fixed: %d" % [dressed, lights, labels_fixed])


func _fill_interiors(w) -> void:
	if w.city == null or not w.city.has_method("districts"):
		return
	for d in w.city.districts():
		var cfg = INTERIOR_FILL.get(d.district_id)
		if cfg == null:
			continue
		var n: int = int(cfg["n"])
		var r: float = float(cfg["r"])
		for i in n:
			var a := TAU * i / float(n) + 0.4
			var pos: Vector3 = d.global_position + Vector3(cos(a) * r * 0.45, float(cfg["h"]), sin(a) * r * 0.45)
			var l := OmniLight3D.new()
			l.name = "FillLight%d" % i
			l.light_color = cfg["c"]
			l.light_energy = float(cfg["e"])
			l.omni_range = r
			l.omni_attenuation = 0.9
			l.shadow_enabled = false
			l.light_specular = 0.2
			w.add_child(l)
			l.global_position = pos
			lights += 1
	# трейлер игрока — тёплая лампочка под потолком, чтобы не просыпаться в чёрной коробке
	var trailer: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Trailer")
	if trailer:
		var l := OmniLight3D.new()
		l.name = "TrailerLamp"
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 1.4
		l.omni_range = 7.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		w.add_child(l)
		l.global_position = trailer.global_position + Vector3(0, 2.3, 0)
		lights += 1


static var _win_mat: StandardMaterial3D


static func _is_window(c: Color, s: Vector3) -> bool:
	var thin := minf(s.x, minf(s.y, s.z)) <= 0.12
	var big := maxf(s.x, maxf(s.y, s.z)) >= 0.5 and maxf(s.x, maxf(s.y, s.z)) <= 4.0
	return thin and big and s.y >= 0.4 and c.b > 0.75 and c.r < 0.75 and c.b - c.r > 0.15


## Один материал на все окна города: DayNight красит его в тёплое свечение ночью.
static func _window_mat() -> StandardMaterial3D:
	if _win_mat == null:
		_win_mat = StandardMaterial3D.new()
		_win_mat.albedo_color = Color(0.62, 0.8, 0.95)
		_win_mat.roughness = 0.2
		_win_mat.metallic = 0.3
		_win_mat.emission_enabled = true
		_win_mat.emission = Color(1.0, 0.72, 0.4)
		_win_mat.emission_energy_multiplier = 0.0
	return _win_mat


## Ночью окна светятся тёплым (зовёт DayNight при смене день/ночь).
static func set_windows_lit(lit: bool) -> void:
	var m := _window_mat()
	m.emission_energy_multiplier = 1.6 if lit else 0.0
	m.albedo_color = Color(0.9, 0.7, 0.45) if lit else Color(0.62, 0.8, 0.95)


## Костёр в трейлер-парке: к статичным «языкам» из сцены добавляем частицы, дым и мерцание
## (тот же FireFx, что у горящих вещей) — это главный тёплый акцент хабного кадра.
## Трейлер-парк не зря так зовётся: дом на колёсах, а не коробка на земле.
## Корпус поднят в сцене; здесь навешиваем шасси с колёсами, дышло, крышу и крыльцо со ступенями.
## Делается здесь, а не в Props: там на момент постройки районы City ещё не зарегистрированы.
func _rig_trailer(w) -> void:
	if w.city == null or not w.city.has_method("district_root"):
		return
	var d: Node3D = w.city.district_root(Types.District.TRAILER_PARK)
	if d == null:
		return
	var trailer: Node = d.get_node_or_null("Trailer")
	if trailer == null or trailer.has_node("Rig"):
		return
	# корпус поднят на TRAILER_LIFT (TrailerPark.tscn), поэтому шасси и крыльцо вешаем ниже —
	# колёса и ступени остаются на земле, ось больше не торчит сквозь пол в комнату
	_attach_model(trailer, "Rig", "trailer_rig", Vector3(0, -TRAILER_LIFT, 0), 0.0)
	_attach_model(trailer, "RoofKit", "trailer_roof", Vector3(0, 2.9, 0), 0.0)
	# дверь на +Z (x = 2.0..3.0); у модели крыльца стена в −Z, спуск в +Z — разворот не нужен
	_attach_model(trailer, "Steps", "trailer_steps", Vector3(2.5, -TRAILER_LIFT, 1.90), 0.0)
	_step_collision(trailer)


## Крыльцо — только меш, коллизии к нему: площадка-блок вровень с полом и наклонный пандус
## под ступенями. CharacterBody3D в Godot сам на ступеньку не шагает, зато уклон 34° проходит
## обычным шагом, так что игрок въезжает наверх плавно, а под площадку не залезет.
func _step_collision(trailer: Node) -> void:
	var body := trailer as StaticBody3D
	if body == null or body.has_node("StepDeckCol"):
		return
	const DECK_W := 1.16
	const DECK_Z0 := 1.90
	const DECK_Z1 := 2.55
	const RAMP_Z1 := 3.91 # линия по носкам ступеней, продлённая до земли (33.8°)
	const TOP_Y := 0.06
	var deck := CollisionShape3D.new()
	deck.name = "StepDeckCol"
	var ds := BoxShape3D.new()
	ds.size = Vector3(DECK_W, TOP_Y + TRAILER_LIFT, DECK_Z1 - DECK_Z0)
	deck.shape = ds
	deck.position = Vector3(2.5, (TOP_Y - TRAILER_LIFT) * 0.5, (DECK_Z0 + DECK_Z1) * 0.5)
	body.add_child(deck)
	var run := RAMP_Z1 - DECK_Z1
	var rise := TOP_Y + TRAILER_LIFT
	var ang := atan2(rise, run)
	var ramp := CollisionShape3D.new()
	ramp.name = "StepRampCol"
	var rs := BoxShape3D.new()
	rs.size = Vector3(DECK_W, 0.24, sqrt(run * run + rise * rise))
	ramp.shape = rs
	var mid := Vector3(2.5, (TOP_Y - TRAILER_LIFT) * 0.5, (DECK_Z1 + RAMP_Z1) * 0.5)
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, ang), mid - Vector3(0.0, cos(ang), sin(ang)) * 0.12)
	body.add_child(ramp)


func _attach_model(parent: Node3D, node_name: String, file: String, pos: Vector3, yaw_deg: float) -> void:
	var path := "res://assets/models/%s.glb" % file
	if not ResourceLoader.exists(path):
		push_warning("[CityDress] нет модели %s" % path)
		return
	var packed: PackedScene = load(path)
	var mdl := packed.instantiate() as Node3D if packed else null
	if mdl == null:
		return
	mdl.name = node_name
	mdl.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	mdl.set_meta("no_dress", true)
	parent.add_child(mdl)
	dressed += 1


func _light_campfire(w) -> void:
	var fire: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Campfire")
	if fire == null or fire.has_node("FireFx"):
		return
	var fx := FireFx.make(Vector3(0.7, 0.7, 0.7))
	fire.add_child(fx)
	fx.position = Vector3(0, 0.15, 0)
	var old := fire.get_node_or_null("FireLight")
	if old:
		old.queue_free() # FireFx приносит свою мерцающую лампу


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var p := TEX + name + ".png"
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_cache[name] = t
	return t


func _walk(n: Node, district: int, depth: int) -> void:
	if depth > 14:
		return
	# у моделей из Blender материалы уже свои — перекраска съедала цвет (диван выцветал, шины серели)
	if n.has_meta("no_dress"):
		return
	if n is District:
		district = (n as District).district_id
	if n is MeshInstance3D:
		_try_dress(n, district)
	elif n is Label3D:
		# текст виден зеркально с тыла — режем тыл (§12 знаки читаются спереди)
		var l := n as Label3D
		if l.billboard == BaseMaterial3D.BILLBOARD_DISABLED and l.double_sided:
			l.double_sided = false
			labels_fixed += 1
	for c in n.get_children():
		_walk(c, district, depth + 1)


func _base_color(mi: MeshInstance3D) -> Color:
	var src: Material = mi.get_active_material(0)
	if src is StandardMaterial3D:
		return (src as StandardMaterial3D).albedo_color
	return Color(1, 1, 1)


func _is_woody(c: Color) -> bool:
	# кремовые/бежевые стены (s < 0.3) — не дерево, иначе трейлер обшивается досками
	return c.r > c.g and c.g > c.b and (c.r - c.b) > 0.15 and c.v > 0.25 and c.s > 0.3


func _is_greenish(c: Color) -> bool:
	return c.g > c.r * 1.05 and c.g > c.b * 1.2


func _under_roads(mi: Node) -> bool:
	var p := mi.get_parent()
	while p:
		if p is Roads:
			return true
		p = p.get_parent()
	return false


func _try_dress(mi: MeshInstance3D, district: int) -> void:
	if mi.mesh == null or mi.material_override is ShaderMaterial:
		return
	if mi.mesh is CylinderMesh and mi.get_parent() and mi.get_parent().name == "Hills":
		_soften_hill(mi)
		return
	if mi.mesh is CylinderMesh:
		# плоские «блины» земли (двор трейлер-парка) — та же глина с колеями, триплана
		var cyl := mi.mesh as CylinderMesh
		var cm := mi.get_active_material(0) as StandardMaterial3D
		if cyl.height <= 0.6 and cyl.top_radius >= 6.0 and (cm == null or cm.albedo_texture == null):
			_apply(mi, "tex_dirt_tracks", 5.0, 1.0, Color(0.7, 0.55, 0.4), 0.0)
		return
	if not (mi.mesh is BoxMesh or mi.mesh is PlaneMesh or mi.mesh is PrismMesh):
		return
	var src: Material = mi.get_active_material(0)
	if src is StandardMaterial3D and (src as StandardMaterial3D).albedo_texture != null:
		return # уже текстурирован автором сцены
	var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
	var s := aabb.size
	var top := aabb.end.y
	var max_xz := maxf(s.x, s.z)
	var min_xz := minf(s.x, s.z)
	var indoor := INDOOR.has(district)
	var base := _base_color(mi)

	# --- окна: голубые тонкие панели в стенах → общий материал, ночью тёплое свечение (DayNight)
	if mi.mesh is BoxMesh and _is_window(base, s):
		mi.material_override = _window_mat()
		dressed += 1
		return

	# --- дороги: асфальт + тротуарные плиты
	if _under_roads(mi):
		if mi.mesh is BoxMesh and s.y <= 0.15 and max_xz > 3.0:
			_apply(mi, "tex_asphalt", 6.0, 0.95, base, 0.35)
		elif mi.mesh is BoxMesh and s.y <= 0.5 and min_xz < 2.5 and max_xz > 1.0: # бордюр сидит в грунте — плита выше 0.3
			_apply(mi, "tex_sidewalk", 2.0, 0.95, base, 0.75)
		return

	# --- крыши: призмы и высокие тонкие горизонтальные плиты
	if mi.mesh is PrismMesh:
		if max_xz > 4.0:
			_apply(mi, "tex_corrugated", 3.0, 0.7, base, 0.45)
		return
	# земля города — толстый бокс 600x1x410, тоже «плоский»
	var flat := (s.y <= 0.6 or (s.y <= 1.6 and min_xz > 20.0)) and min_xz > 1.5
	if flat and top > 2.4:
		_apply(mi, "tex_ceiling" if indoor else "tex_corrugated", 4.0, 0.75, base, 0.5)
		return

	# --- пол / земля
	if flat and top <= 0.6:
		if district == Types.District.CASINO and max_xz > 4.0:
			_apply(mi, "tex_casino_carpet", 3.0, 1.0, base, 0.9)
		elif max_xz > 200.0:
			# земля всего города — пустынная глина с колеёй, как на кей-арте
			_apply(mi, "tex_dirt_tracks", 9.0, 1.0, Color(0.74, 0.62, 0.48), 0.0) # текстура светлая — прибиваем в тёплую глину
		elif district == Types.District.TRAILER_PARK and max_xz > 4.0 and not _is_greenish(base):
			_apply(mi, "tex_dirt_tracks", 5.0, 1.0, Color(0.72, 0.56, 0.4), 0.0)
		elif _is_greenish(base) or (base.r > base.b * 1.25 and base.v < 0.75 and not indoor):
			_apply(mi, "tex_grass_dirt", 4.0, 1.0, base, 0.7)
		elif base.v < 0.3:
			_apply(mi, "tex_asphalt", 6.0, 0.95, base, 0.4)
		elif indoor and max_xz > 6.0:
			_apply(mi, "tex_floor_concrete", 4.0, 0.9, base, 0.8)
		elif max_xz > 14.0:
			_apply(mi, "tex_floor_concrete", 5.0, 0.95, base.darkened(0.15), 0.35) # причал/площадка — литой бетон
		elif _is_woody(base):
			_apply(mi, "tex_planks", 1.6, 0.85, base, 0.55)
		else:
			_apply(mi, "tex_sidewalk", 2.0, 0.95, base, 0.75)
		return

	# --- стены: тонкие и высокие
	var wall := s.y >= 1.6 and min_xz <= 0.9 and max_xz >= 1.8
	if wall:
		if _is_woody(base):
			_apply(mi, "tex_planks", 1.6, 0.85, base, 0.5)
			return
		var rule: Dictionary = WALLS.get(district, {"tex": "tex_wall_exterior", "uv": 4.0, "lighten": 0.75})
		# ярко окрашенные стены (казино, вывески) — держим цвет сильнее
		var lighten: float = float(rule["lighten"]) * (0.55 if base.s > 0.45 else 1.0)
		_apply(mi, rule["tex"], float(rule["uv"]), 0.9, base, lighten)
		return

	# --- объёмные коробки: трейлеры, контейнеры, будки
	var chunky := min_xz > 0.9 and s.y > 0.9
	if chunky and max_xz >= 2.5:
		if _is_woody(base):
			_apply(mi, "tex_planks", 1.6, 0.85, base, 0.5)
		elif district == Types.District.TRAILER_PARK and s.y < 4.0:
			_apply(mi, "tex_trailer_siding", 4.2, 0.85, base, 0.55)
		elif district == Types.District.PORT or base.s > 0.4:
			_apply(mi, "tex_container", 2.5, 0.75, base, 0.3)
		else:
			_apply(mi, "tex_wall_exterior", 4.0, 0.9, base, 0.7)
		return

	# --- мелочь: деревянное — доски, остальное не трогаем (цветные пропсы читаются и так)
	if _is_woody(base) and max_xz > 0.5:
		_apply(mi, "tex_planks", 1.2, 0.85, base, 0.45)


## Фоновые холмы в сцене — конусы (CylinderMesh) → похожи на пирамиды. Меняем на полусферы.
func _soften_hill(mi: MeshInstance3D) -> void:
	var cyl := mi.mesh as CylinderMesh
	var r := maxf(cyl.top_radius, cyl.bottom_radius)
	var h := cyl.height
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.is_hemisphere = true
	sm.radial_segments = 24
	sm.rings = 10
	mi.mesh = sm
	var ground_y := mi.position.y - h * 0.5
	# отодвигаем от центра города и приплющиваем: пологие холмы на горизонте, не «пузыри»
	var center := Vector3(0, 0, -15)
	var off := mi.position - center
	off.y = 0.0
	mi.position = center + off * 1.6
	mi.position.y = ground_y - 3.0
	mi.scale = Vector3(r * 1.7, h * 0.2, r * 1.7)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.42, 0.36) # пыльные пустынные холмы, не зелёные пузыри и не соляная пустыня
	var t := tex("tex_dirt_tracks")
	if t:
		m.albedo_texture = t
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 30.0
	m.roughness = 1.0
	mi.material_override = m
	dressed += 1


func _apply(mi: MeshInstance3D, tex_name: String, uv: float, rough: float, base: Color, lighten: float) -> void:
	var t := tex(tex_name)
	if t == null:
		return
	var tint := base.lerp(Color(1, 1, 1), lighten)
	var key := "%s|%.2f|%.2f|%s" % [tex_name, uv, rough, tint.to_html(false)]
	var m: StandardMaterial3D = _mat_cache.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = tint
		m.albedo_texture = t
		m.roughness = rough
		m.metallic = 0.0
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(1.0 / uv, 1.0 / uv, 1.0 / uv)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mat_cache[key] = m
	mi.material_override = m
	dressed += 1


## Пустые щиты/плакаты → рекламные картинки (пародийные, §12 «знаки в мире»).
func _dress_billboards(root: Node) -> void:
	var boards: Array[MeshInstance3D] = []
	_collect_boards(root, boards)
	var i := 0
	for b in boards:
		var t := tex(BILLBOARD_TEX[i % BILLBOARD_TEX.size()])
		i += 1
		if t == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = t
		m.albedo_color = Color(1, 1, 1)
		m.roughness = 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.material_override = m
		dressed += 1


func _collect_boards(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			# по имени самого меша: раньше сюда попадал весь узел Billboard* — опоры и рама
			# уезжали в рекламную текстуру вместе с полотном
			var name := c.name.to_lower()
			if name.contains("adface") or name.contains("billboardface") or name.contains("advert") or name.contains("poster"):
				out.append(c)
		_collect_boards(c, out)
