// Grama de Interlagos (porte do terrainMaterial de src/render/trackView.ts do web): verde-amarelada (leafy_grass) e
// palha seca alaranjada (sparse_grass) misturadas por ruído em coordenadas de mundo (manchas de dezenas de metros),
// cada uma lida em duas escalas; variação de tom grande, manchas mais verdes e terra vermelha só em trilhas finas
// e falhas pequenas. UV em metros/6 (igual ao web).
shader_type spatial;
render_mode cull_disabled;

uniform bool fast_mode = false;
uniform vec3 base_color = vec3(0.44, 0.70, 0.26); // verde-oliva natural calibrado ao LMU, em linear
// secura por pista (data/tracks.json → visual.grama); o padrão é o de Interlagos
uniform float dry_lo = 0.45;
uniform float dry_mix = 0.75;
uniform float lush_amt = 0.5;
uniform vec3 straw_tint = vec3(1.32, 1.08, 0.55);
uniform vec3 soil_color = vec3(0.50, 0.30, 0.18);
uniform float fast_dry_lo = 0.56;
uniform float fast_dry_mix = 0.45;
uniform vec3 fast_straw_tint = vec3(1.18, 0.92, 0.38);
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec2 ground;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = ground / 6.0;
	if (fast_mode) {
		vec3 green = texture(grass_tex, uv).rgb;
		float n = vnoise(ground * 0.018) * 0.65 + vnoise(ground * 0.07) * 0.35;
		float lg = dot(green, vec3(0.3, 0.59, 0.11));
		vec3 olive = mix(vec3(lg), green, 1.30) * vec3(0.78, 1.08, 0.44);
		vec3 straw = vec3(lg) * fast_straw_tint;
		float dry_k = smoothstep(fast_dry_lo, 0.86, n);
		ALBEDO = base_color * mix(olive, straw, dry_k * fast_dry_mix) * (0.86 + 0.28 * vnoise(ground * 0.035 + 7.0));
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
	} else {
		vec2 gp = ground;
		float n = vnoise(gp * 0.012) * 0.6 + vnoise(gp * 0.05) * 0.3 + vnoise(gp * 0.3) * 0.1;
		vec3 green = mix(texture(grass_tex, uv).rgb, texture(grass_tex, uv * 0.21 + 0.37).rgb, 0.45);
		vec3 dry_c = mix(texture(dry_tex, uv * 0.8).rgb, texture(dry_tex, uv * 0.17 + 0.61).rgb, 0.45);
		float lg = dot(green, vec3(0.3, 0.59, 0.11));
		green = mix(vec3(lg), green, 1.25) * vec3(1.02, 1.0, 0.62);
		float ld = dot(dry_c, vec3(0.3, 0.59, 0.11));
		vec3 straw = vec3(ld) * straw_tint * (0.85 + 0.3 * texture(grass_tex, uv * 0.5).g);
		float dry_k = smoothstep(dry_lo, 0.8, n);
		float tone = 0.82 + 0.34 * vnoise(gp * 0.03 + 7.0);
		float lush = smoothstep(0.55, 0.8, vnoise(gp * 0.09 + 13.0)) * lush_amt;
		vec3 grass_c = mix(mix(green, straw, dry_k * dry_mix), green * vec3(0.85, 1.0, 0.9), lush * (1.0 - dry_k));
		vec3 c = base_color * grass_c * tone;
		// terra vermelha só em trilhas finas e pequenas falhas
		float tr = abs(vnoise(gp * 0.018 + 31.0) - 0.5);
		float trail = (1.0 - smoothstep(0.004, 0.012, tr)) * smoothstep(0.4, 0.7, vnoise(gp * 0.01 + 3.0));
		float bald = smoothstep(0.78, 0.86, vnoise(gp * 0.12 + 5.0) * 0.7 + vnoise(gp * 0.9) * 0.3);
		float dirt = max(trail, bald * 0.7);
		vec3 soil = soil_color * (0.75 + 0.5 * texture(dry_tex, uv * 1.7).r);
		ALBEDO = mix(c, soil, dirt * 0.85);
		vec3 gn1 = texture(grass_n, uv).rgb * 2.0 - 1.0;
		vec3 gn2 = texture(grass_n, uv * 2.8).rgb * 2.0 - 1.0;
		NORMAL_MAP = normalize(vec3(gn1.xy + gn2.xy * 0.4, gn1.z)) * 0.5 + 0.5;
		vec3 arm = texture(grass_arm, uv).rgb;
		AO = arm.r;
		AO_LIGHT_AFFECT = 0.3;
		ROUGHNESS = arm.g;
	}
}
