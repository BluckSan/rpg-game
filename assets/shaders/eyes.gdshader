shader_type spatial;
// Глаза: радужка (маска в альфа-канале) окрашивается в выбранный цвет, может светиться (превращения).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 iris_color : source_color = vec4(0.35, 0.22, 0.12, 1.0);
uniform float glow = 0.0;
void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 iris = t.rgb * iris_color.rgb * 1.6;
	ALBEDO = mix(t.rgb, iris, t.a);
	ROUGHNESS = 0.15;
	SPECULAR = 0.8;
	EMISSION = iris_color.rgb * glow * t.a;
}
