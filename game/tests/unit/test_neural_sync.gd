extends GutTest
## P1-12: Neural Sync threat geometry and timing.

const BOTTOM: Vector3 = Vector3(0.0, 0.5, 0.0)
const TOP: Vector3 = Vector3(0.0, 1.5, 0.0)
const RADIUS: float = 0.6


func test_round_about_to_hit_is_a_threat() -> void:
	# 2 m away at 15 m/s: arrives in ~0.13 s, inside a 0.2 s window.
	assert_true(_threat(Vector3(0.0, 1.0, -2.0), Vector3(0.0, 0.0, 15.0), 0.2))


func test_round_too_far_away_is_not_yet_a_threat() -> void:
	assert_false(_threat(Vector3(0.0, 1.0, -8.0), Vector3(0.0, 0.0, 15.0), 0.2))


func test_round_passing_wide_is_not_a_threat() -> void:
	assert_false(_threat(Vector3(2.0, 1.0, -2.0), Vector3(0.0, 0.0, 15.0), 0.2))


func test_round_flying_away_is_not_a_threat() -> void:
	assert_false(_threat(Vector3(0.0, 1.0, -1.0), Vector3(0.0, 0.0, -15.0), 0.2))


func test_round_over_the_head_is_not_a_threat() -> void:
	assert_false(_threat(Vector3(0.0, 2.6, -2.0), Vector3(0.0, 0.0, 15.0), 0.2))


func test_telegraphed_attack_rules() -> void:
	assert_true(NeuralSync.attack_threatens(0.1, 2.0, 1.5, 0.2), "lands soon, in reach")
	assert_false(NeuralSync.attack_threatens(0.5, 2.0, 1.5, 0.2), "lands too late")
	assert_false(NeuralSync.attack_threatens(0.1, 2.0, 3.0, 0.2), "out of reach")
	assert_false(NeuralSync.attack_threatens(-1.0, 2.0, 1.0, 0.2), "no attack pending")
	assert_false(NeuralSync.attack_threatens(0.1, 0.0, 0.5, 0.2), "ranged: reach 0")


func _threat(from: Vector3, velocity: Vector3, window: float) -> bool:
	return NeuralSync.round_threatens(from, velocity, window, BOTTOM, TOP, RADIUS)
