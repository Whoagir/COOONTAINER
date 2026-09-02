class_name ItemGags
## «Каждый элемент отвечает приколом» (§2 правило 1). Тег карточки → своя реакция на E.
## Вызывается из ItemBody.host_use ДО дефолтных ветвей. Вернул true — обработано.
## Универсальной кнопки «почини / оцени / продай» тут нет и не будет.

## Ключ прикола: тег карточки, иначе — билдер архетипа (чтобы прикол был у КАЖДОЙ вещи,
## даже если контент-таблица не проставила тег).
const BUILDER_KIND := {
	"kettle": "kettle", "teapot": "kettle",
	"boombox": "boombox", "radio": "radio",
	"camera": "camera",
	"umbrella": "umbrella",
	"ball": "ball",
	"guitar": "guitar", "trumpet": "trumpet", "drum": "drum", "keyboard_music": "piano_key", "piano": "piano_key",
	"clock": "clock", "clock_grandfather": "clock",
	"toy_bear": "toy", "doll": "toy", "toy_car": "toy",
	"mirror": "mirror",
	"globe": "globe",
	"trophy": "trophy",
	"skull": "skull",
	"perfume": "perfume",
	"bat": "bat", "sword": "melee", "knife": "melee", "hammer": "melee", "wrench": "melee",
	"bucket": "bucket",
	"broom": "broom", "mop": "broom",
	"nail_box": "nail",
	"fan": "fan",
	"dumbbell": "dumbbell",
	"cup": "mug", "glass": "mug",
	"phone": "phone_prop", "tablet": "phone_prop",
	"laptop": "laptop", "console": "console", "typewriter": "typewriter",
	"microwave": "microwave", "fridge": "fridge", "sink": "sink",
	"lamp_table": "lamp", "lamp_floor": "lamp", "chandelier": "lamp",
	"plant_pot": "plant", "statue": "statue", "bust": "statue",
	"bicycle": "bicycle", "skateboard": "skateboard", "tire": "tire",
	"sewing_machine": "sewing", "engine": "engine", "anvil": "anvil",
	"cassette": "cassette", "cd": "cassette", "usb": "usb",
	"fish_bowl": "fish", "bird_cage": "bird",
	"candle": "candle",
	"shoe": "shoe", "hat": "hat",
	"pillow": "pillow", "mattress": "mattress",
	"brick": "brick", "pallet": "brick",
	"remote": "remote",
}


static func use(b: ItemBody, player, other: ItemBody) -> bool:
	var t: Array = b.def.tags.duplicate()
	var kind: String = BUILDER_KIND.get(b.arch.builder, "")
	if kind != "" and not t.has(kind):
		t.append(kind)
	# --- инструменты и приколы, у которых своя жизнь
	if t.has("kettle"):
		return _kettle(b, player)
	if t.has("boombox") or t.has("radio"):
		return _boombox(b, player)
	if t.has("camera"):
		return _camera(b, player)
	if t.has("umbrella"):
		return _umbrella(b, player)
	if t.has("ball"):
		return _ball(b, player)
	if t.has("guitar") or t.has("trumpet") or t.has("drum") or t.has("piano_key"):
		return _instrument(b, player)
	if t.has("horn") or t.has("whistle"):
		AudioBus.play_at("car_horn", b.global_position, 4.0, 0.2)
		_scare(b, 8.0)
		return true
	if t.has("clock") or t.has("alarm"):
		return _alarm(b, player)
	if t.has("toy_squeak") or t.has("toy"):
		AudioBus.play_at("squeak", b.global_position, 0.0, 0.5)
		player.say(_line(["Пищит.", "Оно пищит."], ["It squeaks.", "Squeak."]))
		return true
	if t.has("mirror"):
		player.say(_line(["Ну и рожа.", "Красавчик."], ["What a face.", "Handsome."]))
		AudioBus.play_at("tap", b.global_position, -6.0)
		return true
	if t.has("globe"):
		b.angular_velocity += Vector3(0, 12.0, 0)
		AudioBus.play_at("drawer", b.global_position, -8.0)
		return true
	if t.has("trophy"):
		player.say(_line(["Первое место по ничему.", "Кубок за участие."], ["First place in nothing.", "Participation trophy."]))
		return true
	if t.has("skull"):
		AudioBus.play_at("crack", b.global_position, -2.0)
		player.say(_line(["Бедный Йорик. $12.", "Он на меня смотрит."], ["Alas, poor Yorick. $12.", "It's looking at me."]))
		return true
	if t.has("perfume"):
		return _perfume(b, player)
	if t.has("counterfeit"):
		player.say(_line(["Краска пачкает пальцы…", "Это точно не рубли."], ["The ink smudges…", "That's definitely not legal tender."]))
		AudioBus.play_at("cloth", b.global_position, -8.0)
		return true
	if t.has("sock"):
		player.say(_line(["Один. Всегда один.", "Второго нет. Нигде."], ["One. Always one.", "There is no second one. Anywhere."]))
		AudioBus.play_at("flop", b.global_position, -8.0)
		return true
	if t.has("mug") and b.integrity == Types.Integrity.WHOLE:
		player.say(_line(["Кружка «Лучший начальник».", "Ещё одна кружка."], ["'World's Best Boss' mug.", "Another mug."]))
		AudioBus.play_at("clink", b.global_position, -8.0)
		return true
	if t.has("bat") or t.has("melee"):
		return _swing(b, player)
	if t.has("bucket"):
		return _bucket(b, player)
	if t.has("broom"):
		player.say(_line(["Метла. Смотритель будет доволен.", "Подметать — тоже глагол."], ["A broom. The caretaker will be pleased.", "Sweeping is a verb too."]))
		return true
	if t.has("nail"):
		return _nails(b, player, other)
	if t.has("fan"):
		return _fan(b, player)
	if t.has("dumbbell"):
		player.say(_line(["Ух. Спина.", "Качаться потом."], ["Ugh. My back.", "I'll lift later."]))
		AudioBus.play_at("oof", player.global_position, -4.0)
		return true
	if t.has("glue"):
		return _glue(b, player, other)
	if t.has("phone_prop"):
		AudioBus.play_at("phone_beep", b.global_position, -2.0, 0.2)
		player.say(_line(["Разблокировать не выйдет.", "Пароль: 0000. Не подошёл."], ["Can't unlock it.", "Password: 0000. Nope."]))
		return true
	if t.has("laptop"):
		AudioBus.play_at("phone_beep", b.global_position, -6.0, 0.1, 0.6)
		player.say(_line(["Грузится. Ещё грузится. Всё, сдох.", "Вентилятор орёт как самолёт."], ["Booting. Still booting. Dead.", "The fan screams like a jet."]))
		return true
	if t.has("console"):
		AudioBus.play_at("achievement", b.global_position, -4.0, 0.1)
		player.say(_line(["Дисков нет. Но лампочка горит.", "Классика. Стоит дороже, чем кажется."], ["No discs. But the light is on.", "A classic. Worth more than it looks."]))
		return true
	if t.has("typewriter"):
		for i in 5:
			b.get_tree().create_timer(i * 0.09).timeout.connect(func():
				if is_instance_valid(b):
					AudioBus.play_at("tap", b.global_position, -4.0, 0.3, 1.6))
		player.say(_line(["Тук-тук-тук. Дзынь!", "Писатель, б."], ["Clack-clack-clack. Ding!", "A writer, huh."]))
		return true
	if t.has("microwave"):
		AudioBus.play_at("phone_beep", b.global_position, -2.0, 0.1, 0.8)
		player.say(_line(["Внутри что-то было. Давно.", "Пахнет 2009 годом."], ["Something was inside. Long ago.", "Smells like 2009."]))
		return true
	if t.has("fridge"):
		b.toggle_open(player)
		AudioBus.play_at("squelch", b.global_position, -2.0)
		player.say(_line(["Фу. Закрой обратно.", "Тут был салат. Наверное."], ["Ugh. Close it back.", "That was a salad. Probably."]))
		return true
	if t.has("sink"):
		var liq = Game.world.system("Liquids") if Game.world else null
		if liq:
			liq.pour(Types.LiquidId.WATER, b.global_position + Vector3(0, 0.6, 0), Vector3.DOWN, 0.35, b)
		player.say(_line(["Вода есть! Тряпку мочи.", "Кран работает."], ["There's water! Wet your rag.", "The tap works."]))
		return true
	if t.has("lamp"):
		b.lit = not b.lit
		var l := b.mesh_root.get_node_or_null("Bulb") as OmniLight3D
		if l == null and b.lit:
			l = OmniLight3D.new()
			l.name = "Bulb"
			l.omni_range = 6.0
			l.light_energy = 2.0
			l.light_color = Color(1.0, 0.9, 0.7)
			l.shadow_enabled = false
			l.position.y = b.arch.dims.y * 0.8
			b.mesh_root.add_child(l)
		if l:
			l.visible = b.lit
		AudioBus.play_at("tap", b.global_position, -8.0)
		b._push_state()
		return true
	if t.has("plant"):
		AudioBus.play_at("flop", b.global_position, -8.0)
		player.say(_line(["Пластиковый. Вечный.", "Полил. Он пластиковый."], ["Plastic. Eternal.", "Watered it. It's plastic."]))
		return true
	if t.has("statue"):
		player.say(_line(["Тяжёлая. Красивая. Никому не нужна.", "Искусство."], ["Heavy. Pretty. Nobody wants it.", "Art."]))
		AudioBus.play_at("thud_heavy", b.global_position, -6.0)
		return true
	if t.has("bicycle") or t.has("skateboard"):
		b.apply_central_impulse(-player.head.global_basis.z * b.mass * 6.0)
		AudioBus.play_at("tire_skid", b.global_position, -2.0, 0.2)
		player.say(_line(["Поехала!", "Катится сама. Ловите."], ["Off it goes!", "It rolls by itself. Catch it."]))
		return true
	if t.has("tire"):
		b.apply_torque_impulse(player.head.global_basis.x * b.mass * 6.0)
		AudioBus.play_at("bump_boing", b.global_position, -4.0)
		return true
	if t.has("sewing"):
		for i in 6:
			b.get_tree().create_timer(i * 0.07).timeout.connect(func():
				if is_instance_valid(b):
					AudioBus.play_at("tap", b.global_position, -8.0, 0.2, 2.0))
		return true
	if t.has("engine") or t.has("anvil"):
		player.take_damage(2.0, "back")
		player.say(_line(["Спина сказала «нет».", "Это не поднять одному."], ["My back said no.", "Can't lift this alone."]))
		AudioBus.play_at("oof", player.global_position, -2.0)
		return true
	if t.has("cassette"):
		AudioBus.play_at("drawer", b.global_position, -8.0, 0.3)
		player.say(_line(["Плёнку зажевало.", "Надо карандашом крутить."], ["The tape is chewed up.", "Need a pencil to rewind."]))
		return true
	if t.has("usb"):
		player.say(_line(["Что там? Никто не узнает.", "Флешка. Или не флешка."], ["What's on it? Nobody will know.", "A USB stick. Or is it."]))
		AudioBus.play_at("phone_beep", b.global_position, -6.0, 0.2, 1.4)
		return true
	if t.has("fish") or t.has("bird"):
		AudioBus.play_at("squeak", b.global_position, -2.0, 0.5)
		player.say(_line(["Оно смотрит на меня.", "Оно живое?! Ладно."], ["It's looking at me.", "Is it alive?! Fine."]))
		return true
	if t.has("candle"):
		b.lit = not b.lit
		b._push_state()
		AudioBus.play_at("ignite" if b.lit else "hiss", b.global_position, -4.0)
		if b.lit:
			player.say(_line(["Романтика. И пожар.", "Только не урони."], ["Romantic. And flammable.", "Just don't drop it."]))
		return true
	if t.has("shoe") or t.has("hat"):
		player.wear(b)
		return true
	if t.has("pillow") or t.has("mattress"):
		b.apply_central_impulse(-player.head.global_basis.z * b.mass * 8.0)
		AudioBus.play_at("flop", b.global_position, -2.0)
		player.say(_line(["Бой подушками!", "Мягкое. Дешёвое."], ["Pillow fight!", "Soft. Cheap."]))
		return true
	if t.has("brick"):
		player.say(_line(["Кирпич. Цена кирпича.", "В контейнере были кирпичи. Класс."], ["A brick. Worth a brick.", "The container had bricks. Great."]))
		AudioBus.play_at("thud_heavy", b.global_position, -6.0)
		return true
	if t.has("remote"):
		AudioBus.play_at("phone_beep", b.global_position, -8.0, 0.3, 1.8)
		# пульт «включает» все телевизоры рядом
		if Game.world:
			for other2 in Game.world.items_in_radius(b.global_position, 6.0):
				if other2.arch.builder.begins_with("tv") or other2.arch.builder == "monitor":
					var scr: Node = other2.mesh_root.get_node_or_null("Screen")
					if scr and scr is MeshInstance3D:
						var m: Material = (scr as MeshInstance3D).material_override
						if m is StandardMaterial3D:
							(m as StandardMaterial3D).emission_enabled = not (m as StandardMaterial3D).emission_enabled
					AudioBus.play_at("tap", other2.global_position, -6.0)
		player.say(_line(["Батарейки живые!", "Что-то щёлкнуло."], ["Batteries still work!", "Something clicked."]))
		return true
	return false


# ------------------------------------------------------------------ реализации

static func _kettle(b: ItemBody, player) -> bool:
	if b.get_meta("whistling", false):
		b.set_meta("whistling", false)
		AudioBus.play_at("hiss", b.global_position, -4.0)
		return true
	b.set_meta("whistling", true)
	AudioBus.play_at("hiss", b.global_position, -2.0)
	var timer := b.get_tree().create_timer(3.0)
	timer.timeout.connect(func():
		if not is_instance_valid(b) or not b.get_meta("whistling", false):
			return
		AudioBus.play_at("phone_beep", b.global_position, 6.0, 0.05, 2.4)
		_scare(b, 7.0)
		b.set_meta("whistling", false)
		if b.def.liquid_id == Types.LiquidId.NONE:
			b.integrity = maxi(b.integrity, Types.Integrity.CHIPPED) # кипятил пустой
			b._push_state())
	player.say(_line(["Поставил. Сейчас засвистит.", "Кипятим."], ["It's on. It'll whistle soon.", "Boiling."]))
	return true


static func _boombox(b: ItemBody, player) -> bool:
	var on: bool = not b.get_meta("playing", false)
	b.set_meta("playing", on)
	var p := b.get_node_or_null("Boom") as AudioStreamPlayer3D
	if on:
		if p == null:
			p = AudioStreamPlayer3D.new()
			p.name = "Boom"
			p.max_distance = 28.0
			p.unit_size = 5.0
			p.bus = "Music"
			b.add_child(p)
		var path := "res://audio/music/car_rock_loop.wav"
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStreamWAV:
				s = s.duplicate()
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			p.stream = s
			p.volume_db = -4.0
			p.pitch_scale = randf_range(0.85, 1.05)
			p.play()
		AudioBus.play_at("tap", b.global_position, -6.0)
		player.say(_line(["Работает! Дерьмовый рок.", "Звук есть — цена есть."], ["It works! Crappy rock.", "It plays, so it sells."]))
		Game.stat_add("boombox_on")
		_scare(b, 6.0)
	else:
		if p:
			p.stop()
	return true


static func _camera(b: ItemBody, player) -> bool:
	AudioBus.play_at("camera_shutter", b.global_position, 2.0, 0.1)
	var flash := OmniLight3D.new()
	flash.light_energy = 12.0
	flash.omni_range = 8.0
	flash.shadow_enabled = false
	b.add_child(flash)
	b.get_tree().create_timer(0.08).timeout.connect(func():
		if is_instance_valid(flash):
			flash.queue_free())
	# вспышка пугает NPC и слепит игроков рядом
	_scare(b, 6.0)
	player.say(_line(["Плёнки нет. Но щёлкает.", "Улыбочку."], ["No film. Still clicks.", "Say cheese."]))
	Game.stat_add("photos")
	return true


static func _umbrella(b: ItemBody, player) -> bool:
	var open: bool = not b.get_meta("open", false)
	b.set_meta("open", open)
	var mesh := b.mesh_root
	if mesh:
		var canopy := mesh.get_child(mesh.get_child_count() - 1)
		if canopy is Node3D:
			var tw := b.create_tween()
			tw.tween_property(canopy, "scale", Vector3(2.2, 0.6, 2.2) if open else Vector3.ONE, 0.25)
	AudioBus.play_at("cloth", b.global_position, -2.0)
	if open:
		# зонт в руках = парашют: замедляет падение
		b.set_meta("parachute", true)
		player.say(_line(["Открыл в помещении. Примета.", "Мэри Поппинс, б."], ["Opened it indoors. Bad luck.", "Mary Poppins, huh."]))
	return true


static func _ball(b: ItemBody, player) -> bool:
	b.physics_material_override.bounce = 0.92 if b.physics_material_override.bounce < 0.5 else 0.05
	b.apply_central_impulse(Vector3.DOWN * b.mass * 4.0)
	AudioBus.play_at("bump_boing", b.global_position, 0.0, 0.2)
	return true


static func _instrument(b: ItemBody, player) -> bool:
	var notes := ["bid_ding", "clink", "phone_beep"]
	for i in 3:
		var d := i * 0.14
		b.get_tree().create_timer(d).timeout.connect(func():
			if is_instance_valid(b):
				AudioBus.play_at(notes[i % notes.size()], b.global_position, -2.0, 0.05, randf_range(0.7, 1.6)))
	player.say(_line(["Я музыкант.", "Три аккорда — и я на сцене."], ["I'm a musician.", "Three chords and I'm famous."]))
	Game.stat_add("jams")
	if Game.stat("jams") >= 10:
		Achievements.unlock("bookworm") # заглушка: любая «мелкая» ачивка
	return true


static func _alarm(b: ItemBody, player) -> bool:
	AudioBus.play_at("buzzer", b.global_position, 4.0, 0.1)
	_scare(b, 9.0)
	player.say(_line(["Он ещё идёт!", "Будильник сработал."], ["It still works!", "The alarm went off."]))
	return true


static func _perfume(b: ItemBody, player) -> bool:
	AudioBus.play_at("water_spray", b.global_position, -2.0, 0.2)
	# аромат: NPC рядом реагируют, скупщик с фобией «мокро» — тоже
	for n in b.get_tree().get_nodes_in_group("npcs"):
		if n is Npc and n.global_position.distance_to(b.global_position) < 4.0:
			n.say(_line(["Фу, чем это пахнет?!", "Ты чем побрызгал?"], ["Ugh, what is that smell?!", "What did you spray?"]), 2.0, "angry")
	player.say(_line(["Пахнет бабушкой и деньгами.", "Крепкая штука."], ["Smells like grandma and money.", "Strong stuff."]))
	return true


static func _swing(b: ItemBody, player) -> bool:
	# замах: сильный импульс вперёд, урон по тому, во что попал (физика сделает остальное)
	var dir: Vector3 = -player.head.global_basis.z
	b.set_meta("swinging", Time.get_ticks_msec())
	b.linear_velocity = dir * 14.0 + Vector3.UP * 1.5
	b.angular_velocity = player.head.global_basis.x * 12.0
	AudioBus.play_at("whoosh", b.global_position, -2.0, 0.2)
	Game.stat_add("swings")
	return true


static func _bucket(b: ItemBody, player) -> bool:
	# ведро: надеть на голову себе или подставить под жидкость
	if b.get_meta("on_head", false):
		b.set_meta("on_head", false)
		player.unwear()
		return true
	var target = player.look_target()
	if target is Player and target != player:
		b.set_meta("on_head", true)
		target.wear(b)
		target.say(_line(["Я НИЧЕГО НЕ ВИЖУ", "ЭТО НЕ СМЕШНО"], ["I CAN'T SEE ANYTHING", "THIS ISN'T FUNNY"]))
		AudioBus.play_at("thud", target.global_position, 0.0)
		Achievements.unlock("painted_friend")
		return true
	b.set_meta("on_head", true)
	player.wear(b)
	player.say(_line(["Шлем.", "Ничего не вижу, зато безопасно."], ["Helmet.", "Can't see, but safe."]))
	return true


static func _nails(b: ItemBody, player, other: ItemBody) -> bool:
	if other and other.def.tags.has("plank"):
		player.say(_line(["Доска и гвозди. Заколачиваем.", "Молотка бы."], ["Plank and nails. Boarding it up.", "Could use a hammer."]))
		return false # пусть дальше сработает патч
	AudioBus.play_at("hammer_nail", b.global_position, -2.0)
	player.take_damage(3.0, "nails")
	player.say(_line(["Ай. Гвоздь.", "Наступил. Классика."], ["Ow. A nail.", "Stepped on it. Classic."]))
	return true


static func _fan(b: ItemBody, player) -> bool:
	var on: bool = not b.get_meta("fan_on", false)
	b.set_meta("fan_on", on)
	AudioBus.play_at("tap" if not on else "car_engine_loop", b.global_position, -8.0)
	if on:
		# вентилятор гоняет бумажки вокруг
		var t := b.get_tree().create_timer(0.5)
		t.timeout.connect(func():
			if not is_instance_valid(b) or not b.get_meta("fan_on", false):
				return
			for other in Game.world.items_in_radius(b.global_position, 3.5):
				if other != b and other.mass < 0.8:
					other.sleeping = false
					other.apply_central_impulse(-b.global_basis.z * other.mass * 1.2))
		player.say(_line(["Дует. Бумажки полетели.", "Работает даже это."], ["It blows. Papers everywhere.", "Even this works."]))
	return true


static func _glue(b: ItemBody, player, other: ItemBody) -> bool:
	# клей (§7.3, опционально): вещь-вещь, чел-вещь, чел-чел
	if other:
		other.glued = true
		other.linear_damp = 6.0
		other._push_state()
		AudioBus.play_at("squelch", b.global_position, -2.0)
		player.say(_line(["Приклеил. Молодец.", "Теперь не отдерёшь."], ["Glued it. Well done.", "That's not coming off."]))
		return true
	var target = player.look_target()
	if target is Player:
		target.stuck = 5.0
		target.say(_line(["Я ПРИЛИП", "СПАСИБО, КОРЕШ"], ["I'M STUCK", "THANKS, BUDDY"]))
		AudioBus.play_at("squelch", target.global_position, 0.0)
		return true
	if target is ItemBody:
		target.glued = true
		target._push_state()
		return true
	player.stuck = 3.0
	player.say(_line(["Клей на руках.", "Зачем я это сделал."], ["Glue on my hands.", "Why did I do that."]))
	return true


# ------------------------------------------------------------------ утилиты

## Резкий звук пугает NPC поблизости: подпрыгивают и орут.
static func _scare(b: ItemBody, radius: float) -> void:
	if Game.world == null:
		return
	for n in Game.world.npcs_root.get_children():
		if n is Npc and n.global_position.distance_to(b.global_position) < radius:
			n.shove(Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)))


static func _line(ru: Array, en: Array) -> String:
	var arr: Array = ru if TranslationServer.get_locale().begins_with("ru") else en
	return arr[randi() % arr.size()]
