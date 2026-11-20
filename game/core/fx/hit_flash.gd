class_name HitFlash
extends RefCounted
## Brief white flash on a hit actor (P1-13). Puts one shared overlay
## material on the actor's meshes for FLASH_TIME, then removes it. No
## per-actor materials are created, and the extra pass only exists while
## flashing (a few frames), so the cost is negligible.

const FLASH_TIME: float = 0.07

## Shared overlay (a resource file: a static var would leak at exit).
const OVERLAY: StandardMaterial3D = preload("res://core/fx/hit_flash_overlay.tres")

var _meshes: Array[GeometryInstance3D] = []
## Bumped on every flash; a timer only clears the flash it started. (Keeping
## the timer itself would make a timer <-> HitFlash reference cycle: a leak.)
var _generation: int = 0


## Remembers every mesh under `root` (call once, after the actor is built).
func _init(root: Node) -> void:
	if root != null:
		_collect(root)


## Number of meshes that flash (tests).
func get_mesh_count() -> int:
	return _meshes.size()


## True while the overlay is on.
func is_flashing() -> bool:
	return not _meshes.is_empty() and _meshes[0].material_overlay != null


## Flashes now; another hit during a flash just restarts it.
func flash(owner: Node) -> void:
	if _meshes.is_empty() or not owner.is_inside_tree():
		return
	for mesh: GeometryInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = OVERLAY
	_generation += 1
	var mine: int = _generation
	owner.get_tree().create_timer(FLASH_TIME, false).timeout.connect(
		func() -> void:
			if mine == _generation:
				clear()
	)


## Removes the overlay.
func clear() -> void:
	for mesh: GeometryInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func _collect(node: Node) -> void:
	for child: Node in node.get_children():
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if geometry != null and geometry is MeshInstance3D:
			_meshes.append(geometry)
		_collect(child)
