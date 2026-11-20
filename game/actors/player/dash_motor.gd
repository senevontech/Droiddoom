class_name DashMotor
extends RefCounted
## Dash timing for HOLLOW (P1-12): a short burst at a fixed speed, i-frames
## that outlast the burst a little, then a cooldown counted from the start.
## Pure logic (no nodes), so it is unit-tested; HOLLOW applies the velocity
## and the invulnerability.

## Horizontal unit direction of the current (or last) dash.
var direction: Vector3 = Vector3.ZERO

var _speed: float = 16.0
var _duration: float = 0.18
var _iframes: float = 0.24
var _cooldown: float = 0.8
var _time_left: float = 0.0
var _iframes_left: float = 0.0
var _cooldown_left: float = 0.0


## Reads the dash values from player stats.
func configure(stats: PlayerStats) -> void:
	_speed = stats.dash_speed
	_duration = stats.dash_time
	_iframes = stats.dash_iframes
	_cooldown = stats.dash_cooldown


func can_dash() -> bool:
	return _cooldown_left <= 0.0 and _time_left <= 0.0


## Starts a dash along `dir` (flattened). Returns false if on cooldown or
## `dir` has no horizontal length.
func start(dir: Vector3) -> bool:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if not can_dash() or flat.length() < 0.01:
		return false
	direction = flat.normalized()
	_time_left = _duration
	_iframes_left = _iframes
	_cooldown_left = _cooldown
	return true


func update(delta: float) -> void:
	_time_left = maxf(0.0, _time_left - delta)
	_iframes_left = maxf(0.0, _iframes_left - delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func is_dashing() -> bool:
	return _time_left > 0.0


func is_invulnerable() -> bool:
	return _iframes_left > 0.0


## Horizontal velocity to use while dashing.
func get_velocity() -> Vector3:
	return direction * _speed


## 0 = ready, 1 = just used (HUD cooldown display).
func get_cooldown_ratio() -> float:
	return _cooldown_left / _cooldown if _cooldown > 0.0 else 0.0


## Ends the dash and its i-frames at once (death, level reset).
func cancel() -> void:
	_time_left = 0.0
	_iframes_left = 0.0
