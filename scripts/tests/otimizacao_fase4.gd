# Teste da Fase 4: otimizações de GPU/materiais/LOD no Mínimo, HUD sem alocações, física e áudio.
# uso: godot --headless --path . --script res://scripts/tests/otimizacao_fase4.gd
extends SceneTree

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _initialize() -> void:
	# teste de Interlagos: não depende da última pista escolhida no jogo (user://jogo.cfg)
	Game.track_id = Game.DEFAULT_TRACK
	run_tests.call_deferred()


func run_tests() -> void:
	var orig_cfg := ConfigFile.new()
	var has_orig_quality := false
	var orig_quality := ""
	if orig_cfg.load(Game.CFG) == OK and orig_cfg.has_section_key("video", "qualidade"):
		has_orig_quality = true
		orig_quality = String(orig_cfg.get_value("video", "qualidade", ""))

	print("--- 1. GPU, LOD, Shaders, Materiais e Culling no Mínimo (4.1) ---")
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await _frames(2)

	main._apply_quality("Mínimo")
	var vp := main.get_viewport()
	check(is_equal_approx(vp.mesh_lod_threshold, 6.0), "Mínimo: mesh_lod_threshold = 6.0")
	check(main.env.sky.radiance_size == Sky.RADIANCE_SIZE_64, "Mínimo: sky.radiance_size = RADIANCE_SIZE_64")
	check(main.car_view.simple_materials, "Mínimo: CarView.simple_materials ativado")
	check(main.car_view._mat_states.size() > 0, "CarView registrou materiais (%d)" % main.car_view._mat_states.size())
	var car_mats_simple := true
	var had_clearcoat := false
	for st in main.car_view._mat_states:
		var m: BaseMaterial3D = st.mat
		if bool(st.clearcoat):
			had_clearcoat = true
		if m.clearcoat_enabled or m.normal_enabled or m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			car_mats_simple = false
	check(had_clearcoat and car_mats_simple, "Mínimo: CarView desativa clearcoat, normal map e anisotrópico")

	check(main.track_view._base_mats.size() > 0, "TrackView registrou BaseMaterial3Ds (%d)" % main.track_view._base_mats.size())
	var track_mats_simple := true
	for st in main.track_view._base_mats:
		var m: BaseMaterial3D = st.mat
		if m.normal_enabled or m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			track_mats_simple = false
	check(track_mats_simple, "Mínimo: TrackView desativa normal map e anisotrópico")

	var tree_fast_ok := false
	for sm in main.track_view._shader_mats:
		if sm and sm.resource_name == "impostor":
			tree_fast_ok = bool(sm.get_shader_parameter("fast_mode"))
	check(tree_fast_ok, "Mínimo: impostor.gdshader com fast_mode = true")

	var tree_hidden_ok := true
	var tree_count := 0
	for c in main.track_view.get_children():
		if c is MultiMeshInstance3D and SurroundingsView._is_tree(c):
			tree_count += 1
			if c.visible:
				tree_hidden_ok = false
	check(tree_count > 0 and tree_hidden_ok, "Mínimo: árvores ocultadas (visible = false)")

	var sec_cull_ok := true
	var sec_nonshadow_count := 0
	for entry in main.track_view._cull_meshes:
		var mi: MeshInstance3D = entry.mi
		if not bool(entry.shadow):
			sec_nonshadow_count += 1
		if not is_equal_approx(mi.visibility_range_end, 300.0):
			sec_cull_ok = false
	check(sec_nonshadow_count > 0 and sec_cull_ok, "Mínimo: malhas secundárias (inclusive %d sem sombra) cortadas em 300 m" % sec_nonshadow_count)

	# Testa escala HiDPI/4K
	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(3840, 2160)
	var scale_4k := Game.get_minimal_3d_scale(sub_vp)
	check(scale_4k < 0.40 and is_equal_approx(scale_4k * 2160.0, 720.0), "Mínimo em 4K limita resolução vertical efetiva para ~720p (escala %.3f)" % scale_4k)
	sub_vp.size = Vector2i(1920, 1080)
	check(is_equal_approx(Game.get_minimal_3d_scale(sub_vp), 0.65), "Mínimo em 1080p mantém escala 0.65")
	sub_vp.free()

	# Alternância para Leve e Extremo deve restaurar tudo corretamente
	main._apply_quality("Leve")
	check(is_equal_approx(vp.mesh_lod_threshold, 3.0), "Leve: mesh_lod_threshold = 3.0")
	check(main.env.sky.radiance_size == Sky.RADIANCE_SIZE_128, "Leve: sky.radiance_size = RADIANCE_SIZE_128")
	var tree_fast_leve := false
	for sm in main.track_view._shader_mats:
		if sm and sm.resource_name == "impostor":
			tree_fast_leve = bool(sm.get_shader_parameter("fast_mode"))
	check(tree_fast_leve, "Leve: impostor.gdshader mantém fast_mode = true")

	main._apply_quality("Extremo")
	check(is_equal_approx(vp.mesh_lod_threshold, 1.0), "Extremo: mesh_lod_threshold = 1.0")
	check(main.env.sky.radiance_size == Sky.RADIANCE_SIZE_256, "Extremo: sky.radiance_size = RADIANCE_SIZE_256")
	check(not main.car_view.simple_materials, "Extremo: CarView.simple_materials desativado")
	var clearcoat_restored := false
	for st in main.car_view._mat_states:
		if (st.mat as BaseMaterial3D).clearcoat_enabled:
			clearcoat_restored = true
	check(clearcoat_restored, "Extremo: CarView restaura clearcoat da pintura")
	var tree_fast_ext := true
	for sm in main.track_view._shader_mats:
		if sm and sm.resource_name == "impostor":
			tree_fast_ext = bool(sm.get_shader_parameter("fast_mode"))
	check(not tree_fast_ext, "Extremo: impostor.gdshader volta para fast_mode = false")

	print("\n--- 2. HUD sem alocações por quadro e minimapa em cache (4.2) ---")
	var hud: Hud = main.hud
	check(hud._fps_sb != null and hud._tyres_panel_sb != null and hud._tyres_body_sb != null and hud._box_sb != null,
		"Hud: StyleBoxFlats pré-alocados")
	check(hud._tyre_sbs.size() == 4, "Hud: 4 StyleBoxFlats pré-alocados para os pneus")
	check(hud._map_draw_pts.size() == hud._map_pts.size() and hud._map_draw_pts.size() > 500,
		"Hud: pontos do minimapa pré-calculados em _layout() (%d pts)" % hud._map_draw_pts.size())
	main._apply_quality("Mínimo")
	check(hud.quality_level == 0, "Hud recebeu quality_level = 0 no Mínimo")
	hud._redraw_t = 0.0
	hud.update(0.01, 0.5, 0.0)
	check(hud._redraw_t > 0.0, "Hud limita redesenho a 30 Hz no Mínimo (não zera em dt=0.01s)")
	hud.update(0.03, 0.5, 0.0)
	check(is_equal_approx(hud._redraw_t, 0.0), "Hud dispara redesenho quando acumula >= 1/30 s")
	# Exercita também o modo dash_on (Porsche câmera de capô) para garantir _box sem alocação
	hud.dash_on = true
	hud.queue_redraw()
	await _frames(2)
	check(true, "Hud desenhou modo padrão e dash_on sem erros")

	print("\n--- 3. Física e Track.nearest/locate (4.3) ---")
	main._apply_quality("Mínimo")
	check(main.car.max_sub_steps == 4, "Mínimo: Car.max_sub_steps = 4 (240 Hz) mesmo no Desktop")
	check(Engine.max_physics_steps_per_frame == 2, "Mínimo: Engine.max_physics_steps_per_frame = 2")
	main._apply_quality("Extremo")
	check(main.car.max_sub_steps == 8, "Extremo: Car.max_sub_steps = 8 no Desktop")
	check(Engine.max_physics_steps_per_frame == 4, "Extremo: Engine.max_physics_steps_per_frame = 4")
	check(Track.WIN_NEAR == 2, "Track.WIN_NEAR reduzido para 2")

	var tr: Track = main.track
	var nearest_exact := true
	for idx in range(0, tr.n, 37):
		var test_p := tr.P[idx] + tr.R[idx] * 2.5 + tr.T[idx] * 1.1
		var got := tr.nearest(test_p, idx)
		var expected := tr.nearest(test_p, -1)
		# Nota: nearest(p, -1) tem termo 4*dy^2, mas no plano local da pista o mais próximo XZ coincide
		var d_got := Vector2(tr.P[got].x - test_p.x, tr.P[got].z - test_p.z).length_squared()
		var d_exp := Vector2(tr.P[expected].x - test_p.x, tr.P[expected].z - test_p.z).length_squared()
		if d_got > d_exp + 1e-4:
			nearest_exact = false
	check(nearest_exact, "Track.nearest com janela curta encontra exatamente a amostra mais próxima")

	print("\n--- 4. CarAudio pausa loops silenciosos (4.3) ---")
	var ca: CarAudio = main.car_audio
	ca.set_paused(false)
	main.car.rpm = 1200.0
	main.car.throttle_out = 0.0
	main.car.vel = Vector3.ZERO
	for w in main.car.wheels:
		w.contact = true
		w.surface = Ground.ASPHALT
		w.kappa = 0.0
		w.alpha = 0.0
	for _i in 30:
		ca.update(0.05)
	var unpaused_engine := 0
	var paused_engine := 0
	for s in ca.engine_loops:
		if (s.player as AudioStreamPlayer).stream_paused:
			paused_engine += 1
		else:
			unpaused_engine += 1
	check(unpaused_engine <= 3 and paused_engine >= 4,
		"CarAudio pausa loops de motor fora da janela ativa (%d ativos, %d pausados)" % [unpaused_engine, paused_engine])
	check(ca.grass_player.stream_paused and ca.gravel_player.stream_paused and ca.tyre_player.stream_paused and ca.wind_player.stream_paused,
		"CarAudio pausa loops de grama, brita, pneu e vento quando em silêncio")

	# Simula entrar na grama e depois voltar para o asfalto
	main.car.vel = Vector3(0, 0, -25.0)
	for w in main.car.wheels:
		w.surface = Ground.GRASS
	for _i in 5:
		ca.update(0.03)
	check(not ca.grass_player.stream_paused and ca.grass_gain > 0.05, "CarAudio despausa grass_player ao andar na grama")
	for w in main.car.wheels:
		w.surface = Ground.ASPHALT
	main.car.vel = Vector3.ZERO
	for _i in 40:
		ca.update(0.05)
	check(ca.grass_player.stream_paused and ca.grass_gain == 0.0, "CarAudio repausa grass_player quando ganho cai para <= 0.001")

	# Verifica que set_paused(false) não despausa loops silenciosos
	ca.set_paused(true)
	ca.set_paused(false)
	check(ca.grass_player.stream_paused and ca.gravel_player.stream_paused,
		"set_paused(false) mantém loops silenciosos pausados")

	main.queue_free()
	if has_orig_quality:
		Game.set_setting("video", "qualidade", orig_quality)
	else:
		Game.erase_setting("video", "qualidade")
	await _frames(2)

	print("\nFase 4 (Otimização Mínimo): " + ("TUDO OK" if ok else "FALHOU"))
	quit(0 if ok else 1)
