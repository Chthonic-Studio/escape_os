extends Node

## Centralized audio manager.

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_VFX1: StringName = &"VFX1"
const BUS_VFX2: StringName = &"VFX2"
const BUS_VFX3: StringName = &"VFX3"
const BUS_BROADCAST: StringName = &"Broadcast"
const BUS_AMBIENCE: StringName = &"Ambience"

const MANAGED_BUSES: Array[StringName] = [
	&"Music", &"VFX1", &"VFX2", &"VFX3", &"Broadcast", &"Ambience",
]

var _music_player: AudioStreamPlayer = null
var _music_crossfading: bool = false

var _ambience_player: AudioStreamPlayer = null

var _default_volumes: Dictionary = {
	&"Master": 1.0,
	&"Music": 0.6,
	&"VFX1": 0.8,
	&"VFX2": 0.8,
	&"VFX3": 0.7,
	&"Broadcast": 0.9,
	&"Ambience": 0.5,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_create_persistent_players()

## Ensures all required audio buses exist at runtime.
func _ensure_buses() -> void:
	for bus_name in MANAGED_BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)
			var vol: float = _default_volumes.get(bus_name, 1.0)
			AudioServer.set_bus_volume_db(idx, linear_to_db(vol))

func _create_persistent_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = BUS_MUSIC
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbiencePlayer"
	_ambience_player.bus = BUS_AMBIENCE
	_ambience_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambience_player)

func _on_music_finished() -> void:
	if _music_crossfading:
		return
	if _music_player.stream != null:
		_music_player.play()

func play_music(stream: AudioStream, fade_in: float = 1.0) -> void:
	if _music_player.playing:
		_music_crossfading = true
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -80.0, fade_in * 0.5)
		tween.tween_callback(func() -> void:
			_music_player.stream = stream
			_music_player.volume_db = -80.0
			_music_player.play()
			_music_crossfading = false
		)
		tween.tween_property(_music_player, "volume_db", linear_to_db(_default_volumes[BUS_MUSIC]), fade_in * 0.5)
	else:
		_music_player.stream = stream
		_music_player.volume_db = -80.0
		_music_player.play()
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", linear_to_db(_default_volumes[BUS_MUSIC]), fade_in)

func stop_music(fade_out: float = 1.0) -> void:
	if not _music_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -80.0, fade_out)
	tween.tween_callback(_music_player.stop)

func play_ambience(stream: AudioStream, fade_in: float = 2.0) -> void:
	_ambience_player.stream = stream
	_ambience_player.volume_db = -80.0
	_ambience_player.play()
	var tween := create_tween()
	tween.tween_property(_ambience_player, "volume_db", linear_to_db(_default_volumes[BUS_AMBIENCE]), fade_in)

func stop_ambience(fade_out: float = 2.0) -> void:
	if not _ambience_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_ambience_player, "volume_db", -80.0, fade_out)
	tween.tween_callback(_ambience_player.stop)

## Play a one-shot sound effect on a specific bus.
func play_sfx(stream: AudioStream, bus: StringName = BUS_VFX1, volume_db: float = 0.0) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player

func play_sfx_2d(stream: AudioStream, position: Vector2, bus: StringName = BUS_VFX1, volume_db: float = 0.0, parent: Node = null) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.global_position = position
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if parent and is_instance_valid(parent):
		parent.add_child(player)
	else:
		add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player

func set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear_volume, 0.0, 1.0)))

func get_bus_volume(bus_name: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return db_to_linear(AudioServer.get_bus_volume_db(idx))
	return 0.0

func set_bus_mute(bus_name: StringName, muted: bool) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)
