class_name EnemyIdleState
extends EnemyState
## Stands still until it sees a living target inside sight range. Spotting
## the target also alerts nearby idle droids (BaseEnemy.notice_target, D-029).


func enter(_previous: StringName) -> void:
	enemy().stop_moving()


func update(_delta: float) -> void:
	var e: BaseEnemy = enemy()
	if not e.is_target_alive():
		return
	if e.distance_to_target() <= e.data.sight_range and e.has_line_of_sight():
		e.notice_target()
