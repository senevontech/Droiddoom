class_name WaveSet
extends Resource
## The waves of one arena or mission section (GDD §7.3). After the last
## wave the set keeps going (endless): the last wave repeats with its budget
## multiplied by `endless_growth` per extra wave.

@export var waves: Array[WaveData] = []
## Budget multiplier for each wave past the end of `waves`.
@export var endless_growth: float = 1.2
## Seconds before the first wave.
@export var first_delay: float = 3.0
## Seconds of calm between waves.
@export var break_time: float = 6.0
## Share of max HP repaired when a wave is cleared (0..1).
@export_range(0.0, 1.0, 0.05) var repair_on_clear: float = 0.35
## Refill every weapon's ammo when a wave is cleared.
@export var refill_ammo_on_clear: bool = true
## Spawn points closer than this to the player are skipped if others exist (m).
@export var min_spawn_distance: float = 14.0
