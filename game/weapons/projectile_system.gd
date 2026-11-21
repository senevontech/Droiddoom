class_name ProjectileSystem
extends Node3D
## Moves and draws every round in flight (D-030). One per level;
## `find_or_create()` adds one when a level has none (tests, dev scenes).
##
## - **Physics:** each physics step a round gets gravity, drag, missile
##   thrust and homing, then sweeps the segment it just flew with
##   `Hitscan.cast` (world ray + hurtbox ray). So fast rounds never tunnel,
##   walls stop them, and targets can dodge a round that's already in the air.
## - **No nodes per round:** rounds are plain objects recycled from a free
##   list. Drawing = one MultiMesh per look (≤ 5 draw calls in total),
##   interpolated between physics steps so motion is smooth at any frame rate.
## Cost: 2 ray queries per round per physics step. Capped at MAX_SHOTS (the
## oldest round is dropped when full).

const GROUP: StringName = &"projectile_system"
const MAX_SHOTS: int = 384
const MAX_PER_VISUAL: int = 192
## The first sweep starts this far behind the muzzle, so point-blank targets
## (and walls the barrel pokes into) are still hit.
const BACKCAST: float = 0.9
## Re-casts allowed in one step after skipping an already-hit actor or piercing.
const MAX_SWEEPS: int = 4
## Bouncing rounds slower than this after a floor bounce come to rest.
const REST_SPEED: float = 1.6
## Homing rounds aim this high above the target's origin (its chest).
const HOMING_AIM_HEIGHT: float = 0.7
## Explosive homing rounds detonate this close to their locked target
## (proximity fuse), so a near miss still counts.
const PROXIMITY_FUSE: float = 0.9
const TRAIL_INTERVAL: float = 0.03
const TRACER_COLOR: Color = Color(1.0, 0.72, 0.3)
const SLUG_COLOR: Color = Color(0.35, 0.85, 1.0)
const FLAME_COLOR: Color = Color(1.0, 0.55, 0.15)
const GRENADE_COLOR: Color = Color(1.0, 0.25, 0.1)
## AXIOM's energy bolts: red, thick and slow so the player can read and dodge them.
const BOLT_COLOR: Color = Color(1.0, 0.12, 0.2)
const GLOW_ENERGY: float = 6.0


## One round in flight.
class Shot:
	extends RefCounted
	var weapon_data: WeaponData
	var data: ProjectileData
	var position: Vector3
	var prev_position: Vector3
	var spawn_position: Vector3
	var velocity: Vector3
	var age: float = 0.0
	var traveled: float = 0.0
	var target_mask: int = 0
	var exclude: Array[RID] = []
	var source_id: int = 0
	var pierce_left: int = 0
	var hit_healths: Array[int] = []
	var homing_id: int = 0
	var homing_point: Vector3 = Vector3.INF
	var resting: bool = false
	var trail_timer: float = 0.0
	## The point-blank check behind the muzzle still has to run.
	var backcast: bool = true
	## Damage multiplier fixed at launch (Neural Sync bonus).
	var damage_scale: float = 1.0


## Random source for crits (seed it in tests).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _shots: Array[Shot] = []
var _spare: Array[Shot] = []
## MultiMesh per ProjectileData.Visual, plus the missile exhaust.
var _meshes: Array[MultiMesh] = []
var _flame: MultiMesh
var _gravity: float = 9.8
var _fx: CombatFX
## Shader warm-up (P1-27): frames left to draw one of every look at _warm_at.
var _warm_frames: int = 0
var _warm_at: Vector3 = Vector3.ZERO


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_gravity = Ballistics.gravity()
	_meshes.append(_make_multimesh(_box(0.035, TRACER_COLOR)))
	_meshes.append(_make_multimesh(_box(0.075, SLUG_COLOR)))
	_meshes.append(_make_multimesh(_missile_body()))
	_meshes.append(_make_multimesh(_grenade_mesh()))
	_meshes.append(_make_multimesh(_box(0.11, BOLT_COLOR)))
	_flame = _make_multimesh(_flame_mesh())


## Returns the level's projectile system, creating one under the current scene.
static func find_or_create(from: Node) -> ProjectileSystem:
	var tree: SceneTree = from.get_tree()
	var found: ProjectileSystem = tree.get_first_node_in_group(GROUP) as ProjectileSystem
	if found != null:
		return found
	var created: ProjectileSystem = ProjectileSystem.new()
	created.name = "ProjectileSystem"
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child.call_deferred(created)
	created.add_to_group(GROUP)
	return created


## Launches one round. `exclude` = the shooter's own bodies. Homing rounds
## steer toward `homing_target` (if alive) or else `homing_point`. On its
## first step the round also checks the stretch just behind the muzzle, so a
## point-blank target between the shooter and the muzzle is still hit.
func fire(
	weapon_data: WeaponData,
	from: Vector3,
	velocity: Vector3,
	target_mask: int,
	source: Node,
	exclude: Array[RID],
	homing_target: Node3D = null,
	homing_point: Vector3 = Vector3.INF,
	damage_scale: float = 1.0
) -> void:
	var shot: Shot = _spare.pop_back() if not _spare.is_empty() else Shot.new()
	shot.weapon_data = weapon_data
	shot.data = weapon_data.projectile
	shot.position = from
	shot.prev_position = from
	shot.spawn_position = from
	shot.velocity = velocity
	shot.age = 0.0
	shot.traveled = 0.0
	shot.target_mask = target_mask
	shot.exclude = exclude.duplicate()
	shot.source_id = source.get_instance_id() if source != null else 0
	shot.pierce_left = shot.data.pierce
	shot.hit_healths.clear()
	shot.homing_id = homing_target.get_instance_id() if homing_target != null else 0
	shot.homing_point = homing_point
	shot.resting = false
	shot.trail_timer = 0.0
	shot.backcast = true
	shot.damage_scale = damage_scale
	if _shots.size() >= MAX_SHOTS:
		_recycle(0)
	_shots.append(shot)


## Draws one of every round look (and the missile flame) at `at` for
## `frames` frames, so their shaders compile during loading, not on the first
## shot (P1-27; WebGL compiles are slow and block the frame).
func warm_up(at: Vector3, frames: int = 4) -> void:
	_warm_at = at
	_warm_frames = frames


## True while a warm-up draw is pending (tests).
func is_warming_up() -> bool:
	return _warm_frames > 0


## Rounds currently in flight.
func get_active_count() -> int:
	return _shots.size()


## Positions of all rounds in flight (debug/tests).
func get_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for shot: Shot in _shots:
		out.append(shot.position)
	return out


## Rounds aimed at `faction_mask` whose path over the next `window` seconds
## passes within `radius` of the segment `bottom`–`top` (Neural Sync, P1-12).
func count_threats(
	bottom: Vector3, top: Vector3, radius: float, window: float, faction_mask: int
) -> int:
	var count: int = 0
	for shot: Shot in _shots:
		if shot.target_mask & faction_mask == 0 or shot.resting:
			continue
		if NeuralSync.round_threatens(shot.position, shot.velocity, window, bottom, top, radius):
			count += 1
	return count


## Removes every round (level restart).
func clear() -> void:
	while not _shots.is_empty():
		_recycle(_shots.size() - 1)


func _physics_process(delta: float) -> void:
	var i: int = 0
	while i < _shots.size():
		if _step(_shots[i], delta):
			i += 1
		else:
			_recycle(i)


func _process(_delta: float) -> void:
	var frac: float = Engine.get_physics_interpolation_fraction()
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
	var flames: int = 0
	for shot: Shot in _shots:
		var visual: int = shot.data.visual
		if counts[visual] >= MAX_PER_VISUAL:
			continue
		var pos: Vector3 = shot.prev_position.lerp(shot.position, frac)
		var speed: float = shot.velocity.length()
		var dir: Vector3 = shot.velocity / speed if speed > 0.01 else Vector3.FORWARD
		var xform: Transform3D
		match visual:
			ProjectileData.Visual.TRACER, ProjectileData.Visual.SLUG, ProjectileData.Visual.BOLT:
				var length: float = minf(
					shot.data.streak_length, pos.distance_to(shot.spawn_position)
				)
				if length < 0.05:
					continue
				xform = Transform3D(
					_look(dir) * Basis.from_scale(Vector3(1.0, 1.0, length)),
					pos - dir * length * 0.5
				)
			ProjectileData.Visual.MISSILE:
				var basis: Basis = _look(dir)
				xform = Transform3D(basis, pos)
				if not shot.resting and flames < MAX_PER_VISUAL:
					var flicker: float = 0.8 + rng.randf() * 0.5
					_flame.set_instance_transform(
						flames,
						Transform3D(
							basis * Basis.from_scale(Vector3(1.0, 1.0, flicker)), pos - dir * 0.42
						)
					)
					flames += 1
			_:
				xform = Transform3D(Basis(), pos)
		_meshes[visual].set_instance_transform(counts[visual], xform)
		counts[visual] += 1
	if _warm_frames > 0:
		_warm_frames -= 1
		for v in _meshes.size():
			if counts[v] == 0:
				var offset: Vector3 = Vector3(0.4 * v, 0.0, 0.0)
				_meshes[v].set_instance_transform(0, Transform3D(Basis(), _warm_at + offset))
				counts[v] = 1
		if flames == 0:
			_flame.set_instance_transform(0, Transform3D(Basis(), _warm_at + Vector3.UP * 0.3))
			flames = 1
	for v in _meshes.size():
		_meshes[v].visible_instance_count = counts[v]
	_flame.visible_instance_count = flames


## Advances one round by `delta`. Returns false when the round is finished.
func _step(shot: Shot, delta: float) -> bool:
	var data: ProjectileData = shot.data
	if shot.backcast:
		shot.backcast = false
		var dir: Vector3 = shot.velocity.normalized()
		if not _sweep(shot, shot.position - dir * BACKCAST, shot.position):
			return false
	shot.age += delta
	shot.prev_position = shot.position
	if data.fuse_time > 0.0 and shot.age >= data.fuse_time:
		_explode(shot, shot.position + Vector3.UP * 0.15)
		return false
	if shot.age >= data.lifetime or shot.traveled >= shot.weapon_data.max_range:
		if data.explodes():
			_explode(shot, shot.position)
		return false
	if shot.resting:
		return true
	var v: Vector3 = shot.velocity
	if data.thrust > 0.0:
		var speed: float = minf(v.length() + data.thrust * delta, data.max_speed)
		v = v.normalized() * speed
	if data.homing_turn_deg > 0.0 and shot.age >= data.arm_time:
		v = _home(shot, v, delta)
		if (
			shot.homing_id != 0
			and data.explodes()
			and shot.position.distance_to(shot.homing_point) < PROXIMITY_FUSE
		):
			_explode(shot, shot.position)
			return false
	v.y -= _gravity * data.gravity_scale * delta
	if data.drag > 0.0:
		v *= exp(-data.drag * delta)
	shot.velocity = v
	if data.visual == ProjectileData.Visual.MISSILE:
		_emit_trail(shot, delta)
	return _sweep(shot, shot.position, shot.position + v * delta)


## Moves the round from `from` to `to`, resolving whatever it hits on the
## way. Returns false when the round is finished.
func _sweep(shot: Shot, from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start: Vector3 = from
	for attempt in MAX_SWEEPS:
		var hit: Dictionary = Hitscan.cast(space, start, to, shot.target_mask, shot.exclude)
		if hit.is_empty():
			break
		var at: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var hurtbox: HurtboxComponent = hit["hurtbox"]
		var dir: Vector3 = shot.velocity.normalized()
		if hurtbox != null:
			shot.exclude.append(hurtbox.get_rid())
			var key: int = hurtbox.health.get_instance_id() if hurtbox.health != null else 0
			if shot.hit_healths.has(key):
				start = at
				continue
			shot.hit_healths.append(key)
			_damage(shot, hurtbox, at, dir)
			EventBus.hit_landed.emit(at, normal, shot.weapon_data.damage_type, true)
			if shot.data.explodes():
				_explode(shot, at)
				return false
			if shot.pierce_left > 0:
				shot.pierce_left -= 1
				start = at
				continue
			shot.position = at
			return false
		# World hit.
		if shot.data.bounce_restitution > 0.0:
			_bounce(shot, at, normal)
			return true
		EventBus.hit_landed.emit(at, normal, shot.weapon_data.damage_type, false)
		if shot.data.explodes():
			_explode(shot, at + normal * 0.15)
		shot.position = at
		return false
	shot.traveled += shot.position.distance_to(to)
	shot.position = to
	return true


func _bounce(shot: Shot, at: Vector3, normal: Vector3) -> void:
	var v: Vector3 = shot.velocity.bounce(normal) * shot.data.bounce_restitution
	shot.position = at + normal * 0.03
	shot.prev_position = shot.position
	if v.length() < REST_SPEED and normal.y > 0.6:
		v = Vector3.ZERO
		shot.resting = true
	shot.velocity = v


func _home(shot: Shot, v: Vector3, delta: float) -> Vector3:
	if shot.homing_id != 0:
		var target: Node3D = instance_from_id(shot.homing_id) as Node3D
		var health: HealthComponent = (
			target.get_node_or_null("Health") as HealthComponent if target != null else null
		)
		if target == null or (health != null and health.is_dead()):
			shot.homing_id = 0
		else:
			shot.homing_point = target.global_position + Vector3.UP * HOMING_AIM_HEIGHT
	if not shot.homing_point.is_finite():
		return v
	var to_goal: Vector3 = shot.homing_point - shot.position
	var speed: float = v.length()
	if to_goal.length() < 0.3 or speed < 0.01:
		return v
	var current: Vector3 = v / speed
	var desired: Vector3 = to_goal.normalized()
	var angle: float = current.angle_to(desired)
	var axis: Vector3 = current.cross(desired)
	if angle < 0.001 or axis.length() < 0.0001:
		return v
	var turn: float = minf(angle, deg_to_rad(shot.data.homing_turn_deg) * delta)
	return current.rotated(axis.normalized(), turn) * speed


func _damage(shot: Shot, hurtbox: HurtboxComponent, at: Vector3, dir: Vector3) -> void:
	if shot.weapon_data.damage <= 0.0:
		return
	var source: Node = instance_from_id(shot.source_id) as Node if shot.source_id != 0 else null
	hurtbox.take_hit(Weapon.make_damage(shot.weapon_data, source, at, dir, rng, shot.damage_scale))


func _explode(shot: Shot, at: Vector3) -> void:
	var data: ProjectileData = shot.data
	var source: Node = instance_from_id(shot.source_id) as Node if shot.source_id != 0 else null
	Explosion.detonate(
		get_world_3d(),
		at,
		data.explosion_radius,
		data.explosion_damage * shot.damage_scale,
		shot.weapon_data.damage_type,
		data.explosion_force,
		shot.target_mask,
		source
	)


func _emit_trail(shot: Shot, delta: float) -> void:
	shot.trail_timer -= delta
	if shot.trail_timer > 0.0:
		return
	shot.trail_timer = TRAIL_INTERVAL
	if not is_instance_valid(_fx):
		_fx = get_tree().get_first_node_in_group(CombatFX.GROUP) as CombatFX
	if _fx != null:
		_fx.emit_trail(shot.position - shot.velocity.normalized() * 0.5)


func _recycle(index: int) -> void:
	var shot: Shot = _shots[index]
	_shots[index] = _shots[_shots.size() - 1]
	_shots.pop_back()
	shot.exclude = []
	_spare.append(shot)


func _make_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_PER_VISUAL
	multimesh.visible_instance_count = 0
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rounds can be anywhere in the level: never frustum-cull the whole set.
	instance.custom_aabb = AABB(Vector3(-500.0, -50.0, -500.0), Vector3(1000.0, 200.0, 1000.0))
	add_child(instance)
	return multimesh


## Rotation that points local -Z along `dir`. Stretch it with
## `* Basis.from_scale()` (local), never `.scaled()` (that scales world axes).
static func _look(dir: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir, up)


static func _box(thickness: float, color: Color) -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, 1.0)
	mesh.material = CombatFX.glow_material(color, GLOW_ENERGY)
	return mesh


static func _missile_body() -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.55)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.3)
	mat.metallic = 0.6
	mat.roughness = 0.5
	mesh.material = mat
	return mesh


static func _flame_mesh() -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.09, 0.09, 0.32)
	mesh.material = CombatFX.glow_material(FLAME_COLOR, GLOW_ENERGY)
	return mesh


static func _grenade_mesh() -> SphereMesh:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = CombatFX.glow_material(GRENADE_COLOR, 2.5)
	return mesh
