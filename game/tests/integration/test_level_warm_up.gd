extends GutTest
## P1-27: the level warm-up draws one of every effect and droid material for
## a few frames, then cleans up after itself and fades out.


func test_collects_every_droid_material() -> void:
	var scenes: Array[PackedScene] = [
		load("res://actors/enemies/swarmer/swarmer.tscn"),
		load("res://actors/enemies/kamikaze/kamikaze.tscn"),
	]
	var materials: Array[Material] = LevelWarmUp.collect_materials(scenes)
	assert_gte(materials.size(), 5, "hull, joints, optic, core, warning ring…")
	for mat: Material in materials:
		assert_eq(materials.count(mat), 1, "no duplicates")


func test_warm_up_shows_proxies_then_cleans_up() -> void:
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	var fx: CombatFX = CombatFX.new()
	root.add_child(fx)
	var rounds: ProjectileSystem = ProjectileSystem.new()
	root.add_child(rounds)
	var warm: LevelWarmUp = LevelWarmUp.new()
	root.add_child(warm)
	var finished: Array[bool] = [false]
	warm.finished.connect(func() -> void: finished[0] = true)
	await wait_process_frames(3)
	assert_gt(warm.get_proxy_count(), 5, "material proxies on screen")
	assert_gt(fx.get_live_beam_count(), 0, "beams drawn")
	assert_gt(fx.get_puff_count(), 0, "puffs drawn")
	await wait_seconds(0.8)
	assert_true(finished[0], "finished was emitted")
	assert_false(is_instance_valid(warm), "removed itself")
	assert_false(rounds.is_warming_up())
