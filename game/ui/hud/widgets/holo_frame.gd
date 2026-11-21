class_name HoloFrame
extends MarginContainer
## A holo panel behind its children: glass fill, thin cut-corner frame and
## bright corner ticks (Holo.draw_panel). Lay content out inside it like any
## MarginContainer.

## Frame colour (cyan = info, red = danger).
@export var accent: Color = Holo.CYAN:
	set(value):
		accent = value
		queue_redraw()
## Size of the cut corners (px).
@export var cut: float = 10.0


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	Holo.draw_panel(self, Rect2(Vector2.ZERO, size), accent, cut)
