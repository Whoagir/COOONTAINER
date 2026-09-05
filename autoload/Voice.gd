extends Node
## Внутриигровой proximity-голос (§3, §14). Push-to-talk V.
## Steam Voice если есть, иначе микрофон → AudioEffectCapture → сырые PCM 16k моно → unreliable RPC.
## Воспроизведение через AudioStreamGenerator на 3D-плеере у головы игрока.

const SAMPLE_RATE := 16000
const CHUNK := 1024

## Крик — механика, а не только чат (§3). Порог по RMS куска микрофона; клавиша `shout` даёт
## то же самое тем, у кого микрофона нет. Кулдаун, чтобы один вопль не сработал десять раз:
## микрофон отдаёт чанки по 1024 сэмпла, это ~20 срабатываний в секунду.
const SHOUT_RMS := 0.16
const SHOUT_CD := 1.2

signal shouted(loud: float)

var loudness := 0.0 ## RMS последнего чанка микрофона с учётом mic_gain (0..~1)
var _shout_cd := 0.0
var talking := false
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _bus_idx := -1
var _players: Dictionary = {} # peer → {player: AudioStreamPlayer3D, pb: AudioStreamGeneratorPlayback}
var _mix_rate := 48000.0
var mic_ok := false
var mute_all := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mix_rate = AudioServer.get_mix_rate()
	_setup_mic()


func _setup_mic() -> void:
	if AudioServer.get_bus_index("Mic") == -1:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, "Mic")
		AudioServer.set_bus_mute(_bus_idx, true)
	else:
		_bus_idx = AudioServer.get_bus_index("Mic")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(_bus_idx, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	mic_ok = ProjectSettings.get_setting("audio/driver/enable_input", false)


func _process(_delta: float) -> void:
	if Game.app_state != Game.AppState.IN_WORLD:
		return
	_shout_cd = maxf(0.0, _shout_cd - _delta)
	if Input.is_action_just_pressed("shout") and not get_tree().paused:
		_try_shout(1.0)
	var want := Input.is_action_pressed("voice") and not get_tree().paused
	if want != talking:
		talking = want
		if SteamBoot.voice_available():
			if talking:
				SteamBoot.start_voice()
			else:
				SteamBoot.stop_voice()
		elif mic_ok:
			if talking:
				_mic.play()
			else:
				_mic.stop()
		var me = Net.players.get(Net.my_id())
		if me and me.has_method("set_talking"):
			me.set_talking(talking)
	if not talking:
		if _capture and _capture.get_frames_available() > 0:
			_capture.clear_buffer()
		loudness = 0.0
		return
	# соло тоже мерим: орать в микрофон на смотрителя можно и без кореша, просто некому слушать
	if SteamBoot.voice_available():
		var d := SteamBoot.get_voice()
		if d.size() > 0 and Net.peer_count() > 1:
			Net.send_voice(PackedByteArray([1]) + d)
	elif mic_ok and _capture:
		while _capture.get_frames_available() >= CHUNK:
			var frames := _capture.get_buffer(CHUNK)
			_measure(frames)
			if Net.peer_count() > 1:
				Net.send_voice(PackedByteArray([0]) + _downsample(frames))


## Громкость чанка. Ор в микрофон = тот же крик, что и клавишей: смотритель выгоняет,
## менты греются, ворона улетает.
func _measure(frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	var sum := 0.0
	for v in frames:
		var m := (v.x + v.y) * 0.5
		sum += m * m
	loudness = sqrt(sum / float(frames.size())) * float(Settings.get_value("mic_gain"))
	if loudness >= SHOUT_RMS:
		_try_shout(loudness)


## Хост считает последствия; клиент только сообщает «я заорал».
func _try_shout(loud: float) -> void:
	if _shout_cd > 0.0 or Game.app_state != Game.AppState.IN_WORLD:
		return
	var me = Net.players.get(Net.my_id())
	if me == null or not is_instance_valid(me):
		return
	# мёртвым орать можно: труп слышно, а последствия каждая система отсеивает у себя
	_shout_cd = SHOUT_CD
	shouted.emit(loud)
	Net.request_action("shout", {"loud": clampf(loud, 0.0, 2.0)})


## 48k stereo → 16k mono int16.
func _downsample(frames: PackedVector2Array) -> PackedByteArray:
	var step := int(_mix_rate / SAMPLE_RATE)
	var out := PackedByteArray()
	var n := frames.size() / step
	out.resize(n * 2)
	for i in n:
		var v := frames[i * step]
		var s := int(clampf((v.x + v.y) * 0.5, -1.0, 1.0) * 32767.0)
		out.encode_s16(i * 2, s)
	return out


func receive(peer: int, data: PackedByteArray) -> void:
	if mute_all or data.size() < 2:
		return
	var kind := data[0]
	var pcm := data.slice(1)
	var rate := SAMPLE_RATE
	if kind == 1:
		pcm = SteamBoot.decompress_voice(pcm)
		rate = 48000
		if pcm.is_empty():
			return
	var entry := _ensure_player(peer, rate)
	var pb: AudioStreamGeneratorPlayback = entry["pb"]
	var n := pcm.size() / 2
	for i in n:
		if pb.get_frames_available() <= 0:
			break
		var s := pcm.decode_s16(i * 2) / 32767.0
		pb.push_frame(Vector2(s, s))
	var p = Net.players.get(peer)
	if p and p.has_method("set_talking"):
		p.set_talking(true)
		p.voice_timeout = 0.4


func _ensure_player(peer: int, rate: int) -> Dictionary:
	if _players.has(peer):
		var e: Dictionary = _players[peer]
		var pl = Net.players.get(peer)
		if pl and is_instance_valid(pl):
			e["player"].global_position = pl.head_position()
		return e
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.3
	var sp := AudioStreamPlayer3D.new()
	sp.stream = gen
	sp.bus = "Voice"
	sp.max_distance = 30.0
	sp.unit_size = 3.0
	add_child(sp)
	sp.play()
	var e := {"player": sp, "pb": sp.get_stream_playback()}
	_players[peer] = e
	return e
