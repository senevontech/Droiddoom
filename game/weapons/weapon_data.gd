class_name WeaponData
extends Resource
## Balance data for one weapon (TDD §3.4). Lives in `data/weapons/*.tres`.
## Upgrades (Phase 2) modify a runtime copy, never the file.

## PROJECTILE = rounds that travel (ProjectileSystem, D-030).
## BEAM = instant ray, drawn as a continuous beam while firing (lasers).
enum FireMode { PROJECTILE, BEAM }

## Translation key for the weapon name.
@export var name_key: String = ""
@export var fire_mode: FireMode = FireMode.PROJECTILE
## Flight data for PROJECTILE weapons.
@export var projectile: ProjectileData
## Direct-hit damage per round (per pellet, per beam tick).
@export var damage: float = 10.0
@export var damage_type: DamageInfo.Type = DamageInfo.Type.KINETIC
## Seconds between shots.
@export var fire_interval: float = 0.12
## Rounds per trigger pull (scattergun pellets).
@export var pellets: int = 1
## Maximum distance a round or beam can reach (m).
@export var max_range: float = 60.0
## Random cone half-angle (degrees).
@export var spread_deg: float = 1.5
## 0..1 chance that a shot crits.
@export_range(0.0, 1.0, 0.01) var crit_chance: float = 0.05
@export var crit_multiplier: float = 2.0
## Push given to the target along the shot (m/s).
@export var knockback: float = 0.0
## Physical shove of each hit (m/s). Drives flinches and how far wrecks fly.
@export var impact_force: float = 2.0

@export_group("Ammo")
## Shots per magazine (heat capacity for beams). 0 = never reloads.
@export var magazine_size: int = 0
## Seconds to reload (or cool down) a magazine.
@export var reload_time: float = 1.5
## Spare rounds carried, -1 = unlimited (primaries). Heavy weapons are limited.
@export var reserve_ammo: int = -1

@export_group("Targeting")
## Homing rounds lock onto the enemy nearest the aim point within this radius (m).
@export var lock_radius: float = 0.0

@export_group("Feedback")
## Enemies within this distance hear the shot (P1-17). 0 = silent.
@export var noise_radius: float = 25.0
## Sound played on each shot (AudioManager name, e.g. &"shot_rifle"). Empty = silent.
@export var fire_sfx: StringName = &""
## Push back on the shooter per shot (m/s, horizontal).
@export var recoil: float = 0.0
## Muzzle flash size (m). 0 = no flash.
@export var muzzle_flash_size: float = 0.35
## Beam thickness (m), BEAM weapons only.
@export var beam_width: float = 0.06
