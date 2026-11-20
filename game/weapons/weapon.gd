class_name Weapon
extends Node3D
## One gun (P1-07, projectiles D-030). The owner decides when to pull the
## trigger and passes the muzzle and the aim point (InputRouter for the
## player, AI for enemies), so the weapon is camera-agnostic.
## - PROJECTILE weapons hand rounds to the level's ProjectileSystem, which
##   flies them with real travel time, drop, drag, thrust and homing.
## - BEAM weapons hit instantly along a ray (Hitscan) and draw a beam.
## Magazines, reloads and limited reserve ammo come from WeaponData.
## Visuals and audio react to EventBus signals; the weapon draws nothing.

signal fired(from: Vector3, direction: Vector3)
signal reload_started(duration: float)
signal reload_finished

## The first ray of a beam starts this far behind the muzzle (point-blank hits).
const BACKCAST: float = 0.9

@export var data: WeaponData
## Faction layers this weapon damages (hurtbox layers).
@export_flags_3d_physics var target_mask: int = PhysicsLayers.ENEMIES
## Who gets credit for hits. Defaults to the parent chain's first actor.
@export var wielder: Node

## Random source for spread and crits (seed it in tests).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _cooldown: float = 0.0
var _exclude: Array[RID] = []
var _magazine: int = 0
var _reserve: int = -1
var _reload_left: float = 0.0
var _projectiles: ProjectileSystem


func _ready() -> void:
	if wielder == null:
		wielder = owner if owner != null else get_parent()
	refill()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


## Bodies the shot passes through (the wielder's own colliders).
func set_exclude(rids: Array[RID]) -> void:
	_exclude = rids


## Full magazine and the data's starting reserve.
func refill() -> void:
	_reload_left = 0.0
	_magazine = data.magazine_size if data != null else 0
	_reserve = data.reserve_ammo if data != null else -1


func can_fire() -> bool:
	return _cooldown <= 0.0 and not is_reloading() and (data.magazine_size <= 0 or _magazine > 0)


## Rounds left in the magazine (0 when the weapon has no magazine).
func get_magazine() -> int:
	return _magazine


## Spare rounds, -1 = unlimited.
func get_reserve() -> int:
	return _reserve


func is_reloading() -> bool:
	return _reload_left > 0.0


## 0..1 progress of the current reload (1 when not reloading).
func get_reload_progress() -> float:
	if not is_reloading() or data.reload_time <= 0.0:
		return 1.0
	return 1.0 - _reload_left / data.reload_time


## True when the magazine is empty and there is nothing left to reload.
func is_out_of_ammo() -> bool:
	return data.magazine_size > 0 and _magazine <= 0 and _reserve == 0 and not is_reloading()


## Starts a reload if the magazine isn't full and spare rounds remain.
func start_reload() -> bool:
	if data.magazine_size <= 0 or is_reloading() or _magazine >= data.magazine_size:
		return false
	if _reserve == 0:
		return false
	_reload_left = maxf(data.reload_time, 0.001)
	reload_started.emit(data.reload_time)
	return true


## Stops a reload in progress (switching weapons).
func cancel_reload() -> void:
	_reload_left = 0.0


## Fires one trigger pull from `from` toward `aim_point` if ready.
## Returns true if it fired. An empty magazine starts a reload instead.
func try_fire(from: Vector3, aim_point: Vector3) -> bool:
	if data.magazine_size > 0 and _magazine <= 0 and not is_reloading():
		start_reload()
		return false
	if not can_fire():
		return false
	_cooldown = data.fire_interval
	var aim_dir: Vector3 = aim_point - from
	aim_dir = aim_dir.normalized() if aim_dir.length() > 0.01 else -global_basis.z
	if data.fire_mode == WeaponData.FireMode.BEAM:
		_fire_beam(from, aim_dir)
	else:
		_fire_rounds(from, aim_point, aim_dir)
	if data.magazine_size > 0:
		_magazine -= 1
		if _magazine <= 0:
			start_reload()
	EventBus.weapon_fired.emit(self, from, aim_dir)
	fired.emit(from, aim_dir)
	return true


## Rotates `dir` by a random angle inside a cone of `spread_deg` (half-angle).
static func apply_spread(dir: Vector3, spread_deg: float, random: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return dir
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var tilted: Vector3 = dir.rotated(side, deg_to_rad(random.randf_range(0.0, spread_deg)))
	return tilted.rotated(dir, random.randf_range(0.0, TAU)).normalized()


## Damage for one direct hit of `weapon_data` travelling along `dir`.
static func make_damage(
	weapon_data: WeaponData, source: Node, at: Vector3, dir: Vector3, random: RandomNumberGenerator
) -> DamageInfo:
	var info: DamageInfo = DamageInfo.create(
		weapon_data.damage, weapon_data.damage_type, source, at
	)
	if random.randf() < weapon_data.crit_chance:
		info.amount *= weapon_data.crit_multiplier
		info.crit = true
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
	if weapon_data.knockback > 0.0:
		info.knockback = flat * weapon_data.knockback
	info.impulse = dir * weapon_data.impact_force
	return info


func _fire_rounds(from: Vector3, aim_point: Vector3, aim_dir: Vector3) -> void:
	var projectile: ProjectileData = data.projectile
	if projectile == null:
		push_error("Weapon %s: PROJECTILE mode needs projectile data" % data.name_key)
		return
	if not is_instance_valid(_projectiles):
		_projectiles = ProjectileSystem.find_or_create(self)
	var g: float = Ballistics.gravity() * projectile.gravity_scale
	var base: Vector3
	if projectile.lob:
		base = Ballistics.lob_velocity(from, aim_point, projectile.speed, g)
	elif projectile.thrust > 0.0:
		base = aim_dir * projectile.speed
	else:
		base = Ballistics.zeroed_velocity(from, aim_point, projectile.speed, g)
	var lock: Node3D = _find_lock(aim_point) if data.lock_radius > 0.0 else null
	for i in maxi(1, data.pellets):
		var velocity: Vector3 = (
			apply_spread(base.normalized(), data.spread_deg, rng) * base.length()
		)
		_projectiles.fire(data, from, velocity, target_mask, wielder, _exclude, lock, aim_point)


func _fire_beam(from: Vector3, aim_dir: Vector3) -> void:
	var dir: Vector3 = apply_spread(aim_dir, data.spread_deg, rng)
	var to: Vector3 = from + dir * data.max_range
	var hit: Dictionary = Hitscan.cast(
		get_world_3d().direct_space_state, from - dir * BACKCAST, to, target_mask, _exclude
	)
	var end: Vector3 = to
	if not hit.is_empty():
		end = hit["position"]
		var hurtbox: HurtboxComponent = hit["hurtbox"]
		if hurtbox != null:
			hurtbox.take_hit(make_damage(data, wielder, end, dir, rng))
		EventBus.hit_landed.emit(end, hit["normal"], data.damage_type, hurtbox != null)
	EventBus.beam_drawn.emit(from, end, data.beam_width, data.damage_type)


## The living actor nearest `point` within `lock_radius` (homing lock), or null.
func _find_lock(point: Vector3) -> Node3D:
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = data.lock_radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), point)
	query.collision_mask = target_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var best: Node3D = null
	var best_d: float = INF
	for r: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var hurtbox: HurtboxComponent = r["collider"] as HurtboxComponent
		if hurtbox == null or hurtbox.health == null or hurtbox.health.is_dead():
			continue
		var actor: Node3D = hurtbox.get_actor() as Node3D
		if actor == null:
			continue
		var d: float = actor.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = actor
	return best


func _finish_reload() -> void:
	_reload_left = 0.0
	var needed: int = data.magazine_size - _magazine
	var taken: int = needed if _reserve < 0 else mini(needed, _reserve)
	_magazine += taken
	if _reserve > 0:
		_reserve -= taken
	reload_finished.emit()
