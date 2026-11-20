extends GutTest
## D-030: rockets and grenades. Blasts fall off with distance and are blocked
## by walls, rockets home onto a locked target, grenades bounce and wait for
## their fuse.

const ROCKET: String = "res://data/weapons/weapon_rocket_pod.tres"
const GRENADE: String = "res://data/weapons/weapon_grenade_launcher.tres"
const MUZZLE: Vector3 = Vector3(0.0, 1.0, 0.0)

var _root: Node3D
var _system: ProjectileSystem


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_system = ProjectileSystem.new()
	_root.add_child(_system)
	_box(Vector3(0.0, -0.25, 0.0), Vector3(60.0, 0.5, 60.0))  # floor


func test_falloff_from_centre_to_edge() -> void:
	assert_eq(Explosion.falloff(0.0, 4.0), 1.0)
	assert_almost_eq(Explosion.falloff(4.0, 4.0), Explosion.EDGE_FALLOFF, 0.0001)
	assert_almost_eq(Explosion.falloff(10.0, 4.0), Explosion.EDGE_FALLOFF, 0.0001)


func test_blast_damage_falls_off_and_stops_at_radius() -> void:
	var near: HealthComponent = _target(Vector3(0.5, 1.0, 0.0))
	var mid: HealthComponent = _target(Vector3(2.5, 1.0, 0.0))
	var outside: HealthComponent = _target(Vector3(7.0, 1.0, 0.0))
	watch_signals(EventBus)
	await wait_physics_frames(2)
	var hits: int = Explosion.detonate(
		_root.get_world_3d(), Vector3(0.0, 1.0, 0.0), 4.0, 80.0, 0, 10.0, PhysicsLayers.ENEMIES
	)
	assert_eq(hits, 2)
	assert_lt(near.get_health(), mid.get_health(), "closer = more damage")
	assert_lt(mid.get_health(), 100.0)
	assert_eq(outside.get_health(), 100.0)
	assert_signal_emitted(EventBus, "explosion_happened")


func test_wall_shields_from_blast() -> void:
	var hidden: HealthComponent = _target(Vector3(2.5, 1.0, 0.0))
	_box(Vector3(1.2, 1.0, 0.0), Vector3(0.3, 3.0, 3.0))
	await wait_physics_frames(2)
	Explosion.detonate(
		_root.get_world_3d(), Vector3(0.0, 1.0, 0.0), 4.0, 80.0, 0, 10.0, PhysicsLayers.ENEMIES
	)
	assert_eq(hidden.get_health(), 100.0)


func test_rocket_homes_onto_the_locked_target() -> void:
	var pod: Weapon = _weapon(ROCKET)
	var target: HealthComponent = _target(Vector3(4.0, 1.0, -18.0))
	await wait_physics_frames(2)
	# Aim 2.5 m beside the target: inside lock_radius, so the rocket locks on.
	pod.try_fire(MUZZLE, Vector3(1.5, 1.0, -18.0))
	await wait_physics_frames(90)
	assert_lt(target.get_health(), 100.0 - pod.data.projectile.explosion_damage * 0.8)


func test_grenade_bounces_and_waits_for_its_fuse() -> void:
	var launcher: Weapon = _weapon(GRENADE)
	var target: HealthComponent = _target(Vector3(2.0, 1.0, -7.0))
	_box(Vector3(0.0, 1.5, -9.0), Vector3(6.0, 3.0, 0.4))  # wall behind the landing point
	await wait_physics_frames(2)
	launcher.try_fire(MUZZLE, Vector3(0.0, 0.0, -8.0))
	await wait_physics_frames(40)  # ~0.67 s: landed, bounced, not yet exploded
	assert_eq(_system.get_active_count(), 1, "still waiting for the fuse")
	assert_eq(target.get_health(), 100.0)
	await wait_physics_frames(60)
	assert_eq(_system.get_active_count(), 0, "went off")
	assert_lt(target.get_health(), 100.0, "caught in the blast")


func _weapon(path: String) -> Weapon:
	var gun: Weapon = Weapon.new()
	gun.data = (load(path) as WeaponData).duplicate()
	gun.data.spread_deg = 0.0
	gun.target_mask = PhysicsLayers.ENEMIES
	_root.add_child(gun)
	return gun


## A stand-in actor whose hurtbox centre is at `pos` (origin 1 m lower, at
## its feet, like real droids: homing aims at origin + chest height).
func _target(pos: Vector3) -> HealthComponent:
	var actor: Node3D = Node3D.new()
	actor.position = pos - Vector3.UP
	_root.add_child(actor)
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	actor.add_child(health)
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.collision_layer = PhysicsLayers.ENEMIES
	hurtbox.collision_mask = 0
	hurtbox.health = health
	hurtbox.position = Vector3.UP
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	hurtbox.add_child(shape)
	actor.add_child(hurtbox)
	return health


func _box(center: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.position = center
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_root.add_child(body)
