extends GutTest
## P1-11: the touch overlay drives the same input actions as keyboard and
## gamepad. Multi-touch (move + aim/fire at once), tap buttons, drag-look in
## Shoulder, and emulated mouse events never kick the game out of touch mode.
## Touch events are fed to `TouchControls.handle_event()` (what `_input`
## calls): inside the headless test runner, touch events never reach a
## node's `_input`. Real delivery is checked in Chrome's touch emulation.

var _touch: TouchControls
var _old_device: InputRouter.Device
var _old_mode: Settings.CameraMode


func before_each() -> void:
	_old_device = InputRouter.active_device
	_old_mode = Settings.camera_mode
	Settings.camera_mode = Settings.CameraMode.TACTICAL
	InputRouter.active_device = InputRouter.Device.TOUCH
	_touch = TouchControls.new()
	add_child_autofree(_touch)
	_touch.size = Vector2(1280.0, 720.0)
	EventBus.input_device_changed.emit(InputRouter.Device.TOUCH)


func after_each() -> void:
	_touch.set_enabled(false)
	InputRouter.active_device = _old_device
	Settings.camera_mode = _old_mode
	InputRouter.consume_look_drag()


func test_shown_only_in_touch_mode() -> void:
	assert_true(_touch.visible)
	InputRouter.active_device = InputRouter.Device.KEYBOARD_MOUSE
	EventBus.input_device_changed.emit(InputRouter.Device.KEYBOARD_MOUSE)
	assert_false(_touch.visible)


func test_move_and_aim_sticks_work_at_the_same_time() -> void:
	_touch_at(0, Vector2(200.0, 500.0), true)
	_touch_at(1, Vector2(1000.0, 500.0), true)
	await wait_process_frames(1)
	_drag(0, Vector2(290.0, 500.0))  # push right
	_drag(1, Vector2(1000.0, 420.0))  # aim up (forward), past the fire threshold
	await wait_process_frames(2)
	assert_gt(InputRouter.get_move_vector().x, 0.8, "moving right")
	assert_lt(InputRouter.get_stick_aim_vector().y, -0.6, "aiming forward")
	assert_true(InputRouter.is_primary_fire_held(), "twin-stick: aiming far fires")
	_touch_at(0, Vector2(290.0, 500.0), false)
	_touch_at(1, Vector2(1000.0, 420.0), false)
	await wait_process_frames(2)
	assert_eq(InputRouter.get_move_vector(), Vector2.ZERO, "released")
	assert_false(InputRouter.is_primary_fire_held())


func test_small_aim_nudge_turns_without_firing() -> void:
	_touch_at(1, Vector2(1000.0, 500.0), true)
	await wait_process_frames(1)
	_drag(1, Vector2(1020.0, 500.0))
	await wait_process_frames(2)
	assert_gt(InputRouter.get_stick_aim_vector().x, 0.0)
	assert_false(InputRouter.is_primary_fire_held())
	_touch_at(1, Vector2(1020.0, 500.0), false)


func test_reload_button_is_a_one_frame_tap() -> void:
	var reload_at: Vector2 = Vector2(1280.0 - 80.0, 720.0 - 480.0)
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


func test_shoulder_right_side_drags_the_camera() -> void:
	Settings.camera_mode = Settings.CameraMode.SHOULDER
	_touch_at(3, Vector2(900.0, 300.0), true)
	_drag(3, Vector2(960.0, 290.0), Vector2(60.0, -10.0))
	await wait_process_frames(1)
	assert_eq(InputRouter.consume_look_drag(), Vector2(60.0, -10.0))
	assert_false(InputRouter.is_primary_fire_held(), "looking alone doesn't fire")
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
