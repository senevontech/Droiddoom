extends GutTest
## P1-10: the Wave Director in a real scene: waves start, spawn in bursts
## away from the player, respect the live cap, clear when every droid is
## dead and move on to the next wave after the break.

const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")

var _root: Node3D
var _director: WaveDirector
var _enemies: Node3D
var _player: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_root.add_child(EnemyCoordinator.new())
	_root.add_child(DebrisSystem.new())
	_floor()
	_player = Node3D.new()
	_player.add_to_group(Hollow.PLAYER_GROUP)
	_root.add_child(_player)
	_enemies = Node3D.new()
	_root.add_child(_enemies)
	_director = WaveDirector.new()
	_director.wave_set = _wave_set(3, 3)
	_director.spawn_parent = _enemies
	_root.add_child(_director)
	_director.set_spawn_points([_marker(Vector3(5.0, 0.0, 0.0)), _marker(Vector3(-20.0, 0.0, 0.0))])


func test_wave_spawns_clears_and_the_next_one_starts() -> void:
	watch_signals(_director)
	_director.start()
	await wait_physics_frames(12)
	assert_signal_emitted_with_parameters(_director, "wave_started", [1])
	assert_eq(_enemies.get_child_count(), 3, "budget 3 of 1-point swarmers, one burst")
	assert_eq(_director.get_remaining(), 3)
	_kill_all()
	await wait_physics_frames(2)
	assert_signal_emitted_with_parameters(_director, "wave_cleared", [1])
	assert_eq(_director.get_phase(), WaveDirector.Phase.BREAK)
	await wait_seconds(0.4)
	assert_eq(_director.get_wave_number(), 2, "next wave after the break")


func test_spawns_away_from_the_player() -> void:
	_director.start()
	await wait_physics_frames(12)
	for droid: Node in _enemies.get_children():
		assert_lt((droid as Node3D).global_position.x, -15.0, "used the far spawn point")


func test_live_cap_holds_spawns_back() -> void:
	_director.max_live_override = 1
	_director.start()
	await wait_physics_frames(12)
	assert_eq(_alive_count(), 1, "only one alive at a time")
	assert_eq(_director.get_remaining(), 3, "the rest are waiting")
	_kill_all()
	await wait_seconds(0.15)
	assert_eq(_alive_count(), 1, "the next one came in after the first died")


func test_stop_ends_spawning() -> void:
	_director.start()
	_director.stop()
	await wait_physics_frames(15)
	assert_eq(_enemies.get_child_count(), 0)
	assert_eq(_director.get_phase(), WaveDirector.Phase.STOPPED)


func _kill_all() -> void:
	for droid: Node in _enemies.get_children():
		var enemy: BaseEnemy = droid as BaseEnemy
		if enemy != null and not enemy.health.is_dead():
			enemy.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.KINETIC))


func _alive_count() -> int:
	var count: int = 0
	for droid: Node in _enemies.get_children():
		var enemy: BaseEnemy = droid as BaseEnemy
		if enemy != null and not enemy.health.is_dead():
			count += 1
	return count


func _wave_set(budget: int, burst: int) -> WaveSet:
	var entry: EnemyEntry = EnemyEntry.new()
	entry.scene = SWARMER
	entry.cost = 1
	var wave: WaveData = WaveData.new()
	wave.budget = budget
	wave.pool = [entry]
	wave.burst_size = burst
	wave.burst_interval = 0.05
	var waves: WaveSet = WaveSet.new()
	waves.waves = [wave]
	waves.first_delay = 0.05
	waves.break_time = 0.3
	return waves


func _marker(pos: Vector3) -> Node3D:
	var marker: Marker3D = Marker3D.new()
	marker.position = pos
	_root.add_child(marker)
	return marker


func _floor() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(80.0, 0.5, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.25, 0.0)
	body.add_child(shape)
	_root.add_child(body)
