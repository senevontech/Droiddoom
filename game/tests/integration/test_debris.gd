extends GutTest
## D-031: a dead droid's parts become rigid bodies that fly along the killing
## hit, land on the floor and sink away; the pool is capped and recycles.

var _root: Node3D
var _debris: DebrisSystem


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_debris = DebrisSystem.new()
	_root.add_child(_debris)
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 0.5, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(shape)
	_root.add_child(floor_body)


func test_parts_fly_along_the_hit_and_land() -> void:
	var visuals: Node3D = _droid(3, Vector3.ZERO)
	await wait_physics_frames(2)
	var spawned: int = _debris.shatter(visuals, Vector3(6.0, 0.0, 0.0), Vector3.ZERO, 5.0)
	assert_eq(spawned, 3)
	assert_false(visuals.visible, "the intact model is hidden")
	assert_eq(_debris.get_active_count(), 3)
	await wait_physics_frames(90)
	var mean_x: float = 0.0
	for body: RigidBody3D in _debris.get_active_bodies():
		mean_x += body.global_position.x / 3.0
		assert_gt(body.global_position.y, -0.1, "rests on the floor, not through it")
		assert_lt(body.global_position.y, 1.0, "fell down")
	assert_gt(mean_x, 0.8, "thrown along the impulse")


func test_parts_sink_away_and_return_to_the_pool() -> void:
	var capacity: int = _debris.get_capacity()
	var visuals: Node3D = _droid(2, Vector3.ZERO)
	await wait_physics_frames(1)
	_debris.shatter(visuals, Vector3.ZERO, Vector3.ZERO, 0.3)
	await wait_seconds(0.5)
	assert_eq(_debris.get_active_count(), 0)
	assert_eq(_debris.get_capacity(), capacity, "bodies are reused, never freed")


func test_full_pool_recycles_the_oldest_parts() -> void:
	var capacity: int = _debris.get_capacity()
	await wait_physics_frames(1)
	var shattered: int = 0
	while shattered <= capacity:
		shattered += _debris.shatter(
			_droid(4, Vector3(shattered, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO, 30.0
		)
	assert_eq(_debris.get_active_count(), capacity)


## A stand-in droid: `parts` box meshes under one Visuals node.
func _droid(parts: int, at: Vector3) -> Node3D:
	var visuals: Node3D = Node3D.new()
	visuals.position = at
	_root.add_child(visuals)
	for i in parts:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.4, 0.3, 0.4)
		mesh.mesh = box
		mesh.position = Vector3(0.0, 0.4 + i * 0.35, 0.0)
		visuals.add_child(mesh)
	return visuals
