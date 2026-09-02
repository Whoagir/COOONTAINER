extends Node
## Звук «весело в лоб» (§16). Пулы 3D-плееров, питч-рандом, NPC-крики RU/EN.
## Файлы: res://audio/sfx/*.wav, res://audio/music/*.wav|ogg, res://audio/voice/<lang>/<npc>/*.wav.

const SFX_DIR := "res://audio/sfx"
const MUSIC_DIR := "res://audio/music"
const VOICE_DIR := "res://audio/voice"
const POOL_SIZE := 24

var _sfx: Dictionary = {} # name → AudioStream
var _voice: Dictionary = {} # "lang/npc" → Array[AudioStream]
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _music: AudioStreamPlayer
var _music_name := ""
var _ui: AudioStreamPlayer
var master_volume := 1.0
var music_volume := 0.7
var sfx_volume := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 40.0
		p.unit_size = 4.0
		p.attenuation_filter_cutoff_hz = 8000
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ui = AudioStreamPlayer.new()
	_ui.bus = "SFX"
	add_child(_ui)
	_scan_sfx()


func _ensure_buses() -> void:
	for name in ["SFX", "Music", "Voice"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _scan_sfx() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		push_warning("[AudioBus] no sfx dir")
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if (n.ends_with(".wav") or n.ends_with(".ogg")) and not _sfx.has(n.get_basename()):
			var p := SFX_DIR.path_join(n)
			if ResourceLoader.exists(p):
				var s := ResourceLoader.load(p)
				if s:
					_sfx[n.get_basename()] = s
		f = dir.get_next()
	dir.list_dir_end()


func has(name: String) -> bool:
	return _sfx.has(name)


## Проиграть 3D-звук. pitch_rand — ± доля; volume в dB.
func play_at(name: String, pos: Vector3, volume_db: float = 0.0, pitch_rand: float = 0.15, pitch_base: float = 1.0) -> void:
	var s: AudioStream = _sfx.get(name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	p.stop()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db + linear_to_db(sfx_volume)
	p.pitch_scale = pitch_base * randf_range(1.0 - pitch_rand, 1.0 + pitch_rand)
	p.play()


func play_ui(name: String, volume_db: float = 0.0) -> void:
	var s: AudioStream = _sfx.get(name)
	if s == null:
		return
	_ui.stream = s
	_ui.volume_db = volume_db
	_ui.pitch_scale = randf_range(0.95, 1.05)
	_ui.play()


func play_music(name: String, loop_db: float = -8.0) -> void:
	if _music_name == name and _music.playing:
		return
	_music_name = name
	var path := MUSIC_DIR.path_join(name + ".wav")
	if not ResourceLoader.exists(path):
		path = MUSIC_DIR.path_join(name + ".ogg")
	if not ResourceLoader.exists(path):
		_music.stop()
		_music_name = ""
		return
	var s := ResourceLoader.load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# в сэмплах по длительности — не зависит от формата (PCM16/QOA/IMA-ADPCM)
		s.loop_begin = 0
		s.loop_end = int(round(s.get_length() * s.mix_rate))
	elif s is AudioStreamOggVorbis:
		s.loop = true
	_music.stream = s
	_music.volume_db = loop_db + linear_to_db(music_volume)
	_music.play()


func stop_music() -> void:
	_music_name = ""
	_music.stop()


## Зациклить WAV-семпл (для эмбиенса и лупов у источников).
func loop_stream(name: String) -> AudioStream:
	var s: AudioStream = _sfx.get(name)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(round(w.get_length() * w.mix_rate))
	return s


## NPC-реплика: res://audio/voice/<ru|en>/<npc_group>/*.wav, случайная, питч-рандом.
## Возвращает длительность (для субтитров/анимации рта).
func npc_shout(npc_group: String, pos: Vector3, pitch_base: float = 1.0, category: String = "") -> float:
	var lang := "ru" if TranslationServer.get_locale().begins_with("ru") else "en"
	var key := "%s/%s" % [lang, npc_group]
	if not _voice.has(key):
		_voice[key] = _scan_voice(lang, npc_group)
	var arr: Array = _voice[key]
	if arr.is_empty():
		play_at("shout_generic", pos, 0.0, 0.3, pitch_base)
		return 0.6
	var pool: Array = arr
	if category != "":
		var filtered: Array = []
		for e in arr:
			if e["name"].begins_with(category):
				filtered.append(e)
		if not filtered.is_empty():
			pool = filtered
	var e: Dictionary = pool[randi() % pool.size()]
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	p.stop()
	p.stream = e["stream"]
	p.bus = "Voice"
	p.global_position = pos
	p.volume_db = 2.0
	p.pitch_scale = pitch_base * randf_range(0.85, 1.2)
	p.play()
	var len: float = e["stream"].get_length() / p.pitch_scale
	return len


func _scan_voice(lang: String, group: String) -> Array:
	var out: Array = []
	var path := VOICE_DIR.path_join(lang).path_join(group)
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".wav") or n.ends_with(".ogg"):
			var p := path.path_join(n)
			if ResourceLoader.exists(p):
				var s := ResourceLoader.load(p)
				if s:
					out.append({"name": n.get_basename(), "stream": s})
		f = dir.get_next()
	dir.list_dir_end()
	return out


func set_master(v: float) -> void:
	master_volume = v
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))
