class_name HitMarkers
extends Control
## Hit feedback on the crosshair (P1-32 gameplay feel): a quick white X when
## the player's damage lands on a droid (amber for crits / weak spots), a
## bigger red X when the player destroys one. Only reacts to damage the player
## caused (EventBus.enemy_hit / enemy_died with the player as source).

const HIT_TIME: float = 0.12
const KILL_TIME: float = 0.32
const GAP: float = 6.0

## Screen point the markers are drawn around (the reticle centre, set by the HUD).
var centre: Vector2 = Vector2.ZERO

var _hit_left: float = 0.0
var _hit_crit: bool = false
var _kill_left: float = 0.0
var _kills: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.enemy_hit.connect(_on_enemy_hit)
	EventBus.enemy_died.connect(_on_enemy_died)


## Kills confirmed by this widget (tests).
func get_confirmed_kills() -> int:
	return _kills


## True while a marker is showing (tests).
func is_showing() -> bool:
	return _hit_left > 0.0 or _kill_left > 0.0


func _process(delta: float) -> void:
	if not is_showing():
		return
	var real: float = delta / maxf(Engine.time_scale, 0.01)
	_hit_left = maxf(0.0, _hit_left - real)
	_kill_left = maxf(0.0, _kill_left - real)
	queue_redraw()


func _draw() -> void:
	if _kill_left > 0.0:
		var t: float = _kill_left / KILL_TIME
		_draw_x(GAP + 2.0, 9.0 + (1.0 - t) * 4.0, Color(Holo.RED, t), 2.5)
	elif _hit_left > 0.0:
		var t2: float = _hit_left / HIT_TIME
		var color: Color = Holo.AMBER if _hit_crit else Color(1.0, 1.0, 1.0)
		_draw_x(GAP, 6.0, Color(color, t2), 2.0)


func _draw_x(gap: float, length: float, color: Color, width: float) -> void:
	for diagonal: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d: Vector2 = diagonal.normalized()
		var a: Vector2 = centre + d * gap
		var b: Vector2 = centre + d * (gap + length)
		draw_line(a, b, Color(0.0, 0.0, 0.0, color.a * 0.6), width + 2.0, true)
		draw_line(a, b, color, width, true)


func _on_enemy_hit(_enemy: Node, _amount: float, crit: bool, source: Node) -> void:
	if not _is_player(source):
		return
	_hit_left = HIT_TIME
	_hit_crit = crit
	queue_redraw()


func _on_enemy_died(_enemy: Node, killer: Node) -> void:
	if not _is_player(killer):
		return
	_kills += 1
	_kill_left = KILL_TIME
	queue_redraw()


static func _is_player(node: Node) -> bool:
	return is_instance_valid(node) and node.is_in_group(Hollow.PLAYER_GROUP)
