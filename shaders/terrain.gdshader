shader_type spatial;
// Ландшафт мира: 7 слоёв ambientCG (CC0) в Texture2DArray, веса — в CUSTOM0 (слои 0–3) и CUSTOM1 (4–6).
// tex_on = false (телефон, низкие пресеты): только цвет вершин (заранее смешанный средний цвет слоёв) + деталь из одного слоя.
render_mode cull_back, diffuse_burley, specular_disabled;
uniform sampler2DArray layers : source_color, filter_linear_mipmap, repeat_enable;
uniform bool tex_on = true;
uniform float uv_scale = 0.16;
varying vec4 w0;
varying vec3 w1;
varying vec2 wuv;

void vertex() {
	w0 = CUSTOM0;
	w1 = CUSTOM1.rgb;
	wuv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * uv_scale;
}

void fragment() {
	vec3 col;
	if (tex_on) {
		col = vec3(0.0);
		float tot = 0.0;
		if (w0.r > 0.02) { col += texture(layers, vec3(wuv, 0.0)).rgb * w0.r; tot += w0.r; }
		if (w0.g > 0.02) { col += texture(layers, vec3(wuv, 1.0)).rgb * w0.g; tot += w0.g; }
		if (w0.b > 0.02) { col += texture(layers, vec3(wuv * 1.3, 2.0)).rgb * w0.b; tot += w0.b; }
		if (w0.a > 0.02) { col += texture(layers, vec3(wuv, 3.0)).rgb * w0.a; tot += w0.a; }
		if (w1.r > 0.02) { col += texture(layers, vec3(wuv, 4.0)).rgb * w1.r; tot += w1.r; }
		if (w1.g > 0.02) { col += texture(layers, vec3(wuv * 0.7, 5.0)).rgb * w1.g; tot += w1.g; }
		if (w1.b > 0.02) { col += texture(layers, vec3(wuv * 0.5, 6.0)).rgb * w1.b; tot += w1.b; }
		// COLOR.a — яркость биома (топи и руины темнее)
		col = col / max(tot, 0.001) * COLOR.a;
	} else {
		float d = texture(layers, vec3(wuv * 0.8, 0.0)).g;
		col = COLOR.rgb * COLOR.a * (0.72 + d * 0.75);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
