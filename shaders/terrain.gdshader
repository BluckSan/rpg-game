shader_type spatial;
// Ландшафт мира: 7 слоёв ambientCG (CC0) в Texture2DArray (+ карты нормалей), веса — в CUSTOM0 (слои 0–3) и CUSTOM1 (4–6).
// Смешение по «высоте» текстуры (чёткие переходы трава/камень), крупная вариация цвета против повторов,
// тени облаков. Уровни: tex_on=false — цвет вершин + деталь (Низкое); normals_on — нормали (Высокое+);
// anti_tile — второй масштаб (Очень высокое/Ультра).
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2DArray layers : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normals : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform bool tex_on = true;
uniform bool normals_on = false;
uniform bool anti_tile = false;
uniform bool clouds_on = true;
uniform float uv_scale = 0.16;
uniform vec2 cloud_wind = vec2(0.006, 0.0025);
uniform float cloud_strength = 0.28;
uniform vec3 grade_tint = vec3(1.0);
varying vec4 w0;
varying vec3 w1;
varying vec2 wuv;
varying vec2 wxz;

void vertex() {
	w0 = CUSTOM0;
	w1 = CUSTOM1.rgb;
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	wuv = wxz * uv_scale;
	// у сетки ландшафта нет касательных: UV = мировые XZ → касательная вдоль +X по поверхности
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

vec3 srgb_to_lin(vec3 c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }

void fragment() {
	vec3 col;
	float wts[7] = float[7](w0.r, w0.g, w0.b, w0.a, w1.r, w1.g, w1.b);
	float sc[7] = float[7](1.0, 1.0, 1.3, 1.0, 1.0, 0.7, 0.5);
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	if (tex_on) {
		col = vec3(0.0);
		float tot = 0.0;
		vec3 nacc = vec3(0.0);
		for (int i = 0; i < 7; i++) {
			if (wts[i] > 0.02) {
				vec3 uvw = vec3(wuv * sc[i], float(i));
				vec4 t = texture(layers, uvw);
				if (anti_tile) {
					vec4 t2 = texture(layers, vec3(wuv * sc[i] * 0.31 + vec2(0.37, 0.71), float(i)));
					t = mix(t, t2, 0.35);
				}
				// «высота» = яркость: светлые камешки/кочки прорастают сквозь соседний слой
				float hgt = dot(t.rgb, vec3(0.33));
				float w = max(wts[i] + hgt * 0.45 - 0.2, 0.0);
				w = w * w;
				col += t.rgb * w; tot += w;
				if (normals_on) nacc += texture(normals, uvw).rgb * w;
			}
		}
		col /= max(tot, 0.0001);
		if (normals_on) nrm = nacc / max(tot, 0.0001);
		// крупные пятна цвета (против повторов) — из сэмпла слоя травы в очень мелком масштабе
		float macro = texture(layers, vec3(wxz * 0.0045, 0.0)).g;
		col *= mix(0.82, 1.16, smoothstep(0.15, 0.6, macro));
		col *= COLOR.a;   // яркость биома
	} else {
		float d = texture(layers, vec3(wuv * 0.8, 0.0)).g;
		float macro = texture(layers, vec3(wxz * 0.0045, 0.0)).g;
		col = srgb_to_lin(COLOR.rgb) * COLOR.a * (0.72 + d * 0.75) * mix(0.86, 1.12, smoothstep(0.15, 0.6, macro));
	}
	if (clouds_on) {
		float cl = texture(cloud_noise, wxz * 0.0016 + TIME * cloud_wind).r;
		col *= 1.0 - cloud_strength * smoothstep(0.48, 0.72, cl);
	}
	ALBEDO = col * grade_tint;
	if (normals_on) { NORMAL_MAP = nrm; NORMAL_MAP_DEPTH = 1.0; }
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
