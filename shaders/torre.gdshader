// Torres residenciais do anel de arredores (porte do towerMaterial de src/render/surroundings.ts do web): andares
// de 2,9 m com janelas, faixa de varanda (laje clara e guarda-corpo escuro) em parte dos prédios, coluna de caixa
// de escada sem janela, térreo mais escuro e telhado de laje cinza. Tudo em coordenadas de mundo, num MultiMesh de
// caixas (uma chamada de desenho); a cor do reboco vem de INSTANCE_CUSTOM (já linear).
shader_type spatial;

varying vec3 v_w;
varying vec3 v_n;
varying float v_seed;
varying float v_h;
varying vec3 v_col;

float t_h(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7); }

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vec3 o = MODEL_MATRIX[3].xyz;
	v_seed = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_h = VERTEX.y * length(MODEL_MATRIX[1].xyz);
	v_col = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 c = v_col;
	float glass = 0.0;
	if (abs(v_n.y) > 0.5) {
		c = vec3(0.52, 0.52, 0.5) * (0.85 + 0.3 * t_h(floor(v_w.xz / 3.0)));
	} else {
		float u = abs(v_n.x) > abs(v_n.z) ? v_w.z : v_w.x;
		float floor_h = 2.9;
		vec2 cell = vec2(floor(u / 3.2), floor(v_h / floor_h));
		vec2 f = vec2(mod(u, 3.2), mod(v_h, floor_h));
		bool balcony = v_seed > 0.45;
		float ground = step(v_h, 3.5);
		// coluna da escada (sem janela) a cada ~6 vãos
		float stair = step(mod(cell.x + floor(v_seed * 7.0), 6.0), 0.5);
		float in_x = step(abs(f.x - 1.6), balcony ? 1.35 : 0.75);
		float in_y = step(0.8, f.y) * step(f.y, balcony ? 2.55 : 2.2);
		float lit = step(0.06, t_h(cell + v_seed * 13.0));
		glass = in_x * in_y * lit * (1.0 - stair) * (1.0 - ground);
		vec3 sky = mix(vec3(0.08, 0.1, 0.13), vec3(0.32, 0.38, 0.46), t_h(cell + 3.0));
		c = mix(c, sky, glass);
		if (balcony) {
			// laje da varanda (faixa clara) e guarda-corpo (faixa escura translúcida) em cada andar
			float slab = step(f.y, 0.22) * (1.0 - ground);
			float rail = step(0.22, f.y) * step(f.y, 1.05) * (1.0 - stair) * (1.0 - ground);
			c = mix(c, vec3(0.93, 0.92, 0.89), slab * 0.8);
			c = mix(c, c * 0.55, rail * 0.6);
		}
		// térreo mais escuro (portaria, garagem) e sujeira escorrida embaixo
		c *= 1.0 - ground * 0.35;
		c *= 0.82 + 0.18 * smoothstep(0.0, 12.0, v_h);
		// lado na sombra um pouco mais frio
		c *= 0.9 + 0.1 * abs(v_n.x);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.15, glass);
}
