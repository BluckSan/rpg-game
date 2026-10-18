shader_type spatial;
// v0.6.0: реалистичный ландшафт мира. 7 PBR-слоёв ambientCG (CC0) 1K в Texture2DArray: цвет (с AO) и нормаль (RG) + высота (B).
// Смешение по высоте текстуры (камешки/кочки прорастают сквозь соседний слой), скала на крутых склонах — трипланарная
// (без растяжения), крупная вариация цвета против повторов, тени облаков. Вид одинаков на всех пресетах:
// normals_on (Среднее+) — карты нормалей; anti_tile (Высокое+) — второй масштаб; tex_on оставлен для совместимости.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2DArray layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normals : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform bool tex_on = true;
uniform bool normals_on = true;
uniform bool anti_tile = false;
uniform bool clouds_on = true;
uniform bool triplanar_rock = true;
uniform float uv_scale = 0.16;
uniform vec2 cloud_wind = vec2(0.006, 0.0025);
uniform float cloud_strength = 0.28;
uniform vec3 grade_tint = vec3(1.0);
varying vec4 w0;
varying vec3 w1;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	w0 = CUSTOM0;
	w1 = CUSTOM1.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
	// у сетки ландшафта нет касательных: UV = мировые XZ → касательная вдоль +X по поверхности
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	float wts[7] = float[7](w0.r, w0.g, w0.b, w0.a, w1.r, w1.g, w1.b);
	float sc[7] = float[7](1.0, 1.0, 1.3, 1.0, 1.0, 0.7, 0.45);
	float rough[7] = float[7](0.95, 0.93, 0.9, 0.88, 0.62, 0.72, 0.82);
	vec2 wuv = wpos.xz * uv_scale;
	vec3 col = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float tot = 0.0;
	float rg = 0.0;
	vec3 an = abs(normalize(wnrm));
	float steep = smoothstep(0.55, 0.85, 1.0 - an.y);
	for (int i = 0; i < 7; i++) {
		if (wts[i] > 0.02) {
			vec3 uvw = vec3(wuv * sc[i], float(i));
			vec4 t; vec4 n;
			if (i == 6 && triplanar_rock && steep > 0.01) {
				// скала на обрывах: проекции по X и Z, вес по нормали
				vec3 bw = pow(an, vec3(4.0)); bw /= (bw.x + bw.y + bw.z);
				vec3 ux = vec3(wpos.zy * uv_scale * sc[i], 6.0);
				vec3 uz = vec3(wpos.xy * uv_scale * sc[i], 6.0);
				t = texture(layers, uvw) * bw.y + texture(layers, ux) * bw.x + texture(layers, uz) * bw.z;
				n = texture(normals, uvw) * bw.y + texture(normals, ux) * bw.x + texture(normals, uz) * bw.z;
			} else {
				t = texture(layers, uvw);
				n = texture(normals, uvw);
				if (anti_tile) {
					vec3 uv2 = vec3(wuv * sc[i] * 0.29 + vec2(0.37, 0.71), float(i));
					t = mix(t, texture(layers, uv2), 0.35);
				}
			}
			// смешение по высоте: B нормалей — карта высот слоя
			float w = max(wts[i] + n.b * 0.55 - 0.25, 0.0);
			w = w * w * w;
			col += t.rgb * w; nxy += n.rg * w; rg += rough[i] * w; tot += w;
		}
	}
	col /= max(tot, 0.0001);
	nxy /= max(tot, 0.0001);
	rg /= max(tot, 0.0001);
	// крупные пятна цвета (против повторов)
	float macro = texture(layers, vec3(wpos.xz * 0.0045, 0.0)).g;
	float macro2 = texture(layers, vec3(wpos.xz * 0.0011 + 0.5, 1.0)).r;
	col *= mix(0.84, 1.14, smoothstep(0.15, 0.6, macro)) * mix(0.92, 1.06, macro2);
	col *= COLOR.a;   // яркость биома
	if (clouds_on) {
		float cl = texture(cloud_noise, wpos.xz * 0.0016 + TIME * cloud_wind).r;
		col *= 1.0 - cloud_strength * smoothstep(0.48, 0.72, cl);
	}
	ALBEDO = col * grade_tint;
	if (normals_on) { NORMAL_MAP = vec3(nxy, 1.0); NORMAL_MAP_DEPTH = 1.0; }
	ROUGHNESS = rg;
	SPECULAR = 0.3;
}
