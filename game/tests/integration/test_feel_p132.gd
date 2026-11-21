extends GutTest
## P1-32: shots leave the barrel forward, the walk cycle moves legs and body,
## droid drops are collected, and hit markers confirm the player's kills.

const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")


func test_fire_target_keeps_far_aligned_aim() -> void:
	var muzzle: Vector3 = Vector3(0.0, 1.3, 0.0)
	var aim: Vector3 = Vector3(0.5, 1.2, -12.0)
	assert_eq(Hollow.fire_target(muzzle, Vector3.FORWARD, aim), aim)


func test_fire_target_never_shoots_sideways_or_backwards() -> void:
	var muzzle: Vector3 = Vector3(0.0, 1.3, 0.0)
	for aim: Vector3 in [Vector3(3.0, 1.2, 0.5), Vector3(0.0, 1.2, 6.0), Vector3(0.3, 0.2, -1.0)]:
		var target: Vector3 = Hollow.fire_target(muzzle, Vector3.FORWARD, aim)
		var flat: Vector3 = Vector3(target.x - muzzle.x, 0.0, target.z - muzzle.z)
		assert_lt(rad_to_deg(Vector3.FORWARD.angle_to(flat)), 20.5, "%s: out of the barrel" % aim)
		assert_gte(flat.length(), Hollow.MIN_AIM_DISTANCE - 0.001, "never point-blank")
		assert_gt(target.y, 0.9, "no steep dive into the ground")


func test_gait_swings_hips_and_bobs_the_body() -> void:
	var body: Node3D = Node3D.new()
	var hip_l: Node3D = Node3D.new()
	var hip_r: Node3D = Node3D.new()
	add_child_autofree(body)
	add_child_autofree(hip_l)
	add_child_autofree(hip_r)
	var gait: Gait = Gait.new([hip_l, hip_r], [] as Array[Node3D], body)
	var swung: float = 0.0
	var bobbed: float = 0.0
	for i in 60:
		gait.update(5.0, 5.0, 1.0 / 60.0)
		swung = maxf(swung, absf(hip_l.rotation.x))
		bobbed = maxf(bobbed, gait.get_body_offset())
		assert_almost_eq(hip_l.rotation.x, -hip_r.rotation.x, 0.0001, "legs in opposite phase")
	assert_gt(swung, 0.2, "hips swing")
	assert_gt(bobbed, 0.01, "body bobs")
	for i in 120:
		gait.update(0.0, 5.0, 1.0 / 60.0)
	assert_almost_eq(hip_l.rotation.x, 0.0, 0.01, "settles when standing")


func test_drops_spawn_and_are_collected() -> void:
	if not _has_lfs_art():
		pending("Needs LFS art for HOLLOW (CI runs without LFS)")
		return
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	var pickups: PickupSystem = PickupSystem.new()
	root.add_child(pickups)
	var player: Node3D = _fake_player(root)
	var health: HealthComponent = player.get_node("Health")
	health.apply_damage(DamageInfo.create(50.0, DamageInfo.Type.KINETIC))
	watch_signals(EventBus)
	pickups.spawn(PickupSystem.REPAIR, player.global_position + Vector3(2.5, 0.0, 0.0))
	assert_eq(pickups.get_active_count(), 1)
	await wait_seconds(0.6)
	assert_eq(pickups.get_active_count(), 0, "pulled in and collected")
	assert_signal_emitted(EventBus, "pickup_collected")
	assert_gt(health.get_health(), 50.0, "repaired")


func test_drop_chances_come_from_enemy_data() -> void:
	var pickups: PickupSystem = PickupSystem.new()
	add_child_autofree(pickups)
	var data: EnemyData = EnemyData.new()
	data.drop_repair_chance = 1.0
	assert_eq(pickups.roll_drop(data, Vector3.ZERO), PickupSystem.REPAIR)
	data.drop_repair_chance = 0.0
	data.drop_ammo_chance = 0.0
	assert_eq(pickups.roll_drop(data, Vector3.ZERO), &"")


func test_hit_markers_confirm_only_the_players_kills() -> void:
	var markers: HitMarkers = HitMarkers.new()
	add_child_autofree(markers)
	var player: Node3D = Node3D.new()
	player.add_to_group(Hollow.PLAYER_GROUP)
	add_child_autofree(player)
	var other: Node = autofree(Node.new())
	EventBus.enemy_died.emit(autofree(Node.new()), other)
	assert_eq(markers.get_confirmed_kills(), 0, "not the player's kill")
	EventBus.enemy_hit.emit(null, 5.0, false, player)
	assert_true(markers.is_showing(), "hit marker")
	EventBus.enemy_died.emit(null, player)
	assert_eq(markers.get_confirmed_kills(), 1)


func _fake_player(root: Node3D) -> Hollow:
	var hollow: Hollow = (load("res://actors/player/hollow.tscn") as PackedScene).instantiate()
	root.add_child(hollow)
	return hollow


func _has_lfs_art() -> bool:
	var probe: FileAccess = FileAccess.open(
		"res://assets/textures/pbr/metal_plate/metal_plate_diff_1k.jpg", FileAccess.READ
	)
	return probe != null and probe.get_buffer(7).get_string_from_ascii() != "version"
