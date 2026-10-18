shader_type spatial;
// v0.6.0: растения Poly Haven (CC0) — PBR (цвет/нормали/ORM), двусторонние, лёгкий ветер по высоте вершины,
// просвет листвы против солнца (BACKLIGHT). Одинаково на всех пресетах (ветер можно выключить).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wind_strength = 0.06;
uniform float wind_height = 1.0;   // высота, на которой качание полное
uniform vec3 tint : source_color = vec3(1.0);
uniform float backlight = 0.35;
uniform float wind_on = 1.0;
global uniform float cam_fade_dist;

void vertex() {
	float h = clamp(VERTEX.y / wind_height, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 0.37 + wp.z * 0.23;
	float s = sin(TIME * 1.7 + ph) * 0.7 + sin(TIME * 3.1 + ph * 1.9) * 0.3;
	VERTEX.xz += vec2(s, s * 0.6) * wind_strength * h * h * wind_on;
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

	vec3 orm = texture(orm_tex, UV).rgb;
	vec4 at = texture(albedo_tex, UV);
	ALBEDO = at.rgb * tint;
	ALPHA = at.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	AO = orm.r; AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
	BACKLIGHT = vec3(backlight) * ALBEDO;
}
