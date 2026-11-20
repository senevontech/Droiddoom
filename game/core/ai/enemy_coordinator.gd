class_name EnemyCoordinator
extends Node
## Shared helper for all enemies in a level (P1-08):
## - **Time-sliced path queries.** Enemies ask for a path with `request_path()`.
##   Each physics frame only `path_queries_per_frame` (from the quality preset)
##   queries run, oldest request first, so a whole wave asking at once can't
##   cause a frame spike. A requester is queued at most once.
## - **Live enemy count** for spawners and the Wave Director (cap per preset).
## - **Hearing (P1-17):** shots from weapons that target AXIOM and every
##   explosion alert idle droids within the noise radius × their `hearing`.
##
## One per level. `find_or_create()` adds one automatically if the level
## doesn't have one, so enemies also work in tests and dev scenes.
## Requesters are any Object with a `run_path_query() -> void` method.

const GROUP: StringName = &"enemy_coordinator"
## Used when no quality preset is loaded.
const DEFAULT_BUDGET: int = 4
## Explosions are heard this many blast radii away.
const EXPLOSION_NOISE_PER_RADIUS: float = 8.0

## Override for the per-frame budget (-1 = use the quality preset).
var budget_override: int = -1

## Instance ids of waiting requesters (ids, not objects, so freed ones are safe).
var _queue: Array[int] = []
var _queued: Dictionary = {}
var _live: Dictionary = {}
var _queries_last_frame: int = 0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.explosion_happened.connect(_on_explosion)


func _physics_process(_delta: float) -> void:
	_queries_last_frame = process_queue(get_budget())


## Returns the level's coordinator, creating one under the current scene if needed.
static func find_or_create(from: Node) -> EnemyCoordinator:
	var tree: SceneTree = from.get_tree()
	var found: EnemyCoordinator = tree.get_first_node_in_group(GROUP) as EnemyCoordinator
	if found != null:
		return found
	var created: EnemyCoordinator = EnemyCoordinator.new()
	created.name = "EnemyCoordinator"
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child.call_deferred(created)
	# Join the group now so other enemies spawned this frame find the same one.
	created.add_to_group(GROUP)
	return created


## Path queries allowed per physics frame.
func get_budget() -> int:
	if budget_override >= 0:
		return budget_override
	var preset: QualityPreset = QualityManager.settings
	return preset.path_queries_per_frame if preset != null else DEFAULT_BUDGET


## Queues a path query for `requester`. Ignored if it's already waiting.
func request_path(requester: Object) -> void:
	var key: int = requester.get_instance_id()
	if _queued.has(key):
		return
	_queued[key] = true
	_queue.append(key)


## Runs up to `budget` queued queries (skipping freed requesters).
## Returns how many ran. Called every physics frame; public for tests.
func process_queue(budget: int) -> int:
	var ran: int = 0
	while ran < budget and not _queue.is_empty():
		var key: int = _queue.pop_front()
		_queued.erase(key)
		var requester: Object = instance_from_id(key)
		if requester == null:
			continue
		requester.run_path_query()
		ran += 1
	return ran


## Number of requests waiting.
func get_pending_count() -> int:
	return _queue.size()


## Path queries that ran in the last physics frame (debug overlay).
func get_queries_last_frame() -> int:
	return _queries_last_frame


## Enemies call this when they spawn.
func register_enemy(enemy: Node) -> void:
	_live[enemy.get_instance_id()] = enemy


## Enemies call this when they die or leave the tree.
func unregister_enemy(enemy: Node) -> void:
	_live.erase(enemy.get_instance_id())


## Living enemies in the level.
func get_live_count() -> int:
	return _live.size()


## The living enemies themselves (aim assist, debug).
func get_live_enemies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for enemy: Node in _live.values():
		if is_instance_valid(enemy) and enemy is Node3D:
			out.append(enemy as Node3D)
	return out


## Calls `alert()` on every living enemy within `radius` of `point` except
## `except` (AXIOM's network, D-029). Runs only when a droid notices the
## player, not per frame. Returns how many were alerted.
func alert_nearby(point: Vector3, radius: float, except: Node = null) -> int:
	var count: int = 0
	var radius_sq: float = radius * radius
	for enemy: Node in _live.values():
		if enemy == except or not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		if (enemy as Node3D).global_position.distance_squared_to(point) <= radius_sq:
			if enemy.has_method(&"alert"):
				enemy.alert()
				count += 1
	return count


## Push that keeps `enemy` apart from live droids closer than `radius`:
## sum of away-directions weighted by overlap (0..1 each), horizontal only.
## Called at the AI think rate, not per frame.
func separation_for(enemy: Node3D, radius: float) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO
	var push: Vector3 = Vector3.ZERO
	var radius_sq: float = radius * radius
	var here: Vector3 = enemy.global_position
	for other: Node in _live.values():
		if other == enemy or not is_instance_valid(other):
			continue
		var away: Vector3 = here - (other as Node3D).global_position
		away.y = 0.0
		var d_sq: float = away.length_squared()
		if d_sq >= radius_sq:
			continue
		if d_sq < 0.0001:
			# Exactly on top of each other: split along a stable direction.
			away = (
				Vector3.RIGHT if enemy.get_instance_id() > other.get_instance_id() else Vector3.LEFT
			)
			push += away
			continue
		var d: float = sqrt(d_sq)
		push += away / d * (1.0 - d / radius)
	return push


## Alerts idle droids that can hear a noise of `radius` at `point` (each
## droid scales it by its `data.hearing`). Returns how many were alerted.
func hear_noise(point: Vector3, radius: float) -> int:
	if radius <= 0.0:
		return 0
	var count: int = 0
	for enemy: Node in _live.values():
		var body: BaseEnemy = enemy as BaseEnemy
		if body == null or not is_instance_valid(body) or body.data == null:
			continue
		var reach: float = radius * body.data.hearing
		if body.global_position.distance_squared_to(point) <= reach * reach:
			if body.get_state() == BaseEnemy.STATE_IDLE:
				body.alert()
				count += 1
	return count


func _on_weapon_fired(weapon: Node3D, muzzle: Vector3, _direction: Vector3) -> void:
	var w: Weapon = weapon as Weapon
	# Only shots aimed at AXIOM count (droids don't startle at their own fire).
	if w == null or w.data == null or (w.target_mask & PhysicsLayers.ENEMIES) == 0:
		return
	hear_noise(muzzle, w.data.noise_radius)


func _on_explosion(position: Vector3, radius: float, _type: int) -> void:
	hear_noise(position, radius * EXPLOSION_NOISE_PER_RADIUS)
