class_name Arena
extends Node3D
## Test arena (P1-10): HOLLOW against endless waves in the spike street.
## Bakes the navigation mesh from the sector, starts the WaveDirector on the
## sector's DroidSpawn markers, repairs HOLLOW between waves, tracks the run
## in GameState, and on HOLLOW's death stops the waves and shows the
## game-over panel (restart = reload the scene).
##
## Scene contract: `Sector` (with `Markers/PlayerStart` and
## `Markers/DroidSpawn*`), `Hollow`, `WaveDirector`, `Hud`.

## Seconds between HOLLOW's death and the game-over panel (watch the wreck).
const GAME_OVER_DELAY: float = 1.8

var _elapsed: float = 0.0
var _running: bool = true

@onready var _sector: Node3D = $Sector
@onready var _hollow: Hollow = $Hollow
@onready var _director: WaveDirector = $WaveDirector
@onready var _hud: Hud = $Hud


func _ready() -> void:
	GameState.reset_run()
	GameState.current_mission_id = &"arena"
	NavBaker.add_region(self, _sector)
	var markers: Node = _sector.get_node("Markers")
	var start: Node3D = markers.get_node_or_null("PlayerStart") as Node3D
	if start != null:
		_hollow.global_position = start.global_position
	var spawns: Array[Node3D] = []
	for marker: Node in markers.get_children():
		if String(marker.name).begins_with("DroidSpawn"):
			spawns.append(marker as Node3D)
	_director.set_spawn_points(spawns)
	_director.wave_cleared.connect(_on_wave_cleared)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)
	_hud.bind(_hollow, _director)
	_hud.restart_requested.connect(SceneRouter.reload_current)
	_director.start()


func _process(delta: float) -> void:
	if _running:
		_elapsed += delta


## Seconds survived so far.
func get_elapsed() -> float:
	return _elapsed


func _on_enemy_died(_enemy: Node, _killer: Node) -> void:
	if _running:
		GameState.kills += 1


func _on_wave_cleared(_number: int) -> void:
	if not _running:
		return
	var health: HealthComponent = _hollow.health
	health.heal(health.max_health * _director.wave_set.repair_on_clear)
	if _director.wave_set.refill_ammo_on_clear:
		_hollow.refill_ammo()


func _on_player_died() -> void:
	_running = false
	_director.stop()
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	if is_inside_tree():
		_hud.show_game_over(_director.get_wave_number(), GameState.kills, _elapsed)
