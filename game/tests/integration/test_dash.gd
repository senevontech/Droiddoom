extends GutTest
## P1-12: HOLLOW's dash (burst, i-frames, cooldown) and Neural Sync detection
## against real rounds in flight and a real arming Kamikaze.

const HOLLOW: String = "res://actors/player/hollow.tscn"
const KAMIKAZE: PackedScene = preload("res://actors/enemies/kamikaze/kamikaze.tscn")
const BOLT: String = "res://data/weapons/weapon_axiom_blaster.tres"
const LFS_PROBE: String = "res://assets/textures/pbr/metal_plate/metal_plate_diff_1k.jpg"

var _root: Node3D
var _projectiles: ProjectileSystem
var _bolt: WeaponData


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_root.add_child(EnemyCoordinator.new())
	_projectiles = ProjectileSystem.new()
	_root.add_child(_projectiles)
	_root.add_child(DebrisSystem.new())
	_root.add_child(CombatFX.new())
	_floor()
	_bolt = load(BOLT) as WeaponData


func test_round_about_to_hit_counts_as_a_threat() -> void:
	var player: Node3D = _stand_in(Vector3.ZERO)
	await wait_physics_frames(2)
	var speed: float = _bolt.projectile.speed
	_projectiles.fire(
		_bolt,
		Vector3(0.0, 1.0, -speed * 0.1),
		Vector3(0.0, 0.0, speed),
		PhysicsLayers.PLAYER,
		null,
		[]
	)
	assert_eq(NeuralSync.count_threats(player, 0.2), 1, "lands in ~0.1 s")
	assert_eq(NeuralSync.count_threats(player, 0.02), 0, "not within a tiny window")


func test_rounds_aimed_at_axiom_are_not_threats() -> void:
	var player: Node3D = _stand_in(Vector3.ZERO)
	await wait_physics_frames(2)
	_projectiles.fire(
		_bolt, Vector3(0.0, 1.0, -1.0), Vector3(0.0, 0.0, 15.0), PhysicsLayers.ENEMIES, null, []
	)
	assert_eq(NeuralSync.count_threats(player, 0.2), 0)


func test_arming_kamikaze_is_a_threat_until_it_resolves() -> void:
	NavBaker.add_region(_root, _root)
	var player: Node3D = _stand_in(Vector3(0.0, 0.0, -3.0))
	player.add_to_group(BaseEnemy.TARGET_GROUP)
	var kamikaze: KamikazeEnemy = KAMIKAZE.instantiate()
	kamikaze.start_alerted = true
	_root.add_child(kamikaze)
	var eta: float = -1.0
	for i in 120:
		await wait_physics_frames(1)
		eta = kamikaze.get_attack_eta()
		if eta >= 0.0:
			break
	assert_between(eta, 0.0, kamikaze.data.attack_windup, "armed: lands within its windup")
	assert_gt(kamikaze.get_threat_reach(), kamikaze.data.death_blast_radius, "blast reach")
	assert_gte(NeuralSync.count_threats(player, kamikaze.data.attack_windup + 0.05), 1)


func test_dash_moves_fast_gives_iframes_and_cools_down() -> void:
	if _lfs_missing():
		pending("Needs LFS art (CI runs without LFS)")
		return
	var hollow: Hollow = _hollow()
	await wait_physics_frames(3)
	var start: Vector3 = hollow.global_position
	assert_true(hollow.try_dash())
	assert_true(hollow.health.invulnerable, "i-frames from the first frame")
	assert_false(hollow.try_dash(), "cooling down")
	await wait_seconds(hollow.stats.dash_time + 0.02)
	var moved: float = (
		Vector2(hollow.global_position.x - start.x, hollow.global_position.z - start.z).length()
	)
	assert_gt(moved, hollow.stats.dash_speed * hollow.stats.dash_time * 0.7, "burst distance")
	await wait_seconds(hollow.stats.dash_iframes)
	assert_false(hollow.health.invulnerable, "i-frames over")


func test_perfect_dash_through_a_bolt_takes_no_damage() -> void:
	if _lfs_missing():
		pending("Needs LFS art (CI runs without LFS)")
		return
	var hollow: Hollow = _hollow()
	await wait_physics_frames(3)
	watch_signals(EventBus)
	watch_signals(hollow)
	var speed: float = _bolt.projectile.speed
	_projectiles.fire(
		_bolt,
		hollow.global_position + Vector3(0.0, 1.0, -speed * 0.1),
		Vector3(0.0, 0.0, speed),
		PhysicsLayers.PLAYER,
		null,
		[]
	)
	assert_true(hollow.try_dash())
	assert_signal_emitted(EventBus, "neural_sync_triggered")
	assert_eq(get_signal_parameters(hollow, "dashed")[1], true, "perfect dash")
	await wait_seconds(0.4)
	assert_eq(hollow.health.get_health(), hollow.stats.max_hp, "the bolt missed")


func test_plain_dash_is_not_perfect() -> void:
	if _lfs_missing():
		pending("Needs LFS art (CI runs without LFS)")
		return
	var hollow: Hollow = _hollow()
	await wait_physics_frames(3)
	watch_signals(EventBus)
	hollow.try_dash()
	assert_signal_emitted(EventBus, "player_dashed")
	assert_signal_not_emitted(EventBus, "neural_sync_triggered")


func _hollow() -> Hollow:
	var hollow: Hollow = (load(HOLLOW) as PackedScene).instantiate()
	hollow.primary_loadout = []
	hollow.heavy_loadout = []
	_root.add_child(hollow)
	return hollow


func _stand_in(pos: Vector3) -> Node3D:
	var player: Node3D = Node3D.new()
	player.position = pos
	_root.add_child(player)
	return player


func _floor() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	body.position = Vector3(0.0, -0.25, 0.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 0.5, 60.0)
	shape.shape = box
	body.add_child(shape)
	_root.add_child(body)


func _lfs_missing() -> bool:
	var f: FileAccess = FileAccess.open(LFS_PROBE, FileAccess.READ)
	if f == null:
		return true
	return f.get_buffer(7).get_string_from_ascii() == "version"
