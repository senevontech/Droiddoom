class_name EnemyStunnedState
extends EnemyState
## Frozen while `BaseEnemy.stun_time` > 0 (EMP, later the Reclaim window),
## then back to the chase. Counting down on the enemy lets a second stun
## extend the first one.


func enter(_previous: StringName) -> void:
	enemy().stop_moving()


func exit(_next: StringName) -> void:
	enemy().stun_time = 0.0


func update(delta: float) -> void:
	var e: BaseEnemy = enemy()
	e.stun_time -= delta
	if e.stun_time > 0.0:
		return
	machine.change(BaseEnemy.STATE_CHASE if e.is_target_alive() else BaseEnemy.STATE_IDLE)
