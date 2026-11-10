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
	if get_parent():
		var t0 := Time.get_ticks_msec()
		_split_crowd(get_parent())
		print("arredores: %d torres, torcida em %d blocos (%d ms)" % [towers, crowd_blocks, Time.get_ticks_msec() - t0])


# ------------------------------------------------------------------ torcida em blocos

const CROWD_CELL := 120.0
var crowd_blocks := 0


static func _is_crowd(mi: MeshInstance3D) -> bool:
	for s in mi.get_surface_override_material_count():
		var mat := mi.get_surface_override_material(s)
		if mat == null and mi.mesh:
			mat = mi.mesh.surface_get_material(s)
		if mat and mat.resource_name == "torcida":
			return true
	return false


## A torcida chega do cenario.glb numa malha só de ~1 km (as arquibancadas da reta inteira): corta em blocos de
## 120 m pelo centro de cada triângulo, para a câmera descartar os blocos fora da tela e o preset Leve poder
## limitar a distância de desenho por bloco.
func _split_crowd(n: Node) -> void:
	for c in n.get_children():
		_split_crowd(c)
	if not (n is MeshInstance3D and _is_crowd(n)):
		return
	var mi := n as MeshInstance3D
	var xf := mi.global_transform
	var cells := {}  # Vector2i -> ArrayMesh
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var groups := {}  # Vector2i -> PackedInt32Array de índices
		for t in range(0, idx.size(), 3):
			var p := xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
			var key := Vector2i(floori(p.x / CROWD_CELL), floori(p.z / CROWD_CELL))
			if not groups.has(key):
				groups[key] = PackedInt32Array()
			groups[key].append_array([idx[t], idx[t + 1], idx[t + 2]])
		for key in groups:
			var sub := _sub_arrays(arr, groups[key])
			if not cells.has(key):
				cells[key] = ArrayMesh.new()
			var am: ArrayMesh = cells[key]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sub)
			am.surface_set_material(am.get_surface_count() - 1, mi.get_surface_override_material(s))
	for key in cells:
		var b := MeshInstance3D.new()
		b.name = "Torcida_%d_%d" % [key.x, key.y]
		b.mesh = cells[key]
		b.transform = mi.transform
		b.cast_shadow = mi.cast_shadow
		mi.get_parent().add_child(b)
		crowd_blocks += 1
	mi.get_parent().remove_child(mi)
	mi.queue_free()


## só os vértices usados pelos índices `tri`, renumerados
static func _sub_arrays(arr: Array, tri: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var out_idx := PackedInt32Array()
	out_idx.resize(tri.size())
	for i in tri.size():
		var o := tri[i]
		if not remap.has(o):
			remap[o] = order.size()
			order.append(o)
		out_idx[i] = remap[o]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var per := {Mesh.ARRAY_TANGENT: 4}
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		var src = arr[slot]
		if src == null:
			continue
		var k: int = per.get(slot, 1)
		var dst = src.duplicate()
		dst.resize(order.size() * k)
		for j in order.size():
			for e in k:
				dst[j * k + e] = src[order[j] * k + e]
		out[slot] = dst
	out[Mesh.ARRAY_INDEX] = out_idx
	return out


# Orçamento dos arredores por preset: 0 = Mínimo, 1 = Leve, 2 = Médio, 3 = Extremo.
# A torcida em cartões e a mata ganham distância de corte adequada para alta taxa de quadros no mobile.
const DETAIL := [
	{"level": 0, "crowd": 0.0, "trees": 600.0, "towers": 0.0},     # 0 = Mínimo (sem torcida, sem torres, mata 600m)
	{"level": 1, "crowd": 180.0, "trees": 1200.0, "towers": 1800.0}, # 1 = Leve (60 fps S22)
	{"level": 2, "crowd": 400.0, "trees": 2400.0, "towers": 0.0},    # 2 = Médio
	{"level": 3, "crowd": 0.0, "trees": 0.0, "towers": 0.0},         # 3 = Extremo (0 = ilimitado)
]


func set_detail(level: int) -> void:
	var d: Dictionary = DETAIL[clampi(level, 0, DETAIL.size() - 1)]
	_apply_detail(get_parent() if get_parent() else self, d)


func _apply_detail(n: Node, d: Dictionary) -> void:
	var lvl: int = int(d.get("level", 2))
	if n is MultiMeshInstance3D and _is_tree(n):
		_range(n, d.trees)
	elif n is MeshInstance3D and _is_crowd(n):
		if lvl == 0:
			n.visible = false
		else:
			n.visible = true
			_range(n, d.crowd)
	elif n is MultiMeshInstance3D and n.name == "Torres":
		if lvl == 0:
			n.visible = false
		else:
			n.visible = true
			_range(n, d.get("towers", 0.0))
	for c in n.get_children():
		_apply_detail(c, d)


## blocos de mata do TrackView (o nome "Arvores" só fica no primeiro; os outros viram @MultiMeshInstance3D@n)
static func _is_tree(n: Node) -> bool:
	var m := (n as MultiMeshInstance3D).material_override as ShaderMaterial
	return m != null and m.shader != null and m.shader.resource_path.ends_with("impostor.gdshader")


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
	if ResourceLoader.exists(HORIZON_TEX):
		mat.set_shader_parameter("tex", load(HORIZON_TEX))
	var mi := MeshInstance3D.new()
	mi.name = "Horizonte"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(h.x, h.y, h.z)
	add_child(mi)
