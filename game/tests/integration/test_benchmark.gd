extends GutTest
## P1-14: a shortened benchmark run completes and reports both cameras.
## Uses the real street and HOLLOW (LFS art), so it is pending in CI.

const PROBE: String = "res://assets/textures/pbr/metal_plate/metal_plate_diff_1k.jpg"

var _bench: Benchmark
var _old_mode: Settings.CameraMode


func before_each() -> void:
	_old_mode = Settings.camera_mode


func after_each() -> void:
	if is_instance_valid(_bench):
		_bench.free()
	Settings.camera_mode = _old_mode


func test_short_run_reports_both_cameras() -> void:
	if not _has_lfs_art():
		pending("Needs LFS art (CI runs without LFS)")
		return
	_bench = (load(Benchmark.SCENE) as PackedScene).instantiate()
	_bench.warmup_seconds = 0.3
	_bench.phase_seconds = 0.6
	_bench.switch_seconds = 0.2
	_bench.target_droids = 8
	add_child(_bench)
	await wait_seconds(2.5)
	assert_eq(_bench.phase, Benchmark.Phase.DONE)
	var results: Dictionary = _bench.get_results()
	assert_gt(int(results["tactical"]["frames"]), 5)
	assert_gt(int(results["shoulder"]["frames"]), 5)
	# (Draw calls are 0 here: headless runs have no renderer.)
	assert_gt(_bench.get_node("Enemies").get_child_count(), 3, "droids were spawned")


func _has_lfs_art() -> bool:
	var probe: FileAccess = FileAccess.open(PROBE, FileAccess.READ)
	return probe != null and probe.get_buffer(7).get_string_from_ascii() != "version"
