# Visual do carro (porta do carView.ts do web): modelo GT3, materiais corrigidos e rodas com suspensão, esterço
# e rotação. O tools/prep.ts já entrega o GLB com as normais corrigidas e, por roda, três nós (car_fix.ts):
#   wheel_XX    roda que gira (aro, pneu, disco);
#   caliper_XX  pinça/suporte: esterça e acompanha a suspensão, mas não gira;
#   blur_XX     filho da roda, o miolo dela (aro e disco), usado no desfoque da roda girando.
# Usado na pista (main.gd, com a física) e na garagem (garagem.gd, sem física).
class_name CarView
extends Node3D

const WHEELS := ["FL", "FR", "RL", "RR"]
## carros com envelopamento fosco: pintura sem verniz e peças sem espelhar o céu
const MATTE := ["ford-mustang-gt3"]
## tempo de exposição do desfoque da roda (1/60 s, como uma câmera de TV)
const SHUTTER := 1.0 / 60.0
const GHOSTS := 6

static var _paint := RegEx.create_from_string("(?i)carpaint|paint(?!ed)|colou?r|body|livery|decal|alex_ka")
static var _non_metal := RegEx.create_from_string("(?i)plastic|carbon|kevlar|glass|window|windshield|light|lamp|led|lcd|display|tyre|tire(?!.*(brake|hub|disk|wheel))|rubber|borracha|alcantara|seat|belt|net|occlusion|painted")
static var _metal := RegEx.create_from_string("(?i)chrome|disc|disk|rotor|rim|wheel|hub|exhaust|exalt|escapamento|mirror|metal|screw|welding|fuel|tamp|hook|brake")

var id := ""
var data: Dictionary
var model: Node3D
## deslocamento do modelo em relação ao CG da física (referencial do carro)
var offset := Vector3.ZERO
var hubs: Array[Node3D] = []        # posição da roda + esterço (pinça e roda dentro)
var spins: Array[Node3D] = []       # gira com a roda
var ghosts: Array = []              # por roda: cópias translúcidas do miolo para o desfoque
var _scale: Array[Vector3] = []
var _rest: Array[Vector3] = []      # centro da roda no modelo (garagem)
## desfoque das rodas (6 cópias translúcidas por roda): desligado no preset Leve
var blur_enabled := true


func _init(car_id := "") -> void:
	if car_id != "":
		setup(car_id)


func setup(car_id: String) -> void:
	id = car_id
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars/%s.json" % id))
	model = (load(data.model.glb) as PackedScene).instantiate()
	add_child(model)
	# alinha o eixo dianteiro do modelo com o da física e o chão do modelo com o chão em repouso
	var p: Dictionary = data.params
	var mw: Array = data.model.wheels
	var front: float = (mw[0].z + mw[1].z) / 2.0
	offset = Vector3(0, -p.cgHeight, -p.wheelbase * (1.0 - p.weightFront) - front)
	model.position = offset
	fix_materials(model, id)
	_build_blob_shadow(p)
	for suf in WHEELS:
		_build_wheel(suf)


## Sombra de contato suave sob o chassi (essencial no mobile para o carro não parecer flutuar sem SSAO)
func _build_blob_shadow(p: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "blob_shadow"
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.1, p.wheelbase + 1.6)
	mi.mesh = quad
	mi.position = Vector3(0, -p.cgHeight + 0.03, -p.wheelbase * (0.5 - p.weightFront))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.65)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = false
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## roda: um nó "cubo" no centro dela, com a roda (que gira) e a pinça (que não gira) dentro
func _build_wheel(suf: String) -> void:
	var wn := model.find_child("wheel_" + suf, true, false) as Node3D
	var hub := Node3D.new()
	hub.name = "hub_" + suf
	hubs.append(hub)
	if wn == null:
		spins.append(null)
		ghosts.append([])
		_scale.append(Vector3.ONE)
		_rest.append(Vector3.ZERO)
		return
	var par := wn.get_parent()
	par.add_child(hub)
	hub.position = wn.position
	_rest.append(wn.position)
	# o nó da roda vem com escala = raio (malha unitária): guardar para não perder ao girar
	var sc := wn.basis.get_scale()
	_scale.append(sc)
	wn.owner = null
	wn.reparent(hub, false)
	wn.transform = Transform3D(Basis.from_scale(sc), Vector3.ZERO)
	spins.append(wn)
	var cal := model.find_child("caliper_" + suf, true, false) as Node3D
	if cal:
		cal.owner = null
		cal.reparent(hub, false)
		cal.transform = Transform3D(Basis.from_scale(sc), Vector3.ZERO)
	# desfoque: cópias do miolo da roda, translúcidas, espalhadas no arco que a roda percorre num quadro
	var list := []
	var blur := wn.find_child("blur_" + suf, false, false) as MeshInstance3D
	if blur:
		blur.visible = false
		for g in GHOSTS:
			var mi := MeshInstance3D.new()
			mi.mesh = blur.mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in blur.mesh.get_surface_count():
				var m := blur.get_active_material(s)
				if m is BaseMaterial3D:
					var t := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					t.albedo_color.a *= 1.0 / (GHOSTS + 1)
					t.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					mi.set_surface_override_material(s, t)
			mi.visible = false
			hub.add_child(mi)
			list.append(mi)
	ghosts.append(list)


## Posição de cada roda a partir da física (main.gd).
func update_from(car: Car) -> void:
	transform = Transform3D(Basis(car.rot), car.pos)
	for k in 4:
		var w: Car.Wheel = car.wheels[k]
		var p := w.mount
		p.y -= w.susp.rest - w.comp
		set_wheel(k, p - offset, w.steer, w.spin, w.omega)


## Roda k no referencial do modelo: centro, esterço, ângulo girado e velocidade de giro (rad/s, para o desfoque).
func set_wheel(k: int, center: Vector3, steer: float, spin: float, omega := 0.0) -> void:
	var hub := hubs[k]
	if spins[k] == null:
		return
	hub.transform = Transform3D(Basis(Vector3.UP, -steer), center)
	spins[k].basis = Basis(Vector3.RIGHT, -spin).scaled_local(_scale[k])
	var arc := clampf(absf(omega) * SHUTTER, 0.0, 1.2)
	var list: Array = ghosts[k]
	var on := blur_enabled and arc > 0.06
	for g in list.size():
		var mi: MeshInstance3D = list[g]
		mi.visible = on
		if on:
			# espalhadas para trás do ângulo atual (o rastro fica atrás do raio que gira)
			var a := -spin + signf(omega) * arc * float(g + 1) / list.size()
			mi.basis = Basis(Vector3.RIGHT, a).scaled_local(_scale[k])


## Garagem: rodas na posição do modelo, esterço e giro dados.
func set_rest_pose(steer := 0.0, spin := 0.0, omega := 0.0) -> void:
	for k in 4:
		set_wheel(k, _rest[k], steer if k < 2 else 0.0, spin, omega)


# ------------------------------------------------------------------ materiais (fixMetalness do carView.ts)

## Muitos modelos do Sketchfab vêm com metalness = 1 em quase tudo, o que deixa o carro com cara de cromado.
## Corrige pelo nome do material: pintura vira verniz (clearcoat) sobre tinta, metal de verdade continua metal
## e o resto vira não metálico.
static func fix_materials(n: Node, car_id: String) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is BaseMaterial3D:
				mi.set_surface_override_material(s, fix_material(m as BaseMaterial3D, car_id))
	for c in n.get_children():
		fix_materials(c, car_id)


static func fix_material(src: BaseMaterial3D, car_id: String) -> BaseMaterial3D:
	var m := src.duplicate() as BaseMaterial3D
	var nm := String(m.resource_name)
	var matte := car_id in MATTE
	var transparent := m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	if _paint.search(nm) and not _non_metal.search(nm):
		m.metallic_texture = null
		if matte:
			m.metallic = 0.0
			m.roughness = 0.62
			m.roughness_texture = null
			m.clearcoat_enabled = false
			m.metallic_specular = 0.3
		else:
			m.metallic = minf(m.metallic, 0.15)
			m.roughness = clampf(m.roughness, 0.25, 0.4)
			# verniz: o reflexo nítido do céu por cima da tinta (PLANO-visual 6; no web, envMapIntensity 2)
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.04
			m.metallic_specular = 0.75
			# Assegura que mesmo em renderizadores sem SSR (como o Mobile), o reflexo do céu seja nítido
			m.roughness = clampf(m.roughness, 0.15, 0.32)
	elif m.metallic_texture != null:
		pass # textura de metalness feita pelo autor: confia nela
	elif _non_metal.search(nm) or not _metal.search(nm):
		m.metallic = 0.0
		if matte and not transparent:
			m.roughness = maxf(m.roughness, 0.6)
			m.clearcoat_enabled = false
	return m
