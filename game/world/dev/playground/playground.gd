extends Node3D
## Dev playground (P1-01…08, D-030/D-031): HOLLOW + CameraRig + the weapon
## roster in the spike street, five target dummies and test drones. The
## navigation mesh is baked from the street's colliders on load. The reticle
## is drawn where the aim lands (both modes). Dev-only: values are inline on
## purpose.

const HINT_TEXT: String = (
	"WASD move · Mouse aim · LMB fire · RMB heavy · 1-4/wheel weapon · Q heavy"
	+ " · R reload · V camera · T drone wave · Esc free mouse"
)
const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")
const GUNNER: PackedScene = preload("res://actors/enemies/gunner/gunner.tscn")
const KAMIKAZE: PackedScene = preload("res://actors/enemies/kamikaze/kamikaze.tscn")
## Idle spawn on load: one droid per DroidSpawn marker, cycling these types.
const START_MIX: Array[PackedScene] = [SWARMER, GUNNER, KAMIKAZE]
## Alerted wave (T): this squad at every marker.
const WAVE_SQUAD: Array[PackedScene] = [SWARMER, SWARMER, SWARMER, GUNNER, KAMIKAZE]
## Squad members spread around their marker (m).
const SQUAD_SPREAD: float = 1.6

var _kills: int = 0

@onready var _rig: CameraRig = $CameraRig
@onready var _reticle: Label = $HUD/Reticle
@onready var _info: Label = $HUD/Info
@onready var _weapons: Label = $HUD/Weapons
@onready var _hollow: Hollow = $Hollow
@onready var _street: Node3D = $StreetSector
@onready var _coordinator: EnemyCoordinator = $EnemyCoordinator


func _ready() -> void:
	$HUD/Hint.text = HINT_TEXT
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	EventBus.enemy_died.connect(func(_enemy: Node, _killer: Node) -> void: _kills += 1)
	NavBaker.add_region(self, _street)
	_spawn_wave(false)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_T:
		_hollow.refill_ammo()
		_spawn_wave(true)


func _process(_delta: float) -> void:
	var aim: Vector3 = InputRouter.get_aim_target()
	_reticle.visible = not _rig.camera.is_position_behind(aim)
	_reticle.position = _rig.camera.unproject_position(aim) - _reticle.size * 0.5
	_info.text = (
		"Camera %s · Input %s · Kills %d · Drones %d · Paths/frame %d (queue %d) · FPS %d"
		% [
			_rig.get_mode_name(),
			InputRouter.Device.keys()[InputRouter.active_device],
			_kills,
			_coordinator.get_live_count(),
			_coordinator.get_queries_last_frame(),
			_coordinator.get_pending_count(),
			Engine.get_frames_per_second()
		]
	)
	_weapons.text = "%s    |    %s" % [_describe(_hollow.weapon), _describe(_hollow.heavy_weapon)]


## "Pulse Rifle  24/32" style label, with reload progress.
static func _describe(gun: Weapon) -> String:
	if gun == null:
		return "-"
	var label: String = gun.data.name_key.trim_prefix("WEAPON_").replace("_", " ").capitalize()
	if gun.data.magazine_size <= 0:
		return label
	if gun.is_reloading():
		var verb: String = (
			"COOLING" if gun.data.fire_mode == WeaponData.FireMode.BEAM else "RELOADING"
		)
		return "%s  %s %d%%" % [label, verb, roundi(gun.get_reload_progress() * 100.0)]
	var reserve: String = "∞" if gun.get_reserve() < 0 else str(gun.get_reserve())
	return "%s  %d/%d  [%s]" % [label, gun.get_magazine(), gun.data.magazine_size, reserve]


## One drone per DroidSpawn marker of the street. `alerted` = chase at once.
func _spawn_wave(alerted: bool) -> void:
	var index: int = 0
	for marker: Node in _street.get_node("Markers").get_children():
		if not String(marker.name).begins_with("DroidSpawn"):
			continue
		var at: Vector3 = (marker as Node3D).global_position
		if not alerted:
			_spawn(START_MIX[index % START_MIX.size()], at, false)
			index += 1
			continue
		for member in WAVE_SQUAD.size():
			var angle: float = TAU * member / WAVE_SQUAD.size()
			var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * SQUAD_SPREAD
			if not _spawn(WAVE_SQUAD[member], at + offset, true):
				return


## Spawns one droid unless the quality preset's live-enemy cap is reached.
func _spawn(scene: PackedScene, at: Vector3, alerted: bool) -> bool:
	var cap: int = QualityManager.settings.max_live_enemies if QualityManager.settings else 40
	if _coordinator.get_live_count() >= cap:
		return false
	var droid: BaseEnemy = scene.instantiate()
	droid.start_alerted = alerted
	droid.position = at
	$Enemies.add_child(droid)
	return true
