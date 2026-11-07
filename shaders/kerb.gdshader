// Zebra estilo LMU: listras de 1,5 m (verde, amarelo, branco), tinta um pouco brilhante e gasta.
shader_type spatial;
render_mode cull_disabled;

void fragment() {
	float k = mod(floor(UV.y / 1.5), 3.0);
	vec3 c = k < 0.5 ? vec3(0.08, 0.42, 0.16) : (k < 1.5 ? vec3(0.95, 0.78, 0.08) : vec3(0.92, 0.92, 0.9));
	// desgaste: borracha escura nas bordas das listras e ruído
	float wear = fract(sin(dot(floor(UV * vec2(8.0, 6.0)), vec2(12.9898, 78.233))) * 43758.5453);
	c *= mix(0.82, 1.0, wear);
	ALBEDO = c;
	ROUGHNESS = 0.45 + wear * 0.2;
	// listra em relevo (onda leve transversal)
	float ph = fract(UV.y / 1.5);
	NORMAL_MAP = normalize(vec3(0.5, 0.5 + 0.25 * sin(ph * 6.2831853), 1.0));
}
