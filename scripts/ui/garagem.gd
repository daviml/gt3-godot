# Garagem: escolhe o carro (o galeria.html do web virou cena). O carro gira num estúdio com luz de softbox,
# piso que reflete e o reflexo das faixas de luz na pintura (sonda de reflexo).
# Controles: ◀ ▶ (setas/A D, direcional ou LB/RB no controle, botões na tela) trocam o carro; Enter/Espaço ou
# A no controle (ou o botão PILOTAR) vai para a pista; arrastar o mouse/dedo gira a câmera, roda do mouse
# aproxima; Esc sai do jogo.
# Linha de comando (depois de --): --car=<id>, --shot=<pasta> e --auto pulam a garagem e abrem a pista direto.
# --vitrine=<pasta> tira, de cada carro, um print 3/4 e três da roda dianteira esquerda (parada, girada 35° e
# girando rápido, com desfoque) e sai: confere materiais, pinça parada e desfoque.
extends Node3D

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
var studio: CarStudioView
var view: CarView
var pivot: Node3D
var cam: Camera3D
var ring_mat: StandardMaterial3D
var studio_env: Environment
var key_light: DirectionalLight3D
var studio_quality_level := 3

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


func _build_studio() -> void:
	studio = CarStudioView.new()
	studio.set_process(false)
	add_child(studio)
	var initial_id := String(cars[idx].id) if not cars.is_empty() else Game.car_id
	studio.setup(cars, initial_id, shot_dir != "", true)
	studio.loading_changed.connect(_set_loading_indicator)
	studio.car_mounted.connect(func(_cid: String):
		view = studio.view
	)
	pivot = studio.pivot
	cam = studio.cam
	ring_mat = studio.ring_mat
	studio_env = studio.studio_env
	key_light = studio.key_light
	studio_quality_level = studio.studio_quality_level


func _apply_studio_quality() -> void:
	if studio:
		studio.apply_studio_quality()
		studio_quality_level = studio.studio_quality_level


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

	name_lbl = _label("", 20, Color.WHITE)
	name_lbl.visible = false
	root.add_child(name_lbl)

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


func _show(i: int, sync := false) -> void:
	if cars.is_empty():
		return
	idx = posmod(i, cars.size())
	var c: Dictionary = cars[idx]
	var car_id: String = c.id
	if name_lbl:
		name_lbl.text = c.name
	if lmu_menu:
		lmu_menu.set_selected_car(car_id, false)
	if studio:
		studio._nav_dir = _nav_dir
		studio.show_index(idx, sync)
		view = studio.view


func _set_loading_indicator(on: bool, accent := Color.WHITE) -> void:
	if loading_overlay:
		loading_overlay.visible = on
	if loading_spinner and on:
		loading_spinner.arc_color = accent.lightened(0.25)
		loading_spinner.queue_redraw()


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


func _process(dt: float) -> void:
	if studio:
		var framing := shot_dir == "" and lmu_menu != null and lmu_menu.visible and lmu_menu.active_view == "cars"
		studio.set_cars_framing(framing, get_viewport().get_visible_rect().size)
		studio.update_camera(dt, shot_dir == "")
		studio._process_async_loading(dt)
		view = studio.view
	if loading_overlay and loading_overlay.visible and loading_spinner:
		loading_spinner.angle = fmod(loading_spinner.angle + dt * 6.0, TAU)
		loading_spinner.queue_redraw()


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
	elif cur_view == "cars" and studio:
		studio.handle_drag_event(e)


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
