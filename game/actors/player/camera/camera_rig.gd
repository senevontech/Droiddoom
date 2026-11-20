class_name CameraRig
extends Node3D
## Single-camera rig with switchable modes (TDD §3.3, D-013). The active
## camera mode (BaseCameraMode) supplies the desired transform; the rig blends over
## `tuning.blend_time` on a switch, also blending the move basis so held
## movement doesn't jerk. Registers with InputRouter, which serves aim to gameplay.
## Camera shake (P1-13) is trauma-based and applied after aim is computed,
## so shaking never moves the aim; it runs on real time (not slowed by
## Neural Sync) and respects `Settings.screen_shake_enabled`.

## Node the camera follows (HOLLOW).
@export var target: Node3D
## Feel values for both modes.
@export var tuning: CameraTuning
## Tactical camera yaw for this sector (deg). Set per sector so the camera
## looks along streets, not into facades.
@export var tactical_yaw_deg: float = 0.0

## Aim point computed this frame (world space).
var aim_target: Vector3 = Vector3.ZERO

var _modes: Dictionary = {}
var _active: BaseCameraMode
var _blend: float = 1.0
var _blend_from: Transform3D = Transform3D.IDENTITY
var _blend_fov_from: float = 60.0
var _blend_radius_from: float = 0.0
var _occlusion_radius: float = 0.0
var _move_yaw: float = 0.0
var _move_yaw_from: float = 0.0
var _exclude: Array[RID] = []
var _trauma: float = 0.0
var _shake_time: float = 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_modes[Settings.CameraMode.TACTICAL] = $Tactical
	_modes[Settings.CameraMode.SHOULDER] = $Shoulder
	for mode: BaseCameraMode in _modes.values():
		mode.rig = self
	var body: CollisionObject3D = target as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())
	aim_target = target.global_position - target.global_basis.z * 5.0
	camera.current = true
	InputRouter.register_camera_rig(self)
	EventBus.camera_mode_changed.connect(_on_camera_mode_changed)
	EventBus.input_device_changed.connect(_on_input_device_changed)
	EventBus.explosion_happened.connect(_on_explosion)
	EventBus.player_damaged.connect(
		func(amount: float, _type: int) -> void: add_trauma(amount * tuning.shake_per_damage)
	)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.neural_sync_triggered.connect(
		func(_threats: int) -> void: add_trauma(tuning.shake_neural_sync)
	)
	_switch_to(Settings.camera_mode, false)


func _exit_tree() -> void:
	InputRouter.unregister_camera_rig(self)
	RenderingServer.global_shader_parameter_set(&"occlusion_radius", 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_camera"):
		Settings.toggle_camera_mode()
	elif _active.handle_input(event):
		pass
	elif event.is_action_pressed(&"pause") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed():
		_apply_cursor()
		return
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_active.update(delta)
	var desired: Transform3D = _active.get_desired_transform()
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / maxf(tuning.blend_time, 0.001))
		var w: float = smoothstep(0.0, 1.0, _blend)
		camera.global_transform = _blend_from.interpolate_with(desired, w)
		camera.fov = lerpf(_blend_fov_from, _active.get_fov(), w)
		_move_yaw = lerp_angle(_move_yaw_from, _active.get_move_yaw(), w)
		_occlusion_radius = lerpf(_blend_radius_from, _active.get_occlusion_radius(), w)
	else:
		camera.global_transform = desired
		camera.fov = _active.get_fov()
		_move_yaw = _active.get_move_yaw()
		_occlusion_radius = _active.get_occlusion_radius()
	aim_target = _assist(_active.compute_aim_target())
	_update_occlusion()
	_apply_shake(delta)


## Adds camera shake (0..1, capped at 1). Ignored when shake is off.
func add_trauma(amount: float) -> void:
	if Settings.screen_shake_enabled and amount > 0.0:
		_trauma = minf(1.0, _trauma + amount)


## Current shake trauma (tests, debug).
func get_trauma() -> float:
	return _trauma


func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
	_shake_time += real_delta
	var amount: float = _trauma * _trauma
	var t: float = _shake_time * tuning.shake_frequency
	var angles: Vector3 = (
		Vector3(_wobble(t, 1.0), _wobble(t, 2.0), _wobble(t, 3.0))
		* deg_to_rad(tuning.shake_max_angle_deg)
		* amount
	)
	var offset: Vector3 = (
		Vector3(_wobble(t, 4.0), _wobble(t, 5.0), 0.0) * tuning.shake_max_offset * amount
	)
	camera.global_transform = (
		camera.global_transform * Transform3D(Basis.from_euler(angles), offset)
	)
	_trauma = maxf(0.0, _trauma - tuning.shake_decay * real_delta)


## Smooth pseudo-noise in -1..1 (two sines; `lane` decorrelates axes).
static func _wobble(t: float, lane: float) -> float:
	return sin(t + lane * 12.9) * 0.6 + sin(t * 2.31 + lane * 7.1) * 0.4


func _on_explosion(position: Vector3, radius: float, _type: int) -> void:
	if not is_instance_valid(target):
		return
	var distance: float = position.distance_to(target.global_position)
	var near: float = clampf(1.0 - distance / maxf(radius * 6.0, 0.1), 0.0, 1.0)
	add_trauma(tuning.shake_explosion * near * clampf(radius / 4.0, 0.5, 1.5))


func _on_weapon_fired(weapon: Node3D, _muzzle: Vector3, _direction: Vector3) -> void:
	var gun: Weapon = weapon as Weapon
	if gun != null and gun.wielder == target and gun.data.recoil > 0.0:
		add_trauma(gun.data.recoil * tuning.shake_per_recoil)


## World yaw that "forward" on the move stick maps to (blended during switches).
func get_move_yaw() -> float:
	return _move_yaw


## Current occlusion fade radius (m), blended during switches.
func get_occlusion_radius() -> float:
	return _occlusion_radius


## Name of the active mode, for debug display only. Gameplay must not branch on it.
func get_mode_name() -> String:
	return _active.name


## Raycast that ignores the followed target. `areas` also hits Area3Ds on
## `mask` (enemy hurtboxes), so aim snaps onto targets.
func raycast(from: Vector3, to: Vector3, mask: int, areas: bool = false) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = _exclude
	query.collide_with_areas = areas
	return get_world_3d().direct_space_state.intersect_ray(query)


func _switch_to(mode: Settings.CameraMode, blend: bool) -> void:
	_active = _modes[mode]
	_active.enter()
	if blend:
		_blend = 0.0
		_blend_from = camera.global_transform
		_blend_fov_from = camera.fov
		_move_yaw_from = _move_yaw
		_blend_radius_from = _occlusion_radius
	else:
		_blend = 1.0
		_move_yaw = _active.get_move_yaw()
		_occlusion_radius = _active.get_occlusion_radius()
	_apply_cursor()


## Feeds the kit shader (world/kits/common/kit_fade.gdshader): fade what is
## between the camera and the player.
## Touch and gamepad aim snaps toward a nearby enemy (P1-11); mouse never.
func _assist(aim: Vector3) -> Vector3:
	if InputRouter.active_device == InputRouter.Device.KEYBOARD_MOUSE:
		return aim
	var coordinator: EnemyCoordinator = (
		get_tree().get_first_node_in_group(EnemyCoordinator.GROUP) as EnemyCoordinator
	)
	if coordinator == null:
		return aim
	var origin: Vector3 = target.global_position + Vector3(0.0, tuning.aim_plane_height, 0.0)
	return AimAssist.apply(
		origin,
		aim,
		coordinator.get_live_enemies(),
		_active.get_aim_assist_cone() * Settings.aim_assist * 2.0,
		tuning.assist_range,
		func(from: Vector3, to: Vector3) -> bool:
			return raycast(from, to, PhysicsLayers.WORLD).is_empty()
	)


func _update_occlusion() -> void:
	var focus: Vector3 = target.global_position + Vector3(0.0, tuning.occlusion_target_height, 0.0)
	RenderingServer.global_shader_parameter_set(&"occlusion_target", focus)
	RenderingServer.global_shader_parameter_set(&"occlusion_radius", _occlusion_radius)


func _apply_cursor() -> void:
	if _active.wants_cursor_visible():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif InputRouter.active_device == InputRouter.Device.KEYBOARD_MOUSE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _on_camera_mode_changed(mode: int) -> void:
	_switch_to(mode as Settings.CameraMode, true)


func _on_input_device_changed(_device: int) -> void:
	_apply_cursor()
