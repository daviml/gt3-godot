// Brita/areia das áreas de escape (Laguna Seca no LMU: bege-amarelada, bem distinta do asfalto e do mato seco).
// Grão fino tirado da textura de grama seca (só o brilho), manchas grandes de tom em coordenadas de mundo e
// rastros mais escuros de quem passou por cima. UV em metros (mundo), sem repetição visível.
shader_type spatial;

uniform bool fast_mode = false;
uniform vec3 sand_color : source_color = vec3(0.80, 0.70, 0.50);
uniform sampler2D grain_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec2 ground;

float b_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float b_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(b_hash(i), b_hash(i + vec2(1, 0)), f.x), mix(b_hash(i + vec2(0, 1)), b_hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float big = b_noise(ground / 25.0) * 0.6 + b_noise(ground / 7.0 + 5.0) * 0.4;
	vec3 c = sand_color * (0.86 + 0.24 * big);
	if (!fast_mode) {
		float g = dot(texture(grain_tex, ground / 3.0).rgb, vec3(0.33));
		float g2 = dot(texture(grain_tex, ground / 0.9 + 0.37).rgb, vec3(0.33));
		c *= 0.78 + 0.5 * mix(g, g2, 0.5);
		// pedrinhas claras e escuras soltas
		float p = b_hash(floor(ground * 9.0));
		c *= p > 0.93 ? 1.12 : (p < 0.05 ? 0.82 : 1.0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.97;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
