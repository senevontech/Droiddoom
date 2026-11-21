class_name SoftBackdrop
extends Control
## A soft dark gradient behind a HUD group (sleek HUD, P1-30): readable text
## on bright scenes without a visible box. Fades out toward `fade_side`.

enum FadeSide { RIGHT, LEFT, BOTH }

@export var fade_side: FadeSide = FadeSide.RIGHT
@export var strength: float = 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if strength <= 0.0:
		return
	var w: float = size.x
	var h: float = size.y
	# Columns (x, horizontal weight) and rows (y, vertical weight): the shade
	# is their product, so every edge is feathered, never a hard box.
	var cols: Array[Vector2] = []
	match fade_side:
		FadeSide.RIGHT:
			cols = [Vector2(0.0, 1.0), Vector2(w * 0.55, 0.8), Vector2(w, 0.0)]
		FadeSide.LEFT:
			cols = [Vector2(0.0, 0.0), Vector2(w * 0.45, 0.8), Vector2(w, 1.0)]
		_:
			cols = [Vector2(0.0, 0.0), Vector2(w * 0.5, 1.0), Vector2(w, 0.0)]
	var rows: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(h * 0.35, 1.0), Vector2(h * 0.8, 1.0), Vector2(h, 0.6)
	]
	for cx in cols.size() - 1:
		for ry in rows.size() - 1:
			var x0: Vector2 = cols[cx]
			var x1: Vector2 = cols[cx + 1]
			var y0: Vector2 = rows[ry]
			var y1: Vector2 = rows[ry + 1]
			draw_polygon(
				PackedVector2Array(
					[
						Vector2(x0.x, y0.x),
						Vector2(x1.x, y0.x),
						Vector2(x1.x, y1.x),
						Vector2(x0.x, y1.x)
					]
				),
				PackedColorArray(
					[
						_shade(x0.y * y0.y),
						_shade(x1.y * y0.y),
						_shade(x1.y * y1.y),
						_shade(x0.y * y1.y)
					]
				)
			)


func _shade(weight: float) -> Color:
	return Color(0.0, 0.02, 0.03, strength * weight)
