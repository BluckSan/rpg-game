shader_type spatial;
// Вода топей/озёр мира: бегущая рябь, френель, цвет по глубине и пена у берега.
// Глубина берётся из маленькой карты высот чанка (depth_map, 33×33) — без копии буфера глубины,
// поэтому одинаково дёшево на телефоне и ПК.
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;
uniform sampler2D wave : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec3 deep : source_color = vec3(0.10, 0.16, 0.11);
uniform vec3 shallow : source_color = vec3(0.30, 0.38, 0.24);
uniform vec3 foam_col : source_color = vec3(0.86, 0.9, 0.82);
varying vec3 wpos;
varying vec2 luv;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	luv = UV;
}
void fragment() {
	vec2 uv = wpos.xz * 0.08;
	vec3 na = texture(wave, uv + vec2(TIME * 0.018, TIME * 0.011)).rgb;
	vec3 nb = texture(wave, uv * 1.9 - vec2(TIME * 0.015, -TIME * 0.019)).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.35;
	float depth = texture(depth_map, luv).r;           // м под водой (<0 — суша)
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 c = mix(shallow, deep, smoothstep(0.0, 0.9, depth));
	// пена: тонкая кромка у берега + рваные пятна шума, медленно колышется
	float fn = texture(foam_noise, wpos.xz * 0.12 + vec2(TIME * 0.02, 0.0)).r;
	float edge = 1.0 - smoothstep(0.0, 0.22 + fn * 0.18, depth);
	float foam = clamp(edge * smoothstep(0.35, 0.6, fn + edge * 0.4), 0.0, 1.0);
	c = mix(c + vec3(0.12, 0.14, 0.12) * fres, foam_col, foam * 0.85);
	ALBEDO = c;
	ROUGHNESS = mix(0.08, 0.8, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(mix(0.55, 0.92, smoothstep(0.0, 0.6, depth)) + foam * 0.3, 0.0, 1.0) * smoothstep(-0.05, 0.03, depth);
}
