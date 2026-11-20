class_name GunnerEnemy
extends BaseEnemy
## Ranged AXIOM droid (P1-09, GDD §6). Keeps its distance (`stop_distance`,
## backs off inside `retreat_distance`), needs line of sight, and after a
## telegraph at the gun (the muzzle glows) fires a burst of slow, visible
## energy bolts through the ProjectileSystem, so the player can sidestep them
## (and, later, Neural Sync off them). Aims at the target's chest without
## leading it: moving targets are hard to hit, standing still is punished.
##
## Scene contract (on top of BaseEnemy's): `Visuals/Gun` (Weapon).

## Who AXIOM's guns are allowed to hurt.
const TARGETS: int = PhysicsLayers.PLAYER | PhysicsLayers.ALLIES

var _burst_left: int = 0
var _burst_timer: float = 0.0

@onready var gun: Weapon = $Visuals/Gun


func _ready() -> void:
	super()
	gun.wielder = self
	gun.target_mask = TARGETS
	gun.set_exclude([get_rid()])


func _physics_process(delta: float) -> void:
	super(delta)
	if _burst_left <= 0:
		return
	if health.is_dead() or get_state() == STATE_STUNNED:
		_burst_left = 0
		return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_fire_once()


## Ranged: its bolts are tracked in flight for Neural Sync, not its windup.
func get_threat_reach() -> float:
	return 0.0


## Starts a burst of `data.attack_burst` shots.
func perform_attack() -> void:
	_burst_left = maxi(1, data.attack_burst)
	_fire_once()
	attacked.emit()


func _fire_once() -> void:
	_burst_left -= 1
	_burst_timer = data.attack_burst_gap
	if not is_target_alive():
		_burst_left = 0
		return
	gun.try_fire(gun.global_position, target.global_position + Vector3.UP * TARGET_CHEST)
