# Protótipo: Interlagos + Porsche 992 GT3 R em Godot 4, com a física e a pista do jogo web.
# Controles: setas/WASD ou controle (gatilhos + analógico). R = volta para a pista. P = piloto automático.
# F1 = alterna qualidade (Alto/Celular). F12 = salva print. Esc = sai.
extends Node3D

const SUN_U := 0.5947
const SUN_ELEV := deg_to_rad(48.0)

var track: Track
var car: Car
var car_root: Node3D
var model: Node3D
var wheel_nodes: Array[Node3D] = []
var wheel_scale: Array[Vector3] = []
var model_offset := Vector3.ZERO
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var hud: Label
var hud_big: Label

var steer := 0.0
var cam_yaw := 0.0
var cam_ready := false
var lap_start := 0.0
var last_lap := -1.0
var best_lap := -1.0
var last_idx := 0
var time := 0.0
var autopilot := false
var high := true

# terreno (grade de alturas) para plantar árvores
var ter: Dictionary


func _ready() -> void:
	track = Track.new("res://data/track/track.json")
	_build_env()
	_build_track()
	_build_terrain()
	_build_trees()
	_build_car()
	_build_hud()
	var args := OS.get_cmdline_user_args()
	autopilot = "--auto" in args
	for a in args:
		if a.begins_with("--shot="):
			shot_dir = a.substr(7)
			autopilot = true
	car.reset_at((track.n - 20) % track.n)


# modo de teste: --shot=<pasta> pilota sozinho, salva prints em alguns tempos e sai
var shot_dir := ""
var shot_times := [3.0, 9.0, 16.0, 24.0, 33.0, 45.0]
var shot_k := 0
var real_time := 0.0

func _shot_tick(dt: float) -> void:
	real_time += dt
	if shot_k < shot_times.size() and time >= shot_times[shot_k]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [shot_dir, shot_k])
		print("shot %d t=%.1f v=%.0f km/h idx=%d fps=%d" % [shot_k, time, car.vel.length() * 3.6, car.hint, Engine.get_frames_per_second()])
		shot_k += 1
		if shot_k == shot_times.size():
			get_tree().quit()


# ------------------------------------------------------------------ ambiente

func _build_env() -> void:
	var phi := (SUN_U - 0.5) * TAU
	var sun_dir := Vector3(cos(phi) * cos(SUN_ELEV), sin(SUN_ELEV), sin(phi) * cos(SUN_ELEV))

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	# HDRI em meio-float (o import padrão do Godot quantizava o céu em faixas)
	var pano := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sky/ceu_2k.hdr"))
	pano.convert(Image.FORMAT_RGBAH)
	sky_mat.set_shader_parameter("pano", ImageTexture.create_from_image(pano))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.85)
	env.fog_density = 0.00035
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.light_angular_distance = 0.5
	add_child(sun)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP)


func _tex_mat(name: String, tint := Color.WHITE, rough_mul := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_diff.png" % name)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_nor_gl.png" % name)
	m.orm_texture = load("res://assets/textures/%s_arm.png" % name)
	m.roughness = rough_mul
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _orm(name: String, tint := Color.WHITE) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_diff.png" % name)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_nor_gl.png" % name)
	m.orm_texture = load("res://assets/textures/%s_arm.png" % name)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ------------------------------------------------------------------ pista

func _build_track() -> void:
	var t := track
	var asphalt := ShaderMaterial.new()
	asphalt.shader = load("res://shaders/asphalt.gdshader")
	asphalt.set_shader_parameter("albedo_tex", load("res://assets/textures/asphalt_track_diff.png"))
	asphalt.set_shader_parameter("normal_tex", load("res://assets/textures/asphalt_track_nor_gl.png"))
	asphalt.set_shader_parameter("arm_tex", load("res://assets/textures/asphalt_track_arm.png"))
	add_child(t.ribbon(func(i): return -t.wl[i], func(i): return t.wr[i], 0.0, asphalt, 5.0, 5.0))

	var white := _flat(Color(0.92, 0.92, 0.9), 0.6)
	add_child(t.ribbon(func(i): return -t.wl[i] + 0.05, func(i): return -t.wl[i] + 0.25, 0.006, white))
	add_child(t.ribbon(func(i): return t.wr[i] - 0.25, func(i): return t.wr[i] - 0.05, 0.006, white))

	# zebras estilo LMU (verde/amarelo/branco), listras de 1,5 m
	var kerb := ShaderMaterial.new()
	kerb.shader = load("res://shaders/kerb.gdshader")
	add_child(t.ribbon(func(i): return -t.wl[i] - t.kerb_l[i], func(i): return -t.wl[i], Track.KERB_H, kerb, 1.0, 1.0, true))
	add_child(t.ribbon(func(i): return t.wr[i], func(i): return t.wr[i] + t.kerb_r[i], Track.KERB_H, kerb, 1.0, 1.0, true))

	# escapes pintados (verde)
	var run := _orm("asphalt_track", Color(0.3, 0.72, 0.45))
	add_child(t.ribbon(func(i): return -t.wl[i] - t.kerb_l[i] - t.run_l[i], func(i): return -t.wl[i] - t.kerb_l[i], 0.004, run, 4, 4, true))
	add_child(t.ribbon(func(i): return t.wr[i] + t.kerb_r[i], func(i): return t.wr[i] + t.kerb_r[i] + t.run_r[i], 0.004, run, 4, 4, true))

	# grama entre a pista e o muro
	var grass := ShaderMaterial.new()
	grass.shader = load("res://shaders/terrain.gdshader")
	_grass_params(grass)
	add_child(t.ribbon(func(i): return -t.wall_l[i], func(i): return -t.wl[i] - t.kerb_l[i] - t.run_l[i], -0.02, grass))
	add_child(t.ribbon(func(i): return t.wr[i] + t.kerb_r[i] + t.run_r[i], func(i): return t.wall_r[i], -0.02, grass))

	# muros de concreto + guard-rail
	var concrete := _orm("concrete_wall_008", Color(0.95, 0.95, 0.95))
	add_child(t.wall(func(i): return -t.wall_l[i], -0.8, 1.05, concrete))
	add_child(t.wall(func(i): return t.wall_r[i], -0.8, 1.05, concrete))
	var rail := _flat(Color(0.75, 0.77, 0.8), 0.35)
	rail.metallic = 0.9
	add_child(t.wall(func(i): return -t.wall_l[i] + 0.08, 0.55, 0.85, rail))
	add_child(t.wall(func(i): return t.wall_r[i] - 0.08, 0.55, 0.85, rail))

	# linha de chegada
	var line := _flat(Color(0.95, 0.95, 0.95), 0.6)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(t.wl[0] + t.wr[0], 0.01, 0.6)
	mi.mesh = bm
	mi.material_override = line
	add_child(mi)
	mi.global_transform = Transform3D(Basis(t.R[0], t.R[0].cross(t.T[0]), -t.T[0]), t.P[0] + t.R[0] * (t.wr[0] - t.wl[0]) / 2.0 + Vector3.UP * 0.008)


func _grass_params(m: ShaderMaterial) -> void:
	m.set_shader_parameter("grass_a", load("res://assets/textures/leafy_grass_diff.png"))
	m.set_shader_parameter("grass_a_n", load("res://assets/textures/leafy_grass_nor_gl.png"))
	m.set_shader_parameter("grass_b", load("res://assets/textures/sparse_grass_diff.png"))
	m.set_shader_parameter("grass_b_n", load("res://assets/textures/sparse_grass_nor_gl.png"))
	var noise := NoiseTexture2D.new()
	noise.width = 512
	noise.height = 512
	noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	noise.noise = fn
	m.set_shader_parameter("mix_noise", noise)


# ------------------------------------------------------------------ relevo

func _build_terrain() -> void:
	ter = JSON.parse_string(FileAccess.get_file_as_string("res://data/track/terrain.json"))
	var nx := int(ter.nx)
	var nz := int(ter.nz)
	var c: float = ter.cell
	var x0: float = ter.x0
	var z0: float = ter.z0
	var h: Array = ter.h
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	uvs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			verts[k] = Vector3(x0 + i * c, h[k], z0 + j * c)
			uvs[k] = Vector2(verts[k].x, verts[k].z) / 6.0
			var hl: float = h[j * nx + maxi(i - 1, 0)]
			var hr: float = h[j * nx + mini(i + 1, nx - 1)]
			var hd: float = h[maxi(j - 1, 0) * nx + i]
			var hu: float = h[mini(j + 1, nz - 1) * nx + i]
			norms[k] = Vector3(hl - hr, 2.0 * c, hd - hu).normalized()
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	_grass_params(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	add_child(mi)


func terrain_h(x: float, z: float) -> float:
	var fx := clampf((x - ter.x0) / ter.cell, 0, ter.nx - 1.001)
	var fz := clampf((z - ter.z0) / ter.cell, 0, ter.nz - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var h: Array = ter.h
	var nx: int = ter.nx
	return lerpf(lerpf(h[j * nx + i], h[j * nx + i + 1], u), lerpf(h[(j + 1) * nx + i], h[(j + 1) * nx + i + 1], u), v)


# ------------------------------------------------------------------ árvores (impostores do jogo web)

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xs: Array[Transform3D] = []
	var custom: Array[Color] = []
	var tries := 0
	while tries < 30000 and xs.size() < 4500:
		tries += 1
		var i := rng.randi_range(0, track.n - 1)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var wall: float = track.wall_l[i] if side < 0 else track.wall_r[i]
		var off := wall + 5.0 + pow(rng.randf(), 1.6) * 260.0
		var p := track.P[i] + track.R[i] * side * off
		track.locate(p, -1)
		var lim := track.lwalll if track.ld < 0 else track.lwallr
		if absf(track.ld) < lim + 4.0 and absf(track.lcenter.y - p.y) < 8.0:
			continue
		p.y = terrain_h(p.x, p.z) - 0.1
		var sc := rng.randf_range(1.6, 3.0)
		xs.append(Transform3D(Basis.from_scale(Vector3.ONE * sc), p))
		custom.append(Color(rng.randi_range(0, 2), rng.randf() * TAU, rng.randf_range(0.8, 1.15), 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-0.5, 0, 0), Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(0.5, 0, 0)]:
		st.set_normal(Vector3.BACK)
		st.add_vertex(v)
	var quad := st.commit()
	mm.mesh = quad
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_custom_data(k, custom[k])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impostor.gdshader")
	mat.set_shader_parameter("color_atlas", load("res://assets/trees/arvores_cor.png"))
	mat.set_shader_parameter("normal_atlas", load("res://assets/trees/arvores_normal.png"))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-3000, -200, -3000), Vector3(6000, 600, 6000))
	add_child(mmi)


# ------------------------------------------------------------------ carro

func _build_car() -> void:
	car = Car.new(track)
	car_root = Node3D.new()
	add_child(car_root)
	var scene: PackedScene = load("res://assets/cars/porsche-992-gt3r/porsche-992-gt3r.glb")
	model = scene.instantiate()
	car_root.add_child(model)
	# alinha o eixo dianteiro do modelo com o da física e o chão do modelo com o chão em repouso (carView.ts)
	var front := -1.261
	var a: float = car.p.wheelbase * (1.0 - car.p.wf)
	model_offset = Vector3(0, -car.p.cg, -a - front)
	model.position = model_offset
	for nm in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
		var wn: Node3D = model.find_child(nm, true, false)
		wheel_nodes.append(wn)
		# o nó da roda vem com escala = raio (malha unitária): guardar para não perder ao girar
		wheel_scale.append(wn.scale if wn else Vector3.ONE)
	_fix_materials(model)


const PAINT := ["carpaint", "paint"]
const METAL := ["chrome", "disc", "disk", "rim", "wheel", "hub", "exhaust", "exalt", "mirror", "metal", "screw", "welding", "tamp", "caliper", "brake"]

func _fix_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if not (m is BaseMaterial3D):
				continue
			var bm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			var nm := String(bm.resource_name).to_lower()
			var is_metal := METAL.any(func(k): return k in nm)
			if PAINT.any(func(k): return k in nm):
				bm.metallic = minf(bm.metallic, 0.15)
				bm.metallic_texture = null
				bm.roughness = clampf(bm.roughness, 0.25, 0.4)
				bm.clearcoat_enabled = true
				bm.clearcoat = 1.0
				bm.clearcoat_roughness = 0.06
			elif not is_metal and bm.metallic_texture == null:
				bm.metallic = 0.0
			mi.set_surface_override_material(s, bm)
	for c in n.get_children():
		_fix_materials(c)


func _update_car_view() -> void:
	car_root.global_transform = Transform3D(Basis(car.rot), car.pos)
	for k in 4:
		var node := wheel_nodes[k]
		if node == null:
			continue
		var w: Car.Wheel = car.wheels[k]
		var p := w.mount
		p.y -= w.susp.rest - w.comp
		node.position = p - model_offset
		node.basis = Basis.from_euler(Vector3(-w.spin, -w.steer, 0), EULER_ORDER_YXZ).scaled_local(wheel_scale[k])


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 6000.0
	add_child(cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 18)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	hud_big = Label.new()
	hud_big.anchor_left = 0.5
	hud_big.anchor_right = 0.5
	hud_big.anchor_top = 1.0
	hud_big.anchor_bottom = 1.0
	hud_big.offset_left = -200
	hud_big.offset_right = 200
	hud_big.offset_top = -120
	hud_big.offset_bottom = -20
	hud_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_big.add_theme_font_size_override("font_size", 44)
	hud_big.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_big.add_theme_constant_override("outline_size", 10)
	layer.add_child(hud_big)


func _fmt(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	return "%d:%06.3f" % [int(t / 60.0), fmod(t, 60.0)]


# ------------------------------------------------------------------ laço

func _input_axes(dt: float) -> Array:
	var thr := 0.0
	var brk := 0.0
	var st_target := 0.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W): thr = 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S): brk = 1.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A): st_target -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): st_target += 1.0
	var joy := Input.get_connected_joypads()
	if joy.size() > 0:
		var d: int = joy[0]
		thr = maxf(thr, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT))
		brk = maxf(brk, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT))
		var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		if absf(ax) > 0.06:
			st_target = signf(ax) * pow((absf(ax) - 0.06) / 0.94, 1.6)
	if autopilot:
		return _autopilot()
	# volante: menos esterço com velocidade, rampa suave no teclado
	var v := absf(car.fwd_speed())
	var lim := clampf(1.0 - v / 90.0, 0.35, 1.0)
	steer = move_toward(steer, st_target * lim, dt * 3.5)
	return [steer, thr, brk]


## Piloto simples: mira um ponto à frente no centro da pista e freia pela curvatura adiante.
func _autopilot() -> Array:
	var i := car.hint
	var v := car.vel.length()
	var look := int(clampf(4.0 + v * 0.45, 6.0, 30.0) / Track.STEP)
	var target := track.P[(i + look) % track.n]
	var fwd := -car.basis().z
	var right := car.basis().x
	var to := (target - car.pos).normalized()
	var st := clampf(atan2(to.dot(right), to.dot(fwd)) * 2.6, -1.0, 1.0)
	# velocidade alvo pela menor curvatura nos próximos 140 m
	var vmax := 80.0
	for k in range(2, 70, 2):
		var a := track.T[(i + k) % track.n]
		var b := track.T[(i + k + 6) % track.n]
		var curv := absf(a.cross(b).y) / 12.0
		var vc := sqrt(1.75 * 9.81 / maxf(curv, 1e-4)) if curv > 1e-4 else 90.0
		vc = sqrt(vc * vc + 2.0 * 20.0 * k * Track.STEP)
		vmax = minf(vmax, vc)
	var thr := 1.0 if v < vmax - 1.0 else 0.0
	var brk := clampf((v - vmax) / 6.0, 0.0, 1.0)
	return [st, thr, brk]


func _physics_process(dt: float) -> void:
	var inp := _input_axes(dt)
	car.step(dt, inp[0], inp[1], inp[2])
	time += dt
	var idx := car.hint
	if last_idx > track.n - 40 and idx < 40:
		if lap_start > 0.0:
			last_lap = time - lap_start
			if best_lap < 0.0 or last_lap < best_lap:
				best_lap = last_lap
		lap_start = time
	last_idx = idx


func _process(dt: float) -> void:
	_update_car_view()
	if shot_dir != "":
		_shot_tick(dt)
	# câmera de perseguição (estilo LMU): 6,8 m atrás, 1,85 m de altura, rumo com atraso e no máx. 6°
	var fwd := -car.basis().z
	var yaw := atan2(-fwd.x, -fwd.z)
	if not cam_ready:
		cam_yaw = yaw
		cam_ready = true
	var diff := wrapf(yaw - cam_yaw, -PI, PI)
	cam_yaw += diff * minf(1.0, dt / 0.15)
	diff = wrapf(yaw - cam_yaw, -PI, PI)
	cam_yaw = yaw - clampf(diff, -deg_to_rad(6), deg_to_rad(6))
	var back := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var target := car.pos + Vector3.UP * 0.75
	var cp := car.pos + back * 6.8 + Vector3.UP * 1.85
	cam.global_position = cp
	cam.look_at(target - back * 4.0 + Vector3.UP * 0.2, Vector3.UP)
	if shot_dir != "" and shot_k % 3 == 0:
		# prints de vitrine: 3/4 de frente, perto do carro
		var r := car.basis().x
		cam.global_position = car.pos + fwd * 5.2 + r * 3.2 + Vector3.UP * 0.6
		cam.look_at(car.pos + Vector3.UP * 0.1, Vector3.UP)

	var kmh := car.vel.length() * 3.6
	hud_big.text = "%d km/h   %s" % [int(kmh), "N" if car.gear == 0 else ("R" if car.gear < 0 else str(car.gear))]
	hud.text = "Atual  %s\nÚltima %s\nMelhor %s\n%d rpm\n%d fps   %s%s\n[R] pista  [P] piloto  [F1] qualidade  [F12] print" % [
		_fmt(time - lap_start if lap_start > 0.0 else -1.0), _fmt(last_lap), _fmt(best_lap), int(car.rpm),
		Engine.get_frames_per_second(), "Alto" if high else "Celular", "  · piloto automático" if autopilot else ""]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_R:
				car.reset_at(track.nearest(car.pos, -1))
			KEY_P:
				autopilot = not autopilot
			KEY_F1:
				_set_quality(not high)
			KEY_F12:
				_screenshot()
			KEY_ESCAPE:
				get_tree().quit()


## "Celular": desliga o que o renderizador Mobile do Godot não tem ou é caro em celular, para ter uma ideia.
func _set_quality(h: bool) -> void:
	high = h
	env.ssao_enabled = h
	env.ssil_enabled = h
	env.ssr_enabled = h
	env.glow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if h else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0 if h else 120.0
	get_viewport().msaa_3d = Viewport.MSAA_4X if h else Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0 if h else 0.75


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var path := "%s/godot-gt3-%d.png" % [dir, Time.get_unix_time_from_system()]
	img.save_png(path)
	print("print: ", path)
