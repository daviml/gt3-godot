// Árvores como impostores (mesmo atlas do jogo web: 12 vistas x 3 árvores da Poly Haven).
// INSTANCE_CUSTOM: r = tipo (linha do atlas), g = giro, b = brilho.
shader_type spatial;
render_mode cull_disabled;

uniform bool fast_mode = false;
uniform sampler2D color_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;

const float VIEWS = 12.0;

varying vec2 uv0;
varying vec2 uv1;
varying float blend;
varying float shade;
varying vec3 v_right;
varying vec3 v_tocam;

void vertex() {
	vec2 sizes[3] = vec2[3](vec2(6.9045, 5.1280), vec2(5.9716, 3.4747), vec2(4.2450, 2.6674));
	vec3 ip = MODEL_MATRIX[3].xyz;
	vec3 tocam = CAMERA_POSITION_WORLD - ip;
	vec2 d = normalize(tocam.xz + vec2(1e-5));
	v_right = vec3(d.y, 0.0, -d.x);
	v_tocam = vec3(d.x, 0.0, d.y);
	int kind = int(INSTANCE_CUSTOM.r + 0.5);
	vec2 size = sizes[kind];
	vec2 cell = vec2(VERTEX.x + 0.5, VERTEX.y);
	VERTEX = v_right * VERTEX.x * size.x + vec3(0.0, VERTEX.y * size.y, 0.0);
	NORMAL = v_tocam;
	float a = mod((atan(d.x, d.y) - INSTANCE_CUSTOM.g) / 6.2831853 * VIEWS, VIEWS);
	float v0 = floor(a);
	blend = a - v0;
	float v1 = mod(v0 + 1.0, VIEWS);
	float k = float(kind);
	uv0 = vec2((v0 + cell.x) / VIEWS, (k + 1.0 - cell.y) / 3.0);
	uv1 = vec2((v1 + cell.x) / VIEWS, (k + 1.0 - cell.y) / 3.0);
	shade = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec4 tc = mix(texture(color_atlas, uv0), texture(color_atlas, uv1), blend);
	ALPHA = tc.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 leaf = tc.rgb;
	leaf = mix(vec3(dot(leaf, vec3(0.3, 0.59, 0.11))), leaf, 1.3) * vec3(0.86, 1.04, 0.8);
	ALBEDO = leaf * shade * 1.25;
	if (!fast_mode) {
		vec3 nt = mix(texture(normal_atlas, uv0).xyz, texture(normal_atlas, uv1).xyz, blend) * 2.0 - 1.0;
		vec3 nw = normalize(v_right * nt.x + vec3(0.0, 1.0, 0.0) * (nt.y + 0.35) + v_tocam * nt.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
