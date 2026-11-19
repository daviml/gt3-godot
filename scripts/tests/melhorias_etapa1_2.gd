# Teste automatizado das Etapas 1 e 2 do PLANO-MELHORIA-GERAL.md:
# - Mixer de 4 canais (Master, Motor, Pneus/Superfície, Efeitos/UI) em Game + AudioServer
# - Blip de redução de marcha encorpado no CarAudio
# - GhostCar: gravação, salvamento, carregamento, interpolação e delta ao vivo na Volta 1 (Ghost + Garage 61)
extends SceneTree

var fails := 0


func ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   %s" % msg)
	else:
		print("  ERRO %s" % msg)
		fails += 1


func _init() -> void:
	print("--- 1. Mixer de Áudio 4 Canais ---")
	var prev_master := Game.get_audio_volume("master")
	var prev_engine := Game.get_audio_volume("engine")
	var prev_tires := Game.get_audio_volume("tires")
	var prev_fx := Game.get_audio_volume("fx")

	var tr := Track.new("res://data/track/track.json")
	var car_data := Game.get_car_data("bmw-m4-gt3")
	var car := Car.new(tr, car_data.params)
	var audio := CarAudio.new(car, "bmw-m4-gt3")
	root.add_child(audio)

	Game.set_audio_volume("engine", 0.5)
	Game.set_audio_volume("tires", 0.25)
	Game.set_audio_volume("fx", 0.0)
	ok(is_equal_approx(Game.get_audio_volume("engine"), 0.5), "vol_motor persistido em 0.50")
	ok(is_equal_approx(Game.get_audio_volume("tires"), 0.25), "vol_pneus persistido em 0.25")
	ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("FX")), "bus FX mutada quando vol_fx = 0.0")
	var eng_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine"))
	ok(absf(eng_db - linear_to_db(0.5)) < 0.05, "bus Engine recebeu %.2f dB" % eng_db)
	var tires_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Tires"))
	var surf_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Surface"))
	ok(absf(tires_db - surf_db) < 0.05 and absf(tires_db - linear_to_db(0.25)) < 0.05, "buses Tires e Surface sincronizadas em %.2f dB" % tires_db)

	# Restaura volumes anteriores
	Game.set_audio_volume("master", prev_master)
	Game.set_audio_volume("engine", prev_engine)
	Game.set_audio_volume("tires", prev_tires)
	Game.set_audio_volume("fx", prev_fx)

	print("--- 2. Blip de Redução de Marchas (CarAudio) ---")
	car.gear = 4
	car.rpm = 6200.0
	car.throttle_out = 0.0
	for _i in 15:
		audio.update(0.016)
	car.gear = 3
	car.shift_count += 1
	car.rpm = 7200.0
	for _i in 4:
		audio.update(0.016)
	ok(audio.downshift_blip_timer > 0.12, "downshift ativa downshift_blip_timer (%.3fs)" % audio.downshift_blip_timer)
	ok(audio.filter_cutoff > 2500.0 and audio.filter_cutoff < 4000.0, "filtro do blip permanece encorpado/médio-grave (%.0f Hz)" % audio.filter_cutoff)

	print("--- 3. GhostCar + Delta na Volta 1 (Garage 61 + PB Salvo) ---")
	var timer := LapTimer.new(tr)
	var ghost := GhostCar.new()
	root.add_child(ghost)
	# Usa modo de teste isolado para não sobrescrever ghost real do usuário
	ghost.setup("interlagos", "audi-r8-lms-gt3", "_test_ghost", timer, false)
	var test_path := ghost.ghost_path()
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
		ghost.setup("interlagos", "audi-r8-lms-gt3", "_test_ghost", timer, false)

	ok(timer.ref_trace.size() > 100 and not is_nan(timer.ref_time), "LapTimer carregou referência Garage 61 na Volta 1 (ref=%.2fs)" % timer.ref_time)

	# Simula gravação de 20 quadros e conclusão de volta válida
	timer.current = 0.0
	for k in 20:
		timer.current = float(k) * 0.1
		car.pos = Vector3(float(k) * 5.0, 0.5, -float(k) * 10.0)
		car.rot = Quaternion(Vector3.UP, float(k) * 0.02)
		ghost.update_frame(car, timer)

	var lap := LapTimer.Lap.new()
	lap.time = 92.5
	lap.valid = true
	lap.sectors = [30.0, 31.0, 31.5]
	lap.trace = PackedFloat32Array([0.0, 0.5, 1.0, 1.5])
	var saved := ghost.on_lap_completed(lap, timer)
	ok(saved, "on_lap_completed salvou novo PB do ghost")
	ok(FileAccess.file_exists(test_path), "arquivo de ghost gravado em user://ghosts/")

	# Recarrega em nova instância e testa interpolação
	var timer2 := LapTimer.new(tr)
	var ghost2 := GhostCar.new()
	root.add_child(ghost2)
	ghost2.setup("interlagos", "audi-r8-lms-gt3", "_test_ghost", timer2, false)
	ok(ghost2.has_ghost() and absf(ghost2.best_time - 92.5) < 0.01, "ghost recarregado com best_time=%.2fs" % ghost2.best_time)
	ok(timer2.ref_trace.size() == 4 and absf(timer2.ref_time - 92.5) < 0.01, "trace do ghost alimentou LapTimer.ref_trace")
	var pose := ghost2.sample_pose(0.55)
	ok(not pose.is_empty() and absf((pose.pos as Vector3).x - 27.5) < 2.5, "interpolação de posição do ghost consistente (%s)" % str(pose.get("pos", Vector3.ZERO)))

	# Limpa arquivo de teste
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))

	print("--- 4. Disco de Freio Incandescente + Setup Brake Bias ---")
	var prev_bb := Game.get_brake_bias_offset("bmw-m4-gt3")
	Game.set_brake_bias_offset(0.03, "bmw-m4-gt3")
	car.set_brake_bias_offset(Game.get_brake_bias_offset("bmw-m4-gt3"))
	ok(absf(float(car.p.brake_bias) - (car.base_brake_bias + 0.03)) < 0.001, "brake_bias ajustado (+3%% -> %.2f)" % float(car.p.brake_bias))
	Game.set_brake_bias_offset(prev_bb, "bmw-m4-gt3")

	var cv := CarView.new("bmw-m4-gt3", false, false)
	root.add_child(cv)
	car.vel = Vector3(0.0, 0.0, -60.0)
	car.brake_out = 1.0
	for _i in 35:
		cv.update_from(car, 1.0, 0.033)
	ok(float(cv.brake_heat[0]) > 0.35 and float(cv.brake_heat[0]) > float(cv.brake_heat[2]), "discos dianteiros aquecem mais que traseiros na freada (F=%.2f R=%.2f)" % [float(cv.brake_heat[0]), float(cv.brake_heat[2])])
	cv.queue_free()

	audio.queue_free()
	ghost.queue_free()
	ghost2.queue_free()

	print("\nResultado Etapas 1-2: %s" % ("TUDO OK" if fails == 0 else "%d FALHA(S)" % fails))
	quit(0 if fails == 0 else 1)
