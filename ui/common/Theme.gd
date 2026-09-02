class_name UiTheme
extends RefCounted
## Общая тема меню / паузы / настроек. Шрифт движка, крупные кегли, тёплая палитра.

const BG := Color("1a121f")
const PANEL := Color("2a1d33")
const PANEL_HI := Color("3a2846")
const ACCENT := Color("ff8a2b")
const ACCENT_DIM := Color("c96518")
const ACCENT_HI := Color("ffaa55")
const MAGENTA := Color("e23c8f")
const TEXT := Color("fff1d6")
const TEXT_DIM := Color("c9b6a8")
const DANGER := Color("e04b3a")
const SUCCESS := Color("ffd23f")
const STRIPE := Color("ff8a2b")
const BORDER_DARK := Color("15101a")
const OUTLINE := Color("15101a")


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 3)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.98, 0.92))
	t.set_color("font_pressed_color", "Button", Color(1, 0.9, 0.75))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color(1, 0.98, 0.92))
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", Color(1, 0.98, 0.92))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_color", "TabBar", TEXT)
	t.set_color("font_selected_color", "TabBar", ACCENT)
	t.set_color("font_hover_color", "TabBar", Color(1, 0.98, 0.92))
	t.set_stylebox("normal", "Button", _btn(ACCENT, BORDER_DARK, 4))
	t.set_stylebox("hover", "Button", _btn(ACCENT_HI, BORDER_DARK, 4))
	t.set_stylebox("pressed", "Button", _btn(ACCENT_DIM, BORDER_DARK, 4))
	t.set_stylebox("focus", "Button", _btn(ACCENT, TEXT, 5))
	t.set_stylebox("disabled", "Button", _btn(Color("4a3a52"), Color("2a2030"), 3))
	t.set_stylebox("normal", "OptionButton", _btn(PANEL_HI, BORDER_DARK, 3))
	t.set_stylebox("hover", "OptionButton", _btn(Color("4a3558"), ACCENT, 4))
	t.set_stylebox("pressed", "OptionButton", _btn(PANEL, ACCENT, 4))
	t.set_stylebox("focus", "OptionButton", _btn(PANEL_HI, TEXT, 5))
	t.set_stylebox("panel", "PanelContainer", _panel())
	t.set_stylebox("panel", "Panel", _panel())
	t.set_stylebox("normal", "LineEdit", _btn(PANEL, BORDER_DARK, 3))
	t.set_stylebox("focus", "LineEdit", _btn(PANEL, ACCENT, 4))
	t.set_stylebox("grabber_area", "HSlider", _slider_fill(ACCENT))
	t.set_stylebox("grabber_area_highlight", "HSlider", _slider_fill(ACCENT_HI))
	t.set_stylebox("grabber_area_disabled", "HSlider", _slider_fill(Color("5a4a62")))
	t.set_stylebox("slider", "HSlider", _slider_track())
	t.set_icon("grabber", "HSlider", _slider_grabber(false))
	t.set_icon("grabber_highlight", "HSlider", _slider_grabber(true))
	t.set_icon("grabber_disabled", "HSlider", _slider_grabber(false, true))
	t.set_stylebox("panel", "TooltipPanel", _panel())
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("h_separation", "BoxContainer", 12)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t


static func apply_to(ctrl: Control) -> void:
	ctrl.theme = make()
	polish(ctrl)


static func polish(root: Node) -> void:
	if root is BaseButton:
		wire_button(root)
	for c in root.get_children():
		polish(c)


static func wire_button(b: BaseButton, click_sfx: String = "coin", hover_sfx: String = "pin") -> void:
	if b.has_meta("ui_wired"):
		return
	b.set_meta("ui_wired", true)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.pivot_offset = b.size * 0.5
	b.mouse_entered.connect(func():
		if AudioBus:
			AudioBus.play_ui(hover_sfx, -14.0)
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.03, 1.03), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	b.mouse_exited.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.08)
	)
	b.pressed.connect(func():
		if AudioBus:
			AudioBus.play_ui(click_sfx, -8.0)
	)


static func click(name: String = "coin") -> void:
	if AudioBus:
		AudioBus.play_ui(name, -8.0)


static func header(text: String, size: int = 48) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.rotation = -0.052
	l.pivot_offset = Vector2(40, 20)
	return l


static func body(text: String, size: int = 22, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT_DIM if dim else TEXT)
	return l


static func fat_button(text: String, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(min_w, 52)
	wire_button(b)
	return b


static func hud_label(text: String, size: int, color: Color = TEXT, outline := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", OUTLINE)
		l.add_theme_constant_override("outline_size", 6)
	return l


static func pill_panel(bg: Color = PANEL, radius: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = BORDER_DARK
	sb.set_border_width_all(4)
	sb.border_width_top = 2
	sb.border_color = PANEL_HI
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func card_panel(border: Color = ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, 0.94)
	sb.border_color = border
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func tab_btn(active: bool) -> StyleBoxFlat:
	if active:
		return _btn(ACCENT, BORDER_DARK, 4)
	return _btn(PANEL_HI, BORDER_DARK, 3)


static func _btn(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func _panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = BORDER_DARK
	sb.set_border_width_all(4)
	sb.border_width_top = 2
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


## Чекбокс: тёмный квадрат с рамкой; отмечен — оранжевая заливка с галкой.
static func _check_icon(checked: bool, disabled := false) -> ImageTexture:
	var s := 28
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var border := (Color("4a3a52") if disabled else BORDER_DARK)
	var fill := (Color("1e1628") if not checked else (Color("6a4a20") if disabled else ACCENT))
	for y in s:
		for x in s:
			var edge := x < 3 or y < 3 or x >= s - 3 or y >= s - 3
			img.set_pixel(x, y, border if edge else fill)
	if checked:
		for i in range(0, 7):
			_dot(img, 7 + i, 14 + i, OUTLINE)
		for i in range(0, 10):
			_dot(img, 13 + i, 19 - i, OUTLINE)
	return ImageTexture.create_from_image(img)


static func _dot(img: Image, x: int, y: int, c: Color) -> void:
	for dx in range(0, 2):
		for dy in range(0, 2):
			var px := x + dx
			var py := y + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, c)


static func _slider_track() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1a121f")
	sb.border_color = BORDER_DARK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.set_content_margin_all(8)
	return sb


static func _slider_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	return sb


static func _slider_grabber(highlight: bool, disabled := false) -> ImageTexture:
	var s := 30
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var fill := (Color("5a4a62") if disabled else (ACCENT_HI if highlight else ACCENT))
	var border := (Color("3a3040") if disabled else BORDER_DARK)
	var cx := s / 2.0
	var cy := s / 2.0
	var r := 11.0
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(Vector2(cx, cy))
			if d <= r + 2.0:
				img.set_pixel(x, y, border if d > r - 1.0 else fill)
	return ImageTexture.create_from_image(img)
