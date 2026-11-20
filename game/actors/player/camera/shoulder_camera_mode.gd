class_name ShoulderCameraMode
extends BaseCameraMode
## Over-the-shoulder camera (GDD §5.1): mouse or right-stick look, crosshair at
## screen centre, pulled in front of walls by a raycast (a cheap spring arm).
## Aim is the centre-screen ray; the gun converges on the hit point.

var yaw: float = 0.0
var pitch: float = 0.0
var _transform: Transform3D = Transform3D.IDENTITY


func enter() -> void:
	var facing: Vector3 = rig.aim_target - rig.target.global_position
	if Vector2(facing.x, facing.z).length() > 0.3:
		yaw = atan2(-facing.x, -facing.z)
	else:
		yaw = rig.target.global_rotation.y
	pitch = rig.tuning.shoulder_start_pitch_rad
	_transform = _compute_transform()


func handle_input(event: InputEvent) -> bool:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var s: float = rig.tuning.mouse_sensitivity
	_look(-motion.relative.x * s, -motion.relative.y * s)
	return true


func update(delta: float) -> void:
	var stick: Vector2 = InputRouter.get_stick_aim_vector()
	var speed: float = rig.tuning.stick_look_speed * delta
	_look(-stick.x * speed, -stick.y * speed)
	var drag: Vector2 = InputRouter.consume_look_drag() * rig.tuning.touch_look_sensitivity
	_look(-drag.x, -drag.y)
	_transform = _compute_transform()


func get_desired_transform() -> Transform3D:
	return _transform


func get_fov() -> float:
	return rig.tuning.shoulder_fov


func get_aim_assist_cone() -> float:
	return rig.tuning.shoulder_assist_cone_deg


func get_occlusion_radius() -> float:
	return rig.tuning.shoulder_occlusion_radius


func get_move_yaw() -> float:
	return yaw


func compute_aim_target() -> Vector3:
	var forward: Vector3 = -_transform.basis.z
	var pivot: Vector3 = rig.target.global_position + rig.tuning.shoulder_pivot
	var from: Vector3 = aim_ray_start(_transform.origin, forward, pivot)
	var to: Vector3 = _transform.origin + forward * rig.tuning.aim_range
	var hit: Dictionary = rig.raycast(from, to, PhysicsLayers.WORLD | PhysicsLayers.ENEMIES, true)
	return to if hit.is_empty() else hit["position"]


## Start of the centre-screen aim ray: the point on the camera ray level with
## the player, so things between the camera and the player can't be aimed at
## (the player would turn around and shoot backwards).
static func aim_ray_start(camera_pos: Vector3, forward: Vector3, pivot: Vector3) -> Vector3:
	return camera_pos + forward * maxf(0.0, (pivot - camera_pos).dot(forward))


func wants_cursor_visible() -> bool:
	return InputRouter.active_device == InputRouter.Device.TOUCH


func _look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(
		pitch + d_pitch, rig.tuning.shoulder_pitch_min_rad, rig.tuning.shoulder_pitch_max_rad
	)


func _compute_transform() -> Transform3D:
	var t: CameraTuning = rig.tuning
	var pivot: Vector3 = rig.target.global_position + t.shoulder_pivot
	var look: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var eye: Vector3 = pivot + look * t.shoulder_offset
	var hit: Dictionary = rig.raycast(pivot, eye, PhysicsLayers.WORLD)
	if not hit.is_empty():
		eye = (hit["position"] as Vector3) + (pivot - eye).normalized() * t.collision_margin
	return Transform3D(look, eye)
