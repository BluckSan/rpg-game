shader_type spatial;
// v0.6.0: кора деревьев — PBR (цвет/нормаль ambientCG CC0), ветер синхронно с кроной (вес — COLOR.r), снег сверху.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind_strength = 0.12;
uniform float wind_on = 1.0;
uniform float snow = 0.0;
uniform float moss = 0.0;
global uniform float cam_fade_dist;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 0.21 + wp.z * 0.17;
	float sway = sin(TIME * 1.3 + ph) * 0.6 + sin(TIME * 2.9 + ph * 2.1 + VERTEX.y) * 0.4;
	VERTEX.xz += vec2(sway, sway * 0.5) * wind_strength * COLOR.r * wind_on;
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

	vec3 c = texture(albedo_tex, UV).rgb * tint;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	c = mix(c, vec3(0.2, 0.3, 0.12), moss * smoothstep(0.1, 0.8, wn.y + 0.3) * (1.0 - COLOR.r));
	c = mix(c, vec3(0.86, 0.9, 0.95), snow * smoothstep(0.35, 0.8, wn.y));
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	AO = mix(0.6, 1.0, COLOR.g);
}
