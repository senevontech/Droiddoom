extends GutTest
## P1-08: AI LOD think intervals per distance tier, fallback and stagger.

var _preset: QualityPreset


func before_each() -> void:
	_preset = QualityPreset.new()
	_preset.ai_near_distance = 10.0
	_preset.ai_mid_distance = 30.0
	_preset.ai_tick_hz_near = 20.0
	_preset.ai_tick_hz_mid = 10.0
	_preset.ai_tick_hz_far = 4.0


func test_near_mid_far_tiers() -> void:
	assert_almost_eq(AiLod.interval_for(0.0, _preset), 0.05, 0.0001, "near = 20 Hz")
	assert_almost_eq(AiLod.interval_for(9.99, _preset), 0.05, 0.0001, "just inside near")
	assert_almost_eq(AiLod.interval_for(10.0, _preset), 0.1, 0.0001, "mid starts at near distance")
	assert_almost_eq(AiLod.interval_for(29.0, _preset), 0.1, 0.0001, "mid = 10 Hz")
	assert_almost_eq(AiLod.interval_for(30.0, _preset), 0.25, 0.0001, "far = 4 Hz")
	assert_almost_eq(AiLod.interval_for(INF, _preset), 0.25, 0.0001, "no target counts as far")


func test_zero_rate_is_clamped_not_infinite() -> void:
	_preset.ai_tick_hz_far = 0.0
	assert_almost_eq(AiLod.interval_for(100.0, _preset), 2.0, 0.0001, "min 0.5 Hz")


func test_null_preset_uses_default() -> void:
	assert_eq(AiLod.interval_for(50.0, null), AiLod.DEFAULT_INTERVAL)


func test_stagger_stays_inside_one_interval() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for i in 50:
		var s: float = AiLod.stagger(0.25, rng)
		assert_between(s, 0.0, 0.25)


func test_low_preset_thinks_less_than_high() -> void:
	var low: QualityPreset = load("res://data/quality/quality_low.tres")
	var high: QualityPreset = load("res://data/quality/quality_high.tres")
	for dist: float in [5.0, 25.0, 60.0]:
		assert_gte(
			AiLod.interval_for(dist, low),
			AiLod.interval_for(dist, high),
			"Low thinks no more often than High at %.0f m" % dist
		)
	assert_lt(low.path_queries_per_frame, high.path_queries_per_frame)
