# Garagem: escolhe o carro (o galeria.html do web virou cena). O carro gira num estúdio com luz de softbox,
# piso que reflete e o reflexo das faixas de luz na pintura (sonda de reflexo).
# Controles: ◀ ▶ (setas/A D, direcional ou LB/RB no controle, botões na tela) trocam o carro; Enter/Espaço ou
# A no controle (ou o botão PILOTAR) vai para a pista; arrastar o mouse/dedo gira a câmera, roda do mouse
# aproxima; Esc sai do jogo.
# Linha de comando (depois de --): --car=<id>, --shot=<pasta> e --auto pulam a garagem e abrem a pista direto.
# --vitrine=<pasta> tira, de cada carro, um print 3/4 e três da roda dianteira esquerda (parada, girada 35° e
# girando rápido, com desfoque) e sai: confere materiais, pinça parada e desfoque.
extends Node3D

const TOP := 0.07          # altura do tampo do giratório
const SPIN_RATE := 0.22    # rad/s do giratório

var cars: Array
var idx := 0
var view: CarView
var pivot: Node3D           # giratório (o carro vai em cima)
var ring_mat: StandardMaterial3D
var cam: Camera3D
var cam_yaw := deg_to_rad(-35.0)
var cam_pitch := deg_to_rad(11.0)
var cam_dist := 7.4
var idle_t := 0.0           # tempo desde o último arrasto (o giratório para enquanto o Davi mexe)
var dragging := false
var steer_pose := 0.22      # rodas da frente esterçadas, pose de vitrine

var name_lbl: Label
var info_lbl: Label
var idx_lbl: Label
var shot_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car=") or a.begins_with("--shot=") or a == "--auto":
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
		if a.begins_with("--vitrine="):
			shot_dir = a.substr(10)
	cars = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	for i in cars.size():
		if cars[i].id == Game.car_id:
			idx = i
	_build_studio()
	_build_ui()
	_show(idx)
	if shot_dir != "":
		_vitrine.call_deferred()


# ------------------------------------------------------------------ estúdio

func _build_studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.033, 0.04)
	# luz ambiente do mesmo céu da pista (fraca); o reflexo vem da sonda, que enxerga as faixas de luz
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var pano := Image.load_from_file("res://assets/sky/ceu_2k.hdr")  # importer "keep": o .hdr vai cru no executável
	pano.convert(Image.FORMAT_RGBAH)
	sky_mat.set_shader_parameter("pano", ImageTexture.create_from_image(pano))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.03
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# piso escuro e liso (reflete o carro pelo SSR) e fundo infinito (ciclorama)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.055, 0.058, 0.065)
	floor_mat.roughness = 0.28
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fl.mesh = pm
	fl.material_override = floor_mat
	add_child(fl)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.07, 0.075, 0.085)
	wall_mat.roughness = 0.95
	wall_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	var cyc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 24.0
	cm.bottom_radius = 24.0
	cm.height = 16.0
	cm.cap_bottom = false
	cyc.mesh = cm
	cyc.position.y = 8.0
	cyc.material_override = wall_mat
	add_child(cyc)

	# giratório com anel de luz na cor do carro
	pivot = Node3D.new()
	add_child(pivot)
	var plate := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 3.3
	pc.bottom_radius = 3.35
	pc.height = TOP
	pc.radial_segments = 96
	plate.mesh = pc
	plate.position.y = TOP / 2.0
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.11, 0.115, 0.125)
	plate_mat.metallic = 0.6
	plate_mat.roughness = 0.35
	plate.material_override = plate_mat
	pivot.add_child(plate)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.33
	tm.outer_radius = 3.39
	tm.rings = 96
	ring.mesh = tm
	ring.position.y = TOP - 0.01
	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.emission_enabled = true
	ring.material_override = ring_mat
	pivot.add_child(ring)

	# faixas de softbox (aparecem como linhas de luz na pintura) e luz principal com sombra
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(1, 1, 1)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(1.0, 0.97, 0.92)
	strip_mat.emission_energy_multiplier = 3.0
	for z in [-2.4, 0.0, 2.4]:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(9.0, 0.05, 0.7)
		s.mesh = bm
		s.material_override = strip_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(0, 6.0, z)
		add_child(s)
	for x in [-9.0, 9.0]:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 2.6, 7.0)
		s.mesh = bm
		s.material_override = strip_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(x, 2.2, 0)
		add_child(s)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.97, 0.93)
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.light_angular_distance = 6.0
	key.directional_shadow_max_distance = 25.0
	add_child(key)
	key.look_at_from_position(Vector3(-3, 10, 4), Vector3.ZERO, Vector3.UP)
	for p in [Vector3(-6, 3.5, -6), Vector3(6, 3.5, 6), Vector3(0, 5.5, 0)]:
		var o := OmniLight3D.new()
		o.light_energy = 1.6 if p.y < 5 else 1.2
		o.omni_range = 14.0
		o.light_color = Color(0.85, 0.9, 1.0)
		o.position = p
		add_child(o)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(40, 14, 40)
	probe.position = Vector3(0, 1.0, 0)
	probe.origin_offset = Vector3(0, 0.5, 0)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.cull_mask = 1 << 1    # só o estúdio (camada 2): o carro não se reflete nele mesmo
	add_child(probe)
	for n in [fl, cyc, plate, ring]:
		n.layers = 1 | (1 << 1)
	for c in get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == strip_mat:
			c.layers = 1 << 1    # faixas de luz: só aparecem no reflexo, a câmera não as vê

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 200.0
	cam.cull_mask = 0xFFFFF & ~(1 << 1) | 1
	add_child(cam)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var title := _label("GARAGEM", 22, Color(1, 1, 1, 0.55))
	title.position = Vector2(36, 26)
	root.add_child(title)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -500
	box.offset_right = 500
	box.offset_top = -190
	box.offset_bottom = -40
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	idx_lbl = _label("", 18, Color(1, 1, 1, 0.5))
	name_lbl = _label("", 46, Color.WHITE)
	info_lbl = _label("", 20, Color(1, 1, 1, 0.8))
	for l in [idx_lbl, name_lbl, info_lbl]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)

	var prev := _button("◀", 44)
	prev.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	prev.offset_left = 30
	prev.offset_right = 120
	prev.offset_top = -50
	prev.offset_bottom = 50
	prev.pressed.connect(func(): _show(idx - 1))
	root.add_child(prev)
	var nxt := _button("▶", 44)
	nxt.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	nxt.offset_left = -120
	nxt.offset_right = -30
	nxt.offset_top = -50
	nxt.offset_bottom = 50
	nxt.pressed.connect(func(): _show(idx + 1))
	root.add_child(nxt)
	var go := _button("PILOTAR", 28)
	go.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	go.offset_left = -270
	go.offset_right = -36
	go.offset_top = -110
	go.offset_bottom = -40
	go.pressed.connect(_drive)
	root.add_child(go)

	var help := _label("◀ ▶ trocar   ·   Enter pilotar   ·   arraste para girar   ·   Esc sair", 16, Color(1, 1, 1, 0.45))
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 36
	help.offset_top = -48
	help.offset_bottom = -24
	root.add_child(help)


func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(t: String, size: int) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.08 if st == "normal" else (0.16 if st == "hover" else 0.28))
		sb.border_color = Color(1, 1, 1, 0.25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override(st, sb)
	return b


# ------------------------------------------------------------------ carro

func _show(i: int) -> void:
	idx = posmod(i, cars.size())
	var c: Dictionary = cars[idx]
	if view:
		view.queue_free()
	view = CarView.new(c.id)
	pivot.add_child(view)
	var p: Dictionary = view.data.params
	var mw: Array = view.data.model.wheels
	var mid: float = (mw[0].z + mw[1].z + mw[2].z + mw[3].z) / 4.0
	# CG da física acima do tampo, carro centrado no giratório
	view.position = Vector3(0, p.cgHeight + TOP, -(view.offset.z + mid))
	view.set_rest_pose(steer_pose)
	var col := Color(c.color)
	ring_mat.albedo_color = col
	ring_mat.emission = col
	ring_mat.emission_energy_multiplier = 2.5
	name_lbl.text = c.name
	info_lbl.text = _info(c, p)
	idx_lbl.text = "%d / %d" % [idx + 1, cars.size()]
	# carrega os vizinhos em segundo plano: trocar de carro fica rápido
	for d in [-1, 1]:
		var n: Dictionary = cars[posmod(idx + d, cars.size())]
		var glb := "res://assets/cars/%s/%s.glb" % [n.id, n.id]
		if ResourceLoader.load_threaded_get_status(glb) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(glb)


func _info(c: Dictionary, p: Dictionary) -> String:
	var cv := 0.0
	for pt in p.engine.torque:
		cv = maxf(cv, pt[0] * pt[1] * TAU / 60.0 / 735.5)
	return "Motor %s   ·   %d cv   ·   %d kg   ·   %d marchas" % [c.layout, roundi(cv / 5.0) * 5, p.mass, p.gearbox.ratios.size()]


func _drive() -> void:
	Game.save_car(cars[idx].id)
	Game.from_garage = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ------------------------------------------------------------------ laço e entrada

func _process(dt: float) -> void:
	idle_t += dt
	if shot_dir == "" and idle_t > 3.0 and not dragging:
		pivot.rotation.y += SPIN_RATE * dt
	var target := Vector3(0, 0.55, 0)
	if shot_dir == "":
		cam.global_position = target + Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
		cam.look_at(target, Vector3.UP)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_LEFT, KEY_A:
				_show(idx - 1)
			KEY_RIGHT, KEY_D:
				_show(idx + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_drive()
			KEY_ESCAPE:
				get_tree().quit()
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
				_show(idx - 1)
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER:
				_show(idx + 1)
			JOY_BUTTON_A, JOY_BUTTON_START:
				_drive()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
			idle_t = 0.0
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			cam_dist = maxf(4.2, cam_dist - 0.4)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			cam_dist = minf(12.0, cam_dist + 0.4)
	elif e is InputEventMouseMotion and dragging:
		cam_yaw -= e.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + e.relative.y * 0.004, deg_to_rad(2), deg_to_rad(55))
		idle_t = 0.0


# ------------------------------------------------------------------ vitrine (prints de conferência)

func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])


func _vitrine() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	for i in cars.size():
		_show(i)
		var id: String = cars[i].id
		pivot.rotation.y = 0.0
		cam.global_position = Vector3(-4.6, 1.7, -5.4)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
		await _frames(8)
		await _snap(id + "_a")
		# roda dianteira esquerda, de lado (o lado esquerdo do carro é -X)
		var hub: Node3D = view.hubs[0]
		var c := hub.global_position
		cam.global_position = c + Vector3(-2.3, 0.15, 0.0)
		cam.look_at(c, Vector3.UP)
		for pose in [[0.0, 0.0, "b"], [0.6, 0.0, "c"], [0.0, 90.0, "d"]]:
			view.set_rest_pose(0.0, pose[0], pose[1])
			await _frames(3)
			await _snap("%s_%s" % [id, pose[2]])
		print("vitrine ", id)
	get_tree().quit()
