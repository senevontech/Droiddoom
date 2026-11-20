extends GutTest
## P1-08/P1-09: in the real spike street (playground scene), the navigation
## mesh bakes from the street's colliders and the droids (Swarmer, Gunner,
## Kamikaze mix) notice HOLLOW, close in and hurt it. Needs the LFS art
## (street textures/props), so it is pending in CI, which checks out without LFS.

const PLAYGROUND: String = "res://world/dev/playground/playground.tscn"
const PROBE: String = "res://assets/textures/pbr/metal_plate/metal_plate_diff_1k.jpg"

var _scene: Node3D


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.free()


func test_drones_close_in_on_hollow_in_the_street() -> void:
	if not _has_lfs_art():
		pending("Needs LFS art (CI runs without LFS)")
		return
	_scene = (load(PLAYGROUND) as PackedScene).instantiate()
	add_child(_scene)
	var hollow: Hollow = _scene.get_node("Hollow")
	var nav: NavigationRegion3D = _scene.get_node("Navigation")
	assert_gt(nav.navigation_mesh.get_polygon_count(), 50, "street navmesh baked")
	var drones: Array[BaseEnemy] = []
	for child: Node in _scene.get_node("Enemies").get_children():
		drones.append(child as BaseEnemy)
	assert_eq(drones.size(), 6, "one droid per DroidSpawn marker")
	var start: float = _mean_distance(drones, hollow)
	var ids: Array[int] = []
	for drone: BaseEnemy in drones:
		ids.append(drone.get_instance_id())

	await wait_physics_frames(600)

	# Awake = chasing/attacking, or already gone (a Kamikaze that blew up).
	var awake: int = 0
	var alive: Array[BaseEnemy] = []
	for id: int in ids:
		var drone: BaseEnemy = instance_from_id(id) as BaseEnemy
		if drone == null or drone.health.is_dead():
			awake += 1
		elif drone.get_state() != BaseEnemy.STATE_IDLE:
			awake += 1
			alive.append(drone)
		else:
			alive.append(drone)
	# One spawn group (3 droids) sees HOLLOW and relays the alert (D-029). The
	# other group, 56 m away behind barricades, has no line of sight and is
	# out of relay range, so it stays idle until it hears shots (P1-17).
	assert_gte(awake, 3, "a whole spawn group noticed HOLLOW")
	assert_lt(_mean_distance(alive, hollow), start - 8.0, "droids closed in")
	assert_lt(hollow.health.get_health(), hollow.stats.max_hp, "and started hurting HOLLOW")


func _mean_distance(drones: Array[BaseEnemy], hollow: Node3D) -> float:
	var total: float = 0.0
	for drone: BaseEnemy in drones:
		total += drone.global_position.distance_to(hollow.global_position)
	return total / drones.size()


func _has_lfs_art() -> bool:
	var probe: FileAccess = FileAccess.open(PROBE, FileAccess.READ)
	return probe != null and probe.get_buffer(7).get_string_from_ascii() != "version"
