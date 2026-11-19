# Teste automatizado: horário nas pistas, shaders noturnos e faróis nos 13 carros.
# uso: godot --headless --path . --script res://scripts/tests/horario_e_farois.gd
extends SceneTree

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[OK] ", msg)
	else:
		_failures += 1
		printerr("[FALHA] ", msg)


func _init() -> void:
	_test_time_resolution_and_persistence()
	_test_shaders_and_surroundings()
	_test_car_headlights_all_13()

	if _failures == 0:
		print("\nTODOS OS TESTES PASSARAM (horario_e_farois.gd)")
	else:
		printerr("\n%d FALHA(S) em horario_e_farois.gd" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_time_resolution_and_persistence() -> void:
	var prev := Game.get_time_of_day_setting()
	Game.set_time_of_day("auto")
	_check(Game.get_time_of_day_setting() == "auto", "Persistência de video/horario = 'auto'")

	_check(Game.resolve_time_of_day(6) == "manha", "Hora 06:00 -> manha")
	_check(Game.resolve_time_of_day(11) == "manha", "Hora 11:00 -> manha")
	_check(Game.resolve_time_of_day(12) == "tarde", "Hora 12:00 -> tarde")
	_check(Game.resolve_time_of_day(16) == "tarde", "Hora 16:00 -> tarde")
	_check(Game.resolve_time_of_day(17) == "por_do_sol", "Hora 17:00 -> por_do_sol")
	_check(Game.resolve_time_of_day(18) == "por_do_sol", "Hora 18:00 -> por_do_sol")
	_check(Game.resolve_time_of_day(19) == "noite", "Hora 19:00 -> noite")
	_check(Game.resolve_time_of_day(2) == "noite", "Hora 02:00 -> noite")

	Game.set_time_of_day("noite")
	_check(Game.get_time_of_day_setting() == "noite", "Persistência de video/horario = 'noite'")
	_check(Game.resolve_time_of_day(14) == "noite", "Preset fixo 'noite' ignora relógio 14:00")

	Game.set_time_of_day(prev)


func _test_shaders_and_surroundings() -> void:
	var tv := TrackView.new()
	tv.manual_setup = true
	tv.build_scene()
	tv.build_surroundings()
	get_root().add_child(tv)

	tv.set_night_amount(1.0, Color(0.28, 0.34, 0.52), 0.18)
	var checked_asfalto := false
	for mat in tv._shader_mats:
		if mat and mat.resource_name == "asfalto":
			_check(is_equal_approx(float(mat.get_shader_parameter("night_amount")), 1.0), "Shader asfalto recebe night_amount = 1.0")
			checked_asfalto = true
			break
	_check(checked_asfalto, "ShaderMaterial 'asfalto' encontrado em TrackView")

	if tv.surroundings and tv.surroundings._torre_mat:
		_check(is_equal_approx(float(tv.surroundings._torre_mat.get_shader_parameter("night_amount")), 1.0), "Shader torre recebe night_amount = 1.0")
	if tv.surroundings and tv.surroundings._horizonte_mat:
		_check(is_equal_approx(float(tv.surroundings._horizonte_mat.get_shader_parameter("brightness")), 0.18), "Shader horizonte recebe brightness = 0.18")

	tv.queue_free()


func _test_car_headlights_all_13() -> void:
	var cars := Game.get_cars_list()
	_check(cars.size() == 13, "13 carros listados em data/cars.json (encontrados: %d)" % cars.size())

	for c in cars:
		var cid := String(c.id)
		var cv := CarView.new(cid, false, false)
		_check(cv._beam_mesh != null, "%s: malha leve de feixe criada" % cid)
		_check(cv._spot_lights.size() == 2, "%s: 2 SpotLight3D criados" % cid)
		_check(not cv._beam_mesh.visible and not cv._spot_lights[0].visible, "%s: feixe inicia desligado" % cid)

		# Modo Leve/Mínimo: malha aditiva visível, SpotLight3D oculto
		cv.beam_spotlight_enabled = false
		cv.headlights_on = true
		_check(cv._beam_mesh.visible and not cv._spot_lights[0].visible, "%s: preset Leve usa malha aditiva (0 ms)" % cid)

		# Modo Médio/Extremo: 2 SpotLight3D sem sombra visíveis, malha oculta
		cv.beam_spotlight_enabled = true
		_check(not cv._beam_mesh.visible and cv._spot_lights[0].visible and not cv._spot_lights[0].shadow_enabled, "%s: preset Médio/Extremo usa SpotLight3D sem sombra" % cid)

		# Garagem / bots: beam_enabled = false oculta qualquer feixe
		cv.beam_enabled = false
		_check(not cv._beam_mesh.visible and not cv._spot_lights[0].visible, "%s: beam_enabled=false oculta feixes" % cid)

		# Freio aceso mesmo de dia
		cv.headlights_on = false
		cv.brake_lights_on = true
		var any_emissive := false
		for entry in cv._light_entries:
			var bm := entry.mat as BaseMaterial3D
			if bm and bm.emission_enabled:
				any_emissive = true
				break
		if cv._light_entries.size() > 0:
			_check(any_emissive, "%s: materiais de luz (%d) ativam emissivo" % [cid, cv._light_entries.size()])
		cv.free()
