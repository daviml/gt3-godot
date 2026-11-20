# Captura automática de prints por posição (s em metros) para comparação visual com o LMU.
# Uso: godot --path . --script res://scripts/tests/capture_compare.gd -- --out=build/compare/godot_atual --quality=2
#      Laguna Seca: -- --track=laguna-seca --out=build/compare/laguna_seca/godot [--cam=0|1]
#      (--cam: 0 perseguição, como a 1ª volta do vídeo do LMU; 1 capô, como a volta onboard)
#      --pontos=nome:s,nome:s: pontos livres em vez da lista da pista
#      --mover: o carro chega andando (piloto automático lançado 260 m antes, o jogo rodando de verdade, com a
#      câmera e o desfoque de velocidade dele); sem --mover, parado e assentado na pista (inclinado com ela).
#      Para o --mover, use um carro com referência na pista (ex.: --car=bmw-m4-gt3); sem ela vale o Bot simples.
#
# Modo --atlas (PLANO-INTERLAGOS-DETALHES.md §2, Fase 0): fotografa por METRO DE PISTA, no mesmo índice dos quadros
# do vídeo do LMU (build/ref/interlagos/<chase|onboard>/sNNNN.jpg), com uma câmera de comparação própria igual à
# do vídeo (a câmera do jogo não muda):
#   -- --atlas --s0=0 --s1=4290 --passo=50 --cam=0 --quality=2 --out=build/ref/interlagos/godot/chase [--regua]
#   --s1 < --s0 cruza a linha de chegada (ex.: --s0=3884 --s1=250). Arquivos: <out>/sNNNN.png (1280x720, 16:9).
#   --cam=0 perseguição do LMU, --cam=1 olho do piloto (modelo do carro escondido).
#   --regua desenha na pista uma linha a cada 10 m de s (número a cada 50 m) e marcas a cada 2 m de d.
#   O carro fica parado sobre a linha da referência do Garage 61 (RefBot); sem --car usa um carro com referência
#   na pista; --car=<id> sem referência falha. Pista sem referência nenhuma: linha central.
extends SceneTree

# ---- câmera de comparação do modo --atlas ----
# Perseguição do LMU (--cam=0). O vídeo mostra "Vertical FOV: 50°". Medido em 3 quadros 1920x1080 de
# build/compare/lmu_30 (01_reta_freada_senna, 08_reta_oposta_meio, 30_reta_grid), Porsche 911 GT3 R de trás, carro
# centrado: carroceria traseira 408 px de largura (≈2,05 m → 21% da tela), pneus traseiros tocam o chão em
# y≈735, topo do teto em y≈435, horizonte em y≈300 (média do ponto de fuga entre a reta em subida e a em descida).
# Com f = 540/tan(25°) = 1158 px, o ajuste (mínimos quadrados) dá: câmera 4,46 m atrás do para-choque traseiro
# (o 911 tem ~2,31 m do centro à traseira → 6,8 m do centro do carro), 2,14 m acima do chão, inclinada 12° para
# baixo. A câmera do LMU segue o carro quase rígida: aqui fica presa atrás dele, na direção dele.
const ATLAS_CHASE_FOV := 50.0
const ATLAS_CHASE_DIST := 6.8
const ATLAS_CHASE_ALT := 2.14
const ATLAS_CHASE_PITCH := -12.0
# Onboard do LMU (--cam=1): olho do piloto. FOV estimado no quadro de t=120 s do vídeo (Reta Oposta) comparando a
# largura angular dos prédios do horizonte com o quadro de perseguição do mesmo trecho (FOV 50° conhecido): 1,21×
# maior no onboard → f ≈ 1350–1400 px → FOV vertical ≈ 43° (±3°). Horizonte em y≈490 de 1080 (acima do meio)
# → olha ~2° para baixo.
# Posição: lado esquerdo do cockpit, um pouco à frente do centro, altura de olho de GT3.
const ATLAS_ONB_FOV := 43.0
const ATLAS_ONB_POS := Vector3(-0.35, 1.05, 0.35)  # x direita, y altura sobre o chão, z para a frente (m)
const ATLAS_ONB_PITCH := -2.0
## saída do atlas: mesma proporção e tamanho dos quadros do LMU em build/ref/interlagos/
const ATLAS_W := 1280
const ATLAS_H := 720

const CHECKPOINTS := [
	["01_reta_freada_senna", 135.0, 4.2, 0.0],
	["02_senna_entrada", 258.0, 4.0, 10.0],
	["03_senna_apex1", 335.0, -4.2, -10.0],
	["04_senna_apex2", 415.0, 4.5, -8.0],
	["05_curva_do_sol_entrada", 545.0, -4.5, 5.0],
	["06_curva_do_sol_saida", 685.0, -5.5, 6.0],
	["07_reta_oposta_inicio", 920.0, 4.8, 0.0],
	["08_reta_oposta_meio", 1165.0, 4.6, 0.0],
	["09_reta_oposta_freada", 1340.0, 5.0, 4.0],
	["10_descida_lago_apex", 1485.0, -3.5, 8.0],
	["11_descida_lago_saida", 1560.0, -3.8, 4.0],
	["12_subida_ferradura_1", 1700.0, 3.5, 0.0],
	["13_subida_ferradura_2", 1850.0, -4.2, 0.0],
	["14_ferradura_entrada", 1985.0, 4.0, -5.0],
	["15_ferradura_meio", 2075.0, 4.8, -12.0],
	["16_laranjinha_entrada", 2165.0, -3.5, -10.0],
	["17_laranjinha_saida", 2280.0, 3.0, 8.0],
	["18_esse_pinheirinho", 2390.0, -3.5, 10.0],
	["19_pinheirinho_saida", 2535.0, -3.0, -5.0],
	["20_bico_de_pato_apex", 2762.0, 3.8, -12.0],
	["21_bico_de_pato_saida", 2835.0, 0.0, -4.0],
	["22_mergulho_entrada", 2935.0, -3.2, -8.0],
	["23_juncao_freada", 3120.0, 4.5, 4.0],
	["24_juncao_apex", 3260.0, -3.5, -8.0],
	["25_juncao_saida", 3390.0, 1.5, -4.0],
	["26_subida_atenuador", 3490.0, -2.5, 2.0],
	["27_subida_cafe", 3610.0, -3.8, 4.0],
	["28_subida_telao", 3780.0, -2.0, 2.0],
	["29_entrada_boxes_ilha", 3940.0, -3.0, 2.0],
	["30_reta_grid", 4160.0, 0.5, 0.0],
]

## Laguna Seca: [nome, s, quadro do LMU em build/compare/lmu_laguna/scan/ (perseguição, onboard)]
const CHECKPOINTS_IMOLA := [
	["01_reta_boxes", 4815.0, 0.0, 0.0],
	["02_freada_tamburello", 540.0, 0.0, 0.0],
	["03_tamburello", 696.0, 0.0, 0.0],
	["04_villeneuve_ent", 1280.0, 0.0, 0.0],
	["05_villeneuve_apex", 1412.0, 0.0, 0.0],
	["06_tosa_ent", 1660.0, 0.0, 0.0],
	["07_tosa_saida", 1780.0, 0.0, 0.0],
	["08_piratella", 2240.0, 0.0, 0.0],
	["09_acque_descida", 2640.0, 0.0, 0.0],
	["10_acque_apex", 2836.0, 0.0, 0.0],
	["11_variante_alta", 3340.0, 0.0, 0.0],
	["12_descida_rivazza", 3890.0, 0.0, 0.0],
	["13_rivazza_1", 4080.0, 0.0, 0.0],
	["14_rivazza_2_pit", 4390.0, 0.0, 0.0],
	["15_traguardo_saida", 150.0, 0.0, 0.0],
]

const CHECKPOINTS_LAGUNA := [
	["01_freada_andretti", 300.0, "chase_7", "onb_98"],
	["02_andretti", 470.0, "chase_16", "onb_100"],
	["03_curva3", 690.0, "chase_22", "onb_104"],
	["04_arco_t3_t4", 840.0, "chase_25", "onb_106"],
	["05_curva5", 1450.0, "chase_31", "onb_120"],
	["06_curva6", 1880.0, "chase_40", "onb_128"],
	["07_rahal", 2150.0, "chase_49", "onb_134"],
	["08_freada_corkscrew", 2370.0, "chase_52", "onb_138"],
	["09_corkscrew", 2440.0, "chase_58", "onb_140"],
	["10_descida", 2500.0, "chase_61", "onb_142"],
	["11_rainey", 2660.0, "chase_64", "onb_146"],
	["12_curva10", 2950.0, "chase_70", "onb_152"],
	["13_curva11", 3230.0, "chase_79", "onb_160"],
	["14_reta", 3450.0, "chase_85", "onb_164"],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--atlas" in OS.get_cmdline_user_args():
		await _run_atlas()
		return
	var out_dir := "build/compare/godot_atual"
	var quality := 2
	var only: PackedStringArray = []
	var bench := false
	var time_opt := ""
	var cam := 0
	var moving := false
	var custom: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--quality="):
			quality = int(a.substr(10))
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--bench":
			bench = true
		elif a.begins_with("--time="):
			time_opt = a.substr(7)
		elif a.begins_with("--cam="):
			cam = int(a.substr(6))
		elif a == "--mover":
			moving = true
		elif a.begins_with("--pontos="):
			# pontos livres: --pontos=nome:s,nome:s (ex.: placas de freada, saída dos boxes)
			for item in a.substr(9).split(","):
				var kv := item.split(":")
				if kv.size() == 2:
					custom.append([kv[0], float(kv[1]), "", ""])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))

	var prev_time := Game.get_time_of_day_setting()
	if not time_opt.is_empty():
		Game.set_time_of_day(time_opt)

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	main.set_physics_process(false)
	main.set_process(false)
	if main.hud:
		main.hud.visible = false
	if main.touch:
		main.touch.visible = false
	main._set_quality(quality)
	main.chase.mode = cam

	# deixa o cenário terminar de carregar e os shaders compilarem (senão os prints repetem um quadro antigo)
	for _f in 45:
		await process_frame

	var track: Track = main.track
	var car: Car = main.car
	var chase: ChaseCamera = main.chase

	var list: Array = CHECKPOINTS_IMOLA if Game.track_id == "imola" else (CHECKPOINTS_LAGUNA if Game.track_id == "laguna-seca" else CHECKPOINTS)
	if not custom.is_empty():
		list = custom
	if moving:
		# o primeiro lançamento depois de carregar volta para o grid (o main reposiciona o carro uma vez quando
		# volta a processar): um lançamento de descarte antes dos prints
		await _drive_to(main, main.track, main.car, main.chase, float(list[0][1]))
	for cp in list:
		var cname: String = cp[0]
		if not only.is_empty() and not (cname in only):
			continue
		var s: float = cp[1]
		if moving:
			await _drive_to(main, track, car, chase, s)
		else:
			# parado na pista, inclinado com ela (pitch e roll pela normal), e 0,4 s de física freado para a
			# suspensão assentar (antes o carro ficava nivelado e enterrava nas rampas, como a do Corkscrew)
			var idx := track.index_at(s)
			car.reset_at(idx)
			var lat: float = float(cp[2]) if cp.size() > 2 and typeof(cp[2]) in [TYPE_FLOAT, TYPE_INT] else 0.0
			var yaw_deg: float = float(cp[3]) if cp.size() > 3 and typeof(cp[3]) in [TYPE_FLOAT, TYPE_INT] else 0.0
			if absf(lat) > 0.01:
				car.pos += track.R[idx] * lat
			if absf(yaw_deg) > 0.01:
				car.rot = Quaternion(Vector3.UP, deg_to_rad(yaw_deg)) * car.rot
			for _k in int(0.4 * Car.HZ):
				car.step(1.0 / Car.HZ, 0.0, 0.0, 1.0)
			car.prev_pos = car.pos
			car.prev_rot = car.rot
			main._update_car_view(1.0)
			chase.snap()
			chase.update(1.0 / 60.0, 1.0)
			for _f in 6:
				await process_frame
		if bench:
			var t0 := Time.get_ticks_usec()
			var frames := 30
			for _f in frames:
				await process_frame
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
			var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			print("bench %s (q=%d): %.2f ms/frame (%.1f FPS), %d draw calls, %.0fk triângulos" % [cname, quality, ms, 1000.0 / maxf(ms, 0.001), dc, prims / 1000.0])
		if main.paused:
			main._set_paused(false)
		chase.mode = cam
		# presets leves limitam o FPS/redesenho: força um quadro novo antes de ler a tela
		RenderingServer.force_draw(true, 1.0 / 60.0)
		var img := root.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, cname]
		img.save_png(ProjectSettings.globalize_path("res://" + path))
		print("saved ", path, " carro=", car.pos.round(), " cam=", chase.cam.global_position.round() if "cam" in chase else "")

	if not time_opt.is_empty():
		Game.set_time_of_day(prev_time)
	quit(0)


## Lança o carro 260 m antes de s (como os testes do RefBot) e deixa o jogo dirigir sozinho até lá.
func _drive_to(main: Node, track: Track, car: Car, chase: ChaseCamera, s_target: float) -> void:
	var L := track.length
	var s0 := fposmod(s_target - 260.0, L)
	var bot = main.bot
	if bot is RefBot:
		var p0: Vector3 = bot.line_point(s0)
		var p1: Vector3 = bot.line_point(s0 + 4.0)
		# no plano da pista (com o camber), alinhado à normal dela: a linha (line_point) já fica sobre a pista
		track.locate(p0, -1)
		var up := track.ln
		var fwd := ((p1 - p0) - up * (p1 - p0).dot(up)).normalized()
		var rgt := fwd.cross(up).normalized()
		car.reset_basis(p0 + up * (car.p.cg + 0.05), Basis(rgt, up, -fwd))
		# a velocidade do iRacing pode passar do que este carro aguenta (T6): lança no limite do piloto automático
		var v0: float = minf(bot.ref_at(bot._rv, s0), bot.speed_at(s0))
		car.vel = fwd * v0
		car.gear = car.p.ratios.size()
		for w in car.wheels:
			w.omega = v0 / car.p.radius
	else:
		car.reset_at(track.index_at(s0))
	car.assists.auto = true
	main.autopilot = true
	main.set_physics_process(true)
	main.set_process(true)
	chase.snap()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		if OS.get_cmdline_user_args().has("--debug-mover") and (Time.get_ticks_msec() - t0) % 300 < 20:
			print("    t=%.2f pos=%s v=%.0f hint=%d" % [(Time.get_ticks_msec() - t0) / 1000.0, car.pos.round(), car.vel.length() * 3.6, car.hint])
		track.locate(car.pos, car.hint)
		var ds := fposmod(track.ls - s0, L)
		if ds >= 260.0 and ds < L * 0.5:
			break
	print("  [mover] s0=%.0f alvo=%.0f chegou s=%.0f em %.1f s, %.0f km/h, bot=%s" % [s0, s_target, track.ls, (Time.get_ticks_msec() - t0) / 1000.0, car.vel.length() * 3.6, "RefBot" if bot is RefBot else "Bot"])
	# congela no quadro da chegada (câmera e desfoque já no estado do movimento)
	main.set_physics_process(false)
	await process_frame
	main.set_process(false)
	await process_frame


# ------------------------------------------------------------------ modo --atlas

func _run_atlas() -> void:
	var out_dir := "build/ref/interlagos/godot/chase"
	var quality := 2
	var cam_mode := 0
	var time_opt := ""
	var s_from := 0.0
	var s_to := -1.0
	var passo := 25.0
	var regua := false
	var car_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--quality="):
			quality = int(a.substr(10))
		elif a.begins_with("--cam="):
			cam_mode = clampi(int(a.substr(6)), 0, 1)
		elif a.begins_with("--time="):
			time_opt = a.substr(7)
		elif a.begins_with("--s0="):
			s_from = float(a.substr(5))
		elif a.begins_with("--s1="):
			s_to = float(a.substr(5))
		elif a.begins_with("--passo="):
			passo = maxf(0.5, float(a.substr(8)))
		elif a == "--regua":
			regua = true
		elif a.begins_with("--car="):
			car_arg = a.substr(6)

	# carro com referência do Garage 61 na pista (o RefBot dá a linha onde o carro fica)
	var car_id: String = Game.car_id
	var refs = Game.get_track_info().get("refs", {})
	var ref_ids: Array = (refs as Dictionary).keys() if refs is Dictionary else []
	if car_arg != "":
		if Game.track_ref_for_car(car_arg) == "":
			printerr("[atlas] o carro %s não tem referência em %s (data/tracks.json → refs). Use um destes: %s"
				% [car_arg, Game.track_id, str(ref_ids)])
			quit(1)
			return
		car_id = car_arg
	elif Game.track_ref_for_car(car_id) == "":
		if not ref_ids.is_empty():
			car_id = String(ref_ids[0])
			print("[atlas] usando %s (carro com referência nesta pista)" % car_id)
		else:
			push_warning("[atlas] %s não tem referência de nenhum carro: carro na linha central" % Game.track_id)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))
	var prev_time := Game.get_time_of_day_setting()
	if not time_opt.is_empty():
		Game.set_time_of_day(time_opt)

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	main.car_id = car_id  # antes do _ready (o --car= da linha de comando, se houver, é o mesmo)
	root.add_child(main)
	await process_frame
	await process_frame

	main.set_physics_process(false)
	main.set_process(false)
	if main.hud:
		main.hud.visible = false
	if main.touch:
		main.touch.visible = false
	if main.speed_blur:
		main.speed_blur.visible = false
	if main.ghost_car:
		main.ghost_car.visible = false
	main._set_quality(quality)
	main.chase.mode = 0

	var track: Track = main.track
	var car: Car = main.car
	var L := track.length
	if s_to < 0.0:
		s_to = s_from
	var lista := _atlas_s_list(s_from, s_to, passo, L)
	var shots := lista.size()

	# câmera de comparação (a do jogo fica como está, só deixa de ser a atual)
	var game_cam: Camera3D = main.cam
	var acam := Camera3D.new()
	acam.near = 0.05
	acam.far = game_cam.far
	acam.environment = game_cam.environment
	acam.attributes = game_cam.attributes
	acam.compositor = game_cam.compositor
	main.add_child(acam)
	acam.make_current()
	# FOV vertical do LMU num quadro 16:9; em janela mais estreita que 16:9 fixa o horizontal equivalente
	var vfov := ATLAS_CHASE_FOV if cam_mode == 0 else ATLAS_ONB_FOV
	var vp_size := root.get_visible_rect().size
	if vp_size.x / vp_size.y >= 16.0 / 9.0 - 0.001:
		acam.keep_aspect = Camera3D.KEEP_HEIGHT
		acam.fov = vfov
	else:
		acam.keep_aspect = Camera3D.KEEP_WIDTH
		acam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov) * 0.5) * 16.0 / 9.0))
	if cam_mode == 1:
		main.car_view.visible = false  # o interesse é a pista; o modelo tamparia a vista

	if regua:
		main.add_child(_build_regua(track))

	# deixa o cenário terminar de carregar e os shaders compilarem (senão os prints repetem um quadro antigo)
	for _f in 45:
		await process_frame

	var bot = main.bot
	print("[atlas] pista=%s carro=%s bot=%s cam=%d s=%.0f→%.0f passo=%.0f (%d prints) tela=%s"
		% [Game.track_id, car_id, "RefBot" if bot is RefBot else "linha central", cam_mode, s_from, s_to, passo,
		shots, str(vp_size)])
	for s: float in lista:
		_place_on_line(main, track, car, bot, s)
		_place_atlas_cam(acam, car, cam_mode)
		for _f in 6:
			await process_frame
		if main.paused:
			main._set_paused(false)
		RenderingServer.force_draw(true, 1.0 / 60.0)
		var img := _crop_16x9(root.get_texture().get_image())
		var path := "%s/s%04d.png" % [out_dir, roundi(s)]
		img.save_png(ProjectSettings.globalize_path("res://" + path))
		track.locate(car.pos, -1)
		print("saved %s s=%.1f d=%+.2f carro=%s" % [path, track.ls, track.ld, str(car.pos.round())])

	if not time_opt.is_empty():
		Game.set_time_of_day(prev_time)
	quit(0)


## Metros a fotografar de s0 a s1 a cada passo. Se s1 < s0 o trecho cruza a linha de chegada: depois dela a
## contagem recomeça na grade alinhada com s = 0 (0, passo, 2·passo…), a mesma dos quadros do LMU (s0000, s0010…).
static func _atlas_s_list(s0: float, s1: float, passo: float, L: float) -> Array[float]:
	var out: Array[float] = []
	var cruza := s1 < s0
	var s := s0
	while s < L - 1e-6 and (cruza or s <= s1 + 1e-6):
		out.append(s)
		s += passo
	if cruza:
		s = 0.0
		while s <= s1 + 1e-6:
			out.append(s)
			s += passo
	return out


## Carro parado em s sobre a linha da referência (RefBot), na direção dela, assentado na pista. Sem RefBot: centro.
func _place_on_line(main: Node, track: Track, car: Car, bot, s: float) -> void:
	if bot is RefBot:
		var p0: Vector3 = bot.line_point(s)
		var pa: Vector3 = bot.line_point(s - 2.0)
		var pb: Vector3 = bot.line_point(s + 2.0)
		track.locate(p0, -1)
		var up := track.ln
		var fwd := ((pb - pa) - up * (pb - pa).dot(up)).normalized()
		var rgt := fwd.cross(up).normalized()
		car.reset_basis(p0 + up * (float(car.p.cg) + 0.05), Basis(rgt, up, -fwd))
	else:
		car.reset_at(track.index_at(s))
	# 0,4 s de física freado para a suspensão assentar (pitch e roll pela pista)
	for _k in int(0.4 * Car.HZ):
		car.step(1.0 / Car.HZ, 0.0, 0.0, 1.0)
	car.vel = Vector3.ZERO
	car.prev_pos = car.pos
	car.prev_rot = car.rot
	main._update_car_view(1.0)


## Posiciona a câmera de comparação presa ao carro (perseguição ou olho do piloto), sem rolagem.
func _place_atlas_cam(acam: Camera3D, car: Car, cam_mode: int) -> void:
	var b := Basis(car.rot)
	var fwd := -b.z
	var rgt := fwd.cross(Vector3.UP).normalized()
	var up := rgt.cross(fwd).normalized()
	var ground := car.pos - b.y * float(car.p.cg)
	var look := Basis(rgt, up, -fwd)
	if cam_mode == 0:
		acam.global_position = ground - fwd * ATLAS_CHASE_DIST + up * ATLAS_CHASE_ALT
		acam.global_basis = Basis(rgt, deg_to_rad(ATLAS_CHASE_PITCH)) * look
	else:
		acam.global_position = ground + b.x * ATLAS_ONB_POS.x + b.y * ATLAS_ONB_POS.y + fwd * ATLAS_ONB_POS.z
		acam.global_basis = Basis(rgt, deg_to_rad(ATLAS_ONB_PITCH)) * look


## Recorta o centro da tela em 16:9 e reduz para ATLAS_W x ATLAS_H (mesmo enquadramento dos quadros do LMU).
func _crop_16x9(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var cw := w
	var ch := h
	if float(w) / h > 16.0 / 9.0:
		cw = roundi(h * 16.0 / 9.0)
	else:
		ch = roundi(w * 9.0 / 16.0)
	var out := img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	out.convert(Image.FORMAT_RGB8)
	out.resize(ATLAS_W, ATLAS_H, Image.INTERPOLATE_LANCZOS)
	return out


## Régua desenhada na pista (só no teste): linha transversal a cada 10 m de s (mais grossa, ciano e com número a
## cada 50 m) e marcas amarelas curtas a cada 2 m de d (a do centro, d = 0, mais longa).
func _build_regua(track: Track) -> Node3D:
	var node := Node3D.new()
	node.name = "Regua"
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var magenta := Color(1.0, 0.1, 0.9)
	var ciano := Color(0.1, 0.95, 1.0)
	var amarelo := Color(1.0, 0.9, 0.1)
	var s := 0.0
	while s < track.length - 0.5:
		var i := track.index_at(s)
		var dl := -(track.wl[i] + 3.0)
		var dr := track.wr[i] + 3.0
		var big := roundi(s) % 50 == 0
		var half := 0.12 if big else 0.06
		var col := ciano if big else magenta
		# transversal, em pedaços de 1 m para acompanhar o relevo
		var d := dl
		while d < dr - 0.01:
			var d2 := minf(d + 1.0, dr)
			_quad(im, _regua_pt(track, s - half, d), _regua_pt(track, s + half, d), _regua_pt(track, s + half, d2),
				_regua_pt(track, s - half, d2), col)
			d = d2
		# marcas de d a cada 2 m (ao longo da pista)
		var dd := ceilf(dl / 2.0) * 2.0
		while dd <= dr:
			var lng := 1.5 if absf(dd) < 0.01 else 0.6
			_quad(im, _regua_pt(track, s - lng, dd - 0.05), _regua_pt(track, s + lng, dd - 0.05),
				_regua_pt(track, s + lng, dd + 0.05), _regua_pt(track, s - lng, dd + 0.05), amarelo)
			dd += 2.0
		if big:
			var lbl := Label3D.new()
			lbl.text = "%d" % roundi(s)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.pixel_size = 0.01
			lbl.font_size = 96
			lbl.outline_size = 16
			lbl.modulate = ciano
			lbl.outline_modulate = Color(0, 0, 0)
			lbl.position = _regua_pt(track, s, dl + 0.5) + Vector3.UP * 1.2
			node.add_child(lbl)
		s += 10.0
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	return node


## Ponto da pista em (s, d), 4 cm acima dela (acima da pintura e do asfalto).
func _regua_pt(track: Track, s: float, d: float) -> Vector3:
	var n := track.n
	var x := fposmod(s / Track.STEP, n)
	var i := int(x)
	var j := (i + 1) % n
	var f := x - i
	var r := track.R[i].lerp(track.R[j], f)
	var nn := track.N[i].lerp(track.N[j], f).normalized()
	return track.P[i].lerp(track.P[j], f) + r * d + nn * 0.04


func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		im.surface_set_color(col)
		im.surface_add_vertex(p)
