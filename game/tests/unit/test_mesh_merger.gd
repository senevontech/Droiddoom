extends GutTest
## P1-25: sibling meshes merge into one mesh per material; originals stay as
## hidden, tagged parts for debris; separate groups stay separate.

const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")


func test_siblings_merge_into_one_surface_per_material() -> void:
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	var red: StandardMaterial3D = StandardMaterial3D.new()
	var blue: StandardMaterial3D = StandardMaterial3D.new()
	root.add_child(_box(Vector3(0, 0, 0), red))
	root.add_child(_box(Vector3(2, 0, 0), red))
	root.add_child(_box(Vector3(0, 2, 0), blue))
	var hidden: int = MeshMerger.merge_tree(root)
	assert_eq(hidden, 3)
	var visible: Array[MeshInstance3D] = _visible_meshes(root)
	assert_eq(visible.size(), 1, "one draw instead of three")
	var merged: ArrayMesh = visible[0].mesh
	assert_eq(merged.get_surface_count(), 2, "one surface per material")
	assert_true(MeshMerger.is_merged(visible[0]))
	var aabb: AABB = merged.get_aabb()
	assert_almost_eq(aabb.end.x, 2.5, 0.001, "parts keep their positions")
	assert_almost_eq(aabb.end.y, 2.5, 0.001)


func test_single_meshes_and_separate_groups_are_left_alone() -> void:
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	root.add_child(_box(Vector3.ZERO, null))
	var turret: Node3D = Node3D.new()
	root.add_child(turret)
	turret.add_child(_box(Vector3.ZERO, null))
	turret.add_child(_box(Vector3(1, 0, 0), null))
	MeshMerger.merge_tree(root)
	var direct: int = 0
	for child: Node in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).visible:
			direct += 1
	assert_eq(direct, 1, "a lone mesh is not merged")
	assert_eq(_visible_meshes(turret).size(), 1, "the turret group merged on its own")


func test_droid_draws_far_fewer_meshes_but_still_shatters_into_parts() -> void:
	var holder: Node3D = Node3D.new()
	add_child_autofree(holder)
	holder.add_child(EnemyCoordinator.new())
	var debris: DebrisSystem = DebrisSystem.new()
	holder.add_child(debris)
	var droid: BaseEnemy = SWARMER.instantiate()
	holder.add_child(droid)
	assert_lte(_visible_meshes(droid.visuals).size(), 3, "merged body + telegraph eye")
	droid.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.KINETIC))
	assert_gt(debris.get_active_count(), 6, "the original parts still fly apart")


func _box(pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	return mesh


func _visible_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.is_visible_in_tree():
			out.append(mesh)
	return out
