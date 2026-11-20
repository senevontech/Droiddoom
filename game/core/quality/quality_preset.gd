class_name QualityPreset
extends Resource
## One graphics quality preset (TDD §6.1). Instances live in `data/quality/*.tres`.
##
## Rule (D-022): presets never switch light shadows on/off, because that changes
## light brightness on the Compatibility renderer. They only change shadow size
## and distance.

## Name shown in the UI and the debug overlay.
@export var display_name: String = ""
## Lowest 3D render scale dynamic resolution may use.
@export_range(0.25, 1.0, 0.05) var render_scale_min: float = 0.6
## Highest (and starting) 3D render scale.
@export_range(0.25, 1.0, 0.05) var render_scale_max: float = 1.0
## Frame-rate target. Dynamic resolution keeps frames inside 1000 / target_fps ms.
@export var target_fps: float = 60.0
## 3D MSAA level.
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_DISABLED
## Directional shadow atlas size in pixels (power of two).
@export var directional_shadow_size: int = 2048
## Directional shadow distance in meters. Scenes apply it to their sun.
@export var shadow_max_distance: float = 30.0
## Positional (omni/spot) shadow atlas size in pixels.
@export var positional_shadow_size: int = 1024
## Particle amount multiplier, 0..1.
@export_range(0.0, 1.0, 0.05) var particle_density: float = 0.25
## Cap for live enemies (Wave Director reads this).
@export var max_live_enemies: int = 40
## Cap for simultaneous dynamic lights (muzzle flashes, explosions).
@export var max_dynamic_lights: int = 2
## Physics bodies for droid wreck parts (DebrisSystem pool, D-031).
@export var max_debris_bodies: int = 48
## Glow (bloom) on/off.
@export var glow_enabled: bool = true

@export_group("Enemy AI LOD")
## Enemies closer than this to the player think at `ai_tick_hz_near` (m).
@export var ai_near_distance: float = 15.0
## Enemies closer than this (but past near) think at `ai_tick_hz_mid` (m).
@export var ai_mid_distance: float = 35.0
## AI decisions per second, near / mid / far. Movement still runs every frame.
@export var ai_tick_hz_near: float = 20.0
@export var ai_tick_hz_mid: float = 10.0
@export var ai_tick_hz_far: float = 4.0
## Navigation path queries allowed per physics frame (time slicing).
@export var path_queries_per_frame: int = 6
