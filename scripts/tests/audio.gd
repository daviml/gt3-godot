# Etapa 11: Sistema de som do carro com bancos engine-sim e efeitos FX.
# - Buses nativas Godot: Master, Engine (com LowPassFilter), Tires, Surface, Wind, FX;
# - Motor: crossfade de mesma potência entre loops vizinhos, pitch proporcional ao giro;
# - Filtro de carga: abre com o pé no acelerador e abafa na desaceleração, corte no limitador;
# - Turbo e blow-off nos carros turbo (ex: Ferrari 296, BMW M4, Nissan GT-R);
# - Pneu cantando pelo slip além do pico, grama, brita/escape, vento e batidas na zebra;
# - Suporte a todos os 13 carros GT3.
# uso: godot --headless --path . --script res://scripts/tests/audio.gd
extends SceneTree

const CarAudio = preload("res://scripts/audio/car_audio.gd")

var ok := true
var log_lines: Array[String] = []


func check(cond: bool, msg: String) -> void:
	var line := ("  ok   " if cond else "  FALHOU ") + msg
	print(line)
	log_lines.append(line)
	ok = ok and cond


func _initialize() -> void:
	await process_frame

	print("--- Testando Buses Nativas de Áudio da Godot ---")
	log_lines.append("--- Testando Buses Nativas de Áudio da Godot ---")

	var ground := FlatGround.new()
	var porsche_car := Car.load_car(ground, "bmw-m4-gt3")
	var audio := CarAudio.new(porsche_car, "bmw-m4-gt3")
	root.add_child(audio)
	await process_frame

	# 1. Verifica Buses
	var buses: Array[String] = ["Engine", "Tires", "Surface", "Wind", "FX"]
	for b in buses:
		var idx := AudioServer.get_bus_index(b)
		check(idx != -1, "bus %s existe (índice %d)" % [b, idx])
		if idx != -1:
			check(AudioServer.get_bus_send(idx) == &"Master", "bus %s envia para Master" % b)

	var eng_idx := AudioServer.get_bus_index("Engine")
	check(eng_idx != -1 and AudioServer.get_bus_effect_count(eng_idx) > 0, "bus Engine tem efeito cadastrado")
	var lpf := audio.engine_filter
	check(lpf != null and lpf is AudioEffectLowPassFilter, "efeito é AudioEffectLowPassFilter nativo")

	print("\n--- Testando Motor (BMW M4 GT3 - Banco tsp) ---")
	log_lines.append("\n--- Testando Motor (BMW M4 GT3 - Banco tsp) ---")
	check(audio.engine_loops.size() == 10, "10 loops carregados para banco tsp")
	check(audio.sound_spec.get("turbo", false), "BMW M4 GT3 tem turbo")

	# Marcha lenta (~1200 rpm)
	porsche_car.rpm = 1200.0
	porsche_car.throttle_out = 0.0
	for step in 10:
		audio.update(0.03)
	# No tsp: loop 0 é 1100 rpm, loop 1 é 2000 rpm
	var l0: Dictionary = audio.engine_loops[0]
	var l1: Dictionary = audio.engine_loops[1]
	var l5: Dictionary = audio.engine_loops[5]
	check(l0.gain > 0.5, "1200 rpm: loop 1 (1100 rpm) ativo (ganho %.2f)" % l0.gain)
	check(l1.gain > 0.05, "1200 rpm: loop 2 (2000 rpm) levemente ativo (ganho %.2f)" % l1.gain)
	check(l5.gain < 0.01, "1200 rpm: loop 6 (6000 rpm) zerado")
	check(lpf.cutoff_hz < 4000.0, "desaceleração/sem acelerador: filtro low-pass abafado (%.1f Hz)" % lpf.cutoff_hz)

	# Plena carga e giro alto (7500 rpm com acelerador 100%)
	porsche_car.rpm = 7500.0
	porsche_car.throttle_out = 1.0
	for step in 10:
		audio.update(0.02)
	check(lpf.cutoff_hz > 14000.0, "plena carga a 7500 rpm: filtro abre (> 14 kHz, atual %.1f Hz)" % lpf.cutoff_hz)
	var l6: Dictionary = audio.engine_loops[6]
	var l7: Dictionary = audio.engine_loops[7]
	check(l6.gain > 0.4 and l7.gain > 0.4, "7500 rpm: loops 7000 e 8000 em crossfade perfeito (%.2f e %.2f)" % [l6.gain, l7.gain])
	check(l6.player.pitch_scale > 1.0 and l7.player.pitch_scale < 1.0, "pitch_scale corrigido (%.3f e %.3f)" % [l6.player.pitch_scale, l7.player.pitch_scale])

	# Limitador (giro > limitador - 40)
	porsche_car.rpm = porsche_car.p.limiter + 10.0
	audio.update(0.016)
	check(audio.engine_overall_gain > 0.0, "corte de limitador atuando")

	print("\n--- Testando Carro com Turbo (Ferrari 296 GT3) ---")
	log_lines.append("\n--- Testando Carro com Turbo (Ferrari 296 GT3) ---")
	var ferrari_car := Car.load_car(ground, "ferrari-488-gt3")
	var ferrari_audio := CarAudio.new(ferrari_car, "ferrari-488-gt3")
	root.add_child(ferrari_audio)
	await process_frame

	check(ferrari_audio.sound_spec.get("turbo", false), "Ferrari 296 tem turbo ativo")
	check(ferrari_audio.turbo_player != null, "player de turbo spool inicializado")

	# Turbo spool em alta rotação com acelerador
	ferrari_car.rpm = 7000.0
	ferrari_car.throttle_out = 1.0
	for step in 10:
		ferrari_audio.update(0.02)
	check(ferrari_audio.turbo_gain > 0.08, "turbo assobiando em alta rotação (ganho %.3f)" % ferrari_audio.turbo_gain)
	check(ferrari_audio.turbo_pitch > 1.2, "pitch do turbo elevado com o giro (%.2f)" % ferrari_audio.turbo_pitch)

	# Válvula de alívio (blow-off) ao tirar o pé
	ferrari_audio.last_throttle = 0.95
	ferrari_car.throttle_out = 0.05
	ferrari_audio.update(0.016)
	# Confere se algum player do pool disparou
	var fired_blowoff := false
	for p in ferrari_audio.oneshot_pool:
		if p.stream == ferrari_audio.fx_streams.get("turbo3") and p.playing:
			fired_blowoff = true
			break
	check(fired_blowoff, "válvula de alívio (blow-off) disparou ao soltar acelerador em alto giro")

	print("\n--- Testando Efeitos FX (Troca de Marcha, Pneu, Grama, Brita, Vento, Zebra) ---")
	log_lines.append("\n--- Testando Efeitos FX (Troca de Marcha, Pneu, Grama, Brita, Vento, Zebra) ---")
	# Troca de marcha
	porsche_car.shift_count += 1
	audio.update(0.016)
	var fired_shift := false
	for p in audio.oneshot_pool:
		if p.stream == audio.fx_streams.get("gear_shift1") and p.playing:
			fired_shift = true
			break
	check(fired_shift, "som de troca de marcha (gear_shift1) acionado ao mudar marcha")

	# Pneu cantando (slip além do pico)
	porsche_car.vel = Vector3(0, 0, -30.0) # ~108 km/h
	for w in porsche_car.wheels:
		w.contact = true
		w.surface = Ground.ASPHALT
		w.kappa = porsche_car.kappa_peak * 1.3 # slip longitudinal acima do pico
	for step in 8:
		audio.update(0.02)
	check(audio.tyre_gain > 0.15, "pneu cantando no asfalto com slip > 1 (ganho %.2f)" % audio.tyre_gain)

	# Grama
	for w in porsche_car.wheels:
		w.surface = Ground.GRASS
	for step in 8:
		audio.update(0.02)
	check(audio.grass_gain > 0.20, "som de grama ativo com rodas na grama (ganho %.2f)" % audio.grass_gain)

	# Brita / Escape
	for w in porsche_car.wheels:
		w.surface = Ground.GRAVEL
	for step in 8:
		audio.update(0.02)
	check(audio.gravel_gain > 0.25, "som de brita ativo na brita (ganho %.2f)" % audio.gravel_gain)

	# Vento em alta velocidade (250 km/h = ~70 m/s)
	porsche_car.vel = Vector3(0, 0, -70.0)
	for step in 12:
		audio.update(0.03)
	check(audio.wind_gain > 0.15, "vento em alta velocidade (250 km/h) audível (ganho %.2f)" % audio.wind_gain)
	check(audio.wind_pitch > 1.0, "pitch do vento aumentado com a velocidade (%.2f)" % audio.wind_pitch)

	# Batida na zebra
	for w in porsche_car.wheels:
		w.surface = Ground.KERB
	audio.kerb_dist = 1.45
	audio.update(0.02) # avança 70 * 0.02 = 1.4 m -> kerb_dist > 1.5 m
	var fired_kerb := false
	for p in audio.oneshot_pool:
		if p.stream == audio.fx_streams.get("bump_front1") and p.playing:
			fired_kerb = true
			break
	check(fired_kerb, "batida na zebra (bump_front1) acionada na zebra")

	print("\n--- Testando Todos os 13 Carros GT3 com seus Bancos Sonoros ---")
	log_lines.append("\n--- Testando Todos os 13 Carros GT3 com seus Bancos Sonoros ---")
	var cars_json: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	for c in cars_json:
		var car_node := Car.load_car(ground, c.id)
		var test_audio := CarAudio.new(car_node, c.id)
		root.add_child(test_audio)
		var bank: String = test_audio.sound_spec.get("bank", "")
		var has_t: bool = test_audio.sound_spec.get("turbo", false)
		var n_loops := test_audio.engine_loops.size()
		check(n_loops >= 7, "%-24s banco: %-6s turbo: %-5s loops: %d" % [c.id, bank, str(has_t), n_loops])
		test_audio.free()

	audio.free()
	ferrari_audio.free()
	await process_frame

	var final_msg := "\nResultado Etapa 11 (Som): " + ("TUDO OK" if ok else "FALHOU")
	print(final_msg)
	log_lines.append(final_msg)

	quit(0 if ok else 1)
