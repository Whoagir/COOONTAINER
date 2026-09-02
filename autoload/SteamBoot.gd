extends Node
## Обвязка GodotSteam (§3, §16). Всё через Engine.get_singleton("Steam") и защищено:
## без GDExtension игра работает как ENet/LAN + локальные ачивки. Для Steam-сборки положи
## addons/godotsteam (GDExtension) и steam_appid.txt рядом с бинарником.

signal lobby_created_ok(id: int)
signal lobby_joined(id: int)
signal lobby_invite_accepted(id: int)
signal overlay_toggled(active: bool)

const APP_ID := 480 # Spacewar (dev). Заменить на реальный AppID.

var enabled := false
var steam = null
var steam_id: int = 0
var persona: String = "Player"
var lobby_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("Steam"):
		print("[SteamBoot] Steam singleton not found → offline/LAN mode")
		return
	steam = Engine.get_singleton("Steam")
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))
	var init: Dictionary = {}
	if steam.has_method("steamInitEx"):
		init = steam.steamInitEx(APP_ID, true)
	elif steam.has_method("steamInit"):
		init = steam.steamInit(true)
	if init.get("status", 1) != 0:
		print("[SteamBoot] steamInit failed: %s" % str(init))
		steam = null
		return
	enabled = true
	steam_id = steam.getSteamID()
	persona = steam.getPersonaName()
	_connect_signal("lobby_created", _on_lobby_created)
	_connect_signal("lobby_joined", _on_lobby_joined)
	_connect_signal("join_requested", _on_join_requested)
	_connect_signal("overlay_toggled", _on_overlay_toggled)
	if steam.has_method("requestCurrentStats"):
		steam.requestCurrentStats()
	print("[SteamBoot] Steam OK: %s (%d)" % [persona, steam_id])


func _connect_signal(name: String, cb: Callable) -> void:
	if steam and steam.has_signal(name):
		steam.connect(name, cb)


func _process(_delta: float) -> void:
	if enabled and steam.has_method("run_callbacks"):
		steam.run_callbacks()


# ------------------------------------------------------------------ lobby

func create_lobby(max_players: int) -> void:
	if not enabled:
		return
	steam.createLobby(1, max_players) # 1 = LOBBY_TYPE_FRIENDS_ONLY


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		return
	lobby_id = id
	steam.setLobbyData(id, "game", "COOONTAINER")
	steam.setLobbyData(id, "host", str(steam_id))
	steam.setLobbyJoinable(id, true)
	lobby_created_ok.emit(id)
	Net.lobby_ready.emit(str(id))


func join_lobby(id: int) -> void:
	if not enabled:
		return
	lobby_id = id
	steam.joinLobby(id)


func _on_lobby_joined(id: int, _perms: int, _locked: bool, response: int) -> void:
	if response == 1:
		lobby_id = id
		lobby_joined.emit(id)


func _on_join_requested(id: int, _friend: int) -> void:
	lobby_invite_accepted.emit(id)


func lobby_owner(id: int) -> int:
	if not enabled:
		return 0
	return steam.getLobbyOwner(id)


func leave_lobby() -> void:
	if enabled and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0


func open_invite_overlay() -> void:
	if enabled and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)


func _on_overlay_toggled(active: bool, _user: bool, _app: int) -> void:
	overlay_toggled.emit(active)


# ------------------------------------------------------------------ cloud (§15)

func cloud_write(name: String, bytes: PackedByteArray) -> bool:
	if not enabled or not steam.has_method("fileWrite"):
		return false
	return steam.fileWrite(name, bytes)


func cloud_read(name: String) -> PackedByteArray:
	if not enabled or not steam.has_method("fileExists") or not steam.fileExists(name):
		return PackedByteArray()
	var size: int = steam.getFileSize(name)
	var d: Dictionary = steam.fileRead(name, size)
	return d.get("buffer", PackedByteArray())


# ------------------------------------------------------------------ achievements / stats (§16)

func set_achievement(id: String) -> void:
	if not enabled:
		return
	steam.setAchievement(id)
	steam.storeStats()


func set_stat(id: String, v: int) -> void:
	if not enabled:
		return
	steam.setStatInt(id, v)


# ------------------------------------------------------------------ voice (§3)

func voice_available() -> bool:
	return enabled and steam.has_method("getAvailableVoice")


func start_voice() -> void:
	if enabled:
		steam.startVoiceRecording()


func stop_voice() -> void:
	if enabled:
		steam.stopVoiceRecording()


func get_voice() -> PackedByteArray:
	if not enabled:
		return PackedByteArray()
	var avail: Dictionary = steam.getAvailableVoice()
	if avail.get("result", 1) != 0 or avail.get("buffer", 0) == 0:
		return PackedByteArray()
	var d: Dictionary = steam.getVoice()
	if d.get("result", 1) != 0:
		return PackedByteArray()
	return d.get("buffer", PackedByteArray())


func decompress_voice(data: PackedByteArray) -> PackedByteArray:
	if not enabled:
		return PackedByteArray()
	var d: Dictionary = steam.decompressVoice(data, 48000)
	if d.get("result", 1) != 0:
		return PackedByteArray()
	return d.get("uncompressed", PackedByteArray())
