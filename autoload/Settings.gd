extends Node
## Настройки игрока. user://settings.cfg. Автолоад первый: локаль/дисплей сразу,
## звук и мир — лениво после остальных автолоадов (Registry перезаписывает локаль).

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SAVE_DELAY := 0.5
const SECTION := "settings"
const BINDS_SECTION := "keybinds"

const ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "crouch", "grab", "release", "second_hand", "swap_hand", "use",
	"throw", "flashlight", "paddle", "pin", "voice", "pause", "alt_use",
	"arm_out", "arm_in",
]
const PROTECTED: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right", "grab", "use",
]

const DEFAULTS := {
	"master_volume": 1.0,
	"music_volume": 0.7,
	"sfx_volume": 1.0,
	"voice_volume": 1.0,
	"mouse_sensitivity": 0.5,
	"invert_y": false,
	"fov": 75.0,
	"locale": "auto",
	"fullscreen": false,
	"vsync": true,
	"msaa": 0,
	"shadow_quality": 2,
	"max_fps": 0,
	"render_scale": 1.0,
	"particles": 2,
	"screen_shake": true,
	"subtitles": true,
	"push_to_talk": true,
	"mic_gain": 1.0,
	"voice_muted": false,
	"crosshair_size": 1.0,
	"ui_scale": 1.0,
}

var last_rebind_error := ""
var _values: Dictionary = {}
var _project_binds: Dictionary = {}
var _save_left := -1.0
var _wired_game := false
var _music_normalized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_values = DEFAULTS.duplicate()
	_values["keybinds"] = {}
	_snapshot_project_binds()
	_load()
	_apply_locale()
	_apply_display()
	call_deferred("_late_boot")


func _late_boot() -> void:
	apply_all()
	if Game and not _wired_game:
		Game.app_state_changed.connect(_on_app)
		_wired_game = true


func _on_app(state: int) -> void:
	if state == Game.AppState.IN_WORLD:
		call_deferred("_apply_world")


func _process(delta: float) -> void:
	if _save_left >= 0.0:
		_save_left -= delta
		if _save_left <= 0.0:
			_save_left = -1.0
			_write()
	_apply_player_live()


func _input(event: InputEvent) -> void:
	if not bool(_values.get("invert_y", false)):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var dy := (event as InputEventMouseMotion).relative.y
		if dy != 0.0:
			call_deferred("_invert_fix", dy)


# ------------------------------------------------------------------ public API

func get_value(key: String) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return null


func set_value(key: String, v: Variant) -> void:
	if key == "keybinds":
		_values["keybinds"] = v if v is Dictionary else {}
		_apply_keybinds()
		changed.emit("keybinds", _values["keybinds"])
		_schedule_save()
		return
	if not DEFAULTS.has(key):
		return
	var coerced: Variant = _clamp_key(key, v)
	if _values.get(key) == coerced:
		_apply_one(key)
		return
	_values[key] = coerced
	_apply_one(key)
	changed.emit(key, coerced)
	_schedule_save()


func apply_all() -> void:
	_apply_locale()
	_apply_display()
	_apply_audio()
	_apply_keybinds()
	_apply_world()
	_apply_player_live()


func reset_defaults() -> void:
	for k in DEFAULTS:
		_values[k] = DEFAULTS[k]
	apply_all()
	for k in DEFAULTS:
		changed.emit(k, _values[k])
	_write()


func reset_keybinds() -> void:
	for a in ACTIONS:
		_restore_action(a)
	_sync_keybinds_from_map()
	changed.emit("keybinds", _values["keybinds"])
	_write()


func reset_action(action: String) -> void:
	_restore_action(action)
	_sync_keybinds_from_map()
	changed.emit("keybinds", _values["keybinds"])
	_schedule_save()


func rebind(action: String, event: InputEvent) -> bool:
	last_rebind_error = ""
	if not InputMap.has_action(action) or not (action in ACTIONS):
		last_rebind_error = _t("SET_UNKNOWN_ACTION", "Неизвестное действие", "Unknown action")
		return false
	if event == null:
		if action in PROTECTED:
			last_rebind_error = _t("SET_NEED_BIND", "Это действие нельзя оставить пустым", "This action needs a binding")
			return false
		InputMap.action_erase_events(action)
		_sync_keybinds_from_map()
		changed.emit("keybinds", _values["keybinds"])
		_schedule_save()
		return true
	var clean := _clean_event(event)
	if clean == null:
		last_rebind_error = _t("SET_BAD_EVENT", "Так не назначить", "Can't bind that")
		return false
	var other := conflict_action(clean, action)
	if other != "":
		last_rebind_error = _t("SET_CONFLICT", "%s уже занята: %s", "%s already used by %s") % [
			event_hint(clean), _action_title(other)
		]
		return false
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	_sync_keybinds_from_map()
	changed.emit("keybinds", _values["keybinds"])
	_schedule_save()
	return true


func conflict_action(event: InputEvent, except_action: String = "") -> String:
	if event == null:
		return ""
	for a in ACTIONS:
		if a == except_action:
			continue
		if not InputMap.has_action(a):
			continue
		for ev in InputMap.action_get_events(a):
			if ev.is_match(event, true):
				return a
	return ""


func hint(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var evs := InputMap.action_get_events(action)
	if evs.is_empty():
		return "—"
	var parts: PackedStringArray = []
	for e in evs:
		parts.append(event_hint(e))
	return " / ".join(parts)


func event_hint(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return _t("SET_KEY_LMB", "ЛКМ", "LMB")
			MOUSE_BUTTON_RIGHT:
				return _t("SET_KEY_RMB", "ПКМ", "RMB")
			MOUSE_BUTTON_MIDDLE:
				return _t("SET_KEY_MMB", "СКМ", "MMB")
			MOUSE_BUTTON_WHEEL_UP:
				return _t("SET_KEY_WHEEL_UP", "Колесо ↑", "Wheel ↑")
			MOUSE_BUTTON_WHEEL_DOWN:
				return _t("SET_KEY_WHEEL_DOWN", "Колесо ↓", "Wheel ↓")
			MOUSE_BUTTON_WHEEL_LEFT:
				return _t("SET_KEY_WHEEL_LEFT", "Колесо ←", "Wheel ←")
			MOUSE_BUTTON_WHEEL_RIGHT:
				return _t("SET_KEY_WHEEL_RIGHT", "Колесо →", "Wheel →")
			_:
				return _t("SET_KEY_MB", "Кнопка %d", "Button %d") % (e as InputEventMouseButton).button_index
	if e is InputEventKey:
		var k := e as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		match code:
			KEY_ESCAPE:
				return "Esc"
			KEY_SPACE:
				return _t("SET_KEY_SPACE", "Пробел", "Space")
			KEY_SHIFT:
				return _t("SET_KEY_SHIFT", "Шифт", "Shift")
			KEY_CTRL:
				return "Ctrl"
			KEY_ALT:
				return "Alt"
			KEY_TAB:
				return "Tab"
			KEY_ENTER, KEY_KP_ENTER:
				return "Enter"
			KEY_BACKSPACE:
				return _t("SET_KEY_BACKSPACE", "←BS", "Backspace")
			KEY_UP:
				return "↑"
			KEY_DOWN:
				return "↓"
			KEY_LEFT:
				return "←"
			KEY_RIGHT:
				return "→"
		var s := OS.get_keycode_string(code as Key)
		if s != "":
			return s
		return "?"
	if e:
		return e.as_text()
	return "—"


func mapped_mouse_sens() -> float:
	return Player.MOUSE_SENS_DEFAULT * lerpf(0.3, 2.5, float(_values["mouse_sensitivity"]))


func resolved_locale() -> String:
	var loc := str(_values.get("locale", "auto"))
	if loc == "auto":
		var sys := OS.get_locale_language()
		return "ru" if sys.begins_with("ru") else "en"
	if loc == "ru" or loc == "en":
		return loc
	return "en"


func is_ru() -> bool:
	return TranslationServer.get_locale().begins_with("ru")


# ------------------------------------------------------------------ load / save

func _load() -> void:
	if not FileAccess.file_exists(PATH):
		_values["locale"] = "auto"
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cfg.has_section_key(SECTION, k):
			_values[k] = _clamp_key(k, cfg.get_value(SECTION, k, DEFAULTS[k]))
	var binds: Dictionary = {}
	if cfg.has_section(BINDS_SECTION):
		for a in cfg.get_section_keys(BINDS_SECTION):
			var raw: Variant = cfg.get_value(BINDS_SECTION, a, [])
			if raw is Array:
				binds[a] = raw
	_values["keybinds"] = binds


func _write() -> void:
	var cfg := ConfigFile.new()
	for k in DEFAULTS:
		cfg.set_value(SECTION, k, _values[k])
	var binds: Dictionary = _values.get("keybinds", {})
	for a in binds:
		cfg.set_value(BINDS_SECTION, a, binds[a])
	cfg.save(PATH)


func _schedule_save() -> void:
	_save_left = SAVE_DELAY


# ------------------------------------------------------------------ apply

func _apply_one(key: String) -> void:
	match key:
		"master_volume", "music_volume", "sfx_volume", "voice_volume", "voice_muted", "mic_gain":
			_apply_audio()
		"locale":
			_apply_locale()
		"fullscreen", "vsync", "msaa", "shadow_quality", "max_fps", "render_scale", "ui_scale":
			_apply_display()
			if key == "shadow_quality":
				_apply_shadows()
		"mouse_sensitivity", "fov", "invert_y", "crosshair_size":
			_apply_player_live()
		_:
			pass


func _apply_locale() -> void:
	TranslationServer.set_locale(resolved_locale())


func _apply_display() -> void:
	if not _is_headless():
		if bool(_values["fullscreen"]):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if bool(_values["vsync"]) else DisplayServer.VSYNC_DISABLED
		)
	Engine.max_fps = int(_values["max_fps"])
	var vp := get_viewport()
	if vp:
		match int(_values["msaa"]):
			2:
				vp.msaa_3d = Viewport.MSAA_2X
			4:
				vp.msaa_3d = Viewport.MSAA_4X
			_:
				vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.scaling_3d_scale = clampf(float(_values["render_scale"]), 0.6, 1.0)
	if get_tree() and get_tree().root:
		get_tree().root.content_scale_factor = clampf(float(_values["ui_scale"]), 0.75, 1.5)
	_apply_shadows()


func _apply_shadows() -> void:
	var q := clampi(int(_values["shadow_quality"]), 0, 3)
	var sizes := [0, 1024, 2048, 4096]
	var sz: int = sizes[q]
	var vp := get_viewport()
	if vp:
		vp.positional_shadow_atlas_size = sz
	if sz > 0:
		RenderingServer.directional_shadow_atlas_set_size(sz, true)
	else:
		RenderingServer.directional_shadow_atlas_set_size(256, true)
	if q == 0:
		_force_sun_off()
	elif Game and Game.world:
		var sun = Game.world.get_node_or_null("Sun")
		if sun is DirectionalLight3D:
			(sun as DirectionalLight3D).shadow_enabled = true


func _apply_audio() -> void:
	var master := float(_values["master_volume"])
	var music := float(_values["music_volume"])
	var sfx := float(_values["sfx_volume"])
	var voice := float(_values["voice_volume"])
	var ab := get_node_or_null("/root/AudioBus")
	if ab:
		ab.set_master(master)
		# шины несут громкость; поля 1.0 — чтобы play_* не умножали второй раз
		ab.music_volume = 1.0
		ab.sfx_volume = 1.0
		if not _music_normalized:
			for c in ab.get_children():
				if c is AudioStreamPlayer and (c as AudioStreamPlayer).bus == "Music" and (c as AudioStreamPlayer).playing:
					(c as AudioStreamPlayer).volume_db = -10.0
			_music_normalized = true
	_set_bus_linear("Music", music)
	_set_bus_linear("SFX", sfx)
	var vi := AudioServer.get_bus_index("Voice")
	if vi != -1:
		AudioServer.set_bus_volume_db(vi, linear_to_db(maxf(voice, 0.001)))
		AudioServer.set_bus_mute(vi, bool(_values["voice_muted"]))


func _apply_keybinds() -> void:
	var binds: Dictionary = _values.get("keybinds", {})
	if binds.is_empty():
		return
	for a in ACTIONS:
		if not binds.has(a) or not InputMap.has_action(a):
			continue
		var arr: Array = binds[a]
		InputMap.action_erase_events(a)
		for d in arr:
			if d is Dictionary:
				var ev := _deserialize_event(d)
				if ev:
					InputMap.action_add_event(a, ev)
		if a in PROTECTED and InputMap.action_get_events(a).is_empty():
			_restore_action(a)


func _apply_world() -> void:
	_apply_shadows()
	_apply_player_live()


func _apply_player_live() -> void:
	if Game == null or Game.world == null:
		return
	if Game.app_state != Game.AppState.IN_WORLD:
		return
	var p = Game.world.local_player()
	if p == null:
		return
	p.mouse_sens = mapped_mouse_sens()
	var fov := clampf(float(_values["fov"]), 65.0, 100.0)
	if p.drunk > 0.05:
		fov += p.drunk * 10.0
	if p.camera:
		p.camera.fov = fov
	if int(_values["shadow_quality"]) == 0:
		_force_sun_off()


func _invert_fix(dy: float) -> void:
	if Game == null or Game.world == null:
		return
	var p = Game.world.local_player()
	if p == null:
		return
	p._pitch = clampf(p._pitch + dy * p.mouse_sens * 2.0, -1.45, 1.45)


func _force_sun_off() -> void:
	if Game == null or Game.world == null:
		return
	var sun = Game.world.get_node_or_null("Sun")
	if sun is DirectionalLight3D:
		(sun as DirectionalLight3D).shadow_enabled = false


func _set_bus_linear(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


# ------------------------------------------------------------------ keybinds helpers

func _snapshot_project_binds() -> void:
	_project_binds.clear()
	for a in ACTIONS:
		var arr: Array = []
		if InputMap.has_action(a):
			for ev in InputMap.action_get_events(a):
				arr.append(ev.duplicate())
		_project_binds[a] = arr


func _restore_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var arr: Array = _project_binds.get(action, [])
	for ev in arr:
		if ev is InputEvent:
			InputMap.action_add_event(action, (ev as InputEvent).duplicate())


func _sync_keybinds_from_map() -> void:
	var binds: Dictionary = {}
	for a in ACTIONS:
		var arr: Array = []
		if InputMap.has_action(a):
			for ev in InputMap.action_get_events(a):
				var d := _serialize_event(ev)
				if not d.is_empty():
					arr.append(d)
		binds[a] = arr
	_values["keybinds"] = binds


func _serialize_event(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		return {"t": "key", "physical": int(k.physical_keycode), "keycode": int(k.keycode)}
	if e is InputEventMouseButton:
		return {"t": "mouse", "button": int((e as InputEventMouseButton).button_index)}
	return {}


func _deserialize_event(d: Dictionary) -> InputEvent:
	var t := str(d.get("t", ""))
	if t == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(d.get("physical", 0)) as Key
		k.keycode = int(d.get("keycode", 0)) as Key
		k.device = -1
		return k
	if t == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(d.get("button", 1)) as MouseButton
		m.device = -1
		return m
	return null


func _clean_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var src := event as InputEventKey
		if src.echo:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = src.physical_keycode
		k.keycode = src.keycode
		k.device = -1
		return k
	if event is InputEventMouseButton:
		var srcm := event as InputEventMouseButton
		var m := InputEventMouseButton.new()
		m.button_index = srcm.button_index
		m.device = -1
		return m
	return null


func _action_title(action: String) -> String:
	return _t("SET_ACT_%s" % action.to_upper(), action, action)


func _clamp_key(key: String, v: Variant) -> Variant:
	match key:
		"invert_y", "fullscreen", "vsync", "screen_shake", "subtitles", "push_to_talk", "voice_muted":
			return bool(v)
		"msaa":
			var m := int(v)
			if m == 2 or m == 4:
				return m
			return 0
		"shadow_quality":
			return clampi(int(v), 0, 3)
		"max_fps":
			var f := int(v)
			if f == 60 or f == 120 or f == 144 or f == 240:
				return f
			return 0
		"particles":
			return clampi(int(v), 0, 2)
		"locale":
			var loc := str(v)
			if loc == "ru" or loc == "en" or loc == "auto":
				return loc
			return "auto"
		"fov":
			return clampf(float(v), 65.0, 100.0)
		"render_scale":
			return clampf(float(v), 0.6, 1.0)
		"ui_scale":
			return clampf(float(v), 0.75, 1.5)
		"crosshair_size":
			return clampf(float(v), 0.4, 2.5)
		"mic_gain":
			return clampf(float(v), 0.0, 2.0)
		"master_volume", "music_volume", "sfx_volume", "voice_volume", "mouse_sensitivity":
			return clampf(float(v), 0.0, 1.0)
		_:
			return v


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _t(key: String, ru: String, en: String) -> String:
	var got := tr(key)
	if got != key:
		return got
	return ru if is_ru() else en
