extends GutTest
## P1-11: aim assist snaps to the enemy closest to the aim line, only inside
## its cone and range, and never through walls.

const ORIGIN: Vector3 = Vector3(0.0, 1.2, 0.0)
const AIM: Vector3 = Vector3(0.0, 1.2, -10.0)


func test_snaps_to_an_enemy_inside_the_cone() -> void:
	var enemy: Node3D = _enemy(Vector3(1.0, 0.0, -10.0))  # ~5.7° off the aim line
	var result: Vector3 = AimAssist.apply(ORIGIN, AIM, [enemy], 12.0, 30.0)
	assert_eq(result, enemy.global_position + Vector3.UP * AimAssist.CHEST)


func test_ignores_enemies_outside_the_cone_or_range() -> void:
	var wide: Node3D = _enemy(Vector3(6.0, 0.0, -10.0))  # ~31°
	var far: Node3D = _enemy(Vector3(0.0, 0.0, -50.0))
	assert_eq(AimAssist.apply(ORIGIN, AIM, [wide, far], 12.0, 30.0), AIM)


func test_picks_the_smallest_angle() -> void:
	var near_line: Node3D = _enemy(Vector3(0.3, 0.0, -12.0))
	var off_line: Node3D = _enemy(Vector3(1.5, 0.0, -8.0))
	var result: Vector3 = AimAssist.apply(ORIGIN, AIM, [off_line, near_line], 15.0, 30.0)
	assert_eq(result, near_line.global_position + Vector3.UP * AimAssist.CHEST)


func test_blocked_line_is_skipped() -> void:
	var enemy: Node3D = _enemy(Vector3(0.5, 0.0, -10.0))
	var walls: Callable = func(_from: Vector3, _to: Vector3) -> bool: return false
	assert_eq(AimAssist.apply(ORIGIN, AIM, [enemy], 12.0, 30.0, walls), AIM)


func test_zero_cone_means_off() -> void:
	var enemy: Node3D = _enemy(Vector3(0.0, 0.0, -10.0))
	assert_eq(AimAssist.apply(ORIGIN, AIM, [enemy], 0.0, 30.0), AIM)


func _enemy(pos: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.position = pos
	add_child_autofree(node)
	return node
