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
const MATTE := ["bentley-continental-gt3-2020"]
## tempo de exposição do desfoque da roda (1/60 s, como uma câmera de TV)
const SHUTTER := 1.0 / 60.0
const GHOSTS := 6

static var _paint := RegEx.create_from_string("(?i)carpaint|paint(?!ed)|colou?r|body|livery|decal|alex_ka|(?:^|_)ext(?:\\.|$)")
static var _non_metal := RegEx.create_from_string("(?i)plastic|carbon|kevlar|glass|window|windshield|light|lamp|led|lcd|display|tyre|tire(?!.*(brake|hub|disk|wheel))|rubber|borracha|alcantara|seat|belt|net|occlusion|painted")
static var _metal := RegEx.create_from_string("(?i)chrome|disc|disk|rotor|rim|wheel|hub|exhaust|exalt|escapamento|mirror|metal|screw|welding|fuel|tamp|hook|brake")
static var _light_front_re := RegEx.create_from_string("(?i)headlight|foflight|fog_?light|lights?_hl|light_hl|lights?_fl")
static var _light_rear_re := RegEx.create_from_string("(?i)brakelight|taillight|tail_light|lights?_tl|light_rear|red_glass|light_emissive")
static var _light_any_re := RegEx.create_from_string("(?i)headlight|foflight|fog_?light|lights?_hl|light_hl|lights?_fl|brakelight|taillight|tail_light|lights?_tl|light_rear|red_glass|light_emissive|(?<![a-z])lights?(?![a-z])|lights1|mm_lights|bentley_gt3_lights")

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
## desfoque das rodas (6 cópias translúcidas por roda): desativado na garagem e nos presets Mínimo/Leve
var blur_enabled := false:
	set(v):
		if blur_enabled == v:
			return
		blur_enabled = v
		if blur_enabled:
			_ensure_ghosts()
		else:
			_hide_ghosts()
## materiais simplificados (sem clearcoat, normal map e anisotrópico) no preset Mínimo
var simple_materials := false:
	set(v):
		if simple_materials == v:
			return
		simple_materials = v
		_apply_material_mode()
## sombra de contato sob o chassi (ativa apenas quando não há sombra direcional do sol)
var blob_shadow_enabled := true:
	set(v):
		if blob_shadow_enabled == v:
			return
		blob_shadow_enabled = v
		if _blob_shadow:
			_blob_shadow.visible = blob_shadow_enabled
var _blob_shadow: MeshInstance3D
var _blur_sources: Array[MeshInstance3D] = []
var _mat_states: Array[Dictionary] = []
var _light_entries: Array[Dictionary] = []
var _beam_mesh: MeshInstance3D
var _spot_lights: Array[SpotLight3D] = []
var _brake_discs: Array[MeshInstance3D] = []
var _brake_disc_mats: Array[StandardMaterial3D] = []
var brake_heat := [0.0, 0.0, 0.0, 0.0]
var _sparks: CPUParticles3D
var _tire_smoke: Array[CPUParticles3D] = []
var vfx_enabled := true

## faróis e lanternas acesos (emissivo em todos os presets)
var headlights_on := false:
	set(v):
		if headlights_on == v:
			return
		headlights_on = v
		_apply_lights()
## luzes de freio acesas (ativado automaticamente quando brake > 0.05)
var brake_lights_on := false:
	set(v):
		if brake_lights_on == v:
			return
		brake_lights_on = v
		_apply_lights()
## habilita projeção de feixe na pista (desligado na garagem e para bots)
var beam_enabled := true:
	set(v):
		if beam_enabled == v:
			return
		beam_enabled = v
		_update_beam_visibility()
## true em Médio/Extremo (2x SpotLight3D sem sombra); false em Mínimo/Leve (malha aditiva 0 ms)
var beam_spotlight_enabled := false:
	set(v):
		if beam_spotlight_enabled == v:
			return
		beam_spotlight_enabled = v
		_update_beam_visibility()


func _init(car_id := "", enable_blur := false, enable_simple := false) -> void:
	if car_id != "":
		setup(car_id, enable_blur, enable_simple)


func setup(car_id: String, enable_blur := false, enable_simple := false) -> void:
	id = car_id
	blur_enabled = enable_blur
	simple_materials = enable_simple
	data = Game.get_car_data(id)
	model = Game.load_car_scene(id).instantiate()
	add_child(model)
	# alinha o eixo dianteiro do modelo com o da física e o chão do modelo com o chão em repouso
	var p: Dictionary = data.params
	var mw: Array = data.model.wheels
	var front: float = (mw[0].z + mw[1].z) / 2.0
	offset = Vector3(0, -p.cgHeight, -p.wheelbase * (1.0 - p.weightFront) - front)
	model.position = offset
	_mat_states.clear()
	_light_entries.clear()
	fix_materials(model, id, _mat_states)
	var rear_w: float = (mw[2].z + mw[3].z) * 0.5
	var mid_z: float = (front + rear_w) * 0.5
	_collect_light_materials(model, Transform3D.IDENTITY, mid_z, {})
	if simple_materials:
		_apply_material_mode()
	_build_blob_shadow(p)
	_build_headlight_beams(p, mw)
	_apply_lights()
	_brake_discs.clear()
	_brake_disc_mats.clear()
	_tire_smoke.clear()
	brake_heat = [0.0, 0.0, 0.0, 0.0]
	for suf in WHEELS:
		_build_wheel(suf)
	_build_vfx(p)


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
	mi.visible = blob_shadow_enabled
	_blob_shadow = mi
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
		_blur_sources.append(null)
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
	var blur := wn.find_child("blur_" + suf, false, false) as MeshInstance3D
	if blur:
		blur.visible = false
	_blur_sources.append(blur)
	ghosts.append(_create_wheel_ghosts(hub, blur) if blur_enabled else [])

	# Disco de freio incandescente (~0 ms, visível apenas quando aquecido em freadas fortes)
	var disc := MeshInstance3D.new()
	disc.name = "brake_glow_" + suf
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.185
	cyl.bottom_radius = 0.185
	cyl.height = 0.032
	cyl.radial_segments = 16
	cyl.rings = 1
	disc.mesh = cyl
	disc.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(1.0, 0.28, 0.04, 0.0)
	dmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	disc.material_override = dmat
	disc.visible = false
	hub.add_child(disc)
	_brake_discs.append(disc)
	_brake_disc_mats.append(dmat)


func _build_vfx(p: Dictionary) -> void:
	var ground_y := -float(p.get("cgHeight", 0.45))

	# Faíscas de fundo raspando (CPUParticles3D compatível com Forward+ e gl_compatibility)
	var sp := CPUParticles3D.new()
	sp.name = "floor_sparks"
	sp.position = Vector3(0.0, ground_y + 0.07, 0.0)
	sp.emitting = false
	sp.amount = 28
	sp.lifetime = 0.28
	sp.local_coords = false
	sp.direction = Vector3(0.0, 0.35, 1.0)
	sp.spread = 28.0
	sp.initial_velocity_min = 6.0
	sp.initial_velocity_max = 14.0
	sp.gravity = Vector3(0.0, -14.0, 0.0)
	sp.scale_amount_min = 0.03
	sp.scale_amount_max = 0.07
	var sp_mesh := QuadMesh.new()
	sp_mesh.size = Vector2(0.06, 0.18)
	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sp_mat.albedo_color = Color(1.0, 0.72, 0.22, 0.95)
	sp_mesh.material = sp_mat
	sp.mesh = sp_mesh
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sp)
	_sparks = sp

	# Fumaça leve de trava de roda / derrapagem forte (4 emissores leves, desligados no Mínimo)
	var sm_mesh := QuadMesh.new()
	sm_mesh.size = Vector2(0.55, 0.55)
	var sm_mat := StandardMaterial3D.new()
	sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm_mat.albedo_color = Color(0.82, 0.84, 0.88, 0.24)
	sm_mesh.material = sm_mat

	for k in 4:
		var sm := CPUParticles3D.new()
		sm.name = "tire_smoke_" + WHEELS[k]
		sm.emitting = false
		sm.amount = 14
		sm.lifetime = 0.50
		sm.local_coords = false
		sm.direction = Vector3(0.0, 0.45, 0.85)
		sm.spread = 32.0
		sm.initial_velocity_min = 0.8
		sm.initial_velocity_max = 2.4
		sm.gravity = Vector3(0.0, 0.7, 0.0)
		sm.scale_amount_min = 0.6
		sm.scale_amount_max = 1.8
		sm.mesh = sm_mesh
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sm)
		_tire_smoke.append(sm)


func _create_wheel_ghosts(hub: Node3D, blur: MeshInstance3D) -> Array:
	var list := []
	if blur == null or hub == null:
		return list
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
	return list


func _ensure_ghosts() -> void:
	for k in mini(ghosts.size(), _blur_sources.size()):
		if (ghosts[k] as Array).is_empty() and _blur_sources[k] != null and hubs[k] != null:
			ghosts[k] = _create_wheel_ghosts(hubs[k], _blur_sources[k])


func _hide_ghosts() -> void:
	for list in ghosts:
		for mi in list:
			(mi as MeshInstance3D).visible = false


## Posição do chassi e de cada roda a partir da física com interpolação sub-frame (main.gd).
func update_from(car: Car, frac := 1.0, dt := 0.016) -> void:
	var v_pos := car.visual_pos(frac)
	var v_rot := car.visual_rot(frac)
	transform = Transform3D(Basis(v_rot), v_pos)
	brake_lights_on = car.brake_out > 0.05
	var spd := car.speed()
	var bias: float = float(car.p.get("brake_bias", 0.58))
	var safe_dt := clampf(dt, 0.001, 0.1)
	var allow_particles := vfx_enabled and not simple_materials
	var bottoming := false

	for k in 4:
		var w: Car.Wheel = car.wheels[k]
		var p := w.mount
		p.y -= w.susp.rest - w.comp
		set_wheel(k, p - offset, w.steer, w.spin, w.omega)

		# 1. Aquecimento e resfriamento térmico dos discos de freio (~0 ms)
		var share := bias if w.front else (1.0 - bias)
		var heat_in := car.brake_out * clampf(spd / 55.0, 0.0, 1.35) * share * 1.15 * safe_dt
		var cool := (0.14 + spd * 0.0045) * safe_dt
		var h := clampf(float(brake_heat[k]) + heat_in - cool, 0.0, 1.0)
		brake_heat[k] = h
		if k < _brake_discs.size():
			var disc := _brake_discs[k]
			var show_disc := h > 0.10
			disc.visible = show_disc
			if show_disc:
				var t := clampf((h - 0.10) / 0.90, 0.0, 1.0)
				var col := Color(1.0, 0.14 + t * 0.50, 0.02 + t * t * 0.16, clampf(t * 0.85, 0.0, 0.88))
				_brake_disc_mats[k].albedo_color = col

		# 2. Detecção de fundo raspando e fumaça de trava/escorregamento (desligado no Mínimo)
		var travel: float = float(w.susp.get("travel", 0.08))
		if w.contact and w.comp > travel and spd > 14.0 and (w.comp_vel > 0.05 or w.fz > 3500.0):
			bottoming = true
		if k < _tire_smoke.size():
			var sm := _tire_smoke[k]
			var on_asphalt := w.contact and (w.surface == Ground.ASPHALT or w.surface == Ground.KERB)
			var sk := w.kappa / car.kappa_peak
			var sa := w.alpha / car.alpha_peak
			var slip := sqrt(sk * sk + sa * sa)
			var do_smoke := allow_particles and on_asphalt and spd > 10.0 and slip > 1.28
			var wheel_r := float(car.p.get("radius", 0.34))
			sm.position = Vector3(p.x, p.y - wheel_r + 0.05, p.z)
			sm.emitting = do_smoke

	if _sparks != null:
		_sparks.emitting = allow_particles and bottoming


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


# ------------------------------------------------------------------ faróis e lanternas


func _build_headlight_beams(p: Dictionary, mw: Array) -> void:
	var front_axle_z: float = -float(p.wheelbase) * (1.0 - float(p.weightFront))
	var ground_y: float = -float(p.cgHeight)
	var half_track: float = clampf(absf(float(mw[0].x) - float(mw[1].x)) * 0.42, 0.55, 0.80)

	# 1. Feixe leve em malha aditiva (Mínimo / Leve — ~0 ms, zero SpotLight3D)
	var beam := MeshInstance3D.new()
	beam.name = "headlight_beam_mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(11.0, 44.0)
	beam.mesh = plane
	beam.position = Vector3(0.0, ground_y + 0.06, front_axle_z - 22.8)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
void fragment() {
	float fwd = UV.y; // 1.0 = perto do carro, 0.0 = 44 m à frente
	float near_fade = smoothstep(1.0, 0.92, fwd);
	float dist_fade = smoothstep(0.0, 0.85, fwd);
	float spread = mix(0.48, 0.16, fwd);
	float left_cone = exp(-pow((UV.x - 0.43) / spread, 2.0));
	float right_cone = exp(-pow((UV.x - 0.57) / spread, 2.0));
	float intensity = clamp(left_cone + right_cone, 0.0, 1.35) * dist_fade * near_fade * 0.28;
	ALBEDO = vec3(0.92, 0.96, 1.0) * intensity;
	ALPHA = intensity;
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	beam.material_override = smat
	beam.visible = false
	_beam_mesh = beam
	add_child(beam)

	# 2. SpotLight3D duplo sem sombra (Médio / Extremo)
	_spot_lights.clear()
	for side in [-1.0, 1.0]:
		var sl := SpotLight3D.new()
		sl.name = "headlight_spot_" + ("L" if side < 0.0 else "R")
		sl.position = Vector3(side * half_track, ground_y + 0.58, front_axle_z - 0.85)
		sl.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		sl.light_color = Color(0.96, 0.97, 1.0)
		sl.light_energy = 4.5
		sl.spot_range = 90.0
		sl.spot_angle = 35.0
		sl.spot_attenuation = 1.2
		sl.shadow_enabled = false
		sl.visible = false
		_spot_lights.append(sl)
		add_child(sl)


func _collect_light_materials(n: Node, xform: Transform3D, mid_z: float, seen: Dictionary) -> void:
	var cur := xform
	if n is Node3D:
		cur = xform * (n as Node3D).transform
	if n is MeshInstance3D and not n.name.begins_with("blur_"):
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for s in mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m == null:
					m = mesh.surface_get_material(s)
				if not (m is BaseMaterial3D):
					continue
				var bm := m as BaseMaterial3D
				var nm := String(bm.resource_name)
				if not _light_any_re.search(nm):
					continue
				var role := "both"
				if _light_front_re.search(nm):
					role = "front"
				elif _light_rear_re.search(nm):
					role = "rear"
				else:
					var arr := mesh.surface_get_arrays(s)
					var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var z_min := INF
					var z_max := -INF
					for v in verts:
						var wz := (cur * v).z
						if wz < z_min:
							z_min = wz
						if wz > z_max:
							z_max = wz
					if z_max < mid_z:
						role = "front"
					elif z_min > mid_z:
						role = "rear"
				var key := "%d:%s" % [bm.get_instance_id(), role]
				if seen.has(key):
					continue
				seen[key] = true
				_light_entries.append({
					"mat": bm,
					"role": role,
					"has_tex": bm.albedo_texture != null,
					"orig_em_on": bm.emission_enabled,
					"orig_em": bm.emission,
					"orig_em_energy": bm.emission_energy_multiplier,
					"orig_em_tex": bm.emission_texture,
				})
	for c in n.get_children():
		_collect_light_materials(c, cur, mid_z, seen)


func _apply_lights() -> void:
	for entry in _light_entries:
		var bm := entry.mat as BaseMaterial3D
		if bm == null:
			continue
		var role: String = entry.role
		var has_tex: bool = entry.has_tex
		if role == "front":
			if headlights_on:
				bm.emission_enabled = true
				if has_tex:
					bm.emission_texture = bm.albedo_texture
					bm.emission = Color(1.0, 1.0, 1.0)
				else:
					bm.emission = Color(0.95, 0.97, 1.0)
				bm.emission_energy_multiplier = 2.8
			else:
				bm.emission_enabled = bool(entry.orig_em_on)
				bm.emission = entry.orig_em
				bm.emission_energy_multiplier = float(entry.orig_em_energy)
				bm.emission_texture = entry.orig_em_tex
		elif role == "rear":
			if brake_lights_on:
				bm.emission_enabled = true
				bm.emission_texture = null
				bm.emission = Color(1.0, 0.06, 0.03)
				bm.emission_energy_multiplier = 4.5
			elif headlights_on:
				bm.emission_enabled = true
				bm.emission_texture = null
				bm.emission = Color(1.0, 0.08, 0.05)
				bm.emission_energy_multiplier = 1.6
			else:
				bm.emission_enabled = bool(entry.orig_em_on)
				bm.emission = entry.orig_em
				bm.emission_energy_multiplier = float(entry.orig_em_energy)
				bm.emission_texture = entry.orig_em_tex
		else:
			if headlights_on or brake_lights_on:
				bm.emission_enabled = true
				if has_tex:
					bm.emission_texture = bm.albedo_texture
					bm.emission = Color(1.0, 1.0, 1.0)
				else:
					bm.emission = Color(0.95, 0.97, 1.0)
				bm.emission_energy_multiplier = 2.4 if brake_lights_on and not headlights_on else 2.0
			else:
				bm.emission_enabled = bool(entry.orig_em_on)
				bm.emission = entry.orig_em
				bm.emission_energy_multiplier = float(entry.orig_em_energy)
				bm.emission_texture = entry.orig_em_tex
	_update_beam_visibility()


func _update_beam_visibility() -> void:
	var show_any := headlights_on and beam_enabled
	if _beam_mesh:
		_beam_mesh.visible = show_any and not beam_spotlight_enabled
	for sl in _spot_lights:
		if sl:
			sl.visible = show_any and beam_spotlight_enabled


# ------------------------------------------------------------------ materiais (fixMetalness do carView.ts)

func _apply_material_mode() -> void:
	for entry in _mat_states:
		var m: BaseMaterial3D = entry.mat
		if not m:
			continue
		if simple_materials:
			m.clearcoat_enabled = false
			m.normal_enabled = false
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			m.clearcoat_enabled = bool(entry.clearcoat)
			m.normal_enabled = bool(entry.normal)
			m.texture_filter = int(entry.filter)


## Muitos modelos do Sketchfab vêm com metalness = 1 em quase tudo, o que deixa o carro com cara de cromado.
## Corrige pelo nome do material: pintura vira verniz (clearcoat) sobre tinta, metal de verdade continua metal
## e o resto vira não metálico.
static func fix_materials(n: Node, car_id: String, states: Array = [], mat_cache: Dictionary = {}) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is BaseMaterial3D:
				var key := m.get_instance_id()
				var fixed: BaseMaterial3D
				if mat_cache.has(key):
					fixed = mat_cache[key] as BaseMaterial3D
				else:
					fixed = fix_material(m as BaseMaterial3D, car_id)
					mat_cache[key] = fixed
					states.append({
						"mat": fixed,
						"clearcoat": fixed.clearcoat_enabled,
						"normal": fixed.normal_enabled,
						"filter": fixed.texture_filter,
					})
				mi.set_surface_override_material(s, fixed)
	for c in n.get_children():
		fix_materials(c, car_id, states, mat_cache)


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
