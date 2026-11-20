class_name EnemyChaseState
extends EnemyState
## Follows a navigation path to the target. Asks for a new path when the old
## one is stale (see BaseEnemy.needs_repath). Attacks once in range.


func enter(_previous: StringName) -> void:
	var e: BaseEnemy = enemy()
	if e.is_target_alive():
		e.request_path_to(e.get_target_position())


func update(_delta: float) -> void:
	var e: BaseEnemy = enemy()
	if not e.is_target_alive():
		machine.change(BaseEnemy.STATE_IDLE)
		return
	var dist: float = e.distance_to_target()
	if dist > e.data.lose_range:
		machine.change(BaseEnemy.STATE_IDLE)
		return
	if dist <= e.data.attack_range and (not e.data.needs_line_of_sight or e.has_line_of_sight()):
		machine.change(BaseEnemy.STATE_ATTACK)
		return
	if e.needs_repath():
		e.request_path_to(e.get_target_position())
