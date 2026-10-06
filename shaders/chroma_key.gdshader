shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 target_color : source_color = vec4(0.0, 0.694, 0.251, 1.0);
uniform float sensitivity : hint_range(0.0, 1.0) = 0.19;
uniform float smoothness : hint_range(0.0, 0.5) = 0.08;
uniform float luma_weight : hint_range(0.0, 1.0) = 0.0;
uniform float edge_choke : hint_range(0.0, 0.5) = 0.0;
uniform float pre_blur : hint_range(0.0, 5.0) = 0.0;
uniform float spill_removal : hint_range(0.0, 1.0) = 0.15;
uniform float brightness : hint_range(-1.0, 1.0) = 0.0;
uniform float contrast : hint_range(0.0, 3.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float hue_degrees : hint_range(-180.0, 180.0) = 0.0;
uniform vec4 crop_rect = vec4(-0.1, -0.1, 1.1, 1.1);
uniform vec2 crop_fade = vec2(0.001);
uniform vec4 capture_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform float capture_rotation = 0.0;
uniform float capture_aspect = 1.0;
uniform sampler2D source_texture : filter_linear;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 color_at(vec2 uv) {
	return texture(source_texture, uv).rgb;
}
float key_alpha(vec3 rgb) {
	vec3 diff = rgb - target_color.rgb;
	float lum_delta = dot(rgb, LUMA) - dot(target_color.rgb, LUMA);
	vec3 chroma_diff = diff - lum_delta * LUMA * (1.0 - luma_weight);
	float edge_low = sensitivity + edge_choke;
	return smoothstep(edge_low, edge_low + max(smoothness, 0.0001), length(chroma_diff));
}
vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - vec2(0.5);
	centered.x *= capture_aspect;
	float c = cos(capture_rotation), s = sin(capture_rotation);
	centered = vec2(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
	centered.x /= max(capture_aspect, 0.0001);
	vec2 sample_uv = (centered + vec2(0.5)) * capture_st.xy + capture_st.zw;
	vec2 pixel_size = 1.0 / vec2(textureSize(source_texture, 0));
	vec2 texel = pixel_size * pre_blur;
	vec3 sample_rgb = color_at(sample_uv);
	vec3 blurred;
	if (pre_blur == 0.0) {
		// At zero blur the four taps all address the center pixel; retain the
		// original weights while avoiding four redundant texture fetches.
		blurred = sample_rgb * 0.4026;
		blurred += (sample_rgb + sample_rgb + sample_rgb + sample_rgb) * 0.1493;
	} else {
		blurred = sample_rgb * 0.4026;
		blurred += (color_at(sample_uv + vec2(texel.x, 0.0)) + color_at(sample_uv - vec2(texel.x, 0.0)) + color_at(sample_uv + vec2(0.0, texel.y)) + color_at(sample_uv - vec2(0.0, texel.y))) * 0.1493;
	}
	vec2 ao = pixel_size * 2.0;
	float alpha = key_alpha(blurred) * 0.4026;
	alpha += (key_alpha(color_at(sample_uv + vec2(ao.x, 0.0))) + key_alpha(color_at(sample_uv - vec2(ao.x, 0.0))) + key_alpha(color_at(sample_uv + vec2(0.0, ao.y))) + key_alpha(color_at(sample_uv - vec2(0.0, ao.y)))) * 0.1493;
	float fx = max(crop_fade.x, 0.001), fy = max(crop_fade.y, 0.001);
	alpha *= smoothstep(0.0, fx, UV.x - crop_rect.x) * smoothstep(0.0, fx, crop_rect.z - UV.x) * smoothstep(0.0, fy, UV.y - crop_rect.y) * smoothstep(0.0, fy, crop_rect.w - UV.y);
	vec3 rgb = sample_rgb;
	if (target_color.g >= target_color.r && target_color.g >= target_color.b) rgb.g -= max(0.0, rgb.g - max(rgb.r, rgb.b)) * spill_removal;
	else if (target_color.b >= target_color.r) rgb.b -= max(0.0, rgb.b - max(rgb.r, rgb.g)) * spill_removal;
	else rgb.r -= max(0.0, rgb.r - max(rgb.g, rgb.b)) * spill_removal;
	rgb = clamp(rgb + brightness, vec3(0.0), vec3(1.0));
	rgb = clamp((rgb - vec3(0.5)) * contrast + vec3(0.5), vec3(0.0), vec3(1.0));
	float lum = dot(rgb, LUMA);
	rgb = mix(vec3(lum), rgb, saturation);
	if (abs(hue_degrees) > 0.5) { vec3 hsv = rgb_to_hsv(rgb); hsv.x = fract(hsv.x + hue_degrees / 360.0); rgb = hsv_to_rgb(hsv); }
	COLOR = vec4(rgb * alpha, alpha) * COLOR;
}
