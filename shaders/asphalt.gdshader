// Asfalto: textura da Poly Haven + variação em escala grande (anti-repetição) + borracha no meio da pista.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	float big = texture(albedo_tex, UV * 0.071 + vec2(0.37, 0.11)).r;
	float lat = UV.x * 5.0; // metros a partir do centro
	float rubber = exp(-pow(lat / 2.4, 2.0)) * 0.22;
	ALBEDO = a * mix(0.85, 1.12, big) * (1.0 - rubber) * vec3(1.0, 0.99, 0.97);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 arm = texture(arm_tex, UV).rgb;
	AO = arm.r;
	ROUGHNESS = clamp(arm.g * 0.92 - rubber * 0.4, 0.45, 1.0);
	METALLIC = 0.0;
}
