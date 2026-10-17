// Трава (ПК, Высокое): травинки покачиваются на ветру, у основания темнее; затухание по дальности.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
uniform vec3 base_col : source_color = vec3(0.16, 0.30, 0.12);
uniform vec3 tip_col : source_color = vec3(0.50, 0.66, 0.30);
uniform float wind = 0.25;
varying float h;
void vertex() {
	h = UV.y;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.7 + w.x * 0.21 + w.z * 0.17;
	float sway = (sin(t) + 0.5 * sin(t * 2.3 + 1.3)) * wind * h * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}
void fragment() {
	vec3 c = mix(base_col, tip_col, h) * (0.85 + 0.3 * COLOR.r);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.25, 0.3, 0.1) * h;
}
