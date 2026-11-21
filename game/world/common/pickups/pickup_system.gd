class_name PickupSystem
extends Node3D
## Droid drops (P1-32 gameplay): when a droid dies it may drop a REPAIR cell
## (restores hull) or heavy AMMO (rockets/grenades), by the chances in its
## EnemyData. Drops hover and spin, slide toward HOLLOW when it gets close,
## are collected on touch, and blink before vanishing. One per level
## (`find_or_create`). Cost: one mesh per drop (≤ max_active), a distance
## check per drop per frame; no physics.

const GROUP: StringName = &"pickup_system"
const REPAIR: StringName = &"repair"
const AMMO: StringName = &"ammo"
const TUNING: PickupTuning = preload("res://data/pickups/pickup_tuning_default.tres")
const HOVER: float = 0.7
const MAGNET_SPEED: float = 9.0

var tuning: PickupTuning = TUNING
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Active drops: {node, kind, age}.
var _drops: Array[Dictionary] = []
var _meshes: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	rng.randomize()
	_meshes[REPAIR] = _mesh(Color(0.35, 1.0, 0.6), Vector3(0.34, 0.34, 0.34))
	_meshes[AMMO] = _mesh(Color(1.0, 0.72, 0.28), Vector3(0.42, 0.26, 0.3))


## Returns the level's pickup system, creating one inside `from`'s level (the
## current scene when it contains `from`, else `from`'s parent) so it is freed
## with that level.
static func find_or_create(from: Node) -> PickupSystem:
	var tree: SceneTree = from.get_tree()
	var found: PickupSystem = tree.get_first_node_in_group(GROUP) as PickupSystem
	if found != null:
		return found
	var created: PickupSystem = PickupSystem.new()
	created.name = "PickupSystem"
	var scene: Node = tree.current_scene
	var parent: Node = scene if scene != null and scene.is_ancestor_of(from) else from.get_parent()
	if parent == null:
		parent = tree.root
	parent.add_child(created)
	return created


## Rolls `data`'s drop chances at `at` (called when a droid dies).
func roll_drop(data: EnemyData, at: Vector3) -> StringName:
	var roll: float = rng.randf()
	if roll < data.drop_repair_chance:
		spawn(REPAIR, at)
		return REPAIR
	if roll < data.drop_repair_chance + data.drop_ammo_chance:
		spawn(AMMO, at)
		return AMMO
	return &""


## Drops a pickup of `kind` at `at`.
func spawn(kind: StringName, at: Vector3) -> void:
	if not is_inside_tree():
		spawn.call_deferred(kind, at)
		return
	if _drops.size() >= tuning.max_active:
		_remove(0)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = _meshes[kind]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = Vector3(at.x, at.y + HOVER, at.z)
	_drops.append({"node": node, "kind": kind, "age": 0.0, "base_y": at.y + HOVER})


## Drops currently on the ground (tests, HUD).
func get_active_count() -> int:
	return _drops.size()


func _process(delta: float) -> void:
	var player: Hollow = get_tree().get_first_node_in_group(Hollow.PLAYER_GROUP) as Hollow
	var i: int = 0
	while i < _drops.size():
		var drop: Dictionary = _drops[i]
		var node: MeshInstance3D = drop["node"]
		drop["age"] = float(drop["age"]) + delta
		var age: float = drop["age"]
		if age >= tuning.lifetime:
			_remove(i)
			continue
		node.rotate_y(delta * 2.5)
		var pos: Vector3 = node.global_position
		pos.y = float(drop["base_y"]) + sin(age * 3.0) * 0.08
		var left: float = tuning.lifetime - age
		node.visible = left > 3.0 or fmod(age, 0.3) < 0.18
		if player != null and not player.health.is_dead():
			var to: Vector3 = player.global_position + Vector3.UP * 0.8 - pos
			var distance: float = to.length()
			if distance <= tuning.collect_radius:
				_collect(drop, player)
				_remove(i)
				continue
			if distance <= tuning.magnet_radius:
				pos += to / distance * minf(distance, MAGNET_SPEED * delta)
				drop["base_y"] = pos.y
		node.global_position = pos
		i += 1


func _collect(drop: Dictionary, player: Hollow) -> void:
	var kind: StringName = drop["kind"]
	var amount: int = 0
	if kind == REPAIR:
		var before: float = player.health.get_health()
		player.health.heal(player.health.max_health * tuning.repair_share)
		amount = roundi(player.health.get_health() - before)
	elif kind == AMMO:
		amount = player.add_heavy_ammo(tuning.ammo_magazines)
	EventBus.pickup_collected.emit(kind, amount, player.global_position)


func _remove(index: int) -> void:
	var node: Node = _drops[index]["node"]
	if is_instance_valid(node):
		node.queue_free()
	_drops.remove_at(index)


static func _mesh(color: Color, size: Vector3) -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = CombatFX.glow_material(color, 3.0)
	return mesh
