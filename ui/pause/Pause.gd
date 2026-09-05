extends CanvasLayer
## Пауза (§18 Esc): продолжить, инвайт Steam / код лобби, настройки, в меню.
## В коопе пауза не останавливает мир (только хост-соло).

var panel: PanelContainer
var code_label: Label
var _open := false
var _settings: SettingsPanel
var _main_box: VBoxContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	Net.lobby_ready.connect(_on_lobby)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.make()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.05, 0.1, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-230, -240)
	panel.custom_minimum_size = Vector2(460, 0)
	root.add_child(panel)
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	panel.add_child(_main_box)
	_main_box.add_child(UiTheme.header(tr("PAUSE_TITLE"), 40))
	code_label = Label.new()
	code_label.text = ""
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 18)
	code_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_main_box.add_child(code_label)
	var b_res := UiTheme.fat_button(tr("PAUSE_RESUME"))
	b_res.pressed.connect(toggle)
	_main_box.add_child(b_res)
	var b_inv := UiTheme.fat_button(tr("PAUSE_INVITE"))
	b_inv.pressed.connect(func():
		if SteamBoot.enabled:
			SteamBoot.open_invite_overlay()
		else:
			DisplayServer.clipboard_set(code_label.text)
			Game.notify.emit(tr("PAUSE_COPIED"), 2.0))
	_main_box.add_child(b_inv)
	var b_set := UiTheme.fat_button(tr("SET_OPEN"))
	b_set.pressed.connect(_open_settings)
	_main_box.add_child(b_set)
	var b_menu := UiTheme.fat_button(tr("PAUSE_MENU"))
	b_menu.pressed.connect(func():
		_set_open(false)
		Game.back_to_menu())
	_main_box.add_child(b_menu)
	_settings = preload("res://ui/settings/Settings.tscn").instantiate()
	_settings.compact = true
	root.add_child(_settings)
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key == "locale" and _open and _settings and not _settings.is_showing():
		_refresh_labels()


func _refresh_labels() -> void:
	if _main_box.get_child_count() > 0 and _main_box.get_child(0) is Label:
		(_main_box.get_child(0) as Label).text = tr("PAUSE_TITLE")
	if _main_box.get_child_count() > 2:
		var i := 2
		for key in ["PAUSE_RESUME", "PAUSE_INVITE", "SET_OPEN", "PAUSE_MENU"]:
			if i < _main_box.get_child_count() and _main_box.get_child(i) is Button:
				(_main_box.get_child(i) as Button).text = tr(key)
			i += 1


func _open_settings() -> void:
	panel.visible = false
	_settings.show_panel()
	if not _settings.closed.is_connected(_on_settings_closed):
		_settings.closed.connect(_on_settings_closed)


func _on_settings_closed() -> void:
	if _open:
		panel.visible = true
		_refresh_labels()


func _on_lobby(code: String) -> void:
	code_label.text = tr("PAUSE_CODE") % code


func toggle() -> void:
	if _open and _settings and _settings.is_showing():
		_settings.hide_panel()
		return
	_set_open(not _open)


func _set_open(v: bool) -> void:
	_open = v
	visible = v
	get_tree().paused = v and Net.peer_count() <= 1
	Game.set_mouse_captured(not v)
	if _settings:
		if not v:
			_settings.hide_panel()
		panel.visible = v and not _settings.is_showing()


func is_open() -> bool:
	return _open
