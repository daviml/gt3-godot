# Teste da Fase 2: cache LRU em Game, preload no Updater, LoadingScreen Garagem -> Pista e Pista -> Garagem.
# uso: godot --headless --path . --script res://scripts/tests/loading_fase2.gd
extends SceneTree

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _wait_until(pred: Callable, max_frames := 600) -> bool:
	for _i in max_frames:
		if pred.call():
			return true
		await process_frame
	return false


func _initialize() -> void:
	# teste de Interlagos: não depende da última pista escolhida no jogo (user://jogo.cfg)
	Game.track_id = Game.DEFAULT_TRACK
	run_tests.call_deferred()


func run_tests() -> void:
	print("--- 1. Testando Cache LRU de Carros (Game) ---")
	Game.clear_car_cache()
	var s1 := Game.load_car_scene("corvette-c6r-gt3")
	var s2 := Game.load_car_scene("bmw-m4-gt3")
	var s3 := Game.load_car_scene("audi-r8-lms-gt3")
	check(s1 != null and s2 != null and s3 != null, "3 PackedScenes carregados no cache")
	check(Game.get_cached_car_scene("corvette-c6r-gt3") == s1, "LRU touch no primeiro carro mantém ele no cache")
	var s4 := Game.load_car_scene("ferrari-488-gt3")
	check(s4 != null, "4o carro carregado")
	check(Game.get_cached_car_scene("bmw-m4-gt3") == null, "carro menos usado (bmw-m4-gt3) foi despejado pelo LRU (limite desktop=3)")
	check(Game.get_cached_car_scene("corvette-c6r-gt3") == s1, "carro mais recentemente tocado (corvette-c6r-gt3) permaneceu")
	check(CarAudio.get_preload_paths("corvette-c6r-gt3").size() >= 15, "CarAudio.get_preload_paths retorna FX + loops do motor")

	print("\n--- 2. Testando Updater (preload inicial + entrada na Garagem) ---")
	Game.clear_car_cache()
	Game.car_id = "corvette-c6r-gt3"
	var up_scene := load("res://scenes/updater.tscn") as PackedScene
	var up := up_scene.instantiate()
	root.add_child(up)
	current_scene = up
	var entered_garagem := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/garagem.tscn", 900)
	check(entered_garagem, "Updater entrou na garagem.tscn")
	check(Game.get_cached_car_scene("corvette-c6r-gt3") != null, "Updater pré-carregou o carro inicial no cache de Game")
	var garagem := current_scene
	check(garagem.view != null and garagem.view.id == "corvette-c6r-gt3", "Garagem exibiu carro inicial")

	print("\n--- 3. Testando Garagem -> LoadingScreen -> Pista ---")
	garagem._drive()
	var entered_loading := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/loading.tscn", 120)
	check(entered_loading, "Garagem._drive() abriu scenes/loading.tscn")
	var entered_main := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn", 1800)
	check(entered_main, "LoadingScreen completou e ativou scenes/main.tscn")
	var main := current_scene
	check(main.track != null and main.track_view != null, "Track e TrackView montados progressivamente")
	check(main.car_view != null and main.car_audio != null and main.hud != null, "CarView, CarAudio e HUD montados")
	check(main.is_physics_processing() and main.is_processing(), "Física e _process reativados após warmup")
	check(not main.car_audio.is_audio_paused, "CarAudio despausado após warmup")

	print("\n--- 4. Testando Pista -> LoadingScreen -> Garagem ---")
	main._to_garage()
	var back_loading := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/loading.tscn", 120)
	check(back_loading, "Main._to_garage() abriu scenes/loading.tscn")
	var back_garagem := await _wait_until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/garagem.tscn", 900)
	check(back_garagem, "LoadingScreen voltou para scenes/garagem.tscn")
	var garagem2 := current_scene
	check(garagem2.view != null and garagem2.view.id == "corvette-c6r-gt3", "Garagem restaurada com o carro selecionado")
	check(garagem2.is_processing() and garagem2.is_processing_unhandled_input(), "Garagem responsiva após warmup")

	print("\n--- 5. Testando Instanciação Direta de main.tscn e Timeout do Updater ---")
	garagem2.queue_free()
	current_scene = null
	await _frames(3)
	var up_check := (load("res://scenes/updater.tscn") as PackedScene).instantiate()
	root.add_child(up_check)
	check(is_equal_approx(up_check.http_version.timeout, 1.5), "Updater timeout reduzido para 1.5s")
	up_check.queue_free()
	var direct_main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(direct_main)
	check(direct_main.track != null and direct_main.track_view != null and direct_main.car_view != null, "main.tscn direto funciona normalmente")
	direct_main.queue_free()
	Game.clear_car_cache()
	await _frames(3)

	print("\nFase 2 (Loading & Cache): " + ("TUDO OK" if ok else "FALHOU"))
	quit(0 if ok else 1)
