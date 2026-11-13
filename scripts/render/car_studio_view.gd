# Estúdio 3D reutilizável para exibir e girar os carros GT3 (usado na Garagem inicial e na Garagem da Pausa).
class_name CarStudioView
extends Node3D

signal loading_changed(is_loading: bool, accent: Color)
signal car_mounted(car_id: String)

const TOP := 0.07
const SPIN_RATE := 0.22
const LOAD_DEBOUNCE := 0.10
const RAPID_SWITCH_MS := 220
const PREFETCH_DELAY := 0.25

var cars: Array = []
var idx := 0
var view: CarView
var pivot: Node3D
var ring_mat: StandardMaterial3D
var studio_env: Environment
var key_light: DirectionalLight3D
var studio_quality_level := 3
var cam: Camera3D
var cam_yaw := deg_to_rad(-35.0)
var cam_pitch := deg_to_rad(11.0)
var cam_dist := 7.4
var idle_t := 0.0
var dragging := false
var steer_pose := 0.22
var vitrine_mode := false
var manage_root_viewport := true
var cars_framing_enabled := false
var framing_vp_size := Vector2(1920.0, 1080.0)

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
var _studio_built := false


func setup(cars_list: Array, initial_car_id := "", is_vitrine := false, manage_vp := true) -> void:
	cars = cars_list
	vitrine_mode = is_vitrine
	manage_root_viewport = manage_vp
	if initial_car_id != "":
		for i in cars.size():
			if String(cars[i].get("id", "")) == initial_car_id:
				idx = i
				break
	if not _studio_built:
		_build_studio()


func build_studio() -> void:
	if not _studio_built:
		_build_studio()


func _build_studio() -> void:
	_studio_built = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.033, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.17, 0.22)
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1

	studio_env = env
	apply_studio_quality()

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

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
	probe.cull_mask = 1 << 1
	add_child(probe)
	for n in [fl, cyc, plate, ring]:
		n.layers = 1 | (1 << 1)
	for c in get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == strip_mat:
			c.layers = 1 << 1

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 200.0
	cam.cull_mask = 0xFFFFF & ~(1 << 1) | 1
	add_child(cam)
	update_camera(0.0)


func apply_studio_quality() -> void:
	studio_quality_level = Game.get_quality_level()
	var is_mobile := Game.is_mobile_platform()
	var is_compat := Game.is_compatibility_renderer()
	var vp := get_viewport()
	if vp and manage_root_viewport:
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
	if view:
		view.blob_shadow_enabled = studio_quality_level == 0


func set_cars_framing(enabled: bool, vp_size := Vector2.ZERO) -> void:
	cars_framing_enabled = enabled
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		framing_vp_size = vp_size


func show_car_by_id(car_id: String, sync := false) -> void:
	for i in cars.size():
		if String(cars[i].get("id", "")) == car_id:
			var delta := i - idx
			if delta != 0:
				_nav_dir = 1 if delta > 0 else -1
			show_index(i, sync)
			return


func step_car(delta: int) -> void:
	if cars.is_empty():
		return
	_nav_dir = 1 if delta >= 0 else -1
	show_index(idx + delta)


func show_index(i: int, sync := false) -> void:
	if cars.is_empty():
		return
	if not _studio_built:
		_build_studio()
	var now_ms := Time.get_ticks_msec()
	var rapid_switch := (now_ms - _last_switch_ms) < RAPID_SWITCH_MS
	_last_switch_ms = now_ms

	idx = posmod(i, cars.size())
	var c: Dictionary = cars[idx]
	var car_id: String = c.id
	var col := Color(c.color)

	if ring_mat:
		ring_mat.albedo_color = col
		ring_mat.emission = col
		ring_mat.emission_energy_multiplier = 2.5

	if _pending_car_id == car_id and not sync:
		return

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
			loading_changed.emit(false, col)
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
		loading_changed.emit(false, col)
		return

	if sync:
		_pending_car_id = ""
		_pending_glb = ""
		_pending_requested = false
		_mount_car(car_id, Game.load_car_scene(car_id))
		loading_changed.emit(false, col)
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
			loading_changed.emit(false, col)
			return

	_pending_car_id = car_id
	_pending_glb = glb
	loading_changed.emit(true, col)

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
	view = CarView.new(car_id, vitrine_mode, studio_quality_level == 0)
	view.blob_shadow_enabled = studio_quality_level == 0
	pivot.add_child(view)
	var p: Dictionary = view.data.params
	var mw: Array = view.data.model.wheels
	var mid: float = (mw[0].z + mw[1].z + mw[2].z + mw[3].z) / 4.0
	view.position = Vector3(0, p.cgHeight + TOP, -(view.offset.z + mid))
	view.set_rest_pose(steer_pose)
	_schedule_neighbor_prefetch()
	car_mounted.emit(car_id)


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
	if vitrine_mode or cars.size() <= 1:
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
		loading_changed.emit(false, Color.WHITE)
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
					loading_changed.emit(false, Color.WHITE)
					_mount_car(target_id, scene if scene != null else Game.load_car_scene(target_id))
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					var target_id := _pending_car_id
					_pending_car_id = ""
					_pending_glb = ""
					_pending_requested = false
					loading_changed.emit(false, Color.WHITE)
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


func update_camera(dt: float, spin_enabled := true) -> void:
	if not _studio_built or cam == null or pivot == null:
		return
	idle_t += dt
	if spin_enabled and idle_t > 3.0 and not dragging:
		pivot.rotation.y += SPIN_RATE * dt
	var target := Vector3(0, 0.55, 0)
	var eff_dist := cam_dist
	if cars_framing_enabled:
		var vp_rect := framing_vp_size
		if vp_rect.x <= 0.0 or vp_rect.y <= 0.0:
			var vp := get_viewport()
			if vp:
				vp_rect = vp.get_visible_rect().size
		if vp_rect.x > vp_rect.y:
			var cam_right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
			target = Vector3(0.0, 0.12, 0.0) + cam_right * 0.72
			eff_dist = maxf(cam_dist, 8.2)
	cam.global_position = target + Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * eff_dist
	cam.look_at(target, Vector3.UP)


func handle_drag_event(e: InputEvent) -> bool:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
			idle_t = 0.0
			return true
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			cam_dist = maxf(4.2, cam_dist - 0.4)
			return true
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			cam_dist = minf(12.0, cam_dist + 0.4)
			return true
	elif e is InputEventMouseMotion and dragging:
		cam_yaw -= e.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + e.relative.y * 0.004, deg_to_rad(2), deg_to_rad(55))
		idle_t = 0.0
		return true
	elif e is InputEventScreenTouch:
		dragging = e.pressed
		idle_t = 0.0
		return true
	elif e is InputEventScreenDrag:
		cam_yaw -= e.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + e.relative.y * 0.004, deg_to_rad(2), deg_to_rad(55))
		idle_t = 0.0
		return true
	return false


func _process(dt: float) -> void:
	update_camera(dt, true)
	_process_async_loading(dt)
