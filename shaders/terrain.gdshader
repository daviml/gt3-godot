// Grama: mistura grama cheia e rala (Poly Haven) por ruído em escala grande, em coordenadas de mundo.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_a_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_b_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mix_noise : filter_linear, repeat_enable;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz / 4.0;
	float m = smoothstep(0.35, 0.7, texture(mix_noise, wp.xz / 700.0).r);
	vec3 a = texture(grass_a, uv).rgb;
	vec3 a2 = texture(grass_a, uv * 0.23 + 0.31).rgb;
	vec3 b = texture(grass_b, uv * 0.8).rgb;
	vec3 col = mix(mix(a, a2, 0.35), b, m * 0.3);
	col *= mix(0.82, 1.15, texture(mix_noise, wp.xz / 70.0).r);
	ALBEDO = col * vec3(0.62, 0.92, 0.42);
	NORMAL_MAP = mix(texture(grass_a_n, uv).rgb, texture(grass_b_n, uv * 0.8).rgb, m * 0.55);
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = 0.95;
}
