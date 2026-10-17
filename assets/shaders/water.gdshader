// Вода пруда (ПК, Высокое): две бегущие нормали, френель, глубина по краю, мягкий край у берега.
shader_type spatial;
render_mode cull_back, depth_draw_always;
uniform sampler2D wave_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wave_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.05, 0.20, 0.26);
uniform vec3 shallow : source_color = vec3(0.20, 0.45, 0.45);
uniform float radius = 8.0;
varying vec3 wpos;
varying vec3 lpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; lpos = VERTEX; }
void fragment() {
	vec2 uv = wpos.xz * 0.12;
	vec3 na = texture(wave_a, uv + vec2(TIME * 0.02, TIME * 0.013)).rgb;
	vec3 nb = texture(wave_b, uv * 1.7 - vec2(TIME * 0.017, -TIME * 0.021)).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.5;
	float edge = clamp(length(lpos.xz) / radius, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, smoothstep(0.55, 1.0, edge)) + vec3(0.25, 0.32, 0.36) * fres;
	ROUGHNESS = 0.06;
	METALLIC = 0.1;
	SPECULAR = 0.7;
	ALPHA = mix(0.88, 0.0, smoothstep(0.86, 1.0, edge));
}
