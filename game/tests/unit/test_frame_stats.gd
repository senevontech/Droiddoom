extends GutTest
## P1-14: benchmark statistics (average FPS, 1% low, worst frame, draw calls).


func test_steady_frames() -> void:
	var stats: FrameStats = FrameStats.new()
	for i in 100:
		stats.add(10.0, 300, 2.0)
	var s: Dictionary = stats.summary()
	assert_eq(s["frames"], 100)
	assert_almost_eq(float(s["avg_fps"]), 100.0, 0.1)
	assert_almost_eq(float(s["low1_fps"]), 100.0, 0.1)
	assert_eq(s["avg_draw_calls"], 300)
	assert_almost_eq(float(s["avg_physics_ms"]), 2.0, 0.01)


func test_one_percent_low_catches_stutter_the_average_hides() -> void:
	var stats: FrameStats = FrameStats.new()
	for i in 198:
		stats.add(10.0, 300, 1.0)
	stats.add(50.0, 900, 1.0)
	stats.add(50.0, 300, 1.0)
	var s: Dictionary = stats.summary()
	assert_gt(float(s["avg_fps"]), 90.0, "the average barely moves")
	assert_almost_eq(float(s["low1_fps"]), 20.0, 0.1, "1% low shows the 50 ms hitches")
	assert_eq(s["worst_ms"], 50.0)
	assert_eq(s["max_draw_calls"], 900)


func test_empty_summary() -> void:
	assert_eq(FrameStats.new().summary()["frames"], 0)


func test_launch_flags_default_off() -> void:
	assert_false(PlatformServices.has_launch_flag("benchmark-test-flag-that-is-never-set"))
