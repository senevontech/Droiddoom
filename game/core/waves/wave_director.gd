class_name WaveDirector
extends Node
## Runs the waves of a WaveSet (P1-10, GDD §7.3, TDD §3.4). Each wave spends
## its point budget on random enemies from its pool, then delivers them in
## bursts at spawn points away from the player, never exceeding the live-enemy
## cap of the quality preset (spawns wait until droids die). A wave is cleared
## when everything it spawned is dead; after a short break the next starts.
## Past the last authored wave it keeps scaling up (endless).
##
## The owner calls `set_spawn_points()` and `start()`. The director only
## reads the player's position (to spawn away from it).

signal wave_started(number: int)
signal wave_cleared(number: int)

enum Phase { IDLE, BREAK, ACTIVE, STOPPED }

## Spacing of a burst's droids around their spawn point (m).
const BURST_SPREAD: float = 1.6
## Used when no quality preset is loaded.
const DEFAULT_CAP: int = 40

@export var wave_set: WaveSet
## Where spawned droids are added.
@export var spawn_parent: Node3D

## Live cap override (-1 = the quality preset's `max_live_enemies`). For tests.
var max_live_override: int = -1
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _phase: Phase = Phase.IDLE
var _wave: int = 0
var _timer: float = 0.0
var _queue: Array[PackedScene] = []
var _alive: Dictionary = {}
var _spawn_points: Array[Node3D] = []
var _current: WaveData


## Spawn points (Marker3Ds of the sector).
func set_spawn_points(points: Array[Node3D]) -> void:
	_spawn_points = points


## Starts wave 1 after `wave_set.first_delay`.
func start() -> void:
	_wave = 0
	_phase = Phase.BREAK
	_timer = wave_set.first_delay


## Stops spawning for good (the player died). Droids already out keep going.
func stop() -> void:
	_phase = Phase.STOPPED
	_queue.clear()


## Current wave number (1-based, 0 before the first).
func get_wave_number() -> int:
	return _wave


## Droids of this wave still to spawn or still alive.
func get_remaining() -> int:
	return _queue.size() + _alive.size()


## Seconds until the next wave starts (0 when not in a break).
func get_break_left() -> float:
	return maxf(_timer, 0.0) if _phase == Phase.BREAK else 0.0


func get_phase() -> Phase:
	return _phase


## Budget of wave `number` (1-based), scaled up past the last authored wave.
func get_budget(number: int) -> int:
	var count: int = wave_set.waves.size()
	if number <= count:
		return wave_set.waves[number - 1].budget
	var extra: int = number - count
	return roundi(wave_set.waves[count - 1].budget * pow(wave_set.endless_growth, extra))


## Spends `budget` on random affordable picks from `pool` (weighted).
## Pure function: unit-tested.
static func build_roster(
	pool: Array[EnemyEntry], budget: int, random: RandomNumberGenerator
) -> Array[PackedScene]:
	var roster: Array[PackedScene] = []
	var left: int = budget
	while left > 0:
		var total: float = 0.0
		for entry: EnemyEntry in pool:
			if entry.cost <= left:
				total += entry.weight
		if total <= 0.0:
			break
		var roll: float = random.randf() * total
		for entry: EnemyEntry in pool:
			if entry.cost > left:
				continue
			roll -= entry.weight
			if roll <= 0.0:
				roster.append(entry.scene)
				left -= entry.cost
				break
	return roster


func _physics_process(delta: float) -> void:
	match _phase:
		Phase.BREAK:
			_timer -= delta
			if _timer <= 0.0:
				_start_wave(_wave + 1)
		Phase.ACTIVE:
			_timer -= delta
			if _timer <= 0.0 and not _queue.is_empty():
				if _spawn_burst() > 0:
					_timer = _current.burst_interval
			if _queue.is_empty() and _alive.is_empty():
				_phase = Phase.BREAK
				_timer = wave_set.break_time
				wave_cleared.emit(_wave)
				EventBus.wave_cleared.emit(_wave)


func _start_wave(number: int) -> void:
	_wave = number
	_current = wave_set.waves[mini(number, wave_set.waves.size()) - 1]
	_queue = build_roster(_current.pool, get_budget(number), rng)
	_phase = Phase.ACTIVE
	_timer = 0.0
	wave_started.emit(number)
	EventBus.wave_started.emit(number)


## Spawns up to one burst at one spawn point. Returns how many spawned.
func _spawn_burst() -> int:
	var room: int = _cap() - _alive.size()
	var count: int = mini(mini(_current.burst_size, room), _queue.size())
	if count <= 0 or _spawn_points.is_empty():
		return 0
	var at: Vector3 = _pick_spawn_point()
	var spread: float = BURST_SPREAD if count > 1 else 0.0
	for i in count:
		var angle: float = TAU * i / count + rng.randf() * 0.5
		_spawn(_queue.pop_front(), at + Vector3(cos(angle), 0.0, sin(angle)) * spread)
	return count


func _spawn(scene: PackedScene, at: Vector3) -> void:
	var droid: BaseEnemy = scene.instantiate()
	droid.start_alerted = true
	droid.position = at
	var id: int = droid.get_instance_id()
	_alive[id] = true
	droid.defeated.connect(func(_info: DamageInfo) -> void: _alive.erase(id))
	droid.tree_exited.connect(func() -> void: _alive.erase(id))
	spawn_parent.add_child(droid)


## A random spawn point at least `min_spawn_distance` from the player
## (the farthest one if none qualifies).
func _pick_spawn_point() -> Vector3:
	var player: Node3D = get_tree().get_first_node_in_group(Hollow.PLAYER_GROUP) as Node3D
	if player == null:
		return _spawn_points[rng.randi() % _spawn_points.size()].global_position
	var far: Array[Node3D] = []
	var farthest: Node3D = _spawn_points[0]
	var best: float = -1.0
	for point: Node3D in _spawn_points:
		var d: float = point.global_position.distance_to(player.global_position)
		if d >= wave_set.min_spawn_distance:
			far.append(point)
		if d > best:
			best = d
			farthest = point
	if far.is_empty():
		return farthest.global_position
	return far[rng.randi() % far.size()].global_position


func _cap() -> int:
	if max_live_override >= 0:
		return max_live_override
	return QualityManager.settings.max_live_enemies if QualityManager.settings else DEFAULT_CAP
