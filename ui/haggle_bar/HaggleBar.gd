class_name HaggleBar
extends CanvasLayer
## Полоска торга (§11): оффер → зелёная зона → попал/промах. Плюс окно ставки казино (§13).
## Только локальный UI; всё считает хост. Оффер/ставка — во встроенном Window (перехватывает
## мышь и клавиатуру, чтобы клик по кнопке не превращался в хват вещи на прилавке).

signal offer_sent(stand: String, nid: int, amount: int)
signal phone_requested(nid: int)
signal bar_finished(nid: int, hit: bool, precision: float)
signal bet_sent(amount: int, red: bool)
signal closed()

enum Mode { NONE, OFFER, BAR, BET }

const BAR_W := 640.0
const BAR_H := 44.0
const BAR_TIMEOUT := 15.0
const RESULT_SEC := 1.4

var mode: int = Mode.NONE

var _root: Control
# --- оффер
var _offer_win: Window
var _offer_title: Label
var _items: OptionButton
var _slider: HSlider
var _spin: SpinBox
var _amount_label: Label
var _hint_label: Label
var _estimate_label: Label
var _offer_items: Array = []
var _stand := ""
var _fair := 1
var _syncing := false
# --- полоска
var _bar_panel: PanelContainer
var _bar_title: Label
var _bar_sub: Label
var _bar_area: Control
var _green: ColorRect
var _marker: ColorRect
var _result: Label
var _nid := 0
var _green_pos := 0.5
var _green_w := 0.3
var _base_speed := 1.0
var _speed := 1.0
var _pos := 0.0
var _dir := 1.0
var _elapsed := 0.0
var _stopped := false
var _result_t := 0.0
var _tick_t := 0.0
var _hit_amt := 0
var _miss_amt := 0
# --- ставка
var _bet_win: Window
var _bet_slider: HSlider
var _bet_spin: SpinBox
var _bet_max := 0
var _bet_syncing := false


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_offer()
	_build_bar()
	_build_bet()
	set_process(false)


func is_open() -> bool:
	return mode != Mode.NONE


# ------------------------------------------------------------------ helpers

func _mk_label(size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(3, size / 7))
	return l


func _panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.85, 0.4, 0.8)
	sb.set_content_margin_all(14)
	return sb


func _mk_window(title: String, size: Vector2i) -> Window:
	var w := Window.new()
	w.title = title
	w.borderless = true
	w.unresizable = true
	w.transient = true
	w.exclusive = false
	w.popup_window = false
	w.size = size
	w.visible = false
	w.close_requested.connect(close)
	w.window_input.connect(_on_window_input)
	add_child(w)
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.08, 0.1, 0.97)))
	w.add_child(bg)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	bg.add_child(v)
	return w


func _win_box(w: Window) -> VBoxContainer:
	return w.get_child(0).get_node("V") as VBoxContainer


func _on_window_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _set_mode(m: int) -> void:
	if mode == m:
		return
	var prev := mode
	mode = m
	_offer_win.visible = m == Mode.OFFER
	_bet_win.visible = m == Mode.BET
	_bar_panel.visible = m == Mode.BAR
	set_process(m == Mode.BAR)
	if m == Mode.OFFER or m == Mode.BET:
		Game.set_mouse_captured(false)
		var w := _offer_win if m == Mode.OFFER else _bet_win
		w.popup_centered()
		w.grab_focus()
	elif prev == Mode.OFFER or prev == Mode.BET:
		if not _pause_open():
			Game.set_mouse_captured(true)
	if m == Mode.NONE:
		closed.emit()


func _pause_open() -> bool:
	var w: World = Game.world as World
	if w and w.pause_menu and w.pause_menu.has_method("is_open"):
		return w.pause_menu.is_open()
	return false


func close() -> void:
	if mode == Mode.BAR and not _stopped:
		_stop()
		return
	_set_mode(Mode.NONE)


# ------------------------------------------------------------------ оффер (§11)

func _build_offer() -> void:
	_offer_win = _mk_window("", Vector2i(560, 360))
	var v := _win_box(_offer_win)
	_offer_title = _mk_label(28, Color(1, 0.85, 0.4))
	_offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_offer_title)
	_items = OptionButton.new()
	_items.item_selected.connect(_on_item_selected)
	v.add_child(_items)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(360, 0)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.step = 1.0
	_slider.value_changed.connect(_on_slider)
	row.add_child(_slider)
	_spin = SpinBox.new()
	_spin.step = 1.0
	_spin.prefix = "$"
	_spin.custom_minimum_size = Vector2(120, 0)
	_spin.value_changed.connect(_on_spin)
	row.add_child(_spin)
	_amount_label = _mk_label(40, Color(1, 0.95, 0.6))
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_amount_label)
	_hint_label = _mk_label(18, Color(0.8, 0.8, 0.8))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint_label)
	_estimate_label = _mk_label(18, Color(0.6, 0.9, 1.0))
	_estimate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estimate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_estimate_label)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	v.add_child(btns)
	var b_offer := Button.new()
	b_offer.text = tr("HAGGLE_BTN_OFFER")
	b_offer.custom_minimum_size = Vector2(150, 40)
	b_offer.pressed.connect(_send_offer)
	btns.add_child(b_offer)
	var b_phone := Button.new()
	b_phone.text = tr("HAGGLE_BTN_PHONE")
	b_phone.custom_minimum_size = Vector2(150, 40)
	b_phone.pressed.connect(func(): phone_requested.emit(_selected_nid()))
	btns.add_child(b_phone)
	var b_cancel := Button.new()
	b_cancel.text = tr("HAGGLE_BTN_CANCEL")
	b_cancel.custom_minimum_size = Vector2(120, 40)
	b_cancel.pressed.connect(close)
	btns.add_child(b_cancel)


## data: {"stand", "vendor", "items": [{nid, name, fair}]} — от хоста (vendor_open).
func open_offer(data: Dictionary) -> void:
	var items: Array = data.get("items", [])
	if items.is_empty():
		return
	_offer_items = items
	_stand = str(data.get("stand", ""))
	_offer_title.text = tr("HAGGLE_TITLE") % str(data.get("vendor", ""))
	_items.clear()
	for it in items:
		_items.add_item("%s  —  %s $%d" % [str(it.get("name", "?")), tr("HAGGLE_FAIR"), int(it.get("fair", 1))])
	_items.select(0)
	_estimate_label.text = ""
	_on_item_selected(0)
	_set_mode(Mode.OFFER)


func _selected_nid() -> int:
	var i := _items.selected
	if i < 0 or i >= _offer_items.size():
		return 0
	return int(_offer_items[i].get("nid", 0))


func _on_item_selected(i: int) -> void:
	if i < 0 or i >= _offer_items.size():
		return
	_fair = maxi(1, int(_offer_items[i].get("fair", 1)))
	_syncing = true
	_slider.min_value = maxf(1.0, floor(_fair * 0.5))
	_slider.max_value = maxf(_slider.min_value + 1.0, ceil(_fair * 3.0))
	_spin.min_value = _slider.min_value
	_spin.max_value = _slider.max_value
	_slider.value = _fair
	_spin.value = _fair
	_syncing = false
	_estimate_label.text = ""
	_refresh_amount()


func _on_slider(v: float) -> void:
	if _syncing:
		return
	_syncing = true
	_spin.value = v
	_syncing = false
	_refresh_amount()


func _on_spin(v: float) -> void:
	if _syncing:
		return
	_syncing = true
	_slider.value = v
	_syncing = false
	_refresh_amount()


func _refresh_amount() -> void:
	var amount := int(_slider.value)
	var ratio := float(amount) / float(_fair)
	_amount_label.text = "$%d   (×%.2f)" % [amount, ratio]
	if ratio <= 1.05:
		_hint_label.text = tr("HAGGLE_HINT_FAIR")
		_hint_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	elif ratio <= 1.35:
		_hint_label.text = tr("HAGGLE_HINT_MID")
		_hint_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	else:
		_hint_label.text = tr("HAGGLE_HINT_GREEDY")
		_hint_label.add_theme_color_override("font_color", Color(1, 0.55, 0.45))


func _send_offer() -> void:
	var nid := _selected_nid()
	if nid == 0:
		close()
		return
	var amount := int(_slider.value)
	_set_mode(Mode.NONE)
	offer_sent.emit(_stand, nid, amount)


## Оценка «ЦеноБота» по кнопке «Позвонить» (текст готовит Vendors/Phone).
func show_estimate(text: String) -> void:
	_estimate_label.text = text


## Вещь продана/исчезла — если окно открыто на ней, закрыть.
func on_item_gone(nid: int) -> void:
	if mode == Mode.OFFER:
		for it in _offer_items:
			if int(it.get("nid", 0)) == nid:
				close()
				return
	elif mode == Mode.BAR and _nid == nid and not _stopped:
		_set_mode(Mode.NONE)


# ------------------------------------------------------------------ полоска (§11)

func _build_bar() -> void:
	_bar_panel = PanelContainer.new()
	_bar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_panel.position = Vector2(-BAR_W * 0.5 - 20, -230)
	_bar_panel.custom_minimum_size = Vector2(BAR_W + 40, 0)
	_bar_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.09, 0.9)))
	_bar_panel.visible = false
	_root.add_child(_bar_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_bar_panel.add_child(v)
	_bar_title = _mk_label(24, Color(1, 0.9, 0.5))
	_bar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_bar_title)
	_bar_sub = _mk_label(16, Color(0.85, 0.85, 0.85))
	_bar_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_bar_sub)
	_bar_area = Control.new()
	_bar_area.custom_minimum_size = Vector2(BAR_W, BAR_H)
	v.add_child(_bar_area)
	var red := ColorRect.new()
	red.color = Color(0.7, 0.12, 0.1)
	red.size = Vector2(BAR_W, BAR_H)
	_bar_area.add_child(red)
	_green = ColorRect.new()
	_green.color = Color(0.2, 0.85, 0.3)
	_green.size = Vector2(BAR_W * 0.3, BAR_H)
	_bar_area.add_child(_green)
	_marker = ColorRect.new()
	_marker.color = Color(1, 1, 1)
	_marker.size = Vector2(6, BAR_H + 12)
	_marker.position = Vector2(0, -6)
	_bar_area.add_child(_marker)
	_result = _mk_label(30, Color(1, 1, 1))
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.text = ""
	v.add_child(_result)
	var hint := _mk_label(16, Color(0.7, 0.7, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = tr("HAGGLE_BAR_HINT")
	v.add_child(hint)


## data: {"nid", "kind", "green_w", "green_pos", "speed", "amount_hit", "amount_miss"} — от хоста (haggle_start).
func start_bar(data: Dictionary) -> void:
	_nid = int(data.get("nid", 0))
	_green_w = clampf(float(data.get("green_w", 0.3)), 0.02, 1.0)
	_green_pos = clampf(float(data.get("green_pos", 0.5)), _green_w * 0.5, 1.0 - _green_w * 0.5)
	_base_speed = maxf(0.2, float(data.get("speed", 1.2)))
	_speed = _base_speed
	_hit_amt = int(data.get("amount_hit", 0))
	_miss_amt = int(data.get("amount_miss", 0))
	_pos = 0.0
	_dir = 1.0
	_elapsed = 0.0
	_tick_t = 0.0
	_stopped = false
	_result.text = ""
	_marker.color = Color.WHITE
	_bar_title.text = tr("HAGGLE_BAR_TITLE") % [_hit_amt, _miss_amt]
	_bar_sub.text = tr("HAGGLE_BAR_REJECT") if str(data.get("kind", "")) == "reject" else tr("HAGGLE_BAR_PARTIAL")
	_green.position.x = (_green_pos - _green_w * 0.5) * BAR_W
	_green.size.x = _green_w * BAR_W
	_marker.position.x = -3.0
	_set_mode(Mode.BAR)


func _process(delta: float) -> void:
	if mode != Mode.BAR:
		return
	if _stopped:
		_result_t -= delta
		if _result_t <= 0.0:
			_set_mode(Mode.NONE)
		return
	_elapsed += delta
	_speed = _base_speed * (1.0 + 0.12 * _elapsed)
	_pos += _dir * _speed * delta
	if _pos > 1.0:
		_pos = 2.0 - _pos
		_dir = -1.0
		AudioBus.play_ui("haggle_tick", -6.0)
	elif _pos < 0.0:
		_pos = -_pos
		_dir = 1.0
		AudioBus.play_ui("haggle_tick", -6.0)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 0.16
		AudioBus.play_ui("haggle_tick", -14.0)
	_marker.position.x = _pos * BAR_W - 3.0
	if _elapsed > BAR_TIMEOUT:
		_stop()


func _stop() -> void:
	if _stopped:
		return
	_stopped = true
	var half := _green_w * 0.5
	var dist := absf(_pos - _green_pos)
	var hit := dist <= half
	var precision := clampf(1.0 - dist / maxf(half, 0.001), 0.0, 1.0) if hit else 0.0
	_result.text = (tr("HAGGLE_HIT") % _hit_amt) if hit else (tr("HAGGLE_MISS") % _miss_amt)
	_result.add_theme_color_override("font_color", Color(0.6, 1, 0.6) if hit else Color(1, 0.6, 0.5))
	_marker.color = Color(0.6, 1, 0.6) if hit else Color(1, 0.4, 0.3)
	_result_t = RESULT_SEC
	bar_finished.emit(_nid, hit, precision)


# ------------------------------------------------------------------ ставка казино (§13)

func _build_bet() -> void:
	_bet_win = _mk_window("", Vector2i(460, 260))
	var v := _win_box(_bet_win)
	var title := _mk_label(28, Color(1, 0.85, 0.4))
	title.text = tr("BET_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _mk_label(16, Color(0.8, 0.8, 0.8))
	sub.text = tr("BET_SUB")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_bet_slider = HSlider.new()
	_bet_slider.step = 1.0
	_bet_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bet_slider.value_changed.connect(func(x):
		if _bet_syncing: return
		_bet_syncing = true
		_bet_spin.value = x
		_bet_syncing = false)
	row.add_child(_bet_slider)
	_bet_spin = SpinBox.new()
	_bet_spin.step = 1.0
	_bet_spin.prefix = "$"
	_bet_spin.custom_minimum_size = Vector2(120, 0)
	_bet_spin.value_changed.connect(func(x):
		if _bet_syncing: return
		_bet_syncing = true
		_bet_slider.value = x
		_bet_syncing = false)
	row.add_child(_bet_spin)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	v.add_child(btns)
	var b_red := Button.new()
	b_red.text = tr("BET_RED")
	b_red.custom_minimum_size = Vector2(150, 44)
	b_red.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	b_red.pressed.connect(func(): _send_bet(true))
	btns.add_child(b_red)
	var b_black := Button.new()
	b_black.text = tr("BET_BLACK")
	b_black.custom_minimum_size = Vector2(150, 44)
	b_black.pressed.connect(func(): _send_bet(false))
	btns.add_child(b_black)
	var b_cancel := Button.new()
	b_cancel.text = tr("HAGGLE_BTN_CANCEL")
	b_cancel.custom_minimum_size = Vector2(110, 44)
	b_cancel.pressed.connect(close)
	btns.add_child(b_cancel)


func open_bet(max_amount: int) -> void:
	_bet_max = maxi(0, max_amount)
	if _bet_max <= 0:
		Game.notify.emit(tr("POT_EMPTY"), 2.0)
		return
	_bet_syncing = true
	_bet_slider.min_value = 1
	_bet_slider.max_value = _bet_max
	_bet_spin.min_value = 1
	_bet_spin.max_value = _bet_max
	var start := clampi(int(_bet_max * 0.25), 1, _bet_max)
	_bet_slider.value = start
	_bet_spin.value = start
	_bet_syncing = false
	_set_mode(Mode.BET)


func _send_bet(red: bool) -> void:
	var amount := clampi(int(_bet_slider.value), 1, _bet_max)
	_set_mode(Mode.NONE)
	bet_sent.emit(amount, red)


# ------------------------------------------------------------------ ввод

func _input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	if mode == Mode.BAR:
		if event.is_action_pressed("grab") or event.is_action_pressed("use") or event.is_action_pressed("jump"):
			if not _stopped:
				_stop()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton or (event is InputEventKey and (event.is_action("grab") or event.is_action("use") or event.is_action("jump"))):
			get_viewport().set_input_as_handled()
		return
	# оффер / ставка: клики мимо окна и игровые кнопки — глотаем, чтобы не хватать вещи с прилавка
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var w := _offer_win if mode == Mode.OFFER else _bet_win
		var r := Rect2(Vector2(w.position), Vector2(w.size))
		if not r.has_point(mb.position):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	for a in ["use", "grab", "release", "throw", "second_hand", "alt_use", "pin", "paddle", "flashlight", "jump"]:
		if event.is_action(a):
			get_viewport().set_input_as_handled()
			return
