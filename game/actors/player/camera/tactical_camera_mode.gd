class_name TacticalCameraMode
extends BaseCameraMode
## High-angle chase camera (GDD §5.1): fixed pitch and yaw, look-ahead toward
## the aim, smoothed follow. Mouse aims at what the cursor points at; a stick
## aims along the ground relative to the camera yaw.

## Hit normals steeper than this count as ground (aim at gun height instead).
const GROUND_NORMAL_Y: float = 0.7

var _transform: Transform3D = Transform3D.IDENTITY
## Last stick aim direction in camera space (x right, y down/back).
var _stick_dir: Vector2 = Vector2(0.0, -1.0)


func enter() -> void:
	_transform = _target_transform()


func update(delta: float) -> void:
	var weight: float = minf(1.0, delta * rig.tuning.tactical_smoothing)
	_transform = _transform.interpolate_with(_target_transform(), weight)


func get_desired_transform() -> Transform3D:
	return _transform


func get_fov() -> float:
	return rig.tuning.tactical_fov


func get_occlusion_radius() -> float:
	return rig.tuning.tactical_occlusion_radius


func get_move_yaw() -> float:
	return deg_to_rad(rig.tactical_yaw_deg)


func get_aim_assist_cone() -> float:
	return rig.tuning.tactical_assist_cone_deg


func compute_aim_target() -> Vector3:
	var t: CameraTuning = rig.tuning
	var origin: Vector3 = rig.target.global_position
	if InputRouter.active_device != InputRouter.Device.KEYBOARD_MOUSE:
		var stick: Vector2 = InputRouter.get_stick_aim_vector()
		if stick.length() > t.stick_deadzone:
			_stick_dir = stick.normalized()
		return stick_aim_point(
			origin, _stick_dir, get_move_yaw(), t.stick_aim_distance, t.aim_plane_height
		)
	var camera: Camera3D = rig.camera
	var mouse: Vector2 = rig.get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse)
	var hit: Dictionary = rig.raycast(
		ray_origin, ray_origin + ray_dir * 200.0, PhysicsLayers.WORLD | PhysicsLayers.ENEMIES, true
	)
	# Cursor on a wall or an enemy: aim right at it. Cursor on the ground: aim
	# at gun height above that spot, so shots fly level (twin-stick feel).
	if not hit.is_empty() and (hit["normal"] as Vector3).y < GROUND_NORMAL_Y:
		return hit["position"]
	var plane: Plane = Plane(Vector3.UP, origin.y + t.aim_plane_height)
	var on_plane: Variant = plane.intersects_ray(ray_origin, ray_dir)
	return on_plane if on_plane != null else origin + Vector3(0.0, t.aim_plane_height, 0.0)


func wants_cursor_visible() -> bool:
	return InputRouter.active_device == InputRouter.Device.KEYBOARD_MOUSE


## Camera transform looking at `focus` from `distance` metres away, `pitch_deg`
## above the horizon, rotated `yaw` radians around Y (yaw 0 = camera on +Z).
static func compute_transform(
	focus: Vector3, pitch_deg: float, distance: float, yaw: float
) -> Transform3D:
	var pitch: float = deg_to_rad(pitch_deg)
	var offset: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)) * distance
	var eye: Vector3 = focus + offset.rotated(Vector3.UP, yaw)
	return Transform3D(Basis(), eye).looking_at(focus, Vector3.UP)


## Aim point for a stick: the stick direction (camera space) turned by the
## camera yaw, `distance` metres from `origin`, at `height` above it.
static func stick_aim_point(
	origin: Vector3, stick_dir: Vector2, yaw: float, distance: float, height: float
) -> Vector3:
	var dir: Vector3 = Vector3(stick_dir.x, 0.0, stick_dir.y).normalized().rotated(Vector3.UP, yaw)
	return origin + dir * distance + Vector3(0.0, height, 0.0)


func _target_transform() -> Transform3D:
	var t: CameraTuning = rig.tuning
	var player: Vector3 = rig.target.global_position
	var ahead: Vector3 = (rig.aim_target - player) * t.tactical_look_ahead_factor
	ahead.y = 0.0
	var focus: Vector3 = player + ahead.limit_length(t.tactical_look_ahead_max) + Vector3.UP
	return compute_transform(focus, t.tactical_pitch_deg, t.tactical_distance, get_move_yaw())
