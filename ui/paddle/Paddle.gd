class_name Paddle
extends Node3D
## Весло (§9, §18): деревянная лопатка в руке. Сумма — «мазня маркером» на SubViewport-текстуре.
## Ввод (только владелец, пока paddle_up): колесо ±шаг, цифры набирают число, Backspace стирает,
## Enter / ЛКМ (Player.raise()) — поднять = ставка. Чужие вёсла — просто проп, число дублируется Label3D.

const RAISE_SECONDS := 0.15
const HOLD_SECONDS := 0.8
const SYNC_EVERY := 0.25
const MAX_VALUE := 999999

var player: Node = null
var value := 0
var step := 5
var _required := 0
var _local := false
var _typing := false
var _face: PaddleFace
var _viewport: SubViewport
var _face_label: Label3D
var _mirror: Label3D
var _root: Node3D
var _tw: Tween
var _sync_timer := 0.0
var _dirty := false
var _flash_tw: Tween


func _ready() -> void:
	_build()
	Net.net_event.connect(_on_net_event)
	set_process_unhandled_input(false)


func set_owner_player(p: Node) -> void:
	player = p
	_local = p != null and p.has_method("is_local") and p.is_local()
	set_process_unhandled_input(_local)
	if _local and value == 0:
		set_value(step)


# ------------------------------------------------------------------ меш

func _build() -> void:
	_root = Node3D.new()
	_root.name = "PaddleRoot"
	add_child(_root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.36, 0.2)
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.016
	hm.bottom_radius = 0.02
	hm.height = 0.3
	hm.radial_segments = 8
	handle.mesh = hm
	handle.material_override = wood
	handle.position.y = 0.15
	_root.add_child(handle)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.3, 0.018)
	board.mesh = bm
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.62, 0.42, 0.24)
	board.material_override = board_mat
	board.position.y = 0.45
	_root.add_child(board)
	# лицевая сторона (+Z — к камере владельца)
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.27, 0.27)
	face.mesh = qm
	face.position = Vector3(0, 0.45, 0.0101)
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.95, 0.93, 0.85)
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.material_override = face_mat
	_root.add_child(face)
	if DisplayServer.get_name() != "headless":
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(256, 256)
		_viewport.disable_3d = true
		_viewport.transparent_bg = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_face = PaddleFace.new()
		_face.size = Vector2(256, 256)
		_viewport.add_child(_face)
		add_child(_viewport)
		face_mat.albedo_texture = _viewport.get_texture()
	else:
		_face_label = Label3D.new()
		_face_label.font_size = 64
		_face_label.pixel_size = 0.002
		_face_label.modulate = Color(0.1, 0.1, 0.35)
		_face_label.position = Vector3(0, 0.45, 0.012)
		_root.add_child(_face_label)
	# зеркало для остальных — над веслом
	_mirror = Label3D.new()
	_mirror.font_size = 56
	_mirror.pixel_size = 0.0035
	_mirror.outline_size = 8
	_mirror.modulate = Color(1, 0.95, 0.7)
	_mirror.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mirror.position.y = 0.68
	_root.add_child(_mirror)
	_refresh()


func _refresh() -> void:
	var txt := "$%d" % value
	if _face:
		_face.set_value(value)
		if _viewport:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _face_label:
		_face_label.text = txt
	if _mirror:
		_mirror.text = txt


func set_value(v: int, sync := true) -> void:
	v = clampi(v, 0, MAX_VALUE)
	if v == value:
		return
	value = v
	_refresh()
	if _local:
		var hud = Game.world.hud if Game.world else null
		if hud and hud.has_method("set_my_bid"):
			hud.set_my_bid(value, _typing)
		if sync:
			_dirty = true


# ------------------------------------------------------------------ ввод владельца

## Player._input зовёт первым (до GUI); _unhandled_input — запасной путь.
func consume_input(event: InputEvent) -> bool:
	if not _local or player == null or not bool(player.get("paddle_up")):
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_typing = false
			set_value(value + step)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_typing = false
			set_value(maxi(value - step, 0))
			return true
	elif event is InputEventKey and event.pressed and not event.echo:
		var d := _digit_of(event.keycode)
		if d < 0:
			d = _digit_of(event.physical_keycode)
		if d >= 0:
			if not _typing:
				_typing = true
				value = 0
			set_value(value * 10 + d)
			if value == 0:
				_refresh()
			return true
		var kc: int = event.keycode
		var pk: int = event.physical_keycode
		if kc == KEY_BACKSPACE:
			set_value(value / 10)
			return true
		if kc == KEY_ENTER or kc == KEY_KP_ENTER or pk == KEY_ENTER or pk == KEY_KP_ENTER:
			raise()
			return true
		if kc == KEY_EQUAL or kc == KEY_PLUS or kc == KEY_KP_ADD or pk == KEY_EQUAL or pk == KEY_PLUS or pk == KEY_KP_ADD:
			_typing = false
			set_value(value + step)
			return true
		if kc == KEY_MINUS or kc == KEY_KP_SUBTRACT or pk == KEY_MINUS or pk == KEY_KP_SUBTRACT:
			_typing = false
			set_value(maxi(value - step, 0))
			return true
		if kc == KEY_R or pk == KEY_R:
			_typing = false
			if _required > 0:
				set_value(_required)
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if consume_input(event):
		get_viewport().set_input_as_handled()


func _flash_red() -> void:
	if _face:
		_face.modulate = Color(1.0, 0.35, 0.35)
	if _face_label:
		_face_label.modulate = Color(1.0, 0.25, 0.25)
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	if _face:
		_flash_tw.tween_property(_face, "modulate", Color.WHITE, 0.45)
	if _face_label:
		_flash_tw.parallel().tween_property(_face_label, "modulate", Color(0.1, 0.1, 0.35), 0.45)


static func _digit_of(code: int) -> int:
	if code >= KEY_0 and code <= KEY_9:
		return code - KEY_0
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return code - KEY_KP_0
	return -1


## Поднять весло = ставка (Player зовёт по ЛКМ). У чужих — только анимация по событию auction_bid.
func raise() -> void:
	_animate_raise()
	if _local:
		_typing = false
		Net.request_action("bid", {"amount": value})


func _animate_raise() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_root.position = Vector3.ZERO
	_root.rotation = Vector3.ZERO
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_root, "position:y", 0.28, RAISE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_root, "rotation:z", deg_to_rad(randf_range(-12.0, 12.0)), RAISE_SECONDS)
	_tw.chain().tween_interval(HOLD_SECONDS)
	_tw.chain().tween_property(_root, "position:y", 0.0, 0.2)
	_tw.parallel().tween_property(_root, "rotation:z", 0.0, 0.2)
	AudioBus.play_at("whoosh", global_position, -10.0, 0.2)


func _process(delta: float) -> void:
	if not _local or not _dirty:
		return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_EVERY
		_dirty = false
		if Net.peer_count() > 1:
			Net.request_action("paddle_value", {"v": value})


# ------------------------------------------------------------------ события аукциона

func _on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"auction_state":
			if not _local or player == null:
				return
			var pos: Vector3 = data.get("pos", global_position)
			if global_position.distance_to(pos) > 45.0:
				return
			step = int(data.get("step", step))
			var req := int(data.get("req", 0))
			_required = req
			var i_lead: bool = bool(data.get("leader_is_player", false)) and int(data.get("leader_peer", 0)) == Net.my_id()
			if not i_lead and not _typing and value < req:
				set_value(req)
		"auction_bid":
			if _local or player == null:
				return
			if int(data.get("kind", 0)) == 1 and int(data.get("id", 0)) == player.get("peer_id"):
				set_value(int(data.get("amount", value)), false)
				_animate_raise()
		"auction_paddle":
			if _local or player == null:
				return
			if int(data.get("peer", 0)) == player.get("peer_id"):
				set_value(int(data.get("v", value)), false)
		"auction_bid_reject":
			if not _local:
				return
			var req_rej := int(data.get("req", 0))
			var hud = Game.world.hud if Game.world else null
			if hud:
				hud.toast(tr("AUC_BID_TOO_LOW_FMT") % req_rej, 3.0)
			if player != null and is_instance_valid(player):
				AudioBus.play_at("buzzer", player.global_position, -6.0)
			_flash_red()


# ------------------------------------------------------------------ кривой шрифт (общее с хантерами)

## Мазня на текстуре: то же перо, что у игрока. seed фиксирует почерк («лысый всегда красным»).
static func draw_face(amount: int, p_seed: int, ink: Color = Color(0.12, 0.1, 0.3, 0.92), px: int = 256) -> ImageTexture:
	var img: Image = PaddleFace.render_image(amount, p_seed, ink, px)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex


## Рисует число «маркером»: цифры из шаблонов-штрихов, точки дрожат, каждая цифра чуть повёрнута.
## Дрожание пересчитывается на каждое новое значение (у игрока). Хантеры зовут Paddle.draw_face.
class PaddleFace extends Control:
	const STROKES := {
		"0": [[Vector2(0.5, 0.05), Vector2(0.85, 0.2), Vector2(0.9, 0.5), Vector2(0.85, 0.8), Vector2(0.5, 0.95), Vector2(0.15, 0.8), Vector2(0.1, 0.5), Vector2(0.15, 0.2), Vector2(0.5, 0.05)]],
		"1": [[Vector2(0.3, 0.25), Vector2(0.55, 0.05), Vector2(0.55, 0.95)]],
		"2": [[Vector2(0.15, 0.25), Vector2(0.35, 0.05), Vector2(0.75, 0.08), Vector2(0.85, 0.3), Vector2(0.6, 0.55), Vector2(0.15, 0.95), Vector2(0.9, 0.95)]],
		"3": [[Vector2(0.15, 0.1), Vector2(0.8, 0.1), Vector2(0.45, 0.45), Vector2(0.85, 0.6), Vector2(0.8, 0.9), Vector2(0.15, 0.92)]],
		"4": [[Vector2(0.7, 0.95), Vector2(0.7, 0.05), Vector2(0.1, 0.65), Vector2(0.9, 0.65)]],
		"5": [[Vector2(0.85, 0.08), Vector2(0.2, 0.08), Vector2(0.15, 0.45), Vector2(0.6, 0.42), Vector2(0.88, 0.65), Vector2(0.7, 0.92), Vector2(0.12, 0.9)]],
		"6": [[Vector2(0.75, 0.08), Vector2(0.35, 0.3), Vector2(0.15, 0.6), Vector2(0.3, 0.9), Vector2(0.7, 0.9), Vector2(0.85, 0.7), Vector2(0.65, 0.52), Vector2(0.2, 0.6)]],
		"7": [[Vector2(0.1, 0.08), Vector2(0.9, 0.08), Vector2(0.4, 0.95)]],
		"8": [[Vector2(0.5, 0.5), Vector2(0.2, 0.3), Vector2(0.5, 0.05), Vector2(0.8, 0.3), Vector2(0.5, 0.5), Vector2(0.15, 0.75), Vector2(0.5, 0.95), Vector2(0.85, 0.75), Vector2(0.5, 0.5)]],
		"9": [[Vector2(0.8, 0.4), Vector2(0.5, 0.5), Vector2(0.2, 0.35), Vector2(0.3, 0.08), Vector2(0.7, 0.05), Vector2(0.85, 0.3), Vector2(0.8, 0.6), Vector2(0.6, 0.95), Vector2(0.25, 0.95)]],
		"$": [[Vector2(0.8, 0.2), Vector2(0.5, 0.1), Vector2(0.2, 0.25), Vector2(0.5, 0.5), Vector2(0.8, 0.75), Vector2(0.5, 0.9), Vector2(0.2, 0.8)], [Vector2(0.5, 0.0), Vector2(0.5, 1.0)]],
	}
	const INK := Color(0.12, 0.1, 0.3, 0.92)
	const PAPER := Color(0.95, 0.93, 0.85)

	var text := "$0"
	var _rng := RandomNumberGenerator.new()
	var _seed := 1

	func set_value(v: int) -> void:
		text = "$%d" % v
		_seed = randi()
		queue_redraw()

	func _draw() -> void:
		var layout: Dictionary = layout_strokes(text, _seed, size, INK)
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		var stains: Array = layout["stains"]
		for stn in stains:
			draw_circle(stn["c"], float(stn["r"]), stn["col"])
		var lines: Array = layout["lines"]
		for ln in lines:
			var pts: PackedVector2Array = ln["pts"]
			if pts.size() >= 2:
				draw_polyline(pts, ln["col"], float(ln["width"]), true)

	## Общая раскладка штрихов: и Control._draw, и Image для хантера.
	static func layout_strokes(p_text: String, p_seed: int, canvas: Vector2, ink: Color) -> Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.seed = p_seed if p_seed != 0 else 1
		var stains: Array = []
		for i in 6:
			stains.append({
				"c": Vector2(rng.randf() * canvas.x, rng.randf() * canvas.y),
				"r": rng.randf_range(2.0, 7.0),
				"col": Color(0.7, 0.65, 0.55, 0.25),
			})
		var lines: Array = []
		var n: int = maxi(p_text.length(), 1)
		var cell := minf(canvas.x / float(n) * 0.98, canvas.y * 0.72)
		var digit_h := cell * 1.48
		var total_w := cell * float(n)
		var x0 := (canvas.x - total_w) * 0.5
		var y0 := (canvas.y - digit_h) * 0.5
		var width := maxf(cell * 0.19, 8.0)
		var jitter := cell * 0.06
		for i in n:
			var ch := p_text[i] if i < p_text.length() else "0"
			var strokes: Array = STROKES.get(ch, STROKES["0"])
			var rot := rng.randf_range(-0.14, 0.14)
			var center := Vector2(x0 + cell * (float(i) + 0.5), y0 + digit_h * 0.5)
			var scale := Vector2(cell * 0.82, digit_h * 0.9)
			var wobble := rng.randf_range(0.92, 1.08)
			for st in strokes:
				var pts := PackedVector2Array()
				for k in st.size() - 1:
					var a: Vector2 = st[k]
					var b: Vector2 = st[k + 1]
					var segs := 5
					for q in segs:
						var t := float(q) / float(segs)
						pts.append(_place_static(a.lerp(b, t), center, scale * wobble, rot, jitter, rng))
				pts.append(_place_static(st[st.size() - 1], center, scale * wobble, rot, jitter, rng))
				if pts.size() >= 2:
					lines.append({"pts": pts, "width": width, "col": ink})
					var pts2 := PackedVector2Array()
					for p in pts:
						pts2.append(p + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(1.0, 3.0)))
					lines.append({"pts": pts2, "width": width * 0.55, "col": Color(ink.r, ink.g, ink.b, ink.a * 0.45)})
		return {"stains": stains, "lines": lines}

	static func _place_static(p: Vector2, center: Vector2, scale: Vector2, rot: float, jitter: float, rng: RandomNumberGenerator) -> Vector2:
		var local := (p - Vector2(0.5, 0.5)) * scale
		local = local.rotated(rot)
		local += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		return center + local

	static func render_image(amount: int, p_seed: int, ink: Color, px: int) -> Image:
		var canvas := Vector2(float(px), float(px))
		var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
		img.fill(PAPER)
		var layout: Dictionary = layout_strokes("$%d" % amount, p_seed, canvas, ink)
		for stn in layout["stains"]:
			_stamp_disk(img, stn["c"], float(stn["r"]), stn["col"])
		for ln in layout["lines"]:
			_stamp_polyline(img, ln["pts"], float(ln["width"]) * 0.5, ln["col"])
		return img

	static func _stamp_polyline(img: Image, pts: PackedVector2Array, radius: float, col: Color) -> void:
		if pts.size() < 2:
			return
		var r := maxf(radius, 1.2)
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var dist := a.distance_to(b)
			var steps := maxi(1, int(ceili(dist / maxf(r * 0.55, 1.0))))
			for s in steps + 1:
				var t := float(s) / float(steps)
				_stamp_disk(img, a.lerp(b, t), r, col)

	static func _stamp_disk(img: Image, c: Vector2, radius: float, col: Color) -> void:
		var w: int = img.get_width()
		var h: int = img.get_height()
		var ir := int(ceili(radius))
		var x0 := clampi(int(floorf(c.x)) - ir, 0, w - 1)
		var y0 := clampi(int(floorf(c.y)) - ir, 0, h - 1)
		var x1 := clampi(int(ceilf(c.x)) + ir, 0, w - 1)
		var y1 := clampi(int(ceilf(c.y)) + ir, 0, h - 1)
		var r2 := radius * radius
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var dx := float(x) + 0.5 - c.x
				var dy := float(y) + 0.5 - c.y
				if dx * dx + dy * dy > r2:
					continue
				var prev: Color = img.get_pixel(x, y)
				img.set_pixel(x, y, prev.lerp(col, col.a))
