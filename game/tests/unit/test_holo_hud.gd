extends GutTest
## P1-29/P1-30: HUD widgets. Bar damage trails, edge-marker placement, and
## the sleek HUD scene builds with its theme, fonts and radar.

const HUD: PackedScene = preload("res://ui/hud/hud.tscn")


func test_segment_bar_trail_drains_to_the_new_value() -> void:
	var bar: SegmentBar = SegmentBar.new()
	bar.trail_time = 0.2
	add_child_autofree(bar)
	bar.ratio = 0.4
	assert_eq(bar.get("_trail"), 1.0, "the lost part is remembered")
	await wait_seconds(0.35)
	assert_almost_eq(float(bar.get("_trail")), 0.4, 0.001, "and drained away")


func test_segment_bar_clamps() -> void:
	var bar: SegmentBar = SegmentBar.new()
	add_child_autofree(bar)
	bar.ratio = 3.0
	assert_eq(bar.ratio, 1.0)
	bar.ratio = -1.0
	assert_eq(bar.ratio, 0.0)


func test_edge_marker_lands_on_the_screen_border() -> void:
	var rect: Rect2 = Rect2(Vector2(34.0, 34.0), Vector2(1212.0, 652.0))
	var centre: Vector2 = Vector2(640.0, 360.0)
	var right: Vector2 = ThreatOverlay._edge_point(centre, Vector2.RIGHT, rect)
	assert_almost_eq(right.x, rect.end.x, 0.001)
	var up_left: Vector2 = ThreatOverlay._edge_point(centre, Vector2(-1.0, -1.0).normalized(), rect)
	assert_almost_eq(up_left.y, rect.position.y, 0.001, "hits the top edge first")


func test_hud_scene_builds_with_fonts() -> void:
	var hud: Hud = HUD.instantiate()
	add_child_autofree(hud)
	await wait_process_frames(2)
	var root: Control = hud.get_node("Root")
	assert_not_null(root.theme, "holo theme applied")
	var title: Label = hud.get_node("Root/Objective/Box/Title")
	assert_eq(title.get_theme_font("font").get_font_name(), "Orbitron")
	assert_eq(title.text, "FREE ROAM", "no director bound")
	hud.show_game_over(3, 42, 125.0)
	assert_true(hud.is_game_over_shown())
	var summary: Label = hud.get_node("Root/GameOver/Center/Panel/Box/Summary")
	assert_string_contains(summary.text, "42 DROIDS")


func test_line_bar_trail_drains() -> void:
	var bar: LineBar = LineBar.new()
	bar.trail_time = 0.2
	add_child_autofree(bar)
	bar.ratio = 0.25
	assert_eq(bar.get("_trail"), 1.0)
	await wait_seconds(0.35)
	assert_almost_eq(float(bar.get("_trail")), 0.25, 0.001)


func test_hud_has_radar_and_hides_the_hint_later() -> void:
	var hud: Hud = HUD.instantiate()
	add_child_autofree(hud)
	assert_true(hud.get_node("Root/RadarCard/Radar") is Radar)
	hud.set("_clock", Hud.HINT_TIME + 2.0)
	await wait_process_frames(2)
	assert_false((hud.get_node("Root/Hint") as Label).visible, "the controls hint fades out")
