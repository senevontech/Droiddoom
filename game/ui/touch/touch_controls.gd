class_name TouchControls
extends Control
## On-screen controls for phones and tablets (P1-11). Shown only while the
## active input device is TOUCH. Every finger is tracked by its touch index,
## so moving, aiming and pressing buttons all work at the same time (Godot's
## own Buttons only see the first finger).
##
## - Left half: floating move stick → `move_*` actions.
## - Right half, Tactical: floating aim stick → `aim_*` actions; pushing it
##   past FIRE_THRESHOLD also holds `fire_primary` (twin-stick).
## - Right half, Shoulder: drag to look (InputRouter.add_look_drag) plus a
##   FIRE button.
## - Buttons: HEAVY (hold), SWAP weapon, RELOAD, CAM (switch camera), DASH.
## It only presses the same input actions as keyboard and gamepad, so
## gameplay never knows touch exists (AGENTS.md rule 6a). UI may look at the
## camera mode; gameplay may not.

## Sizes are for a 720 px tall screen and scale with the shorter side.
const REFERENCE: float = 720.0
const STICK_RADIUS: float = 95.0
const KNOB_RADIUS: float = 40.0
const BUTTON_RADIUS: float = 42.0
const FIRE_RADIUS: float = 64.0
## The aim stick fires once pushed this far (0..1).
const FIRE_THRESHOLD: float = 0.45
## Buttons accept touches a little outside their circle.
const HIT_SLACK: float = 1.2
const FILL: Color = Color(1.0, 1.0, 1.0, 0.12)
const RING: Color = Color(1.0, 1.0, 1.0, 0.45)
const PRESSED: Color = Color(1.0, 0.6, 0.3, 0.45)
const AXES: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const AIM_AXES: Array[StringName] = [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]


## A floating stick: appears where the thumb lands.
class Stick:
	extends RefCounted
	var index: int = -1
	var base: Vector2 = Vector2.ZERO
	var knob: Vector2 = Vector2.ZERO
	var radius: float = 95.0

	func start(touch_index: int, at: Vector2) -> void:
		index = touch_index
		base = at
		knob = Vector2.ZERO

	func drag(at: Vector2) -> void:
		knob = (at - base).limit_length(radius)

	func stop() -> void:
		index = -1
		knob = Vector2.ZERO

	## -1..1 on each axis (x right, y down), length ≤ 1.
	func value() -> Vector2:
		return knob / radius if index >= 0 else Vector2.ZERO


## A round on-screen button.
class TouchButton:
	extends RefCounted
	var label: String = ""
	var action: StringName = &""
	## Hold = pressed while touched; otherwise a one-frame tap.
	var hold: bool = false
	var shoulder_only: bool = false
	var centre: Vector2 = Vector2.ZERO
	var radius: float = 42.0
	var index: int = -1

	func _init(p_label: String, p_action: StringName, p_hold: bool, p_shoulder_only: bool) -> void:
		label = p_label
		action = p_action
		hold = p_hold
		shoulder_only = p_shoulder_only


var _move: Stick = Stick.new()
var _aim: Stick = Stick.new()
var _look_index: int = -1
var _buttons: Array[TouchButton] = []
var _fire: TouchButton
## Tap actions pressed this frame: action → process frame it was pressed.
var _taps: Dictionary = {}
var _firing: bool = false
var _enabled: bool = true


func _ready() -> void:
	# Full-screen anchors come from the scene (hud.tscn).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire = TouchButton.new("FIRE", &"fire_primary", true, true)
	_buttons = [
		_fire,
		TouchButton.new("HEAVY", &"fire_heavy", true, false),
		TouchButton.new("SWAP", &"weapon_next", false, false),
		TouchButton.new("RELOAD", &"reload", false, false),
		TouchButton.new("CAM", &"", false, false),
		TouchButton.new("DASH", &"ability", false, false),
	]
	resized.connect(_layout)
	EventBus.input_device_changed.connect(func(_device: int) -> void: _refresh())
	EventBus.camera_mode_changed.connect(func(_mode: int) -> void: _release_all())
	_layout()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()


## False hides the controls whatever the device (game-over screen).
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_refresh()


func _refresh() -> void:
	visible = _enabled and InputRouter.active_device == InputRouter.Device.TOUCH
	if not visible:
		_release_all()


## Places the buttons for the current screen size.
func _layout() -> void:
	var s: float = minf(size.x, size.y) / REFERENCE
	var w: float = size.x
	var h: float = size.y
	_move.radius = STICK_RADIUS * s
	_aim.radius = STICK_RADIUS * s
	var spots: Array[Vector2] = [
		Vector2(w - 160.0 * s, h - 170.0 * s),  # FIRE (Shoulder)
		Vector2(w - 90.0 * s, h - 360.0 * s),  # HEAVY
		Vector2(w - 200.0 * s, h - 430.0 * s),  # SWAP
		Vector2(w - 80.0 * s, h - 480.0 * s),  # RELOAD
		Vector2(w - 70.0 * s, 110.0 * s),  # CAM
		Vector2(w - 260.0 * s, h - 320.0 * s),  # DASH
	]
	for i in _buttons.size():
		_buttons[i].centre = spots[i]
		_buttons[i].radius = (FIRE_RADIUS if _buttons[i] == _fire else BUTTON_RADIUS) * s


func _input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


## Applies one touch or drag event. Returns true if it was used.
## (Public so tests can drive the overlay without a touchscreen.)
func handle_event(event: InputEvent) -> bool:
	if not visible:
		return false
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
		return true
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		if drag.index == _move.index:
			_move.drag(drag.position)
		elif drag.index == _aim.index:
			_aim.drag(drag.position)
		elif drag.index == _look_index:
			InputRouter.add_look_drag(drag.relative)
		return true
	return false


func _process(_delta: float) -> void:
	if not visible:
		return
	_feed_axes(AXES, _move.value())
	_feed_axes(AIM_AXES, _aim.value())
	var fire: bool = _fire.index >= 0 or _aim.value().length() > FIRE_THRESHOLD
	if fire != _firing:
		_firing = fire
		if fire:
			Input.action_press(&"fire_primary")
		else:
			Input.action_release(&"fire_primary")
	var frame: int = Engine.get_process_frames()
	for action: StringName in _taps.keys():
		if frame > int(_taps[action]):
			Input.action_release(action)
			_taps.erase(action)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var s: float = minf(size.x, size.y) / REFERENCE
	for stick: Stick in [_move, _aim]:
		if stick.index >= 0:
			draw_circle(stick.base, stick.radius, FILL)
			draw_arc(stick.base, stick.radius, 0.0, TAU, 40, RING, 2.0)
			draw_circle(stick.base + stick.knob, KNOB_RADIUS * s, RING)
	for button: TouchButton in _buttons:
		if not _is_available(button):
			continue
		draw_circle(button.centre, button.radius, PRESSED if button.index >= 0 else FILL)
		draw_arc(button.centre, button.radius, 0.0, TAU, 32, RING, 2.0)
		var font_size: int = roundi(15.0 * s) if button != _fire else roundi(20.0 * s)
		var text_size: Vector2 = font.get_string_size(
			button.label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size
		)
		draw_string(
			font,
			button.centre + Vector2(-text_size.x * 0.5, text_size.y * 0.3),
			button.label,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			Color(1.0, 1.0, 1.0, 0.85)
		)


func _press(index: int, at: Vector2) -> void:
	for button: TouchButton in _buttons:
		if _is_available(button) and at.distance_to(button.centre) <= button.radius * HIT_SLACK:
			button.index = index
			_button_down(button)
			return
	if at.x < size.x * 0.5:
		if _move.index < 0:
			_move.start(index, at)
	elif _is_shoulder():
		if _look_index < 0:
			_look_index = index
	elif _aim.index < 0:
		_aim.start(index, at)


func _release(index: int) -> void:
	if index == _move.index:
		_move.stop()
	elif index == _aim.index:
		_aim.stop()
	elif index == _look_index:
		_look_index = -1
	for button: TouchButton in _buttons:
		if button.index == index:
			button.index = -1
			if button.hold and button != _fire:
				Input.action_release(button.action)


func _button_down(button: TouchButton) -> void:
	if button.action == &"":  # CAM: camera switching is event-driven, call it directly.
		Settings.toggle_camera_mode()
		return
	if button == _fire:
		return  # _process holds fire_primary while the button is down.
	Input.action_press(button.action)
	if not button.hold:
		_taps[button.action] = Engine.get_process_frames()


func _release_all() -> void:
	_move.stop()
	_aim.stop()
	_look_index = -1
	for button: TouchButton in _buttons:
		button.index = -1
	for action: StringName in AXES + AIM_AXES + [&"fire_primary", &"fire_heavy"]:
		Input.action_release(action)
	for action: StringName in _taps.keys():
		Input.action_release(action)
	_taps.clear()
	_firing = false


func _is_available(button: TouchButton) -> bool:
	return not button.shoulder_only or _is_shoulder()


func _is_shoulder() -> bool:
	return Settings.camera_mode == Settings.CameraMode.SHOULDER


## Presses the four actions of a stick with analog strength.
static func _feed_axes(actions: Array[StringName], value: Vector2) -> void:
	_feed_axis(actions[0], actions[1], value.x)
	_feed_axis(actions[2], actions[3], value.y)


static func _feed_axis(negative: StringName, positive: StringName, v: float) -> void:
	if v > 0.0:
		Input.action_press(positive, v)
		Input.action_release(negative)
	elif v < 0.0:
		Input.action_press(negative, -v)
		Input.action_release(positive)
	else:
		Input.action_release(negative)
		Input.action_release(positive)
