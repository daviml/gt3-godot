# Captura automática de prints por posição (s em metros) para comparação visual com o LMU.
# Uso: godot --path . --script res://scripts/tests/capture_compare.gd -- --out=build/compare/godot_atual --quality=2
#      Laguna Seca: -- --track=laguna-seca --out=build/compare/laguna_seca/godot [--cam=0|1]
#      (--cam: 0 perseguição, como a 1ª volta do vídeo do LMU; 1 capô, como a volta onboard)
#      --pontos=nome:s,nome:s: pontos livres em vez da lista da pista
#      --mover: o carro chega andando (piloto automático lançado 260 m antes, o jogo rodando de verdade, com a
#      câmera e o desfoque de velocidade dele); sem --mover, parado e assentado na pista (inclinado com ela).
#      Para o --mover, use um carro com referência na pista (ex.: --car=bmw-m4-gt3); sem ela vale o Bot simples.
extends SceneTree

const CHECKPOINTS := [
	["01_senna_entrada", 230.0],
	["02_senna_apex2", 380.0],
	["03_curva_do_sol", 640.0],
	["04_reta_oposta_1", 900.0],
	["05_reta_oposta_2", 1260.0],
	["06_descida_do_lago", 1430.0],
	["07_ferradura_entrada", 1860.0],
	["08_ferradura", 2030.0],
	["09_laranjinha", 2160.0],
	["10_pinheirinho", 2470.0],
	["11_bico_de_pato", 2660.0],
	["12_mergulho", 2960.0],
	["13_juncao", 3180.0],
	["14_subida_boxes", 3650.0],
	["15_arquibancadas", 3980.0],
]

## Laguna Seca: [nome, s, quadro do LMU em build/compare/lmu_laguna/scan/ (perseguição, onboard)]
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
	var out_dir := "build/compare/godot_atual"
	var quality := 2
	var only: PackedStringArray = []
	var bench := false
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

	var list: Array = CHECKPOINTS_LAGUNA if Game.track_id == "laguna-seca" else CHECKPOINTS
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
			car.reset_at(track.index_at(s))
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
		# presets leves limitam o FPS/redesenho: força um quadro novo antes de ler a tela
		RenderingServer.force_draw(true, 1.0 / 60.0)
		var img := root.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, cname]
		img.save_png(ProjectSettings.globalize_path("res://" + path))
		print("saved ", path, " carro=", car.pos.round(), " cam=", chase.cam.global_position.round() if "cam" in chase else "")

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
