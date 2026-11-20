class_name EnemyEntry
extends Resource
## One enemy type a wave may spend its point budget on (GDD §7.3).

@export var scene: PackedScene
## Budget points one of these costs (Swarmer 1, Kamikaze 2, Gunner 3).
@export var cost: int = 1
## Relative pick chance among affordable entries.
@export var weight: float = 1.0
