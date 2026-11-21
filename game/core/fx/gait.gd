class_name Gait
extends RefCounted
## Procedural walk cycle (P1-32), shared by HOLLOW and the droids. No
## animation assets: the cycle advances with distance travelled, so feet
## don't slide at any speed, and it fades in/out smoothly when starting or
## stopping. Every part is optional:
## - hips swing forward/back in opposite phase (+X rotation = leg forward),
## - knees bend on the leg's way forward,
## - a body node bobs twice per cycle (once per step).
## Cost: a few float ops and transform writes per actor per physics frame.

## Radians of cycle per metre moved (bigger = shorter, quicker steps).
var rate: float = 2.4
## Hip swing amplitude (rad).
var swing: float = 0.5
## Knee bend amplitude (rad).
var knee_bend: float = 0.8
## Body bob height (m).
var bob: float = 0.03

var phase: float = 0.0
## 0 = standing, 1 = full stride.
var amount: float = 0.0

var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _body: Node3D
var _body_rest: Vector3 = Vector3.ZERO


## `hips`/`knees` = [left, right] pivots (or empty); `body` bobs (or null).
func _init(hips: Array[Node3D], knees: Array[Node3D], body: Node3D) -> void:
	_hips = hips
	_knees = knees
	_body = body
	if _body != null:
		_body_rest = _body.position


## Advances the cycle by `speed` m/s for `delta` s (`top_speed` = full stride).
func update(speed: float, top_speed: float, delta: float) -> void:
	var target: float = clampf(speed / maxf(top_speed, 0.01), 0.0, 1.0)
	amount = move_toward(amount, target, delta * 5.0)
	phase = fmod(phase + speed * delta * rate, TAU)
	if amount < 0.001 and is_zero_approx(target):
		phase = move_toward(phase, 0.0, delta * 3.0)
	var s: float = sin(phase)
	for i in _hips.size():
		var side: float = 1.0 if i == 0 else -1.0
		if is_instance_valid(_hips[i]):
			_hips[i].rotation.x = s * side * swing * amount
	for i in _knees.size():
		var side_phase: float = phase if i == 0 else phase + PI
		if is_instance_valid(_knees[i]):
			# Bend while the leg swings forward, straight while it pushes off.
			_knees[i].rotation.x = -maxf(0.0, cos(side_phase)) * knee_bend * amount
	if is_instance_valid(_body):
		_body.position = _body_rest + Vector3.UP * absf(cos(phase)) * bob * amount


## The body offset currently applied (tests).
func get_body_offset() -> float:
	return _body.position.y - _body_rest.y if is_instance_valid(_body) else 0.0
