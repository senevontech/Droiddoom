class_name EnemyData
extends Resource
## Balance data for one enemy type (P1-08, GDD §6). Lives in
## `data/enemies/enemy_<id>.tres`. Hardened variants (AXIOM Adapts) use a
## different `resistances` resource; everything else stays shared.

@export var id: StringName = &""
## Translation key for the enemy name.
@export var name_key: String = ""

@export_group("Survival")
@export var max_hp: float = 40.0
## Damage taken per type. Null = normal damage from everything.
@export var resistances: DamageResistances

@export_group("Movement")
## Top speed (m/s).
@export var move_speed: float = 4.0
## Speed gained or lost per second while steering (m/s²).
@export var acceleration: float = 20.0
## Body turn rate (rad/s).
@export var turn_speed: float = 8.0
@export var gravity: float = 20.0
## Keeps this far from other droids (m), 0 = off. Stops packs merging (P1-18).
@export var separation_radius: float = 0.0
## Push away from close neighbours at full overlap (m/s).
@export var separation_strength: float = 3.0
## Backs away while the target is closer than this (m), 0 = never (Gunner).
@export var retreat_distance: float = 0.0

@export_group("Perception")
## Notices the player within this distance (m), if it has line of sight.
@export var sight_range: float = 25.0
## Gives up the chase beyond this distance (m).
@export var lose_range: float = 45.0
## When this droid spots the player or gets hit, idle droids within this
## distance are alerted too (AXIOM's network, D-029). 0 = no relay (m).
@export var alert_radius: float = 15.0
## Multiplies a weapon's `noise_radius` to get how far away this droid hears
## shots and blasts (P1-17). 0 = deaf.
@export var hearing: float = 1.0
## While chasing, asks for a new path at most this often (s).
@export var repath_interval: float = 0.6
## Also asks for a new path once the target has moved this far from the old goal (m).
@export var repath_distance: float = 2.0

@export_group("Attack")
## Starts an attack within this distance (m).
@export var attack_range: float = 1.6
## Stops moving this close to the target (m). Ranged enemies keep their distance.
@export var stop_distance: float = 1.2
## Telegraph time before the hit lands (s). Must be readable from both cameras.
@export var attack_windup: float = 0.35
## Time between attacks (s), counted from the hit.
@export var attack_interval: float = 1.0
@export var attack_damage: float = 8.0
@export var attack_damage_type: DamageInfo.Type = DamageInfo.Type.KINETIC
## Push given to the victim (m/s).
@export var attack_knockback: float = 3.0
## Ranged attackers need a clear line of fire to attack.
@export var needs_line_of_sight: bool = false
## Shots per attack for ranged droids (GunnerEnemy).
@export var attack_burst: int = 1
## Seconds between shots of a burst.
@export var attack_burst_gap: float = 0.12

@export_group("Self-destruct")
## > 0 = explodes when it dies (Kamikaze; volatile droids). Hurts everyone in
## range, AXIOM included, so a shot Kamikaze can take its pack with it.
@export var death_blast_radius: float = 0.0
@export var death_blast_damage: float = 0.0
@export var death_blast_force: float = 0.0

@export_group("Rewards")
@export var scrap_value: int = 2

@export_group("Walk animation")
## Walk cycle radians per metre (Gait.rate). 0 = no walk animation.
@export var gait_rate: float = 3.0
## Hip swing for droids with `Visuals/HipL`/`HipR` pivots (rad).
@export var gait_swing: float = 0.45
## Body bob per step (m).
@export var gait_bob: float = 0.04

@export_group("Drops")
## Chance (0..1) to drop a repair cell when destroyed (PickupSystem).
@export_range(0.0, 1.0, 0.01) var drop_repair_chance: float = 0.0
## Chance (0..1) to drop heavy ammo when destroyed.
@export_range(0.0, 1.0, 0.01) var drop_ammo_chance: float = 0.0

@export_group("HUD")
## Height above the droid's origin where its health bar is drawn (m).
@export var hud_bar_height: float = 1.6

@export_group("Damage")
## Below this share of max HP the droid is crippled: it smokes and limps.
@export_range(0.0, 1.0, 0.05) var cripple_ratio: float = 0.35
## Move speed multiplier while crippled.
@export var crippled_speed: float = 0.7
## How far a hit leans the body (radians per m/s of impulse, capped).
@export var flinch_per_impulse: float = 0.06

@export_group("Death")
## Seconds the wreck stays before it's removed (used when it can't shatter).
@export var corpse_time: float = 3.0
## Seconds the shattered parts lie around before they sink away.
@export var wreck_time: float = 10.0
