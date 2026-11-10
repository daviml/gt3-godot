// Céu HDRI com o mesmo mapeamento equiretangular do Three.js (o sol do jogo web bate com o do HDRI)
// + calibração de horizonte azulado estilo LMU (PLANO-visual etapa 6).
shader_type sky;

uniform sampler2D pano : filter_linear, repeat_enable;

void sky() {
	vec3 d = EYEDIR;
	vec2 uv = vec2(atan(d.z, d.x) / 6.2831853 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
	vec3 col = texture(pano, uv).rgb;

	// Horizonte levemente azulado até ~35° de elevação (igual blueHorizon do web), sem tingir nuvens altas nem o sol
	float elev = asin(clamp(d.y, -1.0, 1.0)); // radianos (-PI/2 a +PI/2)
	float haze = smoothstep(0.61, 0.05, elev) * clamp(1.0 - col.r * 0.4, 0.0, 1.0);
	col = mix(col, col * vec3(0.85, 0.95, 1.25) + vec3(0.04, 0.08, 0.16), haze * 0.45);

	COLOR = col;
}
