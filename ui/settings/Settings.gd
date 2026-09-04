class_name SettingsPanel
extends Control
## Экран опций: Игра / Управление / Видео / Звук. Встраивается в меню и паузу.

signal closed

@export var compact := false

var _tab := 0
var _capturing := ""
var _capture_ignore_ms := 0
var _warn: Label
var _body: VBoxContainer
var _tab_btns: Array[Button] = []
var _title: Label
var _dim: ColorRect
var _card: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	theme = UiTheme.make()
	visible = false
	_build()
	Settings.changed.connect(_on_settings)


func is_showing() -> bool:
	return visible


func is_capturing() -> bool:
	return _capturing != ""


func show_panel() -> void:
	visible = true
	_capturing = ""
	_rebuild()


func hide_panel() -> void:
	_capturing = ""
	var was := visible
	visible = false
	if was:
		closed.emit()


func _on_settings(key: String, _value: Variant) -> void:
	if not visible:
		return
	if key == "locale" or key == "ui_scale":
		_rebuild()
	elif key == "keybinds" and _tab == 1:
		_fill_body()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_tab_btns.clear()
	_dim = ColorRect.new()
	_dim.color = Color(0.08, 0.05, 0.1, 0.78)
	_dim.set_anchors_preset(PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and _capturing == "":
			pass)
	add_child(_dim)
	_card = PanelContainer.new()
	_card.set_anchors_preset(PRESET_CENTER)
	var w := 560.0 if compact else 760.0
	var h := 420.0 if compact else 560.0
	_card.custom_minimum_size = Vector2(w, h)
	_card.position = Vector2(-w * 0.5, -h * 0.5)
	add_child(_card)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10 if compact else 14)
	_card.add_child(outer)
	_title = UiTheme.header(tr("SET_TITLE"), 36 if compact else 52)
	outer.add_child(_title)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.ACCENT
	stripe.custom_minimum_size = Vector2(0, 8)
	outer.add_child(stripe)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(tabs)
	var tab_keys := ["SET_TAB_GAME", "SET_TAB_CONTROLS", "SET_TAB_VIDEO", "SET_TAB_AUDIO"]
	for i in tab_keys.size():
		var b := Button.new()
		b.text = tr(tab_keys[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 40 if compact else 46
		var idx := i
		b.pressed.connect(func(): _switch_tab(idx))
		UiTheme.wire_button(b, "pin")
		tabs.add_child(b)
		_tab_btns.append(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8 if compact else 12)
	scroll.add_child(_body)
	_warn = UiTheme.body("", 18, true)
	_warn.add_theme_color_override("font_color", UiTheme.DANGER)
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_warn)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(foot)
	var rst := UiTheme.fat_button(tr("SET_RESET"), 180)
	rst.pressed.connect(func():
		Settings.reset_defaults()
		_rebuild())
	foot.add_child(rst)
	var back := UiTheme.fat_button(tr("SET_BACK"), 160)
	back.pressed.connect(hide_panel)
	foot.add_child(back)
	_switch_tab(_tab)


func _rebuild() -> void:
	var keep := _tab
	_build()
	_switch_tab(keep)


func _switch_tab(i: int) -> void:
	_tab = i
	_capturing = ""
	_warn.text = ""
	for j in _tab_btns.size():
		var b := _tab_btns[j]
		var on := j == i
		b.modulate = Color.WHITE if on else UiTheme.TEXT_DIM
		b.add_theme_stylebox_override("normal", UiTheme.tab_btn(on))
		b.add_theme_stylebox_override("hover", UiTheme.tab_btn(on))
		b.add_theme_stylebox_override("pressed", UiTheme.tab_btn(on))
	_fill_body()


func _fill_body() -> void:
	for c in _body.get_children():
		c.queue_free()
	match _tab:
		0:
			_fill_game()
		1:
			_fill_controls()
		2:
			_fill_video()
		3:
			_fill_audio()
	UiTheme.polish(_body)


func _fill_game() -> void:
	_body.add_child(_option("locale", "SET_LOCALE",
		["SET_LOC_AUTO", "SET_LOC_RU", "SET_LOC_EN"],
		["auto", "ru", "en"]))
	_body.add_child(_slider("mouse_sensitivity", "SET_MOUSE", 0.0, 1.0, 0.01, true))
	_body.add_child(_check("invert_y", "SET_INVERT_Y"))
	_body.add_child(_slider("fov", "SET_FOV", 65.0, 100.0, 1.0, false, "%d"))
	_body.add_child(_slider("crosshair_size", "SET_CROSSHAIR", 0.4, 2.5, 0.05, true))
	_body.add_child(_slider("ui_scale", "SET_UI_SCALE", 0.75, 1.5, 0.05, true))
	_body.add_child(_check("screen_shake", "SET_SHAKE"))
	_body.add_child(_check("subtitles", "SET_SUBTITLES"))
	_body.add_child(_option("particles", "SET_PARTICLES",
		["SET_PART_LOW", "SET_PART_MED", "SET_PART_HIGH"],
		[0, 1, 2]))


func _fill_controls() -> void:
	var hint := UiTheme.body(tr("SET_BINDS_HINT"), 16, true)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hint)
	for a in Settings.ACTIONS:
		_body.add_child(_bind_row(a))
	var all := UiTheme.fat_button(tr("SET_RESET_BINDS"))
	all.pressed.connect(func():
		Settings.reset_keybinds()
		_warn.text = ""
		_fill_body())
	_body.add_child(all)


func _fill_video() -> void:
	_body.add_child(_check("fullscreen", "SET_FULLSCREEN"))
	_body.add_child(_check("vsync", "SET_VSYNC"))
	_body.add_child(_option("msaa", "SET_MSAA",
		["SET_MSAA_OFF", "SET_MSAA_2", "SET_MSAA_4"],
		[0, 2, 4]))
	_body.add_child(_option("shadow_quality", "SET_SHADOWS",
		["SET_SHAD_OFF", "SET_SHAD_LOW", "SET_SHAD_MED", "SET_SHAD_HIGH"],
		[0, 1, 2, 3]))
	_body.add_child(_option("max_fps", "SET_MAX_FPS",
		["SET_FPS_UNLIM", "SET_FPS_60", "SET_FPS_120", "SET_FPS_144", "SET_FPS_240"],
		[0, 60, 120, 144, 240]))
	_body.add_child(_slider("render_scale", "SET_RENDER_SCALE", 0.6, 1.0, 0.05, true))


func _fill_audio() -> void:
	_body.add_child(_slider("master_volume", "SET_VOL_MASTER", 0.0, 1.0, 0.01, true))
	_body.add_child(_slider("music_volume", "SET_VOL_MUSIC", 0.0, 1.0, 0.01, true))
	_body.add_child(_slider("sfx_volume", "SET_VOL_SFX", 0.0, 1.0, 0.01, true))
	_body.add_child(_slider("voice_volume", "SET_VOL_VOICE", 0.0, 1.0, 0.01, true))
	_body.add_child(_slider("mic_gain", "SET_MIC_GAIN", 0.0, 2.0, 0.05, true))
	_body.add_child(_check("voice_muted", "SET_VOICE_MUTED"))
	_body.add_child(_check("push_to_talk", "SET_PTT"))


func _slider(key: String, label_key: String, mn: float, mx: float, step: float, pct: bool, fmt: String = "%d") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	var l := UiTheme.body(tr(label_key), 18 if compact else 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var readout := UiTheme.body("", 18 if compact else 20)
	readout.custom_minimum_size.x = 72
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(readout)
	box.add_child(row)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(200, 28)
	var paint := func(v: float):
		if pct:
			readout.text = "%d%%" % int(round(v * 100.0))
		else:
			readout.text = fmt % int(round(v))
	paint.call(s.value)
	s.value_changed.connect(func(v: float):
		Settings.set_value(key, v)
		paint.call(v))
	s.drag_ended.connect(func(_c: bool):
		if AudioBus:
			AudioBus.play_ui("coin", -12.0))
	box.add_child(s)
	return box


func _check(key: String, label_key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = tr(label_key)
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(v: bool): Settings.set_value(key, v))
	c.custom_minimum_size.y = 36
	UiTheme.wire_button(c)
	return c


func _option(key: String, label_key: String, item_keys: Array, values: Array) -> Control:
	var row := HBoxContainer.new()
	var l := UiTheme.body(tr(label_key), 18 if compact else 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(220 if compact else 260, 40)
	for i in item_keys.size():
		ob.add_item(tr(item_keys[i]))
	var cur: Variant = Settings.get_value(key)
	var sel := 0
	for i in values.size():
		if _same_opt(values[i], cur):
			sel = i
			break
	ob.select(sel)
	ob.item_selected.connect(func(i: int):
		Settings.set_value(key, values[i]))
	UiTheme.wire_button(ob)
	row.add_child(ob)
	return row


func _bind_row(action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UiTheme.body(tr("SET_ACT_%s" % action.to_upper()), 17 if compact else 19)
	l.custom_minimum_size.x = 200 if compact else 260
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.text = Settings.hint(action)
	b.custom_minimum_size = Vector2(140 if compact else 180, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _capturing == action:
		b.text = tr("SET_PRESS_KEY")
		b.modulate = UiTheme.ACCENT
	var act := action
	b.pressed.connect(func(): _begin_capture(act))
	UiTheme.wire_button(b, "pin")
	row.add_child(b)
	var rst := Button.new()
	rst.text = tr("SET_RESET_ACTION")
	rst.custom_minimum_size = Vector2(100, 38)
	rst.pressed.connect(func():
		Settings.reset_action(act)
		_warn.text = ""
		_fill_body())
	UiTheme.wire_button(rst, "coin")
	row.add_child(rst)
	return row


func _same_opt(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_STRING or typeof(b) == TYPE_STRING:
		return str(a) == str(b)
	return float(a) == float(b)


func _begin_capture(action: String) -> void:
	_capturing = action
	_capture_ignore_ms = Time.get_ticks_msec() + 140
	_warn.text = tr("SET_PRESS_KEY")
	_warn.add_theme_color_override("font_color", UiTheme.ACCENT)
	_fill_body()


func _cancel_capture() -> void:
	_capturing = ""
	_warn.text = ""
	_fill_body()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capturing == "":
		return
	if Time.get_ticks_msec() < _capture_ignore_ms:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if (event as InputEventKey).keycode == KEY_ESCAPE or (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			return
		_try_bind(event)
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		_try_bind(event)


func _try_bind(event: InputEvent) -> void:
	var act := _capturing
	if Settings.rebind(act, event):
		_capturing = ""
		_warn.text = ""
		_warn.add_theme_color_override("font_color", UiTheme.DANGER)
		if AudioBus:
			AudioBus.play_ui("coin", -8.0)
		_fill_body()
	else:
		_warn.text = Settings.last_rebind_error
		_warn.add_theme_color_override("font_color", UiTheme.DANGER)
		if AudioBus:
			AudioBus.play_ui("buzzer", -10.0)


func _process(_delta: float) -> void:
	if visible and _title and is_instance_valid(_title):
		_title.rotation = -0.04 + sin(Time.get_ticks_msec() * 0.002) * 0.012
