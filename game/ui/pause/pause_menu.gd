class_name PauseMenu
extends CanvasLayer
## Pause menu with touch/aim settings (P1-31). Pauses the scene tree; this
## layer keeps running (PROCESS_MODE_ALWAYS). Opens from the touch PAUSE
## button (via the HUD) or the `pause` action (Esc / gamepad Start) when the
## mouse is free. Every control writes through Settings.set_value, so the
## touch overlay and cameras pick changes up immediately.
## (Settings live in memory for now; saving them comes with P2-08.)

signal opened
signal closed

## False blocks opening (game-over screen).
var allowed: bool = true

@onready var _root: Control = $Root
@onready var _resume: Button = $Root/Center/Panel/Box/Buttons/Resume
@onready var _restart: Button = $Root/Center/Panel/Box/Buttons/Restart
@onready var _auto: Button = $Root/Center/Panel/Box/FireRow/Auto
@onready var _manual: Button = $Root/Center/Panel/Box/FireRow/Manual
@onready var _look: HSlider = $Root/Center/Panel/Box/Look/Slider
@onready var _assist: HSlider = $Root/Center/Panel/Box/Assist/Slider
@onready var _size: HSlider = $Root/Center/Panel/Box/Size/Slider
@onready var _opacity: HSlider = $Root/Center/Panel/Box/Opacity/Slider
@onready var _shake: CheckButton = $Root/Center/Panel/Box/Shake


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume.pressed.connect(close)
	_restart.pressed.connect(_on_restart)
	_auto.pressed.connect(
		func() -> void: Settings.set_value(&"touch_fire_mode", Settings.TouchFireMode.AUTO)
	)
	_manual.pressed.connect(
		func() -> void: Settings.set_value(&"touch_fire_mode", Settings.TouchFireMode.MANUAL)
	)
	_bind_slider(_look, &"touch_look_sensitivity")
	_bind_slider(_assist, &"aim_assist")
	_bind_slider(_size, &"touch_button_scale")
	_bind_slider(_opacity, &"touch_opacity")
	_shake.toggled.connect(func(on: bool) -> void: Settings.set_value(&"screen_shake_enabled", on))
	EventBus.settings_changed.connect(func(_key: StringName) -> void: _sync_from_settings())
	# Senevon account + paid weapons (D-035): only where purchases are possible (web).
	if Senevon.can_buy():
		var armory: ArmoryPanel = ArmoryPanel.new()
		armory.name = "Armory"
		_shake.get_parent().add_child(armory)


func is_open() -> bool:
	return _root.visible


## Pauses the game and shows the menu.
func open() -> void:
	if is_open() or not allowed:
		return
	_sync_from_settings()
	var armory: ArmoryPanel = _shake.get_parent().get_node_or_null(^"Armory") as ArmoryPanel
	if armory != null:
		armory.refresh()  # the player spawns after the menu
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()
	opened.emit()


## Hides the menu and resumes the game.
func close() -> void:
	if not is_open():
		return
	_root.visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if is_open():
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Never leave the next scene paused.
	if is_open():
		get_tree().paused = false


func _bind_slider(slider: HSlider, key: StringName) -> void:
	slider.value_changed.connect(
		func(value: float) -> void:
			if not is_equal_approx(float(Settings.get(key)), value):
				Settings.set_value(key, value)
	)


func _sync_from_settings() -> void:
	var auto: bool = Settings.touch_fire_mode == Settings.TouchFireMode.AUTO
	_auto.set_pressed_no_signal(auto)
	_manual.set_pressed_no_signal(not auto)
	_look.set_value_no_signal(Settings.touch_look_sensitivity)
	_assist.set_value_no_signal(Settings.aim_assist)
	_size.set_value_no_signal(Settings.touch_button_scale)
	_opacity.set_value_no_signal(Settings.touch_opacity)
	_shake.set_pressed_no_signal(Settings.screen_shake_enabled)


func _on_restart() -> void:
	close()
	SceneRouter.reload_current()
