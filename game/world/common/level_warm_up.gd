class_name LevelWarmUp
extends CanvasLayer
## Kills first-use stutter (P1-27). The first time a material, effect or light
## is drawn, its shader compiles; on the Web (WebGL) that blocks the frame for
## a noticeable moment (reported by the user: "after the first shot the game
## gets stuck, then continues"). At level start, behind a short fade from black,
## this draws for a few frames:
## - one of every combat effect (CombatFX.warm_up, ProjectileSystem.warm_up),
##   including every pooled flash light, so world and actor materials compile
##   their lit variants too;
## - a small proxy box for every material of every droid that can spawn later
##   (and one with the hit-flash overlay).
## Then the proxies are freed and the cover fades out. Costs a few frames of
## loading time instead of hitches in combat.

signal finished

## Frames the proxies stay on screen (shaders compile on the first one; extra
## frames cover lit variants and pipeline creation).
const WARM_FRAMES: int = 4
const FADE_TIME: float = 0.35
## Proxies sit this far above the player's feet.
const PROXY_HEIGHT: float = 1.0
const COVER_COLOR: Color = Color(0.024, 0.031, 0.039, 1.0)

## Every droid that can appear in this level (their materials get warmed up).
@export var enemy_scenes: Array[PackedScene] = [
	preload("res://actors/enemies/swarmer/swarmer.tscn"),
	preload("res://actors/enemies/gunner/gunner.tscn"),
	preload("res://actors/enemies/kamikaze/kamikaze.tscn"),
	preload("res://actors/enemies/test_drone/test_drone.tscn"),
]

var _cover: ColorRect
var _proxies: Node3D
var _frame: int = 0
var _fade: float = 0.0
var _done: bool = false


func _ready() -> void:
	# Diagnostics: `-- --nowarmup` / `?nowarmup` skips it, to compare hitches.
	if PlatformServices.has_launch_flag("nowarmup"):
		_done = true
		queue_free.call_deferred()
		return
	layer = 100
	_cover = ColorRect.new()
	_cover.color = COVER_COLOR
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cover)


## Proxy meshes currently drawn (tests).
func get_proxy_count() -> int:
	return _proxies.get_child_count() if is_instance_valid(_proxies) else 0


func is_done() -> bool:
	return _done


func _process(delta: float) -> void:
	_frame += 1
	if _frame == 2:
		# Frame 1 lets the camera rig place itself; then put everything in view.
		_start()
	elif _frame == 2 + WARM_FRAMES:
		if is_instance_valid(_proxies):
			_proxies.queue_free()
	elif _frame > 2 + WARM_FRAMES:
		_fade += delta / maxf(Engine.time_scale, 0.01)
		_cover.color.a = clampf(1.0 - _fade / FADE_TIME, 0.0, 1.0)
		if _fade >= FADE_TIME:
			_done = true
			finished.emit()
			queue_free()


func _start() -> void:
	var at: Vector3 = _focus_point()
	var fx: CombatFX = get_tree().get_first_node_in_group(CombatFX.GROUP) as CombatFX
	if fx != null:
		fx.warm_up(at)
	var rounds: ProjectileSystem = (
		get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	)
	if rounds != null:
		rounds.warm_up(at + Vector3.UP * 0.5, WARM_FRAMES)
	_spawn_proxies(at)


## Where the player is (always in view in both cameras).
func _focus_point() -> Vector3:
	var player: Node3D = get_tree().get_first_node_in_group(Hollow.PLAYER_GROUP) as Node3D
	if player != null:
		return player.global_position + Vector3.UP * PROXY_HEIGHT
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position - camera.global_basis.z * 6.0
	return Vector3.ZERO


## One small box per distinct droid material, plus one with the hit flash.
func _spawn_proxies(at: Vector3) -> void:
	var parent: Node = (
		get_tree().current_scene if get_tree().current_scene != null else get_parent()
	)
	_proxies = Node3D.new()
	_proxies.name = "WarmUpProxies"
	parent.add_child(_proxies)
	var materials: Array[Material] = collect_materials(enemy_scenes)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE * 0.2
	for i in materials.size() + 1:
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.mesh = box
		if i < materials.size():
			proxy.material_override = materials[i]
		else:
			proxy.material_overlay = HitFlash.OVERLAY
		proxy.position = at + Vector3((i % 6) * 0.25 - 0.6, (i / 6) * 0.25, 0.0)
		_proxies.add_child(proxy)


## Every distinct material used by meshes in `scenes` (instanced, never added
## to the tree, so no droid logic runs).
static func collect_materials(scenes: Array[PackedScene]) -> Array[Material]:
	var out: Array[Material] = []
	for scene: PackedScene in scenes:
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var mat: Material = mesh.get_active_material(surface)
				if mat != null and not out.has(mat):
					out.append(mat)
		root.free()
	return out
