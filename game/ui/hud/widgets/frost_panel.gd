class_name FrostPanel
extends MarginContainer
## A frosted-glass card behind its children (P1-32): blurred background, 3%
## white tint, rounded corners, hairline border (ui/theme/frost.gdshader).
## Lay content out inside it like any MarginContainer.
## The card draws the glass itself (its own material); a glass child node
## would be shrunk by the container's margins.

const SHADER: Shader = preload("res://ui/theme/frost.gdshader")

@export var corner_radius: float = 10.0
## 0..1 opacity of the white tint (the "3%" look by default).
@export var tint_alpha: float = 0.03
## Darkening under the glass for readability (0 = none).
@export var shade: float = 0.06
## Border colour (alpha = strength). Red for danger states, etc.
@export var border: Color = Color(1.0, 1.0, 1.0, 0.1):
	set(value):
		border = value
		if _material != null:
			_material.set_shader_parameter(&"border_color", border)

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	_material.set_shader_parameter(&"corner_radius", corner_radius)
	_material.set_shader_parameter(&"tint", Color(1.0, 1.0, 1.0, tint_alpha))
	_material.set_shader_parameter(&"shade", shade)
	_material.set_shader_parameter(&"border_color", border)
	resized.connect(_on_resized)
	_on_resized()


func _draw() -> void:
	# The shader replaces this rect's colour with the frosted glass.
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


func _on_resized() -> void:
	if _material != null:
		_material.set_shader_parameter(&"rect_size", size)
	queue_redraw()
