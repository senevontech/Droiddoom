class_name FrameStats
extends RefCounted
## Collects per-frame samples and summarises them (P1-14 benchmark).
## Pure maths, unit-tested. "1% low" = the FPS of the 99th-percentile frame
## time: what the slowest 1% of frames feel like (stutter), which an average
## hides.

var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _draw_calls: PackedInt32Array = PackedInt32Array()
var _physics_ms: PackedFloat32Array = PackedFloat32Array()


## One frame: its real duration, draw calls and physics time.
func add(frame_ms: float, draw_calls: int, physics_ms: float) -> void:
	_frame_ms.append(frame_ms)
	_draw_calls.append(draw_calls)
	_physics_ms.append(physics_ms)


func get_frame_count() -> int:
	return _frame_ms.size()


## Summary dictionary (all numbers rounded for display):
## frames, seconds, avg_fps, low1_fps, avg_ms, worst_ms, avg_draw_calls,
## max_draw_calls, avg_physics_ms.
func summary() -> Dictionary:
	var n: int = _frame_ms.size()
	if n == 0:
		return {"frames": 0}
	var total_ms: float = 0.0
	var worst: float = 0.0
	var physics: float = 0.0
	var draws: int = 0
	var max_draws: int = 0
	for i in n:
		total_ms += _frame_ms[i]
		worst = maxf(worst, _frame_ms[i])
		physics += _physics_ms[i]
		draws += _draw_calls[i]
		max_draws = maxi(max_draws, _draw_calls[i])
	var sorted: PackedFloat32Array = _frame_ms.duplicate()
	sorted.sort()
	# Slowest 1% of frames (at least the single worst frame).
	var p99: float = sorted[mini(n - 1, int(n * 0.99))]
	return {
		"frames": n,
		"seconds": snappedf(total_ms / 1000.0, 0.01),
		"avg_fps": snappedf(1000.0 * n / maxf(total_ms, 0.001), 0.1),
		"low1_fps": snappedf(1000.0 / maxf(p99, 0.001), 0.1),
		"avg_ms": snappedf(total_ms / n, 0.01),
		"worst_ms": snappedf(worst, 0.01),
		"avg_draw_calls": roundi(float(draws) / n),
		"max_draw_calls": max_draws,
		"avg_physics_ms": snappedf(physics / n, 0.01),
	}
