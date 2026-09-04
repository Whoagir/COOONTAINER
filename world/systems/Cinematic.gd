extends Node
class_name Cinematic
## Катсцены и трейлер: своя камера, чёрные полосы, титры, фейды. Локально у каждого игрока (не по сети).
## Шот = Dictionary:
##   from/to: Vector3 позиции камеры; look / look_to: куда смотреть (интерполируется);
##   dur: сек; fov; title / sub: строки (уже tr()); fade_in / fade_out: сек; ease: 0 линейно, 1 smooth;
##   shake: 0..1; on_start: Callable — постановка сцены (спавн, поджиг, старт аукциона).
## Любая клавиша — скип (если skippable). Игрок заморожен через Player.cinematic.

signal finished
signal shot_started(index: int)

var playing := false
var skippable := true
var cam: Camera3D
var _layer: CanvasLayer
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _fade: ColorRect
var _title: Label
var _sub: Label
var _sub_panel: PanelContainer
var _skip_hint: Label
var _shots: Array = []
var _i := -1
var _t := 0.0
var _cur: Dictionary = {}
var _prev_cam: Camera3D
var _p: Player
var _shake := 0.0
var _hud_was_visible := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.name = "CineCam"
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 500.0
	add_child(cam)
	_layer = CanvasLayer.new()
	_layer.layer = 90
	_layer.visible = false
	add_child(_layer)
	_bar_top = _bar(true)
	_bar_bot = _bar(false)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 72)
	_title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title.position.y -= 40
	_title.rotation = -0.03
	_title.modulate.a = 0.0
	_layer.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 24)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT)
	_sub.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_panel = PanelContainer.new()
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_panel.visible = false
	var sub_sb := StyleBoxFlat.new()
	sub_sb.bg_color = Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.82)
	sub_sb.border_color = Color(UiTheme.BORDER_DARK.r, UiTheme.BORDER_DARK.g, UiTheme.BORDER_DARK.b, 0.6)
	sub_sb.set_border_width_all(2)
	sub_sb.set_corner_radius_all(12)
	sub_sb.content_margin_left = 22
	sub_sb.content_margin_right = 22
	sub_sb.content_margin_top = 12
	sub_sb.content_margin_bottom = 12
	_sub_panel.add_theme_stylebox_override("panel", sub_sb)
	_sub_panel.add_child(_sub)
	_layer.add_child(_sub_panel)
	_skip_hint = Label.new()
	_skip_hint.add_theme_font_size_override("font_size", 15)
	_skip_hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_skip_hint.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_skip_hint.add_theme_constant_override("outline_size", 4)
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip_hint.position += Vector2(-24, -28)
	_skip_hint.visible = false
	_layer.add_child(_skip_hint)
	get_viewport().size_changed.connect(_layout_text)
	_layout_text()


## Плашка и заголовок жили на жёсткой ширине 920 — на узком окне текст уезжал за левый край.
func _layout_text() -> void:
	if not is_instance_valid(_sub_panel):
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var sub_w: float = clampf(vw - 80.0, 240.0, 920.0)
	_sub_panel.custom_minimum_size.x = sub_w
	_sub_panel.offset_left = -sub_w * 0.5
	_sub_panel.offset_right = sub_w * 0.5
	# grow_vertical = BEGIN: нулевая высота на -130 от низа, min size растит плашку вверх
	_sub_panel.offset_top = -130.0
	_sub_panel.offset_bottom = -130.0
	var title_w: float = maxf(240.0, vw - 60.0)
	_title.offset_left = -title_w * 0.5
	_title.offset_right = title_w * 0.5


func _bar(top: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	r.custom_minimum_size = Vector2(0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(r)
	return r


# ------------------------------------------------------------------ API

## Запустить последовательность. Возвращается сразу; ждать — `await finished`.
func play(shots: Array, can_skip: bool = true) -> void:
	if playing or shots.is_empty():
		return
	begin(can_skip)
	_manual = false
	run(shots)


signal sequence_done
var _manual := false


## Ручной режим (трейлер): begin() → run([...]) / await sequence_done … → end().
## Между run'ами камера и полосы остаются, можно ставить сцену.
func begin(can_skip: bool = true) -> void:
	if playing:
		return
	_manual = true
	skippable = can_skip
	playing = true
	_p = Game.world.local_player() if Game.world else null
	_prev_cam = get_viewport().get_camera_3d()
	if _p:
		_p.cinematic = true
		_p.set_third_person(true)
	if Game.world and Game.world.hud:
		_hud_was_visible = Game.world.hud.visible
		Game.world.hud.visible = false
	_layer.visible = true
	_skip_hint.text = tr("CINE_SKIP") if can_skip else ""
	_skip_hint.visible = can_skip
	_bar_top.custom_minimum_size.y = 0
	_bar_bot.custom_minimum_size.y = 0
	var tw := create_tween()
	tw.tween_property(_bar_top, "custom_minimum_size:y", 70.0, 0.5)
	tw.parallel().tween_property(_bar_bot, "custom_minimum_size:y", 70.0, 0.5)
	cam.current = true
	_cur = {}


func run(shots: Array) -> void:
	_shots = shots
	_i = -1
	_advance()


func end() -> void:
	_manual = false
	stop()


func stop() -> void:
	if not playing:
		return
	playing = false
	_cur = {}
	_fade_tween(0.0, 0.35)
	var tw := create_tween()
	tw.tween_property(_bar_top, "custom_minimum_size:y", 0.0, 0.35)
	tw.parallel().tween_property(_bar_bot, "custom_minimum_size:y", 0.0, 0.35)
	tw.parallel().tween_property(_title, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(_sub_panel, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _layer.visible = false)
	if _p and is_instance_valid(_p):
		_p.cinematic = false
		_p.set_third_person(false)
		_p.camera.current = true
	elif _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	cam.current = false
	if Game.world and Game.world.hud:
		Game.world.hud.visible = _hud_was_visible
	finished.emit()


## Мгновенно: камера в точку, смотрит на цель (для ручной постановки кадра между шотами).
func snap(pos: Vector3, look: Vector3, fov: float = 60.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov


var _fade_tw: Tween


## Единственный твин затемнения: новый убивает старый, иначе fade_out и восстановление гоняются и экран остаётся чёрным.
func _fade_tween(to: float, sec: float) -> Tween:
	if _fade_tw and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.tween_property(_fade, "color:a", to, sec)
	return _fade_tw


func fade_to_black(sec: float = 0.6) -> void:
	await _fade_tween(1.0, sec).finished


func fade_from_black(sec: float = 0.6) -> void:
	await _fade_tween(0.0, sec).finished


func card(title: String, sub: String = "", hold: float = 2.2) -> void:
	_show_text(title, sub)
	await get_tree().create_timer(hold).timeout
	_hide_text()


# ------------------------------------------------------------------ внутренности

func _advance() -> void:
	_i += 1
	if _i >= _shots.size():
		_cur = {}
		if _manual:
			sequence_done.emit()
		else:
			stop()
		return
	_cur = _shots[_i]
	_t = 0.0
	_shake = float(_cur.get("shake", 0.0))
	cam.fov = float(_cur.get("fov", 60.0))
	if _cur.has("on_start"):
		var cb: Callable = _cur["on_start"]
		if cb.is_valid():
			cb.call()
	var from: Vector3 = _cur.get("from", cam.global_position)
	var look: Vector3 = _cur.get("look", from + Vector3.FORWARD)
	var follow: Node3D = _cur.get("follow", null) as Node3D
	if follow and is_instance_valid(follow):
		from = follow.global_position + (_cur.get("from", Vector3(3, 2, 3)) as Vector3)
		look = follow.global_position + (_cur.get("look", Vector3(0, 1, 0)) as Vector3)
	cam.global_position = from
	if look.distance_to(from) > 0.05:
		cam.look_at(look, Vector3.UP)
	var fin := float(_cur.get("fade_in", 0.0))
	if fin > 0.0:
		_fade.color.a = 1.0
		_fade_tween(0.0, fin)
	if _cur.has("title") or _cur.has("sub"):
		_show_text(str(_cur.get("title", "")), str(_cur.get("sub", "")), float(_cur.get("text_delay", 0.4)))
	shot_started.emit(_i)


func _show_text(title: String, sub: String, delay: float = 0.0) -> void:
	_layout_text() # размер окна на момент _ready ещё не финальный — меряем перед показом
	_title.text = title
	_sub.text = sub
	_sub_panel.visible = sub.strip_edges() != ""
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	if title != "":
		_title.scale = Vector2(1.15, 1.15)
		_title.pivot_offset = _title.size * 0.5
		tw.tween_property(_title, "modulate:a", 1.0, 0.35)
		tw.parallel().tween_property(_title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if sub.strip_edges() != "":
		_sub_panel.modulate.a = 0.0
		tw.parallel().tween_property(_sub_panel, "modulate:a", 1.0, 0.5)


func _hide_text(sec: float = 0.3) -> void:
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 0.0, sec)
	tw.parallel().tween_property(_sub_panel, "modulate:a", 0.0, sec)
	tw.tween_callback(func():
		_sub.text = ""
		_sub_panel.visible = false)


func _process(delta: float) -> void:
	if not playing or _cur.is_empty():
		return
	var dur := float(_cur.get("dur", 3.0))
	_t += delta
	var k := clampf(_t / dur, 0.0, 1.0)
	var e := k
	if int(_cur.get("ease", 1)) == 1:
		e = k * k * (3.0 - 2.0 * k)
	var from: Vector3 = _cur.get("from", cam.global_position)
	var to: Vector3 = _cur.get("to", from)
	var look_a: Vector3 = _cur.get("look", from + Vector3.FORWARD)
	var look_b: Vector3 = _cur.get("look_to", look_a)
	# follow: камера едет за узлом (тачка, игрок, хантер); from/to и look — смещения относительно него
	var follow: Node3D = _cur.get("follow", null) as Node3D
	if follow and is_instance_valid(follow):
		var base := follow.global_position
		from = base + (_cur.get("from", Vector3(3, 2, 3)) as Vector3)
		to = base + (_cur.get("to", _cur.get("from", Vector3(3, 2, 3))) as Vector3)
		look_a = base + (_cur.get("look", Vector3(0, 1, 0)) as Vector3)
		look_b = base + (_cur.get("look_to", _cur.get("look", Vector3(0, 1, 0))) as Vector3)
	var pos := from.lerp(to, e)
	if _shake > 0.0:
		var s := Time.get_ticks_msec() * 0.011
		pos += Vector3(sin(s * 1.3), cos(s * 1.7), sin(s * 0.9)) * 0.03 * _shake
	cam.global_position = pos
	var look := look_a.lerp(look_b, e)
	if look.distance_to(pos) > 0.05:
		cam.look_at(look, Vector3.UP)
	if _cur.has("fov_to"):
		cam.fov = lerpf(float(_cur.get("fov", 60.0)), float(_cur["fov_to"]), e)
	var fout := float(_cur.get("fade_out", 0.0))
	if fout > 0.0 and _t >= dur - fout and _fade.color.a < 0.99 and not _cur.get("_fading", false):
		_cur["_fading"] = true
		_fade_tween(1.0, fout)
	if (_cur.has("title") or _cur.has("sub")) and _t >= dur - 0.5 and not _cur.get("_text_hidden", false):
		_cur["_text_hidden"] = true
		_hide_text()
	if _t >= dur:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not playing or not skippable:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		stop()
