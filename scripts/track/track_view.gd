# Pista e arredores (etapa 7 do PLANO): tudo vem do próprio jogo web, exportado por tools/cenario.mjs:
#   assets/track/cenario.glb      asfalto, faixas, zebras, escapes por trecho, borracha e marcas de pneu do traçado
#                                 real, remendos, grid, muros com placas, barreira azul, alambrado, guard-rail, pneus,
#                                 pórticos, passarela, placas de frenagem e de curva, arquibancadas com torcida, pits,
#                                 postos de fiscal, câmeras de TV, cones, relevo, prédios do OSM, lago, kartódromo,
#                                 caixa d'água e paddock
#   data/track/arvores_pos.json   mata (impostores): [x, y, z, tamanho, espécie, giro, tom] por árvore
# O que o web desenha com shader próprio chega só com o nome do material, e aqui vira o shader equivalente:
#   asfalto → shaders/asfalto.gdshader, grama → shaders/grama.gdshader, fachada → shaders/fachada.gdshader,
#   ph:<nome> → texturas da Poly Haven, pinta → tinta com o relevo e a rugosidade do asfalto por baixo.
# O nome de cada malha traz a ordem de desenho e se faz sombra (o_<ordem>_s<0|1>), que o glTF não guarda.
class_name TrackView
extends Node3D

const GLB := "res://assets/track/cenario.glb"
const TREES := "res://data/track/arvores_pos.json"
const CHUNK := 250.0
const CULL_SECONDARY_MIN := 300.0
const CULL_SHADOW_DEFAULT := 550.0

var meshes := 0
var trees := 0
var surroundings: SurroundingsView
var detail_level := 2
var manual_setup := false
var _cache := {}
var _shader_mats: Array[ShaderMaterial] = []
var _base_mats: Array[Dictionary] = []
var _cull_meshes: Array[Dictionary] = []
var _name_re := RegEx.create_from_string("^o(-?\\d+)_s(\\d)")


func _init() -> void:
	name = "Pista"


func _ready() -> void:
	if manual_setup:
		return
	build_scene()
	build_trees()
	build_surroundings()
	set_detail(detail_level)


func build_scene(scene: PackedScene = null) -> void:
	if scene == null:
		scene = load(GLB)
	var root := scene.instantiate()
	add_child(root)
	_fix(root)


func build_surroundings(towers_data: Array = [], horizon_data: Dictionary = {}) -> void:
	# torres residenciais e horizonte (etapa 9): scripts/track/surroundings_view.gd
	surroundings = SurroundingsView.new()
	if not towers_data.is_empty():
		surroundings.preloaded_towers = towers_data
	if not horizon_data.is_empty():
		surroundings.preloaded_horizon = horizon_data
	add_child(surroundings)


func set_detail(level: int) -> void:
	detail_level = level
	var fast: bool = level <= 1
	var minimal: bool = level == 0
	for mat in _shader_mats:
		if mat and mat.resource_name != "fachada":
			mat.set_shader_parameter("fast_mode", fast)
	for entry in _base_mats:
		var m: BaseMaterial3D = entry.mat
		if m:
			m.normal_enabled = false if minimal else bool(entry.normal)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if minimal else int(entry.filter)
	for entry in _cull_meshes:
		var mi: MeshInstance3D = entry.mi
		if mi:
			if minimal:
				mi.visibility_range_end = CULL_SECONDARY_MIN
			else:
				mi.visibility_range_end = CULL_SHADOW_DEFAULT if entry.shadow else 0.0
	if surroundings:
		surroundings.set_detail(level)


func _fix(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		meshes += 1
		var order := 0
		var shadow := true
		var m := _name_re.search(mi.name)
		if m:
			order = int(m.get_string(1))
			shadow = m.get_string(2) == "1"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var is_primary_surface := false
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat:
				var mat_name := String(mat.resource_name)
				if mat_name in ["asfalto", "grama", "pinta", "torcida"]:
					is_primary_surface = true
				mi.set_surface_override_material(s, _material(mat, order))
		# Otimização de Distância de Visão (Culling / HLOD):
		# Detalhes secundários (postes, alambrado, cones, placas, detalhes de pit/arquibancada)
		# são cortados mais perto no Mínimo (300 m) e com sombra até 550 m nos demais presets.
		var ext := mi.get_aabb().size
		if order == 0 and not is_primary_surface and maxf(ext.x, ext.z) <= 450.0:
			_cull_meshes.append({"mi": mi, "shadow": shadow})
			mi.visibility_range_end_margin = 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if detail_level == 0:
				mi.visibility_range_end = CULL_SECONDARY_MIN
			else:
				mi.visibility_range_end = CULL_SHADOW_DEFAULT if shadow else 0.0
	for c in n.get_children():
		_fix(c)


func _material(src: Material, order: int) -> Material:
	var key := "%d:%d" % [src.get_instance_id(), order]
	if _cache.has(key):
		return _cache[key]
	var out: Material = src
	var nm := String(src.resource_name)
	var bm := src as BaseMaterial3D
	if nm == "asfalto":
		out = _shader("asfalto", {"albedo_tex": _tex("asphalt_track_diff"), "normal_tex": _tex("asphalt_track_nor_gl"), "arm_tex": _tex("asphalt_track_arm")})
	elif nm == "grama":
		out = _shader("grama", {"grass_tex": _tex("leafy_grass_diff"), "grass_n": _tex("leafy_grass_nor_gl"), "grass_arm": _tex("leafy_grass_arm"), "dry_tex": _tex("sparse_grass_diff")})
	elif nm == "fachada":
		out = _shader("fachada", {"plaster": _tex("concrete_wall_008_diff")})
	elif nm.begins_with("ph:") and bm:
		var ph := nm.substr(3)
		var o := ORMMaterial3D.new()
		o.albedo_texture = _tex(ph + "_diff")
		o.albedo_color = bm.albedo_color
		o.normal_enabled = true
		o.normal_texture = _tex(ph + "_nor_gl")
		o.orm_texture = _tex(ph + "_arm")
		o.cull_mode = bm.cull_mode
		o.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		out = o
	elif bm:
		var d := bm.duplicate() as BaseMaterial3D
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if nm == "pinta":
			d.normal_enabled = true
			d.normal_texture = _tex("asphalt_track_nor_gl")
			d.normal_scale = 0.6
			d.roughness_texture = _tex("asphalt_track_arm")
			d.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if d.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			# decalques (borracha, marcas, remendos, grid, faixas da pit lane): na ordem do web, sem gravar
			# profundidade, por cima do asfalto
			d.render_priority = clampi(order, -128, 127)
			# Otimização crítica mobile: alpha-scissor (test) ou depth prepass evita overdraw
			# desativando depth write com transparência simples reduz custo de GPU
			d.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		out = d
	if out is BaseMaterial3D:
		var obm := out as BaseMaterial3D
		_base_mats.append({"mat": obm, "normal": obm.normal_enabled, "filter": obm.texture_filter})
	_cache[key] = out
	return out


func _shader(file: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = file
	m.shader = load("res://shaders/%s.gdshader" % file)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_shader_mats.append(m)
	return m


func _tex(file: String) -> Texture2D:
	return load("res://assets/textures/%s.png" % file)


# ------------------------------------------------------------------ árvores (impostores do web)

func build_trees(data: Array = []) -> void:
	var a: Array = data if not data.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(TREES))
	trees = a.size() / 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-0.5, 0, 0), Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(0.5, 0, 0)]:
		st.set_normal(Vector3.BACK)
		st.add_vertex(v)
	var quad := st.commit()
	var mat := ShaderMaterial.new()
	mat.resource_name = "impostor"
	mat.shader = load("res://shaders/impostor.gdshader")
	mat.set_shader_parameter("color_atlas", load("res://assets/trees/arvores_cor.png"))
	mat.set_shader_parameter("normal_atlas", load("res://assets/trees/arvores_normal.png"))
	mat.set_shader_parameter("fast_mode", detail_level <= 1)
	_shader_mats.append(mat)
	# blocos de 250 m, cada um com a sua caixa: a câmera só desenha os blocos que vê (o cartão gira no shader,
	# então a caixa ganha a margem do maior tamanho de árvore)
	var cells := {}
	for k in trees:
		var key := Vector2i(floori(a[k * 7] / CHUNK), floori(a[k * 7 + 2] / CHUNK))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(k)
	for key in cells:
		var ids: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = ids.size()
		var box := AABB()
		for j in ids.size():
			var o: int = ids[j] * 7
			var p := Vector3(a[o], a[o + 1], a[o + 2])
			var sc: float = a[o + 3]
			mm.set_instance_transform(j, Transform3D(Basis.from_scale(Vector3.ONE * sc), p))
			mm.set_instance_custom_data(j, Color(a[o + 4], a[o + 5], a[o + 6], 0))
			var r := 3.5 * sc
			var b := AABB(p - Vector3(r, 0, r), Vector3(2 * r, 5.2 * sc, 2 * r))
			box = b if j == 0 else box.merge(b)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Arvores"
		mmi.multimesh = mm
		mmi.material_override = mat
		# como no web: a copa recebe sombra mas não faz (cada árvore faria uma passada a mais em cada fatia da sombra)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = box
		add_child(mmi)
