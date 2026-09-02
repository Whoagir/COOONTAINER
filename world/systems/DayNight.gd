class_name DayNight
extends Node
## Время суток (§6.1: «свет в мире не гарантирован — гараж без лампы, ночь»).
## Круг ≈ 24 минуты реального времени (1 мин ≈ 1 час суток): фонарик и ночь имеют смысл.
## Ночью можно лечь на кровать трейлера (`Sleep`) и пропустить до утра.
## Арт-направление кей-арта — вечное «золотое» солнце: день проходит быстро в полдень и ночью,
## а на закате/рассвете время течёт медленнее (GOLD_SLOW). Ночь короткая (NIGHT_FRAC круга).
## Хост ведёт время и шлёт его редко; клиенты интерполируют.

const CYCLE_SECONDS := 1440.0 # 24 мин wall-clock при rate≈1 (золотой час чуть растягивает)
const SYNC_EVERY := 20.0
const NIGHT_FRAC := 0.22 # доля круга на ночь (солнце под горизонтом)
const GOLD_SLOW := 0.45 # скорость времени на золотом часу (1.0 = обычная)
const SUN_SHAPE := 2.2 # >1 — солнце дольше висит низко (длинные тени, тёплый свет)
const DEFAULT_TIME := 0.77 # новая игра: золотой вечер, как на кей-арте
const CLOUDS := 14

var time_of_day := DEFAULT_TIME # 0 = полночь, 0.5 = полдень
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _sky: ProceduralSkyMaterial
var _sync_t := 0.0
var _street_lights: Array[Light3D] = []
var _lights_on := false
var _clouds: Node3D
var _cloud_mat: StandardMaterial3D


func system_name() -> String:
	return "DayNight"


func _ready() -> void:
	await get_tree().process_frame
	var w := Game.world
	if w == null:
		return
	_sun = w.get_node_or_null("Sun")
	_env = w.get_node_or_null("Env")
	if _env and _env.environment and _env.environment.sky:
		var m = _env.environment.sky.sky_material
		if m is ProceduralSkyMaterial:
			_sky = m
	_collect_street_lights(w)
	if Net.is_host():
		time_of_day = float(Game.save.get("time_of_day", DEFAULT_TIME))
		for a in OS.get_cmdline_user_args(): # dev: --time=0.85 — стартовать ночью/на закате
			if a.begins_with("--time="):
				time_of_day = clampf(float(a.substr(7)), 0.0, 1.0)
	_build_clouds(w)
	_apply()


func _collect_street_lights(n: Node) -> void:
	for c in n.get_children():
		if c is Light3D and (c.name.begins_with("Street") or c.name.begins_with("Lamp") or c.name.begins_with("Neon")):
			_street_lights.append(c)
		if c.get_child_count() > 0:
			_collect_street_lights(c)


## Скорость хода времени: на золотом часу медленнее (комедия живёт на закате).
func _rate() -> float:
	var h := sun_height()
	var gold := clampf(1.0 - absf(h - 0.12) / 0.3, 0.0, 1.0) if h > -0.05 else 0.0
	return lerpf(1.0, GOLD_SLOW, gold)


func _process(delta: float) -> void:
	var step := delta / CYCLE_SECONDS * _rate()
	if Net.is_host():
		time_of_day = fposmod(time_of_day + step, 1.0)
		Game.save["time_of_day"] = time_of_day
		_sync_t += delta
		if _sync_t >= SYNC_EVERY and Net.peer_count() > 1:
			_sync_t = 0.0
			Net.broadcast_event("time_of_day", {"t": time_of_day})
	else:
		time_of_day = fposmod(time_of_day + step, 1.0)
	_drift_clouds(delta)
	_apply()


func on_net_event(kind: String, data: Dictionary) -> void:
	if kind == "time_of_day" and not Net.is_host():
		time_of_day = float(data["t"])


func send_full_state_to(peer: int) -> void:
	Net.send_event(peer, "time_of_day", {"t": time_of_day})


## Фаза дня 0..1 (0 = восход, 0.5 = полдень, 1 = закат) или -1 ночью.
func _day_u() -> float:
	var half := NIGHT_FRAC * 0.5
	if time_of_day < half or time_of_day > 1.0 - half:
		return -1.0
	return (time_of_day - half) / (1.0 - NIGHT_FRAC)


## Высота солнца: -1 (глухая ночь) … 1 (полдень). Форма кривой держит солнце низко дольше.
func sun_height() -> float:
	var u := _day_u()
	if u < 0.0:
		# ночь: 0 → -1 → 0 по короткой дуге
		var half := NIGHT_FRAC * 0.5
		var n := (time_of_day + half) if time_of_day < half else (time_of_day - (1.0 - half))
		return -sin(n / NIGHT_FRAC * PI)
	return pow(sin(u * PI), SUN_SHAPE)


## Азимут солнца: восход +X, закат -X (тени длинные вдоль главной улицы).
func _sun_yaw() -> float:
	var u := _day_u()
	if u < 0.0:
		return PI * 0.5
	return lerpf(-PI * 0.5, PI * 0.5, u) + 0.6


func is_night() -> bool:
	return sun_height() < -0.05


## 0..1 — насколько сейчас «золотой час» (низкое солнце над горизонтом).
func golden() -> float:
	var h := sun_height()
	if h < 0.0:
		return clampf(1.0 + h * 6.0, 0.0, 1.0) * 0.6
	return clampf(1.0 - h / 0.45, 0.0, 1.0)


func _apply() -> void:
	var h := sun_height()
	var gold := golden()
	var day := clampf(h * 2.0 + 0.25, 0.0, 1.0)
	if _sun:
		# ночью тот же источник работает луной: светит сверху, а не из-под земли
		var elev := h if h >= 0.0 else -h * 0.7
		_sun.rotation = Vector3(-asin(clampf(elev, 0.06, 0.999)), _sun_yaw(), 0.0)
		_sun.light_energy = lerpf(0.5, 1.45, day) + gold * 0.35 # ночь — лунная, а не чёрный экран
		# закат/рассвет — оранжевый, полдень — тёплый белый, ночь — синяя луна
		var c := Color(1, 0.95, 0.85).lerp(Color(1.0, 0.7, 0.4), gold)
		if h < 0.0:
			c = c.lerp(Color(0.55, 0.65, 1.0), clampf(-h * 2.0, 0.0, 1.0))
		_sun.light_color = c
		_sun.shadow_enabled = true
	if _sky:
		var top_day := Color(0.22, 0.42, 0.85).lerp(Color(0.42, 0.16, 0.48), gold) # золото: пурпур сверху
		var hor_day := Color(0.86, 0.72, 0.52).lerp(Color(1.0, 0.5, 0.22), gold) # … оранж у горизонта
		_sky.sky_top_color = Color(0.05, 0.07, 0.18).lerp(top_day, day)
		_sky.sky_horizon_color = Color(0.18, 0.14, 0.3).lerp(hor_day, day)
		_sky.sky_curve = lerpf(0.15, 0.09, gold)
		_sky.ground_bottom_color = Color(0.02, 0.02, 0.03).lerp(Color(0.2, 0.14, 0.12), day)
		_sky.ground_horizon_color = Color(0.05, 0.05, 0.07).lerp(Color(0.6, 0.45, 0.4).lerp(Color(0.95, 0.5, 0.3), gold), day)
		_sky.sun_angle_max = lerpf(30.0, 45.0, gold)
		_sky.sun_curve = 0.15
	if _env and _env.environment:
		var e := _env.environment
		# тени на закате — маджента/фиолет, как на арте; днём нейтральные
		var amb_day := Color(0.72, 0.72, 0.8).lerp(Color(0.78, 0.5, 0.7), gold)
		e.ambient_light_energy = lerpf(0.8, 0.85, day) + gold * 0.75 # тени на арте лиловые, не чёрные; ночь — синяя, а не чёрная
		e.ambient_light_color = Color(0.42, 0.5, 0.78).lerp(amb_day, day)
		e.ambient_light_sky_contribution = lerpf(0.45, 0.2, gold) # на закате небо тёмное сверху — берём цвет, не небо
		var fog_day := Color(0.72, 0.72, 0.78).lerp(Color(0.84, 0.58, 0.66), gold) # даль уходит в лиловое, как горы на арте
		e.fog_light_color = Color(0.14, 0.16, 0.28).lerp(fog_day, day)
		e.fog_density = lerpf(0.0035, 0.002, day)
		e.adjustment_saturation = lerpf(1.18, 1.12, gold) # тёплый свет сам насыщает — не пережигаем в красное
	if _cloud_mat:
		var cloud_day := Color(1.0, 0.98, 0.95).lerp(Color(1.0, 0.66, 0.5), gold)
		_cloud_mat.albedo_color = Color(0.22, 0.24, 0.35).lerp(cloud_day, day)
		_cloud_mat.emission = Color(0.0, 0.0, 0.0).lerp(Color(1.0, 0.45, 0.35), gold * day)
		_cloud_mat.emission_energy_multiplier = 0.35
	var want_on := is_night()
	if want_on != _lights_on:
		_lights_on = want_on
		for l in _street_lights:
			if is_instance_valid(l):
				l.visible = want_on
		CityDress.set_windows_lit(want_on)


# ------------------------------------------------------------------ облака

## Плоские гранёные облака как на кей-арте: 3–5 сплюснутых сфер, дрейфуют по ветру.
func _build_clouds(w: Node) -> void:
	if _clouds:
		return
	_clouds = Node3D.new()
	_clouds.name = "Clouds"
	w.add_child(_clouds)
	_cloud_mat = StandardMaterial3D.new()
	_cloud_mat.albedo_color = Color(1, 0.9, 0.85)
	_cloud_mat.roughness = 1.0
	_cloud_mat.emission_enabled = true
	_cloud_mat.emission = Color(0, 0, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in CLOUDS:
		var cl := Node3D.new()
		cl.name = "Cloud%d" % i
		var a := rng.randf() * TAU
		var r := rng.randf_range(120.0, 340.0)
		cl.position = Vector3(cos(a) * r, rng.randf_range(55.0, 95.0), sin(a) * r - 20.0)
		var puffs := rng.randi_range(3, 5)
		var w0 := rng.randf_range(18.0, 40.0)
		for k in puffs:
			var mi := MeshInstance3D.new()
			var pr := rng.randf_range(6.0, 11.0) * (1.0 if k == 0 else 0.75)
			mi.mesh = LowPoly.sphere(pr, 7, 3)
			mi.material_override = _cloud_mat
			mi.position = Vector3(rng.randf_range(-w0, w0) * 0.5, rng.randf_range(-1.5, 2.5), rng.randf_range(-4.0, 4.0))
			mi.scale = Vector3(rng.randf_range(1.4, 2.4), 0.55, 1.2)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cl.add_child(mi)
		_clouds.add_child(cl)


func _drift_clouds(delta: float) -> void:
	if _clouds == null:
		return
	for c in _clouds.get_children():
		var n := c as Node3D
		n.position.x += delta * 0.9
		if n.position.x > 380.0:
			n.position.x = -380.0
