extends GutTest
## P1-07 + D-030: weapons fire rounds that really travel. Rounds take time to
## arrive, are blocked by walls, drop under gravity unless zeroed, pierce
## (railgun) and come in pellets (scattergun). Beams (laser) hit instantly.
## Magazines, reloads and limited reserve ammo. EventBus signals for FX.

const RIFLE: String = "res://data/weapons/weapon_pulse_rifle.tres"
const SCATTER: String = "res://data/weapons/weapon_scattergun.tres"
const LASER: String = "res://data/weapons/weapon_beam_laser.tres"
const RAIL: String = "res://data/weapons/weapon_railgun.tres"
const MUZZLE: Vector3 = Vector3(0.0, 1.0, 0.0)

var _root: Node3D
var _system: ProjectileSystem
var _weapon: Weapon


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_system = ProjectileSystem.new()
	_root.add_child(_system)
	_weapon = _make_weapon(RIFLE)


func test_round_travels_before_it_hits() -> void:
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -20.0), PhysicsLayers.ENEMIES)
	watch_signals(EventBus)
	await wait_physics_frames(2)
	assert_true(_weapon.try_fire(MUZZLE, Vector3(0.0, 1.0, -20.0)))
	assert_signal_emitted(EventBus, "weapon_fired")
	assert_eq(target.get_health(), 100.0, "nothing is hit the instant the trigger is pulled")
	await wait_physics_frames(2)
	assert_eq(_system.get_active_count(), 1, "the round is in flight")
	var at: Vector3 = _system.get_positions()[0]
	assert_between(at.z, -10.0, -1.0, "between muzzle and target")
	await wait_physics_frames(15)
	assert_eq(target.get_health(), 100.0 - _weapon.data.damage)
	assert_eq(_system.get_active_count(), 0, "the round is gone after the hit")
	var params: Array = get_signal_parameters(EventBus, "hit_landed")
	assert_true(params[3], "on_target")


func test_wall_blocks_round() -> void:
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -10.0), PhysicsLayers.ENEMIES)
	_wall(Vector3(0.0, 1.0, -5.0))
	await wait_physics_frames(2)
	_weapon.try_fire(MUZZLE, Vector3(0.0, 1.0, -10.0))
	await wait_physics_frames(20)
	assert_eq(target.get_health(), 100.0)


func test_wrong_faction_is_not_hit() -> void:
	var ally: HealthComponent = _target(Vector3(0.0, 1.0, -10.0), PhysicsLayers.PLAYER)
	await wait_physics_frames(2)
	_weapon.try_fire(MUZZLE, Vector3(0.0, 1.0, -10.0))
	await wait_physics_frames(20)
	assert_eq(ally.get_health(), 100.0)


func test_point_blank_target_behind_the_muzzle_is_hit() -> void:
	# The target overlaps the muzzle (enemy hugging HOLLOW).
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -0.2), PhysicsLayers.ENEMIES)
	await wait_physics_frames(2)
	_weapon.try_fire(MUZZLE, Vector3(0.0, 1.0, -10.0))
	await wait_physics_frames(3)
	assert_lt(target.get_health(), 100.0)


func test_gravity_drops_a_level_round() -> void:
	await wait_physics_frames(1)
	_system.fire(_weapon.data, MUZZLE, Vector3(0.0, 0.0, -60.0), PhysicsLayers.ENEMIES, null, [])
	await wait_physics_frames(30)
	var at: Vector3 = _system.get_positions()[0]
	assert_lt(at.y, MUZZLE.y - 0.3, "dropped under gravity over half a second")
	assert_lt(at.z, -20.0, "and kept flying forward")


func test_zeroed_round_lands_on_a_far_aim_point() -> void:
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -60.0), PhysicsLayers.ENEMIES)
	await wait_physics_frames(2)
	_weapon.try_fire(MUZZLE, Vector3(0.0, 1.0, -60.0))
	await wait_physics_frames(40)
	assert_lt(target.get_health(), 100.0, "sights are zeroed at the aim point")


func test_scattergun_fires_a_pellet_cloud() -> void:
	var scatter: Weapon = _make_weapon(SCATTER)
	await wait_physics_frames(1)
	scatter.try_fire(MUZZLE, Vector3(0.0, 1.0, -20.0))
	await wait_physics_frames(1)
	assert_eq(_system.get_active_count(), scatter.data.pellets)


func test_railgun_slug_pierces_a_line_of_targets() -> void:
	var rail: Weapon = _make_weapon(RAIL)
	var first: HealthComponent = _target(Vector3(0.0, 1.0, -8.0), PhysicsLayers.ENEMIES)
	var second: HealthComponent = _target(Vector3(0.0, 1.0, -14.0), PhysicsLayers.ENEMIES)
	await wait_physics_frames(2)
	rail.try_fire(MUZZLE, Vector3(0.0, 1.0, -14.0))
	await wait_physics_frames(6)
	assert_lt(first.get_health(), 100.0)
	assert_lt(second.get_health(), 100.0, "went through the first target")


func test_beam_hits_instantly_and_is_drawn() -> void:
	var laser: Weapon = _make_weapon(LASER)
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -10.0), PhysicsLayers.ENEMIES)
	watch_signals(EventBus)
	await wait_physics_frames(2)
	laser.try_fire(MUZZLE, Vector3(0.0, 1.0, -10.0))
	assert_eq(target.get_health(), 100.0 - laser.data.damage)
	assert_signal_emitted(EventBus, "beam_drawn")
	assert_eq(_system.get_active_count(), 0, "beams don't spawn rounds")


func test_magazine_empties_then_reloads() -> void:
	_weapon.data.magazine_size = 3
	_weapon.data.fire_interval = 0.0
	_weapon.data.reload_time = 0.2
	_weapon.refill()
	await wait_physics_frames(1)
	for i in 3:
		assert_true(_weapon.try_fire(MUZZLE, Vector3.FORWARD), "shot %d" % i)
	assert_true(_weapon.is_reloading(), "auto-reload on empty")
	assert_false(_weapon.try_fire(MUZZLE, Vector3.FORWARD), "can't fire while reloading")
	await wait_seconds(0.3)
	assert_false(_weapon.is_reloading())
	assert_eq(_weapon.get_magazine(), 3)


func test_reserve_ammo_runs_out() -> void:
	_weapon.data.magazine_size = 2
	_weapon.data.reserve_ammo = 2
	_weapon.data.fire_interval = 0.0
	_weapon.data.reload_time = 0.05
	_weapon.refill()
	await wait_physics_frames(1)
	_weapon.try_fire(MUZZLE, Vector3.FORWARD)
	_weapon.try_fire(MUZZLE, Vector3.FORWARD)
	await wait_seconds(0.15)
	assert_eq(_weapon.get_magazine(), 2, "reloaded from the reserve")
	assert_eq(_weapon.get_reserve(), 0)
	_weapon.try_fire(MUZZLE, Vector3.FORWARD)
	_weapon.try_fire(MUZZLE, Vector3.FORWARD)
	assert_true(_weapon.is_out_of_ammo())
	assert_false(_weapon.start_reload())


func test_fire_rate_limits_shots() -> void:
	await wait_physics_frames(1)
	assert_true(_weapon.try_fire(MUZZLE, Vector3.FORWARD))
	assert_false(_weapon.try_fire(MUZZLE, Vector3.FORWARD), "still cooling down")
	await wait_seconds(_weapon.data.fire_interval + 0.05)
	assert_true(_weapon.try_fire(MUZZLE, Vector3.FORWARD))


func test_crit_multiplies_damage() -> void:
	_weapon.data.crit_chance = 1.0
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -10.0), PhysicsLayers.ENEMIES)
	await wait_physics_frames(2)
	_weapon.try_fire(MUZZLE, Vector3(0.0, 1.0, -10.0))
	await wait_physics_frames(12)
	assert_eq(target.get_health(), 100.0 - _weapon.data.damage * _weapon.data.crit_multiplier)


func test_spread_stays_inside_cone() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var dir: Vector3 = Vector3(0.3, 0.1, -1.0).normalized()
	var widest: float = 0.0
	for i in 500:
		var spread: Vector3 = Weapon.apply_spread(dir, 3.0, rng)
		assert_almost_eq(spread.length(), 1.0, 0.0001)
		widest = maxf(widest, rad_to_deg(dir.angle_to(spread)))
	assert_lt(widest, 3.0001)
	assert_gt(widest, 2.0, "uses the cone, not just the centre")


func _make_weapon(path: String) -> Weapon:
	var gun: Weapon = Weapon.new()
	gun.data = (load(path) as WeaponData).duplicate()
	gun.data.spread_deg = 0.0
	gun.data.crit_chance = 0.0
	gun.target_mask = PhysicsLayers.ENEMIES
	_root.add_child(gun)
	return gun


func _target(pos: Vector3, layer: int) -> HealthComponent:
	var actor: Node3D = Node3D.new()
	actor.position = pos
	_root.add_child(actor)
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	actor.add_child(health)
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.collision_layer = layer
	hurtbox.collision_mask = 0
	hurtbox.health = health
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	hurtbox.add_child(shape)
	actor.add_child(hurtbox)
	return health


func _wall(pos: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.position = pos
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.3)
	shape.shape = box
	body.add_child(shape)
	_root.add_child(body)
