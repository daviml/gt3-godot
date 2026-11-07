// Céu HDRI com o mesmo mapeamento equiretangular do Three.js (o sol do jogo web bate com o do HDRI).
shader_type sky;

uniform sampler2D pano : filter_linear, repeat_enable;

void sky() {
	vec3 d = EYEDIR;
	vec2 uv = vec2(atan(d.z, d.x) / 6.2831853 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
	COLOR = texture(pano, uv).rgb;
}
