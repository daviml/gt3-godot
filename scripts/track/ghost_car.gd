# Carro Fantasma (Ghost Car) — grava a melhor volta pessoal (~12 Hz em user://ghosts/)
# e reproduz o carro translúcido interpolado na pista, alimentando também o delta ao vivo do LapTimer
# (com fallback automático para a volta de referência do Garage 61 quando não há PB salvo).
class_name GhostCar
extends Node3D

const GHOST_DIR := "user://ghosts"
const SAMPLE_DT := 1.0 / 12.0
const STRIDE := 8  # [t, px, py, pz, qx, qy, qz, qw]
const HIDE_DIST_SQ := 2.25  # oculta se estiver a menos de 1.5 m do jogador para não tampar a visão

var track_id := ""
var car_id := ""
var mode := "sim"
var enabled := true:
	set(v):
		enabled = v
		if not enabled and _model != null:
			_model.visible = false

var best_time := -1.0
var _play_frames := PackedFloat32Array()
var _play_idx := 0
var _rec_frames := PackedFloat32Array()
var _rec_next_t := 0.0
var _was_recording := false

var _model: Node3D
var _ghost_mat: StandardMaterial3D


func setup(p_track_id: String, p_car_id: String, p_mode: String, timer: LapTimer, build_visual := true) -> void:
	track_id = p_track_id
	car_id = p_car_id
	mode = p_mode
	enabled = Game.is_ghost_enabled()
	reset_recording()
	_play_frames = PackedFloat32Array()
	_play_idx = 0
	best_time = -1.0

	if build_visual:
		_build_visual()

	var loaded := load_ghost(timer)
	if not loaded and timer != null:
		_load_garage61_reference(timer)


func ghost_path() -> String:
	return "%s/%s__%s__%s.json" % [GHOST_DIR, track_id, car_id, mode]


func has_ghost() -> bool:
	return _play_frames.size() >= STRIDE * 2 and best_time > 0.0


func reset_recording() -> void:
	_rec_frames = PackedFloat32Array()
	_rec_next_t = 0.0
	_was_recording = false
	_play_idx = 0
	if _model != null:
		_model.visible = false


func _build_visual() -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	var scene := Game.load_car_scene(car_id)
	var data := Game.get_car_data(car_id)
	if scene == null or data.is_empty():
		return
	_model = scene.instantiate() as Node3D
	if _model == null:
		return
	var p: Dictionary = data.get("params", {})
	var model_info: Dictionary = data.get("model", {})
	var mw: Array = model_info.get("wheels", [])
	if mw.size() >= 2 and not p.is_empty():
		var front: float = (float(mw[0].z) + float(mw[1].z)) * 0.5
		var offset := Vector3(0.0, -float(p.cgHeight), -float(p.wheelbase) * (1.0 - float(p.weightFront)) - front)
		_model.position = offset
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.albedo_color = Color(0.26, 0.78, 1.0, 0.28)
		_ghost_mat.emission_enabled = true
		_ghost_mat.emission = Color(0.16, 0.62, 1.0)
		_ghost_mat.emission_energy_multiplier = 0.55
		_ghost_mat.roughness = 0.25
		_ghost_mat.metallic = 0.1
		_ghost_mat.cull_mode = BaseMaterial3D.CULL_BACK
		_ghost_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_apply_ghost_material(_model)
	_model.visible = false
	add_child(_model)


func _apply_ghost_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.name.begins_with("blur_"):
			mi.visible = false
			return
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _ghost_mat
	for c in node.get_children():
		_apply_ghost_material(c)


func load_ghost(timer: LapTimer) -> bool:
	var path := ghost_path()
	if not FileAccess.file_exists(path):
		return false
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		return false
	var t_val := float(raw.get("time", -1.0))
	var frames_arr = raw.get("frames", [])
	if t_val <= 0.0 or not (frames_arr is Array) or frames_arr.size() < STRIDE * 2:
		return false
	var pf := PackedFloat32Array()
	pf.resize(frames_arr.size())
	for i in frames_arr.size():
		pf[i] = float(frames_arr[i])
	_play_frames = pf
	best_time = t_val
	_play_idx = 0
	if timer != null:
		var trace_arr = raw.get("trace", [])
		if trace_arr is Array and not trace_arr.is_empty():
			var tr := PackedFloat32Array()
			tr.resize(trace_arr.size())
			for i in trace_arr.size():
				var v = trace_arr[i]
				tr[i] = NAN if v == null else float(v)
			timer.set_reference(tr, best_time)
	return true


func _load_garage61_reference(timer: LapTimer) -> void:
	var ref_id := Game.track_ref_for_car(car_id)
	if ref_id == "":
		# Fallback: qualquer referência disponível da pista atual
		var refs = Game.get_track_info(track_id).get("refs", {})
		if refs is Dictionary and not refs.is_empty():
			var keys: Array = (refs as Dictionary).keys()
			ref_id = String(refs[keys[0]])
	if ref_id == "":
		return
	var path := "res://data/reference/%s.json" % ref_id
	if not FileAccess.file_exists(path):
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		return
	var t_arr = raw.get("t", [])
	var step := float(raw.get("step", 2.0))
	var lap_time := float(raw.get("lapTime", NAN))
	if not (t_arr is Array) or t_arr.is_empty() or step <= 0.0:
		return
	var n_bins := ceili(timer.track.length / LapTimer.TRACE_STEP) + 1
	var trace := PackedFloat32Array()
	trace.resize(n_bins)
	trace.fill(NAN)
	# Converte o array de tempo por distância (step=2m) para o passo do LapTimer (10m)
	# Nota: em alguns arquivos do Garage 61 t[0] é o final da volta anterior (~lapTime) e cai para ~0 logo após a linha
	for k in n_bins:
		var dist := float(k) * LapTimer.TRACE_STEP
		var idx := clampi(roundi(dist / step), 0, t_arr.size() - 1)
		var tv := float(t_arr[idx])
		if k == 0 and tv > lap_time * 0.5:
			tv = 0.0
		trace[k] = tv
	timer.set_reference(trace, lap_time)


func update_frame(car: Car, timer: LapTimer) -> void:
	if car == null or timer == null:
		return

	# 1. Gravação leve a ~12 Hz durante volta ativa
	if timer.current >= 0.0:
		if not _was_recording or timer.current < _rec_next_t - 1.0:
			_rec_frames = PackedFloat32Array()
			_rec_next_t = 0.0
			_was_recording = true
		if timer.current >= _rec_next_t:
			_append_sample(timer.current, car.pos, car.rot)
			_rec_next_t = timer.current + SAMPLE_DT
	else:
		_was_recording = false

	# 2. Reprodução interpolada do carro fantasma
	if _model == null:
		return
	if not enabled or not has_ghost() or timer.current < 0.0 or timer.current > best_time:
		_model.visible = false
		return

	var pose := sample_pose(timer.current)
	if pose.is_empty():
		_model.visible = false
		return
	var gpos: Vector3 = pose.pos
	var grot: Quaternion = pose.rot
	position = gpos
	quaternion = grot
	_model.visible = gpos.distance_squared_to(car.pos) >= HIDE_DIST_SQ


func _append_sample(t: float, p: Vector3, q: Quaternion) -> void:
	var qn := q.normalized()
	_rec_frames.append(t)
	_rec_frames.append(p.x)
	_rec_frames.append(p.y)
	_rec_frames.append(p.z)
	_rec_frames.append(qn.x)
	_rec_frames.append(qn.y)
	_rec_frames.append(qn.z)
	_rec_frames.append(qn.w)


func sample_pose(t: float) -> Dictionary:
	var n := _play_frames.size() / STRIDE
	if n < 2:
		return {}
	if _play_idx >= n - 1 or _play_frames[_play_idx * STRIDE] > t:
		_play_idx = 0
	while _play_idx + 1 < n - 1 and _play_frames[(_play_idx + 1) * STRIDE] <= t:
		_play_idx += 1
	var i0 := _play_idx * STRIDE
	var i1 := mini(_play_idx + 1, n - 1) * STRIDE
	var t0 := _play_frames[i0]
	var t1 := _play_frames[i1]
	var alpha := clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
	var p0 := Vector3(_play_frames[i0 + 1], _play_frames[i0 + 2], _play_frames[i0 + 3])
	var p1 := Vector3(_play_frames[i1 + 1], _play_frames[i1 + 2], _play_frames[i1 + 3])
	var q0 := Quaternion(_play_frames[i0 + 4], _play_frames[i0 + 5], _play_frames[i0 + 6], _play_frames[i0 + 7])
	var q1 := Quaternion(_play_frames[i1 + 4], _play_frames[i1 + 5], _play_frames[i1 + 6], _play_frames[i1 + 7])
	return {
		"pos": p0.lerp(p1, alpha),
		"rot": q0.slerp(q1, alpha),
	}


func on_lap_completed(lap: LapTimer.Lap, timer: LapTimer) -> bool:
	var saved := false
	if lap != null and lap.valid and _rec_frames.size() >= STRIDE * 10:
		if best_time <= 0.0 or lap.time < best_time:
			best_time = lap.time
			_play_frames = _rec_frames.duplicate()
			_play_idx = 0
			_save_ghost(lap)
			if timer != null:
				timer.set_reference(lap.trace, lap.time)
			saved = true
	_rec_frames = PackedFloat32Array()
	_rec_next_t = 0.0
	_was_recording = false
	return saved


func _save_ghost(lap: LapTimer.Lap) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GHOST_DIR))
	var frames_out: Array = []
	frames_out.resize(_play_frames.size())
	for i in _play_frames.size():
		frames_out[i] = snappedf(_play_frames[i], 0.001)
	var trace_out: Array = []
	trace_out.resize(lap.trace.size())
	for i in lap.trace.size():
		trace_out[i] = null if is_nan(lap.trace[i]) else snappedf(lap.trace[i], 0.001)
	var payload := {
		"track": track_id,
		"car": car_id,
		"mode": mode,
		"time": snappedf(lap.time, 0.001),
		"trace": trace_out,
		"frames": frames_out,
	}
	var f := FileAccess.open(ghost_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()
