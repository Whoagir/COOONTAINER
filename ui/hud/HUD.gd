extends CanvasLayer
## Худ (§16): котёл, таймер лота. Без карты. Состояния вещей — на модели.
## Плюс: прицел, подсказка на что смотришь, тосты (ор/статус, не туториал), субтитры NPC, ачивки.

var pot_label: Label
var pot_delta: Label
var timer_label: Label
var timer_title: Label
var timer_bar: ProgressBar
var timer_panel: PanelContainer
var hint_label: Label
var hint_key: Label
var hint_key_panel: PanelContainer
var hint_panel: PanelContainer
var hint_row: HBoxContainer
var toast_box: VBoxContainer
var crosshair: Control
var bid_panel: PanelContainer
var bid_label: Label
var bid_leader: Label
var status_label: Label
var vignette: ColorRect
var dead_label: Label
var ach_panel: PanelContainer
var ach_label: Label
var subtitle: Label
var subtitle_panel: PanelContainer
var doc_panel: PanelContainer
var doc_label: RichTextLabel
var credits_panel: Control
var objective_panel: PanelContainer
var objective_title: Label
var objective_label: Label
var objective_dist: Label

var _objective_target: Vector3 = Vector3.INF
var _objective_t := 0.0
var _pot_shown: float = 0.0
var _pot_target: int = 0
var _timer_seconds := -1.0
var _timer_max := 0.0
var _overtime := false
var _delta_timer := 0.0
var _ach_timer := 0.0
var _sub_timer := 0.0
var _doc_timer := 0.0


func _ready() -> void:
	layer = 5
	_build()
	Economy.pot_changed.connect(_on_pot)
	Game.notify.connect(toast)
	Achievements.unlocked.connect(_on_achievement)
	Game.world_mode_changed.connect(_on_mode)
	_pot_target = Economy.pot
	_pot_shown = _pot_target
	pot_label.text = "$%d" % _pot_target


func _mk_label(size: int, color: Color = UiTheme.TEXT, outline := true) -> Label:
	return UiTheme.hud_label("", size, color, outline)


func _style_panel(p: PanelContainer, border: Color = UiTheme.ACCENT) -> void:
	p.add_theme_stylebox_override("panel", UiTheme.card_panel(border))


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0.2, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	# котёл — слева сверху, plum pill + жёлтый $
	var pot_panel := PanelContainer.new()
	pot_panel.position = Vector2(20, 16)
	pot_panel.add_theme_stylebox_override("panel", UiTheme.pill_panel())
	root.add_child(pot_panel)
	var pot_box := HBoxContainer.new()
	pot_box.add_theme_constant_override("separation", 10)
	pot_panel.add_child(pot_box)
	var pot_title := _mk_label(18, UiTheme.TEXT_DIM, false)
	pot_title.text = tr("HUD_POT")
	pot_box.add_child(pot_title)
	pot_label = _mk_label(52, UiTheme.SUCCESS)
	pot_label.text = "$0"
	pot_box.add_child(pot_label)
	pot_delta = _mk_label(28, UiTheme.SUCCESS)
	pot_delta.text = ""
	pot_delta.modulate.a = 0.0
	pot_box.add_child(pot_delta)

	# цель/задача — под котлом: «что делать дальше» (работа, штраф, подсказка пути)
	objective_panel = PanelContainer.new()
	objective_panel.position = Vector2(20, 96)
	objective_panel.custom_minimum_size = Vector2(300, 0)
	objective_panel.visible = false
	root.add_child(objective_panel)
	objective_panel.add_theme_stylebox_override("panel", UiTheme.pill_panel(UiTheme.PANEL_HI, 18))
	var obox := VBoxContainer.new()
	obox.add_theme_constant_override("separation", 2)
	objective_panel.add_child(obox)
	objective_title = _mk_label(15, UiTheme.ACCENT, false)
	objective_title.text = tr("HUD_OBJECTIVE")
	obox.add_child(objective_title)
	objective_label = _mk_label(19, UiTheme.TEXT, false)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size = Vector2(300, 0)
	objective_label.text = ""
	obox.add_child(objective_label)
	objective_dist = _mk_label(15, UiTheme.TEXT_DIM, false)
	objective_dist.text = ""
	obox.add_child(objective_dist)

	# таймер — сверху по центру, pill + оранжевый прогресс
	timer_panel = PanelContainer.new()
	timer_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_panel.position = Vector2(-130, 14)
	timer_panel.custom_minimum_size = Vector2(260, 0)
	timer_panel.visible = false
	root.add_child(timer_panel)
	_style_panel(timer_panel, UiTheme.BORDER_DARK)
	var tinner := VBoxContainer.new()
	tinner.add_theme_constant_override("separation", 4)
	timer_panel.add_child(tinner)
	timer_title = _mk_label(16, UiTheme.ACCENT, false)
	timer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_title.text = ""
	tinner.add_child(timer_title)
	timer_label = _mk_label(48, UiTheme.TEXT)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.text = ""
	tinner.add_child(timer_label)
	timer_bar = ProgressBar.new()
	timer_bar.custom_minimum_size = Vector2(220, 8)
	timer_bar.show_percentage = false
	timer_bar.max_value = 100.0
	timer_bar.value = 0.0
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.BORDER_DARK
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.ACCENT
	fill.set_corner_radius_all(4)
	timer_bar.add_theme_stylebox_override("background", track)
	timer_bar.add_theme_stylebox_override("fill", fill)
	tinner.add_child(timer_bar)

	# ставка на аукционе — справа сверху
	bid_panel = PanelContainer.new()
	bid_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bid_panel.position = Vector2(-300, 16)
	bid_panel.custom_minimum_size = Vector2(280, 0)
	bid_panel.visible = false
	root.add_child(bid_panel)
	_style_panel(bid_panel, UiTheme.MAGENTA)
	var bv := VBoxContainer.new()
	bid_panel.add_child(bv)
	var bt := _mk_label(16, UiTheme.ACCENT, false)
	bt.text = tr("HUD_BID")
	bv.add_child(bt)
	bid_label = _mk_label(44, UiTheme.SUCCESS)
	bid_label.text = "$0"
	bv.add_child(bid_label)
	bid_leader = _mk_label(18, UiTheme.TEXT_DIM, false)
	bid_leader.text = ""
	bv.add_child(bid_leader)

	# прицел
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	var dot := ColorRect.new()
	dot.color = Color(UiTheme.TEXT, 0.85)
	dot.size = Vector2(4, 4)
	dot.position = Vector2(-2, -2)
	crosshair.add_child(dot)

	# подсказка — низ по центру, pill + keycap
	hint_panel = PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.position = Vector2(-280, -56)
	hint_panel.custom_minimum_size = Vector2(560, 0)
	hint_panel.visible = false
	root.add_child(hint_panel)
	hint_panel.add_theme_stylebox_override("panel", UiTheme.pill_panel(UiTheme.PANEL_HI, 22))
	hint_row = HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 10)
	hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_panel.add_child(hint_row)
	hint_key_panel = PanelContainer.new()
	hint_key_panel.visible = false
	var key_sb := StyleBoxFlat.new()
	key_sb.bg_color = UiTheme.BORDER_DARK
	key_sb.border_color = UiTheme.ACCENT_DIM
	key_sb.set_border_width_all(2)
	key_sb.set_corner_radius_all(6)
	key_sb.content_margin_left = 10
	key_sb.content_margin_right = 10
	key_sb.content_margin_top = 4
	key_sb.content_margin_bottom = 4
	hint_key_panel.add_theme_stylebox_override("panel", key_sb)
	hint_key = _mk_label(20, UiTheme.TEXT, false)
	hint_key.text = "E"
	hint_key_panel.add_child(hint_key)
	hint_row.add_child(hint_key_panel)
	hint_label = _mk_label(22, UiTheme.TEXT, false)
	hint_label.custom_minimum_size = Vector2(480, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.text = ""
	hint_row.add_child(hint_label)

	status_label = _mk_label(18, UiTheme.DANGER, false)
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(24, -88)
	status_label.text = ""
	status_label.visible = false
	root.add_child(status_label)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toast_box.position = Vector2(-440, -260)
	toast_box.add_theme_constant_override("separation", 8)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.visible = false
	root.add_child(toast_box)

	subtitle_panel = PanelContainer.new()
	subtitle_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_panel.position = Vector2(-460, -145)
	subtitle_panel.custom_minimum_size = Vector2(920, 0)
	subtitle_panel.visible = false
	var sub_sb := StyleBoxFlat.new()
	sub_sb.bg_color = Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.82)
	sub_sb.border_color = Color(UiTheme.BORDER_DARK.r, UiTheme.BORDER_DARK.g, UiTheme.BORDER_DARK.b, 0.6)
	sub_sb.set_border_width_all(2)
	sub_sb.set_corner_radius_all(12)
	sub_sb.content_margin_left = 22
	sub_sb.content_margin_right = 22
	sub_sb.content_margin_top = 12
	sub_sb.content_margin_bottom = 12
	subtitle_panel.add_theme_stylebox_override("panel", sub_sb)
	root.add_child(subtitle_panel)
	subtitle = _mk_label(24, UiTheme.TEXT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = ""
	subtitle_panel.add_child(subtitle)

	dead_label = _mk_label(64, UiTheme.DANGER)
	dead_label.set_anchors_preset(Control.PRESET_CENTER)
	dead_label.position = Vector2(-300, -60)
	dead_label.custom_minimum_size = Vector2(600, 0)
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_label.text = ""
	dead_label.visible = false
	root.add_child(dead_label)

	ach_panel = PanelContainer.new()
	ach_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ach_panel.position = Vector2(-220, 110)
	ach_panel.custom_minimum_size = Vector2(440, 0)
	ach_panel.visible = false
	root.add_child(ach_panel)
	_style_panel(ach_panel, UiTheme.SUCCESS)
	ach_label = _mk_label(22, UiTheme.SUCCESS)
	ach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ach_panel.add_child(ach_label)

	doc_panel = PanelContainer.new()
	doc_panel.set_anchors_preset(Control.PRESET_CENTER)
	doc_panel.position = Vector2(-260, -160)
	doc_panel.custom_minimum_size = Vector2(520, 200)
	doc_panel.visible = false
	root.add_child(doc_panel)
	_style_panel(doc_panel)
	doc_label = RichTextLabel.new()
	doc_label.bbcode_enabled = true
	doc_label.fit_content = true
	doc_label.add_theme_font_size_override("normal_font_size", 22)
	doc_label.add_theme_color_override("default_color", UiTheme.TEXT)
	doc_panel.add_child(doc_label)


func _process(delta: float) -> void:
	_objective_t += delta
	if _objective_t >= 0.5:
		_objective_t = 0.0
		_tick_objective()
	if absf(_pot_shown - _pot_target) > 0.5:
		_pot_shown = lerpf(_pot_shown, _pot_target, minf(1.0, delta * 6.0))
		pot_label.text = "$%d" % int(round(_pot_shown))
	else:
		pot_label.text = "$%d" % _pot_target
	if _delta_timer > 0.0:
		_delta_timer -= delta
		pot_delta.modulate.a = clampf(_delta_timer, 0.0, 1.0)
	if _timer_seconds >= 0.0:
		timer_panel.visible = true
		timer_label.text = _fmt(_timer_seconds)
		var urgent := _overtime or _timer_seconds < 15.0
		timer_label.add_theme_color_override("font_color", UiTheme.DANGER if urgent else UiTheme.TEXT)
		if _timer_max > 0.0:
			timer_bar.value = clampf(_timer_seconds / _timer_max * 100.0, 0.0, 100.0)
		if _timer_seconds < 15.0 and not _overtime:
			timer_label.scale = Vector2.ONE * (1.0 + 0.08 * absf(sin(Time.get_ticks_msec() * 0.01)))
	else:
		timer_panel.visible = false
		timer_bar.value = 0.0
	if _ach_timer > 0.0:
		_ach_timer -= delta
		if _ach_timer <= 0.0:
			ach_panel.visible = false
	if _sub_timer > 0.0:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			subtitle.text = ""
			subtitle_panel.visible = false
	elif subtitle.text.strip_edges() != "":
		subtitle.text = ""
		subtitle_panel.visible = false
	if _doc_timer > 0.0:
		_doc_timer -= delta
		if _doc_timer <= 0.0:
			doc_panel.visible = false
	_update_player_hints()


func _fmt(s: float) -> String:
	var t := int(ceil(s))
	return "%d:%02d" % [t / 60, t % 60]


func _set_hint(txt: String, key_txt: String) -> void:
	txt = txt.strip_edges()
	var show := txt != ""
	hint_panel.visible = show
	hint_row.visible = show
	if not show:
		hint_label.text = ""
		hint_key_panel.visible = false
		return
	hint_label.text = txt
	if key_txt != "":
		hint_key.text = key_txt
	hint_key_panel.visible = key_txt != ""


func _update_player_hints() -> void:
	var p: Player = Game.world.local_player() if Game.world else null
	if p == null:
		_set_hint("", "")
		return
	var t = p.look_target() if not p.dead else null
	var txt := ""
	var key_txt := ""
	if t is ItemBody:
		txt = t.describe().strip_edges()
		if t.def.is_cash():
			txt += "  → %s" % tr("HUD_POT")
			key_txt = "E"
	elif t and t.has_method("interact_hint"):
		txt = str(t.interact_hint(p)).strip_edges()
		if txt != "":
			key_txt = "E"
	elif t and t.has_method("interact"):
		txt = "[E]"
		key_txt = "E"
	_set_hint(txt, key_txt)
	var st := ""
	if p.burning:
		st += tr("HUD_BURNING") + "  "
	if p.drunk > 0.3:
		st += tr("HUD_DRUNK") + "  "
	if p.cuffed:
		st += "🔗  "
	if p.wanted > 0.3:
		st += tr("HUD_WANTED") + "  "
	var held := p.hands.any_held()
	if held:
		st += "✋ " + held.describe()
		if p.hands.two_hands_same:
			st += " (2)"
	status_label.text = st
	status_label.visible = st != ""
	vignette.color.a = 0.35 if p.burning else (0.12 * clampf(1.0 - p.hp / 100.0, 0.0, 1.0))
	if p.burning:
		vignette.color = Color(1, 0.3, 0, 0.35 + 0.1 * sin(Time.get_ticks_msec() * 0.02))
	else:
		vignette.color = Color(0.6, 0, 0, vignette.color.a)
	dead_label.text = tr("HUD_DEAD") if p.dead else ""
	dead_label.visible = p.dead
	crosshair.visible = not p.dead


func _on_pot(v: int, delta: int, _reason: String) -> void:
	_pot_target = v
	if delta != 0:
		pot_delta.text = ("+%d" if delta > 0 else "%d") % delta
		pot_delta.add_theme_color_override("font_color", UiTheme.SUCCESS if delta > 0 else UiTheme.DANGER)
		_delta_timer = 2.5
		AudioBus.play_ui("coin" if delta > 0 else "coin_loss", -6.0)


func set_timer(seconds: float, title_key: String = "HUD_TIMER", overtime := false) -> void:
	if seconds < 0.0:
		clear_timer()
		return
	_timer_seconds = seconds
	_overtime = overtime
	timer_panel.visible = true
	timer_title.text = tr(title_key)
	if _timer_max <= 0.0 or seconds > _timer_max:
		_timer_max = seconds


func clear_timer() -> void:
	_timer_seconds = -1.0
	_overtime = false
	_timer_max = 0.0
	timer_label.text = ""
	timer_title.text = ""
	timer_label.scale = Vector2.ONE
	timer_bar.value = 0.0
	timer_panel.visible = false


func set_bid(amount: int, leader: String, yours: bool) -> void:
	bid_panel.visible = amount >= 0
	if amount < 0:
		return
	bid_label.text = "$%d" % amount
	bid_leader.text = ("★ " + tr("HUD_YOURS")) if yours else leader
	bid_label.add_theme_color_override("font_color", UiTheme.SUCCESS if yours else UiTheme.TEXT)


## Текущая цель («что делать»): текст + необязательная точка в мире — худ дописывает расстояние.
## Пустой текст — убрать. Зовут Jobs / Police / TrailerHub; локально у каждого игрока.
func set_objective(text: String, target: Vector3 = Vector3.INF) -> void:
	if text.strip_edges() == "":
		clear_objective()
		return
	objective_label.text = text
	_objective_target = target
	objective_dist.text = ""
	objective_dist.visible = target != Vector3.INF
	if not objective_panel.visible:
		objective_panel.visible = true
		objective_panel.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(objective_panel, "modulate:a", 1.0, 0.25)
	_objective_t = 0.0
	_tick_objective()


func clear_objective() -> void:
	objective_panel.visible = false
	objective_label.text = ""
	_objective_target = Vector3.INF


func has_objective() -> bool:
	return objective_panel.visible


func _tick_objective() -> void:
	if not objective_panel.visible or _objective_target == Vector3.INF:
		return
	var w = Game.world
	var p: Node3D = w.local_player() if w else null
	if p == null:
		return
	var d: float = p.global_position.distance_to(_objective_target)
	var to: Vector3 = _objective_target - p.global_position
	to.y = 0.0
	var arrow := ""
	if to.length() > 2.0:
		var fwd: Vector3 = -p.global_basis.z
		fwd.y = 0.0
		var ang := rad_to_deg(fwd.signed_angle_to(to.normalized(), Vector3.UP))
		if absf(ang) < 30.0:
			arrow = "↑"
		elif absf(ang) > 150.0:
			arrow = "↓"
		elif ang > 0.0:
			arrow = "←"
		else:
			arrow = "→"
	objective_dist.text = "%s %d м" % [arrow, int(d)]


func toast(text: String, seconds: float = 3.0) -> void:
	if text.strip_edges() == "":
		return
	toast_box.visible = true
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_panel())
	card.custom_minimum_size = Vector2(400, 0)
	var l := _mk_label(20, UiTheme.TEXT, false)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	card.add_child(l)
	toast_box.add_child(card)
	card.modulate.a = 0.0
	card.position.x = 40.0
	var tw_in := create_tween()
	tw_in.tween_property(card, "modulate:a", 1.0, 0.2)
	tw_in.parallel().tween_property(card, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	while toast_box.get_child_count() > 6:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	# карточку могли уже вытолкнуть из очереди (>6 тостов) — держим слабую ссылку,
	# иначе движок ругается на освобождённый захват лямбды
	var wr: WeakRef = weakref(card)
	tw.tween_callback(func():
		var c: Node = wr.get_ref()
		if c and c.get_parent() == toast_box:
			toast_box.remove_child(c)
			c.queue_free()
		if toast_box.get_child_count() == 0:
			toast_box.visible = false)


func show_subtitle(text: String, seconds: float = 3.0) -> void:
	if text.strip_edges() == "":
		subtitle.text = ""
		subtitle_panel.visible = false
		_sub_timer = 0.0
		return
	subtitle.text = text
	subtitle_panel.visible = true
	_sub_timer = seconds


func show_document(text: String) -> void:
	doc_label.text = text
	doc_panel.visible = true
	_doc_timer = 6.0


func _on_achievement(_id: String, title: String) -> void:
	ach_label.text = "🏆 " + title
	ach_panel.visible = true
	_ach_timer = 4.0


func _on_mode(m: int, _prev: int) -> void:
	if m != Types.WorldMode.AUCTION:
		bid_panel.visible = false
	if m != Types.WorldMode.CLEAR_OUT and m != Types.WorldMode.AUCTION and m != Types.WorldMode.JANITOR_JOB and m != Types.WorldMode.POLICE_CUSTODY:
		clear_timer()


var _lot_card: Control


func show_lot_card(d: Dictionary) -> void:
	if _lot_card and is_instance_valid(_lot_card):
		_lot_card.queue_free()
	var value := int(d.get("value", 0))
	var paid := int(d.get("paid", 0))
	var net := value - paid
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.position.y = 100
	card.custom_minimum_size = Vector2(560, 0)
	var border := UiTheme.SUCCESS if net >= 0 else UiTheme.DANGER
	card.add_theme_stylebox_override("panel", UiTheme.card_panel(border))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	_lot_card = card
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var title := _mk_label(32, UiTheme.ACCENT)
	title.text = tr("LOTCARD_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var rows: Array = [
		[tr("LOTCARD_HAUL"), "%d — $%d" % [int(d.get("haul", 0)), value]],
		[tr("LOTCARD_PAID"), "$%d" % paid],
	]
	if str(d.get("best", "")) != "":
		rows.append([tr("LOTCARD_BEST"), "%s ($%d)" % [str(d["best"]), int(d.get("best_value", 0))]])
	if int(d.get("broken", 0)) > 0:
		rows.append([tr("LOTCARD_BROKEN"), str(int(d["broken"]))])
	for r in rows:
		var h := HBoxContainer.new()
		var a := _mk_label(20, UiTheme.TEXT_DIM, false)
		a.text = r[0]
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := _mk_label(20, UiTheme.TEXT, false)
		b.text = r[1]
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(a)
		h.add_child(b)
		v.add_child(h)
	var verdict := _mk_label(26, UiTheme.SUCCESS if net >= 0 else UiTheme.DANGER)
	var vk := "LOTCARD_PROFIT" if net >= 0 else "LOTCARD_LOSS"
	var shown := absi(net)
	if bool(d.get("locked", false)):
		vk = "LOTCARD_LOCKED"
		shown = net
	elif bool(d.get("overtime", false)):
		vk = "LOTCARD_OVERTIME"
		shown = net
	verdict.text = tr(vk) % shown
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(verdict)
	var broom_key := str(d.get("broom", ""))
	if broom_key != "":
		var bl := _mk_label(17, UiTheme.TEXT_DIM, false)
		bl.text = tr(broom_key)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(bl)
	card.modulate.a = 0.0
	card.scale = Vector2(0.9, 0.9)
	card.pivot_offset = card.size * 0.5
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(7.5)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		if _lot_card == card:
			_lot_card = null
		card.queue_free())
	AudioBus.play_ui("coin" if net >= 0 else "buzzer", -6.0)


var _death_panel: Control


func show_death(reason: String, seconds: float = 5.0) -> void:
	hide_death()
	_death_panel = Control.new()
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death_panel)
	var vig := ColorRect.new()
	vig.color = Color(0.35, 0.02, 0.08, 0.0)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.add_child(vig)
	var stamp := _mk_label(96, UiTheme.DANGER)
	stamp.text = tr("HUD_DEAD")
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.set_anchors_preset(Control.PRESET_CENTER)
	stamp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stamp.grow_vertical = Control.GROW_DIRECTION_BOTH
	stamp.rotation = -0.08
	stamp.scale = Vector2(2.2, 2.2)
	stamp.modulate.a = 0.0
	_death_panel.add_child(stamp)
	stamp.pivot_offset = stamp.size * 0.5
	var why := _mk_label(28, UiTheme.TEXT)
	var key := "DEATH_" + reason.to_upper()
	why.text = tr(key) if tr(key) != key else reason
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	why.set_anchors_preset(Control.PRESET_CENTER)
	why.grow_horizontal = Control.GROW_DIRECTION_BOTH
	why.position.y += 80
	why.modulate.a = 0.0
	_death_panel.add_child(why)
	var cd := _mk_label(22, UiTheme.TEXT_DIM, false)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cd.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cd.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cd.position.y -= 90
	_death_panel.add_child(cd)
	var tw := create_tween()
	tw.tween_property(vig, "color:a", 0.6, 0.6)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.25).set_delay(0.3)
	tw.parallel().tween_property(stamp, "scale", Vector2.ONE, 0.35).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(why, "modulate:a", 1.0, 0.4).set_delay(0.7)
	var left := seconds
	while left > 0.0 and _death_panel and is_instance_valid(_death_panel):
		cd.text = tr("HUD_RESPAWN_IN") % ceili(left)
		await get_tree().create_timer(0.25).timeout
		left -= 0.25


func hide_death() -> void:
	if _death_panel and is_instance_valid(_death_panel):
		var p := _death_panel
		_death_panel = null
		var tw := create_tween()
		tw.tween_property(p, "modulate:a", 0.0, 0.4)
		tw.tween_callback(p.queue_free)


func show_credits() -> void:
	if credits_panel:
		return
	credits_panel = Control.new()
	credits_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	credits_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(credits_panel)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits_panel.add_child(bg)
	var txt := _mk_label(40, UiTheme.SUCCESS)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.set_anchors_preset(Control.PRESET_CENTER)
	txt.custom_minimum_size = Vector2(900, 0)
	txt.position = Vector2(-450, 400)
	txt.text = tr("CREDITS_TEXT") + "\n\n\n" + tr("CRED_CHRONICLE") + "\n" + Cutscenes.chronicle() + "\n\n\n" + tr("CRED_TAIL")
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits_panel.add_child(txt)
	var n_lines := txt.text.count("\n") + 4
	var scroll_sec := clampf(n_lines * 1.6, 24.0, 70.0)
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 0.8, 2.0)
	tw.parallel().tween_property(txt, "position:y", -60.0 * n_lines - 500.0, scroll_sec)
	tw.tween_property(bg, "color:a", 0.0, 2.0)
	tw.tween_callback(func():
		credits_panel.queue_free()
		credits_panel = null
		Game.set_world_mode(Types.WorldMode.TRAILER_HUB)
		Game.notify.emit(tr("NOTIFY_SANDBOX"), 6.0))
