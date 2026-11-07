// Fachada procedural dos prédios do OSM (porte do facadeMaterial de src/render/osmScenery.ts do web): reboco
// (concreto clareado por cima da cor do prédio, que vem por vértice), janelas em grade por andar de 3 m com vidro
// escuro refletindo o céu, parapeito e sujeira perto do chão. UV = metros na fachada; UV2.x = tipo
// (-1 teto, 0 parede lisa, 1 casa, 2 prédio).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D plaster : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

float h1(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7); }

void fragment() {
	float win = UV2.x;
	vec2 fac = UV;
	vec3 c = COLOR.rgb;
	vec3 pl = texture(plaster, fac / 4.0).rgb;
	float glass = 0.0;
	if (win < -0.5) {
		c *= 0.75 + 0.5 * pl.r;
	} else {
		c *= 0.6 + 0.8 * pl.g;
		if (win > 0.5) {
			bool house = win < 1.5;
			float bay = house ? 3.6 : 3.0;
			float ww = house ? 1.2 : 1.7;
			vec2 cell = vec2(floor(fac.x / bay), floor(fac.y / 3.0));
			vec2 f = vec2(mod(fac.x, bay), mod(fac.y, 3.0));
			float in_x = step(abs(f.x - bay * 0.5), ww * 0.5);
			float in_y = step(0.95, f.y) * step(f.y, house ? 2.15 : 2.45);
			float present = step(house ? 0.35 : 0.08, h1(cell));
			glass = in_x * in_y * present;
			float sill = step(abs(f.x - bay * 0.5), ww * 0.5 + 0.1) * step(0.82, f.y) * step(f.y, 0.95) * present;
			c = mix(c, vec3(0.75), sill * 0.6);
			vec3 sky = mix(vec3(0.07, 0.09, 0.12), vec3(0.35, 0.42, 0.5), h1(cell + 7.0));
			c = mix(c, sky, glass);
		}
		c *= 0.78 + 0.22 * smoothstep(0.0, 1.6, fac.y);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.12, glass);
	SPECULAR = mix(0.5, 0.8, glass);
}
