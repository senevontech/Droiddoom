class_name ThreatOverlay
extends Control
## Screen-space threat info, drawn in one pass (cheap: no nodes per droid):
## - **Off-screen markers:** a red chevron at the screen edge pointing at each
##   living droid you can't see (GDD §5.1 asks for this in Shoulder mode;
##   useful in Tactical too). Closer droids get bigger, brighter markers.
## - **Droid health bars:** a small bar above every damaged droid on screen.
## Reads living droids from the level's EnemyCoordinator. UI only: it may
## look at the camera, gameplay never does.

## Ignore droids farther than this (m).
const MARKER_RANGE: float = 45.0
const MAX_MARKERS: int = 16
## Markers sit this far inside the screen edge (px).
const EDGE: float = 26.0
const BAR_RANGE: float = 35.0
const BAR_SIZE: Vector2 = Vector2(34.0, 3.0)

## The player (distances are measured from it). Set by the HUD.
var player: Node3D

var _coordinator: EnemyCoordinator


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or player == null or not is_instance_valid(player):
		return
	if not is_instance_valid(_coordinator):
		_coordinator = (
			get_tree().get_first_node_in_group(EnemyCoordinator.GROUP) as EnemyCoordinator
		)
		if _coordinator == null:
			return
	var screen: Rect2 = Rect2(Vector2.ZERO, size)
	var inner: Rect2 = screen.grow(-EDGE)
	var centre: Vector2 = size * 0.5
	var markers: int = 0
	for enemy: Node3D in _coordinator.get_live_enemies():
		var droid: BaseEnemy = enemy as BaseEnemy
		if droid == null or droid.health.is_dead():
			continue
		var distance: float = droid.global_position.distance_to(player.global_position)
		var head: Vector3 = droid.global_position + Vector3.UP * droid.data.hud_bar_height
		var behind: bool = camera.is_position_behind(head)
		var at: Vector2 = camera.unproject_position(head)
		if not behind and screen.has_point(at):
			if distance <= BAR_RANGE and droid.health.get_ratio() < 1.0:
				_draw_bar(at, droid.health.get_ratio())
			continue
		if distance > MARKER_RANGE or markers >= MAX_MARKERS:
			continue
		markers += 1
		var dir: Vector2 = at - centre
		if behind:
			dir = -dir
		if dir.length() < 0.01:
			dir = Vector2.DOWN
		_draw_marker(_edge_point(centre, dir.normalized(), inner), dir.normalized(), distance)


func _draw_bar(at: Vector2, ratio: float) -> void:
	var rect: Rect2 = Rect2(at - Vector2(BAR_SIZE.x * 0.5, BAR_SIZE.y), BAR_SIZE)
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), Holo.RED)


func _draw_marker(at: Vector2, dir: Vector2, distance: float) -> void:
	var near: float = clampf(1.0 - distance / MARKER_RANGE, 0.0, 1.0)
	var length: float = lerpf(7.0, 12.0, near)
	var color: Color = Color(Holo.RED, lerpf(0.4, 1.0, near))
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = at + dir * length * 0.5
	var points: PackedVector2Array = PackedVector2Array(
		[
			tip,
			at - dir * length * 0.5 + side * length * 0.6,
			at - dir * length * 0.15,
			at - dir * length * 0.5 - side * length * 0.6
		]
	)
	draw_colored_polygon(points, color)


## Where the ray from `centre` along `dir` leaves `rect`.
static func _edge_point(centre: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var tx: float = INF
	var ty: float = INF
	if absf(dir.x) > 0.0001:
		tx = ((rect.end.x if dir.x > 0.0 else rect.position.x) - centre.x) / dir.x
	if absf(dir.y) > 0.0001:
		ty = ((rect.end.y if dir.y > 0.0 else rect.position.y) - centre.y) / dir.y
	return centre + dir * minf(tx, ty)
