// Desfoque de velocidade (porte de src/render/speedBlur.ts do web): a imagem é borrada na direção do ponto de fuga,
// mais forte nas bordas e no chão perto da câmera, crescendo com a velocidade (90 a 260 km/h).
// O carro não borra: sua caixa projetada na tela vira uma máscara suave.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 car_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform float aspect = 1.7777778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 base = texture(screen_texture, SCREEN_UV);
	if (strength <= 0.001) {
		COLOR = base;
		return;
	}
	vec2 d = SCREEN_UV - center;
	// distância ao ponto de fuga (corrigida pelo aspecto da tela): o centro fica nítido
	float r = length(vec2(d.x * aspect, d.y));
	float amount = strength * smoothstep(0.12, 0.75, r);
	// chão perto da câmera (parte de baixo da tela no Godot: SCREEN_UV.y > 0.55) borra mais
	amount *= 1.0 + 0.9 * smoothstep(0.55, 1.0, SCREEN_UV.y);
	// máscara do carro, com borda suave
	if (car_rect.z > car_rect.x && car_rect.w > car_rect.y) {
		vec2 m = smoothstep(car_rect.xy - vec2(0.025), car_rect.xy + vec2(0.01), SCREEN_UV) * (1.0 - smoothstep(car_rect.zw - vec2(0.01), car_rect.zw + vec2(0.025), SCREEN_UV));
		amount *= 1.0 - m.x * m.y;
	}
	if (amount <= 0.001) {
		COLOR = base;
		return;
	}
	// amostras ao longo da direção do ponto de fuga com jitter para evitar faixas/degraus
	vec2 stepv = d * amount * 0.1 / 8.0;
	float jitter = hash(SCREEN_UV * 1000.0) - 0.5;
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	for (int i = -4; i <= 4; i++) {
		float t = float(i) + jitter;
		float w = 1.0 - abs(float(i)) / 5.0;
		acc += texture(screen_texture, SCREEN_UV - stepv * t) * w;
		wsum += w;
	}
	COLOR = acc / wsum;
}
