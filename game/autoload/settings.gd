extends Node
## Player settings: graphics, audio, accessibility, controls and camera mode.
##
## Stub (P0-04). Persistence comes with SaveManager (P2-08). Settings UI comes in P2-10.

enum CameraMode { TACTICAL, SHOULDER }
## Touch firing (P1-31): AUTO fires by itself while the aim is on a droid
## (FIRE still works); MANUAL fires only while FIRE is held.
enum TouchFireMode { AUTO, MANUAL }

## Active camera mode (D-013). Tactical is the default on every platform for now.
var camera_mode: CameraMode = CameraMode.TACTICAL
## Screen shake on/off (accessibility).
var screen_shake_enabled: bool = true
## Aim assist strength, 0.0 to 1.0.
var aim_assist: float = 0.5

# --- Touch controls (P1-31) ---
var touch_fire_mode: TouchFireMode = TouchFireMode.AUTO
## Multiplies the Shoulder drag-look speed (0.4–2.5).
var touch_look_sensitivity: float = 1.0
## Multiplies touch button and stick sizes (0.75–1.4).
var touch_button_scale: float = 1.0
## Opacity of the touch controls (0.25–1).
var touch_opacity: float = 0.8


## Changes one setting by name and tells listeners (EventBus.settings_changed).
## Values are clamped to their allowed ranges.
func set_value(key: StringName, value: Variant) -> void:
	match key:
		&"touch_fire_mode":
			touch_fire_mode = int(value) as TouchFireMode
		&"touch_look_sensitivity":
			touch_look_sensitivity = clampf(float(value), 0.4, 2.5)
		&"touch_button_scale":
			touch_button_scale = clampf(float(value), 0.75, 1.4)
		&"touch_opacity":
			touch_opacity = clampf(float(value), 0.25, 1.0)
		&"aim_assist":
			aim_assist = clampf(float(value), 0.0, 1.0)
		&"screen_shake_enabled":
			screen_shake_enabled = bool(value)
		_:
			push_error("Settings: unknown key %s" % key)
			return
	EventBus.settings_changed.emit(key)


## Switches the camera mode and notifies listeners via EventBus.
func set_camera_mode(mode: CameraMode) -> void:
	if mode == camera_mode:
		return
	camera_mode = mode
	EventBus.camera_mode_changed.emit(mode)


## Toggles between Tactical and Shoulder.
func toggle_camera_mode() -> void:
	if camera_mode == CameraMode.TACTICAL:
		set_camera_mode(CameraMode.SHOULDER)
	else:
		set_camera_mode(CameraMode.TACTICAL)
