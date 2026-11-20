class_name Explosion
extends RefCounted
## Blast damage (D-030): one sphere query against hurtbox areas, then a wall
## check per victim. Damage and push fall off from 100% at the centre to
## `EDGE_FALLOFF` at the edge. Each actor (HealthComponent) is hit once, with
## no weak-spot bonus. Used by rockets and grenades now, Kamikazes and
## barrels later. Emits EventBus.explosion_happened for FX, debris and hearing.

const EDGE_FALLOFF: float = 0.25
const MAX_RESULTS: int = 32
## Blasts lift things a little as well as pushing them away.
const LIFT: float = 0.45


## Returns the number of actors damaged.
static func detonate(
	world: World3D,
	center: Vector3,
	radius: float,
	damage: float,
	type: DamageInfo.Type,
	force: float,
	target_mask: int,
	source: Node = null
) -> int:
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = target_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	# One hurtbox per actor: the one nearest the centre.
	var nearest: Dictionary = {}
	for r: Dictionary in space.intersect_shape(query, MAX_RESULTS):
		var hurtbox: HurtboxComponent = r["collider"] as HurtboxComponent
		if hurtbox == null or hurtbox.health == null or hurtbox.health.is_dead():
			continue
		var key: int = hurtbox.health.get_instance_id()
		var current: HurtboxComponent = nearest.get(key)
		if (
			current == null
			or (
				centre_of(hurtbox).distance_squared_to(center)
				< centre_of(current).distance_squared_to(center)
			)
		):
			nearest[key] = hurtbox
	var count: int = 0
	for hurtbox: HurtboxComponent in nearest.values():
		var at: Vector3 = centre_of(hurtbox)
		if not _clear_line(space, center, at):
			continue
		var scale: float = falloff(center.distance_to(at), radius)
		var info: DamageInfo = DamageInfo.create(damage * scale, type, source, at)
		var away: Vector3 = at - center
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
		info.knockback = away * force * scale
		info.impulse = (away + Vector3.UP * LIFT).normalized() * force * scale
		hurtbox.health.apply_damage(info, 1.0)
		count += 1
	EventBus.explosion_happened.emit(center, radius, type)
	return count


## Middle of a hurtbox's first shape (the area's own origin is usually at
## the actor's feet, where a wall check would hit the floor).
static func centre_of(hurtbox: HurtboxComponent) -> Vector3:
	for child: Node in hurtbox.get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape != null:
			return shape.global_position
	return hurtbox.global_position


## Damage share at `distance` from the centre of a blast of `radius`.
static func falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return lerpf(1.0, EDGE_FALLOFF, clampf(distance / radius, 0.0, 1.0))


static func _clear_line(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, PhysicsLayers.WORLD
	)
	return space.intersect_ray(query).is_empty()
