class_name ProjectileData
extends Resource
## How a fired round flies (D-030). Lives in `data/projectiles/*.tres` and is
## referenced by WeaponData. ProjectileSystem moves every round with these
## values: real travel time, gravity drop, air drag, missile thrust and
## homing, bouncing grenades, piercing slugs and explosions.

## Look of the round in flight (ProjectileSystem draws one MultiMesh per look).
## Append only: the index is saved in data files.
enum Visual { TRACER, SLUG, MISSILE, GRENADE, BOLT }

@export var visual: Visual = Visual.TRACER
## Length of the glowing streak drawn behind TRACER and SLUG rounds (m).
@export var streak_length: float = 1.2

@export_group("Flight")
## Muzzle velocity (m/s).
@export var speed: float = 120.0
## 1 = normal gravity. Bullets keep it low-ish so long shots still drop a bit.
@export var gravity_scale: float = 1.0
## Air drag (1/s): speed shrinks by exp(-drag × t). Pellets slow down fast.
@export var drag: float = 0.0
## Seconds before the round disappears (or bursts, if it explodes).
@export var lifetime: float = 1.5
## True = launched on a ballistic arc that lands on the aim point (grenades).
## False = aimed straight, with the sights zeroed at the aim point.
@export var lob: bool = false

@export_group("Missile")
## Forward acceleration (m/s²), 0 = unpowered.
@export var thrust: float = 0.0
## Top speed under thrust (m/s).
@export var max_speed: float = 0.0
## Turn rate toward the locked target (deg/s), 0 = no homing.
@export var homing_turn_deg: float = 0.0
## Seconds of straight flight before homing starts (leaves the pod first).
@export var arm_time: float = 0.0

@export_group("Impact")
## Extra enemies a round passes through (railgun slugs).
@export var pierce: int = 0
## > 0 = bounces off walls and floors, keeping this share of its speed.
@export_range(0.0, 1.0, 0.05) var bounce_restitution: float = 0.0
## > 0 = explodes after this many seconds instead of on hitting a wall
## (a direct hit on an enemy still detonates at once).
@export var fuse_time: float = 0.0

@export_group("Explosion")
## > 0 = the round explodes (on impact, on its fuse, or when its life ends).
@export var explosion_radius: float = 0.0
## Damage at the centre. Falls off to 25% at the edge; walls block it.
@export var explosion_damage: float = 0.0
## Push at the centre (m/s): knockback for actors, launch speed for debris.
@export var explosion_force: float = 0.0


func explodes() -> bool:
	return explosion_radius > 0.0
