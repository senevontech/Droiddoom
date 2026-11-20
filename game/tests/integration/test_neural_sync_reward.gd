extends GutTest
## P1-13: the Neural Sync reward on HOLLOW. Slows the world, keeps HOLLOW
## fast (haste), boosts its weapons, and always restores time: when it runs
## out, when HOLLOW dies, and when HOLLOW leaves the tree mid-reward.
## HOLLOW's materials use LFS textures, so this is pending in CI.

const HOLLOW: String = "res://actors/player/hollow.tscn"
const PROBE: String = "res://assets/textures/pbr/metal_plate/metal_plate_diff_1k.jpg"

var _root: Node3D
var _hollow: Hollow


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


func after_each() -> void:
	Engine.time_scale = 1.0


func test_reward_slows_time_and_boosts_hollow_then_restores() -> void:
	if not _spawn():
		return
	watch_signals(EventBus)
	_hollow.start_neural_sync()
	assert_true(_hollow.is_neural_synced())
	assert_almost_eq(Engine.time_scale, _hollow.stats.neural_sync_time_scale, 0.001)
	assert_gt(_hollow.get_haste(), 1.5, "HOLLOW outpaces the slowed world")
	for gun: Weapon in _hollow.get_primaries() + _hollow.get_heavies():
		assert_eq(gun.damage_scale, _hollow.stats.neural_sync_damage_bonus)
	# Real-time length: 0.3 s here; scaled waits would take longer in real time.
	await get_tree().create_timer(0.45, true, false, true).timeout
	assert_false(_hollow.is_neural_synced(), "ran out on real time")
	assert_eq(Engine.time_scale, 1.0, "time restored")
	assert_signal_emitted(EventBus, "neural_sync_ended")
	assert_eq(_hollow.weapon.damage_scale, 1.0)


func test_death_and_leaving_the_tree_restore_time() -> void:
	if not _spawn():
		return
	_hollow.start_neural_sync()
	_hollow.health.apply_damage(DamageInfo.create(1.0e6, DamageInfo.Type.KINETIC))
	assert_eq(Engine.time_scale, 1.0, "death ends the reward")
	var other: Hollow = (load(HOLLOW) as PackedScene).instantiate()
	_root.add_child(other)
	other.start_neural_sync()
	other.free()
	assert_eq(Engine.time_scale, 1.0, "freed mid-reward (scene restart)")


func _spawn() -> bool:
	if not _has_lfs_art():
		pending("Needs LFS art (CI runs without LFS)")
		return false
	_hollow = (load(HOLLOW) as PackedScene).instantiate()
	_hollow.stats = _hollow.stats.duplicate()
	_hollow.stats.neural_sync_duration = 0.3
	_root.add_child(_hollow)
	return true


func _has_lfs_art() -> bool:
	var probe: FileAccess = FileAccess.open(PROBE, FileAccess.READ)
	return probe != null and probe.get_buffer(7).get_string_from_ascii() != "version"
