extends Control
## Меню (§5 App: Menu → LoadSlot): слоты мира, хост/джойн, настройки, выход. Без туториала.

var slots_box: VBoxContainer
var join_edit: LineEdit
var status: Label
var _settings: SettingsPanel
var _loading: LoadingOverlay
var _chrome: Control
var _locale_dirty := false
var _join_keep := "127.0.0.1"


func _ready() -> void:
	Game.set_mouse_captured(false)
	Game.set_app_state(Game.AppState.MENU)
	if not AudioBus.has("menu_loop") and ResourceLoader.exists("res://audio/music/menu_loop.wav"):
		pass
	AudioBus.play_music("menu_loop", -10.0)
	theme = UiTheme.make()
	Settings.changed.connect(func(key, _v):
		if key == "locale":
			_locale_dirty = true)
	_build()
	Net.connection_failed.connect(func(): status.text = tr("NOTIFY_CONNECTION_FAILED"))
	SteamBoot.lobby_invite_accepted.connect(func(id): _join(str(id)))
	var auto_slot: bool = load("res://tools/Smoke.gd").wanted()
	if not auto_slot and ResourceLoader.exists("res://tools/Playtest.gd"):
		var pt = load("res://tools/Playtest.gd")
		if pt:
			auto_slot = pt.wanted()
	if auto_slot:
		Game.delete_slot(3)
		call_deferred("_host", 3)
	# --nettest [--join=ADDR]: headless сетевой тест (tools/NetTest.gd); --join=ADDR сам по себе — автоджойн
	var join_addr := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="):
			join_addr = a.substr(7)
	if OS.get_cmdline_user_args().has("--menu-shot") and DisplayServer.get_name() != "headless":
		_menu_shot()
	if join_addr != "":
		call_deferred("_join", join_addr)
	elif not auto_slot and (OS.get_cmdline_user_args().has("--nettest") or OS.get_cmdline_user_args().has("--trailer") or OS.get_cmdline_user_args().has("--autoshot") or OS.get_cmdline_user_args().has("--artshot")):
		Game.delete_slot(3)
		call_deferred("_host", 3)


func _build() -> void:
	var open_settings := _settings != null and _settings.is_showing()
	for c in get_children():
		c.queue_free()
	_settings = null
	_loading = null
	set_anchors_preset(PRESET_FULL_RECT)
	var has_art := ResourceLoader.exists("res://assets/textures/keyart_menu.png")
	var bg := ColorRect.new()
	bg.color = Color.TRANSPARENT if has_art else UiTheme.BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	if has_art:
		var art := TextureRect.new()
		art.texture = load("res://assets/textures/keyart_menu.png")
		art.set_anchors_preset(PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 0.98, 0.95, 1)
		add_child(art)
		var shade := ColorRect.new()
		shade.color = Color(0.08, 0.05, 0.1, 0.35)
		shade.set_anchors_preset(PRESET_LEFT_WIDE)
		shade.anchor_right = 0.42
		add_child(shade)
	var title := Label.new()
	title.text = "COOONTAINER"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	title.add_theme_color_override("font_outline_color", UiTheme.ACCENT)
	title.add_theme_constant_override("outline_size", 8)
	title.rotation = -0.052
	title.set_anchors_preset(PRESET_TOP_LEFT)
	title.position = Vector2(28, 18)
	add_child(title)
	var sub := UiTheme.body(tr("MENU_SUBTITLE"), 20, true)
	sub.set_anchors_preset(PRESET_TOP_LEFT)
	sub.position = Vector2(32, 108)
	sub.rotation = -0.03
	add_child(sub)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_LEFT_WIDE)
	panel.anchor_right = 0.36
	panel.offset_left = 20
	panel.offset_top = 150
	panel.offset_right = -8
	panel.offset_bottom = -72
	panel.add_theme_stylebox_override("panel", UiTheme.card_panel(UiTheme.BORDER_DARK))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_chrome = v
	slots_box = VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 8)
	v.add_child(slots_box)
	_refresh_slots()
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	v.add_child(join_row)
	join_edit = LineEdit.new()
	join_edit.placeholder_text = tr("MENU_JOIN_HINT")
	join_edit.custom_minimum_size = Vector2(0, 48)
	join_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_edit.text = _join_keep
	join_row.add_child(join_edit)
	var bj := UiTheme.fat_button(tr("MENU_JOIN"), 120)
	bj.pressed.connect(func(): _join(join_edit.text.strip_edges()))
	join_row.add_child(bj)
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	v.add_child(bottom)
	var bhow := UiTheme.fat_button(tr("MENU_HOWTO"), 0)
	bhow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bhow.pressed.connect(_toggle_howto)
	bottom.add_child(bhow)
	var bset := UiTheme.fat_button(tr("SET_OPEN"), 0)
	bset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bset.pressed.connect(_open_settings)
	bottom.add_child(bset)
	var quit := UiTheme.fat_button(tr("MENU_QUIT"), 0)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func(): get_tree().quit())
	bottom.add_child(quit)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", UiTheme.DANGER)
	status.add_theme_font_size_override("font_size", 18)
	v.add_child(status)
	var foot := Label.new()
	foot.text = tr("MENU_FOOTER") + ("  •  Steam: " + SteamBoot.persona if SteamBoot.enabled else "  •  LAN/offline")
	foot.set_anchors_preset(PRESET_BOTTOM_LEFT)
	foot.offset_left = 24
	foot.offset_bottom = -16
	foot.add_theme_font_size_override("font_size", 15)
	foot.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	add_child(foot)
	_settings = preload("res://ui/settings/Settings.tscn").instantiate()
	_settings.compact = false
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)
	_loading = preload("res://ui/common/Loading.tscn").instantiate()
	_loading.visible = false
	add_child(_loading)
	if open_settings:
		_settings.show_panel()


func _on_settings_closed() -> void:
	if join_edit:
		_join_keep = join_edit.text
	if _locale_dirty:
		_locale_dirty = false
		call_deferred("_build")


func _open_settings() -> void:
	_settings.show_panel()


var _howto: Control


## «Записка от Петровича» — не туториал, а мятый листок с правилами двора (§16: без обучалок в игре).
func _toggle_howto() -> void:
	if _howto and is_instance_valid(_howto):
		_howto.queue_free()
		_howto = null
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_toggle_howto())
	add_child(overlay)
	_howto = overlay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.rotation = 0.012
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.88, 0.72)
	sb.border_color = Color(0.55, 0.42, 0.2)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(4, 8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.resized.connect(func(): panel.pivot_offset = panel.size * 0.5)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var title := Label.new()
	title.text = tr("HOWTO_TITLE")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.35, 0.2, 0.08))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	outer.add_child(title)
	## Список пунктов длиннее экрана на низких разрешениях — крутим его, шапка и подпись стоят на месте.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	for i in range(1, 10):
		var l := Label.new()
		l.text = tr("HOWTO_%d" % i)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.15, 0.1, 0.06))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		v.add_child(l)
	var foot := Label.new()
	foot.text = tr("MENU_BACK") + " — Esc / " + tr("MENU_HOWTO").to_lower()
	foot.add_theme_font_size_override("font_size", 15)
	foot.add_theme_color_override("font_color", Color(0.45, 0.35, 0.25))
	foot.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	outer.add_child(foot)
	UiTheme.click("pin")
	overlay.modulate.a = 0.0 # пока меряем высоту, карточка сплющена — не показываем эти кадры
	var vp := get_viewport_rect().size
	scroll.custom_minimum_size.x = minf(760.0, vp.x - 80.0)
	# Высота списка известна только после того, как автоперенос ляжет на реальную ширину.
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	var chrome := outer.get_combined_minimum_size().y + sb.get_minimum_size().y
	var room: float = maxf(160.0, vp.y * 0.9 - chrome)
	scroll.custom_minimum_size.y = minf(v.get_combined_minimum_size().y, room)
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.12)


## Dev: `godot --path . -- --menu-shot` → user://shots/menu*.png (меню и записка), затем выход.
func _menu_shot() -> void:
	var dir := OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("menu_00.png"))
	_toggle_howto()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("menu_01_howto.png"))
	_toggle_howto()
	_open_settings()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("menu_02_settings.png"))
	print("[menu-shot] saved to %s" % dir)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _howto and is_instance_valid(_howto) and event.is_action_pressed("pause"):
		_toggle_howto()
		get_viewport().set_input_as_handled()


func _refresh_slots() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	for i in Game.SLOT_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		slots_box.add_child(row)
		var info := Game.slot_summary(i)
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(0, 0)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 20)
		if info.is_empty():
			lbl.text = "%s %d — %s" % [tr("MENU_SLOT"), i + 1, tr("MENU_EMPTY")]
			lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		else:
			var won := "  🏠 " + tr("MENU_WON") if info["won"] else ""
			lbl.text = "%s %d — $%d • %d %s • %s %s%s" % [tr("MENU_SLOT"), i + 1, info["pot"], info["lots_done"], tr("MENU_LOTS"), tr("MENU_PLAYTIME"), _fmt_time(info["playtime"]), won]
			lbl.add_theme_color_override("font_color", UiTheme.TEXT)
		row.add_child(lbl)
		var b := UiTheme.fat_button(tr("MENU_CONTINUE") if not info.is_empty() else tr("MENU_NEW_SLOT"), 160)
		var slot_i := i
		b.pressed.connect(func(): _host(slot_i))
		row.add_child(b)
		if not info.is_empty():
			var d := Button.new()
			d.text = "✕"
			d.tooltip_text = tr("MENU_DELETE")
			d.custom_minimum_size = Vector2(44, 44)
			d.pressed.connect(func():
				Game.delete_slot(slot_i)
				_refresh_slots())
			UiTheme.wire_button(d)
			row.add_child(d)


func _fmt_time(s: float) -> String:
	var t := int(s)
	return "%d:%02d" % [t / 3600, (t % 3600) / 60]


func _cover_load() -> void:
	if _loading == null:
		return
	_loading.visible = true
	_loading.roll_line()
	_loading.move_to_front()
	await get_tree().process_frame


func _host(i: int) -> void:
	status.text = ""
	await _cover_load()
	Game.start_world_from_slot(i, true)


func _join(address: String) -> void:
	if address == "":
		return
	status.text = "…"
	await _cover_load()
	Game.start_world_from_slot(0, false, address)
