extends GutTest
## P1-11 / P1-31: the touch overlay drives the same input actions as keyboard
## and gamepad. Hybrid sticks, AUTO vs MANUAL fire, the arc buttons, the
## fire-mode toggle and the pause button. Emulated mouse events never kick the
## game out of touch mode.
## Touch events are fed to `TouchControls.handle_event()` (what `_input`
## calls): inside the headless test runner, touch events never reach a
## node's `_input`. Real delivery is checked in Chrome's touch emulation.

var _touch: TouchControls
var _old_device: InputRouter.Device
var _old_mode: Settings.CameraMode
var _old_fire: Settings.TouchFireMode
var _on_target: bool = false


func before_each() -> void:
	_old_device = InputRouter.active_device
	_old_mode = Settings.camera_mode
	_old_fire = Settings.touch_fire_mode
	Settings.camera_mode = Settings.CameraMode.TACTICAL
	Settings.touch_fire_mode = Settings.TouchFireMode.AUTO
	InputRouter.active_device = InputRouter.Device.TOUCH
	_on_target = false
	_touch = TouchControls.new()
	_touch.aim_on_target = func() -> bool: return _on_target
	add_child_autofree(_touch)
	_touch.size = Vector2(1280.0, 720.0)
	EventBus.input_device_changed.emit(InputRouter.Device.TOUCH)


func after_each() -> void:
	_touch.set_enabled(false)
	InputRouter.active_device = _old_device
	Settings.camera_mode = _old_mode
	Settings.touch_fire_mode = _old_fire
	InputRouter.consume_look_drag()


func test_shown_only_in_touch_mode() -> void:
	assert_true(_touch.visible)
	InputRouter.active_device = InputRouter.Device.KEYBOARD_MOUSE
	EventBus.input_device_changed.emit(InputRouter.Device.KEYBOARD_MOUSE)
	assert_false(_touch.visible)


func test_sticks_jump_to_the_thumb_and_work_together() -> void:
	_touch_at(0, Vector2(300.0, 450.0), true)  # not on the move stick's home spot
	_touch_at(1, Vector2(700.0, 500.0), true)
	_drag(0, Vector2(390.0, 450.0))
	_drag(1, Vector2(700.0, 420.0))
	await wait_process_frames(2)
	assert_gt(InputRouter.get_move_vector().x, 0.8, "moving right")
	assert_lt(InputRouter.get_stick_aim_vector().y, -0.6, "aiming forward")
	_touch_at(0, Vector2(390.0, 450.0), false)
	_touch_at(1, Vector2(700.0, 420.0), false)
	await wait_process_frames(2)
	assert_eq(InputRouter.get_move_vector(), Vector2.ZERO, "released")


func test_auto_mode_fires_only_while_on_target() -> void:
	await wait_process_frames(2)
	assert_false(InputRouter.is_primary_fire_held(), "nothing in the sights")
	_on_target = true
	await wait_process_frames(2)
	assert_true(InputRouter.is_primary_fire_held(), "auto-fire on a droid")
	_on_target = false
	await wait_process_frames(2)
	assert_false(InputRouter.is_primary_fire_held())


func test_manual_mode_fires_only_with_the_fire_button() -> void:
	Settings.touch_fire_mode = Settings.TouchFireMode.MANUAL
	_on_target = true
	await wait_process_frames(2)
	assert_false(InputRouter.is_primary_fire_held(), "manual ignores the target")
	var fire_at: Vector2 = _touch.get_button_centre("FIRE")
	_touch_at(4, fire_at, true)
	await wait_process_frames(2)
	assert_true(InputRouter.is_primary_fire_held(), "FIRE held")
	_touch_at(4, fire_at, false)
	await wait_process_frames(2)
	assert_false(InputRouter.is_primary_fire_held())


func test_mode_pill_toggles_auto_and_manual() -> void:
	var pill: Vector2 = _touch.get_button_centre("AUTO")
	_touch_at(5, pill, true)
	_touch_at(5, pill, false)
	assert_eq(Settings.touch_fire_mode, Settings.TouchFireMode.MANUAL)
	_touch_at(5, pill, true)
	_touch_at(5, pill, false)
	assert_eq(Settings.touch_fire_mode, Settings.TouchFireMode.AUTO)


func test_arc_buttons_sit_around_fire() -> void:
	var fire_at: Vector2 = _touch.get_button_centre("FIRE")
	for label: String in ["DASH", "HEAVY", "SWAP", "RELOAD"]:
		var at: Vector2 = _touch.get_button_centre(label)
		assert_almost_eq(at.distance_to(fire_at), 122.0, 1.0, "%s on the arc" % label)
		assert_true(Rect2(Vector2.ZERO, _touch.size).has_point(at), "%s on screen" % label)


func test_reload_button_is_a_one_frame_tap() -> void:
	var reload_at: Vector2 = _touch.get_button_centre("RELOAD")
	var seen: Array[bool] = []
	var poll: Callable = func() -> void: seen.append(Input.is_action_pressed(&"reload"))
	get_tree().process_frame.connect(poll)
	_touch_at(2, reload_at, true)
	_touch_at(2, reload_at, false)
	await wait_process_frames(5)
	get_tree().process_frame.disconnect(poll)
	assert_true(seen.has(true), "the tap pressed reload")
	assert_lt(seen.count(true), 3, "for a frame or so, not held")
	assert_false(Input.is_action_pressed(&"reload"), "then released")


func test_pause_button_asks_for_the_pause_menu() -> void:
	watch_signals(_touch)
	var pause_at: Vector2 = _touch.get_button_centre("II")
	_touch_at(6, pause_at, true)
	assert_signal_emitted(_touch, "pause_requested")
	_touch_at(6, pause_at, false)


func test_shoulder_right_side_drags_the_camera() -> void:
	Settings.camera_mode = Settings.CameraMode.SHOULDER
	_touch_at(3, Vector2(900.0, 300.0), true)
	_drag(3, Vector2(960.0, 290.0), Vector2(60.0, -10.0))
	assert_eq(InputRouter.consume_look_drag(), Vector2(60.0, -10.0))
	_touch_at(3, Vector2(960.0, 290.0), false)


func test_emulated_mouse_events_keep_touch_mode() -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.device = InputEvent.DEVICE_ID_EMULATION
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await wait_process_frames(1)
	assert_eq(InputRouter.active_device, InputRouter.Device.TOUCH)


func _touch_at(index: int, at: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	_touch.handle_event(event)


func _drag(index: int, at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = relative
	_touch.handle_event(event)
