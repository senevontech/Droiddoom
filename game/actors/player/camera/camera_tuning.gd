class_name CameraTuning
extends Resource
## Camera feel values for both camera modes (TDD §3.3). Data lives in
## `data/camera/*.tres`. Angles in degrees unless the name says rad.

@export_group("Tactical")
## Downward angle of the high camera.
@export var tactical_pitch_deg: float = 55.0
## Distance from the focus point to the camera.
@export var tactical_distance: float = 14.0
## Field of view in Tactical mode.
@export var tactical_fov: float = 50.0
## Share of the player→aim vector the camera leans toward.
@export var tactical_look_ahead_factor: float = 0.25
## Maximum look-ahead distance (m).
@export var tactical_look_ahead_max: float = 3.0
## Follow smoothing (higher = snappier).
@export var tactical_smoothing: float = 8.0
## Occlusion fade radius around the camera→player line (m).
@export var tactical_occlusion_radius: float = 3.0
## Gamepad/touch aim: distance of the aim point from the player (m).
@export var stick_aim_distance: float = 8.0
## Stick deflection below this keeps the last aim direction.
@export var stick_deadzone: float = 0.25
## Aim assist cone half-angle for touch/gamepad in Tactical (deg, 0 = off),
## at the default strength (Settings.aim_assist 0.5; 1.0 doubles it).
@export var tactical_assist_cone_deg: float = 12.0

@export_group("Shoulder")
## Point the camera orbits around, relative to the player's feet.
@export var shoulder_pivot: Vector3 = Vector3(0.0, 1.6, 0.0)
## Camera offset from the pivot (right, up, back).
@export var shoulder_offset: Vector3 = Vector3(0.8, 0.4, 3.4)
## Field of view in Shoulder mode.
@export var shoulder_fov: float = 70.0
## Pitch limits (rad). Negative looks down.
@export var shoulder_pitch_min_rad: float = -0.6
@export var shoulder_pitch_max_rad: float = 0.35
## Pitch when entering Shoulder mode (rad).
@export var shoulder_start_pitch_rad: float = -0.15
## Mouse look: radians per pixel.
@export var mouse_sensitivity: float = 0.0025
## Stick look: radians per second at full deflection.
@export var stick_look_speed: float = 2.5
## Touch drag-look turn per screen pixel (rad).
@export var touch_look_sensitivity: float = 0.006
## Aim assist cone half-angle for touch/gamepad in Shoulder (deg, 0 = off).
@export var shoulder_assist_cone_deg: float = 5.0
## Occlusion fade radius around the camera→player line (m).
@export var shoulder_occlusion_radius: float = 1.0
## Gap kept between the camera and a wall it is pulled in by (m).
@export var collision_margin: float = 0.2

@export_group("Shared")
## Mode switch blend time (s).
@export var blend_time: float = 0.3
## Maximum aim raycast distance (m).
@export var aim_range: float = 60.0
## Height above the player's feet that occlusion fade keeps visible (m).
@export var occlusion_target_height: float = 1.1
## Height of the fallback aim plane above the player's feet (m).
@export var aim_plane_height: float = 1.2
## Aim assist only considers enemies this close (m).
@export var assist_range: float = 30.0
## Touch auto-fire (P1-31) shoots while a droid is within this many degrees
## of the (assisted) aim line, within `assist_range` and in clear view.
@export var auto_fire_cone_deg: float = 4.0

@export_group("Shake")
## Camera shake (P1-13, Settings.screen_shake_enabled turns it off). Shake =
## trauma² × these maxima; trauma (0..1) is added by events and decays.
@export var shake_max_angle_deg: float = 2.2
@export var shake_max_offset: float = 0.22
## Trauma lost per real second.
@export var shake_decay: float = 1.8
## Wobble speed (Hz-ish).
@export var shake_frequency: float = 17.0
## Trauma from a blast at point-blank (scaled by radius, fades out at 6 radii).
@export var shake_explosion: float = 0.55
## Trauma per hull point HOLLOW loses.
@export var shake_per_damage: float = 0.018
## Trauma per m/s of the player's weapon recoil (railgun, scattergun, rockets).
@export var shake_per_recoil: float = 0.07
## Trauma when Neural Sync triggers.
@export var shake_neural_sync: float = 0.3
