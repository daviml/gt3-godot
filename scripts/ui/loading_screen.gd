# Tela reutilizável de Load (Fase 2): carrega recursos em threads separadas e fatia
# instanciação pesada entre múltiplos quadros para manter o loop responsivo.
class_name LoadingScreen
extends Control

const TRACK_SCENE := "res://scenes/main.tscn"
const GARAGEM_SCENE := "res://scenes/garagem.tscn"
const CENARIO_GLB := "res://assets/track/cenario.glb"
const SKY_HDR := "res://assets/sky/ceu_2k.hdr"

const TRACK_PRELOAD_RESOURCES := [
	"res://assets/track/horizonte.png",
	"res://assets/trees/arvores_cor.png",
	"res://assets/trees/arvores_normal.png",
	"res://assets/textures/asphalt_track_diff.png",
	"res://assets/textures/asphalt_track_nor_gl.png",
	"res://assets/textures/asphalt_track_arm.png",
	"res://assets/textures/leafy_grass_diff.png",
	"res://assets/textures/leafy_grass_nor_gl.png",
	"res://assets/textures/leafy_grass_arm.png",
	"res://assets/textures/sparse_grass_diff.png",
	"res://assets/textures/concrete_wall_008_diff.png",
	"res://shaders/sky.gdshader",
	"res://shaders/asfalto.gdshader",
	"res://shaders/grama.gdshader",
	"res://shaders/fachada.gdshader",
	"res://shaders/impostor.gdshader",
	"res://shaders/torre.gdshader",
	"res://shaders/horizonte.gdshader",
	"res://shaders/speed_blur.gdshader",
]

const TIPS := [
	"Dica: Pressione C (ou Y no controle) para alternar entre as câmeras.",
	"Dica: Use R para reiniciar a volta imediatamente no grid de largada.",
	"Dica: Ajuste qualidade gráfica e assistências (ABS/TC) no menu de pausa.",
	"Dica: Reduza a marcha antes da tangência para aproveitar o freio-motor.",
	"Dica: Pressione T durante a corrida para visualizar a telemetria em tempo real.",
]

var _target := ""
var _car_id := ""
var _car_info: Dictionary = {}
var _car_data: Dictionary = {}

var _layer: CanvasLayer
var _title_lbl: Label
var _car_lbl: Label
var _specs_lbl: Label
var _stage_lbl: Label
var _pct_lbl: Label
var _tip_lbl: Label
var _progress_bar: ProgressBar
var _accent_bar: ColorRect


func _ready() -> void:
	_target = Game.transition_target
	Game.transition_target = ""
	if _target == "":
		_target = "track" if _has_direct_track_args() else "garage"

	_car_id = Game.car_id
	_car_info = Game.get_car_info(_car_id)
	_car_data = Game.get_car_data(_car_id)

	_build_ui()
	_start_loading.call_deferred()


func _has_direct_track_args() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car=") or a.begins_with("--shot=") or a == "--auto":
			return true
	return false


func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.051, 0.063, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	_layer.add_child(bg)

	var accent := Color(_car_info.get("color", "#3b82f6"))

	_accent_bar = ColorRect.new()
	_accent_bar.color = accent
	_accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	_accent_bar.offset_bottom = 4
	_layer.add_child(_accent_bar)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.075, 0.088, 0.11, 0.94)
	panel_sb.border_color = Color(1, 1, 1, 0.10)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(14)
	panel_sb.content_margin_left = 40
	panel_sb.content_margin_right = 40
	panel_sb.content_margin_top = 34
	panel_sb.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.text = "AUTÓDROMO DE INTERLAGOS" if _target == "track" else "GARAGEM GT3"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 18)
	_title_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(_title_lbl)

	_car_lbl = Label.new()
	_car_lbl.text = String(_car_info.get("name", _car_id)).to_upper()
	_car_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_lbl.add_theme_font_size_override("font_size", 36)
	_car_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_car_lbl)

	_specs_lbl = Label.new()
	_specs_lbl.text = _format_car_specs()
	_specs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_specs_lbl.add_theme_font_size_override("font_size", 16)
	_specs_lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(_specs_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(spacer)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 18)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.08)
	bar_bg.set_corner_radius_all(9)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = accent
	bar_fill.set_corner_radius_all(9)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(_progress_bar)

	var status_row := HBoxContainer.new()
	vbox.add_child(status_row)

	_stage_lbl = Label.new()
	_stage_lbl.text = "Preparando carregamento..."
	_stage_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_lbl.add_theme_font_size_override("font_size", 16)
	_stage_lbl.add_theme_color_override("font_color", Color("#e2e8f0"))
	status_row.add_child(_stage_lbl)

	_pct_lbl = Label.new()
	_pct_lbl.text = "0%"
	_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_lbl.add_theme_font_size_override("font_size", 16)
	_pct_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	status_row.add_child(_pct_lbl)

	var footer_spacer := Control.new()
	footer_spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(footer_spacer)

	_tip_lbl = Label.new()
	_tip_lbl.text = TIPS[randi() % TIPS.size()]
	_tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_lbl.add_theme_font_size_override("font_size", 14)
	_tip_lbl.add_theme_color_override("font_color", Color("#64748b"))
	vbox.add_child(_tip_lbl)


func _format_car_specs() -> String:
	if _car_info.is_empty() or _car_data.is_empty():
		return "GT3 Time Attack"
	var p: Dictionary = _car_data.get("params", {})
	var eng: Dictionary = p.get("engine", {})
	var torque: Array = eng.get("torque", [])
	var cv := 0.0
	for pt in torque:
		cv = maxf(cv, float(pt[0]) * float(pt[1]) * TAU / 60.0 / 735.5)
	var gears: Array = p.get("gearbox", {}).get("ratios", [])
	return "Motor %s  ·  %d cv  ·  %d kg  ·  %d marchas" % [
		String(_car_info.get("layout", "")),
		roundi(cv / 5.0) * 5,
		int(p.get("mass", 0)),
		gears.size(),
	]


func _set_progress(pct: float, label: String) -> void:
	var clamped := clampf(pct, 0.0, 100.0)
	if _progress_bar:
		_progress_bar.value = maxf(_progress_bar.value, clamped)
	if _pct_lbl and _progress_bar:
		_pct_lbl.text = "%d%%" % roundi(_progress_bar.value)
	if _stage_lbl and label != "":
		_stage_lbl.text = label


func _step(pct: float, label: String) -> void:
	_set_progress(pct, label)
	await get_tree().process_frame


func _start_loading() -> void:
	await get_tree().process_frame
	if _target == "track":
		await _load_to_track()
	else:
		await _load_to_garage()


# ------------------------------------------------------------------ Garagem -> Pista (2.4)

func _load_to_track() -> void:
	var t0 := Time.get_ticks_msec()

	# 1. 0–45%: dispara threaded load de cenario.glb, main.tscn e carro (se não estiver em cache)
	#    enquanto lê os JSONs da pista fatiados entre frames.
	var stage1_paths: Array[String] = [CENARIO_GLB, TRACK_SCENE]
	var car_glb := ""
	if Game.get_cached_car_scene(_car_id) == null:
		car_glb = Game.get_car_glb_path(_car_id)
		if car_glb != "":
			stage1_paths.append(car_glb)

	_request_threaded_batch(stage1_paths)
	await _step(4.0, "Lendo traçado de Interlagos...")

	var track_json := JSON.parse_string(FileAccess.get_file_as_string("res://data/track/track.json")) as Dictionary
	await _step(10.0, "Construindo referencial da pista...")

	var track := Track.new("", track_json)
	track_json = {}
	await _step(15.0, "Lendo dados de vegetação...")

	var trees_data: Array = JSON.parse_string(FileAccess.get_file_as_string(TrackView.TREES))
	await _step(20.0, "Lendo dados dos arredores...")

	var towers_data: Array = JSON.parse_string(FileAccess.get_file_as_string(SurroundingsView.TOWERS))
	var horizon_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SurroundingsView.HORIZON))
	await _step(24.0, "Carregando cenário 3D da pista...")

	var stage1_res := await _await_threaded_batch(stage1_paths, 24.0, 45.0, "Carregando cenário 3D da pista...")
	var cenario_scene := stage1_res.get(CENARIO_GLB) as PackedScene
	var main_scene := stage1_res.get(TRACK_SCENE) as PackedScene
	if car_glb != "" and stage1_res.get(car_glb) is PackedScene:
		Game.cache_car_scene(_car_id, stage1_res[car_glb] as PackedScene)

	# 2. 45–65%: pré-carga assíncrona dos áudios do carro, céu HDR e texturas/shaders da pista
	var stage2_paths: Array[String] = []
	var audio_paths := CarAudio.get_preload_paths(_car_id)
	for p in audio_paths:
		stage2_paths.append(p)
	if ResourceLoader.exists(SKY_HDR):
		stage2_paths.append(SKY_HDR)
	for p in TRACK_PRELOAD_RESOURCES:
		if ResourceLoader.exists(p) and not p in stage2_paths:
			stage2_paths.append(p)

	_request_threaded_batch(stage2_paths)
	var stage2_res := await _await_threaded_batch(stage2_paths, 45.0, 65.0, "Pré-carregando áudios e céu...")

	var sky_tex := stage2_res.get(SKY_HDR) as Texture2D
	var audio_streams := {}
	for p in audio_paths:
		if stage2_res.has(p) and stage2_res[p] is AudioStreamWAV:
			audio_streams[p] = stage2_res[p]

	# 3. 65–90%: instanciação progressiva entre frames
	if main_scene == null:
		main_scene = ResourceLoader.load(TRACK_SCENE) as PackedScene
	var main_node := main_scene.instantiate()
	main_node.manual_setup = true
	get_tree().root.add_child(main_node)
	main_node.setup_step_track(track)
	await _step(68.0, "Preparando céu e iluminação...")

	main_node.setup_step_env(sky_tex)
	await _step(72.0, "Instanciando malhas da pista...")

	var tv := TrackView.new()
	tv.manual_setup = true
	main_node.add_child(tv)
	tv.build_scene(cenario_scene)
	await _step(78.0, "Plantando vegetação...")

	tv.build_trees(trees_data)
	trees_data = []
	await _step(82.0, "Construindo torres e horizonte...")

	tv.build_surroundings(towers_data, horizon_data)
	towers_data = []
	horizon_data = {}
	main_node.track_view = tv
	await _step(86.0, "Montando carro e sistema de áudio...")

	main_node.setup_step_car(audio_streams)
	await _step(90.0, "Configurando HUD e física...")

	main_node.setup_step_hud_and_quality()

	# 4. 90–100%: warmup de 2 frames para compilação de shaders antes de liberar a câmera no grid
	await _step(95.0, "Aquecendo shaders...")
	await _step(99.0, "Preparando grid de largada...")
	_set_progress(100.0, "Pronto!")

	main_node.finish_loading()
	get_tree().current_scene = main_node
	print("[Loading] Garagem -> Pista (%s) concluído em %d ms" % [_car_id, Time.get_ticks_msec() - t0])
	queue_free()


# ------------------------------------------------------------------ Pista -> Garagem (2.5)

func _load_to_garage() -> void:
	var t0 := Time.get_ticks_msec()

	# 1. 0–25%: aguarda 2 frames para a cena da pista descarregar e liberar memória sem travar a UI
	await _step(10.0, "Descarregando pista...")
	await _step(25.0, "Liberando recursos da sessão...")

	# 2. 25–65%: carrega garagem.tscn e garante o .glb do carro selecionado em cache
	var paths: Array[String] = [GARAGEM_SCENE]
	var car_glb := ""
	if Game.get_cached_car_scene(_car_id) == null:
		car_glb = Game.get_car_glb_path(_car_id)
		if car_glb != "":
			paths.append(car_glb)

	_request_threaded_batch(paths)
	var loaded := await _await_threaded_batch(paths, 25.0, 65.0, "Preparando garagem e carro...")
	var gar_scene := loaded.get(GARAGEM_SCENE) as PackedScene
	if car_glb != "" and loaded.get(car_glb) is PackedScene:
		Game.cache_car_scene(_car_id, loaded[car_glb] as PackedScene)

	# 3. 65–90%: instanciação progressiva do estúdio, UI e carro selecionado
	if gar_scene == null:
		gar_scene = ResourceLoader.load(GARAGEM_SCENE) as PackedScene
	var gar_node := gar_scene.instantiate()
	gar_node.manual_setup = true
	get_tree().root.add_child(gar_node)
	await _step(72.0, "Montando estúdio...")

	gar_node.setup_step_studio()
	await _step(80.0, "Construindo interface da garagem...")

	gar_node.setup_step_ui()
	await _step(88.0, "Posicionando carro no giratório...")

	gar_node.setup_step_car()

	# 4. 90–100%: warmup de 2 frames (ReflectionProbe + shaders do estúdio)
	await _step(94.0, "Aquecendo reflexos e shaders...")
	await _step(99.0, "Abrindo garagem...")
	_set_progress(100.0, "Pronto!")

	gar_node.finish_loading()
	get_tree().current_scene = gar_node
	print("[Loading] Pista -> Garagem (%s) concluído em %d ms" % [_car_id, Time.get_ticks_msec() - t0])
	queue_free()


# ------------------------------------------------------------------ Fila de carga assíncrona

func _request_threaded_batch(paths: Array[String]) -> void:
	for path in paths:
		if path == "" or not ResourceLoader.exists(path):
			continue
		ResourceLoader.load_threaded_request(path, "", true)


func _await_threaded_batch(paths: Array[String], p_start: float, p_end: float, label: String) -> Dictionary:
	var results := {}
	var pending: Array[String] = []
	for path in paths:
		if path != "" and ResourceLoader.exists(path):
			pending.append(path)
	var total := pending.size()
	if total == 0:
		_set_progress(p_end, label)
		return results

	var done := 0
	while pending.size() > 0:
		var in_prog_sum := 0.0
		var next_pending: Array[String] = []
		for path in pending:
			var prog: Array = []
			var st := ResourceLoader.load_threaded_get_status(path, prog)
			match st:
				ResourceLoader.THREAD_LOAD_LOADED:
					results[path] = ResourceLoader.load_threaded_get(path)
					done += 1
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					var p: float = clampf(float(prog[0]), 0.0, 1.0) if prog.size() > 0 else 0.0
					in_prog_sum += p
					next_pending.append(path)
				_:
					push_warning("[Loading] Fallback síncrono (%d): %s" % [st, path])
					results[path] = ResourceLoader.load(path)
					done += 1
		pending = next_pending
		var frac := (float(done) + in_prog_sum) / float(total)
		_set_progress(lerpf(p_start, p_end, frac), label)
		if pending.size() > 0:
			await get_tree().process_frame
	return results
