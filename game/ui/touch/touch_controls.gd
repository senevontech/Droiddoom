class_name TouchControls
extends Control
## On-screen controls for phones and tablets (P1-11, redesigned P1-31).
## Shown only while the active input device is TOUCH. Every finger is tracked
## by its touch index, so moving, aiming and buttons work at the same time
## (Godot's own Buttons only see the first finger).
##
## - **Hybrid sticks:** dim stick bases always show at their home spots; a
##   touch anywhere in a stick's zone moves the stick there.
##   Left zone = move (`move_*`). Right zone, Tactical = aim (`aim_*`);
##   Shoulder = drag to look (InputRouter.add_look_drag).
## - **Fire modes** (Settings.touch_fire_mode, toggled by the AUTO/MANUAL pill):
##   AUTO fires while the aim is on a droid (InputRouter.is_aim_on_target) and
##   the FIRE button also works; MANUAL fires only while FIRE is held.
## - **Arc layout:** FIRE in the bottom-right corner; DASH, HEAVY, SWAP and
##   RELOAD in an arc around it; fire-mode pill, CAM and PAUSE top-right.
## - Size and opacity follow Settings.touch_button_scale / touch_opacity.
## It presses the same input actions as keyboard and gamepad, so gameplay
## never knows touch exists (AGENTS.md rule 6a). UI may look at the camera mode.

## The PAUSE button was tapped (the HUD opens the pause menu).
signal pause_requested

## Sizes are for a 720 px tall screen and scale with the shorter side.
const REFERENCE: float = 720.0
const STICK_RADIUS: float = 92.0
const KNOB_RADIUS: float = 36.0
const BUTTON_RADIUS: float = 38.0
const FIRE_RADIUS: float = 62.0
const SMALL_RADIUS: float = 24.0
## Distance of the arc buttons from the FIRE button's centre.
const ARC_RADIUS: float = 122.0
## Arc angles (degrees, 0 = right, 90 = up) for DASH, HEAVY, SWAP, RELOAD.
const ARC_ANGLES: Array[float] = [180.0, 138.0, 98.0, 58.0]
## Stick zones start below this share of the screen height (HUD lives above).
const ZONE_TOP: float = 0.22
## Buttons accept touches a little outside their circle.
const HIT_SLACK: float = 1.15
const FILL: Color = Color(1.0, 1.0, 1.0, 0.05)
const RING: Color = Color(1.0, 1.0, 1.0, 0.32)
const PRESSED: Color = Color(0.32, 0.86, 1.0, 0.28)
const AXES: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const AIM_AXES: Array[StringName] = [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]
## Special button ids (no input action).
const CAM: StringName = &"__cam"
const PAUSE: StringName = &"__pause"
const FIRE_MODE: StringName = &"__fire_mode"


## A hybrid stick: rests at `home`, jumps to the thumb inside its zone.
class Stick:
	extends RefCounted
	var index: int = -1
	var home: Vector2 = Vector2.ZERO
	var base: Vector2 = Vector2.ZERO
	var knob: Vector2 = Vector2.ZERO
	var radius: float = 92.0

	func start(touch_index: int, at: Vector2) -> void:
		index = touch_index
		base = at
		knob = Vector2.ZERO

	func drag(at: Vector2) -> void:
		knob = (at - base).limit_length(radius)

	func stop() -> void:
		index = -1
		knob = Vector2.ZERO
		base = home

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
	var centre: Vector2 = Vector2.ZERO
	var radius: float = 38.0
	var index: int = -1

	func _init(p_label: String, p_action: StringName, p_hold: bool) -> void:
		label = p_label
		action = p_action
		hold = p_hold


## Where "is the aim on a droid?" comes from (tests replace it).
var aim_on_target: Callable = InputRouter.is_aim_on_target

var _move: Stick = Stick.new()
var _aim: Stick = Stick.new()
var _look_index: int = -1
var _buttons: Array[TouchButton] = []
var _fire: TouchButton
## Tap actions pressed this frame: action → process frame it was pressed.
var _taps: Dictionary = {}
var _firing: bool = false
var _enabled: bool = true
## 0 = ready, 1 = just used (the DASH button shows a cooldown sweep).
var _dash_cooldown: float = 0.0


func _ready() -> void:
	# Full-screen anchors come from the scene (hud.tscn).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire = TouchButton.new("FIRE", &"fire_primary", true)
	_buttons = [
		_fire,
		TouchButton.new("DASH", &"ability", false),
		TouchButton.new("HEAVY", &"fire_heavy", true),
		TouchButton.new("SWAP", &"weapon_next", false),
		TouchButton.new("RELOAD", &"reload", false),
		TouchButton.new("AUTO", FIRE_MODE, false),
		TouchButton.new("CAM", CAM, false),
		TouchButton.new("II", PAUSE, false),
	]
	resized.connect(_layout)
	EventBus.input_device_changed.connect(func(_device: int) -> void: _refresh())
	EventBus.camera_mode_changed.connect(func(_mode: int) -> void: _release_all())
	EventBus.settings_changed.connect(func(_key: StringName) -> void: _layout())
	_layout()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		_release_all()


## Dash cooldown to show on the DASH button (0 = ready, 1 = just used).
func set_dash_cooldown(ratio: float) -> void:
	_dash_cooldown = clampf(ratio, 0.0, 1.0)


## False hides the controls whatever the device (game-over screen).
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_refresh()


## Centre of the button labelled `label` (tests, tutorials), or (-1, -1).
func get_button_centre(label: String) -> Vector2:
	for button: TouchButton in _buttons:
		if button.label == label or (label == "AUTO" and button.action == FIRE_MODE):
			return button.centre
	return Vector2(-1.0, -1.0)


## True while fire_primary is held by this overlay (tests, HUD).
func is_firing() -> bool:
	return _firing


func _refresh() -> void:
	visible = _enabled and InputRouter.active_device == InputRouter.Device.TOUCH
	if not visible:
		_release_all()


## Places sticks and buttons for the current screen size and settings.
func _layout() -> void:
	var s: float = minf(size.x, size.y) / REFERENCE
	var k: float = s * Settings.touch_button_scale
	var w: float = size.x
	var h: float = size.y
	_move.radius = STICK_RADIUS * k
	_aim.radius = STICK_RADIUS * k
	_move.home = Vector2(170.0 * k, h - 160.0 * k)
	var fire_at: Vector2 = Vector2(w - 118.0 * k, h - 118.0 * k)
	_aim.home = Vector2(fire_at.x - ARC_RADIUS * k - 220.0 * k, h - 150.0 * k)
	if _move.index < 0:
		_move.base = _move.home
	if _aim.index < 0:
		_aim.base = _aim.home
	_fire.centre = fire_at
	_fire.radius = FIRE_RADIUS * k
	for i in ARC_ANGLES.size():
		var a: float = deg_to_rad(ARC_ANGLES[i])
		var button: TouchButton = _buttons[i + 1]
		button.centre = fire_at + Vector2(cos(a), -sin(a)) * ARC_RADIUS * k
		button.radius = BUTTON_RADIUS * k
	# Top row, right to left: PAUSE, CAM, fire-mode pill.
	var top: float = 62.0 * s
	_buttons[7].centre = Vector2(w - 40.0 * s, top)
	_buttons[6].centre = Vector2(w - 98.0 * s, top)
	_buttons[5].centre = Vector2(w - 186.0 * s, top)
	for i in [5, 6, 7]:
		_buttons[i].radius = SMALL_RADIUS * s
	queue_redraw()


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
	var auto: bool = Settings.touch_fire_mode == Settings.TouchFireMode.AUTO
	var fire: bool = _fire.index >= 0 or (auto and bool(aim_on_target.call()))
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
	var s: float = minf(size.x, size.y) / REFERENCE
	var k: float = s * Settings.touch_button_scale
	var alpha: float = Settings.touch_opacity
	_draw_stick(_move, k, alpha)
	if not _is_shoulder():
		_draw_stick(_aim, k, alpha)
	var auto: bool = Settings.touch_fire_mode == Settings.TouchFireMode.AUTO
	for button: TouchButton in _buttons:
		var lit: bool = button.index >= 0 or (button == _fire and _firing)
		if button.action == FIRE_MODE:
			_draw_pill(button, auto, s, alpha)
			continue
		draw_circle(button.centre, button.radius, _fade(PRESSED if lit else FILL, alpha))
		draw_arc(button.centre, button.radius, 0.0, TAU, 36, _fade(RING, alpha), 2.0, true)
		if button == _fire and auto:
			# A thin outer ring marks auto-fire.
			draw_arc(
				button.centre,
				button.radius + 5.0 * k,
				0.0,
				TAU,
				40,
				_fade(RING, alpha * 0.5),
				1.5,
				true
			)
		if button.action == &"ability" and _dash_cooldown > 0.0:
			draw_arc(
				button.centre,
				button.radius * 0.8,
				-PI * 0.5,
				-PI * 0.5 + TAU * _dash_cooldown,
				32,
				Color(0.0, 0.0, 0.0, 0.5 * alpha),
				button.radius * 0.35
			)
		var size_px: float = (
			16.0 if button == _fire else (11.0 if button.radius < 30.0 * k else 12.0)
		)
		_draw_label(button.centre, button.label, roundi(size_px * k), alpha)


func _draw_stick(stick: Stick, k: float, alpha: float) -> void:
	var active: bool = stick.index >= 0
	var a: float = alpha * (1.0 if active else 0.45)
	draw_circle(stick.base, stick.radius, _fade(FILL, a))
	draw_arc(stick.base, stick.radius, 0.0, TAU, 48, _fade(RING, a), 2.0, true)
	draw_circle(stick.base + stick.knob, KNOB_RADIUS * k, _fade(PRESSED if active else FILL, a))
	draw_arc(stick.base + stick.knob, KNOB_RADIUS * k, 0.0, TAU, 32, _fade(RING, a), 2.0, true)


func _draw_pill(button: TouchButton, auto: bool, s: float, alpha: float) -> void:
	var half: Vector2 = Vector2(46.0, 16.0) * s
	var rect: Rect2 = Rect2(button.centre - half, half * 2.0)
	var color: Color = Holo.CYAN if auto else Holo.AMBER
	var glass: Color = Color(0.02, 0.06, 0.08, 0.85 if button.index < 0 else 0.6)
	draw_rect(rect, _fade(glass, maxf(alpha, 0.6)))
	draw_rect(rect, _fade(color, maxf(alpha, 0.6)), false, 1.5)
	# Always readable, even at low button opacity: the mode is important state.
	_draw_label(button.centre, "AUTO" if auto else "MANUAL", roundi(12.0 * s), 1.0, color)


func _draw_label(
	centre: Vector2, text: String, font_size: int, alpha: float, color: Color = Holo.WHITE
) -> void:
	var font: Font = Holo.HEADING_FONT
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(
		font,
		centre + Vector2(-text_size.x * 0.5, text_size.y * 0.3),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		_fade(color, alpha)
	)


func _press(index: int, at: Vector2) -> void:
	for button: TouchButton in _buttons:
		var hit: float = button.radius * HIT_SLACK
		if button.action == FIRE_MODE:
			hit = 48.0 * minf(size.x, size.y) / REFERENCE
		if at.distance_to(button.centre) <= hit:
			button.index = index
			_button_down(button)
			return
	if at.y < size.y * ZONE_TOP:
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
	match button.action:
		CAM:
			Settings.toggle_camera_mode()  # Camera switching is event-driven.
			return
		PAUSE:
			_release_all()
			pause_requested.emit()
			return
		FIRE_MODE:
			var auto: bool = Settings.touch_fire_mode == Settings.TouchFireMode.AUTO
			Settings.set_value(
				&"touch_fire_mode",
				Settings.TouchFireMode.MANUAL if auto else Settings.TouchFireMode.AUTO
			)
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


func _is_shoulder() -> bool:
	return Settings.camera_mode == Settings.CameraMode.SHOULDER


static func _fade(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)


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
