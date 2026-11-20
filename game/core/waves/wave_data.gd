class_name WaveData
extends Resource
## One wave of the Wave Director (GDD §7.3): a point budget spent on random
## picks from an enemy pool, delivered in bursts.

## Points to spend on enemies this wave.
@export var budget: int = 10
@export var pool: Array[EnemyEntry] = []
## Droids per burst (one spawn point per burst).
@export var burst_size: int = 3
## Seconds between bursts.
@export var burst_interval: float = 2.0
