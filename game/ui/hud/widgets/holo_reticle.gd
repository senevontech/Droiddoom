class_name HoloReticle
extends Control
## Aim reticle (sleek HUD, P1-30): four short ticks around a gap and a centre
## dot, each with a thin dark outline so it reads on any background. A thin
## amber ring fills while the weapon reloads. Placed by the HUD at the
## projected aim point.

const TICK: float = 4.0
const GAP: float = 4.0
const RING: float = 11.0

var color: Color = Holo.CYAN:
	set(value):
		color = value
		queue_redraw()
## 0..1 reload progress, or -1 when not reloading.
var reload: float = -1.0:
	set(value):
		if not is_equal_approx(value, reload):
			reload = value
			queue_redraw()


func _draw() -> void:
	var c: Vector2 = (size * 0.5).round()
	var shadow: Color = Color(0.0, 0.0, 0.0, 0.55)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a: Vector2 = c + dir * GAP
		var b: Vector2 = c + dir * (GAP + TICK)
		draw_line(a, b, shadow, 3.0)
		draw_line(a, b, color, 1.5)
	draw_circle(c, 1.8, shadow)
	draw_circle(c, 1.1, color)
	if reload >= 0.0:
		draw_arc(c, RING, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.15), 1.5, true)
		draw_arc(c, RING, -PI * 0.5, -PI * 0.5 + TAU * reload, 40, Holo.AMBER, 2.0, true)
