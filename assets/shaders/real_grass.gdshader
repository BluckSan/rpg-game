shader_type spatial;
// v0.6.0: трава — карточки с фото-травинками (CC0 ambientCG), альфа-срез, оттенок биома (основание/кончики),
// ветер по высоте (UV.y: 0 — верх), нормали «вверх» — трава светится как газон, а не как плоскости.
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_col : source_color = vec4(0.16, 0.3, 0.1, 1.0);
uniform vec4 tip_col : source_color = vec4(0.55, 0.7, 0.28, 1.0);
uniform float wind_on = 1.0;
uniform float wind_strength = 0.12;

void vertex() {
	float h = 1.0 - UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = wp.x * 0.35 + wp.z * 0.27;
	float s = sin(TIME * 1.8 + ph) * 0.7 + sin(TIME * 3.3 + ph * 1.7) * 0.3;
	VERTEX.xz += vec2(s, s * 0.6) * wind_strength * h * h * wind_on;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < 0.45) discard;
	float h = 1.0 - UV.y;
	float lum = dot(t.rgb, vec3(0.3, 0.55, 0.15));
	vec3 tint = mix(base_col.rgb, tip_col.rgb, smoothstep(0.0, 0.9, h));
	vec3 c = mix(t.rgb, tint * (0.6 + lum * 1.5), 0.6) * (0.7 + 0.3 * h) * mix(0.88, 1.1, COLOR.r);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.35;
}
