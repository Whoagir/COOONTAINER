class_name Auctioneer
extends Npc
## Аукционист (§9): объявляет старт/шаг/«идёт»/продано, держит молоток, звуки толпы.
## E по нему — начать торги; E со стволом в руках — угроза (скидка / выгон / менты).

var auction: Node = null # система Auction
var anchor: Node3D = null # LotAnchor
var _gavel: Node3D
var _murmur: AudioStreamPlayer3D
var _gavel_tw: Tween


func _ready() -> void:
	npc_group = "auctioneer"
	if display_name == "":
		display_name = tr("NPC_AUCTIONEER")
	super()
	_build_gavel()
	_murmur = AudioStreamPlayer3D.new()
	_murmur.bus = "SFX"
	_murmur.max_distance = 30.0
	_murmur.unit_size = 5.0
	_murmur.volume_db = -8.0
	_murmur.position.y = height
	add_child(_murmur)


func _build_gavel() -> void:
	_gavel = Node3D.new()
	_gavel.name = "Gavel"
	_gavel.position = Vector3(0.38, height * 0.55, -0.1)
	_gavel.rotation.x = deg_to_rad(-35.0)
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.015
	hm.bottom_radius = 0.018
	hm.height = 0.3
	hm.radial_segments = 8
	handle.mesh = hm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.14)
	handle.material_override = wood
	handle.position.y = 0.15
	_gavel.add_child(handle)
	var head := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.07, 0.07)
	head.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.3, 0.18, 0.1)
	head.material_override = dark
	head.position.y = 0.3
	_gavel.add_child(head)
	add_child(_gavel)


# ------------------------------------------------------------------ интерактив (хост зовёт)

func interact(player: Node) -> void:
	if not Net.is_host() or auction == null:
		return
	var held = player.hands.any_held() if player.get("hands") else null
	if held and held.def.has_facet(Types.Facet.WEAPON):
		if auction.has_method("threaten"):
			auction.threaten(anchor, player, self)
		return
	if auction.has_method("request_start"):
		auction.request_start(anchor, player)


func interact_hint(player: Node) -> String:
	var held = player.hands.any_held() if player.get("hands") else null
	if held and held.def.has_facet(Types.Facet.WEAPON):
		return tr("AUCTION_HINT_THREAT")
	if auction and auction.has_method("interact_hint_for"):
		return auction.interact_hint_for(anchor, player)
	return tr("AUCTION_INTERACT_HINT")


# ------------------------------------------------------------------ шоу

## category: start / step / going / sold / angry / police / threatened / tale
func announce(category: String, text: String, seconds: float = 2.5) -> void:
	say(text, seconds, category)


func gavel_hit() -> void:
	if _gavel_tw and _gavel_tw.is_valid():
		_gavel_tw.kill()
	_gavel_tw = create_tween()
	_gavel_tw.tween_property(_gavel, "rotation:x", deg_to_rad(-80.0), 0.12)
	_gavel_tw.tween_property(_gavel, "rotation:x", deg_to_rad(10.0), 0.08)
	_gavel_tw.tween_property(_gavel, "rotation:x", deg_to_rad(-35.0), 0.3)
	AudioBus.play_at("hammer", global_position + Vector3(0, height * 0.6, 0), 3.0, 0.08)


func ding() -> void:
	AudioBus.play_at("bid_ding", global_position + Vector3(0, height, 0), -2.0, 0.1)
	if _gavel:
		var tw := create_tween()
		tw.tween_property(_gavel, "rotation:x", deg_to_rad(-55.0), 0.06)
		tw.tween_property(_gavel, "rotation:x", deg_to_rad(-35.0), 0.12)


## crowd_gasp / crowd_laugh / crowd_murmur (разовые)
func crowd(name: String) -> void:
	AudioBus.play_at(name, global_position + Vector3(0, 1.0, 2.0), 0.0, 0.1)


func set_murmur(on: bool) -> void:
	if _murmur == null:
		return
	if on:
		if _murmur.playing:
			return
		var s := _load_loop("crowd_murmur")
		if s == null:
			return
		_murmur.stream = s
		_murmur.play()
	else:
		_murmur.stop()


func _load_loop(name: String) -> AudioStream:
	var path := "res://audio/sfx/%s.wav" % name
	if not ResourceLoader.exists(path):
		path = "res://audio/sfx/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return null
	var s := ResourceLoader.load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = s.data.size() / (2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if s.stereo else 1)
	elif s is AudioStreamOggVorbis:
		s.loop = true
	return s
