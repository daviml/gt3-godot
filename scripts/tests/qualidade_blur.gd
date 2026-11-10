# Etapa 8: Desfoque de velocidade e Presets Reais (Leve / Médio / Extremo)
# uso: godot --headless --path . --script res://scripts/tests/qualidade_blur.gd
extends SceneTree

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _initialize() -> void:
	print("--- Testando Desfoque de Velocidade (SpeedBlur) ---")

	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)

	var track := Track.new("res://data/track/track.json")
	var ground := FlatGround.new()
	var car := Car.load_car(ground, "porsche-992-gt3r")

	var blur := SpeedBlur.new()
	root.add_child(blur)

	check(blur.rect != null and blur.mat != null, "SpeedBlur inicializado com ColorRect e ShaderMaterial")
	check(not blur.rect.visible, "desfoque começa invisível")

	# Teste a baixa velocidade (< 90 km/h)
	car.vel = Vector3(0, 0, -20.0)  # ~72 km/h
	blur.update(cam, car, 0, 0.016)
	check(not blur.rect.visible, "a 72 km/h (< 90) fica invisível")

	# Teste a média velocidade (~175 km/h, meio da rampa 90..260)
	car.vel = Vector3(0, 0, -48.6)  # ~175 km/h
	# Posiciona câmera atrás do carro (modo perseguição)
	cam.global_position = car.pos + Vector3(0, 1.85, 6.8)
	cam.look_at(car.pos + Vector3.UP * 0.75, Vector3.UP)
	blur.update(cam, car, 0, 0.016)
	check(blur.rect.visible, "a 175 km/h fica visível")
	var s_mid: float = blur.mat.get_shader_parameter("strength")
	check(s_mid > 0.35 and s_mid < 0.65, "intensidade intermediária a 175 km/h: %.3f" % s_mid)

	# Confere máscara do carro projetada na tela no modo perseguição
	var cr: Vector4 = blur.mat.get_shader_parameter("car_rect")
	check(cr.z > cr.x and cr.w > cr.y, "caixa do carro delimitada na tela: (%.2f, %.2f) a (%.2f, %.2f)" % [cr.x, cr.y, cr.z, cr.w])

	# Teste a alta velocidade (>= 260 km/h)
	car.vel = Vector3(0, 0, -80.0)  # 288 km/h
	blur.update(cam, car, 0, 0.016)
	var s_high: float = blur.mat.get_shader_parameter("strength")
	check(absf(s_high - 1.0) < 1e-4, "intensidade máxima a 288 km/h: %.3f" % s_high)

	# Teste na câmera de capô (modo 1): sem máscara do carro
	blur.update(cam, car, 1, 0.016)
	var cr_hood: Vector4 = blur.mat.get_shader_parameter("car_rect")
	check(cr_hood == Vector4.ZERO, "câmera de capô não mascara o carro")

	# Desativado
	blur.enabled = false
	blur.update(cam, car, 0, 0.016)
	check(not blur.rect.visible, "desabilitado força visibilidade = false")

	print("\n--- Testando 3 Presets de Qualidade em Main ---")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	check(main_scene != null, "cena main.tscn carregada")
	var main = main_scene.instantiate()
	root.add_child(main)

	# Leve
	main._apply_quality("Leve")
	check(not main.env.ssao_enabled, "Leve: SSAO desativado")
	check(not main.env.ssil_enabled, "Leve: SSIL desativado")
	check(not main.env.ssr_enabled, "Leve: SSR desativado")
	check(main.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Leve: sombras em 2 splits")
	check(main.sun.directional_shadow_max_distance <= 90.0, "Leve: distância de sombra curta (80 m)")
	check(not main.speed_blur.enabled, "Leve: speed blur desativado no mobile")
	if main.track_view and main.track_view.surroundings:
		check(main.track_view.surroundings.detail_level == 0, "Leve: orçamento de arredores no nível 0 (torcida 220 m)")

	# Médio
	main._apply_quality("Médio")
	check(main.env.ssao_enabled, "Médio: SSAO ativado")
	check(absf(main.env.ssao_intensity - 1.0) < 0.05, "Médio: SSAO intensidade 1.0")
	check(not main.env.ssil_enabled, "Médio: SSIL desativado")
	check(not main.env.ssr_enabled, "Médio: SSR desativado")
	check(main.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Médio: sombras em 4 splits")
	check(main.speed_blur.enabled and absf(main.speed_blur.max_strength - 0.8) < 1e-4, "Médio: speed blur ativado (max 0.8)")
	if main.track_view and main.track_view.surroundings:
		check(main.track_view.surroundings.detail_level == 1, "Médio: orçamento de arredores no nível 1 (torcida 500 m)")

	# Extremo
	main._apply_quality("Extremo")
	check(main.env.ssao_enabled and absf(main.env.ssao_intensity - 1.6) < 0.05, "Extremo: SSAO intensidade 1.6")
	check(main.env.ssil_enabled, "Extremo: SSIL ativado")
	check(main.env.ssr_enabled and main.env.ssr_max_steps == 48, "Extremo: SSR ativado (48 steps)")
	check(main.sun.directional_shadow_max_distance >= 180.0, "Extremo: sombra longa (180 m)")
	check(main.speed_blur.enabled and absf(main.speed_blur.max_strength - 1.0) < 1e-4, "Extremo: speed blur ativado (max 1.0)")
	if main.track_view and main.track_view.surroundings:
		check(main.track_view.surroundings.detail_level == 2, "Extremo: orçamento de arredores no nível 2 (torcida 900 m)")

	print("\nQualidade e Blur: " + ("TUDO OK" if ok else "FALHOU"))
	quit(0 if ok else 1)
