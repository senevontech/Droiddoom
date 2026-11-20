extends GutTest
## P1-09: Swarmer, Gunner and Kamikaze in real physics and navigation.
## Swarmers spread out (P1-18), Gunners keep their distance and shoot slow
## bolts that really travel, Kamikazes arm and explode, and a Kamikaze shot
## early takes its neighbours with it.

const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")
const GUNNER: PackedScene = preload("res://actors/enemies/gunner/gunner.tscn")
const KAMIKAZE: PackedScene = preload("res://actors/enemies/kamikaze/kamikaze.tscn")

var _root: Node3D
var _projectiles: ProjectileSystem
var _target: Node3D
var _target_health: HealthComponent


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_root.add_child(EnemyCoordinator.new())
	_projectiles = ProjectileSystem.new()
	_root.add_child(_projectiles)
	_root.add_child(DebrisSystem.new())
	_root.add_child(CombatFX.new())
	_box(Vector3(0.0, -0.25, 0.0), Vector3(60.0, 0.5, 60.0))


func test_swarmers_spread_out_instead_of_stacking() -> void:
	_bake()
	_make_target(Vector3(40.0, 0.0, 0.0))  # far away: they just stand around
	var pack: Array[BaseEnemy] = []
	for i in 4:
		pack.append(_spawn(SWARMER, Vector3(0.05 * i, 0.0, 0.0), false))
	await wait_physics_frames(90)
	var closest: float = INF
	for a in pack.size():
		for b in range(a + 1, pack.size()):
			closest = minf(closest, _flat_distance(pack[a], pack[b]))
	assert_gt(closest, 0.7, "separation pushed the pack apart")


func test_gunner_keeps_its_distance_and_shoots_bolts() -> void:
	_bake()
	_make_target(Vector3(0.0, 0.0, -14.0))
	var gunner: GunnerEnemy = _spawn(GUNNER, Vector3.ZERO, true)
	watch_signals(EventBus)
	await wait_physics_frames(30)
	assert_eq(gunner.get_state(), BaseEnemy.STATE_ATTACK, "in range with line of sight")
	await wait_physics_frames(30)
	assert_gt(_projectiles.get_active_count(), 0, "bolts are in flight, not instant")
	assert_eq(_target_health.get_health(), 100.0, "they haven't arrived yet")
	await wait_physics_frames(120)
	assert_lt(_target_health.get_health(), 100.0, "bolts hit a target that stands still")
	assert_gt(_flat_distance(gunner, _target), 8.0, "stays at range instead of rushing in")


func test_gunner_backs_away_from_a_close_target() -> void:
	_bake()
	_make_target(Vector3(0.0, 0.0, -2.5))
	var gunner: GunnerEnemy = _spawn(GUNNER, Vector3.ZERO, true)
	await wait_physics_frames(60)
	assert_gt(_flat_distance(gunner, _target), 3.5, "backpedalled")


func test_kamikaze_arms_then_explodes_on_the_target() -> void:
	_bake()
	_make_target(Vector3(0.0, 0.0, -10.0))
	var kamikaze: KamikazeEnemy = _spawn(KAMIKAZE, Vector3.ZERO, true)
	var ring: MeshInstance3D = kamikaze.get_node("WarningRing")
	watch_signals(kamikaze)
	var armed: bool = false
	for i in 120:
		await wait_physics_frames(1)
		if not is_instance_valid(kamikaze) or kamikaze.health.is_dead():
			break
		armed = armed or ring.visible
	assert_true(armed, "showed the blast radius on the ground before going off")
	await wait_physics_frames(5)
	assert_lt(_target_health.get_health(), 100.0, "caught in the blast")


func test_shot_kamikaze_takes_its_neighbours_with_it() -> void:
	_make_target(Vector3(40.0, 0.0, 0.0))
	var kamikaze: KamikazeEnemy = _spawn(KAMIKAZE, Vector3.ZERO, false)
	var neighbour: BaseEnemy = _spawn(SWARMER, Vector3(1.5, 0.0, 0.0), false)
	var bystander: BaseEnemy = _spawn(SWARMER, Vector3(-9.0, 0.0, 0.0), false)
	await wait_physics_frames(3)
	kamikaze.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.KINETIC))
	await wait_physics_frames(3)
	assert_true(neighbour.health.is_dead(), "the swarmer next to it was destroyed")
	assert_false(bystander.health.is_dead(), "out of range")
	assert_eq(_target_health.get_health(), 100.0, "the far-away player is safe")


func _spawn(scene: PackedScene, pos: Vector3, alerted: bool) -> BaseEnemy:
	var droid: BaseEnemy = scene.instantiate()
	droid.start_alerted = alerted
	droid.position = pos
	_root.add_child(droid)
	return droid


## Stand-in for HOLLOW: in the player group, with Health and a PLAYER hurtbox.
func _make_target(pos: Vector3) -> void:
	_target = Node3D.new()
	_target.position = pos
	_root.add_child(_target)
	_target.add_to_group(BaseEnemy.TARGET_GROUP)
	_target_health = HealthComponent.new()
	_target_health.name = "Health"
	_target.add_child(_target_health)
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.collision_layer = PhysicsLayers.PLAYER
	hurtbox.collision_mask = 0
	hurtbox.health = _target_health
	hurtbox.position = Vector3(0.0, 1.0, 0.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.5
	shape.shape = capsule
	hurtbox.add_child(shape)
	_target.add_child(hurtbox)


func _bake() -> void:
	NavBaker.add_region(_root, _root)


func _flat_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x, a.global_position.z).distance_to(
		Vector2(b.global_position.x, b.global_position.z)
	)


func _box(center: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	body.position = center
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_root.add_child(body)
