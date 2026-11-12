# Teste da Fase 3: garagem assíncrona (prefetch de vizinhos, debounce/cancelamento, spinner não-bloqueante,
# CarView enable_blur := false e respeito ao preset gráfico salvo em user://jogo.cfg).
# uso: godot --headless --path . --script res://scripts/tests/garagem_fase3.gd
extends SceneTree

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _wait_until(pred: Callable, max_frames := 900) -> bool:
	for _i in max_frames:
		if pred.call():
			return true
		await process_frame
	return false


func _count_ghosts(cv: CarView) -> int:
	var total := 0
	for list in cv.ghosts:
		total += (list as Array).size()
	return total


func _initialize() -> void:
	run_tests.call_deferred()


func run_tests() -> void:
	var had_saved_quality := ConfigFile.new().load(Game.CFG) == OK and ConfigFile.new().has_section_key("video", "qualidade")
	var orig_cfg := ConfigFile.new()
	var has_orig_quality := false
	var orig_quality := ""
	if orig_cfg.load(Game.CFG) == OK and orig_cfg.has_section_key("video", "qualidade"):
		has_orig_quality = true
		orig_quality = String(orig_cfg.get_value("video", "qualidade", ""))
	var orig_car := Game.car_id

	print("--- 1. Testando CarView enable_blur := false (3.3) ---")
	Game.clear_car_cache()
	var cv_no_blur := CarView.new("corvette-c6r-gt3")
	root.add_child(cv_no_blur)
	check(not cv_no_blur.blur_enabled, "CarView.new(id) inicia com blur_enabled = false por padrão")
	check(_count_ghosts(cv_no_blur) == 0, "CarView sem blur não instancia as 24 malhas ghosts")
	cv_no_blur.blur_enabled = true
	check(_count_ghosts(cv_no_blur) == 24, "Ligar blur_enabled depois cria os 24 ghosts sob demanda")
	cv_no_blur.blur_enabled = false
	var all_hidden := true
	for list in cv_no_blur.ghosts:
		for mi in list:
			if (mi as MeshInstance3D).visible:
				all_hidden = false
	check(all_hidden, "Desligar blur_enabled oculta todos os ghosts")
	cv_no_blur.queue_free()

	var cv_blur := CarView.new("corvette-c6r-gt3", true)
	root.add_child(cv_blur)
	check(cv_blur.blur_enabled and _count_ghosts(cv_blur) == 24, "CarView.new(id, true) instancia os 24 ghosts")
	cv_blur.queue_free()
	await _frames(2)

	print("\n--- 2. Testando Garagem respeitando preset gráfico em user://jogo.cfg (3.3) ---")
	var gar_scene := load("res://scenes/garagem.tscn") as PackedScene
	Game.car_id = "corvette-c6r-gt3"
	Game.load_car_scene("corvette-c6r-gt3")

	Game.set_setting("video", "qualidade", "Mínimo")
	var gar_min := gar_scene.instantiate()
	root.add_child(gar_min)
	check(not gar_min.studio_env.ssao_enabled and not gar_min.studio_env.ssr_enabled and not gar_min.studio_env.glow_enabled,
		"Garagem no preset Mínimo desliga SSAO/SSR/Glow")
	check(not gar_min.key_light.shadow_enabled, "Garagem no preset Mínimo desliga sombra da luz principal")
	check(gar_min.view != null and not gar_min.view.blur_enabled and _count_ghosts(gar_min.view) == 0,
		"Garagem instancia CarView sem ghosts de blur")
	gar_min.queue_free()
	await _frames(2)

	Game.set_setting("video", "qualidade", "Leve")
	var gar_leve := gar_scene.instantiate()
	root.add_child(gar_leve)
	check(not gar_leve.studio_env.ssao_enabled and not gar_leve.studio_env.ssr_enabled and not gar_leve.studio_env.glow_enabled,
		"Garagem no preset Leve desliga SSAO/SSR/Glow")
	check(gar_leve.key_light.shadow_enabled, "Garagem no preset Leve mantém sombra da luz principal")
	gar_leve.queue_free()
	await _frames(2)

	Game.set_setting("video", "qualidade", "Extremo")
	var gar_ext := gar_scene.instantiate()
	root.add_child(gar_ext)
	check(gar_ext.studio_env.ssao_enabled and gar_ext.studio_env.ssr_enabled and gar_ext.studio_env.glow_enabled,
		"Garagem no preset Extremo ativa SSAO/SSR/Glow")
	gar_ext.queue_free()
	await _frames(2)

	print("\n--- 3. Testando Pré-carregamento dos Vizinhos (3.1) ---")
	Game.clear_car_cache()
	Game.car_id = "corvette-c6r-gt3"
	Game.load_car_scene("corvette-c6r-gt3")
	var gar := gar_scene.instantiate()
	root.add_child(gar)
	current_scene = gar
	check(gar.view != null and gar.view.id == "corvette-c6r-gt3", "Carro inicial exibido imediatamente via cache")
	check(not gar.loading_overlay.visible, "Overlay de carregamento fica oculto quando o carro está em cache")

	var prev_id: String = gar.cars[gar.cars.size() - 1].id
	var next_id: String = gar.cars[1].id
	var prefetched := await _wait_until(func():
		return Game.has_cached_car_scene(next_id) and Game.has_cached_car_scene(prev_id), 900)
	check(prefetched, "Vizinhos (idx - 1 e idx + 1) pré-carregados assincronamente em segundo plano")
	check(Game.has_cached_car_scene("corvette-c6r-gt3"), "Carro atual permaneceu no cache LRU após prefetch dos vizinhos")

	gar._nav_dir = 1
	gar._show(gar.idx + 1)
	check(gar.view != null and gar.view.id == next_id, "Troca para o próximo carro foi instantânea (cache hit)")
	check(not gar.loading_overlay.visible, "Overlay permanece oculto em troca com cache hit")

	print("\n--- 4. Testando Troca Rápida + Spinner Não-Bloqueante (3.1 & 3.2) ---")
	# Limpa cache para forçar carga assíncrona em carros não-cacheados
	Game.clear_car_cache()
	var target_idx := 5
	var target_id: String = gar.cars[target_idx].id
	var skipped_id: String = gar.cars[3].id
	gar._nav_dir = 1
	gar._show(3)
	await _frames(1)
	gar._show(4)
	await _frames(1)
	gar._show(target_idx)

	check(gar.name_lbl.text == gar.cars[target_idx].name, "UI atualizou imediatamente para o carro final desejado")
	check(gar.loading_overlay.visible and gar.loading_lbl.text == "Carregando carro...",
		"Overlay/spinner discreto exibido durante carga assíncrona")
	check(gar.loading_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Overlay é não-bloqueante (MOUSE_FILTER_IGNORE mantém câmera/UI responsivas)")

	var final_loaded := await _wait_until(func():
		return gar.view != null and gar.view.id == target_id and not gar.loading_overlay.visible, 900)
	check(final_loaded, "Apenas o carro final (%s) foi montado e overlay sumiu ao concluir" % target_id)
	check(not Game.has_cached_car_scene(skipped_id), "Carro intermediário ignorado (%s) não poluiu o cache" % skipped_id)

	gar.queue_free()
	current_scene = null
	Game.clear_car_cache()
	Game.car_id = orig_car
	if has_orig_quality:
		Game.set_setting("video", "qualidade", orig_quality)
	else:
		Game.erase_setting("video", "qualidade")
	await _frames(3)

	print("\nFase 3 (Garagem Instantânea e Responsiva): " + ("TUDO OK" if ok else "FALHOU"))
	quit(0 if ok else 1)
