extends GutTest
## P1-31: the pause menu pauses the game, its controls change Settings, and
## it never leaves the tree paused.

const PAUSE: PackedScene = preload("res://ui/pause/pause_menu.tscn")

var _menu: PauseMenu
var _saved: Dictionary = {}


func before_each() -> void:
	for key: String in [
		"touch_fire_mode",
		"touch_look_sensitivity",
		"touch_button_scale",
		"touch_opacity",
		"aim_assist",
		"screen_shake_enabled"
	]:
		_saved[key] = Settings.get(key)
	_menu = PAUSE.instantiate()
	add_child_autofree(_menu)


func after_each() -> void:
	get_tree().paused = false
	for key: String in _saved:
		Settings.set(key, _saved[key])


func test_open_pauses_and_close_resumes() -> void:
	_menu.open()
	assert_true(_menu.is_open())
	assert_true(get_tree().paused)
	_menu.close()
	assert_false(get_tree().paused)


func test_controls_write_settings() -> void:
	_menu.open()
	(_menu.get_node("Root/Center/Panel/Box/FireRow/Manual") as Button).emit_signal("pressed")
	assert_eq(Settings.touch_fire_mode, Settings.TouchFireMode.MANUAL)
	(_menu.get_node("Root/Center/Panel/Box/Size/Slider") as HSlider).value = 1.3
	assert_almost_eq(Settings.touch_button_scale, 1.3, 0.001)
	(_menu.get_node("Root/Center/Panel/Box/Look/Slider") as HSlider).value = 2.0
	assert_almost_eq(Settings.touch_look_sensitivity, 2.0, 0.001)
	_menu.close()


func test_blocked_when_not_allowed() -> void:
	_menu.allowed = false
	_menu.open()
	assert_false(_menu.is_open())
	assert_false(get_tree().paused)


func test_settings_clamp_their_ranges() -> void:
	Settings.set_value(&"touch_button_scale", 9.0)
	assert_eq(Settings.touch_button_scale, 1.4)
	Settings.set_value(&"touch_opacity", 0.0)
	assert_eq(Settings.touch_opacity, 0.25)
