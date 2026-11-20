class_name Ballistics
extends RefCounted
## Launch maths for rounds that fall (D-030). Pure functions, unit-tested.


## Gravity used by every round (project physics setting, m/s²).
static func gravity() -> float:
	return ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


## Velocity for a straight shot whose sights are zeroed at `target`: aimed
## at it, tilted up just enough to cancel the drop over the flight time
## (ignores drag, so drag-heavy pellets still fall short at long range).
static func zeroed_velocity(from: Vector3, target: Vector3, speed: float, g: float) -> Vector3:
	var to_target: Vector3 = target - from
	var distance: float = to_target.length()
	if distance < 0.01 or speed <= 0.0:
		return Vector3.FORWARD * speed
	var velocity: Vector3 = to_target / distance * speed
	velocity.y += 0.5 * g * (distance / speed)
	return velocity.normalized() * speed


## Velocity for a lobbed shot that lands on `target` (lower of the two arcs).
## Out of reach: the 45° arc toward it (maximum range).
static func lob_velocity(from: Vector3, target: Vector3, speed: float, g: float) -> Vector3:
	var flat: Vector3 = Vector3(target.x - from.x, 0.0, target.z - from.z)
	var d: float = flat.length()
	var h: float = target.y - from.y
	var dir: Vector3 = flat / d if d > 0.01 else Vector3.FORWARD
	if d < 0.01:
		return Vector3.UP * speed
	var v2: float = speed * speed
	var root: float = v2 * v2 - g * (g * d * d + 2.0 * h * v2)
	var angle: float = PI / 4.0
	if root >= 0.0 and g > 0.0:
		angle = atan((v2 - sqrt(root)) / (g * d))
	return dir * cos(angle) * speed + Vector3.UP * sin(angle) * speed


## One explicit integration step for a round (the same maths ProjectileSystem
## uses). Returns [new_position, new_velocity].
static func step(
	position: Vector3, velocity: Vector3, g: float, drag: float, delta: float
) -> Array[Vector3]:
	var v: Vector3 = velocity
	v.y -= g * delta
	if drag > 0.0:
		v *= exp(-drag * delta)
	return [position + v * delta, v]
