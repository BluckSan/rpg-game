shader_type spatial;
// Кожа: текстура × тон, мягкое «подповерхностное» осветление по краю (дёшево, без SSS).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 skin_tone : source_color = vec4(1.0);
uniform float roughness = 0.62;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.9, 0.45, 0.35, 1.0);
void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb;
	ALBEDO = t * skin_tone.rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = emission_color.rgb + rim_color.rgb * ALBEDO * rim * 0.12;
}
