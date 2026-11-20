class_name EnemyAttackState
extends EnemyState
## Telegraph (windup) → hit → cooldown, repeated while the target stays in
## range. A hit that was telegraphed always resolves, so dodging out of the
## hit volume during the windup is how the player avoids it.

## Leave the attack once the target is this much farther than attack range.
const RANGE_SLACK: float = 1.15

var _windup: float = 0.0
var _cooldown: float = 0.0


func enter(_previous: StringName) -> void:
	var e: BaseEnemy = enemy()
	e.stop_moving()
	e.face_target = true
	_cooldown = 0.0
	_start_windup()


func exit(_next: StringName) -> void:
	enemy().face_target = false
	enemy().clear_pending_attack()


func update(delta: float) -> void:
	var e: BaseEnemy = enemy()
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			e.clear_pending_attack()
			e.perform_attack()
			_cooldown = e.data.attack_interval
		return
	if not e.is_target_alive():
		machine.change(BaseEnemy.STATE_IDLE)
		return
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	var out_of_range: bool = e.distance_to_target() > e.data.attack_range * RANGE_SLACK
	if out_of_range or (e.data.needs_line_of_sight and not e.has_line_of_sight()):
		machine.change(BaseEnemy.STATE_CHASE)
		return
	_start_windup()


func _start_windup() -> void:
	_windup = maxf(enemy().data.attack_windup, 0.01)
	enemy().telegraph_attack(_windup)
