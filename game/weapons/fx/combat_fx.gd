class_name CombatFX
extends Node3D
## Draws muzzle flashes, beams, impacts, explosions and smoke for the whole
## level (one instance per level). Listens to EventBus, so weapons, enemies
## and cameras never know it exists. Rounds in flight are drawn by
## ProjectileSystem.
##
## Cost (web-safe, no GPU particles):
## - Beams: one MultiMesh per damage type (≤ 3 draw calls).
## - Smoke and fire: two camera-facing MultiMeshes fed from packed arrays
##   (2 draw calls, CPU update of ≤ ~250 puffs). Puff counts follow the
##   quality preset's `particle_density`.
## - Sparks: a fixed pool of CPUParticles3D.
## - Light flashes: a pool of `max_dynamic_lights` OmniLights (no shadows).

const GROUP: StringName = &"combat_fx"
const BEAM_POOL: int = 32
const BEAM_LIFE: float = 0.07
const BEAM_BASE_WIDTH: float = 0.05
const IMPACT_POOL: int = 16
const SPARKS_AT_FULL_DENSITY: int = 10
const SMOKE_CAP: int = 256
const FIRE_CAP: int = 128
const SOURCE_CAP: int = 24
## Seconds between puffs of a smoking droid or wreck.
const SOURCE_INTERVAL: float = 0.1
## Tracer, flash and spark colour per DamageInfo.Type (GDD §4.2: yellow / orange / cyan).
const TYPE_COLORS: Array[Color] = [
	Color(1.0, 0.75, 0.35),
	Color(1.0, 0.42, 0.1),
	Color(0.3, 0.9, 1.0),
]
const SMOKE_COLOR: Color = Color(0.16, 0.15, 0.14, 0.6)
const DUST_COLOR: Color = Color(0.45, 0.42, 0.38, 0.45)
const FIRE_COLOR: Color = Color(1.0, 0.5, 0.18, 1.0)
const GLOW_ENERGY: float = 8.0


## A pool of billboard puffs drawn by one MultiMesh.
class PuffLayer:
	extends RefCounted
	var multimesh: MultiMesh
	var cap: int = 0
	var count: int = 0
	var pos: PackedVector3Array = PackedVector3Array()
	var vel: PackedVector3Array = PackedVector3Array()
	var age: PackedFloat32Array = PackedFloat32Array()
	var life: PackedFloat32Array = PackedFloat32Array()
	var size0: PackedFloat32Array = PackedFloat32Array()
	var size1: PackedFloat32Array = PackedFloat32Array()
	var color: PackedColorArray = PackedColorArray()
	var buffer: PackedFloat32Array = PackedFloat32Array()
	## Velocity damping (1/s): smoke slows quickly, fire a little less.
	var damping: float = 2.0

	func _init(p_cap: int) -> void:
		cap = p_cap
		pos.resize(cap)
		vel.resize(cap)
		age.resize(cap)
		life.resize(cap)
		size0.resize(cap)
		size1.resize(cap)
		color.resize(cap)
		buffer.resize(cap * 16)

	func spawn(p: Vector3, v: Vector3, l: float, s0: float, s1: float, c: Color) -> void:
		if count >= cap:
			return
		pos[count] = p
		vel[count] = v
		age[count] = 0.0
		life[count] = maxf(l, 0.01)
		size0[count] = s0
		size1[count] = s1
		color[count] = c
		count += 1

	## `facing` = the camera's basis: puffs are turned to face it here on the
	## CPU (material billboarding isn't applied to MultiMesh instances on the
	## Compatibility renderer).
	func update(delta: float, facing: Basis) -> void:
		var bx: Vector3 = facing.x
		var by: Vector3 = facing.y
		var bz: Vector3 = facing.z
		var i: int = 0
		var keep: float = exp(-damping * delta)
		while i < count:
			age[i] += delta
			if age[i] >= life[i]:
				var last: int = count - 1
				pos[i] = pos[last]
				vel[i] = vel[last]
				age[i] = age[last]
				life[i] = life[last]
				size0[i] = size0[last]
				size1[i] = size1[last]
				color[i] = color[last]
				count -= 1
				continue
			var t: float = age[i] / life[i]
			vel[i] = vel[i] * keep
			pos[i] = pos[i] + vel[i] * delta
			var s: float = lerpf(size0[i], size1[i], sqrt(t))
			var c: Color = color[i]
			var p: Vector3 = pos[i]
			var o: int = i * 16
			buffer[o] = bx.x * s
			buffer[o + 1] = by.x * s
			buffer[o + 2] = bz.x * s
			buffer[o + 3] = p.x
			buffer[o + 4] = bx.y * s
			buffer[o + 5] = by.y * s
			buffer[o + 6] = bz.y * s
			buffer[o + 7] = p.y
			buffer[o + 8] = bx.z * s
			buffer[o + 9] = by.z * s
			buffer[o + 10] = bz.z * s
			buffer[o + 11] = p.z
			buffer[o + 12] = c.r
			buffer[o + 13] = c.g
			buffer[o + 14] = c.b
			buffer[o + 15] = c.a * (1.0 - t) * (1.0 - t * 0.5)
			i += 1
		multimesh.buffer = buffer
		multimesh.visible_instance_count = count


## Random source for FX jitter.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _beams: Array[MultiMesh] = []
var _beam_life: Array[PackedFloat32Array] = []
var _beam_next: PackedInt32Array = PackedInt32Array()
var _spark_meshes: Array[QuadMesh] = []
var _impacts: ObjectPool
var _smoke: PuffLayer
var _fire: PuffLayer
var _lights: Array[OmniLight3D] = []
var _light_life: PackedFloat32Array = PackedFloat32Array()
var _light_peak: PackedFloat32Array = PackedFloat32Array()
var _light_span: PackedFloat32Array = PackedFloat32Array()
## Smoke sources: [instance_id, seconds left (-1 = forever), timer].
var _sources: Array[Array] = []
var _density: float = 1.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for type_index in TYPE_COLORS.size():
		_build_beams(TYPE_COLORS[type_index])
		_spark_meshes.append(_spark_mesh(TYPE_COLORS[type_index]))
	_impacts = ObjectPool.new(_new_sparks, IMPACT_POOL, self)
	var soft: Texture2D = _soft_texture()
	_smoke = PuffLayer.new(SMOKE_CAP)
	_smoke.multimesh = _build_puffs(_puff_material(soft, false), SMOKE_CAP)
	_smoke.damping = 1.6
	_fire = PuffLayer.new(FIRE_CAP)
	_fire.multimesh = _build_puffs(_puff_material(soft, true), FIRE_CAP)
	_fire.damping = 3.0
	_build_lights()
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.beam_drawn.connect(_on_beam_drawn)
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.explosion_happened.connect(_on_explosion)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.smoke_source_added.connect(add_smoke_source)
	EventBus.quality_preset_changed.connect(_on_quality_changed)
	_on_quality_changed(QualityManager.preset)


func _process(delta: float) -> void:
	_update_beams(delta)
	_update_sources(delta)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var facing: Basis = camera.global_basis.orthonormalized() if camera != null else Basis()
	_smoke.update(delta, facing)
	_fire.update(delta, facing)
	_update_lights(delta)


## Number of beams currently visible (debug/tests).
func get_live_beam_count() -> int:
	var count: int = 0
	for life: PackedFloat32Array in _beam_life:
		for v: float in life:
			if v > 0.0:
				count += 1
	return count


## Live smoke and fire puffs (debug/tests).
func get_puff_count() -> int:
	return _smoke.count + _fire.count


## Smoke sources being tracked (debug/tests).
func get_smoke_source_count() -> int:
	return _sources.size()


## Shows one of everything this node draws at `at` (beams of every damage
## type, sparks, smoke, fire, every pooled light), so their shaders compile
## during loading instead of on the first shot (P1-27). Lights also make the
## nearby world/actor materials compile their lit variants.
func warm_up(at: Vector3) -> void:
	for t in _beams.size():
		_on_beam_drawn(at + Vector3(0.0, 0.2 * t, 0.0), at + Vector3(1.0, 0.2 * t, 0.0), 0.05, t)
	for t in _spark_meshes.size():
		_on_hit_landed(at, Vector3.UP, t, true)
	_smoke.spawn(at, Vector3.ZERO, 0.2, 0.3, 0.3, SMOKE_COLOR)
	_fire.spawn(at, Vector3.ZERO, 0.2, 0.3, 0.3, FIRE_COLOR)
	for i in _lights.size():
		_flash_light(at + Vector3.UP, Color(1.0, 0.7, 0.4), 0.4, 8.0, 0.25)


## A missile's exhaust trail puff (called by ProjectileSystem).
func emit_trail(at: Vector3) -> void:
	if rng.randf() > maxf(_density, 0.4):
		return
	var jitter: Vector3 = _jitter(0.25)
	_smoke.spawn(at, jitter, rng.randf_range(0.6, 0.9), 0.12, 0.55, SMOKE_COLOR.lightened(0.25))
	if rng.randf() < 0.5:
		_fire.spawn(at, jitter, 0.06, 0.14, 0.08, FIRE_COLOR)


## Makes `source` trail smoke for `duration` s (-1 = until freed).
func add_smoke_source(source: Node3D, duration: float) -> void:
	if source == null:
		return
	var id: int = source.get_instance_id()
	for entry: Array in _sources:
		if entry[0] == id:
			entry[1] = duration
			return
	if _sources.size() >= SOURCE_CAP:
		_sources.pop_front()
	_sources.append([id, duration, 0.0])


## Bright unshaded-looking material shared by tracers, beams and sparks.
static func glow_material(color: Color, energy: float = GLOW_ENERGY) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.6)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _on_weapon_fired(weapon: Node3D, muzzle: Vector3, direction: Vector3) -> void:
	var w: Weapon = weapon as Weapon
	if w == null or w.data == null:
		return
	var size: float = w.data.muzzle_flash_size
	if size <= 0.0:
		return
	var color: Color = TYPE_COLORS[clampi(w.data.damage_type, 0, TYPE_COLORS.size() - 1)]
	var flash_color: Color = color.lerp(Color.WHITE, 0.35)
	_fire.spawn(
		muzzle + direction * size * 0.3, direction * 2.0, 0.05, size, size * 1.4, flash_color
	)
	_fire.spawn(
		muzzle + direction * size * 0.9, direction * 3.0, 0.04, size * 0.6, size * 0.8, flash_color
	)
	_flash_light(muzzle, color, 2.5, 3.0 + size * 6.0, 0.07)
	if w.data.projectile != null and w.data.projectile.thrust > 0.0:
		# Missile launch backblast.
		for i in roundi(3 * _density) + 1:
			_smoke.spawn(
				muzzle - direction * 0.4,
				-direction * 3.0 + _jitter(1.0),
				0.9,
				0.2,
				0.8,
				SMOKE_COLOR
			)
	elif w.data.fire_mode != WeaponData.FireMode.BEAM and rng.randf() < _density:
		_smoke.spawn(muzzle, direction * 1.5 + _jitter(0.2), 0.4, 0.06, 0.3, DUST_COLOR)


func _on_beam_drawn(from: Vector3, to: Vector3, width: float, damage_type: int) -> void:
	var length: float = from.distance_to(to)
	if length < 0.05:
		return
	var t: int = clampi(damage_type, 0, _beams.size() - 1)
	var dir: Vector3 = (to - from) / length
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var w: float = width / BEAM_BASE_WIDTH
	var basis: Basis = Basis.looking_at(dir, up) * Basis.from_scale(Vector3(w, w, length))
	var slot: int = _beam_next[t]
	_beams[t].set_instance_transform(slot, Transform3D(basis, (from + to) * 0.5))
	_beam_life[t][slot] = BEAM_LIFE
	_beam_next[t] = (slot + 1) % BEAM_POOL


func _on_hit_landed(position: Vector3, normal: Vector3, damage_type: int, on_target: bool) -> void:
	var sparks: CPUParticles3D = _impacts.acquire()
	sparks.mesh = _spark_meshes[clampi(damage_type, 0, _spark_meshes.size() - 1)]
	sparks.global_position = position + normal * 0.05
	sparks.direction = normal
	sparks.restart()
	if not on_target and rng.randf() < _density:
		_smoke.spawn(
			position + normal * 0.1, normal * 1.2 + _jitter(0.3), 0.6, 0.1, 0.45, DUST_COLOR
		)


func _on_explosion(position: Vector3, radius: float, _damage_type: int) -> void:
	_blast(position, radius, 1.0)


func _on_enemy_died(enemy: Node, _killer: Node) -> void:
	var body: Node3D = enemy as Node3D
	if body == null or not body.is_inside_tree():
		return
	# The droid's power core pops: a small fireball, sparks and smoke.
	_blast(body.global_position + Vector3.UP * 0.7, 1.1, 0.5)


## Fireball + smoke + sparks + light. `strength` scales the puff counts.
func _blast(position: Vector3, radius: float, strength: float) -> void:
	var fire_n: int = roundi((8.0 * _density + 3.0) * strength)
	var smoke_n: int = roundi((10.0 * _density + 3.0) * strength)
	_fire.spawn(position, Vector3.ZERO, 0.16, radius * 0.6, radius * 1.3, FIRE_COLOR.lightened(0.3))
	for i in fire_n:
		var out: Vector3 = _jitter(1.0).normalized() * radius * rng.randf_range(1.5, 3.0)
		out.y = absf(out.y)
		_fire.spawn(
			position, out, rng.randf_range(0.25, 0.5), radius * 0.35, radius * 0.7, FIRE_COLOR
		)
	for i in smoke_n:
		var drift: Vector3 = _jitter(1.0).normalized() * radius * rng.randf_range(0.6, 1.4)
		drift.y = absf(drift.y) + 1.2
		_smoke.spawn(
			position + drift * 0.15,
			drift,
			rng.randf_range(1.3, 2.3),
			radius * 0.4,
			radius * 1.2,
			SMOKE_COLOR
		)
	for i in 2:
		var sparks: CPUParticles3D = _impacts.acquire()
		sparks.mesh = _spark_meshes[1]
		sparks.global_position = position
		sparks.direction = Vector3.UP
		sparks.restart()
	_flash_light(position, Color(1.0, 0.6, 0.25), 6.0 * strength, radius * 3.5, 0.3)


func _update_sources(delta: float) -> void:
	var i: int = 0
	while i < _sources.size():
		var entry: Array = _sources[i]
		var source: Node3D = instance_from_id(entry[0]) as Node3D
		var left: float = entry[1]
		if source == null or not source.is_inside_tree() or (left >= 0.0 and left <= delta):
			_sources.remove_at(i)
			continue
		if left > 0.0:
			entry[1] = left - delta
		entry[2] = float(entry[2]) - delta
		if entry[2] <= 0.0:
			entry[2] = SOURCE_INTERVAL / maxf(_density, 0.3)
			var at: Vector3 = source.global_position + Vector3.UP * 0.6 + _jitter(0.15)
			_smoke.spawn(
				at,
				Vector3(0.0, 1.3, 0.0) + _jitter(0.3),
				rng.randf_range(1.2, 1.8),
				0.2,
				0.9,
				SMOKE_COLOR
			)
			if rng.randf() < 0.25:
				_fire.spawn(at, Vector3.UP * 0.6, 0.18, 0.18, 0.1, FIRE_COLOR)
		i += 1


func _flash_light(
	position: Vector3, color: Color, energy: float, light_range: float, life: float
) -> void:
	if _lights.is_empty():
		return
	# Reuse the light closest to finishing.
	var slot: int = 0
	for i in _lights.size():
		if _light_life[i] < _light_life[slot]:
			slot = i
	var light: OmniLight3D = _lights[slot]
	light.global_position = position
	light.light_color = color
	light.omni_range = light_range
	light.light_energy = energy
	light.visible = true
	_light_life[slot] = life
	_light_span[slot] = life
	_light_peak[slot] = energy


func _update_lights(delta: float) -> void:
	for i in _lights.size():
		if _light_life[i] <= 0.0:
			continue
		_light_life[i] -= delta
		if _light_life[i] <= 0.0:
			_lights[i].visible = false
			continue
		var t: float = _light_life[i] / _light_span[i]
		_lights[i].light_energy = _light_peak[i] * t * t


func _update_beams(delta: float) -> void:
	for t in _beams.size():
		var life: PackedFloat32Array = _beam_life[t]
		for i in BEAM_POOL:
			if life[i] <= 0.0:
				continue
			life[i] -= delta
			if life[i] <= 0.0:
				_beams[t].set_instance_transform(i, _hidden())
		_beam_life[t] = life


func _on_quality_changed(_preset: int) -> void:
	_density = QualityManager.settings.particle_density if QualityManager.settings else 1.0
	var amount: int = maxi(2, roundi(SPARKS_AT_FULL_DENSITY * _density))
	for child: Node in get_children():
		var sparks: CPUParticles3D = child as CPUParticles3D
		if sparks != null and sparks.amount != amount:
			sparks.amount = amount


func _build_lights() -> void:
	var count: int = QualityManager.settings.max_dynamic_lights if QualityManager.settings else 2
	for i in maxi(0, count):
		var light: OmniLight3D = OmniLight3D.new()
		light.shadow_enabled = false
		light.visible = false
		light.omni_attenuation = 1.5
		add_child(light)
		_lights.append(light)
		_light_life.append(0.0)
		_light_peak.append(0.0)
		_light_span.append(1.0)


func _build_beams(color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(BEAM_BASE_WIDTH, BEAM_BASE_WIDTH, 1.0)
	mesh.material = glow_material(color)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = BEAM_POOL
	for i in BEAM_POOL:
		multimesh.set_instance_transform(i, _hidden())
	_add_multimesh(multimesh)
	_beams.append(multimesh)
	var life: PackedFloat32Array = PackedFloat32Array()
	life.resize(BEAM_POOL)
	_beam_life.append(life)
	_beam_next.append(0)


func _build_puffs(material: StandardMaterial3D, cap: int) -> MultiMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = cap
	multimesh.visible_instance_count = 0
	_add_multimesh(multimesh)
	return multimesh


func _add_multimesh(multimesh: MultiMesh) -> void:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# FX can be anywhere in the level: never frustum-cull the whole set.
	instance.custom_aabb = AABB(Vector3(-500.0, -50.0, -500.0), Vector3(1000.0, 200.0, 1000.0))
	add_child(instance)


func _spark_mesh(color: Color) -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat: StandardMaterial3D = glow_material(color)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	return quad


func _new_sparks() -> CPUParticles3D:
	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = SPARKS_AT_FULL_DENSITY
	sparks.lifetime = 0.35
	sparks.explosiveness = 1.0
	sparks.spread = 50.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 6.0
	sparks.gravity = Vector3(0.0, -9.0, 0.0)
	sparks.mesh = _spark_meshes[0]
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.finished.connect(func() -> void: _impacts.release(sparks))
	return sparks


func _jitter(amount: float) -> Vector3:
	return Vector3(
		rng.randf_range(-amount, amount),
		rng.randf_range(-amount, amount),
		rng.randf_range(-amount, amount)
	)


static func _puff_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = (BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = texture
	return mat


static func _soft_texture() -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.55))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture


static func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
