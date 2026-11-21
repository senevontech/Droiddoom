class_name Hollow
extends CharacterBody3D
## HOLLOW, the player droid (P1-02). Camera-relative movement with
## acceleration and friction. The legs turn toward the move direction, the
## turret (upper body) turns toward the aim independently. Move and aim come
## from InputRouter only, so this works the same in every camera mode.
## Weapons: primaries (fire_primary, slots 1–4 / cycle) and heavies
## (fire_heavy, cycle), built from the loadout data at spawn (D-030).
## Dash (ability): burst + i-frames + cooldown, with Neural Sync detection.
## A perfect dash starts the Neural Sync reward (P1-13): the world slows
## (Engine.time_scale), HOLLOW keeps most of its real-time speed and fire
## rate (`neural_sync_haste`) and its weapons deal bonus damage. The reward
## runs on real time and always restores time when it ends, on death or when
## HOLLOW leaves the tree.

## The equipped weapons changed (HUD listens).
signal weapons_changed(primary: Weapon, heavy: Weapon)
## A dash started (P1-12). `perfect` = it dodged a hit about to land (Neural Sync).
signal dashed(direction: Vector3, perfect: bool)

## Enemies find the player through this group (BaseEnemy.TARGET_GROUP).
const PLAYER_GROUP: StringName = &"player"
## Seconds HOLLOW's wreck lies around after death.
const WRECK_TIME: float = 30.0
## Shots never aim closer than this to the muzzle (m) (P1-32 shot-angle fix).
const MIN_AIM_DISTANCE: float = 4.0
## Aim more than this far off the barrel (turret still turning, cursor beside
## or behind the gun) fires straight along the barrel instead (degrees).
const MAX_CONVERGE_DEG: float = 20.0

@export var stats: PlayerStats
## Primary weapons in slot order (slot 1 is equipped at spawn).
@export var primary_loadout: Array[WeaponData] = []
## Heavy weapons (limited ammo), cycled with heavy_next.
@export var heavy_loadout: Array[WeaponData] = []

## Equipped primary weapon (null if the loadout is empty).
var weapon: Weapon
## Equipped heavy weapon (null if the loadout is empty).
var heavy_weapon: Weapon

## Dash timing, i-frames and cooldown (P1-12).
var dash: DashMotor = DashMotor.new()
## True = every weapon is usable, whatever the Senevon account has (benchmark).
## Call refresh_unlocks() after changing it.
var ignore_unlocks: bool = false

var _dash_requested: bool = false
## Real-time msec when the Neural Sync reward ends, -1 = not active.
var _sync_end_msec: int = -1
var _hit_flash: HitFlash
## Procedural walk (P1-32): hips, knees and a torso bob.
var _gait: Gait
var _primaries: Array[Weapon] = []
var _heavies: Array[Weapon] = []

## Player health. Max comes from `stats.max_hp`.
@onready var health: HealthComponent = $Health
@onready var _legs: Node3D = $Legs
@onready var _turret: Node3D = $Turret
@onready var _muzzle: Marker3D = $Turret/Muzzle


func _ready() -> void:
	add_to_group(PLAYER_GROUP)
	health.max_health = stats.max_hp
	health.reset()
	dash.configure(stats)
	_gait = Gait.new(
		[$Legs/HipL as Node3D, $Legs/HipR as Node3D],
		[$Legs/HipL/KneeL as Node3D, $Legs/HipR/KneeR as Node3D],
		_turret
	)
	_gait.rate = stats.gait_rate
	_gait.swing = stats.gait_swing
	_gait.knee_bend = stats.gait_knee
	_gait.bob = stats.gait_bob
	# Legs and turret each become one mesh per material (draw calls, P1-25).
	MeshMerger.merge_tree(_legs)
	MeshMerger.merge_tree(_turret)
	_hit_flash = HitFlash.new(self)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	for data: WeaponData in primary_loadout:
		_primaries.append(_mount_weapon(data))
	for data: WeaponData in heavy_loadout:
		_heavies.append(_mount_weapon(data))
	# Paid weapons stay mounted but can't be equipped until unlocked (D-035).
	weapon = _first_unlocked(_primaries)
	heavy_weapon = _first_unlocked(_heavies)
	Senevon.state_changed.connect(refresh_unlocks)


func _physics_process(delta: float) -> void:
	if health.is_dead():
		return
	dash.update(delta * get_haste())
	if _dash_requested:
		_dash_requested = false
		try_dash()
	health.invulnerable = dash.is_invulnerable()
	var wish: Vector3 = InputRouter.get_move_vector_world() * stats.move_speed
	var flat: Vector3
	if dash.is_dashing():
		flat = dash.get_velocity()
	else:
		flat = step_velocity(
			Vector3(velocity.x, 0.0, velocity.z), wish, stats.acceleration, stats.friction, delta
		)
	# Haste (Neural Sync): cover real-time distance while the world is slowed.
	var haste: float = get_haste()
	velocity.x = flat.x * haste
	velocity.z = flat.z * haste
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= stats.gravity * delta
	move_and_slide()
	velocity.x /= haste
	velocity.z /= haste
	_gait.update(0.0 if dash.is_dashing() else flat.length(), stats.move_speed, delta)
	if flat.length() > 0.5:
		var leg_yaw: float = atan2(-flat.x, -flat.z)
		_legs.rotation.y = rotate_angle_toward(
			_legs.rotation.y, leg_yaw, stats.leg_turn_speed * delta
		)


func _exit_tree() -> void:
	end_neural_sync()


func _process(delta: float) -> void:
	if _sync_end_msec >= 0 and Time.get_ticks_msec() >= _sync_end_msec:
		end_neural_sync()
	var to_aim: Vector3 = InputRouter.get_aim_target() - global_position
	if Vector2(to_aim.x, to_aim.z).length() > 0.3:
		var aim_yaw: float = atan2(-to_aim.x, -to_aim.z) - global_rotation.y
		_turret.rotation.y = rotate_angle_toward(
			_turret.rotation.y, aim_yaw, stats.turret_turn_speed * delta * get_haste()
		)
	if health.is_dead():
		return
	# Latched here: a one-frame tap (touch DASH) can fall between physics steps.
	if InputRouter.is_dash_pressed():
		_dash_requested = true
	_handle_weapon_input()
	var aim: Vector3 = InputRouter.get_aim_target()
	var target: Vector3 = fire_target(get_muzzle_position(), get_turret_forward(), aim)
	if InputRouter.is_primary_fire_held() and weapon != null:
		weapon.try_fire(get_muzzle_position(), target)
	if InputRouter.is_heavy_fire_held() and heavy_weapon != null:
		heavy_weapon.try_fire(get_muzzle_position(), target)


## Dashes along the move input (or the turret's facing with no input). Checks
## for Neural Sync: hits that would have landed within the sync window.
## Returns false if the dash is on cooldown.
func try_dash() -> bool:
	var dir: Vector3 = InputRouter.get_move_vector_world()
	if dir.length() < 0.2:
		dir = get_turret_forward()
	if not dash.start(dir):
		return false
	health.invulnerable = true
	_legs.rotation.y = atan2(-dash.direction.x, -dash.direction.z)
	var threats: int = NeuralSync.count_threats(self, stats.neural_sync_window)
	EventBus.player_dashed.emit(dash.direction)
	if threats > 0:
		start_neural_sync()
		EventBus.neural_sync_triggered.emit(threats)
	dashed.emit(dash.direction, threats > 0)
	return true


## Starts (or extends) the Neural Sync reward.
func start_neural_sync() -> void:
	_sync_end_msec = Time.get_ticks_msec() + roundi(stats.neural_sync_duration * 1000.0)
	Engine.time_scale = stats.neural_sync_time_scale
	var haste: float = get_haste()
	for gun: Weapon in _primaries + _heavies:
		gun.damage_scale = stats.neural_sync_damage_bonus
		gun.time_scale = haste


## True while the Neural Sync reward runs.
func is_neural_synced() -> bool:
	return _sync_end_msec >= 0


## 0..1 of the reward left (HUD).
func get_neural_sync_ratio() -> float:
	if _sync_end_msec < 0:
		return 0.0
	var left: float = (_sync_end_msec - Time.get_ticks_msec()) / 1000.0
	return clampf(left / maxf(stats.neural_sync_duration, 0.001), 0.0, 1.0)


## How much faster than the world HOLLOW runs right now (1 = same speed).
func get_haste() -> float:
	if _sync_end_msec < 0 or Engine.time_scale <= 0.0:
		return 1.0
	return lerpf(1.0, 1.0 / Engine.time_scale, stats.neural_sync_haste)


## Ends the reward and puts time back to normal.
func end_neural_sync() -> void:
	if _sync_end_msec < 0:
		return
	_sync_end_msec = -1
	Engine.time_scale = 1.0
	for gun: Weapon in _primaries + _heavies:
		gun.damage_scale = 1.0
		gun.time_scale = 1.0
	EventBus.neural_sync_ended.emit()


## Equips primary weapon `index` (wraps around). Locked weapons are ignored.
## A reload in progress is lost.
func select_primary(index: int) -> void:
	if _primaries.is_empty():
		return
	var next: Weapon = _primaries[wrapi(index, 0, _primaries.size())]
	if next == weapon or not is_weapon_unlocked(next):
		return
	if weapon != null:
		weapon.cancel_reload()
	weapon = next
	weapons_changed.emit(weapon, heavy_weapon)


## Equips heavy weapon `index` (wraps around). Locked weapons are ignored.
func select_heavy(index: int) -> void:
	if _heavies.is_empty():
		return
	var next: Weapon = _heavies[wrapi(index, 0, _heavies.size())]
	if next == heavy_weapon or not is_weapon_unlocked(next):
		return
	if heavy_weapon != null:
		heavy_weapon.cancel_reload()
	heavy_weapon = next
	weapons_changed.emit(weapon, heavy_weapon)


## True if `gun` is free or the player has unlocked it (Senevon, D-035).
func is_weapon_unlocked(gun: Weapon) -> bool:
	return ignore_unlocks or Senevon.has_item(gun.data.unlock_id)


## Re-checks unlocks (sign-in, purchase, Plus ended): a locked equipped weapon
## is swapped for the first unlocked one; with nothing equipped, picks one.
func refresh_unlocks() -> void:
	var primary: Weapon = weapon
	if primary == null or not is_weapon_unlocked(primary):
		primary = _first_unlocked(_primaries)
	var heavy: Weapon = heavy_weapon
	if heavy == null or not is_weapon_unlocked(heavy):
		heavy = _first_unlocked(_heavies)
	if primary == weapon and heavy == heavy_weapon:
		return
	if weapon != null and primary != weapon:
		weapon.cancel_reload()
	if heavy_weapon != null and heavy != heavy_weapon:
		heavy_weapon.cancel_reload()
	weapon = primary
	heavy_weapon = heavy
	weapons_changed.emit(weapon, heavy_weapon)


## All primary weapons in slot order.
func get_primaries() -> Array[Weapon]:
	return _primaries


## All heavy weapons.
func get_heavies() -> Array[Weapon]:
	return _heavies


## Adds `magazines` magazines to each heavy weapon's reserve (drops).
## Returns the rounds added in total.
func add_heavy_ammo(magazines: int) -> int:
	var added: int = 0
	for gun: Weapon in _heavies:
		added += gun.add_reserve(gun.data.magazine_size * magazines)
	return added


## Full ammo for every weapon (pickups and checkpoints later; dev wave reset now).
func refill_ammo() -> void:
	for w: Weapon in _primaries + _heavies:
		w.refill()


## Takes knockback from a hit (horizontal push, m/s).
func apply_knockback(push: Vector3) -> void:
	velocity.x += push.x
	velocity.z += push.z


## World position where shots start.
func get_muzzle_position() -> Vector3:
	return _muzzle.global_position


## Where shots really go (P1-32): the aim point, unless it would send rounds
## out of the barrel sideways, backwards or steeply into the ground. Aim
## within MIN_AIM_DISTANCE, or more than MAX_CONVERGE_DEG off the barrel
## (fast flick, cursor beside the gun), fires along the barrel instead, at
## the aim's height (eased toward muzzle height when very close).
static func fire_target(muzzle: Vector3, barrel: Vector3, aim: Vector3) -> Vector3:
	var forward: Vector3 = Vector3(barrel.x, 0.0, barrel.z)
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var flat: Vector3 = Vector3(aim.x - muzzle.x, 0.0, aim.z - muzzle.z)
	var distance: float = flat.length()
	var aligned: bool = (
		distance > 0.01 and forward.angle_to(flat / distance) <= deg_to_rad(MAX_CONVERGE_DEG)
	)
	if aligned and distance >= MIN_AIM_DISTANCE:
		return aim
	var reach: float = maxf(distance, MIN_AIM_DISTANCE)
	var height: float = lerpf(muzzle.y, aim.y, clampf(distance / MIN_AIM_DISTANCE, 0.0, 1.0))
	var target: Vector3 = muzzle + forward * reach
	target.y = height
	return target


## Horizontal direction the turret faces (unit vector).
func get_turret_forward() -> Vector3:
	return -_turret.global_basis.z


## Moves `current` horizontal velocity toward `wish`: accelerates while there is
## move input, brakes with friction when there is none.
static func step_velocity(
	current: Vector3, wish: Vector3, accel: float, friction: float, delta: float
) -> Vector3:
	var rate: float = accel if wish.length_squared() > 0.0001 else friction
	return current.move_toward(wish, rate * delta)


## Turns angle `from` toward `to` by at most `max_step` radians (shortest way).
static func rotate_angle_toward(from: float, to: float, max_step: float) -> float:
	var diff: float = wrapf(to - from, -PI, PI)
	if absf(diff) <= max_step:
		return wrapf(to, -PI, PI)
	return wrapf(from + signf(diff) * max_step, -PI, PI)


func _on_damaged(info: DamageInfo, final_amount: float) -> void:
	_hit_flash.flash(self)
	if info.knockback != Vector3.ZERO:
		apply_knockback(info.knockback)
	EventBus.player_damaged.emit(final_amount, info.type)


func _on_died(info: DamageInfo) -> void:
	dash.cancel()
	end_neural_sync()
	_hit_flash.clear()
	# The wreck no longer blocks or can be hit; droids lose their target.
	collision_layer = 0
	for child: Node in get_children():
		var hurtbox: HurtboxComponent = child as HurtboxComponent
		if hurtbox != null:
			hurtbox.collision_layer = 0
	# Break apart like the droids do (D-031); legs and turret are separate parts.
	var push: Vector3 = info.impulse if info.impulse != Vector3.ZERO else info.knockback
	var debris: DebrisSystem = DebrisSystem.find_or_create(self)
	debris.shatter(_legs, push, velocity, WRECK_TIME)
	debris.shatter(_turret, push, velocity, WRECK_TIME)
	velocity = Vector3.ZERO
	EventBus.player_died.emit()


func _handle_weapon_input() -> void:
	var slot: int = InputRouter.get_weapon_slot_pressed()
	if slot >= 0 and slot < _primaries.size():
		select_primary(slot)
	var cycle: int = InputRouter.get_weapon_cycle()
	if cycle != 0:
		select_primary(_next_unlocked_index(_primaries, weapon, cycle))
	if InputRouter.is_heavy_cycle_pressed():
		select_heavy(_next_unlocked_index(_heavies, heavy_weapon, 1))
	if InputRouter.is_reload_pressed() and weapon != null:
		weapon.start_reload()


func _first_unlocked(list: Array[Weapon]) -> Weapon:
	for gun: Weapon in list:
		if is_weapon_unlocked(gun):
			return gun
	return null


## Index of the next unlocked weapon `step` away from `current` (skips locked
## ones). Returns the current index when no other weapon is unlocked.
func _next_unlocked_index(list: Array[Weapon], current: Weapon, step: int) -> int:
	var start: int = list.find(current)
	for i: int in range(1, list.size() + 1):
		var idx: int = wrapi(start + step * i, 0, list.size())
		if is_weapon_unlocked(list[idx]):
			return idx
	return start


func _mount_weapon(data: WeaponData) -> Weapon:
	var gun: Weapon = Weapon.new()
	gun.name = data.name_key.to_pascal_case()
	# A runtime copy: upgrades change it, never the file.
	gun.data = data.duplicate()
	gun.target_mask = PhysicsLayers.ENEMIES
	gun.wielder = self
	_muzzle.add_child(gun)
	gun.set_exclude([get_rid()])
	gun.fired.connect(_on_weapon_fired.bind(gun))
	return gun


func _on_weapon_fired(_from: Vector3, direction: Vector3, gun: Weapon) -> void:
	if gun.data.recoil > 0.0:
		apply_knockback(-Vector3(direction.x, 0.0, direction.z).normalized() * gun.data.recoil)
