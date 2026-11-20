class_name AimAssist
extends RefCounted
## Light aim assist for touch and gamepad (P1-11). The camera rig asks for
## it after its mode computed the raw aim point: if a living enemy lies inside
## a small cone around the aim direction (and within range, with a clear line
## when a `line_clear` callable is given), the aim snaps to that enemy's
## chest. The closest angle wins. Mouse aim never gets assist.

## Chest height above an enemy's origin that assisted aim goes to (m).
const CHEST: float = 0.8


## Returns the assisted aim point, or `aim` unchanged.
## `cone_deg` = half-angle of the cone; `line_clear(from, to) -> bool`.
static func apply(
	origin: Vector3,
	aim: Vector3,
	candidates: Array[Node3D],
	cone_deg: float,
	max_range: float,
	line_clear: Callable = Callable()
) -> Vector3:
	if cone_deg <= 0.0 or candidates.is_empty():
		return aim
	var dir: Vector3 = aim - origin
	if dir.length() < 0.01:
		return aim
	dir = dir.normalized()
	var best: Vector3 = aim
	var best_angle: float = deg_to_rad(cone_deg)
	for enemy: Node3D in candidates:
		if not is_instance_valid(enemy):
			continue
		var chest: Vector3 = enemy.global_position + Vector3.UP * CHEST
		var to: Vector3 = chest - origin
		var distance: float = to.length()
		if distance < 0.1 or distance > max_range:
			continue
		var angle: float = dir.angle_to(to / distance)
		if angle >= best_angle:
			continue
		if line_clear.is_valid() and not line_clear.call(origin, chest):
			continue
		best_angle = angle
		best = chest
	return best
