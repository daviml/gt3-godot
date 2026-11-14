# Etapa 10: HUD LMU e menu de pausa (sem janela).
# - cor dos pneus pelo slip combinado (azul → verde → amarelo → vermelho), igual ao tyreColor do web;
# - uso do pneu = hipotenusa de κ/κpico e α/αpico, zero com a roda no ar;
# - cor dos setores (roxo / verde / amarelo) e formatação dos tempos;
# - o painel do Porsche só liga na câmera de capô, e só no Porsche;
# - ajustes do menu (qualidade, volume, assistências) gravados e lidos de user://jogo.cfg.
# uso: godot --headless --path . --script res://scripts/tests/hud.gd
extends SceneTree

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func near(c: Color, hex: String, tol := 0.02) -> bool:
	var d := Color(hex)
	return absf(c.r - d.r) < tol and absf(c.g - d.g) < tol and absf(c.b - d.b) < tol


func _init() -> void:
	# teste de Interlagos: não depende da última pista escolhida no jogo (user://jogo.cfg)
	Game.track_id = Game.DEFAULT_TRACK
	var track := Track.new("res://data/track/track.json")
	var ground := FlatGround.new()
	var car := Car.load_car(ground, "corvette-c6r-gt3")
	var timer := LapTimer.new(track)

	print("cor dos pneus")
	check(near(Hud.tyre_color(0.0), "#3d8bff"), "solto = azul")
	check(near(Hud.tyre_color(0.45), "#2fd36b"), "45% = verde")
	check(near(Hud.tyre_color(0.8), "#f2cc30"), "80% = amarelo")
	check(near(Hud.tyre_color(1.5), "#ff3b30"), "passou do pico = vermelho")
	var mid := Hud.tyre_color(0.225)
	check(mid.g > Hud.tyre_color(0.0).g and mid.b < Hud.tyre_color(0.0).b, "meio do caminho azul→verde interpola")

	print("uso do pneu")
	var w := car.wheels[0]
	w.fz = 4000.0
	w.kappa = car.kappa_peak
	w.alpha = 0.0
	check(absf(Hud.tyre_use(car, 0) - 1.0) < 1e-6, "κ no pico = 1,0")
	w.alpha = car.alpha_peak
	check(absf(Hud.tyre_use(car, 0) - sqrt(2.0)) < 1e-6, "κ e α no pico = √2")
	w.fz = 0.0
	check(Hud.tyre_use(car, 0) == 0.0, "roda no ar = 0")

	print("setores e tempos")
	var hud := Hud.new(car, timer, track, "corvette-c6r-gt3", false)
	check(hud.sector_color(0, 30.0) == Hud.PURPLE, "sem referência = roxo")
	hud.best_sectors = [30.0, 31.0, 32.0]
	var best := LapTimer.Lap.new()
	best.time = 95.0
	best.sectors = [30.5, 31.5, 33.0]
	timer.best = best
	check(hud.sector_color(0, 29.9) == Hud.PURPLE, "melhor da sessão = roxo")
	check(hud.sector_color(0, 30.3) == Hud.GREEN, "melhor que a melhor volta = verde")
	check(hud.sector_color(0, 31.0) == Hud.YELLOW, "mais lento = amarelo")
	check(LapTimer.format_time(95.123) == "1:35.123", "formato 1:35.123")
	check(LapTimer.format_time(-1.0) == "-:--.---", "sem tempo")

	print("painel dedicado (DASH_CARS vazio)")
	check(not hud.dash, "Corvette C6.R usa mostrador LMU padrão")
	hud.set_view("perseguição")
	check(not hud.dash_on, "fora do capô: só o mostrador LMU")
	hud.set_view("capô")
	check(not hud.dash_on, "câmera de capô sem painel próprio mantém mostrador LMU")
	var hud2 := Hud.new(car, timer, track, "bmw-m4-gt3", false)
	hud2.set_view("capô")
	check(not hud2.dash_on, "M4 não tem painel próprio")
	check(hud._map_pts.size() > 500 and hud._map_pts[0] == hud._map_pts[hud._map_pts.size() - 1], "mapa: traçado fechado")
	check(hud._corners.size() == 15, "radar detecta as 15 curvas de Interlagos")

	print("melhorias de HUD (barra horizontal, radar, placa expansível)")
	var old_gauge = Game.get_setting("hud", "mostrador", null)
	var old_map = Game.get_setting("hud", "minimapa", null)
	hud.set_gauge_style("circular")
	check(hud.gauge_style == "circular" and String(Game.get_setting("hud", "mostrador", "")) == "circular", "mostrador alterna para circular e salva")
	hud.set_gauge_style("barra")
	check(hud.gauge_style == "barra", "mostrador retorna para barra horizontal")
	check(hud.map_mode in ["dynamic", "circuit"], "minimapa em modo válido")
	hud._toggle_map_mode()
	var toggled_map := hud.map_mode
	hud._toggle_map_mode()
	check(hud.map_mode != toggled_map, "minimapa alterna entre RADAR e CIRCUITO")
	check(not hud.board_expanded, "melhores tempos começa recolhido")
	hud._toggle_board()
	check(hud.board_expanded, "melhores tempos expande ao clicar")
	car.g_lat = 1.4
	car.g_long = -0.8
	hud.update(0.02, 0.7, 0.0)
	check(hud._g_trail.size() == 1, "radar de força G registra rastro")
	if old_gauge != null:
		Game.set_setting("hud", "mostrador", old_gauge)
	else:
		Game.erase_setting("hud", "mostrador")
	if old_map != null:
		Game.set_setting("hud", "minimapa", old_map)
	else:
		Game.erase_setting("hud", "minimapa")

	print("ajustes do menu (user://jogo.cfg)")
	var old_q = Game.get_setting("video", "qualidade", null)
	var old_v = Game.get_setting("audio", "volume", null)
	Game.set_setting("video", "qualidade", "Médio")
	Game.set_setting("audio", "volume", 0.35)
	check(String(Game.get_setting("video", "qualidade", "")) == "Médio", "qualidade gravada e lida")
	check(absf(float(Game.get_setting("audio", "volume", 0.0)) - 0.35) < 1e-6, "volume gravado e lido")
	check("Mínimo" in PauseMenu.QUALITIES and "Médio" in PauseMenu.QUALITIES and PauseMenu.QUALITIES.size() == 4, "4 presets: Mínimo / Leve / Médio / Extremo")
	# devolve o que estava
	if old_q != null:
		Game.set_setting("video", "qualidade", old_q)
	else:
		Game.erase_setting("video", "qualidade")
	if old_v != null:
		Game.set_setting("audio", "volume", old_v)
	else:
		Game.erase_setting("audio", "volume")
	check(Game.get_setting("video", "qualidade", "x") == (old_q if old_q != null else "x"), "ajuste devolvido ao que estava")

	hud.free()
	hud2.free()
	print("HUD: " + ("tudo ok" if ok else "FALHOU"))
	quit(0 if ok else 1)
