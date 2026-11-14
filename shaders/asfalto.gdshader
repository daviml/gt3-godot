// Asfalto de Interlagos no estilo do LMU (porte do onBeforeCompile do asfalto em src/render/trackView.ts do web):
// cinza-amarronzado médio, lido em duas escalas (a repetição de 4 m some), manchas de tom de 18 e 45 m em
// coordenadas de mundo (trechos recapeados mais escuros, velhos mais claros) e variação fina de 7 m.
// A borracha do traçado real, as marcas de pneu e os remendos vêm por cima (malhas do cenario.glb).
// UV em metros/4 (igual ao web).
shader_type spatial;

uniform bool fast_mode = false;
// cor por pista (data/tracks.json → visual.asfalto); o padrão é o de Interlagos (cinza-amarronzado do LMU)
uniform vec3 color_mul = vec3(1.24, 1.14, 0.96);
uniform vec3 color_add = vec3(0.032, 0.028, 0.022);
uniform vec3 fast_mul = vec3(1.16, 1.08, 0.93);
uniform vec3 fast_add = vec3(0.022, 0.020, 0.016);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec2 ground;

float a_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float a_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a_hash(i), a_hash(i + vec2(1, 0)), f.x), mix(a_hash(i + vec2(0, 1)), a_hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = ground / 4.0;
	if (fast_mode) {
		vec3 c = texture(albedo_tex, uv).rgb;
		c = c * fast_mul + fast_add;
		float patch_n = a_noise(ground / 22.0 + 7.0) * 0.65 + a_noise(ground / 5.5 + 3.0) * 0.35;
		c *= 0.86 + 0.28 * patch_n;
		ALBEDO = c;
		ROUGHNESS = 0.84;
		METALLIC = 0.0;
	} else {
		vec3 c = texture(albedo_tex, uv).rgb;
		c = mix(c, texture(albedo_tex, uv * 0.23 + 0.41).rgb, 0.4);
		c = c * color_mul + color_add;
		float big = a_noise(ground / 45.0) * 0.65 + a_noise(ground / 18.0 + 13.0) * 0.35;
		float newer = smoothstep(0.6, 0.68, big);
		float older = smoothstep(0.36, 0.28, big);
		c *= mix(vec3(1.0), vec3(0.70, 0.71, 0.74), newer);
		c *= mix(vec3(1.0), vec3(1.14, 1.13, 1.10), older);
		c *= 0.92 + 0.16 * a_noise(ground / 7.0 + 3.0);
		ALBEDO = c;
		vec3 n1 = texture(normal_tex, uv).rgb * 2.0 - 1.0;
		vec3 n2 = texture(normal_tex, uv * 3.2).rgb * 2.0 - 1.0;
		NORMAL_MAP = normalize(vec3(n1.xy + n2.xy * 0.45, n1.z)) * 0.5 + 0.5;
		vec3 arm = texture(arm_tex, uv).rgb;
		AO = arm.r;
		AO_LIGHT_AFFECT = 0.3;
		ROUGHNESS = arm.g;
		METALLIC = 0.0;
	}
}
