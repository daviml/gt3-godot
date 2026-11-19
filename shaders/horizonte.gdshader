// Horizonte (porte do buildHorizon de src/render/surroundings.ts do web): faixa cilíndrica bem longe com morros e
// cidade em camadas, já azulada pela distância na própria textura. Sem luz e sem neblina; o topo é transparente
// (recorte) e deixa o céu aparecer.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint_color = vec3(1.0, 1.0, 1.0);
uniform float brightness = 1.0;

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * tint_color * brightness;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.02;
}
