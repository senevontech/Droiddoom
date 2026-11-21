class_name MeshMerger
extends RefCounted
## Draw-call diet for rigid-part actors (P1-25). Our robots are built from many
## small meshes (GDD §16), and each one costs a draw call, plus another in the
## shadow pass. `merge_tree()` replaces every group of 2+ sibling meshes with
## ONE MeshInstance3D that has one surface per material, under the same parent.
## Parts that move on their own (HOLLOW's legs vs turret, a Kamikaze's rolling
## shell, a pulsing telegraph) live under their own parent node, so they stay
## separate groups and keep animating.
##
## The original parts are kept, hidden and tagged, so DebrisSystem can still
## break the actor into its real parts when it dies. Merged meshes are built
## once per scene and cached on the PackedScene resource (no leaks, no rebuild
## per spawn).

## Meta on the merged MeshInstance3D.
const MERGED: StringName = &"mesh_merger_merged"
## Meta on each hidden original part.
const PART: StringName = &"mesh_merger_part"
const CACHE_PREFIX: String = "merged_mesh_"


## Merges every sibling group of 2+ visible meshes under `root` (recursively).
## Returns the number of meshes hidden (parts merged away).
static func merge_tree(root: Node) -> int:
	if root == null:
		return 0
	var merged: int = 0
	var groups: Array[Node] = [root]
	groups.append_array(root.find_children("*", "Node3D", true, false))
	for parent: Node in groups:
		merged += _merge_children(parent, root)
	return merged


## True if `mesh` is a merged mesh made by this class.
static func is_merged(mesh: Node) -> bool:
	return mesh.has_meta(MERGED)


## True if `mesh` is a hidden original part (still usable as debris).
static func is_part(mesh: Node) -> bool:
	return mesh.has_meta(PART)


static func _merge_children(parent: Node, root: Node) -> int:
	var parts: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null and mesh.visible and mesh.mesh != null and not is_merged(mesh):
			parts.append(mesh)
	if parts.size() < 2:
		return 0
	var merged_mesh: ArrayMesh = _cached_or_built(parts, parent, root)
	var merged: MeshInstance3D = MeshInstance3D.new()
	merged.name = "MergedParts"
	merged.mesh = merged_mesh
	merged.set_meta(MERGED, true)
	merged.cast_shadow = parts[0].cast_shadow
	parent.add_child(merged)
	for part: MeshInstance3D in parts:
		part.visible = false
		part.set_meta(PART, true)
	return parts.size()


## One surface per material, every part baked in at its local transform.
static func build(parts: Array[MeshInstance3D]) -> ArrayMesh:
	var by_material: Dictionary = {}
	var order: Array[Material] = []
	for part: MeshInstance3D in parts:
		for surface in part.mesh.get_surface_count():
			var mat: Material = part.get_active_material(surface)
			if not by_material.has(mat):
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_material[mat] = tool
				order.append(mat)
			(by_material[mat] as SurfaceTool).append_from(part.mesh, surface, part.transform)
	var out: ArrayMesh = ArrayMesh.new()
	for mat: Material in order:
		var tool: SurfaceTool = by_material[mat]
		tool.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


static func _cached_or_built(parts: Array[MeshInstance3D], parent: Node, root: Node) -> ArrayMesh:
	var scene: Resource = _scene_of(root)
	var key: StringName = StringName(CACHE_PREFIX + str(root.get_path_to(parent)).md5_text())
	if scene != null and scene.has_meta(key):
		return scene.get_meta(key)
	var built: ArrayMesh = build(parts)
	if scene != null:
		scene.set_meta(key, built)
	return built


## The PackedScene `root` was instanced from (cached by ResourceLoader), or null.
static func _scene_of(root: Node) -> Resource:
	var path: String = root.scene_file_path
	if path == "" or not ResourceLoader.has_cached(path):
		return null
	return ResourceLoader.get_cached_ref(path)
