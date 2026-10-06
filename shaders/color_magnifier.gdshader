shader_type canvas_item;

uniform vec2 focus_uv = vec2(0.5, 0.5);
uniform float zoom_window_size = 0.1;
uniform bool source_bgr = true;

void fragment() {
	vec2 source_uv = focus_uv + (UV - vec2(0.5)) * zoom_window_size;
	vec4 sample_color = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
	COLOR = source_bgr ? vec4(sample_color.bgr, sample_color.a) : sample_color;
}
