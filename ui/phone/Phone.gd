class_name PhoneOverlay
extends CanvasLayer
## Телефон (§11): рамка телефона + видоискатель в центре экрана. E — открыть, E — снять.
## Оценщик «ЦеноБот»: честная ±10% если вещь в прицеле (<3 м); если вещь только где-то в кадре —
## ВРЁТ (0.2×..5×) уверенным тоном; если ничего — «похоже на пол». Всё локально, хост не нужен.

signal photo_taken(result: Dictionary)

const EXACT_DIST := 3.0
const CONE_DIST := 4.0
const CONE_DEG := 25.0
const RESULT_SEC := 3.5

var _root: Control
var _frame: PanelContainer
var _viewfinder: Panel
var _title: Label
var _result: Label
var _flash: ColorRect
var _open := false
var _result_t := 0.0
var _capturing := false


func _ready() -> void:
	layer = 7
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_build()
	set_process(false)


func _build() -> void:
	# корпус телефона — тёмная рамка с дыркой-экраном по центру
	_frame = PanelContainer.new()
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.custom_minimum_size = Vector2(440, 760)
	_frame.position = Vector2(-220, -380)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(22)
	sb.border_color = Color(0.08, 0.08, 0.1, 0.96)
	sb.set_corner_radius_all(46)
	sb.set_content_margin_all(30)
	_frame.add_theme_stylebox_override("panel", sb)
	_root.add_child(_frame)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_frame.add_child(v)
	_title = _mk_label(22, Color(0.6, 0.95, 1.0))
	_title.text = tr("PHONE_APP")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 90)
	v.add_child(spacer)
	_viewfinder = Panel.new()
	_viewfinder.custom_minimum_size = Vector2(300, 300)
	_viewfinder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_viewfinder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vf := StyleBoxFlat.new()
	vf.bg_color = Color(0, 0, 0, 0)
	vf.set_border_width_all(3)
	vf.border_color = Color(1, 1, 1, 0.85)
	vf.set_corner_radius_all(6)
	_viewfinder.add_theme_stylebox_override("panel", vf)
	v.add_child(_viewfinder)
	var cross := _mk_label(28, Color(1, 1, 1, 0.8))
	cross.text = "+"
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.position = Vector2(0, 130)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-14, -20)
	_viewfinder.add_child(cross)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 40)
	v.add_child(spacer2)
	_result = _mk_label(22, Color(1, 1, 0.9))
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(340, 0)
	_result.text = tr("PHONE_HINT")
	v.add_child(_result)
	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 30)
	spacer3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer3)
	var shutter := _mk_label(44, Color(1, 1, 1, 0.9))
	shutter.text = "◉"
	shutter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(shutter)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


func _mk_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(3, size / 7))
	return l


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	_root.visible = true
	_result.text = tr("PHONE_HINT")
	_result_t = 0.0
	set_process(true)
	AudioBus.play_ui("tap", -8.0)


func close() -> void:
	_open = false
	_root.visible = false
	set_process(false)


## Снимок: вспышка, щелчок, оценка. Возвращает результат (см. estimate).
func snap(player: Player) -> Dictionary:
	if not _open:
		open()
	var res := estimate(player)
	_result.text = str(res.get("text", ""))
	_flash.color = Color(1, 1, 1, 0.85)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.4)
	AudioBus.play_ui("camera_shutter", 0.0)
	_result_t = RESULT_SEC
	if float(res.get("lie", 1.0)) > 3.0:
		Achievements.unlock("phone_liar")
	photo_taken.emit(res)
	_capture(res)
	return res


## Кадр в плёнку: на один кадр убираем рамку телефона и худ, иначе на снимке будет интерфейс,
## а не то, что снимали. Подпись — то, что сказал ЦеноБот (он же и врёт).
func _capture(res: Dictionary) -> void:
	var roll: Node = Game.world.system("PhotoRoll") if Game.world else null
	if roll == null or not roll.has_method("add_shot") or _capturing:
		return # два снимка подряд не должны перепрятать друг у друга худ
	_capturing = true
	var hud: CanvasLayer = Game.world.hud if Game.world else null
	var hud_was: bool = hud.visible if hud else false
	_root.visible = false
	if hud:
		hud.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_root.visible = _open
	if hud:
		hud.visible = hud_was
	_capturing = false
	roll.add_shot(img, str(res.get("text", "")))


func _process(delta: float) -> void:
	if _result_t > 0.0:
		_result_t -= delta
		if _result_t <= 0.0:
			close()


## Что в кадре: {"text", "value", "lie": ratio(1.0 = честно), "target": ItemBody|null, "kind": exact|lie|floor}.
static func estimate(player: Player) -> Dictionary:
	if player == null or player.camera == null:
		return {"text": tr_static("PHONE_FLOOR"), "value": 0, "lie": 1.0, "target": null, "kind": "floor"}
	var cam: Camera3D = player.camera
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var t = player.look_target()
	if t is ItemBody and not _held_by(t, player) and t.global_position.distance_to(origin) < EXACT_DIST:
		var cv: int = t.current_value()
		var v := maxi(1, int(round(cv * randf_range(0.9, 1.1))))
		return {"text": tr_static("PHONE_ESTIMATE") % [t.def.display_name(), v], "value": v, "lie": 1.0, "target": t, "kind": "exact"}
	# в кадре, но не в прицеле — врём уверенно
	var cos_lim := cos(deg_to_rad(CONE_DEG))
	var best: ItemBody = null
	var best_dot := -1.0
	for nid in Net.items:
		var b = Net.items[nid]
		if b == null or not is_instance_valid(b) or not (b is ItemBody):
			continue
		if b.nested_in != null or _held_by(b, player) or b.get_meta("pocket_of", 0) != 0:
			continue
		var to: Vector3 = b.global_position - origin
		var d := to.length()
		if d > CONE_DIST or d < 0.05:
			continue
		var dot := fwd.dot(to / d)
		if dot >= cos_lim and dot > best_dot:
			best_dot = dot
			best = b
	if best:
		var ratio := exp(randf_range(log(0.2), log(5.0)))
		var cv2: int = best.current_value()
		var v2 := maxi(1, int(round(cv2 * ratio)))
		return {"text": tr_static("PHONE_CONFIDENT") % [best.def.display_name(), v2], "value": v2, "lie": ratio, "target": best, "kind": "lie"}
	return {"text": tr_static("PHONE_FLOOR"), "value": 0, "lie": 1.0, "target": null, "kind": "floor"}


static func _held_by(b: ItemBody, player: Player) -> bool:
	for h in b.held_by:
		if h and is_instance_valid(h) and h.player == player:
			return true
	return false


static func tr_static(key: String) -> String:
	return TranslationServer.translate(key)
