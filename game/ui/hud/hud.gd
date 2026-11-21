class_name Hud
extends CanvasLayer
## In-mission HUD (P1-10 → holo P1-29 → sleek P1-30 → frosted P1-32).
## Minimal frosted-glass cards (FrostPanel: blurred background, 3% white tint,
## rounded corners, hairline border) with thin lines and clean text.
## - Top-left: radar (droids as red dots, up = camera forward).
## - Top-centre: objective strip (WAVE 0N, hostiles / countdown, progress line).
## - Top-right: kills · FPS.
## - Bottom-left: hull number + thin hull line, dash line, SYNC tag.
## - Bottom-right: big magazine number, weapon name, ammo line, heavy weapon.
## - Centre: small tick reticle with a thin reload ring.
## - Overlays: off-screen droid chevrons + droid health bars, edge damage
##   flash, Neural Sync tint, banners, game-over panel.
## Touch mode moves vitals and weapons to the top-left (next to the radar),
## clear of the thumbs. Reads the bound player and wave director each frame.

## The player asked to play again (game-over panel).
signal restart_requested

const BANNER_TIME: float = 2.0
const FLASH_FADE: float = 2.4
## Hull share below which the hull readout turns red and pulses.
const HULL_WARNING: float = 0.3
## Screen tint while Neural Sync slows the world.
const SYNC_TINT: Color = Color(0.2, 0.85, 1.0, 0.14)
## Seconds the keyboard hint stays before fading out.
const HINT_TIME: float = 12.0
## Card offsets (left, top, right, bottom) per input layout; cards grow to
## fit their content. 28 px safe margins (notches, cropped browser edges).
const VITALS_DEFAULT: Rect2 = Rect2(28.0, -100.0, 278.0, -28.0)
const VITALS_TOUCH: Rect2 = Rect2(146.0, 20.0, 396.0, 92.0)
const WEAPONS_DEFAULT: Rect2 = Rect2(-258.0, -112.0, -28.0, -28.0)
const WEAPONS_TOUCH: Rect2 = Rect2(146.0, 104.0, 376.0, 186.0)
const BORDER: Color = Color(1.0, 1.0, 1.0, 0.1)
const BORDER_DANGER: Color = Color(1.0, 0.3, 0.32, 0.55)

var _player: Hollow
var _director: WaveDirector
var _banner_left: float = 0.0
var _game_over: bool = false
var _clock: float = 0.0
var _toast_left: float = 0.0

@onready var _flash: TextureRect = $Root/DamageFlash
@onready var _sync_tint: ColorRect = $Root/SyncTint
@onready var _threats: ThreatOverlay = $Root/Threats
@onready var _reticle: HoloReticle = $Root/Reticle
@onready var _radar: Radar = $Root/RadarCard/Radar
@onready var _hits: HitMarkers = $Root/Hits
@onready var _objective_title: Label = $Root/Objective/Box/Title
@onready var _objective_sub: Label = $Root/Objective/Box/Sub
@onready var _objective_bar: LineBar = $Root/Objective/Box/Progress
@onready var _stats: Label = $Root/StatsCard/Stats
@onready var _vitals: FrostPanel = $Root/Vitals
@onready var _hull_value: Label = $Root/Vitals/Box/HullRow/HullValue
@onready var _sync_tag: Label = $Root/Vitals/Box/HullRow/SyncTag
@onready var _hull_bar: LineBar = $Root/Vitals/Box/HullBar
@onready var _dash_bar: LineBar = $Root/Vitals/Box/DashRow/DashBar
@onready var _dash_label: Label = $Root/Vitals/Box/DashRow/DashLabel
@onready var _weapons: FrostPanel = $Root/Weapons
@onready var _primary_name: Label = $Root/Weapons/Box/PrimaryName
@onready var _mag: Label = $Root/Weapons/Box/AmmoRow/MagValue
@onready var _reserve: Label = $Root/Weapons/Box/AmmoRow/ReserveValue
@onready var _primary_state: Label = $Root/Weapons/Box/AmmoRow/PrimaryState
@onready var _ammo_bar: LineBar = $Root/Weapons/Box/AmmoBar
@onready var _heavy_name: Label = $Root/Weapons/Box/HeavyRow/HeavyName
@onready var _heavy_ammo: Label = $Root/Weapons/Box/HeavyRow/HeavyAmmo
@onready var _banner: Label = $Root/Banner
@onready var _toast: Label = $Root/Toast
@onready var _hint: Label = $Root/Hint
@onready var _touch: TouchControls = $Root/TouchControls
@onready var _game_over_panel: Control = $Root/GameOver
@onready var _summary: Label = $Root/GameOver/Center/Panel/Box/Summary
@onready var _restart: Button = $Root/GameOver/Center/Panel/Box/Restart
@onready var _pause: PauseMenu = $PauseMenu


func _ready() -> void:
	_game_over_panel.visible = false
	_sync_tint.color = SYNC_TINT
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	_touch.pause_requested.connect(_pause.open)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.neural_sync_triggered.connect(
		func(_count: int) -> void: show_banner("NEURAL SYNC", Holo.CYAN)
	)
	EventBus.wave_started.connect(func(n: int) -> void: show_banner("WAVE %02d" % n, Holo.RED))
	EventBus.wave_cleared.connect(
		func(n: int) -> void: show_banner("WAVE %02d CLEARED  ·  HULL REPAIRED" % n, Holo.CYAN)
	)
	EventBus.input_device_changed.connect(func(_device: int) -> void: _place_panels())
	EventBus.pickup_collected.connect(_on_pickup)
	_place_panels()


## Starts showing `player` and `director` (either may be null).
func bind(player: Hollow, director: WaveDirector) -> void:
	_player = player
	_director = director
	_threats.player = player
	_radar.player = player


## Short centred message that fades out.
func show_banner(text: String, color: Color = Holo.RED) -> void:
	_banner.add_theme_color_override("font_color", Color(color, 1.0))
	_banner.text = text
	_banner_left = BANNER_TIME


## Game-over panel with the run summary. Enter / gamepad A also restarts.
func show_game_over(wave: int, kills: int, seconds: float) -> void:
	_game_over = true
	_summary.text = (
		"WAVE %02d   ·   %d DROIDS DESTROYED   ·   %d:%02d"
		% [wave, kills, int(seconds) / 60, int(seconds) % 60]
	)
	_game_over_panel.visible = true
	_pause.close()
	_pause.allowed = false
	_touch.set_enabled(false)
	_restart.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_game_over_shown() -> bool:
	return _game_over


func _process(delta: float) -> void:
	# Real time, so HUD animations keep their pace during Neural Sync.
	var real: float = delta / maxf(Engine.time_scale, 0.01)
	_clock += real
	var keyboard: bool = InputRouter.active_device == InputRouter.Device.KEYBOARD_MOUSE
	_hint.visible = keyboard and _clock < HINT_TIME + 1.0
	_hint.modulate.a = clampf(HINT_TIME + 1.0 - _clock, 0.0, 1.0)
	_update_reticle()
	_update_player()
	_update_objective()
	_stats.text = "KILLS %d   ·   %d FPS" % [GameState.kills, Engine.get_frames_per_second()]
	_flash.modulate.a = maxf(0.0, _flash.modulate.a - FLASH_FADE * real)
	if _toast_left > 0.0:
		_toast_left -= real
		_toast.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
	if _banner_left > 0.0:
		_banner_left -= real
		_banner.modulate.a = clampf(_banner_left / 0.4, 0.0, 1.0)


func _update_reticle() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var aim: Vector3 = InputRouter.get_aim_target()
	var dead: bool = _player != null and _player.health.is_dead()
	_reticle.visible = camera != null and not dead and not camera.is_position_behind(aim)
	if _reticle.visible:
		_reticle.position = (camera.unproject_position(aim) - _reticle.size * 0.5).round()
		_hits.centre = _reticle.position + _reticle.size * 0.5
	var gun: Weapon = _player.weapon if _player != null else null
	_reticle.reload = gun.get_reload_progress() if gun != null and gun.is_reloading() else -1.0
	var synced: bool = _player != null and _player.is_neural_synced()
	_reticle.color = Color(0.75, 1.0, 1.0) if synced else Holo.CYAN


func _update_player() -> void:
	if _player == null:
		return
	var health: HealthComponent = _player.health
	var ratio: float = health.get_ratio()
	_hull_bar.ratio = ratio
	_hull_value.text = "%d" % ceili(health.get_health())
	var danger: bool = ratio <= HULL_WARNING and not health.is_dead()
	var color: Color = Holo.RED if danger else Holo.CYAN
	if danger:
		color.a = 0.55 + 0.45 * absf(sin(_clock * 6.0))
	_hull_bar.color = color
	_hull_value.add_theme_color_override("font_color", Holo.RED if danger else Holo.WHITE)
	_vitals.border = BORDER_DANGER if danger else BORDER
	var cooldown: float = _player.dash.get_cooldown_ratio()
	_dash_bar.ratio = 1.0 - cooldown
	_dash_bar.color = Holo.CYAN if cooldown <= 0.0 else Holo.CYAN_DIM
	_dash_label.add_theme_color_override("font_color", Holo.CYAN if cooldown <= 0.0 else Holo.MUTED)
	_touch.set_dash_cooldown(cooldown)
	var synced: bool = _player.is_neural_synced()
	_sync_tag.visible = synced
	_sync_tint.visible = synced
	if synced:
		_sync_tint.color.a = SYNC_TINT.a * (0.4 + 0.6 * _player.get_neural_sync_ratio())
	_update_weapons()


func _update_weapons() -> void:
	var gun: Weapon = _player.weapon
	if gun != null:
		_primary_name.text = weapon_name(gun)
		var mag_size: int = gun.data.magazine_size
		var beam: bool = gun.data.fire_mode == WeaponData.FireMode.BEAM
		if mag_size > 0:
			_mag.text = "%d" % gun.get_magazine()
			_reserve.text = "/ ∞" if gun.get_reserve() < 0 else "/ %d" % gun.get_reserve()
			_ammo_bar.ratio = float(gun.get_magazine()) / mag_size
			_ammo_bar.ticks = mag_size if mag_size <= 12 else 0
		else:
			_mag.text = "∞"
			_reserve.text = ""
			_ammo_bar.ratio = 1.0
		var low: bool = mag_size > 0 and gun.get_magazine() <= maxi(1, mag_size / 5)
		_ammo_bar.color = Holo.AMBER if low else Holo.CYAN
		_mag.add_theme_color_override("font_color", Holo.AMBER if low else Holo.WHITE)
		_primary_state.text = _weapon_state(gun, beam)
	var heavy: Weapon = _player.heavy_weapon
	if heavy != null:
		_heavy_name.text = weapon_name(heavy)
		if heavy.is_reloading():
			_heavy_ammo.text = "RELOADING"
		elif heavy.is_out_of_ammo():
			_heavy_ammo.text = "EMPTY"
		else:
			var reserve: String = "∞" if heavy.get_reserve() < 0 else str(heavy.get_reserve())
			_heavy_ammo.text = "%d / %s" % [heavy.get_magazine(), reserve]
	else:
		# No unlocked heavy weapon (paid, D-035): unlock it in the pause menu.
		_heavy_name.text = "HEAVY"
		_heavy_ammo.text = "LOCKED"


func _weapon_state(gun: Weapon, beam: bool) -> String:
	if gun.is_reloading():
		return "COOLING" if beam else "RELOADING"
	if gun.is_out_of_ammo():
		return "EMPTY"
	if beam and _ammo_bar.ratio < 0.999:
		return "HEAT %d%%" % roundi((1.0 - _ammo_bar.ratio) * 100.0)
	return ""


func _update_objective() -> void:
	if _director == null:
		_objective_title.text = "FREE ROAM"
		_objective_sub.text = ""
		_objective_bar.ratio = 0.0
		return
	var number: int = _director.get_wave_number()
	if _director.get_phase() == WaveDirector.Phase.BREAK:
		_objective_title.text = "WAVE %02d" % (number + 1)
		_objective_sub.text = "INCOMING  %d" % ceili(_director.get_break_left())
		_objective_bar.ratio = 0.0
	elif number > 0:
		var left: int = _director.get_remaining()
		_objective_title.text = "WAVE %02d" % number
		_objective_sub.text = "%d HOSTILES" % left
		var size: int = maxi(1, _director.get_wave_size())
		_objective_bar.ratio = 1.0 - float(left) / size


func _place_panels() -> void:
	var touch: bool = InputRouter.active_device == InputRouter.Device.TOUCH
	_place(_vitals, VITALS_TOUCH if touch else VITALS_DEFAULT, 0.0, 0.0 if touch else 1.0)
	var corner: float = 0.0 if touch else 1.0
	_place(_weapons, WEAPONS_TOUCH if touch else WEAPONS_DEFAULT, corner, corner)


## Anchors `panel` to one corner point and sets its offsets (left, top, right, bottom).
static func _place(panel: Control, offsets: Rect2, anchor_x: float, anchor_y: float) -> void:
	panel.anchor_left = anchor_x
	panel.anchor_right = anchor_x
	panel.anchor_top = anchor_y
	panel.anchor_bottom = anchor_y
	panel.offset_left = offsets.position.x
	panel.offset_top = offsets.position.y
	panel.offset_right = offsets.size.x
	panel.offset_bottom = offsets.size.y


func _unhandled_input(event: InputEvent) -> void:
	if _game_over and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		restart_requested.emit()


func _on_pickup(kind: StringName, amount: int, _at: Vector3) -> void:
	if kind == PickupSystem.REPAIR:
		_toast.text = "+%d HULL" % amount
		_toast.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	else:
		_toast.text = "+%d HEAVY AMMO" % amount
		_toast.add_theme_color_override("font_color", Holo.AMBER)
	_toast_left = 1.6


func _on_player_damaged(amount: float, _type: int) -> void:
	_flash.modulate.a = clampf(0.4 + amount / 40.0, 0.4, 1.0)


## "PULSE RIFLE" from "WEAPON_PULSE_RIFLE".
static func weapon_name(gun: Weapon) -> String:
	return gun.data.name_key.trim_prefix("WEAPON_").replace("_", " ")
