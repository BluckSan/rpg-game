shader_type spatial;
// v0.6.0: листва/хвоя/трава деревьев — карточки с альфа-срезом (CC0 атласы ambientCG), объёмные нормали кроны
// (задаются в сетке), просвет против солнца, ветер: ствол слабо, края кроны сильнее (вес — COLOR.r).
// COLOR.g — затенение внутри кроны, COLOR.b — разброс оттенка.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, depth_prepass_alpha;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 tint_var : source_color = vec3(1.0);   // второй оттенок (разброс по COLOR.b)
uniform float alpha_cut = 0.42;
uniform float wind_strength = 0.12;
uniform float wind_on = 1.0;
uniform float backlight = 0.5;
uniform float snow = 0.0;     // снег на верхних гранях (хребет)
global uniform float cam_fade_dist;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 0.21 + wp.z * 0.17;
	float sway = sin(TIME * 1.3 + ph) * 0.6 + sin(TIME * 2.9 + ph * 2.1 + VERTEX.y) * 0.4;
	float flutter = sin(TIME * 7.0 + dot(VERTEX, vec3(3.1, 2.3, 4.7))) * 0.25;
	VERTEX.xz += vec2(sway, sway * 0.5) * wind_strength * COLOR.r * wind_on;
	VERTEX.y += flutter * wind_strength * 0.3 * COLOR.r * wind_on;
}

void fragment() {
	// v0.6.0: растворение между камерой и героем (дизеринг)
	float vd = -VERTEX.z;
	float lat = length(VERTEX.xy);   // удаление от луча камера→герой
	if (vd < cam_fade_dist && lat < 3.2) {
		float fade = clamp((cam_fade_dist - vd) / 2.0, 0.0, 1.0) * (1.0 - smoothstep(2.0, 3.2, lat));
		float hsh = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (hsh < fade * 0.92) discard;
	}

	vec4 t = texture(albedo_tex, UV);
	if (t.a < alpha_cut) discard;
	vec3 c = t.rgb * mix(tint, tint_var, COLOR.b);
	c *= mix(0.6, 1.0, COLOR.g);
	float up = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.0, 1.0);
	c = mix(c, vec3(0.86, 0.9, 0.95), snow * smoothstep(0.55, 0.9, up) * (0.4 + 0.6 * COLOR.g));
	ALBEDO = c;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	AO = mix(0.5, 1.0, COLOR.g); AO_LIGHT_AFFECT = 0.25;
	BACKLIGHT = c * backlight;
}
