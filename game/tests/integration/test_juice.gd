extends GutTest
## P1-13: hit flash, camera shake (with the accessibility toggle), sound
## wiring, and the weapon hooks Neural Sync uses (damage bonus, haste).

const RIG: PackedScene = preload("res://actors/player/camera/camera_rig.tscn")
const RIFLE: WeaponData = preload("res://data/weapons/weapon_pulse_rifle.tres")
const WEAPONS: Array[String] = [
	"res://data/weapons/weapon_pulse_rifle.tres",
	"res://data/weapons/weapon_scattergun.tres",
	"res://data/weapons/weapon_beam_laser.tres",
	"res://data/weapons/weapon_railgun.tres",
	"res://data/weapons/weapon_rocket_pod.tres",
	"res://data/weapons/weapon_grenade_launcher.tres",
	"res://data/weapons/weapon_axiom_blaster.tres",
]

var _root: Node3D
var _shake_setting: bool


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_shake_setting = Settings.screen_shake_enabled


func after_each() -> void:
	Settings.screen_shake_enabled = _shake_setting


func test_hit_flash_overlays_then_clears() -> void:
	var actor: Node3D = Node3D.new()
	_root.add_child(actor)
	for i in 3:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		actor.add_child(mesh)
	var flash: HitFlash = HitFlash.new(actor)
	assert_eq(flash.get_mesh_count(), 3)
	flash.flash(actor)
	assert_true(flash.is_flashing())
	await wait_seconds(HitFlash.FLASH_TIME + 0.05)
	assert_false(flash.is_flashing(), "cleared after a few frames")


func test_enemy_flashes_when_hit() -> void:
	_root.add_child(EnemyCoordinator.new())
	var drone: BaseEnemy = (
		(load("res://actors/enemies/swarmer/swarmer.tscn") as PackedScene).instantiate()
	)
	_root.add_child(drone)
	var any_mesh: MeshInstance3D = drone.visuals.find_children("*", "MeshInstance3D")[0]
	drone.health.apply_damage(DamageInfo.create(1.0, DamageInfo.Type.KINETIC))
	assert_not_null(any_mesh.material_overlay)


func test_camera_shake_builds_and_decays() -> void:
	var rig: CameraRig = _rig()
	await wait_process_frames(1)
	Settings.screen_shake_enabled = true
	EventBus.explosion_happened.emit(rig.target.global_position + Vector3(2.0, 0.0, 0.0), 3.5, 0)
	var peak: float = rig.get_trauma()
	assert_gt(peak, 0.3, "a nearby blast shakes the camera")
	await wait_seconds(0.3)
	assert_lt(rig.get_trauma(), peak, "and it settles")


func test_far_blasts_and_the_toggle_mean_no_shake() -> void:
	var rig: CameraRig = _rig()
	await wait_process_frames(1)
	EventBus.explosion_happened.emit(rig.target.global_position + Vector3(80.0, 0.0, 0.0), 3.5, 0)
	assert_eq(rig.get_trauma(), 0.0, "too far away")
	Settings.screen_shake_enabled = false
	rig.add_trauma(1.0)
	assert_eq(rig.get_trauma(), 0.0, "screen shake off (accessibility)")


func test_every_weapon_has_a_sound() -> void:
	for path: String in WEAPONS:
		var data: WeaponData = load(path)
		assert_true(AudioManager.has_sound(data.fire_sfx), "%s → %s" % [path, data.fire_sfx])


func test_combat_events_play_sounds_with_a_repeat_limit() -> void:
	# Other tests also set off blasts: wait out the repeat limit first.
	await get_tree().create_timer(0.25, true, false, true).timeout
	var before: int = AudioManager.get_played_count()
	EventBus.explosion_happened.emit(Vector3.ZERO, 3.5, 0)
	assert_eq(AudioManager.get_played_count(), before + 1)
	EventBus.explosion_happened.emit(Vector3.ZERO, 3.5, 0)
	assert_eq(AudioManager.get_played_count(), before + 1, "same sound again at once: skipped")


func test_damage_scale_boosts_hits() -> void:
	var gun: Weapon = _weapon()
	gun.damage_scale = 1.5
	var target: HealthComponent = _target(Vector3(0.0, 1.0, -8.0))
	await wait_physics_frames(2)
	gun.try_fire(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -8.0))
	await wait_physics_frames(10)
	assert_eq(target.get_health(), 100.0 - RIFLE.damage * 1.5)


func test_time_scale_speeds_up_the_fire_rate() -> void:
	var gun: Weapon = _weapon()
	gun.time_scale = 4.0
	await wait_physics_frames(1)
	assert_true(gun.try_fire(Vector3.ZERO, Vector3.FORWARD))
	await wait_seconds(gun.data.fire_interval / 4.0 + 0.03)
	assert_true(gun.can_fire(), "cooled down four times faster")


func _rig() -> CameraRig:
	var target: Node3D = Node3D.new()
	_root.add_child(target)
	var rig: CameraRig = RIG.instantiate()
	rig.target = target
	_root.add_child(rig)
	return rig


func _weapon() -> Weapon:
	_root.add_child(ProjectileSystem.new())
	var gun: Weapon = Weapon.new()
	gun.data = RIFLE.duplicate()
	gun.data.spread_deg = 0.0
	gun.data.crit_chance = 0.0
	_root.add_child(gun)
	return gun


func _target(pos: Vector3) -> HealthComponent:
	var actor: Node3D = Node3D.new()
	actor.position = pos
	_root.add_child(actor)
	var health: HealthComponent = HealthComponent.new()
	health.name = "Health"
	actor.add_child(health)
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.collision_layer = PhysicsLayers.ENEMIES
	hurtbox.collision_mask = 0
	hurtbox.health = health
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	hurtbox.add_child(shape)
	actor.add_child(hurtbox)
	return health
