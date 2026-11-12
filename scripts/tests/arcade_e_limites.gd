# Testes dedicados para: modo Arcade (2.0x grip + anti-capotamento), limites de pista ao cruzar a linha
# e separação/contrato de recordes locais e remotos entre Simulador e Arcade.
extends SceneTree

const DT := 1.0 / Car.HZ

var ok_all := true
var track: Track


func _init() -> void:
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
	var sim_path := Records.PATH_SIM
	var arc_path := Records.PATH_ARCADE
	var b_sim := FileAccess.get_file_as_string(sim_path) if FileAccess.file_exists(sim_path) else ""
	var b_arc := FileAccess.get_file_as_string(arc_path) if FileAccess.file_exists(arc_path) else ""
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

	check(Records.ranking_url("sim").ends_with("/api/ranking?modo=godot-sim"), "URL ranking sim aponta para godot-sim")
	check(Records.ranking_url("arcade").ends_with("/api/ranking?modo=godot-arcade"), "URL ranking arcade aponta para godot-arcade")
	var payload = JSON.parse_string(Records.build_volta_payload("Davi", "corvette-c6r-gt3", lap_arc, "arcade"))
	check(payload is Dictionary and payload.get("modo") == "godot-arcade" and payload.get("valid") == true, "payload POST inclui modo godot-arcade")

	# Segurança contra API desatualizada: resposta sem 'modo' igual ao esperado é rejeitada
	var legacy_body := JSON.stringify({"voltas": [{"nick": "Web", "carId": "corvette-c6r-gt3", "time": 90.0}]}).to_utf8_buffer()
	var parsed_legacy := Records.parse_ranking_response(200, legacy_body, "godot-sim")
	check(not bool(parsed_legacy.get("ok", false)), "rejeita resposta sem campo modo (evita misturar ranking web)")

	var ok_body := JSON.stringify({"modo": "godot-arcade", "voltas": [{"nick": "Godot", "carId": "bmw-m4-gt3", "time": 74.5}]}).to_utf8_buffer()
	var parsed_ok := Records.parse_ranking_response(200, ok_body, "godot-arcade")
	check(bool(parsed_ok.get("ok", false)) and parsed_ok.voltas.size() == 1, "aceita resposta com modo godot-arcade")

	var post_ok_body := JSON.stringify({"modo": "godot-arcade", "recorde": true, "voltas": [{"nick": "Godot", "carId": "bmw-m4-gt3", "time": 74.5}]}).to_utf8_buffer()
	var parsed_post := Records.parse_volta_response(200, post_ok_body, "godot-arcade")
	check(bool(parsed_post.get("ok", false)) and bool(parsed_post.get("recorde", false)), "aceita retorno POST do modo godot-arcade")

	# Restaura arquivos do usuário
	for p_b in [[sim_path, b_sim], [arc_path, b_arc]]:
		if p_b[1] != "":
			var f := FileAccess.open(p_b[0], FileAccess.WRITE)
			f.store_string(p_b[1])
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p_b[0]))
