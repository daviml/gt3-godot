# Protótipo: Interlagos + os GT3 do jogo web em Godot 4, com a física e a pista do web.
# Controles (iguais ao web): setas/WASD ou controle (gatilhos + analógico). E/Shift ou RB/A sobe marcha,
# Q/Ctrl ou LB/X reduz. 1 = ABS, 2 = TC, G = câmbio automático. C/Y = câmera (perseguição, capô, longe).
# R ou Back = volta para a pista. P = piloto automático. Etapa 3: curva e suavização da direção do web,
# vibração no controle; no celular (ou -- --touch no PC) botões de toque, câmbio automático e ☰ = pausa.
# F1 = alterna qualidade (Alto/Celular). F12 = salva print. Esc = sai.
# Linha de comando (depois de --): --car=<id> escolhe o carro (data/cars.json), --auto liga o piloto,
# --nick=<nome> define o nick, --shot=<pasta> tira prints sozinho.
# Cronometragem (etapa 4): R volta para o grid e zera a volta; N = nick (recordes por nick e carro).
extends Node3D

const SUN_U := 0.5947
const SUN_ELEV := deg_to_rad(48.0)

var track: Track
var car: Car
var car_view: CarView
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var hud: Label
var hud_big: Label
var panel: RichTextLabel
var nick_edit: LineEdit

# entrada (etapa 3, scripts/input/): curva e suavização do web, vibração e botões de toque no celular
var input := InputReader.new()
var rumble := Rumble.new()
var touch: TouchControls
## ☰ ou voltar do Android: pausa (o menu da etapa 9 entra no lugar)
var paused := false
var chase: ChaseCamera
var timer: LapTimer
var nick := ""
## melhores setores da sessão, de todas as voltas válidas (roxo no painel)
var best_sectors: Array[float] = []
## recordes deste PC (Records.top), atualizados a cada volta
var top_records: Array = []
var time := 0.0
var autopilot := false
var bot: RefCounted
var car_id := Game.car_id  # escolhido na garagem (scenes/garagem.tscn)
var car_data: Dictionary
var high := true
var toast := ""
var toast_t := 0.0
# referência do iRacing de cada carro que tem uma: o piloto automático segue a volta real
const REFS := {"porsche-992-gt3r": "interlagos-porsche", "audi-r8-lms-gt3": "interlagos-r8", "ford-mustang-gt3": "interlagos-mustang"}



func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autopilot = "--auto" in args
	for a in args:
		if a.begins_with("--shot="):
			shot_dir = a.substr(7)
			autopilot = true
		if a.begins_with("--car="):
			car_id = a.substr(6)
		if a.begins_with("--nick="):
			nick = a.substr(7)
			Records.save_nick(nick)
	if nick == "":
		nick = Records.load_nick()
	# --touch mostra os botões de toque no PC (o mouse vira dedo)
	input.touch = OS.has_feature("mobile") or "--touch" in args
	track = Track.new("res://data/track/track.json")
	_build_env()
	# pista e arredores exportados do jogo web (etapa 7): scripts/track/track_view.gd
	add_child(TrackView.new())
	_build_car()
	_build_hud()
	timer = LapTimer.new(track)
	timer.on_lap = _on_lap
	top_records = Records.top(8)
	_spawn()
	if REFS.has(car_id):
		# malha de giro: segue o traçado real do iRacing sem passar da zebra (Porsche 1:35,9 e Mustang 1:33,6 válidas).
		# A volta do R8 passa 2,3 m além da zebra na Descida do Lago: ele continua com o traçado contido.
		var opts := {"yaw_p": 2.0, "hold_line": 0.02}
		if car_id == "audi-r8-lms-gt3":
			opts = {"yaw_p": 2.0, "line_gain": 0.4, "hold_line": 0.02, "edge": [-0.3, 0.5]}
		bot = RefBot.new(track, car, RefBot.load_ref(REFS[car_id]), opts)
	else:
		bot = Bot.new(track, car)
	# No celular ou com flag --mobile, já inicia configurado para Mobile
	var is_mobile := OS.has_feature("mobile") or "--mobile" in args
	_set_quality(not is_mobile)


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
	var pano := Image.load_from_file("res://assets/sky/ceu_2k.hdr")  # importer "keep": o .hdr vai cru no executável
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

func _build_car() -> void:
	if not FileAccess.file_exists("res://data/cars/%s.json" % car_id):
		push_warning("carro desconhecido: %s" % car_id)
		car_id = "porsche-992-gt3r"
	# visual do carro (modelo, materiais, rodas com pinça parada e desfoque): scripts/render/car_view.gd
	car_view = CarView.new(car_id)
	add_child(car_view)
	car_data = car_view.data
	car = Car.new(track, car_data.params)


func _update_car_view() -> void:
	car_view.update_from(car)


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.1
	cam.far = 6000.0
	add_child(cam)
	chase = ChaseCamera.new(cam, car)
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
	_build_timing_hud(layer)
	if input.touch:
		touch = TouchControls.new()
		touch.keys = input.touch_keys
		touch.menu_pressed.connect(_toggle_pause)
		layer.add_child(touch)


func _fmt(t: float) -> String:
	return LapTimer.format_time(t)


# ------------------------------------------------------------------ cronometragem (etapa 4)

func _build_timing_hud(layer: CanvasLayer) -> void:
	# painel de tempos (canto superior direito); o painel LMU completo vem na etapa 9
	panel = RichTextLabel.new()
	panel.bbcode_enabled = true
	panel.fit_content = true
	panel.scroll_active = false
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -420
	panel.offset_right = -24
	panel.offset_top = 18
	panel.add_theme_font_size_override("normal_font_size", 22)
	panel.add_theme_font_size_override("bold_font_size", 22)
	panel.add_theme_color_override("font_outline_color", Color.BLACK)
	panel.add_theme_constant_override("outline_size", 6)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	# nick (tecla N): os recordes ficam guardados por nick e carro
	nick_edit = LineEdit.new()
	nick_edit.placeholder_text = "Seu nick (Enter grava, Esc cancela)"
	nick_edit.max_length = 16
	nick_edit.anchor_left = 0.5
	nick_edit.anchor_right = 0.5
	nick_edit.anchor_top = 0.4
	nick_edit.anchor_bottom = 0.4
	nick_edit.offset_left = -200
	nick_edit.offset_right = 200
	nick_edit.add_theme_font_size_override("font_size", 26)
	nick_edit.visible = false
	nick_edit.text_submitted.connect(_on_nick)
	layer.add_child(nick_edit)


## Largada na reta dos boxes, 120 m antes da linha, com a volta zerada (como o spawn do web).
func _spawn() -> void:
	car.reset_at(track.index_at(-120.0))
	timer.reset()


## Volta fechada por você (não pelo piloto automático): vira recorde se for a melhor desse nick nesse carro.
func _on_lap(lap: LapTimer.Lap) -> void:
	if lap.valid:
		for i in 3:
			if i >= best_sectors.size():
				best_sectors.append(lap.sectors[i])
			else:
				best_sectors[i] = minf(best_sectors[i], lap.sectors[i])
	if autopilot:
		return
	if Records.save_lap(nick, car_id, lap):
		_toast("Recorde pessoal: " + _fmt(lap.time))
		top_records = Records.top(8)
	elif not lap.valid:
		_toast("Volta inválida (4 rodas fora)")
	elif nick == "":
		_toast("Sem nick: aperte N para gravar seus recordes")


func _open_nick() -> void:
	nick_edit.text = nick
	nick_edit.visible = true
	nick_edit.grab_focus.call_deferred()


func _on_nick(t: String) -> void:
	nick = t.strip_edges()
	Records.save_nick(nick)
	nick_edit.visible = false
	nick_edit.release_focus()
	_toast("Nick: " + (nick if nick != "" else "(nenhum)"))


## cor do setor como no web: roxo = melhor da sessão, verde = melhor que a melhor volta, amarelo = mais lento
func _sector_color(i: int, v: float) -> String:
	if i >= best_sectors.size() or v <= best_sectors[i]:
		return "#b26cff"
	if timer.best == null or v <= timer.best.sectors[i]:
		return "#3ddc6a"
	return "#ffd23f"


func _panel_text() -> String:
	var t := timer
	var red := "#ff5a5a"
	var cur := _fmt(t.current)
	if t.current >= 0.0 and not t.valid:
		cur = "[color=%s]%s  inválida[/color]" % [red, cur]
	var last := _fmt(t.last.time if t.last else -1.0)
	if t.last and not t.last.valid:
		last = "[color=%s]%s[/color]" % [red, last]
	var lines := [
		"[right][b]%s[/b]" % track.section_at(t.s),
		"Melhor  %s" % _fmt(t.best.time if t.best else -1.0),
		"Última  %s" % last,
		"Atual   %s" % cur,
	]
	var secs := []
	for i in 3:
		if i < t.sectors.size():
			secs.append("[color=%s]%.2f[/color]" % [_sector_color(i, t.sectors[i]), t.sectors[i]])
		else:
			secs.append("--.--")
	lines.append("S1 %s   S2 %s   S3 %s" % secs)
	if not is_nan(t.delta):
		var d := t.delta
		lines.append("[font_size=34][color=%s]%s%.2f[/color][/font_size]" % ["#3ddc6a" if d < 0.0 else red, "−" if d < 0.0 else "+", absf(d)])
	lines.append("")
	lines.append("[b]Recordes[/b]  ·  " + (nick if nick != "" else "sem nick (N)"))
	for k in top_records.size():
		var r: Dictionary = top_records[k]
		lines.append("%d. %s  %s  %s" % [k + 1, r.nick, _car_short(r.carId), _fmt(float(r.time))])
	return "\n".join(lines) + "[/right]"


var _shorts := {}

func _car_short(id: String) -> String:
	if _shorts.is_empty():
		var list = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
		for c in list:
			_shorts[c.id] = c.get("short", c.get("name", c.id))
	return _shorts.get(id, id)


# ------------------------------------------------------------------ laço

func _input_axes(dt: float) -> Array:
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
	if paused or nick_edit.visible:
		return
	var inp := _input_axes(dt)
	car.step(dt, inp[0], inp[1], inp[2], inp[3], inp[4])
	time += dt
	timer.update(dt, car)


func _process(dt: float) -> void:
	_update_car_view()
	if not paused:
		rumble.update(car, dt)
	if shot_dir != "":
		_shot_tick(dt)
	chase.update(dt)
	if shot_dir != "" and shot_k % 3 == 0:
		# prints de vitrine: 3/4 de frente, perto do carro
		var r := car.basis().x
		var fwd := -car.basis().z
		cam.global_position = car.pos + fwd * 5.2 + r * 3.2 + Vector3.UP * 0.6
		cam.look_at(car.pos + Vector3.UP * 0.1, Vector3.UP)

	var kmh := car.vel.length() * 3.6
	hud_big.text = "%d km/h   %s" % [int(kmh), "N" if car.gear == 0 else ("R" if car.gear < 0 else str(car.gear))]
	if paused:
		hud_big.text = "PAUSA"
	var abs_on := false
	for w in car.wheels:
		abs_on = abs_on or w.abs_active
	toast_t -= dt
	panel.text = _panel_text()
	hud.text = "%s\n%d rpm   %.1f g lat  %+.1f g long\n%s  %s  %s%s%s\n%s\n%d fps   %s   %s%s\n%s\n%s" % [
		car.name, int(car.rpm),
		absf(car.g_lat), car.g_long,
		"ABS" if car.assists.abs else "abs off", "TC" if car.assists.tc else "tc off",
		"câmbio auto" if car.assists.auto else "câmbio manual",
		"   [ABS atuando]" if abs_on else "", "   [TC atuando]" if car.tc_cut > 0.05 else "",
		_surfaces(), Engine.get_frames_per_second(), "Alto" if high else "Celular", input.source,
		"  · piloto automático" if autopilot else "", toast if toast_t > 0.0 else "",
		"[E/Q] marcha  [1] ABS  [2] TC  [G] câmbio  [R] grid  [N] nick  [C] câmera  [P] piloto  [F1] qualidade  [F12] print"]


func _unhandled_input(e: InputEvent) -> void:
	# digitando o nick: as teclas não comandam o carro
	if nick_edit.visible:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			nick_edit.visible = false
			nick_edit.release_focus()
			get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_N:
				_open_nick()
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
				_set_quality(not high)
			KEY_F12:
				_screenshot()
			KEY_ESCAPE:
				# volta para a garagem (sem garagem, quando aberto direto com --car/--shot, sai)
				if Game.from_garage:
					get_tree().change_scene_to_file("res://scenes/garagem.tscn")
				else:
					get_tree().quit()


	# câmera também no controle (Y, como no web)
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y:
		chase.next()
		_toast("Câmera: " + chase.mode_name())


func _notification(what: int) -> void:
	# botão voltar do Android: pausa (o menu entra na etapa 9)
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()


func _toggle_pause() -> void:
	paused = not paused


func _toast(t: String) -> void:
	toast = t
	toast_t = 2.0


## superfície sob cada roda (DE DD / TE TD), quando alguma sai do asfalto
func _surfaces() -> String:
	var out := []
	var any := false
	for w in car.wheels:
		out.append(Ground.NAMES[w.surface] if w.contact else "ar")
		any = any or w.surface != Ground.ASPHALT or not w.contact
	return "%s %s / %s %s" % out if any else ""


## Ajusta presets de qualidade: h=true (Alto/PC), h=false (Leve/Mobile Bonito).
func _set_quality(h: bool) -> void:
	high = h
	env.ssao_enabled = h
	env.ssil_enabled = h
	env.ssr_enabled = h
	env.glow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if h else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 180.0 if h else 90.0
	get_viewport().msaa_3d = Viewport.MSAA_4X if h else Viewport.MSAA_2X
	# No mobile, mantemos a resolução nítida nativa (1.0) ou muito próxima (0.95 com FSR se necessário)
	# para nunca ficar embaçado ou parecer PS1
	get_viewport().scaling_3d_scale = 1.0


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var path := "%s/godot-gt3-%d.png" % [dir, Time.get_unix_time_from_system()]
	img.save_png(path)
	print("print: ", path)
