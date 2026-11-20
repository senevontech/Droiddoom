class_name NeuralSync
extends RefCounted
## Neural Sync detection (P1-12, GDD §4.4): a dash is "perfect" when a hit
## would have landed on the player within a short window of the dash
## starting. Counts two kinds of threat:
## - **Rounds in flight** (ProjectileSystem) that target the player's faction
##   and whose path over the window crosses the player's hurt capsule.
## - **Telegraphed attacks** (melee windups, Kamikaze arming) that resolve
##   within the window and whose reach covers the player.
## The reward (slow-motion + damage bonus) listens to
## `EventBus.neural_sync_triggered` (P1-13).

## Player hurt capsule (matches HOLLOW's hurtbox: radius 0.5, 0.5–1.5 m
## inner segment) plus a little slack for "it was that close".
const CAPSULE_BOTTOM: float = 0.5
const CAPSULE_TOP: float = 1.5
const CAPSULE_RADIUS: float = 0.6


## Number of hits that would have landed on `player` within `window` seconds.
static func count_threats(player: Node3D, window: float) -> int:
	var tree: SceneTree = player.get_tree()
	var base: Vector3 = player.global_position
	var bottom: Vector3 = base + Vector3.UP * CAPSULE_BOTTOM
	var top: Vector3 = base + Vector3.UP * CAPSULE_TOP
	var count: int = 0
	var rounds: ProjectileSystem = tree.get_first_node_in_group(ProjectileSystem.GROUP)
	if rounds != null:
		count += rounds.count_threats(bottom, top, CAPSULE_RADIUS, window, PhysicsLayers.PLAYER)
	var coordinator: EnemyCoordinator = tree.get_first_node_in_group(EnemyCoordinator.GROUP)
	if coordinator != null:
		for node: Node3D in coordinator.get_live_enemies():
			var enemy: BaseEnemy = node as BaseEnemy
			if enemy == null:
				continue
			var distance: float = enemy.global_position.distance_to(base)
			if attack_threatens(enemy.get_attack_eta(), enemy.get_threat_reach(), distance, window):
				count += 1
	return count


## True if a telegraphed attack landing in `eta` seconds (-1 = none) with
## `reach` metres hits something `distance` metres away within `window`.
static func attack_threatens(eta: float, reach: float, distance: float, window: float) -> bool:
	return eta >= 0.0 and eta <= window and reach > 0.0 and distance <= reach


## True if a round at `from` moving at `velocity` passes within `radius` of
## the segment `bottom`–`top` during the next `window` seconds (straight-line
## prediction: over 0.2 s gravity moves a round by ~2 cm).
static func round_threatens(
	from: Vector3, velocity: Vector3, window: float, bottom: Vector3, top: Vector3, radius: float
) -> bool:
	var to: Vector3 = from + velocity * window
	var closest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
		from, to, bottom, top
	)
	return closest[0].distance_to(closest[1]) <= radius
