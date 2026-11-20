class_name DebrisSystem
extends Node3D
## Breaks dead droids into their rigid parts (D-031). Our robots are built
## from separate meshes (GDD §16 solo rules), so each mesh becomes a physics
## body flung by the killing hit: a rifle tips a droid over and scatters a few
## parts, a rocket throws them across the street. Wrecks lie on the ground for
## a while, then sink away.
##
## Cost: a fixed pool of `max_debris_bodies` RigidBody3Ds (quality preset)
## built at level load. Pooled bodies sit in PROCESS_MODE_DISABLED (removed
## from physics). Bodies collide with the world only (not each other, not
## actors, not shots) and fall asleep when still. When the pool is empty the
## oldest piece is recycled.

const GROUP: StringName = &"debris_system"
## Used when no quality preset is loaded.
const DEFAULT_POOL: int = 48
## Parts taken from one droid at most (smallest parts are skipped first).
const MAX_PARTS_PER_SHATTER: int = 10
const SINK_TIME: float = 0.6
## Mass per cubic metre of part (hollow metal shell, not solid steel).
const DENSITY: float = 300.0
const SCATTER: float = 1.6
const POP_UP: float = 2.2
const SPIN: float = 9.0
## Wrecks this heavy (kg) or more keep smoking for a while.
const SMOKE_MASS: float = 10.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _free: Array[RigidBody3D] = []
## Active pieces, oldest first: [body, seconds left].
var _active: Array[Array] = []
var _shapes: Dictionary = {}
var _physics_material: PhysicsMaterial


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = 0.9
	_physics_material.bounce = 0.15
	var size: int = (
		QualityManager.settings.max_debris_bodies if QualityManager.settings else DEFAULT_POOL
	)
	for i in maxi(0, size):
		var body: RigidBody3D = _new_body()
		add_child(body)
		_park(body)
		_free.append(body)
	EventBus.explosion_happened.connect(_on_explosion)


## Returns the level's debris system, creating one under the current scene.
static func find_or_create(from: Node) -> DebrisSystem:
	var tree: SceneTree = from.get_tree()
	var found: DebrisSystem = tree.get_first_node_in_group(GROUP) as DebrisSystem
	if found != null:
		return found
	var created: DebrisSystem = DebrisSystem.new()
	created.name = "DebrisSystem"
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(created)
	return created


## Turns every visible MeshInstance3D under `visuals` into a flying part and
## hides `visuals`. `impulse` = the killing hit's shove (m/s), `inherit` =
## the droid's own velocity, `lifetime` = seconds before parts sink away.
## Returns the number of parts spawned (0 = the pool is disabled).
func shatter(visuals: Node3D, impulse: Vector3, inherit: Vector3, lifetime: float) -> int:
	if _free.is_empty() and _active.is_empty():
		return 0
	var parts: Array[MeshInstance3D] = []
	_collect(visuals, parts)
	parts.sort_custom(
		func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return _volume(a) > _volume(b)
	)
	parts.resize(mini(parts.size(), MAX_PARTS_PER_SHATTER))
	var centre: Vector3 = visuals.global_position + Vector3.UP * 0.6
	var heaviest: RigidBody3D = null
	for part: MeshInstance3D in parts:
		var body: RigidBody3D = _acquire()
		_dress(body, part)
		var away: Vector3 = part.global_position - centre
		away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
		# Light parts fly further than the heavy hull.
		var lightness: float = clampf(8.0 / body.mass, 0.35, 1.6)
		body.linear_velocity = (
			inherit
			+ impulse * rng.randf_range(0.7, 1.2) * lightness
			+ away * SCATTER * rng.randf_range(0.5, 1.2)
			+ Vector3.UP * POP_UP * rng.randf_range(0.4, 1.0) * lightness
		)
		body.angular_velocity = (
			Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			* SPIN
			* lightness
		)
		_active.append([body, lifetime])
		if heaviest == null or body.mass > heaviest.mass:
			heaviest = body
	visuals.visible = false
	if heaviest != null and heaviest.mass >= SMOKE_MASS:
		EventBus.smoke_source_added.emit(heaviest, minf(lifetime * 0.6, 6.0))
	return parts.size()


## Pieces lying around now (debug/tests).
func get_active_count() -> int:
	return _active.size()


## Pool size (debug/tests).
func get_capacity() -> int:
	return _free.size() + _active.size()


## Active bodies (tests).
func get_active_bodies() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for entry: Array in _active:
		out.append(entry[0])
	return out


func _process(delta: float) -> void:
	var i: int = 0
	while i < _active.size():
		var entry: Array = _active[i]
		var left: float = float(entry[1]) - delta
		entry[1] = left
		var body: RigidBody3D = entry[0]
		if left <= 0.0:
			_active.remove_at(i)
			_park(body)
			_free.append(body)
			continue
		if left < SINK_TIME:
			var mesh: MeshInstance3D = body.get_child(1) as MeshInstance3D
			mesh.scale = Vector3.ONE * maxf(left / SINK_TIME, 0.01)
		i += 1


func _on_explosion(position: Vector3, radius: float, _type: int) -> void:
	# Blasts also kick wrecks that are already lying around.
	for entry: Array in _active:
		var body: RigidBody3D = entry[0]
		var away: Vector3 = body.global_position - position
		var d: float = away.length()
		if d > radius * 1.5:
			continue
		var push: float = (1.0 - d / (radius * 1.5)) * 8.0
		var dir: Vector3 = (away / d if d > 0.01 else Vector3.UP) + Vector3.UP * 0.5
		body.sleeping = false
		body.linear_velocity += dir.normalized() * push


func _acquire() -> RigidBody3D:
	var body: RigidBody3D
	if _free.is_empty():
		body = _active.pop_front()[0]
	else:
		body = _free.pop_back()
	body.process_mode = Node.PROCESS_MODE_INHERIT
	body.visible = true
	body.sleeping = false
	return body


func _dress(body: RigidBody3D, part: MeshInstance3D) -> void:
	var aabb: AABB = part.mesh.get_aabb()
	var scale: Vector3 = part.global_basis.get_scale()
	var size: Vector3 = (aabb.size * scale).max(Vector3.ONE * 0.04)
	var shape_node: CollisionShape3D = body.get_child(0) as CollisionShape3D
	shape_node.shape = _box_shape(size)
	shape_node.position = aabb.get_center() * scale
	var mesh_node: MeshInstance3D = body.get_child(1) as MeshInstance3D
	mesh_node.mesh = part.mesh
	mesh_node.scale = Vector3.ONE
	mesh_node.material_override = (
		part.material_override
		if part.material_override != null
		else part.get_surface_override_material(0)
	)
	mesh_node.transform = Transform3D(Basis().scaled(scale), Vector3.ZERO)
	body.global_transform = Transform3D(part.global_basis.orthonormalized(), part.global_position)
	body.mass = clampf(size.x * size.y * size.z * DENSITY, 1.0, 120.0)


func _park(body: RigidBody3D) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.visible = false
	body.process_mode = Node.PROCESS_MODE_DISABLED


func _new_body() -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = PhysicsLayers.WORLD
	body.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	body.physics_material_override = _physics_material
	body.can_sleep = true
	body.linear_damp = 0.1
	body.angular_damp = 0.8
	var shape: CollisionShape3D = CollisionShape3D.new()
	body.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh)
	return body


func _box_shape(size: Vector3) -> BoxShape3D:
	var key: Vector3i = Vector3i((size * 100.0).round())
	var shape: BoxShape3D = _shapes.get(key)
	if shape == null:
		shape = BoxShape3D.new()
		shape.size = size
		_shapes[key] = shape
	return shape


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	for child: Node in node.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null and mesh.visible and mesh.mesh != null:
			out.append(mesh)
		if child is Node3D and (child as Node3D).visible:
			_collect(child, out)


static func _volume(part: MeshInstance3D) -> float:
	var size: Vector3 = part.mesh.get_aabb().size * part.global_basis.get_scale()
	return size.x * size.y * size.z
