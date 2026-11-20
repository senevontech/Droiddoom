class_name Hud
extends CanvasLayer
## In-mission HUD (P1-10): hull bar, wave + droids left, kills, weapons and
## ammo with reload progress, an aim reticle (both camera modes), a red
## damage flash, wave banners and the game-over panel. Reads the bound
## player and wave director each frame; reacts to EventBus for one-off events.
## Draws nothing in 3D, so it is camera- and platform-agnostic.

## The player asked to play again (game-over panel).
signal restart_requested

const BANNER_TIME: float = 2.2
const FLASH_ALPHA: float = 0.35
const FLASH_FADE: float = 2.5
const HP_OK: Color = Color(0.35, 0.9, 0.55)
const HP_LOW: Color = Color(1.0, 0.25, 0.2)

var _player: Hollow
var _director: WaveDirector
var _banner_left: float = 0.0
var _game_over: bool = false
var _hp_fill: StyleBoxFlat

@onready var _reticle: Label = $Reticle
@onready var _flash: ColorRect = $DamageFlash
@onready var _hp_bar: ProgressBar = $TopLeft/HpBar
@onready var _hp_text: Label = $TopLeft/HpText
@onready var _wave: Label = $Wave
@onready var _stats: Label = $Stats
@onready var _banner: Label = $Banner
@onready var _weapons: Label = $BottomLeft/Weapons
@onready var _reload: ProgressBar = $BottomLeft/Reload
@onready var _hint: Label = $Hint
@onready var _touch: TouchControls = $TouchControls
@onready var _game_over_panel: Control = $GameOver
@onready var _summary: Label = $GameOver/Center/Box/Summary
@onready var _restart: Button = $GameOver/Center/Box/Restart


func _ready() -> void:
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = HP_OK
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	_flash.color.a = 0.0
	_banner.modulate.a = 0.0
	_game_over_panel.visible = false
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.wave_started.connect(func(n: int) -> void: show_banner("WAVE %d" % n))
	EventBus.wave_cleared.connect(
		func(n: int) -> void: show_banner("WAVE %d CLEARED · HULL REPAIRED" % n)
	)


## Starts showing `player` and `director` (either may be null).
func bind(player: Hollow, director: WaveDirector) -> void:
	_player = player
	_director = director


## Big centred message that fades out.
func show_banner(text: String) -> void:
	_banner.text = text
	_banner_left = BANNER_TIME


## Game-over panel with the run summary. Enter / gamepad A also restarts.
func show_game_over(wave: int, kills: int, seconds: float) -> void:
	_game_over = true
	_summary.text = (
		"Reached wave %d · %d droids destroyed · %d:%02d"
		% [wave, kills, int(seconds) / 60, int(seconds) % 60]
	)
	_game_over_panel.visible = true
	_touch.set_enabled(false)
	_restart.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_game_over_shown() -> bool:
	return _game_over


func _process(delta: float) -> void:
	_hint.visible = InputRouter.active_device == InputRouter.Device.KEYBOARD_MOUSE
	_update_reticle()
	_update_player()
	_update_wave()
	_stats.text = "Kills %d · FPS %d" % [GameState.kills, Engine.get_frames_per_second()]
	_flash.color.a = maxf(0.0, _flash.color.a - FLASH_FADE * delta * FLASH_ALPHA)
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(_banner_left / 0.5, 0.0, 1.0)


func _update_reticle() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var aim: Vector3 = InputRouter.get_aim_target()
	var dead: bool = _player != null and _player.health.is_dead()
	_reticle.visible = camera != null and not dead and not camera.is_position_behind(aim)
	if _reticle.visible:
		_reticle.position = camera.unproject_position(aim) - _reticle.size * 0.5


func _update_player() -> void:
	if _player == null:
		return
	var health: HealthComponent = _player.health
	_hp_bar.max_value = health.max_health
	_hp_bar.value = health.get_health()
	_hp_text.text = "HULL %d / %d" % [ceili(health.get_health()), roundi(health.max_health)]
	_hp_fill.bg_color = HP_LOW.lerp(HP_OK, clampf(health.get_ratio() * 1.6 - 0.2, 0.0, 1.0))
	_weapons.text = "%s    |    %s" % [describe(_player.weapon), describe(_player.heavy_weapon)]
	var reloading: Weapon = null
	for gun: Weapon in [_player.weapon, _player.heavy_weapon]:
		if gun != null and gun.is_reloading():
			reloading = gun
	_reload.visible = reloading != null
	if reloading != null:
		_reload.value = reloading.get_reload_progress()


func _update_wave() -> void:
	if _director == null:
		_wave.text = ""
		return
	var number: int = _director.get_wave_number()
	if _director.get_phase() == WaveDirector.Phase.BREAK:
		_wave.text = "NEXT WAVE IN %d" % ceili(_director.get_break_left())
	elif number > 0:
		_wave.text = "WAVE %d · %d droids left" % [number, _director.get_remaining()]


func _unhandled_input(event: InputEvent) -> void:
	if _game_over and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		restart_requested.emit()


func _on_player_damaged(_amount: float, _type: int) -> void:
	_flash.color.a = FLASH_ALPHA


## "Pulse Rifle  24/32  [∞]" style label, with reload or cool-down state.
static func describe(gun: Weapon) -> String:
	if gun == null:
		return "-"
	var label: String = gun.data.name_key.trim_prefix("WEAPON_").replace("_", " ").capitalize()
	if gun.data.magazine_size <= 0:
		return label
	if gun.is_reloading():
		var beam: bool = gun.data.fire_mode == WeaponData.FireMode.BEAM
		return "%s  %s" % [label, "COOLING" if beam else "RELOADING"]
	if gun.is_out_of_ammo():
		return "%s  EMPTY" % label
	var reserve: String = "∞" if gun.get_reserve() < 0 else str(gun.get_reserve())
	return "%s  %d/%d  [%s]" % [label, gun.get_magazine(), gun.data.magazine_size, reserve]
