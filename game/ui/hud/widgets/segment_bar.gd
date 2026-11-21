class_name SegmentBar
extends Control
## Slanted segmented bar (hull, dash, ammo). A white "trail" shows what was
## just lost and drains after it, so a hit reads instantly.

@export var segments: int = 20:
	set(value):
		segments = maxi(1, value)
		queue_redraw()
@export var color: Color = Holo.CYAN:
	set(value):
		color = value
		queue_redraw()
@export var gap: float = 3.0
## Seconds the lost-value trail takes to drain (0 = no trail).
@export var trail_time: float = 0.45

var ratio: float = 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value < ratio and trail_time > 0.0:
			_trail = maxf(_trail, ratio)
		ratio = value
		queue_redraw()

var _trail: float = 0.0


func _process(delta: float) -> void:
	if _trail > ratio:
		_trail = maxf(ratio, _trail - delta / maxf(trail_time, 0.01))
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if _trail > ratio:
		Holo.draw_segments(self, rect, segments, _trail, Color(1.0, 1.0, 1.0, 0.75), gap)
		Holo.draw_segments(self, rect, segments, ratio, color, gap, false)
	else:
		Holo.draw_segments(self, rect, segments, ratio, color, gap)
