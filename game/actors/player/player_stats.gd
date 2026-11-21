class_name PlayerStats
extends Resource
## HOLLOW's base movement and survival stats (P1-02). Upgrades modify a copy at
## mission start. Data lives in `data/player/*.tres`.

## Top run speed (m/s).
@export var move_speed: float = 6.0
## Speed gained per second while moving (m/s²).
@export var acceleration: float = 40.0
## Speed lost per second with no input (m/s²).
@export var friction: float = 30.0
## Downward acceleration (m/s²).
@export var gravity: float = 20.0
## Turret (upper body) turn rate toward the aim (rad/s).
@export var turret_turn_speed: float = 14.0
## Legs turn rate toward the move direction (rad/s).
@export var leg_turn_speed: float = 10.0
## Maximum hit points.
@export var max_hp: float = 100.0

@export_group("Dash")
## Burst speed while dashing (m/s).
@export var dash_speed: float = 16.0
## Length of the burst (s).
@export var dash_time: float = 0.18
## Invulnerable time from the start of the dash (s). Slightly longer than the
## burst so a hit that lands as the dash ends still misses.
@export var dash_iframes: float = 0.24
## Seconds from one dash start to the next.
@export var dash_cooldown: float = 0.8

@export_group("Neural Sync")
## A dash counts as perfect if a hit would have landed within this many
## seconds of the dash starting (GDD §4.4).
@export var neural_sync_window: float = 0.2
## Reward length in real seconds (GDD §4.4: 1.5 s). Another perfect dash extends it.
@export var neural_sync_duration: float = 1.5
## World speed during the reward (Engine.time_scale).
@export_range(0.05, 1.0, 0.05) var neural_sync_time_scale: float = 0.35
## Damage multiplier for HOLLOW's weapons during the reward.
@export var neural_sync_damage_bonus: float = 1.5
## How much of its real-time speed HOLLOW keeps while the world is slowed
## (moving and firing): 0 = slowed like everything else, 1 = full speed.
@export_range(0.0, 1.0, 0.05) var neural_sync_haste: float = 0.7

@export_group("Walk animation")
## Walk cycle radians per metre (Gait.rate).
@export var gait_rate: float = 2.3
## Hip swing (rad).
@export var gait_swing: float = 0.55
## Knee bend (rad).
@export var gait_knee: float = 0.85
## Upper-body bob (m).
@export var gait_bob: float = 0.035
