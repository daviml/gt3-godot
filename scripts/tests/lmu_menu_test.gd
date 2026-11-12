# Testes unitários e de layout responsivo da UI LMU (Entrega 1 — Fases 1 a 3).
# uso: godot --headless --path . --script res://scripts/tests/lmu_menu_test.gd
extends SceneTree

const TouchControls = preload("res://scripts/input/touch_controls.gd")

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _initialize() -> void:
	run_tests.call_deferred()


func _frames(n := 2) -> void:
	for _i in n:
		await process_frame


func run_tests() -> void:
	var orig_car := Game.car_id
	var orig_mode := Game.mode
	var orig_hide_touch := Game.is_hide_touch_controls()
	var orig_nick := Records.load_nick()

	print("--- 1. Catálogo data/cars.json e distribuição de peso ---")
	var cars := Game.get_cars_list()
	check(cars.size() == 13, "13 carros carregados de data/cars.json (encontrados: %d)" % cars.size())
	var all_complete := true
	for c in cars:
		for field in ["id", "name", "layout", "color", "brand", "engine", "power", "weight", "gears"]:
			if str(c.get(field, "")).strip_edges() == "":
				all_complete = false
				print("    faltando %s em %s" % [field, str(c.get("id", "?"))])
	check(all_complete, "Todos os 13 carros possuem brand, engine, power, weight e gears preenchidos")
	check(Game.weight_distribution_for_layout("dianteiro") == "49% / 51%", "Layout dianteiro = 49% / 51%")
	check(Game.weight_distribution_for_layout("central") == "43% / 57%", "Layout central = 43% / 57%")
	check(Game.weight_distribution_for_layout("traseiro") == "39% / 61%", "Layout traseiro = 39% / 61%")

	print("--- 2. Perfis responsivos LmuTheme ---")
	var lp_desk := LmuTheme.compute_layout_profile(Vector2(1920, 1080), false)
	check(lp_desk.profile == "desktop", "1920x1080 classifica como desktop")
	check(int(lp_desk.header_height) == 56 and bool(lp_desk.show_header_center), "Desktop header 56px com relógio/circuito central")
	check(int(lp_desk.cars_panel_width) == 330 and not bool(lp_desk.cars_hide_aero), "Desktop Carros: painel 330px e 5 linhas com Downforce")
	check(int(lp_desk.cars_grid_cols) == 7 and int(lp_desk.cars_chip_height) == 52, "Desktop Carros: grade 7 col com chips 52px")

	var lp_mob := LmuTheme.compute_layout_profile(Vector2(844, 390), true)
	check(lp_mob.profile == "mobile_landscape", "844x390 mobile classifica como mobile_landscape")
	check(int(lp_mob.header_height) == 42 and not bool(lp_mob.show_header_center), "Mobile landscape header 42px sem centro")
	check(int(lp_mob.cars_panel_width) == 235 and bool(lp_mob.cars_hide_aero) and bool(lp_mob.cars_pb_horizontal), "Mobile landscape Carros: painel 235px, oculta Downforce e PB horizontal")
	check(int(lp_mob.cars_chip_height) == 36 and int(lp_mob.cars_grid_cols) == 7, "Mobile landscape chips 36px e grade 7 col")

	var lp_mob_hd := LmuTheme.compute_layout_profile(Vector2(2400, 1080), true)
	check(lp_mob_hd.profile == "mobile_landscape" and not bool(lp_mob_hd.is_compact_mobile), "2400x1080 mobile (canvas_items) usa mobile_landscape expandido")
	check(int(lp_mob_hd.header_height) == 76 and float(lp_mob_hd.font_scale) >= 1.75, "2400x1080 mobile escala header (76px) e fontes (>=1.75x) para toque")

	var lp_port := LmuTheme.compute_layout_profile(Vector2(390, 844), true)
	check(lp_port.profile == "portrait" and int(lp_port.cars_grid_cols) == 3, "390x844 classifica como portrait (grade 3 col)")

	var lp_tab := LmuTheme.compute_layout_profile(Vector2(800, 600), false)
	check(lp_tab.profile == "tablet" and int(lp_tab.cars_grid_cols) == 5, "800x600 classifica como tablet (grade 5 col)")

	print("--- 3. LmuMenu em Context.GARAGE e visões ---")
	var gar_layer := CanvasLayer.new()
	root.add_child(gar_layer)
	var gar_root := Control.new()
	gar_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gar_layer.add_child(gar_root)
	var gar_menu := LmuMenu.new(LmuMenu.Context.GARAGE)
	gar_root.add_child(gar_menu)
	await _frames(2)

	var vp_exp := root.get_visible_rect().size
	check(gar_menu.size == vp_exp and gar_menu._backdrop.size == vp_exp and gar_menu._root_vbox.size.x == vp_exp.x, "GARAGE preenche a viewport inteira automaticamente sob CanvasLayer (%s vs %s)" % [str(gar_menu.size), str(vp_exp)])
	check(gar_menu.active_view == "home", "GARAGE inicia na aba home")
	check(gar_menu._backdrop.visible, "Home exibe backdrop angular LMU")

	gar_menu.switch_view("cars")
	await _frames(2)
	check(not gar_menu._backdrop.visible, "GARAGE/cars oculta backdrop central para exibir estúdio 3D")
	check(gar_menu._backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE, "GARAGE/cars libera arraste 3D no centro")

	var picked_car := [""]
	gar_menu.car_selected.connect(func(cid: String): picked_car[0] = cid)
	gar_menu.category_filter = "central"
	gar_menu._rebuild_view()
	await _frames(2)
	var central_count := 0
	for c in cars:
		if String(c.get("layout", "")) == "central":
			central_count += 1
	check(gar_menu._cars_grid_nodes.size() == central_count, "Filtro motor central exibe %d/%d chips" % [gar_menu._cars_grid_nodes.size(), central_count])

	gar_menu.set_selected_car("ferrari-488-gt3", true)
	check(picked_car[0] == "ferrari-488-gt3" and Game.car_id == "ferrari-488-gt3", "Seleção de carro emite sinal e salva em Game")

	gar_menu.switch_view("settings")
	gar_menu.search_query = "abs"
	gar_menu._rebuild_view()
	await _frames(2)
	check(not gar_menu._settings_rows.is_empty(), "Busca em Config ('abs') retorna resultados filtrados")

	gar_menu.search_query = ""
	for tab_id in LmuMenu.SETTINGS_TABS:
		gar_menu.switch_settings_tab(tab_id)
		await _frames(1)
	check(gar_menu.active_settings_tab == "driver", "Todas as 5 abas de configurações constroem sem erro")

	gar_menu.switch_view("records")
	gar_menu.set_shared_records("sim", [{"nick": "PilotoTeste", "carId": "corvette-c6r-gt3", "time": 94.12, "sectors": [30.1, 32.0, 32.02]}])
	await _frames(2)
	check(gar_menu.shared_records_by_mode.has("sim"), "Records recebe lista compartilhada por modo")

	gar_menu.switch_view("help")
	await _frames(2)
	check(gar_menu.active_view == "help", "Guia de Controles & Pilotagem abre corretamente")

	# Teste de responsividade em 844x390 e 390x844
	for vp_size in [Vector2(844, 390), Vector2(390, 844)]:
		gar_menu.size = vp_size
		gar_menu.switch_view("home")
		gar_menu.relayout(vp_size)
		await _frames(2)
		check(gar_menu._view_root != null, "Home constrói em %.0fx%.0f" % [vp_size.x, vp_size.y])
		gar_menu.switch_view("cars")
		gar_menu.relayout(vp_size)
		await _frames(2)
		check(gar_menu._view_root != null, "Carros constrói em %.0fx%.0f" % [vp_size.x, vp_size.y])

	# DR/SR check
	var dr_sr := LmuMenu.compute_driver_rating("sim")
	check(dr_sr.has("dr") and dr_sr.has("sr"), "compute_driver_rating retorna DR (%s) e SR (%s)" % [dr_sr.get("dr", "?"), dr_sr.get("sr", "?")])

	gar_menu.queue_free()
	gar_layer.queue_free()
	await _frames(2)

	print("--- 4. PauseMenu (Context.PAUSE) e sinais ---")
	var pmenu := PauseMenu.new()
	root.add_child(pmenu)
	await _frames(1)
	pmenu.open("Davi", "Leve", 0.5, {"abs": true, "tc": true, "auto": false}, "padrao", true, false, "sim", "barra", "corvette-c6r-gt3")
	await _frames(2)
	check(pmenu.is_open and pmenu.visible, "PauseMenu abre e fica visível")
	check(pmenu.lmu_menu.context == LmuMenu.Context.PAUSE, "PauseMenu usa LmuMenu em Context.PAUSE")
	check(pmenu.lmu_menu._backdrop.visible, "PAUSE exibe backdrop sólido completo")
	check(pmenu.lmu_menu._backdrop.size == vp_exp and pmenu.lmu_menu._root_vbox.size.x == vp_exp.x, "PauseMenu preenche toda a viewport mesmo após nascer oculto (%s vs %s)" % [str(pmenu.lmu_menu._backdrop.size), str(vp_exp)])

	var sig_hits := {"resumed": false, "restart": false, "garage": false, "hide_touch": false}
	pmenu.resumed.connect(func(): sig_hits.resumed = true)
	pmenu.restart_requested.connect(func(): sig_hits.restart = true)
	pmenu.garage.connect(func(): sig_hits.garage = true)
	pmenu.hide_touch_changed.connect(func(h: bool): sig_hits.hide_touch = h)

	pmenu.lmu_menu.resumed.emit()
	pmenu.lmu_menu.restart_requested.emit()
	pmenu.lmu_menu.garage_requested.emit()
	pmenu.lmu_menu.hide_touch_changed.emit(true)
	check(sig_hits.resumed and sig_hits.restart and sig_hits.garage and sig_hits.hide_touch, "PauseMenu repassa sinais resumed, restart_requested, garage e hide_touch_changed")

	pmenu.open("Davi", "Leve", 0.5, {"abs": true, "tc": true, "auto": false}, "padrao", true, true, "sim", "barra")
	await _frames(1)
	check(pmenu.lmu_menu.active_view == "settings" and pmenu.lmu_menu.active_settings_tab == "driver", "focus_nick=true abre diretamente Configurações -> Piloto")
	check(pmenu.handle_back() and pmenu.lmu_menu.active_view == "home", "handle_back() volta da sub-tela para Home antes de fechar")
	check(not pmenu.handle_back(), "handle_back() na Home retorna false para main.gd fechar o menu")
	pmenu.update_fps(60)
	check(pmenu.lmu_menu.live_fps == 60, "update_fps alimenta o LmuMenu ao vivo")
	pmenu.close()
	check(not pmenu.is_open and not pmenu.visible, "PauseMenu fecha corretamente")
	pmenu.queue_free()

	print("--- 5. Preferência hide_touch_controls e bloqueio no InputReader ---")
	Game.set_hide_touch_controls(true)
	check(Game.is_hide_touch_controls(), "hide_touch_controls salvo e lido em user://jogo.cfg")

	var tc := TouchControls.new()
	root.add_child(tc)
	await _frames(1)
	tc.manual_hide = true
	tc.sync_visibility(true)
	check(not tc.visible and tc.is_effectively_hidden(), "TouchControls fica oculto quando manual_hide=true")
	tc.manual_hide = false
	tc.gamepad_connected = true
	check(tc.is_effectively_hidden(), "TouchControls reporta oculto quando gamepad físico está conectado")
	tc.queue_free()

	var ir := InputReader.new()
	ir.touch = true
	ir.touch_mode = "padrao"
	ir.touch_hidden = true
	ir.touch_axes = {"steer": 0.9, "gas": 1.0, "brake": 0.0}
	ir.filter(0.1, 20.0, {"left": false, "right": false, "gas": false, "brake": false, "up": false, "down": false, "pad": null})
	check(is_zero_approx(ir.steer) and is_zero_approx(ir.throttle) and ir.source == "teclado", "InputReader ignora toque quando touch_hidden=true")

	var ir_pad := InputReader.new()
	ir_pad.touch = true
	ir_pad.touch_mode = "padrao"
	ir_pad.touch_axes = {"steer": 0.9, "gas": 1.0, "brake": 0.0}
	ir_pad.filter(0.1, 20.0, {"left": false, "right": false, "gas": false, "brake": false, "up": false, "down": false, "pad": {"x": 0.0, "rt": 0.0, "lt": 0.0, "up": false, "down": false, "reset": false}})
	check(is_zero_approx(ir_pad.steer) and is_zero_approx(ir_pad.throttle), "InputReader ignora toque proporcional quando controle físico está conectado")

	# Restaura configurações originais
	Game.save_car(orig_car)
	Game.set_mode(orig_mode)
	Game.set_hide_touch_controls(orig_hide_touch)
	Records.save_nick(orig_nick)

	await _frames(2)
	print("\n" + ("LMU Menu UI (Entrega 1): TUDO OK" if ok else "HOUVE FALHA NOS TESTES LMU MENU"))
	quit(0 if ok else 1)
