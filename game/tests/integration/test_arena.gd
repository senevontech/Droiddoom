extends GutTest
## P1-10: the arena scene end to end. Waves start, the HUD binds, HOLLOW
## breaks apart when destroyed, waves stop and the game-over panel appears.
## Needs the LFS art (street + HOLLOW textures), so it is pending in CI.

const ARENA: String = "res://world/arena/arena.tscn"
const PROBE: String = "res://assets/textures/pbr/metal_plate/metal_plate_diff_1k.jpg"

var _scene: Arena


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.free()


func test_waves_run_and_death_ends_the_run() -> void:
	if not _has_lfs_art():
		pending("Needs LFS art (CI runs without LFS)")
		return
	_scene = (load(ARENA) as PackedScene).instantiate()
	add_child(_scene)
	var director: WaveDirector = _scene.get_node("WaveDirector")
	var hollow: Hollow = _scene.get_node("Hollow")
	var hud: Hud = _scene.get_node("Hud")
	var debris: DebrisSystem = _scene.get_node("DebrisSystem")
	assert_eq(GameState.current_mission_id, &"arena")
	await wait_seconds(director.wave_set.first_delay + 0.5)
	assert_eq(director.get_wave_number(), 1, "wave 1 started")
	assert_gt(_scene.get_node("Enemies").get_child_count(), 0, "droids spawned")
	watch_signals(EventBus)
	hollow.health.apply_damage(DamageInfo.create(1.0e6, DamageInfo.Type.KINETIC))
	assert_signal_emitted(EventBus, "player_died")
	assert_eq(hollow.collision_layer, 0, "the wreck doesn't block")
	assert_gt(debris.get_active_count(), 6, "HOLLOW broke into parts")
	assert_eq(director.get_phase(), WaveDirector.Phase.STOPPED)
	await wait_seconds(Arena.GAME_OVER_DELAY + 0.3)
	assert_true(hud.is_game_over_shown())


func _has_lfs_art() -> bool:
	var probe: FileAccess = FileAccess.open(PROBE, FileAccess.READ)
	return probe != null and probe.get_buffer(7).get_string_from_ascii() != "version"
