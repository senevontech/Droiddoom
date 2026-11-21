class_name HitboxComponent
extends Area3D
## Attacker-side damage volume for explosions, slams, melee and contact hits.
## Not monitoring (no per-frame overlap cost): call `strike()` at the moment
## of impact and it runs one shape query against hurtbox areas.
## Its first CollisionShape3D child defines the volume. `collision_mask`
## selects the victims' faction layers (e.g. PhysicsLayers.PLAYER | ALLIES).

const MAX_RESULTS: int = 32

@export var damage: float = 10.0
@export var damage_type: DamageInfo.Type = DamageInfo.Type.KINETIC
## Knockback speed applied away from the hitbox centre (m/s).
@export var knockback: float = 0.0
## Who gets credit for the hit. Defaults to this node's parent.
@export var source: Node


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	# Only ever used for one-shot shape queries (strike), so keep it out of the
	# physics world: no broadphase updates every time the owner moves (P1-26).
	disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	process_mode = Node.PROCESS_MODE_DISABLED
	if source == null:
		source = get_parent()


## Damages every hurtbox inside the volume once. Several hurtboxes of one
## actor share a health; each health is only hit once (by its best zone).
## Returns the number of healths damaged.
func strike() -> int:
	var shape_node: CollisionShape3D = _first_shape()
	if shape_node == null or shape_node.shape == null:
		return 0
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(
		query, MAX_RESULTS
	)
	var best: Dictionary = {}
	for r: Dictionary in results:
		var hurtbox: HurtboxComponent = r["collider"] as HurtboxComponent
		if hurtbox == null or hurtbox.health == null:
			continue
		var key: int = hurtbox.health.get_instance_id()
		var current: HurtboxComponent = best.get(key)
		if current == null or hurtbox.zone_multiplier > current.zone_multiplier:
			best[key] = hurtbox
	var centre: Vector3 = shape_node.global_position
	for hurtbox: HurtboxComponent in best.values():
		var info: DamageInfo = DamageInfo.create(damage, damage_type, source, centre)
		if knockback > 0.0:
			var away: Vector3 = hurtbox.global_position - centre
			away.y = 0.0
			info.knockback = away.normalized() * knockback if away.length() > 0.01 else Vector3.ZERO
		hurtbox.take_hit(info)
	return best.size()


func _first_shape() -> CollisionShape3D:
	for child: Node in get_children():
		if child is CollisionShape3D:
			return child
	return null
