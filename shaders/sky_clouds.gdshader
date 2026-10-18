shader_type sky;
// v0.6.0: небо мира — фото-панорама Poly Haven «Kloofendal 48d Partly Cloudy (Pure Sky)» (CC0, тонмаппинг в JPG),
// верхняя полусфера; повёрнута так, чтобы солнце на фото совпадало с направленным светом. Оттенок биома — мягко
// (top_col/hor_col из WorldDress), у горизонта — дымка цвета тумана. Без TIME — карта отражений не пересчитывается.
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform vec3 top_col : source_color = vec3(0.28, 0.5, 0.85);
uniform vec3 hor_col : source_color = vec3(0.72, 0.8, 0.88);
uniform vec3 ground_col : source_color = vec3(0.3, 0.32, 0.28);
uniform vec3 cloud_col : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.62, 0.66, 0.74);
uniform float coverage = 0.48;
uniform float cloud_offset = 0.0;
uniform bool clouds_on = true;
uniform float sun_u = 0.604;      // где солнце на панораме (доля ширины)
uniform float energy = 1.0;
uniform float tint_amount = 0.45;

const vec3 DEF_TOP = vec3(0.28, 0.5, 0.85);
const vec3 DEF_HOR = vec3(0.72, 0.8, 0.88);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	float az = atan(d.x, -d.z);
	float saz = LIGHT0_ENABLED ? atan(LIGHT0_DIRECTION.x, -LIGHT0_DIRECTION.z) : 0.0;
	float u = fract((az - saz) / 6.2831853 + sun_u);
	float el = asin(clamp(h, 0.0, 1.0));
	float v = clamp(1.0 - el / 1.5707963, 0.002, 0.998);
	vec3 c = textureLod(pano, vec2(u, v), 0.0).rgb * energy;
	// оттенок биома: отношение к «обычному» небу (мрачные топи, тёплая пустошь)
	vec3 tt = clamp(top_col / DEF_TOP, vec3(0.3), vec3(2.0));
	vec3 th = clamp(hor_col / DEF_HOR, vec3(0.3), vec3(2.0));
	c *= mix(vec3(1.0), mix(th, tt, smoothstep(0.0, 0.6, h)), tint_amount);
	// дымка у горизонта
	c = mix(c, hor_col, (1.0 - smoothstep(0.0, 0.16, h)) * 0.55);
	if (h < 0.0) c = mix(hor_col, ground_col, clamp(-h * 4.0, 0.0, 1.0));
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		c += LIGHT0_COLOR * LIGHT0_ENERGY * pow(max(sd, 0.0), 1400.0) * 4.0;
	}
	COLOR = c;
}
