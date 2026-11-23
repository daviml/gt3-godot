# Interlagos (PLANO-INTERLAGOS-DETALHES.md, Fase 2B, etapa E): a pista nova (tools/tracks/interlagos/, exportada
# pelo tools/pista.ts para data/track/) carrega e o piloto automático (RefBot, a mesma malha do jogo) dá voltas
# seguindo as 6 voltas reais do iRacing (Garage 61), comparando com elas:
#   - comprimento (<= 0,5% dos 4.309 m oficiais), amostras a 2 m de verdade (s do jogo = metro), desnível,
#     14 trechos com nome, muros nunca a menos de 1,35 m da borda, saída dos boxes com escape asfaltado;
#   - tempo de volta (<= 3% do iRacing), volta válida (limites de pista), velocidade mínima em cada trecho
#     (<= 10 km/h do iRacing, fora as pendentes declaradas em KNOWN);
#   - fundo do carro: nenhuma roda perde o chão por muito tempo; câmera vê a pista por cima do carro.
# Relevo e camber (`bank`) do LiDAR GeoSampa (`build_track.py --lidar`); sem o LiDAR ficavam pendentes a Ferradura,
# a câmera no Bico de Pato e os carros de motor central (ver KNOWN, CAM_KNOWN e PENDING_CARS).
# Os carros de data/tracks.json → refs são cobrados; os de PENDING_CARS rodam e só informam ("pendente").
# uso: godot --headless --path . --script res://scripts/tests/interlagos.gd [-- carro=<id>[,<id>]] [--sem-garagem]
#      [--sem-pendentes]
extends SceneTree

const DT := 1.0 / Car.HZ
const BOT_OPTS := {"yaw_p": 2.0, "hold_line": 0.02}
const PATH := "res://data/track/track.json"
const OFICIAL := 4309.0
const VMIN_TOL := 10.0
## diferenças conhecidas (aparecem como "pendente", não como falha): trecho → explicação. Vazio desde o LiDAR:
## a Ferradura (crista falsa do relevo antigo, jogo 120–132 × iRacing 145–155 km/h) passou a 145–154 × 145–155.
const KNOWN := {}
## câmera rente ao teto conhecida (pendente): trecho → explicação. Vazio desde o LiDAR (Bico de Pato tinha 0,02 m).
const CAM_KNOWN := {}
## carros do jogo sem referência por enquanto: rodam aqui só para informar. Vazio desde o LiDAR (NSX, 488 e 720S
## rodavam na saída da Ferradura com o relevo antigo; agora fecham válidas a 1,0–1,5% com as 6 referências).
const PENDING_CARS := {}
var pend := false
var ok := true
var track: Track
var resumo: Array = []


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else ("  pendente " if pend else "  FALHOU ")) + msg)
	ok = ok and (cond or pend)


func _init() -> void:
	Records.use_test_storage()
	track = Track.new(PATH)
	print("pista Interlagos (Fase 2B)")
	geometry()
	if not "--sem-garagem" in OS.get_cmdline_user_args():
		print("garagem e recordes")
		garage()
	var info := {}
	for t in JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks.json")):
		if t.id == "interlagos":
			info = t
	var refs: Dictionary = info.get("refs", {})
	check(refs.size() >= 6, "%d carros com referência do Garage 61 em data/tracks.json" % refs.size())
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("carro="):
			only = a.substr(6).split(",")
	for car_id in refs:
		if only.is_empty() or car_id in only:
			print("volta com RefBot: %s (%s)" % [car_id, refs[car_id]])
			lap(car_id, refs[car_id])
	if not "--sem-pendentes" in OS.get_cmdline_user_args():
		pend = true
		for car_id in PENDING_CARS:
			if (only.is_empty() or car_id in only) and not refs.has(car_id):
				print("volta com RefBot (pendente, só informa): %s (%s)" % [car_id, PENDING_CARS[car_id]])
				lap(car_id, PENDING_CARS[car_id])
		pend = false
	print("resumo (carro, referência, jogo, iRacing, diferença):")
	for r in resumo:
		print("    " + r)
	print("TUDO OK" if ok else "HOUVE FALHAS")
	quit(0 if ok else 1)


func geometry() -> void:
	check(absf(track.length - OFICIAL) / OFICIAL < 0.005, "comprimento %.0f m (oficial 4.309 m, %+.2f%%)" % [track.length, (track.length - OFICIAL) / OFICIAL * 100.0])
	# s do jogo = metro: distância 3D entre amostras vizinhas a 2 m ± 1% (o Track do web com 200 cordas dava até 2,07)
	var dmin := INF
	var dmax := 0.0
	for i in track.n:
		var d := track.P[i].distance_to(track.P[(i + 1) % track.n])
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	check(dmin > 1.98 and dmax < 2.02, "amostras a cada %.3f–%.3f m" % [dmin, dmax])
	var ymin := INF
	var ymax := -INF
	for p in track.P:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	# relevo do LiDAR (oficial ~43 m)
	check(absf(ymax - ymin - 43.0) < 4.0, "desnível %.1f m (oficial ~43 m)" % (ymax - ymin))
	var names: Array = track.sections.map(func(c): return c.name)
	check(names.size() == 14 and "S do Senna" in names and "Junção" in names and "Subida dos Boxes" in names,
		"14 trechos com nome (%s)" % ", ".join(names))
	# muros: nunca a menos de 1,5 m da borda (wallMinGap da fonte); saída dos boxes (esq., s ~830–980) com asfalto
	var gap := INF
	for i in track.n:
		gap = minf(gap, minf(track.wall_l[i] - track.wl[i], track.wall_r[i] - track.wr[i]))
	# 1,35 m na barreira Goodyear do Lago (colada na zebra, etapa F); no resto o build_track.py mantém >= 1,5 m
	check(gap > 1.34, "muro a >= 1,35 m da borda (mín. %.2f m)" % gap)
	var pit_ok := true
	for s in range(840, 980, 10):
		var i := track.index_at(float(s))
		pit_ok = pit_ok and track.run_l[i] >= 4.0
	check(pit_ok, "faixa de aceleração da saída dos boxes é escape asfaltado (runL >= 4 m em s 840–970)")


func lap(car_id: String, ref_name: String) -> void:
	var ref := RefBot.load_ref(ref_name)
	var car := Car.load_car(track, car_id)
	car.assists.auto = true
	var bot := RefBot.new(track, car, ref, BOT_OPTS)
	var s0 := track.length - 300.0
	var p0 := bot.line_point(s0)
	var p1 := bot.line_point(s0 + 4.0)
	track.locate(p0, -1)
	car.reset(Vector3(p0.x, track.lcenter.y + car.p.cg + 0.02, p0.z), atan2(-(p1.x - p0.x), -(p1.z - p0.z)))
	var v0 := bot.ref_at(bot._rv, s0)
	car.vel = Vector3(p1.x - p0.x, 0, p1.z - p0.z).normalized() * v0
	car.gear = car.p.ratios.size()
	for w in car.wheels:
		w.omega = v0 / car.p.radius
	var timer := LapTimer.new(track)
	var got: Array = []
	timer.on_lap = func(l): got.append(l)
	var vmin := {}
	var max_err := 0.0
	var err_at := ""
	var airborne := 0.0
	var air_max := 0.0
	var air_at := ""
	var cam := Camera3D.new()
	var chase := ChaseCamera.new(cam, car)
	var cam_low := INF
	var cam_low_at := ""
	var cam_pend := {}
	var invalid_at := ""
	var t := 0.0
	while got.size() < 2 and t < 260.0:
		var inp := bot.drive()
		car.step(DT, inp[0], inp[1], inp[2])
		chase.update(DT)
		var was_valid := timer.valid
		timer.update(DT, car)
		t += DT
		if got.size() == 1:
			var name := track.section_at(timer.s)
			var v := car.vel.length()
			vmin[name] = minf(vmin.get(name, INF), v)
			if absf(bot.line_error) > max_err:
				max_err = absf(bot.line_error)
				err_at = "s=%.0f (%s)" % [timer.s, name]
			if was_valid and not timer.valid and invalid_at == "":
				invalid_at = "s=%.0f (%s)" % [timer.s, name]
			var down := 0
			for w in car.wheels:
				if w.fz > 0.0:
					down += 1
			var cp := car.visual_pos(1.0)
			track.locate(cp, track.li)
			var roof := track.lcenter + track.lr * track.ld + track.ln * 1.25
			var ahead := bot.line_point(timer.s + 25.0)
			var co := cam.transform.origin
			var u := clampf((roof - co).length() / maxf(0.1, (ahead - co).length()), 0.0, 1.0)
			var rel: float = (co.lerp(ahead, u) - roof).dot(track.ln)
			if rel < 0.15 and CAM_KNOWN.has(name):
				cam_pend[name] = minf(cam_pend.get(name, INF), rel)
			elif rel < cam_low:
				cam_low = rel
				cam_low_at = "s=%.0f (%s)" % [timer.s, name]
			airborne = airborne + DT if down <= 2 else 0.0
			if airborne > air_max:
				air_max = airborne
				air_at = "s=%.0f (%s)" % [timer.s, name]
	check(got.size() == 2, "fechou 2 voltas (%d; parou em s=%.0f, %s, %.0f km/h, t=%.0f s)" % [got.size(), timer.s,
		track.section_at(timer.s), car.vel.length() * 3.6, t])
	if got.size() < 2:
		cam.free()
		resumo.append("%s (%s): não fechou 2 voltas" % [car_id, ref_name])
		return
	var b: LapTimer.Lap = got[1]
	var real: float = ref.lapTime
	print("    volta %s (iRacing %s), erro de linha máx %.2f m" % [LapTimer.format_time(b.time), LapTimer.format_time(real), max_err])
	resumo.append("%s (%s): %s × %s (%+.2f s, %+.2f%%)%s" % [car_id, ref_name, LapTimer.format_time(b.time),
		LapTimer.format_time(real), b.time - real, (b.time - real) / real * 100.0, "" if b.valid else " INVÁLIDA"])
	check(b.valid, "2ª volta válida" + ("" if invalid_at == "" else " (invalidou em %s)" % invalid_at))
	check(absf(b.time - real) / real < 0.03, "tempo a <=3%% do iRacing (%+.2f s, %+.2f%%)" % [b.time - real, (b.time - real) / real * 100.0])
	check(max_err < 3.5, "segue a linha real (erro máx %.2f m em %s)" % [max_err, err_at])
	check(cam_low > 0.15, "pista à frente visível por cima do carro (folga mín. %.2f m em %s; fora as pendentes)" % [cam_low, cam_low_at])
	for n in cam_pend:
		print("  pendente câmera em %s: folga %.2f m — %s" % [n, cam_pend[n], CAM_KNOWN[n]])
	cam.free()
	check(air_max < 0.25, "no máx. 2 rodas no ar por %.2f s em %s (limite 0,25 s)" % [air_max, air_at])
	var rmin := {}
	var rv: Array = ref.v
	for k in rv.size():
		var name := track.section_at(k * float(ref.step))
		rmin[name] = minf(rmin.get(name, INF), float(rv[k]))
	var line := "    mínimas (km/h, jogo/iRacing):"
	var worst_v := 0.0
	var worst_n := ""
	for c in track.sections:
		var n: String = c.name
		if vmin.has(n) and rmin.has(n):
			line += " %s %d/%d" % [n, roundi(vmin[n] * 3.6), roundi(rmin[n] * 3.6)]
			var diff := absf(vmin[n] - rmin[n]) * 3.6
			if KNOWN.has(n):
				if diff >= VMIN_TOL:
					print("  pendente %s: %.0f km/h de diferença — %s" % [n, diff, KNOWN[n]])
			elif diff > worst_v:
				worst_v = diff
				worst_n = n
	print(line)
	check(worst_v < VMIN_TOL, "mínimas por trecho a <=10 km/h do iRacing, fora as pendentes (pior %.1f em %s)" % [worst_v, worst_n])


## Interlagos no seletor, recordes da v4 (placar zerado na Fase 2B) separados das outras pistas e o fantasma
## com chave nova. Só troca Game.track_id na memória (não grava user://jogo.cfg).
func garage() -> void:
	var ids: Array = Game.get_available_tracks().map(func(t): return t.id)
	check("interlagos" in ids, "Interlagos disponível no seletor (%s)" % ", ".join(ids))
	var before := Game.track_id
	Game.track_id = "interlagos"
	var inter := [Records.path_for("sim"), Records.path_for("arcade"), Records.remote_file("sim")]
	Game.track_id = "imola"
	var imo := [Records.path_for("sim"), Records.path_for("arcade"), Records.remote_file("sim")]
	Game.track_id = before
	check(inter[0].ends_with("recordes-interlagos-v4.json") and inter[1].ends_with("recordes-interlagos-arcade-v4.json"),
		"recordes da v4 (%s, %s)" % [inter[0].get_file(), inter[1].get_file()])
	check(imo[0] != inter[0] and imo[1] != inter[1] and imo[2] != inter[2], "recordes de Imola separados")
	var g := GhostCar.new()
	g.track_id = "interlagos"
	g.car_id = "audi-r8-lms-gt3"
	g.mode = "sim"
	check(g.ghost_path().get_file().begins_with("interlagos-v4__"), "fantasma com chave nova (%s)" % g.ghost_path().get_file())
	g.free()
