shader_type spatial;
// Одежда: PBR (albedo + normal + ORM) и перекраска насыщенных участков (кожа/металл/серые части не трогаются).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float hue_shift = 0.0;      // 0..1 оборот
uniform float sat_mul = 1.0;
uniform float val_mul = 1.0;
uniform float sat_threshold = 0.22; // ниже — не перекрашиваем
uniform float band_center = -1.0;   // >=0: перекрашивать только оттенки около band_center (ткань), кожу/ремни не трогать
uniform float band_width = 0.12;
uniform vec4 tint : source_color = vec4(1.0);
uniform float metal_add = 0.0;
uniform float rough_mul = 1.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
uniform float rim_amount = 0.28;
// v0.6.0: микрорельеф ткани/металла (ambientCG Fabric030 / Metal032) поверх родной нормали — ткань перестаёт быть «пластиком»
uniform sampler2DArray detail_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool detail_on = false;
uniform float detail_scale = 9.0;
uniform float detail_strength = 0.55;   // v0.5.1: контровой свет (силуэт читается на тёмном фоне)

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(a);
	float m = smoothstep(sat_threshold, sat_threshold + 0.12, hsv.y);
	if (band_center >= 0.0) {
		float hd = abs(fract(hsv.x - band_center + 0.5) - 0.5);
		m *= 1.0 - smoothstep(band_width, band_width + 0.05, hd);
	}
	vec3 shifted = hsv2rgb(vec3(fract(hsv.x + hue_shift), clamp(hsv.y * sat_mul, 0.0, 1.0), clamp(hsv.z * val_mul, 0.0, 1.0)));
	ALBEDO = mix(a, shifted, m) * tint.rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	AO = orm.r; AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = clamp(orm.g * rough_mul, 0.05, 1.0);
	METALLIC = clamp(orm.b + metal_add, 0.0, 1.0);
	vec3 nb = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	if (detail_on) {
		vec3 dc = texture(detail_n, vec3(UV * detail_scale, 6.0)).rgb * 2.0 - 1.0;
		vec3 dm = texture(detail_n, vec3(UV * detail_scale * 0.7, 7.0)).rgb * 2.0 - 1.0;
		vec2 d = mix(dc.xy, dm.xy * 0.5, METALLIC);
		nb.xy += d * detail_strength * (0.4 + 0.6 * ROUGHNESS);
		// мягкий «блеск ворса» на шероховатой ткани
		float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		ALBEDO += ALBEDO * fr * 0.25 * ROUGHNESS * (1.0 - METALLIC);
	}
	NORMAL_MAP = normalize(nb) * 0.5 + 0.5;
	EMISSION = emission_color.rgb * emission_strength * m;
	RIM = rim_amount * (1.0 - METALLIC * 0.5); RIM_TINT = 0.55;
	SPECULAR = 0.5;
}
