class_name BaseEnemy
extends CharacterBody3D
## Base for every AXIOM droid (P1-08, TDD §3.4).
##
## - **Thinks at an AI LOD rate:** the state machine, line-of-sight rays and
##   path requests run 3–30 times a second depending on distance to the player
##   and the quality preset (AiLod). Thinks are staggered between enemies.
## - **Moves every physics frame** along the last path (cheap steering only).
## - **Paths are time-sliced:** requests queue in the level's EnemyCoordinator,
##   which runs a few NavigationServer3D queries per frame (D-028).
##
## Scene contract (child node names): `Health` (HealthComponent), one or more
## HurtboxComponents, optional `AttackHitbox` (HitboxComponent, used by the
## default melee attack), optional `Visuals/Telegraph` (Node3D that pulses
## during the attack windup). Override `perform_attack()` for other attacks.

## The attack windup started (seconds until the hit). Visuals and audio listen.
signal attack_telegraphed(windup: float)
## The attack landed (or whiffed) this frame.
signal attacked
## This enemy died. EventBus.enemy_died is also emitted.
signal defeated(info: DamageInfo)

const STATE_IDLE: StringName = &"idle"
const STATE_CHASE: StringName = &"chase"
const STATE_ATTACK: StringName = &"attack"
const STATE_STUNNED: StringName = &"stunned"
const STATE_DEAD: StringName = &"dead"
## Added to melee reach for Neural Sync: the player's hurtbox radius.
const THREAT_MARGIN: float = 0.5
## Group the player joins (Hollow.PLAYER_GROUP).
const TARGET_GROUP: StringName = &"player"
## A path corner counts as reached this close (m, horizontal).
const CORNER_REACHED: float = 0.6
## Height of the eyes for line-of-sight rays (m).
const EYE_HEIGHT: float = 1.0
## Line of sight aims at the target's chest (m above its origin).
const TARGET_CHEST: float = 1.0
## Below this speed the body stops turning toward its velocity (m/s).
const TURN_MIN_SPEED: float = 0.5
## Trying to move but covering less than this share of the wanted distance
## counts as being stuck (blocked by a wall the path didn't know about, or a crowd).
const STUCK_PROGRESS_RATIO: float = 0.25
## Stuck this long → ask for a new path (s).
const STUCK_REPATH_TIME: float = 0.75
## Backpedalling is slower than walking forward (share of move speed).
const RETREAT_SPEED: float = 0.7
## Volatile droids blow up from about chest height.
const BLAST_HEIGHT: float = 0.6

@export var data: EnemyData
## Skip Idle and chase the player right away (spawned by a wave).
@export var start_alerted: bool = false

## Current target (the player for now; allies come with Reclaim).
var target: Node3D
## While true, the body turns toward the target instead of its velocity.
var face_target: bool = false
## Stun seconds left. The Stunned state counts it down.
var stun_time: float = 0.0
## Random source (attack variety, think stagger). Seed it in tests.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _brain: StateMachine
var _coordinator: EnemyCoordinator
var _target_health: HealthComponent
var _think_timer: float = 0.0
var _think_elapsed: float = 0.0
var _moving: bool = false
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _path_goal: Vector3 = Vector3.ZERO
var _pending_goal: Vector3 = Vector3.ZERO
var _path_pending: bool = false
## The last query found no navigation path (straight-line stand-in).
var _path_is_fallback: bool = false
## Seconds spent trying to move without getting anywhere.
var _stuck_time: float = 0.0
var _since_path: float = INF
var _query: NavigationPathQueryParameters3D = NavigationPathQueryParameters3D.new()
var _query_result: NavigationPathQueryResult3D = NavigationPathQueryResult3D.new()
var _hurtboxes: Array[HurtboxComponent] = []
var _crippled: bool = false
## Push away from crowding neighbours (m/s), refreshed every think.
var _separation: Vector3 = Vector3.ZERO
## Backing away from a target that came too close (Gunner).
var _retreating: bool = false
var _flinch_tween: Tween
## When the telegraphed attack lands (Time.get_ticks_msec()), -1 = none.
var _attack_lands_msec: int = -1

@onready var health: HealthComponent = $Health
@onready var visuals: Node3D = get_node_or_null("Visuals")
@onready var _attack_hitbox: HitboxComponent = get_node_or_null("AttackHitbox")
@onready var _telegraph: Node3D = get_node_or_null("Visuals/Telegraph")


func _ready() -> void:
	rng.randomize()
	health.max_health = data.max_hp
	health.resistances = data.resistances
	health.reset()
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	for child: Node in get_children():
		if child is HurtboxComponent:
			_hurtboxes.append(child)
	if _attack_hitbox != null:
		_attack_hitbox.damage = data.attack_damage
		_attack_hitbox.damage_type = data.attack_damage_type
		_attack_hitbox.knockback = data.attack_knockback
		_attack_hitbox.source = self
	_coordinator = EnemyCoordinator.find_or_create(self)
	_coordinator.register_enemy(self)
	_brain = StateMachine.new(self)
	_brain.add(STATE_IDLE, EnemyIdleState.new())
	_brain.add(STATE_CHASE, EnemyChaseState.new())
	_brain.add(STATE_ATTACK, EnemyAttackState.new())
	_brain.add(STATE_STUNNED, EnemyStunnedState.new())
	_brain.add(STATE_DEAD, EnemyDeadState.new())
	_refresh_target()
	_brain.start(STATE_CHASE if start_alerted else STATE_IDLE)
	_think_timer = AiLod.stagger(AiLod.interval_for(0.0, QualityManager.settings), rng)


func _exit_tree() -> void:
	if is_instance_valid(_coordinator):
		_coordinator.unregister_enemy(self)


func _physics_process(delta: float) -> void:
	if health.is_dead():
		return
	_since_path += delta
	_think_elapsed += delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_refresh_target()
		_think_timer = AiLod.interval_for(distance_to_target(), QualityManager.settings)
		_brain.update(_think_elapsed)
		_think_elapsed = 0.0
		_think_movement()
	_move(delta)


# --- Queries used by states -------------------------------------------------


## Name of the current state (debug, tests).
func get_state() -> StringName:
	return _brain.get_current()


## True if there is a target and it isn't dead.
func is_target_alive() -> bool:
	if not is_instance_valid(target):
		return false
	return _target_health == null or not _target_health.is_dead()


func get_target_position() -> Vector3:
	return target.global_position if is_instance_valid(target) else global_position


## Horizontal distance to the target, or INF without one.
func distance_to_target() -> float:
	if not is_instance_valid(target):
		return INF
	var d: Vector3 = target.global_position - global_position
	return Vector2(d.x, d.z).length()


## One ray against WORLD geometry from the eyes to the target's chest.
## Only call this from thinks (it's the most expensive query here).
func has_line_of_sight() -> bool:
	if not is_instance_valid(target):
		return false
	var from: Vector3 = global_position + Vector3.UP * EYE_HEIGHT
	var to: Vector3 = target.global_position + Vector3.UP * TARGET_CHEST
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, PhysicsLayers.WORLD, [get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## True when chasing needs a fresh path: none yet, or the old one is older
## than `repath_interval` and either the target moved `repath_distance` from
## its goal, the path is used up, it was only a straight-line fallback, or
## the enemy is stuck.
func needs_repath() -> bool:
	if _path_pending:
		return false
	if _path.is_empty():
		return true
	if _since_path < data.repath_interval:
		return false
	if _path_is_fallback or is_stuck():
		return true
	var moved: bool = _path_goal.distance_to(get_target_position()) > data.repath_distance
	return moved or _path_index >= _path.size()


# --- Commands used by states ------------------------------------------------


## True after trying to move for STUCK_REPATH_TIME without real progress.
func is_stuck() -> bool:
	return _stuck_time >= STUCK_REPATH_TIME


## Queues a path to `point` in the coordinator and starts moving once it arrives.
## Keeps following the old path meanwhile.
func request_path_to(point: Vector3) -> void:
	_pending_goal = point
	_moving = true
	if not _path_pending:
		_path_pending = true
		_coordinator.request_path(self)


## Stops moving (velocity eases to zero) and drops the current path.
func stop_moving() -> void:
	_moving = false
	_path.clear()
	_path_index = 0


## Starts the attack windup: pulses `Visuals/Telegraph` and emits `attack_telegraphed`.
func telegraph_attack(windup: float) -> void:
	attack_telegraphed.emit(windup)
	_attack_lands_msec = Time.get_ticks_msec() + roundi(windup * 1000.0)
	if _telegraph == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_telegraph, "scale", Vector3.ONE * 1.8, windup * 0.8)
	tween.tween_property(_telegraph, "scale", Vector3.ONE, windup * 0.2)


## Lands the attack. Default: one melee strike with `AttackHitbox`.
## Ranged enemies override this (P1-09).
func perform_attack() -> void:
	if _attack_hitbox != null:
		_attack_hitbox.strike()
	attacked.emit()


## Seconds until the telegraphed attack lands, or -1 if none is winding up
## (Neural Sync, P1-12).
func get_attack_eta() -> float:
	if _attack_lands_msec < 0 or health.is_dead():
		return -1.0
	return maxf(0.0, (_attack_lands_msec - Time.get_ticks_msec()) / 1000.0)


## How far the pending attack reaches (m). Melee: attack range plus the
## player's hurtbox. Ranged enemies return 0: their rounds are tracked in
## flight instead (ProjectileSystem.count_threats).
func get_threat_reach() -> float:
	return data.attack_range + THREAT_MARGIN


## The windup ended (attack landed) or was interrupted (stun, retreat).
func clear_pending_attack() -> void:
	_attack_lands_msec = -1


## Wakes an idle enemy (alerted by a nearby droid, or spawned by a wave).
## Does not relay further, so one sighting can't wake the whole map.
func alert() -> void:
	if _brain.get_current() == STATE_IDLE and is_target_alive():
		_brain.change(STATE_CHASE)


## This droid itself spotted the player or got hit: chase, and alert idle
## droids within `data.alert_radius` (one hop, D-029).
func notice_target() -> void:
	var was_idle: bool = _brain.get_current() == STATE_IDLE
	alert()
	if was_idle and data.alert_radius > 0.0 and is_instance_valid(_coordinator):
		_coordinator.alert_nearby(global_position, data.alert_radius, self)


## Freezes the enemy for `duration` seconds (EMP). Stunning a stunned enemy
## extends the stun to whichever ends later.
func stun(duration: float) -> void:
	if health.is_dead() or duration <= 0.0:
		return
	stun_time = maxf(stun_time, duration)
	_brain.change(STATE_STUNNED)


## Called by the EnemyCoordinator when this enemy's turn comes (time slicing).
func run_path_query() -> void:
	_path_pending = false
	if not is_inside_tree() or health.is_dead():
		return
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		# The navigation map hasn't synced yet (first frames of a level). Try again later.
		_path_pending = true
		_coordinator.request_path(self)
		return
	_query.map = map
	_query.start_position = global_position
	_query.target_position = _pending_goal
	NavigationServer3D.query_path(_query, _query_result)
	_path = _query_result.path
	_path_is_fallback = _path.is_empty()
	if _path_is_fallback:
		# No navigation result (no navmesh, or the region hasn't synced into the
		# map yet): walk straight at the goal for now and ask again soon.
		_path = PackedVector3Array([_pending_goal])
	_path_index = 0
	_path_goal = _pending_goal
	_since_path = 0.0
	_stuck_time = 0.0


## Current top speed (slower while crippled).
func get_move_speed() -> float:
	return data.move_speed * (data.crippled_speed if _crippled else 1.0)


## True once HP fell below `data.cripple_ratio` (smoking, limping).
func is_crippled() -> bool:
	return _crippled


# --- Internals -------------------------------------------------------------


## Per-think movement helpers: crowd separation and retreat.
func _think_movement() -> void:
	var state: StringName = _brain.get_current()
	var active: bool = state != STATE_STUNNED and state != STATE_DEAD
	_separation = Vector3.ZERO
	if active and data.separation_radius > 0.0 and is_instance_valid(_coordinator):
		_separation = (
			_coordinator.separation_for(self, data.separation_radius) * data.separation_strength
		)
	_retreating = (
		active
		and state != STATE_IDLE
		and data.retreat_distance > 0.0
		and is_target_alive()
		and distance_to_target() < data.retreat_distance
	)


func _move(delta: float) -> void:
	var desired: Vector3 = Vector3.ZERO
	if _retreating:
		var away: Vector3 = global_position - target.global_position
		away.y = 0.0
		desired = away.normalized() * get_move_speed() * RETREAT_SPEED
	elif _moving and distance_to_target() > data.stop_distance:
		desired = _steer_along_path() * get_move_speed()
	desired += _separation
	var flat: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(
		desired, data.acceleration * delta
	)
	velocity.x = flat.x
	velocity.z = flat.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= data.gravity * delta
	var before: Vector3 = global_position
	move_and_slide()
	_track_stuck(delta, desired.length(), before)
	_turn(delta, flat)


func _track_stuck(delta: float, wanted_speed: float, before: Vector3) -> void:
	if wanted_speed < 0.1:
		_stuck_time = 0.0
		return
	var moved: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if moved < wanted_speed * delta * STUCK_PROGRESS_RATIO:
		_stuck_time += delta
	else:
		_stuck_time = 0.0


## Unit direction toward the next path corner, or ZERO when the path is done.
func _steer_along_path() -> Vector3:
	while _path_index < _path.size():
		var to_corner: Vector3 = _path[_path_index] - global_position
		to_corner.y = 0.0
		if to_corner.length() > CORNER_REACHED:
			return to_corner.normalized()
		_path_index += 1
	return Vector3.ZERO


func _turn(delta: float, flat_velocity: Vector3) -> void:
	var look: Vector3 = flat_velocity
	if (face_target or _retreating) and is_instance_valid(target):
		look = target.global_position - global_position
		look.y = 0.0
	elif flat_velocity.length() < TURN_MIN_SPEED:
		return
	if look.length_squared() < 0.0001:
		return
	var yaw: float = atan2(-look.x, -look.z)
	rotation.y = rotate_toward(rotation.y, yaw, data.turn_speed * delta)


func _refresh_target() -> void:
	if is_instance_valid(target):
		return
	target = get_tree().get_first_node_in_group(TARGET_GROUP) as Node3D
	_target_health = null
	if target != null:
		_target_health = target.get_node_or_null("Health") as HealthComponent


func _on_damaged(info: DamageInfo, _amount: float) -> void:
	if info.knockback != Vector3.ZERO:
		velocity.x += info.knockback.x
		velocity.z += info.knockback.z
	if health.is_dead():
		return
	_flinch(info)
	if not _crippled and health.get_ratio() <= data.cripple_ratio:
		_crippled = true
		EventBus.smoke_source_added.emit(self, -1.0)
	notice_target()


func _on_died(info: DamageInfo) -> void:
	stop_moving()
	velocity = Vector3.ZERO
	collision_layer = 0
	for hurtbox: HurtboxComponent in _hurtboxes:
		hurtbox.collision_layer = 0
	_brain.change(STATE_DEAD)
	if is_instance_valid(_coordinator):
		_coordinator.unregister_enemy(self)
	if _flinch_tween != null:
		_flinch_tween.kill()
	var corpse: float = data.corpse_time
	if visuals != null:
		# Break into rigid parts flung by the killing hit (D-031). Without a
		# debris pool (disabled preset), fall back to toppling over.
		var debris: DebrisSystem = DebrisSystem.find_or_create(self)
		if debris.shatter(visuals, _death_impulse(info), velocity, data.wreck_time) > 0:
			corpse = 0.1
		else:
			var tween: Tween = create_tween()
			tween.tween_property(visuals, "rotation:x", deg_to_rad(-80.0), 0.35)
	if data.death_blast_radius > 0.0:
		# Deferred: a blast that kills another volatile droid mustn't detonate
		# it inside this explosion's own query loop.
		_detonate.call_deferred(global_position + Vector3.UP * BLAST_HEIGHT)
	defeated.emit(info)
	EventBus.enemy_died.emit(self, info.source)
	get_tree().create_timer(corpse).timeout.connect(queue_free)


## Leans the body away from the hit, then springs back (reads in both cameras).
func _flinch(info: DamageInfo) -> void:
	if visuals == null:
		return
	var push: Vector3 = info.impulse if info.impulse != Vector3.ZERO else info.knockback
	if push == Vector3.ZERO:
		return
	var local: Vector3 = global_basis.inverse() * push
	var max_lean: float = 0.45
	var lean_x: float = clampf(local.z * data.flinch_per_impulse, -max_lean, max_lean)
	var lean_z: float = clampf(-local.x * data.flinch_per_impulse, -max_lean, max_lean)
	if _flinch_tween != null:
		_flinch_tween.kill()
	visuals.rotation = Vector3(lean_x, 0.0, lean_z)
	_flinch_tween = create_tween()
	(
		_flinch_tween
		. tween_property(visuals, "rotation", Vector3.ZERO, 0.18)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


## Which way the wreck flies: the hit's impulse, else its knockback, else
## away from the attacker.
func _death_impulse(info: DamageInfo) -> Vector3:
	if info.impulse != Vector3.ZERO:
		return info.impulse
	if info.knockback != Vector3.ZERO:
		return info.knockback
	if is_instance_valid(info.source) and info.source is Node3D:
		var away: Vector3 = global_position - (info.source as Node3D).global_position
		away.y = 0.0
		return away.normalized() * 2.0 if away.length() > 0.01 else Vector3.ZERO
	return Vector3.ZERO


## Self-destruct blast (data.death_blast_*). Hurts the player, allies and
## other AXIOM droids alike.
func _detonate(at: Vector3) -> void:
	if not is_inside_tree():
		return
	Explosion.detonate(
		get_world_3d(),
		at,
		data.death_blast_radius,
		data.death_blast_damage,
		DamageInfo.Type.KINETIC,
		data.death_blast_force,
		PhysicsLayers.PLAYER | PhysicsLayers.ALLIES | PhysicsLayers.ENEMIES,
		self
	)
