class_name Holo
extends RefCounted
## HOLLOW holo-cockpit look (UI art direction, 2026-11-20): one palette and
## a few drawing helpers shared by every HUD widget, so the whole UI stays
## consistent. Cyan = HOLLOW / friendly info, red = AXIOM / danger, amber =
## warnings. Fonts and sizes live in `ui/theme/holo_theme.tres`.

const CYAN: Color = Color(0.32, 0.86, 1.0)
const CYAN_DIM: Color = Color(0.32, 0.86, 1.0, 0.35)
const RED: Color = Color(1.0, 0.24, 0.3)
const AMBER: Color = Color(1.0, 0.72, 0.28)
const WHITE: Color = Color(0.9, 0.97, 1.0)
const MUTED: Color = Color(0.55, 0.68, 0.76)
## Panel glass fill.
const GLASS: Color = Color(0.03, 0.09, 0.12, 0.55)
## Unlit segment / track.
const TRACK: Color = Color(0.6, 0.85, 1.0, 0.1)

const HEADING_FONT: Font = preload("res://ui/theme/holo_heading_font.tres")
const BODY_FONT: Font = preload("res://ui/theme/holo_body_font.tres")


## Polygon of a rectangle with its top-left and bottom-right corners cut.
static func cut_rect(rect: Rect2, cut: float) -> PackedVector2Array:
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	return PackedVector2Array(
		[
			Vector2(p.x + cut, p.y),
			Vector2(e.x, p.y),
			Vector2(e.x, e.y - cut),
			Vector2(e.x - cut, e.y),
			Vector2(p.x, e.y),
			Vector2(p.x, p.y + cut),
		]
	)


## Draws a holo panel: glass fill, thin frame, bright corner ticks.
static func draw_panel(item: CanvasItem, rect: Rect2, accent: Color, cut: float = 10.0) -> void:
	var poly: PackedVector2Array = cut_rect(rect, cut)
	item.draw_colored_polygon(poly, GLASS)
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	item.draw_polyline(closed, Color(accent, 0.35), 1.0, true)
	var tick: float = 14.0
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	item.draw_line(Vector2(p.x + cut, p.y), Vector2(p.x + cut + tick, p.y), accent, 2.0)
	item.draw_line(Vector2(p.x, p.y + cut), Vector2(p.x, p.y + cut + tick), accent, 2.0)
	item.draw_line(Vector2(e.x - cut, e.y), Vector2(e.x - cut - tick, e.y), accent, 2.0)
	item.draw_line(Vector2(e.x, e.y - cut), Vector2(e.x, e.y - cut - tick), accent, 2.0)


## Draws `count` slanted segments filling `rect`, the first `ratio` lit.
static func draw_segments(
	item: CanvasItem,
	rect: Rect2,
	count: int,
	ratio: float,
	lit: Color,
	gap: float = 3.0,
	track: bool = true
) -> void:
	if count <= 0:
		return
	var w: float = (rect.size.x - gap * (count - 1)) / count
	var slant: float = minf(rect.size.y * 0.35, w * 0.4)
	var on: int = int(round(clampf(ratio, 0.0, 1.0) * count))
	for i in count:
		var x: float = rect.position.x + i * (w + gap)
		var y0: float = rect.position.y
		var y1: float = rect.end.y
		var quad: PackedVector2Array = PackedVector2Array(
			[
				Vector2(x + slant, y0),
				Vector2(x + w, y0),
				Vector2(x + w - slant, y1),
				Vector2(x, y1),
			]
		)
		if i < on:
			item.draw_colored_polygon(quad, lit)
		elif track:
			item.draw_colored_polygon(quad, TRACK)
