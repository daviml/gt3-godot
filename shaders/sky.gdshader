// Céu HDRI com o mesmo mapeamento equiretangular do Three.js (o sol do jogo web bate com o do HDRI)
// + calibração de horizonte azulado estilo LMU (PLANO-visual etapa 6).
// Por pista (data/tracks.json → visual.ceu), opcional: céu limpo procedural (degradê horizonte → zênite, chão
// para a luz ambiente e halo do sol na direção da luz) misturado por cima do HDRI, e giro do HDRI para o sol
// da foto acompanhar o sol da pista. Os padrões deixam o céu exatamente como antes (Laguna e Imola).
shader_type sky;

uniform sampler2D pano : filter_linear, repeat_enable;
uniform vec3 sky_tint = vec3(1.0, 1.0, 1.0);
uniform float sky_exposure = 1.0;
uniform vec3 horizon_color = vec3(0.04, 0.08, 0.16);
uniform float horizon_mix = 0.45;
uniform float night_amount = 0.0;
// giro do HDRI em fração de volta (0 = como exportado)
uniform float pano_offset = 0.0;
// 0 = só o HDRI (padrão); 1 = só o céu limpo
uniform float clear_amount = 0.0;
uniform vec3 clear_zenith = vec3(0.16, 0.36, 0.78);
uniform vec3 clear_horizon = vec3(0.55, 0.72, 0.92);
// expoente do degradê: menor = azul do zênite desce mais perto do horizonte
uniform float clear_curve = 0.5;
// abaixo do horizonte (não aparece atrás do relevo; vale para a luz ambiente que chega de baixo)
uniform vec3 clear_ground = vec3(0.20, 0.18, 0.14);
// halo em volta do sol (só no céu limpo)
uniform float clear_sun_halo = 0.6;

float sky_hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = EYEDIR;
	vec2 uv = vec2(atan(d.z, d.x) / 6.2831853 + 0.5 + pano_offset, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
	vec3 col = texture(pano, uv).rgb;
	if (clear_amount > 0.001) {
		float up = clamp(d.y, 0.0, 1.0);
		vec3 clear_c = mix(clear_horizon, clear_zenith, pow(up, clear_curve));
		clear_c = mix(clear_c, clear_ground, smoothstep(0.0, -0.12, d.y));
		if (LIGHT0_ENABLED) {
			float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
			clear_c += LIGHT0_COLOR * (pow(sd, 48.0) * 0.25 + pow(sd, 6.0) * 0.06) * clear_sun_halo * step(-0.02, d.y);
		}
		col = mix(col, clear_c, clear_amount);
	}
	col *= sky_tint * sky_exposure;

	// Horizonte levemente azulado até ~35° de elevação (igual blueHorizon do web), sem tingir nuvens altas nem o sol
	float elev = asin(clamp(d.y, -1.0, 1.0)); // radianos (-PI/2 a +PI/2)
	float haze = smoothstep(0.61, 0.05, elev) * clamp(1.0 - col.r * 0.4, 0.0, 1.0);
	vec3 haze_tint = mix(col * vec3(0.85, 0.95, 1.25) + horizon_color, horizon_color * 1.4, clamp(night_amount, 0.0, 0.75));
	col = mix(col, haze_tint, haze * horizon_mix);

	if (night_amount > 0.01) {
		float up = smoothstep(0.0, 0.75, clamp(d.y, 0.0, 1.0));
		vec3 night_sky = mix(vec3(0.018, 0.028, 0.062), vec3(0.005, 0.010, 0.026), up);
		col = mix(col, max(col * 0.4, night_sky), night_amount * 0.88);
		if (d.y > 0.04) {
			vec3 p = d * 260.0;
			vec3 cell = floor(p);
			vec3 f = fract(p) - 0.5;
			float s = sky_hash(cell);
			float star = step(0.994, s) * smoothstep(0.34, 0.06, length(f)) * smoothstep(0.04, 0.25, d.y);
			float twinkle = 0.65 + 0.35 * fract(s * 97.3);
			col += vec3(0.82, 0.88, 1.0) * star * twinkle * night_amount * 0.85;
		}
	}

	COLOR = col;
}
