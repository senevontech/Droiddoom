// Frosted glass for HUD cards (P1-32): blurs what is behind the control,
// lays a very faint tint over it (3% by default) and draws a hairline border,
// all inside a rounded rectangle. Works on the Compatibility renderer:
// a single screen-texture read pattern (25 taps), no mipmaps needed.
// Cost: only the card's pixels (small areas), so it fits the Low preset.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
// Control size in pixels (set by FrostPanel when it resizes).
uniform vec2 rect_size = vec2(100.0, 40.0);
uniform float corner_radius = 10.0;
// Distance between blur taps in pixels (bigger = more frosted).
uniform float blur_step = 2.5;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.03);
// Slight darkening under the glass so white text stays readable on bright scenes.
uniform float shade = 0.06;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec3 acc = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 offset = vec2(float(x), float(y)) * blur_step * SCREEN_PIXEL_SIZE;
			float k = exp(-float(x * x + y * y) / 4.5);
			acc += texture(screen_texture, SCREEN_UV + offset).rgb * k;
			total += k;
		}
	}
	vec3 glass = acc / total;
	glass = mix(glass, vec3(0.0), shade);
	glass = mix(glass, tint.rgb, tint.a);
	vec2 p = (UV - 0.5) * rect_size;
	float d = rounded_box(p, rect_size * 0.5, corner_radius);
	float inside = clamp(0.5 - d, 0.0, 1.0);
	float edge = clamp(1.0 - abs(d + 0.75), 0.0, 1.0);
	COLOR = vec4(mix(glass, border_color.rgb, edge * border_color.a), inside);
}
