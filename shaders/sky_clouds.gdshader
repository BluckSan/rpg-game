shader_type sky;
// Небо мира: градиент, солнце с ореолом и облака (fbm). Без TIME — карта отражений не пересчитывается
// каждый кадр (дёшево на телефоне); цвета меняются по биому редко и плавно.
uniform vec3 top_col : source_color = vec3(0.28, 0.5, 0.85);
uniform vec3 hor_col : source_color = vec3(0.72, 0.8, 0.88);
uniform vec3 ground_col : source_color = vec3(0.3, 0.32, 0.28);
uniform vec3 cloud_col : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.62, 0.66, 0.74);
uniform float coverage = 0.48;
uniform float cloud_offset = 0.0;
uniform bool clouds_on = true;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = mix(hor_col, top_col, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) c = mix(hor_col, ground_col, clamp(-h * 4.0, 0.0, 1.0));
	// солнце
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		c += LIGHT0_COLOR * LIGHT0_ENERGY * (pow(max(sd, 0.0), 900.0) * 6.0 + pow(max(sd, 0.0), 12.0) * 0.18);
	}
	if (clouds_on && h > 0.02) {
		vec2 p = d.xz / (h + 0.12) * 1.6 + vec2(cloud_offset, 0.0);
		float n = fbm(p);
		float cov = smoothstep(1.0 - coverage, 1.0 - coverage + 0.28, n);
		float shade = smoothstep(0.3, 0.85, fbm(p * 1.7 + 3.1));
		vec3 cc = mix(cloud_shadow, cloud_col, shade);
		if (LIGHT0_ENABLED) cc += LIGHT0_COLOR * 0.15 * pow(max(dot(d, LIGHT0_DIRECTION), 0.0), 6.0);
		c = mix(c, cc, cov * smoothstep(0.02, 0.18, h));
	}
	COLOR = c;
}
