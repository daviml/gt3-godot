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
const LOAD_DEBOUNCE := 0.10    # atraso curto em trocas rápidas para evitar disparar cargas intermediárias
const RAPID_SWITCH_MS := 220   # janela para considerar troca rápida consecutiva
const PREFETCH_DELAY := 0.25   # respiro antes de pré-carregar carros vizinhos

class _SpinnerGraphic extends Control:
	var angle := 0.0
	var arc_color := Color(1, 1, 1, 0.92)

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.38
		draw_arc(c, r, 0.0, TAU, 24, Color(1, 1, 1, 0.16), 2.5, true)
		draw_arc(c, r, angle, angle + PI * 1.35, 18, arc_color, 2.5, true)

var cars: Array
var idx := 0
var view: CarView
var pivot: Node3D           # giratório (o carro vai em cima)
var ring_mat: StandardMaterial3D
var studio_env: Environment
var key_light: DirectionalLight3D
var studio_quality_level := 3
var cam: Camera3D
var cam_yaw := deg_to_rad(-35.0)
var cam_pitch := deg_to_rad(11.0)
var cam_dist := 7.4
var idle_t := 0.0           # tempo desde o último arrasto (o giratório para enquanto o Davi mexe)
var dragging := false
var steer_pose := 0.22      # rodas da frente esterçadas, pose de vitrine

var name_lbl: Label
var loading_overlay: PanelContainer
var loading_spinner: _SpinnerGraphic
var loading_lbl: Label
var lmu_menu: LmuMenu
var remote_records: Records.RemoteClient
var shot_dir := ""
var manual_setup := false
var _transitioning := false
var _prefetch_other_mode_records := true

var _nav_dir := 1
var _last_switch_ms := -1000
var _pending_car_id := ""
var _pending_glb := ""
var _pending_delay := 0.0
var _pending_requested := false
var _prefetch_delay := 0.0
var _prefetch_queue: Array[Dictionary] = []
var _in_flight_prefetches: Dictionary = {}
var _stale_loads: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car=") or a.begins_with("--shot=") or a == "--auto":
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
		if a.begins_with("--vitrine="):
			shot_dir = a.substr(10)
	cars = Game.get_cars_list()
	for i in cars.size():
		if cars[i].id == Game.car_id:
			idx = i
	if manual_setup:
		set_process(false)
		set_process_unhandled_input(false)
		return
	_build_studio()
	_build_ui()
	_show(idx)
	if shot_dir != "":
		_vitrine.call_deferred()


func setup_step_studio() -> void:
	_build_studio()


func setup_step_ui() -> void:
	_build_ui()


func setup_step_car() -> void:
	_show(idx)


func finish_loading() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	_process(0.0)


# ------------------------------------------------------------------ estúdio

func _build_studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.033, 0.04)
	# iluminação ambiente de estúdio suave; o reflexo realista vem da sonda (ReflectionProbe)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.17, 0.22)
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	
	# SSAO, SSR, Glow e resolução respeitam o preset gráfico salvo em user://jogo.cfg
	studio_env = env
	_apply_studio_quality()
		
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
	key_light = key
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.97, 0.93)
	key.shadow_enabled = studio_quality_level >= 1
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

func _apply_studio_quality() -> void:
	studio_quality_level = Game.get_quality_level()
	var is_mobile := Game.is_mobile_platform()
	var is_compat := Game.is_compatibility_renderer()
	var vp := get_viewport()
	if vp:
		vp.mesh_lod_threshold = 6.0 if studio_quality_level == 0 else (3.0 if studio_quality_level == 1 else 1.0)
		if studio_quality_level == 0:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = Game.get_minimal_3d_scale(vp)
			vp.msaa_3d = Viewport.MSAA_DISABLED
		elif studio_quality_level == 1:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if (is_mobile or is_compat) else Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.75
			vp.fsr_sharpness = 0.2
			vp.msaa_3d = Viewport.MSAA_DISABLED
		elif studio_quality_level == 2:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
	if studio_env:
		studio_env.ssao_enabled = (studio_quality_level >= 2) and not is_compat
		if studio_env.ssao_enabled:
			studio_env.ssao_radius = 0.8
			studio_env.ssao_intensity = 1.2 if studio_quality_level == 2 else 2.0
		studio_env.ssr_enabled = (studio_quality_level >= 3) and not is_compat
		if studio_env.ssr_enabled:
			studio_env.ssr_max_steps = 64
		studio_env.glow_enabled = studio_quality_level >= 2
		if studio_env.glow_enabled:
			studio_env.glow_intensity = 0.3 if studio_quality_level == 2 else 0.4
			studio_env.glow_bloom = 0.03
	if key_light:
		key_light.shadow_enabled = studio_quality_level >= 1


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var sync_root := func():
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sync_root.call()
	get_viewport().size_changed.connect(sync_root)

	lmu_menu = LmuMenu.new(LmuMenu.Context.GARAGE)
	lmu_menu.visible = (shot_dir == "")
	lmu_menu.car_selected.connect(_on_menu_car_selected)
	lmu_menu.drive_requested.connect(_drive)
	lmu_menu.quit_requested.connect(func(): get_tree().quit())
	lmu_menu.quality_changed.connect(func(_q: String): _apply_studio_quality())
	lmu_menu.mode_changed.connect(func(m: String):
		_prefetch_other_mode_records = false
		_fetch_shared_records(m)
	)
	root.add_child(lmu_menu)

	# Rótulo sincronizado (preservado para testes e automações que leem `gar.name_lbl.text`)
	name_lbl = _label("", 20, Color.WHITE)
	name_lbl.visible = false
	root.add_child(name_lbl)

	# Indicador discreto e não-bloqueante sobre a plataforma enquanto o carro carrega em segundo plano
	loading_overlay = PanelContainer.new()
	loading_overlay.set_anchors_preset(Control.PRESET_CENTER)
	loading_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	loading_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.visible = false
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.05, 0.06, 0.08, 0.78)
	lsb.border_color = Color(1, 1, 1, 0.18)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(12)
	lsb.content_margin_left = 18
	lsb.content_margin_right = 18
	lsb.content_margin_top = 10
	lsb.content_margin_bottom = 10
	loading_overlay.add_theme_stylebox_override("panel", lsb)
	root.add_child(loading_overlay)

	var lbox := HBoxContainer.new()
	lbox.add_theme_constant_override("separation", 10)
	lbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(lbox)

	loading_spinner = _SpinnerGraphic.new()
	lbox.add_child(loading_spinner)

	loading_lbl = _label("Carregando carro...", 18, Color(1, 1, 1, 0.92))
	lbox.add_child(loading_lbl)

	if shot_dir == "":
		remote_records = Records.RemoteClient.new()
		add_child(remote_records)
		_fetch_shared_records.call_deferred(Game.mode)


func _fetch_shared_records(m: String) -> void:
	if remote_records == null:
		return
	remote_records.fetch_ranking(m, func(ok: bool, voltas: Array, r_mode: String):
		if ok and lmu_menu != null and is_instance_valid(lmu_menu):
			lmu_menu.set_shared_records(r_mode, voltas)
		if _prefetch_other_mode_records:
			_prefetch_other_mode_records = false
			var other := "arcade" if r_mode == "sim" else "sim"
			_fetch_shared_records(other)
	)


func _on_menu_car_selected(car_id: String) -> void:
	for i in cars.size():
		if cars[i].id == car_id:
			var delta := posmod(i - idx, cars.size())
			_nav_dir = 1 if delta <= cars.size() / 2 else -1
			_show(i)
			return


func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ carro

func _show(i: int, sync := false) -> void:
	if cars.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var rapid_switch := (now_ms - _last_switch_ms) < RAPID_SWITCH_MS
	_last_switch_ms = now_ms

	idx = posmod(i, cars.size())
	var c: Dictionary = cars[idx]
	var car_id: String = c.id

	# Atualiza UI, anel luminoso e especificações na hora (sem esperar GLB)
	var col := Color(c.color)
	if ring_mat:
		ring_mat.albedo_color = col
		ring_mat.emission = col
		ring_mat.emission_energy_multiplier = 2.5
	if name_lbl:
		name_lbl.text = c.name
	if lmu_menu:
		lmu_menu.set_selected_car(car_id, false)

	# Se já estamos aguardando exatamente este carro em modo assíncrono, não reinicia
	if _pending_car_id == car_id and not sync:
		return

	# Ignora/descarta carga pendente anterior se o usuário trocou para outro carro
	if _pending_car_id != "" and _pending_car_id != car_id:
		if _pending_requested and _pending_glb != "":
			_stale_loads[_pending_glb] = true
		_pending_car_id = ""
		_pending_glb = ""
		_pending_requested = false
		_pending_delay = 0.0
	_prefetch_queue.clear()
	_prefetch_delay = PREFETCH_DELAY

	if view:
		if view.id == car_id and _pending_car_id == "":
			_set_loading_indicator(false)
			_schedule_neighbor_prefetch()
			return
		view.queue_free()
		view = null

	var cached := Game.get_cached_car_scene(car_id)
	if cached != null:
		_pending_car_id = ""
		_pending_glb = ""
		_pending_requested = false
		_mount_car(car_id, cached)
		_set_loading_indicator(false)
		return

	if sync:
		_pending_car_id = ""
		_pending_glb = ""
		_pending_requested = false
		_mount_car(car_id, Game.load_car_scene(car_id))
		_set_loading_indicator(false)
		return

	var glb := Game.get_car_glb_path(car_id)
	if glb == "":
		return

	var st := ResourceLoader.load_threaded_get_status(glb)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var scene := ResourceLoader.load_threaded_get(glb) as PackedScene
		_in_flight_prefetches.erase(glb)
		_stale_loads.erase(glb)
		if scene != null:
			_pending_car_id = ""
			_pending_glb = ""
			_pending_requested = false
			_mount_car(car_id, scene)
			_set_loading_indicator(false)
			return

	_pending_car_id = car_id
	_pending_glb = glb
	_set_loading_indicator(true, col)

	if _stale_loads.has(glb):
		_stale_loads.erase(glb)
		_pending_requested = true
		_pending_delay = 0.0
	elif _in_flight_prefetches.has(glb) or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_in_flight_prefetches.erase(glb)
		_pending_requested = true
		_pending_delay = 0.0
	else:
		_pending_requested = false
		_pending_delay = LOAD_DEBOUNCE if rapid_switch else 0.0
		if _pending_delay <= 0.0:
			_start_pending_request()


func _mount_car(car_id: String, scene: PackedScene = null) -> void:
	if scene != null:
		Game.cache_car_scene(car_id, scene)
	if view:
		view.queue_free()
		view = null
	view = CarView.new(car_id, shot_dir != "", studio_quality_level == 0)
	pivot.add_child(view)
	var p: Dictionary = view.data.params
	var mw: Array = view.data.model.wheels
	var mid: float = (mw[0].z + mw[1].z + mw[2].z + mw[3].z) / 4.0
	# CG da física acima do tampo, carro centrado no giratório
	view.position = Vector3(0, p.cgHeight + TOP, -(view.offset.z + mid))
	view.set_rest_pose(steer_pose)
	_schedule_neighbor_prefetch()


func _set_loading_indicator(on: bool, accent := Color.WHITE) -> void:
	if loading_overlay:
		loading_overlay.visible = on
	if loading_spinner and on:
		loading_spinner.arc_color = accent.lightened(0.25)
		loading_spinner.queue_redraw()


func _neighbor_indices() -> Array[int]:
	var n := cars.size()
	if n <= 1:
		return []
	var primary := posmod(idx + _nav_dir, n)
	if Game.is_mobile_platform() or n == 2:
		return [primary]
	var secondary := posmod(idx - _nav_dir, n)
	return [primary, secondary]


func _schedule_neighbor_prefetch() -> void:
	_prefetch_queue.clear()
	if shot_dir != "" or cars.size() <= 1:
		return
	for ni in _neighbor_indices():
		var nid: String = cars[ni].id
		if nid == "" or Game.has_cached_car_scene(nid):
			continue
		var glb := Game.get_car_glb_path(nid)
		if glb != "":
			_prefetch_queue.append({"id": nid, "glb": glb})
	_prefetch_delay = PREFETCH_DELAY


func _cache_neighbor(pid: String, scene: PackedScene) -> void:
	Game.cache_car_scene(pid, scene)
	var cur_id: String = cars[idx].id if idx >= 0 and idx < cars.size() else ""
	if cur_id != "" and Game.has_cached_car_scene(cur_id):
		Game.get_cached_car_scene(cur_id)


func _start_pending_request() -> void:
	if _pending_glb == "":
		return
	var st := ResourceLoader.load_threaded_get_status(_pending_glb)
	if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_pending_requested = true
		return
	var err := ResourceLoader.load_threaded_request(_pending_glb, "PackedScene", true)
	if err == OK:
		_pending_requested = true
	else:
		var target_id := _pending_car_id
		_pending_car_id = ""
		_pending_glb = ""
		_pending_requested = false
		_set_loading_indicator(false)
		_mount_car(target_id, Game.load_car_scene(target_id))


func _process_async_loading(dt: float) -> void:
	if not _stale_loads.is_empty():
		for glb in _stale_loads.keys():
			var st := ResourceLoader.load_threaded_get_status(glb)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(glb)
				_stale_loads.erase(glb)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_stale_loads.erase(glb)

	if _pending_car_id != "":
		if not _pending_requested:
			_pending_delay -= dt
			if _pending_delay <= 0.0:
				_start_pending_request()
		if _pending_requested and _pending_glb != "":
			var st := ResourceLoader.load_threaded_get_status(_pending_glb)
			match st:
				ResourceLoader.THREAD_LOAD_LOADED:
					var scene := ResourceLoader.load_threaded_get(_pending_glb) as PackedScene
					var target_id := _pending_car_id
					_pending_car_id = ""
					_pending_glb = ""
					_pending_requested = false
					_set_loading_indicator(false)
					_mount_car(target_id, scene if scene != null else Game.load_car_scene(target_id))
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					var target_id := _pending_car_id
					_pending_car_id = ""
					_pending_glb = ""
					_pending_requested = false
					_set_loading_indicator(false)
					_mount_car(target_id, Game.load_car_scene(target_id))

	if _pending_car_id == "" and not _prefetch_queue.is_empty():
		_prefetch_delay -= dt
		if _prefetch_delay <= 0.0:
			while not _prefetch_queue.is_empty():
				var item: Dictionary = _prefetch_queue.pop_front()
				var pid: String = item.id
				var glb: String = item.glb
				if Game.has_cached_car_scene(pid) or _in_flight_prefetches.has(glb):
					continue
				if _stale_loads.has(glb):
					_stale_loads.erase(glb)
				var st := ResourceLoader.load_threaded_get_status(glb)
				if st == ResourceLoader.THREAD_LOAD_LOADED:
					var scene := ResourceLoader.load_threaded_get(glb) as PackedScene
					if scene != null:
						_cache_neighbor(pid, scene)
				elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					_in_flight_prefetches[glb] = pid
				else:
					var err := ResourceLoader.load_threaded_request(glb, "PackedScene", true)
					if err == OK:
						_in_flight_prefetches[glb] = pid

	if not _in_flight_prefetches.is_empty():
		var valid_neighbors := {}
		for ni in _neighbor_indices():
			valid_neighbors[cars[ni].id] = true
		for glb in _in_flight_prefetches.keys():
			var st := ResourceLoader.load_threaded_get_status(glb)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var pid: String = _in_flight_prefetches[glb]
				_in_flight_prefetches.erase(glb)
				var scene := ResourceLoader.load_threaded_get(glb) as PackedScene
				if scene != null and valid_neighbors.has(pid):
					_cache_neighbor(pid, scene)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_in_flight_prefetches.erase(glb)


func _drive() -> void:
	if _transitioning:
		return
	_transitioning = true
	var cur_nick := Records.load_nick()
	if cur_nick != "":
		Records.save_nick(cur_nick)
	if lmu_menu:
		lmu_menu.set_drive_busy(true)
	Game.save_car(cars[idx].id)
	Game.from_garage = true
	Game.transition_target = "track"
	get_tree().change_scene_to_file("res://scenes/loading.tscn")


# ------------------------------------------------------------------ laço e entrada

func _process(dt: float) -> void:
	idle_t += dt
	if shot_dir == "" and idle_t > 3.0 and not dragging:
		pivot.rotation.y += SPIN_RATE * dt
	var target := Vector3(0, 0.55, 0)
	var eff_dist := cam_dist
	if shot_dir == "":
		if lmu_menu != null and lmu_menu.visible and lmu_menu.active_view == "cars":
			var vp_rect := get_viewport().get_visible_rect().size
			if vp_rect.x > vp_rect.y:
				# Desloca o enquadramento para que o carro fique livre na área esquerda/superior, acima da barra inferior e à esquerda da ficha técnica
				var cam_right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
				target = Vector3(0.0, 0.12, 0.0) + cam_right * 0.72
				eff_dist = maxf(cam_dist, 8.2)
		cam.global_position = target + Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * eff_dist
		cam.look_at(target, Vector3.UP)
	if loading_overlay and loading_overlay.visible and loading_spinner:
		loading_spinner.angle = fmod(loading_spinner.angle + dt * 6.0, TAU)
		loading_spinner.queue_redraw()
	_process_async_loading(dt)


func _unhandled_input(e: InputEvent) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			focus_owner.release_focus()
		return
	var cur_view: String = lmu_menu.active_view if lmu_menu else "cars"
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_LEFT, KEY_A:
				if cur_view == "cars":
					_nav_dir = -1
					_show(idx - 1)
			KEY_RIGHT, KEY_D:
				if cur_view == "cars":
					_nav_dir = 1
					_show(idx + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if cur_view == "home" or cur_view == "cars":
					_drive()
			KEY_ESCAPE:
				if lmu_menu and lmu_menu.active_view != "home":
					lmu_menu.switch_view("home")
				else:
					get_tree().quit()
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
				if cur_view == "cars":
					_nav_dir = -1
					_show(idx - 1)
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER:
				if cur_view == "cars":
					_nav_dir = 1
					_show(idx + 1)
			JOY_BUTTON_A, JOY_BUTTON_START:
				if cur_view == "home" or cur_view == "cars":
					_drive()
			JOY_BUTTON_B:
				if lmu_menu and lmu_menu.active_view != "home":
					lmu_menu.switch_view("home")
	elif cur_view == "cars" and e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
			idle_t = 0.0
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			cam_dist = maxf(4.2, cam_dist - 0.4)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			cam_dist = minf(12.0, cam_dist + 0.4)
	elif cur_view == "cars" and e is InputEventMouseMotion and dragging:
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
		_show(i, true)
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
