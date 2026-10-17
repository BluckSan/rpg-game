// Земля для ПК (Высокое): смесь трав, сухой травы и земли по шуму в мировых координатах, мелкая детализация,
// возмущение нормали. На телефоне не используется (там — дешёвый цвет вершин).
shader_type spatial;
render_mode cull_back;
uniform sampler2D noise_big : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_small : repeat_enable, filter_linear_mipmap;
uniform vec3 grass_a : source_color = vec3(0.30, 0.45, 0.21);
uniform vec3 grass_b : source_color = vec3(0.40, 0.52, 0.25);
uniform vec3 dry : source_color = vec3(0.52, 0.50, 0.30);
uniform vec3 dirt : source_color = vec3(0.42, 0.34, 0.24);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz;
	float big = texture(noise_big, uv * 0.012).r;
	float mid = texture(noise_big, uv * 0.06 + 0.37).r;
	float fine = texture(noise_small, uv * 0.45).r;
	vec3 c = mix(grass_a, grass_b, smoothstep(0.35, 0.65, mid));
	c = mix(c, dry, smoothstep(0.62, 0.8, big) * 0.7);
	c = mix(c, dirt, smoothstep(0.78, 0.9, big * 0.6 + fine * 0.5));
	c *= 0.86 + fine * 0.28;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	float dx = texture(noise_small, uv * 0.45 + vec2(0.01, 0.0)).r - fine;
	float dz = texture(noise_small, uv * 0.45 + vec2(0.0, 0.01)).r - fine;
	NORMAL_MAP = normalize(vec3(0.5 - dx * 6.0, 0.5 - dz * 6.0, 1.0));
	NORMAL_MAP_DEPTH = 0.6;
}
