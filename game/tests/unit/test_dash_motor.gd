extends GutTest
## P1-12: dash timing. Burst, i-frames that outlast it, cooldown from the start.

var _dash: DashMotor
var _stats: PlayerStats


func before_each() -> void:
	_stats = PlayerStats.new()
	_stats.dash_speed = 16.0
	_stats.dash_time = 0.2
	_stats.dash_iframes = 0.3
	_stats.dash_cooldown = 1.0
	_dash = DashMotor.new()
	_dash.configure(_stats)


func test_dash_moves_flat_at_dash_speed() -> void:
	assert_true(_dash.start(Vector3(3.0, 5.0, 4.0)))
	assert_true(_dash.is_dashing())
	assert_almost_eq(_dash.get_velocity(), Vector3(0.6, 0.0, 0.8) * 16.0, Vector3.ONE * 0.001)


func test_iframes_outlast_the_burst() -> void:
	_dash.start(Vector3.FORWARD)
	_dash.update(0.25)
	assert_false(_dash.is_dashing(), "burst over")
	assert_true(_dash.is_invulnerable(), "still safe")
	_dash.update(0.1)
	assert_false(_dash.is_invulnerable())


func test_cooldown_blocks_until_ready() -> void:
	_dash.start(Vector3.FORWARD)
	_dash.update(0.5)
	assert_false(_dash.start(Vector3.FORWARD), "cooling down")
	assert_almost_eq(_dash.get_cooldown_ratio(), 0.5, 0.001)
	_dash.update(0.5)
	assert_true(_dash.can_dash())
	assert_true(_dash.start(Vector3.BACK))


func test_no_horizontal_direction_is_rejected() -> void:
	assert_false(_dash.start(Vector3.UP))
	assert_false(_dash.start(Vector3.ZERO))
	assert_true(_dash.can_dash(), "a rejected dash costs nothing")


func test_cancel_ends_dash_and_iframes() -> void:
	_dash.start(Vector3.FORWARD)
	_dash.cancel()
	assert_false(_dash.is_dashing())
	assert_false(_dash.is_invulnerable())
