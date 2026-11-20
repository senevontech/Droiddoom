extends GutTest
## D-030: launch maths. Zeroed straight shots and lobbed arcs land on the
## aim point when flown with the same integration as ProjectileSystem.

const G: float = 9.8
const DT: float = 1.0 / 60.0


func test_zeroed_shot_crosses_the_aim_point() -> void:
	var from: Vector3 = Vector3(0.0, 1.3, 0.0)
	var target: Vector3 = Vector3(0.0, 1.2, -50.0)
	var v: Vector3 = Ballistics.zeroed_velocity(from, target, 120.0, G)
	assert_almost_eq(v.length(), 120.0, 0.001, "speed is kept")
	var y_at_target: float = _height_when_passing(from, v, target, 0.0)
	assert_almost_eq(y_at_target, target.y, 0.08)


func test_unzeroed_shot_falls_short() -> void:
	var from: Vector3 = Vector3(0.0, 1.3, 0.0)
	var target: Vector3 = Vector3(0.0, 1.3, -80.0)
	var straight: Vector3 = (target - from).normalized() * 100.0
	assert_lt(_height_when_passing(from, straight, target, 0.0), target.y - 0.2)


func test_lob_lands_on_target() -> void:
	var from: Vector3 = Vector3(0.0, 1.3, 0.0)
	var target: Vector3 = Vector3(6.0, 0.0, -9.0)
	var v: Vector3 = Ballistics.lob_velocity(from, target, 20.0, G)
	assert_almost_eq(v.length(), 20.0, 0.001)
	assert_gt(v.y, 0.0, "arcs upward")
	var landed: Vector3 = _landing_point(from, v, target.y)
	assert_lt(Vector2(landed.x, landed.z).distance_to(Vector2(target.x, target.z)), 0.5)


func test_lob_out_of_reach_uses_45_degrees() -> void:
	var v: Vector3 = Ballistics.lob_velocity(Vector3.ZERO, Vector3(0.0, 0.0, -500.0), 20.0, G)
	var flat: float = Vector2(v.x, v.z).length()
	assert_almost_eq(v.y, flat, 0.01)


func test_drag_slows_a_round() -> void:
	var state: Array[Vector3] = Ballistics.step(
		Vector3.ZERO, Vector3(0.0, 0.0, -100.0), 0.0, 2.0, 0.5
	)
	assert_almost_eq(state[1].length(), 100.0 * exp(-1.0), 0.01)


func _height_when_passing(from: Vector3, v: Vector3, target: Vector3, drag: float) -> float:
	var pos: Vector3 = from
	var vel: Vector3 = v
	var flat_goal: float = Vector2(target.x - from.x, target.z - from.z).length()
	for i in 2000:
		var state: Array[Vector3] = Ballistics.step(pos, vel, G, drag, DT)
		var next: Vector3 = state[0]
		var travelled: float = Vector2(next.x - from.x, next.z - from.z).length()
		if travelled >= flat_goal:
			var before: float = Vector2(pos.x - from.x, pos.z - from.z).length()
			var t: float = (flat_goal - before) / maxf(travelled - before, 0.0001)
			return lerpf(pos.y, next.y, t)
		pos = next
		vel = state[1]
	return -INF


func _landing_point(from: Vector3, v: Vector3, ground_y: float) -> Vector3:
	var pos: Vector3 = from
	var vel: Vector3 = v
	for i in 2000:
		var state: Array[Vector3] = Ballistics.step(pos, vel, G, 0.0, DT)
		if state[0].y <= ground_y and state[1].y < 0.0:
			return state[0]
		pos = state[0]
		vel = state[1]
	return pos
