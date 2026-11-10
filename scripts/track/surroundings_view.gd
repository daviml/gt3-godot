# Arredores distantes (etapa 9 do PLANO; surroundings.ts do web), exportados por tools/arredores.mjs:
#   data/track/torres.json       anel de ~1.400 torres residenciais em condomínios (2–6 iguais) entre ~350 m e
#                                ~2,8 km da pista, mais denso a norte/leste: [x, base, z, giro, largura, altura,
#                                profundidade, cor sRGB] por torre. Um MultiMesh de caixas com a fachada (janelas,
#                                varandas, caixa de escada, térreo) em shaders/torre.gdshader: uma chamada de desenho.
#   data/track/horizonte.json    cilindro do horizonte a 3,9 km (centro, raio, altura, segmentos)
#   assets/track/horizonte.png   morros e cidade em camadas, já azulados pela distância (shaders/horizonte.gdshader)
# Os dois são baratos (≈ 17 mil triângulos no total, sem sombra), então ficam iguais em todos os presets.
class_name SurroundingsView
extends Node3D

const TOWERS := "res://data/track/torres.json"
const HORIZON := "res://data/track/horizonte.json"
const HORIZON_TEX := "res://assets/track/horizonte.png"

var towers := 0


func _init() -> void:
	name = "Arredores"


func _ready() -> void:
	_build_towers()
	_build_horizon()


# Orçamento dos arredores por preset (para a etapa 8 chamar ao trocar a qualidade): 0 = Leve, 1 = Médio,
# 2 = Extremo. A torcida em cartões (~40 mil pessoas, juntadas em blocos de 250 m pelo exportador) e a mata
# (MultiMesh por bloco de 250 m) ganham uma distância máxima de desenho; torres e horizonte ficam sempre (baratos).
# Sem esmaecer na borda (o esmaecimento desenha com transparência, caro no celular).
const DETAIL := [
	{"crowd": 220.0, "trees": 1500.0},
	{"crowd": 450.0, "trees": 2600.0},
	{"crowd": 0.0, "trees": 0.0},
]


func set_detail(level: int) -> void:
	var d: Dictionary = DETAIL[clampi(level, 0, DETAIL.size() - 1)]
	_apply_detail(get_parent() if get_parent() else self, d)


func _apply_detail(n: Node, d: Dictionary) -> void:
	if n is MultiMeshInstance3D and n.name.begins_with("Arvores"):
		_range(n, d.trees)
	elif n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(s)
			if mat and mat.resource_name == "torcida":
				_range(mi, d.crowd)
				break
	for c in n.get_children():
		_apply_detail(c, d)


func _range(g: GeometryInstance3D, end: float) -> void:
	g.visibility_range_end = end
	g.visibility_range_end_margin = 0.0
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _build_towers() -> void:
	var a: Array = JSON.parse_string(FileAccess.get_file_as_string(TOWERS))
	towers = a.size() / 8
	# caixa de 1 m com a base em y = 0 (como o BoxGeometry().translate(0, 0.5, 0) do web): o shader mede a
	# altura do andar a partir da base
	var arr := BoxMesh.new().get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += 0.5
	arr[Mesh.ARRAY_VERTEX] = v
	var box := ArrayMesh.new()
	box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = towers
	for k in towers:
		var o := k * 8
		var b := Basis(Vector3.UP, a[o + 3]) * Basis.from_scale(Vector3(a[o + 4], a[o + 5], a[o + 6]))
		mm.set_instance_transform(k, Transform3D(b, Vector3(a[o], a[o + 1], a[o + 2])))
		mm.set_instance_custom_data(k, Color.hex((int(a[o + 7]) << 8) | 0xff).srgb_to_linear())
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/torre.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Torres"
	mmi.multimesh = mm
	mmi.material_override = mat
	# como no web: sem sombra (estão longe, e cada torre seria mais uma passada em cada fatia da sombra)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_horizon() -> void:
	var h: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HORIZON))
	var r: float = h.radius
	var half: float = h.height / 2.0
	var n: int = h.segments
	# mesma malha do CylinderGeometry aberto do three.js (u = 0 em +z, girando para +x; v = 0 no topo)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in n + 1:
		var u := float(x) / n
		var th := u * TAU
		for y in 2:
			st.set_uv(Vector2(u, y))
			st.set_normal(Vector3(-sin(th), 0, -cos(th)))
			st.add_vertex(Vector3(r * sin(th), half - y * 2.0 * half, r * cos(th)))
	for x in n:
		var i := x * 2
		st.add_index(i)
		st.add_index(i + 1)
		st.add_index(i + 2)
		st.add_index(i + 2)
		st.add_index(i + 1)
		st.add_index(i + 3)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/horizonte.gdshader")
	mat.set_shader_parameter("tex", load(HORIZON_TEX))
	var mi := MeshInstance3D.new()
	mi.name = "Horizonte"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(h.x, h.y, h.z)
	add_child(mi)
