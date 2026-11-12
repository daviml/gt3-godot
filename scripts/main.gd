# Protótipo: Interlagos + os GT3 do jogo web em Godot 4, com a física e a pista do web.
# Controles (iguais ao web): setas/WASD ou controle (gatilhos + analógico). E/Shift ou RB/A sobe marcha,
# Q/Ctrl ou LB/X reduz. 1 = ABS, 2 = TC, G = câmbio automático. C/Y = câmera (perseguição, capô, longe).
# R ou Back = volta para a pista. P = piloto automático. Etapa 3: curva e suavização da direção do web,
# vibração no controle; no celular (ou -- --touch no PC) botões de toque, câmbio automático e ☰ = menu.
# F1 = alterna qualidade (Leve / Médio / Extremo). F12 = salva print. T = telemetria.
# Esc, Start ou ☰ / Voltar = menu de pausa (scripts/ui/pause_menu.gd): nick, qualidade, volume, assistências,
# garagem e sair. HUD estilo LMU em scripts/ui/hud.gd (etapa 10).
# Linha de comando (depois de --): --car=<id> escolhe o carro (data/cars.json), --auto liga o piloto,
# --nick=<nome> define o nick, --shot=<pasta> tira prints sozinho, --cam=<0..2> fixa a câmera nos prints.
# Cronometragem (etapa 4): R volta para o grid e zera a volta; N = nick (recordes por nick e carro).
extends Node3D

const SUN_U := 0.5947
const SUN_ELEV := deg_to_rad(48.0)

var track: Track
var track_view: TrackView
var car: Car
var car_view: CarView
var car_audio: CarAudio
var cam: Camera3D
var chase: ChaseCamera
var speed_blur: SpeedBlur
var env: Environment
var sun: DirectionalLight3D
var hud: Hud
var menu: PauseMenu
## preset gráfico atual (PauseMenu.QUALITIES): Leve / Médio / Extremo
var quality_name := ""
var volume := 0.6
## última entrada aplicada ao carro [direção, acelerador, freio, sobe, reduz], para o HUD
var last_inp := [0.0, 0.0, 0.0, false, false]

# entrada (etapa 3, scripts/input/): curva e suavização do web, vibração e botões de toque no celular
var input := InputReader.new()
var rumble := Rumble.new()
var touch: TouchControls
## ☰ ou voltar do Android: pausa (o menu da etapa 9 entra no lugar)
var paused := false
var timer: LapTimer
var nick := ""
## modo de condução atual ("sim" ou "arcade")
var mode := Game.mode
## melhores setores da sessão, de todas as voltas válidas (roxo no painel)
var best_sectors: Array[float] = []
## recordes exibidos no painel (remoto quando disponível, senão Records.top local)
var top_records: Array = []
var shared_records: Array = []
var has_shared_records := false
var remote_records: Records.RemoteClient
var _was_valid := true
var time := 0.0
var autopilot := false
var bot: RefCounted
var car_id := Game.car_id  # escolhido na garagem (scenes/garagem.tscn)
var car_data: Dictionary
var high := true
var manual_setup := false
var _init_cli_args: PackedStringArray
# referência do iRacing de cada carro que tem uma: o piloto automático segue a volta real
const REFS := {"porsche-992-gt3r": "interlagos-porsche", "audi-r8-lms-gt3": "interlagos-r8", "ford-mustang-gt3": "interlagos-mustang"}



func _ready() -> void:
	_init_args()
	if manual_setup:
		set_physics_process(false)
		set_process(false)
		set_process_unhandled_input(false)
		return
	track = Track.new("res://data/track/track.json")
	_build_env()
	# pista e arredores exportados do jogo web (etapa 7): scripts/track/track_view.gd
	track_view = TrackView.new()
	add_child(track_view)
	_build_car()
	setup_step_hud_and_quality()
	_apply_cli_post_setup()


func _init_args() -> void:
	mode = Game.mode
	_init_cli_args = OS.get_cmdline_user_args()
	var is_mobile_init := OS.has_feature("mobile") or "--mobile" in _init_cli_args
	Engine.max_physics_steps_per_frame = 2 if is_mobile_init else 4
	autopilot = "--auto" in _init_cli_args
	for a in _init_cli_args:
		if a.begins_with("--shot="):
			shot_dir = a.substr(7)
			autopilot = true
		if a.begins_with("--car="):
			car_id = a.substr(6)
		if a.begins_with("--nick="):
			nick = a.substr(7).strip_edges()
			if nick != "":
				Records.save_nick(nick)
	if nick == "":
		nick = Records.load_nick()
	if nick == "":
		nick = "Piloto"
	# --touch mostra os botões de toque no PC (o mouse vira dedo)
	input.touch = OS.has_feature("mobile") or "--touch" in _init_cli_args


func setup_step_track(pre_track: Track) -> void:
	track = pre_track if pre_track != null else Track.new("res://data/track/track.json")


func setup_step_env(sky_tex: Texture2D = null) -> void:
	_build_env(sky_tex)


func setup_step_car(preloaded_streams: Dictionary = {}) -> void:
	_build_car(preloaded_streams, true)


func setup_step_hud_and_quality() -> void:
	timer = LapTimer.new(track)
	timer.on_lap = _on_lap
	remote_records = Records.RemoteClient.new()
	add_child(remote_records)
	_build_hud()
	# assistências e volume guardados no menu de pausa (user://jogo.cfg)
	for key in ["abs", "tc", "auto"]:
		car.assists[key] = bool(Game.get_setting("assistencias", key, car.assists[key]))
	_set_volume(float(Game.get_setting("audio", "volume", 0.6)))
	# no celular e no piloto automático o câmbio é automático, como no web
	if autopilot or input.touch:
		car.assists.auto = true
	_apply_mode(mode, false)
	_spawn()
	bot = _create_bot()
	# No celular ou com flag --mobile, já inicia configurado para Mobile; o menu de pausa guarda a escolha
	_apply_quality(Game.get_quality_name())
	_update_car_view(1.0)
	chase.snap()


func _create_bot():
	if REFS.has(car_id):
		# malha de giro: segue o traçado real do iRacing sem passar da zebra (Porsche 1:35,9 e Mustang 1:33,6 válidas).
		# A volta do R8 passa 2,3 m além da zebra na Descida do Lago: ele continua com o traçado contido.
		var opts := {"yaw_p": 2.0, "hold_line": 0.02}
		if car_id == "audi-r8-lms-gt3":
			opts = {"yaw_p": 2.0, "line_gain": 0.4, "hold_line": 0.02, "edge": [-0.3, 0.5]}
		return RefBot.new(track, car, RefBot.load_ref(REFS[car_id]), opts)
	return Bot.new(track, car)


func _apply_cli_post_setup() -> void:
	for a in _init_cli_args:
		if a.begins_with("--cam="):
			chase.mode = clampi(int(a.substr(6)), 0, 2)
			fixed_cam = true
		if a == "--menu":
			# teste: abre o menu de pausa já na largada (os prints usam o tempo real)
			_set_paused.call_deferred(true)


func finish_loading() -> void:
	set_physics_process(true)
	set_process(true)
	set_process_unhandled_input(true)
	if car_audio:
		car_audio.set_paused(paused)
	chase.snap()
	_apply_cli_post_setup()


# modo de teste: --shot=<pasta> pilota sozinho, salva prints em alguns tempos e sai
var shot_dir := ""
## --cam=<n>: prints na câmera escolhida (0 perseguição, 1 capô, 2 longe) em vez da vitrine
var fixed_cam := false
var shot_times := [3.0, 9.0, 16.0, 24.0, 33.0, 45.0]
var shot_k := 0
var real_time := 0.0

func _shot_tick(dt: float) -> void:
	real_time += dt
	if shot_k < shot_times.size() and (real_time if paused else time) >= shot_times[shot_k]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [shot_dir, shot_k])
		print("shot %d t=%.1f v=%.0f km/h idx=%d fps=%d" % [shot_k, time, car.vel.length() * 3.6, car.hint, Engine.get_frames_per_second()])
		shot_k += 1
		if shot_k == shot_times.size():
			get_tree().quit()


# ------------------------------------------------------------------ ambiente

func _build_env(sky_tex: Texture2D = null) -> void:
	var phi := (SUN_U - 0.5) * TAU
	var sun_dir := Vector3(cos(phi) * cos(SUN_ELEV), sin(SUN_ELEV), sin(phi) * cos(SUN_ELEV))

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	if sky_tex == null:
		sky_tex = load("res://assets/sky/ceu_2k.hdr")
	sky_mat.set_shader_parameter("pano", sky_tex)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var q_lvl := Game.get_quality_level()
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if q_lvl == 0 else (Sky.RADIANCE_SIZE_128 if q_lvl == 1 else Sky.RADIANCE_SIZE_256)

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	if not Game.is_compatibility_renderer():
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
	# Sol LMU: mais quente e brilhante (0xffe6c2 = Color(1.0, 0.90, 0.76))
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.light_energy = 2.8
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.50
	sun.light_angular_distance = 0.5
	add_child(sun)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP)


# ------------------------------------------------------------------ carro

func _build_car(preloaded_streams: Dictionary = {}, start_paused := false) -> void:
	if not FileAccess.file_exists("res://data/cars/%s.json" % car_id):
		push_warning("carro desconhecido: %s" % car_id)
		car_id = "porsche-992-gt3r"
	# visual do carro (modelo, materiais, rodas com pinça parada e desfoque): scripts/render/car_view.gd
	var q_lvl := Game.get_quality_level()
	car_view = CarView.new(car_id, q_lvl >= 2, q_lvl == 0)
	add_child(car_view)
	car_data = car_view.data
	car = Car.new(track, car_data.params)
	# som do carro (etapa 11): motor engine-sim, turbo, pneu, superfícies e vento
	car_audio = CarAudio.new(car, car_id, preloaded_streams)
	if start_paused:
		car_audio.is_audio_paused = true
	add_child(car_audio)


func _update_car_view(frac := 1.0) -> void:
	car_view.update_from(car, frac)


# ------------------------------------------------------------------ HUD e menu (etapa 10)

func _build_hud() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 6000.0
	add_child(cam)
	chase = ChaseCamera.new(cam, car)
	# desfoque de velocidade no layer 1 (etapa 8 / PLANO-visual etapa 1)
	speed_blur = SpeedBlur.new()
	add_child(speed_blur)
	# HUD e controles de toque no layer 2 (ficam por cima do desfoque)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	# HUD estilo LMU: mostrador, pneus, tempos, melhores tempos, mapa, FPS (scripts/ui/hud.gd)
	hud = Hud.new(car, timer, track, car_id, input.touch)
	hud.arcade = (mode == "arcade")
	hud.best_sectors = best_sectors
	hud.nick = nick
	hud.menu_requested.connect(_toggle_pause)
	hud.camera_requested.connect(func():
		chase.next()
		_toast("Câmera: " + chase.mode_name())
	)
	hud.reset_requested.connect(func():
		if not autopilot:
			_spawn()
			chase.snap()
	)
	layer.add_child(hud)
	var touch_mode_saved := String(Game.get_setting("controles", "modo_toque", "padrao"))
	if not touch_mode_saved in TouchControls.MODES:
		touch_mode_saved = "padrao"
	input.touch_mode = touch_mode_saved
	input.grip_scale = car.grip_scale
	if input.touch:
		touch = TouchControls.new()
		touch.show_menu_btn = false
		touch.mode = touch_mode_saved
		touch.manual_hide = Game.is_hide_touch_controls()
		touch.keys = input.touch_keys
		touch.axes = input.touch_axes
		touch.menu_pressed.connect(_toggle_pause)
		touch.recenter_requested.connect(func(): _toast("Volante calibrado"))
		layer.add_child(touch)
		car.assists.brake_reverse = true
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_sync_touch_visibility()
	# menu de pausa (scripts/ui/pause_menu.gd): CanvasLayer própria por cima de tudo
	menu = PauseMenu.new()
	menu.resumed.connect(func(): _set_paused(false))
	menu.garage.connect(_to_garage)
	menu.quit.connect(func(): get_tree().quit())
	menu.restart_requested.connect(func():
		_set_paused(false)
		_spawn()
		if chase:
			chase.snap()
	)
	menu.car_selected.connect(_switch_car)
	menu.nick_changed.connect(_on_nick)
	menu.mode_changed.connect(func(m: String):
		_apply_mode(m, not autopilot)
		if autopilot and timer:
			timer.reset()
		_toast("Modo: " + String(Game.MODE_NAMES.get(m, m)))
	)
	menu.quality_changed.connect(_apply_quality)
	menu.volume_changed.connect(_set_volume)
	menu.assist_changed.connect(func(key: String, on: bool): car.assists[key] = on)
	menu.hud_gauge_changed.connect(func(style: String): hud.set_gauge_style(style))
	menu.touch_mode_changed.connect(func(tm: String):
		input.touch_mode = tm
		if touch:
			touch.mode = tm
		_toast("Controles: " + TouchControls.MODE_NAMES.get(tm, tm))
	)
	menu.hide_touch_changed.connect(func(hidden: bool):
		if touch:
			touch.manual_hide = hidden
		_sync_touch_visibility()
	)
	menu.recenter_tilt.connect(func():
		if touch:
			touch.recenter_tilt()
		_toast("Volante calibrado")
	)
	add_child(menu)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if quality_name == "Mínimo":
		var vp := get_viewport()
		if vp:
			vp.scaling_3d_scale = Game.get_minimal_3d_scale(vp)


func _fmt(t: float) -> String:
	return LapTimer.format_time(t)


# ------------------------------------------------------------------ cronometragem (etapa 4)

## Largada na reta dos boxes, 120 m antes da linha, com a volta zerada (como o spawn do web).
func _spawn() -> void:
	car.reset_at(track.index_at(-120.0))
	timer.reset()
	_was_valid = true
	if car_audio:
		car_audio.reset()


func _refresh_records() -> void:
	var local_all := Records.load_all(mode)
	if has_shared_records and not shared_records.is_empty():
		top_records = Records.merge_records(shared_records, local_all).slice(0, 8)
	else:
		top_records = Records.top(8, mode)
	if hud:
		hud.records = top_records


func _apply_mode(m: String, reset_car := true) -> void:
	Game.set_mode(m)
	mode = Game.mode
	car.grip_scale = Game.get_grip_scale()
	input.grip_scale = car.grip_scale
	if hud:
		hud.arcade = (mode == "arcade")
	best_sectors = []
	if hud:
		hud.best_sectors = best_sectors
	shared_records = []
	has_shared_records = false
	_refresh_records()
	if remote_records:
		remote_records.fetch_ranking(mode, _on_remote_ranking)
	if reset_car:
		_spawn()
		if chase:
			chase.snap()


func _on_remote_ranking(ok: bool, voltas: Array, r_mode: String) -> void:
	if not ok or r_mode != mode:
		return
	shared_records = voltas
	has_shared_records = true
	_refresh_records()
	if menu:
		menu.set_shared_records(r_mode, voltas)


func _on_remote_lap_posted(ok: bool, is_record: bool, voltas: Array, r_mode: String) -> void:
	if not ok or r_mode != mode:
		return
	shared_records = voltas
	has_shared_records = true
	_refresh_records()
	if menu:
		menu.set_shared_records(r_mode, voltas)
	if is_record and not voltas.is_empty():
		var best_rec: Dictionary = voltas[0]
		if String(best_rec.get("nick", "")) == nick.strip_edges() and String(best_rec.get("carId", "")) == car_id:
			_toast("Novo recorde geral (%s): %s" % [Game.MODE_NAMES.get(mode, mode), _fmt(float(best_rec.get("time", 0.0)))])


## Volta fechada por você (não pelo piloto automático): vira recorde se for a melhor desse nick nesse carro.
func _on_lap(lap: LapTimer.Lap) -> void:
	var lap_mode := mode
	if lap.valid:
		for i in 3:
			if i >= best_sectors.size():
				best_sectors.append(lap.sectors[i])
			else:
				best_sectors[i] = minf(best_sectors[i], lap.sectors[i])
	if autopilot:
		return
	var clean_nick := nick.strip_edges()
	if clean_nick == "":
		clean_nick = Records.load_nick()
		if clean_nick == "":
			clean_nick = "Piloto"
		nick = clean_nick
		Records.save_nick(nick)
		if hud:
			hud.nick = nick
	var saved := Records.save_lap(clean_nick, car_id, lap, lap_mode)
	if saved:
		_toast("Recorde pessoal: " + _fmt(lap.time))
	elif not lap.valid:
		_toast("Volta inválida (4 rodas fora)")
	_refresh_records()
	if lap.valid and clean_nick != "" and remote_records:
		remote_records.post_lap(clean_nick, car_id, lap, lap_mode, _on_remote_lap_posted)


func _on_nick(t: String) -> void:
	nick = t.strip_edges()
	if nick == "":
		nick = "Piloto"
	hud.nick = nick
	Records.save_nick(nick)
	_refresh_records()


# ------------------------------------------------------------------ laço

func _input_axes(dt: float) -> Array:
	if touch and input.touch_mode == "inclinar":
		touch.step_tilt(dt)
	input.grip_scale = car.grip_scale
	input.update(dt, car.speed())
	# Back/Select do controle = R (volta para o grid)
	if input.reset:
		_spawn()
		chase.snap()
	if autopilot:
		var b: Array = bot.drive()
		return [b[0], b[1], b[2], false, false]
	return [input.steer, input.throttle, input.brake, input.shift_up, input.shift_down]


func _physics_process(dt: float) -> void:
	if paused:
		return
	var inp := _input_axes(dt)
	last_inp = inp
	car.step(dt, inp[0], inp[1], inp[2], inp[3], inp[4])
	time += dt
	timer.update(dt, car)
	if timer.current >= 0.0:
		if _was_valid and not timer.valid:
			_toast("Volta inválida (4 rodas fora)")
		_was_valid = timer.valid
	else:
		_was_valid = true
	if car.pos.y < track.lcenter.y - 20.0:
		_spawn()
		chase.snap()


func _process(dt: float) -> void:
	var frac := Engine.get_physics_interpolation_fraction()
	_update_car_view(frac)
	if not paused:
		rumble.update(car, dt)
		if car_audio:
			car_audio.update(dt)
	if shot_dir != "":
		_shot_tick(dt)
	chase.update(dt, frac)
	if not paused and speed_blur:
		speed_blur.update(cam, car, chase.mode, dt)
	if shot_dir != "" and shot_k % 3 == 0 and not fixed_cam:
		# prints de vitrine: 3/4 de frente, perto do carro
		var v_pos := car.visual_pos(frac)
		var b := car.visual_basis(frac)
		var r := b.x
		var fwd := -b.z
		cam.global_position = v_pos + fwd * 5.2 + r * 3.2 + Vector3.UP * 0.6
		cam.look_at(v_pos + Vector3.UP * 0.1, Vector3.UP)

	hud.records = top_records
	hud.autopilot = autopilot
	hud.quality = quality_name
	hud.set_view(chase.mode_name())
	hud.update(dt, last_inp[1], last_inp[2])
	if paused:
		menu.update_fps(hud.fps)


func _unhandled_input(e: InputEvent) -> void:
	var key: bool = e is InputEventKey and e.pressed and not e.echo
	var pad: bool = e is InputEventJoypadButton and e.pressed
	# menu aberto: Esc volta para a Home antes de retomar; Start fecha direto
	if paused:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit:
			if key and e.keycode == KEY_ESCAPE:
				focus_owner.release_focus()
				get_viewport().set_input_as_handled()
			return
		if key and e.keycode == KEY_ESCAPE:
			if menu == null or not menu.handle_back():
				_set_paused(false)
			get_viewport().set_input_as_handled()
		elif pad and e.button_index == JOY_BUTTON_START:
			_set_paused(false)
			get_viewport().set_input_as_handled()
		return
	if key:
		match e.keycode:
			KEY_N:
				_set_paused(true, true)
			KEY_R:
				_spawn()
				chase.snap()
			KEY_C:
				chase.next()
				_toast("Câmera: " + chase.mode_name())
			KEY_P:
				autopilot = not autopilot
				if autopilot:
					car.assists.auto = true
			KEY_T:
				hud.telemetry = not hud.telemetry
			KEY_1:
				car.assists.abs = not car.assists.abs
				_toast("ABS " + ("ligado" if car.assists.abs else "desligado"))
			KEY_2:
				car.assists.tc = not car.assists.tc
				_toast("Controle de tração " + ("ligado" if car.assists.tc else "desligado"))
			KEY_G:
				car.assists.auto = not car.assists.auto
				_toast("Câmbio " + ("automático" if car.assists.auto else "manual"))
			KEY_F1:
				var q: Array = PauseMenu.QUALITIES
				_apply_quality(q[(q.find(quality_name) + 1) % q.size()])
				_toast("Gráficos: " + quality_name)
			KEY_F12:
				_screenshot()
			KEY_ESCAPE:
				_set_paused(true)
	if pad:
		# câmera também no controle (Y, como no web); Start abre o menu
		if e.button_index == JOY_BUTTON_Y:
			chase.next()
			_toast("Câmera: " + chase.mode_name())
		elif e.button_index == JOY_BUTTON_START:
			_set_paused(true)


func _notification(what: int) -> void:
	# botão voltar do Android: volta para a Home dentro do menu ou abre/fecha o menu
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if paused and menu and menu.handle_back():
			return
		_toggle_pause()


func _toggle_pause() -> void:
	_set_paused(not paused)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_sync_touch_visibility()


func _sync_touch_visibility() -> void:
	if touch:
		touch.sync_visibility(not paused)
		input.touch_hidden = touch.is_effectively_hidden()
	else:
		input.touch_hidden = Game.is_hide_touch_controls() or Game.has_gamepad_connected()


## Troca o carro ao vivo diretamente a partir do Menu de Pausa sem sair da pista.
func _switch_car(new_id: String) -> void:
	if new_id == "" or new_id == car_id:
		return
	if not FileAccess.file_exists("res://data/cars/%s.json" % new_id):
		push_warning("carro desconhecido: %s" % new_id)
		return
	var prev_assists := car.assists.duplicate()
	var prev_grip := car.grip_scale
	car_id = new_id
	Game.save_car(car_id)

	if car_view:
		car_view.queue_free()
	var q_lvl := Game.get_quality_level()
	car_view = CarView.new(car_id, q_lvl >= 2, q_lvl == 0)
	add_child(car_view)
	car_data = car_view.data

	car = Car.new(track, car_data.params)
	car.assists = prev_assists
	car.grip_scale = prev_grip

	if car_audio:
		car_audio.queue_free()
	car_audio = CarAudio.new(car, car_id)
	car_audio.set_paused(paused)
	add_child(car_audio)

	if chase:
		chase.car = car
	if hud:
		hud.car = car
		var c_info := Game.get_car_info(car_id)
		if c_info.has("color"):
			hud.car_color = Color(String(c_info.color))
		hud.dash = (car_id in Hud.DASH_CARS)
		hud.dash_on = hud.dash
	bot = _create_bot()
	_spawn()
	_update_car_view(1.0)
	if chase:
		chase.snap()
	var cname := String(Game.get_car_info(car_id).get("name", car_id))
	_toast("Carro: " + cname)


## pausa = menu aberto (o carro para, os botões de toque somem)
func _set_paused(on: bool, focus_nick := false) -> void:
	if on == paused and not (on and focus_nick):
		return
	paused = on
	if hud:
		hud.set_menu_open(on)
		hud.visible = not on
	_sync_touch_visibility()
	if speed_blur and on:
		speed_blur.rect.visible = false
	if car_audio:
		car_audio.set_paused(on)
	if on:
		menu.open(nick, quality_name, volume, car.assists, input.touch_mode, input.touch, focus_nick, mode, hud.gauge_style if hud else "barra", car_id)
		if has_shared_records and not shared_records.is_empty():
			menu.set_shared_records(mode, shared_records)
	elif menu.is_open:
		menu.close()


func _to_garage() -> void:
	paused = false
	if car_audio:
		car_audio.set_paused(true)
	Game.transition_target = "garage"
	get_tree().change_scene_to_file("res://scenes/loading.tscn")


func _toast(t: String) -> void:
	hud.toast(t)


func _set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)


const PRESET_INDEX := {"Mínimo": 0, "Leve": 1, "Médio": 2, "Extremo": 3}


## Preset gráfico pelo nome do menu (Mínimo / Leve / Médio / Extremo).
func _apply_quality(name: String) -> void:
	quality_name = name
	var is_mobile := OS.has_feature("mobile")
	var level: int = PRESET_INDEX.get(name, 1 if is_mobile else 3)
	_set_quality(level)


## Ajusta presets de qualidade:
## 0 = Mínimo (FSR 0.70x, sem sombras, máx FPS mobile),
## 1 = Leve (FSR 0.80x, sombras leves, sem glow - recomendado S22 60 FPS),
## 2 = Médio (1.0x nativo, sombras 2 cortes, SSAO leve),
## 3 = Extremo (PC com GPU: SSAO, SSIL, SSR, sombras 4 cortes).
func _set_quality(level: int) -> void:
	high = level > 1
	var vp := get_viewport()
	var is_mobile := Game.is_mobile_platform()
	var is_compat := Game.is_compatibility_renderer()

	# 1. Resolução interna, upscaling e LOD de malhas
	# No Mínimo, usamos Bilinear nativo limitado a <=720p efetivo em telas HiDPI/4K (e 0.65x em 1080p)
	# No Leve, 75% Bilinear no mobile/Compatibility ou FSR no desktop
	vp.mesh_lod_threshold = 6.0 if level == 0 else (3.0 if level == 1 else 1.0)
	if level == 0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = Game.get_minimal_3d_scale(vp)
		vp.msaa_3d = Viewport.MSAA_DISABLED
	elif level == 1:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if (is_mobile or is_compat) else Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 0.75
		vp.fsr_sharpness = 0.2
		vp.msaa_3d = Viewport.MSAA_DISABLED
	elif level == 2:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_4X

	# 2. Ambiente, céu e efeitos pós-processamento
	if env:
		if env.sky:
			env.sky.radiance_size = Sky.RADIANCE_SIZE_64 if level == 0 else (Sky.RADIANCE_SIZE_128 if level == 1 else Sky.RADIANCE_SIZE_256)
		env.ssao_enabled = (level >= 2) and not is_compat
		if env.ssao_enabled:
			env.ssao_radius = 1.0 if level == 2 else 1.2
			env.ssao_intensity = 1.0 if level == 2 else 1.6

		env.ssil_enabled = (level == 3) and not is_compat
		env.ssr_enabled = (level == 3) and not is_compat
		if env.ssr_enabled:
			env.ssr_max_steps = 48

		# Glow desligado em Mínimo e Leve (crítico para taxa de quadros e temperatura no celular)
		env.glow_enabled = level >= 2
		if env.glow_enabled:
			env.glow_intensity = 0.3 if level == 2 else 0.35
			env.glow_bloom = 0.03 if level == 2 else 0.04

	# 3. Sol e sombras direcionais
	if sun:
		if level == 0:
			# Mínimo: sem sombras de sol, apenas o blob shadow sob o carro
			sun.shadow_enabled = false
		elif level == 1:
			# Leve: sombra direcional ortogonal curta (50 m)
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 50.0
		elif level == 2:
			# Médio: sombra em 2 cortes
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 110.0
			sun.directional_shadow_split_1 = 0.15
		else:
			# Extremo: sombra em 4 cortes
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 180.0
			sun.directional_shadow_split_1 = 0.08
			sun.directional_shadow_split_2 = 0.22
			sun.directional_shadow_split_3 = 0.50

	# 4. Far plane da câmera (economiza precisão de Z e culling de geometria)
	if cam:
		if level == 0:
			cam.far = 1200.0
		elif level == 1:
			cam.far = 1600.0
		elif level == 2:
			cam.far = 4000.0
		else:
			cam.far = 6000.0

	# 5. Arredores (corte de torcida, torres e árvores pelo orçamento)
	if track_view:
		track_view.set_detail(level)

	# 6. Desfoque radial de velocidade (apenas em Médio e Extremo)
	if speed_blur:
		speed_blur.enabled = level >= 2
		speed_blur.max_strength = 0.8 if level == 2 else 1.0

	# 7. Desfoque das rodas e simplificação de materiais do carro
	if car_view:
		car_view.blur_enabled = level >= 2
		car_view.simple_materials = level == 0

	# 8. Física e HUD por orçamento (Mínimo limita sub-passos a 4 / 240 Hz mesmo no Desktop)
	if car:
		car.max_sub_steps = 4 if (level == 0 or is_mobile) else 8
	Engine.max_physics_steps_per_frame = 2 if (level == 0 or is_mobile) else 4
	if hud:
		hud.quality_level = level


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var path := "%s/godot-gt3-%d.png" % [dir, Time.get_unix_time_from_system()]
	img.save_png(path)
	print("print: ", path)
