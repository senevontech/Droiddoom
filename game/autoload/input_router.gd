extends Node
## Detects the active input device and serves camera-agnostic move and aim.
##
## Gameplay asks this autoload for movement and aim and never reads devices or
## cameras directly (AGENTS.md rule 6a). The active `CameraRig` registers here
## and supplies the aim target and the move basis for whichever mode is active.

enum Device { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

const WEAPON_SLOT_ACTIONS: Array[StringName] = [
	&"weapon_slot_1", &"weapon_slot_2", &"weapon_slot_3", &"weapon_slot_4"
]

## Device that produced the most recent meaningful input.
var active_device: Device = Device.KEYBOARD_MOUSE

var _rig: CameraRig
## Touch drag-look accumulated since the camera last read it (pixels).
var _look_drag: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Phones and tablets (native or mobile browsers) start in touch mode.
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		active_device = Device.TOUCH


func _input(event: InputEvent) -> void:
	# Mouse events Godot emulates from touches must not switch to mouse mode.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var device: Device = active_device
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		device = Device.TOUCH
	elif event is InputEventJoypadButton:
		device = Device.GAMEPAD
	elif (
		event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3
	):
		device = Device.GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton:
		device = Device.KEYBOARD_MOUSE
	if device != active_device:
		active_device = device
		EventBus.input_device_changed.emit(device)


## Called by a CameraRig when it enters the tree.
func register_camera_rig(rig: CameraRig) -> void:
	_rig = rig


## Called by a CameraRig when it leaves the tree.
func unregister_camera_rig(rig: CameraRig) -> void:
	if _rig == rig:
		_rig = null


## Movement input as a 2D vector (x = right, y = down/back), length ≤ 1.
func get_move_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


## Movement input in world space (XZ plane, length ≤ 1), relative to the
## active camera. Zero-yaw basis when no camera rig is registered.
func get_move_vector_world() -> Vector3:
	var yaw: float = _rig.get_move_yaw() if _rig != null else 0.0
	return move_to_world(get_move_vector(), yaw)


## Right-stick aim as a 2D vector (gamepad; touch sticks feed the same actions).
func get_stick_aim_vector() -> Vector2:
	return Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")


## True while the primary fire input is held (touch auto-fire comes in P1-11).
func is_primary_fire_held() -> bool:
	return Input.is_action_pressed(&"fire_primary")


## True while the heavy weapon fire input is held.
func is_heavy_fire_held() -> bool:
	return Input.is_action_pressed(&"fire_heavy")


## Primary weapon slot picked this frame (0-based), or -1.
func get_weapon_slot_pressed() -> int:
	for i in WEAPON_SLOT_ACTIONS.size():
		if Input.is_action_just_pressed(WEAPON_SLOT_ACTIONS[i]):
			return i
	return -1


## +1 / -1 when the player cycles the primary weapon this frame, else 0.
func get_weapon_cycle() -> int:
	if Input.is_action_just_pressed(&"weapon_next"):
		return 1
	if Input.is_action_just_pressed(&"weapon_prev"):
		return -1
	return 0


## True on the frame the player cycles the heavy weapon.
func is_heavy_cycle_pressed() -> bool:
	return Input.is_action_just_pressed(&"heavy_next")


## True on the frame the player asks for a dash (ability: Space/Shift, A/RB,
## touch DASH).
func is_dash_pressed() -> bool:
	return Input.is_action_just_pressed(&"ability")


## True on the frame the player asks for a reload.
func is_reload_pressed() -> bool:
	return Input.is_action_just_pressed(&"reload")


## Touch controls add drag-look here (pixels); the Shoulder camera reads it.
func add_look_drag(pixels: Vector2) -> void:
	_look_drag += pixels


## Returns the drag-look since the last call and clears it.
func consume_look_drag() -> Vector2:
	var drag: Vector2 = _look_drag
	_look_drag = Vector2.ZERO
	return drag


## World-space point the player is aiming at. `Vector3.ZERO` with no camera rig.
func get_aim_target() -> Vector3:
	return _rig.aim_target if _rig != null else Vector3.ZERO


## Unit direction from `from` toward the aim target (full 3D).
func get_aim_direction(from: Vector3) -> Vector3:
	var to_target: Vector3 = get_aim_target() - from
	return to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.FORWARD


## Converts a 2D move vector (x right, y back) to world XZ, rotated by `yaw`.
static func move_to_world(move: Vector2, yaw: float) -> Vector3:
	return Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, yaw)
