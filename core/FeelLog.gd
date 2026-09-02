class_name FeelLog
extends RefCounted
## Диагностика «тряски» хвата и супепрыжков. Вкл: debug-сборка (не smoke/playtest) или `--feel-log`.
## Выкл: `--no-feel-log`. Смотри Output в редакторе / консоль Godot.

static var enabled := false
static var _boot := false
static var _hold_t := 0.0
static var _launch_t := 0.0
static var _shake_t := 0.0


static func ensure() -> void:
	if _boot:
		return
	_boot = true
	var args := OS.get_cmdline_user_args()
	if args.has("--no-feel-log"):
		enabled = false
		return
	if args.has("--feel-log"):
		enabled = true
	elif OS.is_debug_build() and not args.has("--smoke") and not args.has("--playtest") and not args.has("--nettest"):
		enabled = true
	if enabled:
		print("[FeelLog] ON — хват/прыжки в Output (выкл: --no-feel-log)")


static func grab(kind: String, item_id: String, shoulder_d: float, look_d: float, reach: float, arm: float, ok: bool, extra: String = "") -> void:
	ensure()
	if not enabled:
		return
	var far := "ДАЛЕКО" if shoulder_d > reach * 1.05 else ("ок" if shoulder_d <= reach * 0.85 else "на_грани")
	print("[Feel/grab] %s id=%s shoulder=%.2f look=%.2f reach=%.2f arm=%.2f %s ok=%s %s" % [
		kind, item_id, shoulder_d, look_d, reach, arm, far, str(ok), extra
	])


static func hold(item_id: String, err: float, vel: float, ang: float, shoulder_d: float, max_sep: float, player_v: float, force := false) -> void:
	ensure()
	if not enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	# спам только при тряске (err/vel высокие) или раз в ~0.35с
	var shaky := err > 0.10 or vel > 8.0 or ang > 0.55
	if not force and not shaky and now - _hold_t < 0.45:
		return
	if not force and shaky and now - _hold_t < 0.12:
		return
	_hold_t = now
	var tag := "ТРЯСКА" if shaky else "hold"
	print("[Feel/%s] id=%s err=%.3f vel=%.2f ang=%.2f shoulder=%.2f/%.2f pvel=%.2f" % [
		tag, item_id, err, vel, ang, shoulder_d, max_sep, player_v
	])


static func jump(vy_before: float, vy_after: float, on_floor: bool, floor_ny: float, collider: String, pos: Vector3, reason: String) -> void:
	ensure()
	if not enabled:
		return
	print("[Feel/jump] reason=%s vy %.2f→%.2f floor=%s n.y=%.2f hit=%s pos=(%.1f,%.2f,%.1f)" % [
		reason, vy_before, vy_after, str(on_floor), floor_ny, collider, pos.x, pos.y, pos.z
	])


static func launch(vy: float, on_floor: bool, floor_ny: float, collider: String, pos: Vector3, jumped: bool) -> void:
	ensure()
	if not enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _launch_t < 0.15:
		return
	_launch_t = now
	print("[Feel/LAUNCH] vy=%.2f floor=%s n.y=%.2f hit=%s jumped=%s pos=(%.1f,%.2f,%.1f) — подозрительный взлёт" % [
		vy, str(on_floor), floor_ny, collider, str(jumped), pos.x, pos.y, pos.z
	])


static func cam_shake(strength: float, src: String) -> void:
	ensure()
	if not enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if strength < 0.35 and now - _shake_t < 0.4:
		return
	_shake_t = now
	print("[Feel/shake] strength=%.2f src=%s" % [strength, src])
