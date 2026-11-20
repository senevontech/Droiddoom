class_name Benchmark
extends Node3D
## Performance benchmark (P1-14, TDD §6): the arena street under a heavy,
## repeatable combat load, measured in both cameras.
##
## Load: as many droids as the quality preset allows (`max_live_enemies`, kept
## topped up from the street's DroidSpawn markers), HOLLOW invulnerable and
## sweeping the street while firing non-stop, plus a rocket every few seconds
## (explosions, wrecks, smoke).
## Run: warm-up → Tactical (measured) → switch → Shoulder (measured, slowly
## panning) → results. Frame time is real wall-clock time per frame.
## Results: on screen (screenshot it on the web), in the console, and as
## JSON in user://benchmarks/.
##
## Launch: `godot --path game -- --benchmark` (desktop) or `index.html?benchmark`
## (web; Arena redirects here). Add `--benchmark-quit` to exit when done.
## Force a quality preset with `--low` / `--medium` / `--high` / `--ultra`
## (web: `?benchmark&low`); otherwise the current preset is used.

enum Phase { WARMUP, TACTICAL, SWITCH, SHOULDER, DONE }

const SCENE: String = "res://world/common/benchmark.tscn"
const RESULTS_DIR: String = "user://benchmarks"
## Seconds between HOLLOW's rockets.
const ROCKET_EVERY: float = 2.5
## Droids spawned per frame at most while topping up (avoids spawn spikes).
const SPAWNS_PER_FRAME: int = 2
## Shoulder camera pan while measuring (drag pixels per second).
const SHOULDER_PAN: float = 55.0
## How far HOLLOW sweeps along the street from its start (m; stays clear of the props).
const SWEEP_X: float = 5.0
const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")
const GUNNER: PackedScene = preload("res://actors/enemies/gunner/gunner.tscn")
const KAMIKAZE: PackedScene = preload("res://actors/enemies/kamikaze/kamikaze.tscn")

@export var warmup_seconds: float = 3.0
@export var phase_seconds: float = 20.0
@export var switch_seconds: float = 1.0
## Droids to keep alive; -1 = the quality preset's `max_live_enemies`.
@export var target_droids: int = -1

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var phase: Phase = Phase.WARMUP

## Spawn mix: two Swarmers for every Gunner and Kamikaze.
var _scenes: Array[PackedScene] = [SWARMER, SWARMER, GUNNER, KAMIKAZE]
var _stats: Dictionary = {}
var _phase_left: float = 0.0
var _last_usec: int = 0
var _clock: float = 0.0
var _rocket_left: float = ROCKET_EVERY
var _spawns: Array[Node3D] = []
var _start: Vector3 = Vector3.ZERO
var _results: Dictionary = {}

@onready var _sector: Node3D = $Sector
@onready var _hollow: Hollow = $Hollow
@onready var _enemies: Node3D = $Enemies
@onready var _coordinator: EnemyCoordinator = $EnemyCoordinator
@onready var _projectiles: ProjectileSystem = $ProjectileSystem
@onready var _debris: DebrisSystem = $DebrisSystem
@onready var _label: Label = $Overlay/Label


func _enter_tree() -> void:
	# Before the children's _ready: pools (debris, lights) size from the preset.
	var names: Array[String] = ["low", "medium", "high", "ultra"]
	for i in names.size():
		if PlatformServices.has_launch_flag(names[i]):
			QualityManager.apply_preset(i as QualityManager.Preset)


func _ready() -> void:
	rng.seed = 1234
	NavBaker.add_region(self, _sector)
	var markers: Node = _sector.get_node("Markers")
	var start: Node3D = markers.get_node_or_null("PlayerStart") as Node3D
	if start != null:
		_hollow.global_position = start.global_position
	_start = _hollow.global_position
	for marker: Node in markers.get_children():
		if String(marker.name).begins_with("DroidSpawn"):
			_spawns.append(marker as Node3D)
	Settings.set_camera_mode(Settings.CameraMode.TACTICAL)
	_phase_left = warmup_seconds
	_last_usec = Time.get_ticks_usec()


## The results dictionary once finished (empty before).
func get_results() -> Dictionary:
	return _results


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0
	_last_usec = now
	if phase == Phase.DONE:
		return
	var dt: float = frame_ms / 1000.0
	_clock += dt
	_drive_hollow(dt)
	_top_up_droids()
	if phase == Phase.TACTICAL or phase == Phase.SHOULDER:
		_record(frame_ms)
	if phase == Phase.SHOULDER:
		InputRouter.add_look_drag(Vector2(SHOULDER_PAN * dt, 0.0))
	_phase_left -= dt
	if _phase_left <= 0.0:
		_next_phase()
	_label.text = _live_text(frame_ms)


func _next_phase() -> void:
	match phase:
		Phase.WARMUP:
			phase = Phase.TACTICAL
			_phase_left = phase_seconds
		Phase.TACTICAL:
			phase = Phase.SWITCH
			_phase_left = switch_seconds
			Settings.set_camera_mode(Settings.CameraMode.SHOULDER)
		Phase.SWITCH:
			phase = Phase.SHOULDER
			_phase_left = phase_seconds
		Phase.SHOULDER:
			phase = Phase.DONE
			_finish()


func _record(frame_ms: float) -> void:
	var key: String = "tactical" if phase == Phase.TACTICAL else "shoulder"
	if not _stats.has(key):
		_stats[key] = FrameStats.new()
	(_stats[key] as FrameStats).add(
		frame_ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	)


## HOLLOW sweeps the street, shooting the nearest droid; a rocket now and then.
func _drive_hollow(dt: float) -> void:
	_hollow.health.invulnerable = true
	_hollow.global_position = (
		_start + Vector3(sin(_clock * 0.25) * SWEEP_X, 0.0, cos(_clock * 0.5) * 1.5)
	)
	var target: BaseEnemy = _nearest_droid()
	if target == null:
		return
	var aim: Vector3 = target.global_position + Vector3.UP * 0.7
	if _hollow.weapon.is_out_of_ammo() or _hollow.weapon.get_magazine() == 0:
		_hollow.refill_ammo()
	_hollow.weapon.try_fire(_hollow.get_muzzle_position(), aim)
	_rocket_left -= dt
	if _rocket_left <= 0.0 and _hollow.heavy_weapon != null:
		_rocket_left = ROCKET_EVERY
		_hollow.heavy_weapon.refill()
		_hollow.heavy_weapon.try_fire(_hollow.get_muzzle_position(), aim)


func _nearest_droid() -> BaseEnemy:
	var best: BaseEnemy = null
	var best_d: float = INF
	for node: Node in _enemies.get_children():
		var droid: BaseEnemy = node as BaseEnemy
		if droid == null or droid.health.is_dead():
			continue
		var d: float = droid.global_position.distance_squared_to(_hollow.global_position)
		if d < best_d:
			best_d = d
			best = droid
	return best


func _top_up_droids() -> void:
	var want: int = _target()
	for i in SPAWNS_PER_FRAME:
		if _coordinator.get_live_count() >= want or _spawns.is_empty():
			return
		var droid: BaseEnemy = _scenes[rng.randi() % _scenes.size()].instantiate()
		droid.start_alerted = true
		var marker: Node3D = _spawns[rng.randi() % _spawns.size()]
		var spread: Vector3 = Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
		droid.position = marker.global_position + spread
		_enemies.add_child(droid)


func _target() -> int:
	if target_droids >= 0:
		return target_droids
	return QualityManager.settings.max_live_enemies if QualityManager.settings else 40


func _finish() -> void:
	var preset: QualityPreset = QualityManager.settings
	_results = {
		"date": Time.get_datetime_string_from_system(),
		"platform": PlatformServices.get_platform_id(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"preset": preset.display_name if preset != null else "?",
		"resolution":
		(
			"%dx%d"
			% [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
		),
		"droids": _target(),
		"render_scale_end": snappedf(QualityManager.render_scale, 0.01),
		"tactical": (_stats.get("tactical", FrameStats.new()) as FrameStats).summary(),
		"shoulder": (_stats.get("shoulder", FrameStats.new()) as FrameStats).summary(),
	}
	var json: String = JSON.stringify(_results, "  ")
	print("[BENCHMARK] ", JSON.stringify(_results))
	var saved: String = _save(json)
	_label.text = _results_text(saved)
	Settings.set_camera_mode(Settings.CameraMode.TACTICAL)
	if OS.get_cmdline_user_args().has("--benchmark-quit"):
		get_tree().quit()


func _save(json: String) -> String:
	DirAccess.make_dir_recursive_absolute(RESULTS_DIR)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "%s/benchmark_%s.json" % [RESULTS_DIR, stamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(json)
	return ProjectSettings.globalize_path(path)


func _live_text(frame_ms: float) -> String:
	var names: Array[String] = ["WARM-UP", "TACTICAL", "SWITCHING", "SHOULDER", "DONE"]
	return (
		(
			"BENCHMARK  %s  %ds\n%.0f FPS (%.1f ms)  ·  draw calls %d"
			+ "  ·  droids %d  ·  rounds %d  ·  debris %d"
		)
		% [
			names[phase],
			ceili(maxf(_phase_left, 0.0)),
			1000.0 / maxf(frame_ms, 0.001),
			frame_ms,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			_coordinator.get_live_count(),
			_projectiles.get_active_count(),
			_debris.get_active_count(),
		]
	)


func _results_text(saved: String) -> String:
	var lines: Array[String] = [
		(
			"BENCHMARK RESULTS   %s · %s · preset %s · %s · %d droids"
			% [
				_results["platform"],
				_results["gpu"],
				_results["preset"],
				_results["resolution"],
				_results["droids"],
			]
		),
		"",
	]
	for key: String in ["tactical", "shoulder"]:
		var s: Dictionary = _results[key]
		if int(s.get("frames", 0)) == 0:
			continue
		(
			lines
			. append(
				(
					"%s   avg %s FPS   1%% low %s FPS   worst %s ms   draw calls avg %s / max %s   physics %s ms"
					% [
						key.to_upper(),
						s["avg_fps"],
						s["low1_fps"],
						s["worst_ms"],
						s["avg_draw_calls"],
						s["max_draw_calls"],
						s["avg_physics_ms"],
					]
				)
			)
		)
	lines.append("")
	lines.append("Saved: %s" % saved if saved != "" else "Not saved (no writable user://)")
	lines.append("Take a screenshot of this screen and send it over.")
	return "\n".join(lines)
