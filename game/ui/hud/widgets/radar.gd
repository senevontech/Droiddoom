class_name Radar
extends Control
## Small round radar (sleek HUD, P1-30). Up = where the camera looks, so it
## matches the screen in both camera modes (UI may read the camera; gameplay
## never does). A cyan cone shows the view direction, red dots are living
## droids within RANGE, droids beyond it sit on the rim as small ticks.
## One draw pass, no nodes per droid.

## Metres from the centre to the rim.
const RANGE: float = 32.0
const DOT: float = 2.6

## The player (radar centre). Set by the HUD.
var player: Node3D

var _coordinator: EnemyCoordinator


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 2.0
	# The frosted card behind provides the background (P1-32).
	draw_arc(c, r * 0.97, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.08), 1.0, true)
	draw_arc(c, r * 0.5, 0.0, TAU, 32, Color(Holo.CYAN, 0.12), 1.0, true)
	draw_line(c - Vector2(r, 0.0), c + Vector2(r, 0.0), Color(Holo.CYAN, 0.08), 1.0)
	draw_line(c - Vector2(0.0, r), c + Vector2(0.0, r), Color(Holo.CYAN, 0.08), 1.0)
	# View cone (up = camera forward).
	var cone: PackedVector2Array = PackedVector2Array([c])
	for i in 9:
		var a: float = -PI * 0.5 + deg_to_rad(-30.0 + 7.5 * i)
		cone.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(cone, Color(Holo.CYAN, 0.08))
	_draw_droids(c, r)
	# The player: a small chevron pointing up.
	var me: PackedVector2Array = PackedVector2Array(
		[
			c + Vector2(0.0, -5.0),
			c + Vector2(4.0, 4.0),
			c + Vector2(0.0, 2.0),
			c + Vector2(-4.0, 4.0)
		]
	)
	draw_colored_polygon(me, Holo.WHITE)


func _draw_droids(c: Vector2, r: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or player == null or not is_instance_valid(player):
		return
	if not is_instance_valid(_coordinator):
		_coordinator = (
			get_tree().get_first_node_in_group(EnemyCoordinator.GROUP) as EnemyCoordinator
		)
		if _coordinator == null:
			return
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	for enemy: Node3D in _coordinator.get_live_enemies():
		var rel: Vector3 = enemy.global_position - player.global_position
		var at: Vector2 = Vector2(rel.dot(right), -rel.dot(forward)) * (r / RANGE)
		if at.length() > r - 3.0:
			var rim: Vector2 = at.normalized()
			draw_line(c + rim * (r - 5.0), c + rim * (r - 1.0), Color(Holo.RED, 0.8), 2.0)
		else:
			draw_circle(c + at, DOT, Holo.RED)
