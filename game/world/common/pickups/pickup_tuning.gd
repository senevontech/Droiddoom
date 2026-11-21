class_name PickupTuning
extends Resource
## Balance for droid drops (P1-32). Lives in `data/pickups/`.

## Share of max hull a repair cell restores.
@export_range(0.0, 1.0, 0.01) var repair_share: float = 0.15
## Heavy-weapon magazines one ammo crate adds to each heavy weapon's reserve.
@export var ammo_magazines: int = 1
## Seconds a drop stays before vanishing (blinks for the last 3 s).
@export var lifetime: float = 15.0
## Drops slide toward HOLLOW inside this distance (m).
@export var magnet_radius: float = 4.0
## Collected inside this distance (m).
@export var collect_radius: float = 1.1
## Most drops on the ground at once (oldest vanishes).
@export var max_active: int = 12
