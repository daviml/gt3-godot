# Testes dedicados para: modo Arcade (2.0x grip + anti-capotamento), limites de pista ao cruzar a linha
# e separação/contrato de recordes locais e remotos entre Simulador e Arcade.
extends SceneTree

const DT := 1.0 / Car.HZ

var ok_all := true
var track: Track


func _init() -> void:
	# teste de Interlagos: não depende da última pista escolhida no jogo (user://jogo.cfg)
	Game.track_id = Game.DEFAULT_TRACK
	Records.use_test_storage()  # nunca mexer nos recordes de verdade
	track = Track.new("res://data/track/track.json")
	print("limites avançados")
	_test_offtime_reset_at_finish()
	print("modo arcade (2.0x grip e anti-capotamento)")
	_test_arcade_mode_state()
	_test_arcade_grip_and_no_rollover()
	print("recordes separados e contrato da API")
	_test_records_separation_and_api()
	print("OK" if ok_all else "HOUVE FALHAS")
	quit(0 if ok_all else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		ok_all = false
	print("  %s %s" % ["ok  " if cond else "FALHOU", msg])


func _park(car: Car, i: int, d: float) -> void:
	var r := track.R[i]
	var tt := track.T[i]
	var up := r.cross(tt).normalized()
	car.reset_basis(track.P[i] + r * d + up * (car.p.cg + 0.03), Basis(r, up, -tt))
	car.hint = i
	for _k in Car.HZ / 2:
		car.step(DT, 0, 0, 1)


func _test_offtime_reset_at_finish() -> void:
	var i_off := -1
	for k in range(100, track.n - 100):
		if track.kerb_r[k] > 1.0 and track.run_r[k] > 4.0 and track.kerb_r[k - 5] > 1.0 and track.kerb_r[k + 5] > 1.0:
			i_off = k
			break
	if i_off < 0:
		check(false, "amostra fora da pista encontrada")
		return
	var car := Car.load_car(track, "corvette-c6r-gt3")
	var timer := LapTimer.new(track)
	var half := absf(car.wheels[0].mount.x)
	# simula estar com 4 rodas fora por 0.16 s no fim da volta anterior
	_park(car, i_off, track.wr[i_off] + track.kerb_r[i_off] + half + 0.6)
	timer.current = 90.0
	timer.sectors = [28.0, 32.0]
	timer.valid = true
	timer._last_s = track.length - 10.0
	for _k in int(0.16 * Car.HZ):
		car.step(DT, 0, 0, 1)
		timer.update(DT, car)
	check(timer.valid and timer._off_time >= 0.14, "acumulou ~0.16 s fora antes da linha sem invalidar")
	# cruza a linha de chegada sobre o asfalto: _off_time precisa zerar na nova volta
	_park(car, 2, 0.0)
	timer._last_s = track.length - 5.0
	timer.update(DT, car)
	check(timer.laps.size() == 1 and timer.laps[0].valid, "fechou volta anterior válida")
	check(timer.valid and timer._off_time == 0.0, "cruzou a linha: _off_time zerou para a nova volta")


func _test_arcade_mode_state() -> void:
	var prev_mode := Game.mode
	Game.set_mode("arcade")
	check(Game.is_arcade() and absf(Game.get_grip_scale() - 2.0) < 1e-6, "Game.mode='arcade' aplica grip 2.0x")
	Game.set_mode("sim")
	check((not Game.is_arcade()) and absf(Game.get_grip_scale() - 1.0) < 1e-6, "Game.mode='sim' aplica grip 1.0x")
	Game.set_mode(prev_mode)


func _test_arcade_grip_and_no_rollover() -> void:
	var sim_peak_lat := 0.0
	for m in [["sim", 1.0], ["arcade", 2.0]]:
		var ground := FlatGround.new()
		var car_data := Game.get_car_data("corvette-c6r-gt3")
		var car := Car.new(ground, car_data.params)
		car.grip_scale = m[1]
		car.assists.abs = true
		car.assists.tc = true
		car.assists.auto = true
		car.reset(Vector3(0.0, float(car.p.cg) + 0.02, 0.0), 0.0)
		car.vel = Vector3(0.0, 0.0, -200.0 / 3.6)
		car.gear = 4
		car.rpm = 7200.0
		var min_up_y := 1.0
		var max_lat_g := 0.0
		# slalom violento de 5 s a ~200 km/h
		for k in 5 * Car.HZ:
			var t := k * DT
			var steer := 1.0 if int(t * 2.5) % 2 == 0 else -1.0
			car.step(DT, steer, 0.85, 0.0)
			min_up_y = minf(min_up_y, car.basis().y.y)
			max_lat_g = maxf(max_lat_g, absf(car.g_lat))
		if m[0] == "sim":
			sim_peak_lat = max_lat_g
		print("    %s (%.1fx): g_lat_max=%.2f g, min_up_y=%.4f" % [m[0], m[1], max_lat_g, min_up_y])
		check(min_up_y > 0.90, "%s não capotou no slalom (up.y=%.3f)" % [m[0], min_up_y])
		if m[0] == "arcade":
			check(max_lat_g > sim_peak_lat * 1.4, "arcade gera bem mais g lateral que o simulador (%.2f vs %.2f)" % [max_lat_g, sim_peak_lat])

	# Teste extra na pista real passando em zebras com 2.0x grip a alta velocidade (usando RefBot Porsche)
	var car_arc := Car.load_car(track, "corvette-c6r-gt3")
	car_arc.grip_scale = 2.0
	car_arc.assists.abs = true
	car_arc.assists.tc = true
	car_arc.assists.auto = true
	car_arc.reset_at(track.index_at(-120.0))
	var bot := Bot.new(track, car_arc)
	var min_track_up_y := 1.0
	for _k in 25 * Car.HZ:
		var inp := bot.drive()
		car_arc.step(DT, inp[0], inp[1], inp[2])
		min_track_up_y = minf(min_track_up_y, car_arc.basis().y.y)
	check(min_track_up_y > 0.90, "arcade 2.0x na pista/zebras não capota (up.y=%.3f)" % min_track_up_y)


func _test_records_separation_and_api() -> void:
	var sim_path := Records.path_for("sim")
	var arc_path := Records.path_for("arcade")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sim_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(arc_path))

	var lap_sim := LapTimer.Lap.new()
	lap_sim.time = 95.123
	lap_sim.sectors = [29.0, 35.123, 31.0]
	var lap_arc := LapTimer.Lap.new()
	lap_arc.time = 74.500
	lap_arc.sectors = [23.0, 27.5, 24.0]

	check(Records.save_lap("DaviSim", "corvette-c6r-gt3", lap_sim, "sim"), "grava recorde no modo sim")
	check(Records.save_lap("DaviArc", "bmw-m4-gt3", lap_arc, "arcade"), "grava recorde no modo arcade")
	var top_sim := Records.top(8, "sim")
	var top_arc := Records.top(8, "arcade")
	check(top_sim.size() == 1 and top_sim[0].nick == "DaviSim", "ranking local sim separado do arcade")
	check(top_arc.size() == 1 and top_arc[0].nick == "DaviArc", "ranking local arcade separado do sim")
	var merged := Records.merge_records([{"nick": "Remoto", "carId": "bmw-m4-gt3", "time": 76.0}], [{"nick": "Local", "carId": "bmw-m4-gt3", "time": 75.0}])
	check(merged.size() == 2 and merged[0].nick == "Local", "merge_records combina remoto e local mantendo menor tempo primeiro")

	# ranking direto no GitHub (gt3-tempos), mesmos arquivos e regras da antiga função da Vercel
	check(Records.contents_url("sim").ends_with("/contents/interlagos-godot.json?ref=main"), "sim lê interlagos-godot.json")
	check(Records.contents_url("arcade", false).ends_with("/contents/interlagos-godot-arcade.json"), "arcade grava interlagos-godot-arcade.json")
	check(Records.unscramble(Records.scramble("github_pat_abc123")) == "github_pat_abc123", "token embaralhado volta ao original")
	var rec := Records.validate_remote(" Da<vi> ", "bmw-m4-gt3", lap_arc.time, Array(lap_arc.sectors), true, "arcade")
	check(not rec.is_empty() and rec.nick == "Davi" and absf(float(rec.time) - 74.5) < 1e-9, "volta válida vira registro com nick limpo")
	check(Records.validate_remote("Davi", "bmw-m4-gt3", lap_arc.time, Array(lap_arc.sectors), false, "arcade").is_empty(), "volta inválida não sobe")
	check(Records.validate_remote("Davi", "bmw-m4-gt3", lap_arc.time, Array(lap_arc.sectors), true, "sim").is_empty(), "1:14 no Simulador é rejeitado (mínimo 85 s)")
	check(Records.validate_remote("Davi", "carro-x", lap_arc.time, Array(lap_arc.sectors), true, "arcade").is_empty(), "carro desconhecido rejeitado")
	check(Records.validate_remote("Davi", "bmw-m4-gt3", 80.0, [20.0, 20.0, 20.0], true, "arcade").is_empty(), "setores que não somam a volta rejeitados")
	var base := [{"nick": "Davi", "carId": "bmw-m4-gt3", "time": 75.0}, {"nick": "Gui", "carId": "bmw-m4-gt3", "time": 74.8}]
	var m1 := Records.merge_remote(base, rec)
	check(m1.recorde and m1.voltas.size() == 2 and m1.voltas[0].nick == "Davi", "volta melhor substitui e reordena")
	var slow := rec.duplicate()
	slow.time = 76.0
	check(not Records.merge_remote(base, slow).recorde, "volta pior não grava")
	var body := JSON.stringify({"sha": "abc", "content": Marshalls.utf8_to_base64(Records.encode_file(m1.voltas)).insert(8, "\n")}).to_utf8_buffer()
	var parsed := Records.parse_contents(200, body)
	check(parsed.ok and parsed.sha == "abc" and parsed.voltas.size() == 2 and parsed.voltas[0].nick == "Davi", "lê o arquivo do GitHub (base64 com quebras)")
	check(Records.encode_file(m1.voltas).find('"nick": "Davi"') >= 0, "grava no formato {voltas: [...]}")
	check(Records.parse_contents(404, PackedByteArray()).ok and Records.parse_contents(404, PackedByteArray()).voltas.is_empty(), "arquivo inexistente = ranking vazio")
	check(not Records.parse_contents(401, PackedByteArray()).ok, "token inválido = falha (usa a cópia)")

	# cópia do ranking compartilhado: aparece ao abrir o jogo mesmo sem resposta do servidor
	check(sim_path.begins_with("user://testes/"), "testes gravam em user://testes/, longe dos recordes reais")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.cache_path("arcade")))
	Records.save_cache("arcade", [{"nick": "Amigo", "carId": "bmw-m6-gt3", "time": 73.0}])
	var shown := Records.ranking(15, "arcade")
	check(shown.size() == 2 and shown[0].nick == "Amigo", "ranking usa a cópia guardada + local sem servidor")
	var fresh := Records.ranking(15, "arcade", [{"nick": "Novo", "carId": "bmw-m6-gt3", "time": 72.0}])
	check(fresh.size() == 2 and fresh[0].nick == "Novo", "ranking prefere a resposta do servidor à cópia")
	for p in [sim_path, arc_path, Records.cache_path("arcade")]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
