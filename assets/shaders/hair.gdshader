shader_type spatial;
// Волосы/борода/брови: серую текстуру умножаем на цвет; лёгкий анизотропный блик.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 hair_color : source_color = vec4(0.3, 0.2, 0.12, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb;
	float l = dot(t, vec3(0.333));
	ALBEDO = hair_color.rgb * (0.35 + l * 0.9);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	EMISSION = emission_color.rgb;
	RIM = 0.22; RIM_TINT = 0.7;   // v0.5.1
}
