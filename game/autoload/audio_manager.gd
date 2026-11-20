extends Node
## Sound effects and volume buses (Master, Music, SFX, Voice, UI).
##
## P1-13: pooled SFX. Gameplay never calls this directly for combat sounds;
## it listens to EventBus (shots, hits, blasts, deaths, dash, Neural Sync,
## waves, reloads) and plays sounds by name.
## Sources, best first: real recordings in `assets/audio/sfx_real/`
## (`<name>.ogg|.wav`, plus optional takes `<name>_2` … `<name>_6`, one picked
## at random per play), else the synthesized fallback in `assets/audio/sfx/`
## (tools/gen_sfx.py). See tools/README_SFX.md.
## Cost: a fixed pool of POOL_3D positional + POOL_UI flat players, built once.
## Each sound plays at most MAX_VOICES_PER_SOUND at a time (the oldest is
## restarted), so a laser or a big wave can't flood the mixer.
## Music layers come with P2-14.

const SFX_DIR: String = "res://assets/audio/sfx/%s.wav"
const REAL_DIR: String = "res://assets/audio/sfx_real/"
const REAL_EXTENSIONS: Array[String] = ["ogg", "wav"]
## Takes per sound looked for in REAL_DIR: name, name_2 … name_MAX_TAKES.
const MAX_TAKES: int = 6
const SOUNDS: Array[StringName] = [
	&"shot_rifle",
	&"shot_scatter",
	&"shot_laser",
	&"shot_rail",
	&"shot_rocket",
	&"shot_grenade",
	&"shot_bolt",
	&"droid_death",
	&"explosion",
	&"impact_metal",
	&"impact_world",
	&"dash",
	&"neural_sync",
	&"hollow_hit",
	&"wave_start",
	&"reload",
]
const POOL_3D: int = 14
const POOL_UI: int = 4
const MAX_VOICES_PER_SOUND: int = 3
## Same sound again within this many seconds is skipped (impacts, laser ticks).
const MIN_REPEAT: float = 0.035
## Random pitch spread so repeated shots don't sound identical (±).
const PITCH_JITTER: float = 0.06
## Mixer speed while Neural Sync slows the world (sounds drop in pitch).
const SYNC_PLAYBACK_SPEED: float = 0.6
const SFX_BUS: StringName = &"SFX"
const UI_BUS: StringName = &"UI"

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Sound id → Array of AudioStream takes (≥ 1).
var _streams: Dictionary = {}
## Sound ids that use real recordings (tests, debug).
var _real: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_ui: Array[AudioStreamPlayer] = []
## Sound id → msec it last started (repeat limit).
var _last_played: Dictionary = {}
var _next_3d: int = 0
var _next_ui: int = 0
## Sounds requested so far (tests, debug).
var _played_count: int = 0


func _ready() -> void:
	for id: StringName in SOUNDS:
		var takes: Array[AudioStream] = _load_real_takes(id)
		if not takes.is_empty():
			_real[id] = true
		else:
			var path: String = SFX_DIR % id
			var fallback: AudioStream = load(path) if ResourceLoader.exists(path) else null
			if fallback != null:
				takes.append(fallback)
		if not takes.is_empty():
			_streams[id] = takes
	for i in POOL_3D:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.bus = _bus_or_master(SFX_BUS)
		player.unit_size = 10.0
		player.max_distance = 90.0
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)
		_players_3d.append(player)
	for i in POOL_UI:
		var flat: AudioStreamPlayer = AudioStreamPlayer.new()
		flat.bus = _bus_or_master(UI_BUS)
		add_child(flat)
		_players_ui.append(flat)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.explosion_happened.connect(_on_explosion)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_damaged.connect(
		func(_amount: float, _type: int) -> void: play_ui(&"hollow_hit", -3.0)
	)
	EventBus.player_dashed.connect(func(_dir: Vector3) -> void: play_ui(&"dash", -4.0))
	EventBus.neural_sync_triggered.connect(_on_neural_sync)
	EventBus.neural_sync_ended.connect(func() -> void: AudioServer.playback_speed_scale = 1.0)
	EventBus.wave_started.connect(func(_n: int) -> void: play_ui(&"wave_start", -6.0))
	EventBus.weapon_reload_started.connect(_on_reload)


func _exit_tree() -> void:
	# Sounds still playing at quit leak their playbacks; stop them first.
	for player: AudioStreamPlayer3D in _players_3d:
		player.stop()
		player.stream = null
	for flat: AudioStreamPlayer in _players_ui:
		flat.stop()
		flat.stream = null
	AudioServer.playback_speed_scale = 1.0


## Sets a bus volume from a linear 0..1 value. Does nothing if the bus doesn't exist yet.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


## True if a sound with this name is loaded.
func has_sound(id: StringName) -> bool:
	return _streams.has(id)


## True if `id` plays real recordings (sfx_real/) instead of the fallback.
func is_real(id: StringName) -> bool:
	return _real.has(id)


## Number of takes loaded for `id` (tests, debug).
func get_take_count(id: StringName) -> int:
	return (_streams.get(id, []) as Array).size()


## How many sounds were started so far (tests, debug).
func get_played_count() -> int:
	return _played_count


## Plays `id` at a world position. Returns false if skipped (unknown sound,
## repeat limit).
func play_at(id: StringName, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if not _admit(id):
		return false
	var player: AudioStreamPlayer3D = _pick_3d(id)
	player.stream = _take(id)
	player.set_meta(&"sfx_id", id)
	player.global_position = at
	player.volume_db = volume_db
	player.pitch_scale = pitch * rng.randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.play()
	return true


## Plays `id` without position (UI, the player's own body).
func play_ui(id: StringName, volume_db: float = 0.0) -> bool:
	if not _admit(id):
		return false
	var player: AudioStreamPlayer = _players_ui[_next_ui]
	_next_ui = (_next_ui + 1) % _players_ui.size()
	player.stream = _take(id)
	player.volume_db = volume_db
	player.play()
	return true


func _admit(id: StringName) -> bool:
	if not _streams.has(id):
		return false
	var now: int = Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < roundi(MIN_REPEAT * 1000.0):
		return false
	_last_played[id] = now
	_played_count += 1
	return true


## A free 3D player, or the oldest voice of the same sound if it already has
## MAX_VOICES_PER_SOUND, or the next one round-robin.
func _pick_3d(id: StringName) -> AudioStreamPlayer3D:
	var same: int = 0
	for player: AudioStreamPlayer3D in _players_3d:
		if player.playing and player.get_meta(&"sfx_id", &"") == id:
			same += 1
	for i in _players_3d.size():
		var index: int = (_next_3d + i) % _players_3d.size()
		var player: AudioStreamPlayer3D = _players_3d[index]
		var reusable: bool = (
			not player.playing
			or (same >= MAX_VOICES_PER_SOUND and player.get_meta(&"sfx_id", &"") == id)
		)
		if reusable:
			_next_3d = (index + 1) % _players_3d.size()
			return player
	var oldest: AudioStreamPlayer3D = _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	return oldest


func _on_weapon_fired(weapon: Node3D, muzzle: Vector3, _direction: Vector3) -> void:
	var gun: Weapon = weapon as Weapon
	if gun == null or gun.data == null or gun.data.fire_sfx == &"":
		return
	var player_side: bool = (gun.target_mask & PhysicsLayers.ENEMIES) != 0
	play_at(gun.data.fire_sfx, muzzle, 0.0 if player_side else -3.0)


func _on_hit_landed(position: Vector3, _normal: Vector3, _type: int, on_target: bool) -> void:
	if on_target:
		play_at(&"impact_metal", position, -6.0)
	else:
		play_at(&"impact_world", position, -12.0)


func _on_explosion(position: Vector3, radius: float, _type: int) -> void:
	var size: float = clampf(radius / 3.5, 0.5, 1.4)
	play_at(&"explosion", position, linear_to_db(size), 1.15 - size * 0.15)


func _on_enemy_died(enemy: Node, _killer: Node) -> void:
	var body: Node3D = enemy as Node3D
	if body != null and body.is_inside_tree():
		play_at(&"droid_death", body.global_position, -4.0)


func _on_neural_sync(_threats: int) -> void:
	play_ui(&"neural_sync", -2.0)
	AudioServer.playback_speed_scale = SYNC_PLAYBACK_SPEED


func _on_reload(weapon: Node3D) -> void:
	play_at(&"reload", weapon.global_position, -8.0)


static func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"


## A random take of `id`.
func _take(id: StringName) -> AudioStream:
	var takes: Array = _streams[id]
	return takes[rng.randi() % takes.size()] if takes.size() > 1 else takes[0]


## Real recordings for `id`: `<id>` then `<id>_2` … in REAL_DIR (ogg or wav).
## Files that fail to load (e.g. Git LFS pointers in CI) are skipped.
static func _load_real_takes(id: StringName) -> Array[AudioStream]:
	var takes: Array[AudioStream] = []
	for n in range(1, MAX_TAKES + 1):
		var base: String = String(id) if n == 1 else "%s_%d" % [id, n]
		for ext: String in REAL_EXTENSIONS:
			var path: String = "%s%s.%s" % [REAL_DIR, base, ext]
			if ResourceLoader.exists(path):
				var stream: AudioStream = load(path) as AudioStream
				if stream != null:
					takes.append(stream)
					break
	return takes
