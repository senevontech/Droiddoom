extends GutTest
## P1-08: BaseEnemy with real physics and navigation: notices the target,
## paths around a wall, telegraphs and lands its melee attack, stuns, dies
## cleanly. Uses the placeholder test drone (no LFS art needed) and a simple
## stand-in target, so it runs in CI.

const DRONE: PackedScene = preload("res://actors/enemies/test_drone/test_drone.tscn")
const RIFLE: WeaponData = preload("res://data/weapons/weapon_pulse_rifle.tres")

var _root: Node3D
var _coord: EnemyCoordinator
var _target: Node3D
var _target_health: HealthComponent


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_coord = EnemyCoordinator.new()
	_root.add_child(_coord)
	_static_box(Vector3(0.0, -0.25, 0.0), Vector3(40.0, 0.5, 40.0))


func test_idle_enemy_sees_target_and_closes_in() -> void:
	_bake()
	_make_target(Vector3(8.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3(-8.0, 0.0, 0.0), false)
	var start_dist: float = 16.0
	await wait_physics_frames(90)
	assert_ne(drone.get_state(), BaseEnemy.STATE_IDLE, "noticed the target in sight range")
	assert_lt(drone.distance_to_target(), start_dist - 4.0, "moved toward the target")


func test_idle_enemy_ignores_target_out_of_sight_range() -> void:
	_bake()
	_make_target(Vector3(17.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3(-17.0, 0.0, 0.0), false)  # 34 m > 30 m sight
	await wait_physics_frames(60)
	assert_eq(drone.get_state(), BaseEnemy.STATE_IDLE)


func test_paths_around_a_wall() -> void:
	# Wall across the straight line between the drone and the target.
	_static_box(Vector3(0.0, 1.5, 0.0), Vector3(0.6, 3.0, 12.0))
	_bake()
	_make_target(Vector3(6.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3(-6.0, 0.0, 0.0), true)
	await wait_physics_frames(300)
	assert_gt(drone.global_position.x, 1.0, "got past the wall (walking straight would stick)")


func test_melee_attack_is_telegraphed_then_damages_target() -> void:
	_bake()
	_make_target(Vector3(0.0, 0.0, -1.5))
	var drone: BaseEnemy = _spawn(Vector3.ZERO, true)
	watch_signals(drone)
	await wait_physics_frames(90)
	assert_signal_emitted(drone, "attack_telegraphed")
	assert_signal_emitted(drone, "attacked")
	assert_lt(_target_health.get_health(), 100.0, "the strike hit the target hurtbox")


func test_stun_freezes_then_resumes_chase() -> void:
	_bake()
	_make_target(Vector3(10.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3(-5.0, 0.0, 0.0), true)
	await wait_physics_frames(10)
	drone.stun(0.5)
	assert_eq(drone.get_state(), BaseEnemy.STATE_STUNNED)
	var frozen_at: Vector3 = drone.global_position
	await wait_physics_frames(15)
	assert_lt(drone.global_position.distance_to(frozen_at), 0.6, "barely drifts while stunned")
	await wait_physics_frames(45)
	assert_eq(drone.get_state(), BaseEnemy.STATE_CHASE, "back to chasing after the stun")


func test_death_cleans_up_and_reports() -> void:
	_bake()
	_make_target(Vector3(10.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3.ZERO, false)
	await wait_physics_frames(2)
	assert_eq(_coord.get_live_count(), 1)
	watch_signals(EventBus)
	var killer: Node = autofree(Node.new())
	drone.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.KINETIC, killer))
	assert_eq(drone.get_state(), BaseEnemy.STATE_DEAD)
	assert_signal_emitted_with_parameters(EventBus, "enemy_died", [drone, killer])
	assert_eq(_coord.get_live_count(), 0)
	assert_eq(drone.collision_layer, 0, "the wreck doesn't block")
	assert_eq((drone.get_node("Hurtbox") as Area3D).collision_layer, 0, "can't be shot again")


func test_resistances_come_from_data() -> void:
	var data: EnemyData = (
		(load("res://data/enemies/enemy_test_drone.tres") as EnemyData).duplicate()
	)
	data.resistances = DamageResistances.new()
	data.resistances.kinetic = 0.5
	var drone: BaseEnemy = DRONE.instantiate()
	drone.data = data
	_root.add_child(drone)
	drone.health.apply_damage(DamageInfo.create(10.0, DamageInfo.Type.KINETIC))
	assert_eq(drone.health.get_health(), data.max_hp - 5.0)


func test_kill_shatters_the_droid_into_flying_parts() -> void:
	var debris: DebrisSystem = DebrisSystem.new()
	_root.add_child(debris)
	_make_target(Vector3(10.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3.ZERO, false)
	await wait_physics_frames(2)
	var info: DamageInfo = DamageInfo.create(1000.0, DamageInfo.Type.KINETIC)
	info.impulse = Vector3(8.0, 0.0, 0.0)
	drone.health.apply_damage(info)
	assert_gt(debris.get_active_count(), 4, "hull, head and legs become parts")
	assert_false(drone.visuals.visible, "the intact model is gone")
	await wait_physics_frames(30)
	var mean_x: float = 0.0
	for body: RigidBody3D in debris.get_active_bodies():
		mean_x += body.global_position.x / debris.get_active_count()
	assert_gt(mean_x, 0.5, "parts fly along the killing shot")


func test_heavy_damage_cripples_the_droid() -> void:
	_make_target(Vector3(10.0, 0.0, 0.0))
	var drone: BaseEnemy = _spawn(Vector3.ZERO, false)
	await wait_physics_frames(2)
	watch_signals(EventBus)
	var full_speed: float = drone.get_move_speed()
	drone.health.apply_damage(DamageInfo.create(drone.data.max_hp * 0.3, DamageInfo.Type.KINETIC))
	assert_false(drone.is_crippled(), "a scratch doesn't cripple")
	drone.health.apply_damage(DamageInfo.create(drone.data.max_hp * 0.4, DamageInfo.Type.KINETIC))
	assert_true(drone.is_crippled())
	assert_lt(drone.get_move_speed(), full_speed, "limps")
	assert_signal_emitted(EventBus, "smoke_source_added", "smokes")


func test_gunfire_wakes_idle_droids_in_earshot() -> void:
	_make_target(Vector3(0.0, 0.0, 38.0))  # beyond sight range of both drones
	var near: BaseEnemy = _spawn(Vector3(0.0, 0.0, 0.0), false)
	var far: BaseEnemy = _spawn(Vector3(0.0, 0.0, -18.0), false)
	var rifle: Weapon = Weapon.new()
	rifle.data = RIFLE
	_root.add_child(rifle)
	await wait_physics_frames(3)
	assert_eq(near.get_state(), BaseEnemy.STATE_IDLE, "precondition: nobody sees the target")
	# A shot 20 m from `near` (inside the rifle's noise radius), 38 m from `far`.
	EventBus.weapon_fired.emit(rifle, Vector3(0.0, 1.0, 20.0), Vector3.FORWARD)
	assert_eq(near.get_state(), BaseEnemy.STATE_CHASE, "heard the shot")
	assert_eq(far.get_state(), BaseEnemy.STATE_IDLE, "too far to hear it")


func test_droids_ignore_their_own_side_shooting() -> void:
	_make_target(Vector3(0.0, 0.0, 38.0))
	var drone: BaseEnemy = _spawn(Vector3.ZERO, false)
	var gun: Weapon = Weapon.new()
	gun.data = RIFLE
	gun.target_mask = PhysicsLayers.PLAYER | PhysicsLayers.ALLIES
	_root.add_child(gun)
	await wait_physics_frames(3)
	EventBus.weapon_fired.emit(gun, Vector3(0.0, 1.0, 3.0), Vector3.FORWARD)
	assert_eq(drone.get_state(), BaseEnemy.STATE_IDLE)


func test_optic_is_a_weak_spot_from_the_front() -> void:
	var drone: BaseEnemy = _spawn(Vector3.ZERO, false)
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = drone.get_world_3d().direct_space_state
	var eye: Dictionary = Hitscan.cast(
		space, Vector3(0.0, 1.17, -6.0), Vector3(0.0, 1.17, 6.0), PhysicsLayers.ENEMIES
	)
	assert_eq((eye["hurtbox"] as Node).name, &"OpticHurtbox")
	assert_true((eye["hurtbox"] as HurtboxComponent).is_weak_spot)
	var hull: Dictionary = Hitscan.cast(
		space, Vector3(0.0, 0.6, -6.0), Vector3(0.0, 0.6, 6.0), PhysicsLayers.ENEMIES
	)
	assert_eq((hull["hurtbox"] as Node).name, &"Hurtbox")


# --- helpers ---------------------------------------------------------------


func _spawn(pos: Vector3, alerted: bool) -> BaseEnemy:
	var drone: BaseEnemy = DRONE.instantiate()
	drone.start_alerted = alerted
	drone.position = pos
	_root.add_child(drone)
	return drone


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


func _static_box(center: Vector3, size: Vector3) -> void:
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


func test_spotting_alerts_droids_within_alert_radius_only() -> void:
	_static_box(Vector3(0.0, -0.25, 0.0), Vector3(80.0, 0.5, 80.0))  # room for the far drone
	# Wall that hides the target from `hidden` but not from `spotter`.
	_static_box(Vector3(5.0, 1.5, -6.0), Vector3(0.6, 3.0, 6.0))
	_bake()
	_make_target(Vector3(10.0, 0.0, 0.0))
	var spotter: BaseEnemy = _spawn(Vector3(0.0, 0.0, 0.0), false)
	var hidden: BaseEnemy = _spawn(Vector3(0.0, 0.0, -8.0), false)  # 8 m from spotter
	var far: BaseEnemy = _spawn(Vector3(-25.0, 0.0, -8.0), false)  # 26 m away, out of sight
	assert_false(_line_clear(hidden, _target), "precondition: hidden has no line of sight")
	await wait_physics_frames(20)
	assert_eq(spotter.get_state(), BaseEnemy.STATE_CHASE, "spotter saw the target")
	assert_ne(hidden.get_state(), BaseEnemy.STATE_IDLE, "alerted through AXIOM's network")
	assert_eq(far.get_state(), BaseEnemy.STATE_IDLE, "outside alert_radius: still idle")


func _line_clear(from: Node3D, to: Node3D) -> bool:
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from.global_position + Vector3.UP, to.global_position + Vector3.UP, PhysicsLayers.WORLD
	)
	return from.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
