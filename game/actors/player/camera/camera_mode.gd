class_name BaseCameraMode
extends Node
## Base class for a camera mode (TDD §3.3). A mode owns its own desired camera
## transform and decides how aim works. `CameraRig` blends between modes and
## drives the single Camera3D. Gameplay never talks to modes directly: it asks
## `InputRouter` for move and aim (AGENTS.md rule 6a).

## Set by the rig before `enter()` is called.
var rig: CameraRig


## Called when the mode becomes active. Reset state here.
func enter() -> void:
	pass


## Handles mode-specific input (e.g. mouse look). Returns true if consumed.
func handle_input(_event: InputEvent) -> bool:
	return false


## Advances the mode by one frame.
func update(_delta: float) -> void:
	pass


## Camera transform this mode wants this frame (the rig may be blending to it).
func get_desired_transform() -> Transform3D:
	return Transform3D.IDENTITY


## Field of view this mode wants.
func get_fov() -> float:
	return 60.0


## Radius (m) of the occlusion fade cylinder in this mode.
func get_occlusion_radius() -> float:
	return 0.0


## World-space yaw that "forward" on the move stick maps to.
func get_move_yaw() -> float:
	return 0.0


## World-space point the player is aiming at this frame.
func compute_aim_target() -> Vector3:
	return Vector3.ZERO


## Aim assist half-angle for touch/gamepad in this mode (deg, 0 = none).
func get_aim_assist_cone() -> float:
	return 0.0


## True if the OS mouse cursor should be visible in this mode.
func wants_cursor_visible() -> bool:
	return true
