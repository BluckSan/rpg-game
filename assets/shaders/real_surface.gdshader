shader_type spatial;
// v0.6.0: реалистичные PBR-поверхности для построек, стен подземелья и прочей «геометрии» (бывшие одноцветные блоки
// Kenney и примитивы): трипланарные текстуры ambientCG (CC0) по мировым координатам — кладка, плиты, доски, брус,
// черепица, штукатурка, ткань, металл, скала, трава, солома, бут, грунт. Материал — INSTANCE_CUSTOM.r (слой+1)
// или, если 0, — по цвету вершины/копии (палитра Kenney): серое — камень/штукатурка, коричневое — дерево,
// красное на скатах — черепица и т.д. Цвет палитры слегка тонирует текстуру.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tint_amount = 0.18;
uniform int orange_layer = -1;    // палитра «дерево» → другой материал (палатки — ткань)
uniform int force_layer = -1;      // ≥0 — один материал для всего меша
uniform bool normals_on = true;
uniform bool use_instance = false; // MultiMesh с custom data
uniform float uv_mul = 1.0;
varying flat float layer;
varying vec3 wpos;
varying vec3 wn;
varying vec3 vcol;

const float SCALE[13] = float[13](0.45, 0.5, 0.55, 0.6, 0.5, 0.35, 0.8, 0.5, 0.25, 0.4, 0.45, 0.35, 0.3);
const float ROUGH[13] = float[13](0.85, 0.8, 0.75, 0.7, 0.65, 0.9, 0.95, 0.45, 0.85, 0.95, 0.95, 0.88, 0.95);
const float METAL[13] = float[13](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.85, 0.0, 0.0, 0.0, 0.0, 0.0);
// средняя яркость слоя (sRGB→лин.) — чтобы оттенок палитры не темнил текстуру
const vec3 AVG[13] = vec3[13](vec3(0.16), vec3(0.2), vec3(0.12), vec3(0.06), vec3(0.17, 0.07, 0.04), vec3(0.6), vec3(0.12), vec3(0.3),
	vec3(0.12), vec3(0.08, 0.12, 0.03), vec3(0.2, 0.15, 0.08), vec3(0.18, 0.14, 0.1), vec3(0.18, 0.13, 0.09));

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

float classify(vec3 c, vec3 n) {
	// палитра Kenney: дерево — оранжевое, камень — серо-лиловый, крыши — бирюза/красный, ткань — красная
	vec3 h = rgb2hsv(c);
	float slope = n.y;
	float hue = h.x;
	if (h.z < 0.28) return 7.0;                                         // тёмное — металл
	if (h.y < 0.14 || (h.y < 0.32 && hue > 0.5 && hue < 0.8)) {         // серое/серо-лиловое — камень
		return slope > 0.85 ? 1.0 : 0.0;
	}
	if (hue > 0.17 && hue < 0.42) return 9.0;                           // зелень — трава/мох
	if (hue >= 0.42 && hue < 0.5) return 4.0;                           // бирюзовые крыши — черепица
	if (hue >= 0.5 && hue < 0.9) return h.y > 0.35 ? 6.0 : 7.0;         // синее/фиолетовое — ткань или металл
	if (hue >= 0.9 || hue < 0.025) {
		if (slope > 0.25 && slope < 0.97) return 4.0;                   // красные скаты — черепица
		return 6.0;                                                     // красная ткань
	}
	if (hue < 0.11) {
		if (orange_layer >= 0) return float(orange_layer);
		return h.z < 0.66 ? 3.0 : 2.0;                                  // брус / доски
	}
	return h.z > 0.6 ? 10.0 : 2.0;                                      // жёлтое — солома / доски
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
	float l = -1.0;
	if (use_instance) l = INSTANCE_CUSTOM.r * 255.0 - 1.0;
	if (force_layer >= 0) l = float(force_layer);
	if (l < 0.0) l = classify(COLOR.rgb, wn);
	layer = l;
}

void fragment() {
	int li = int(layer + 0.5);
	float s = SCALE[li] * uv_mul;
	vec3 an = abs(wn);
	vec3 bw = pow(an, vec3(6.0)); bw /= (bw.x + bw.y + bw.z);
	vec3 col = vec3(0.0);
	vec3 pn = vec3(0.0);   // возмущение нормали в мировых осях (без касательных — у блоков их нет)
	// по каждой оси — только если её вес заметен (у блоков обычно одна проекция)
	if (bw.x > 0.02) {
		vec3 u = vec3(wpos.zy * s, layer); col += texture(albedo_arr, u).rgb * bw.x;
		if (normals_on) { vec2 t = texture(normal_arr, u).rg * 2.0 - 1.0; pn += vec3(0.0, t.y, t.x * sign(wn.x)) * bw.x; }
	}
	if (bw.y > 0.02) {
		vec3 u = vec3(wpos.xz * s, layer); col += texture(albedo_arr, u).rgb * bw.y;
		if (normals_on) { vec2 t = texture(normal_arr, u).rg * 2.0 - 1.0; pn += vec3(t.x, 0.0, -t.y) * bw.y; }
	}
	if (bw.z > 0.02) {
		vec3 u = vec3(wpos.xy * s, layer); col += texture(albedo_arr, u).rgb * bw.z;
		if (normals_on) { vec2 t = texture(normal_arr, u).rg * 2.0 - 1.0; pn += vec3(t.x * sign(wn.z), t.y, 0.0) * bw.z; }
	}
	vec3 lin = vcol * vcol;   // палитра (≈sRGB→лин.)
	vec3 tinted = col * clamp(lin / max(AVG[li], vec3(0.02)), vec3(0.35), vec3(2.2));
	ALBEDO = mix(col, tinted, tint_amount);
	if (normals_on) {
		vec3 n = normalize(wn + pn * 0.9);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	ROUGHNESS = ROUGH[li];
	METALLIC = METAL[li];
	SPECULAR = 0.4;
}
