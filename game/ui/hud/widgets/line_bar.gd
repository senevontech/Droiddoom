class_name LineBar
extends Control
## Thin continuous bar (sleek HUD, P1-30): faint track, coloured fill, and a
## white trail that shows what was just lost before draining away.

@export var color: Color = Holo.CYAN:
	set(value):
		color = value
		queue_redraw()
## Seconds the lost-value trail takes to drain (0 = no trail).
@export var trail_time: float = 0.5
## Small separators every 1/ticks of the length (0 = none).
@export var ticks: int = 0

var ratio: float = 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value < ratio and trail_time > 0.0:
			_trail = maxf(_trail, ratio)
		ratio = value
		queue_redraw()

var _trail: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _trail > ratio:
		var real: float = delta / maxf(Engine.time_scale, 0.01)
		_trail = maxf(ratio, _trail - real / maxf(trail_time, 0.01))
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(0.0, 0.0, w, h), Color(1.0, 1.0, 1.0, 0.14))
	if _trail > ratio:
		draw_rect(Rect2(0.0, 0.0, w * _trail, h), Color(1.0, 1.0, 1.0, 0.7))
	draw_rect(Rect2(0.0, 0.0, w * ratio, h), color)
	if ticks > 1:
		for i in range(1, ticks):
			var x: float = roundf(w * i / ticks)
			draw_line(Vector2(x, 0.0), Vector2(x, h), Color(0.0, 0.0, 0.0, 0.55), 1.0)
