extends GutTest
## Sanity checks for the Phase 0 scaffold: renderer, input actions,
## collision layer names and autoloads must match the TDD (§3.2, §3.6, §3.7).

const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"aim_left",
	&"aim_right",
	&"aim_up",
	&"aim_down",
	&"fire_primary",
	&"fire_heavy",
	&"ability",
	&"reclaim",
	&"switch_camera",
	&"pause",
	&"toggle_debug",
	&"weapon_next",
	&"weapon_prev",
	&"weapon_slot_1",
	&"weapon_slot_2",
	&"weapon_slot_3",
	&"weapon_slot_4",
	&"heavy_next",
	&"reload",
]

const REQUIRED_LAYERS: Dictionary = {
	1: "world",
	2: "player",
	3: "player_projectiles",
	4: "enemies",
	5: "enemy_projectiles",
	6: "pickups",
	7: "allies",
	8: "triggers",
	9: "camera_occluders",
	10: "navigation_only",
}

const REQUIRED_AUTOLOADS: Array[String] = [
	"EventBus",
	"Settings",
	"Profile",
	"SaveManager",
	"Economy",
	"GameState",
	"QualityManager",
	"InputRouter",
	"AudioManager",
	"PlatformServices",
	"SceneRouter",
]


func test_renderer_is_compatibility() -> void:
	var method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	assert_eq(method, "gl_compatibility", "D-014: Compatibility renderer is the baseline")


func test_required_input_actions_exist() -> void:
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "Missing input action: %s" % action)


func test_collision_layer_names_match_tdd() -> void:
	for layer: int in REQUIRED_LAYERS:
		var key: String = "layer_names/3d_physics/layer_%d" % layer
		assert_eq(ProjectSettings.get_setting(key, ""), REQUIRED_LAYERS[layer], key)


func test_autoloads_are_registered() -> void:
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_not_null(
			get_tree().root.get_node_or_null(autoload_name), "Missing autoload: %s" % autoload_name
		)


func test_camera_mode_toggles() -> void:
	var start: int = Settings.camera_mode
	Settings.toggle_camera_mode()
	assert_ne(Settings.camera_mode, start, "toggle should change the mode")
	Settings.toggle_camera_mode()
	assert_eq(Settings.camera_mode, start, "toggling twice returns to the start mode")


func test_new_profile_starts_with_zero_currencies() -> void:
	Profile.reset()
	assert_eq(Economy.get_amount(Economy.SCRAP), 0)
	assert_eq(Economy.get_amount(Economy.SHARDS), 0)
	assert_eq(Economy.get_amount(Economy.CORES), 0)
