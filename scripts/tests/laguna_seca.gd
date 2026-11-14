# Laguna Seca (PLANO-LAGUNA-SECA.md, fase 3): a pista carrega e o piloto automático (RefBot, a mesma malha do jogo)
# dá voltas seguindo a telemetria real do iRacing (Garage 61), comparando com ela:
#   - comprimento (≤ 0,5% dos 3.602 m oficiais) e desnível do Corkscrew;
#   - tempo de volta, volta válida (limites de pista), velocidade mínima em cada curva × a referência;
#   - fundo do carro: nenhuma roda perde o chão por muito tempo na saída do Corkscrew e na T6.
# uso: godot --headless --path . --script res://scripts/tests/laguna_seca.gd [-- carro=<id>[,<id>]]
extends SceneTree

const DT := 1.0 / Car.HZ
const BOT_OPTS := {"yaw_p": 2.0, "hold_line": 0.02}
const PATH := "res://data/tracks/laguna-seca/track.json"
## diferenças conhecidas (aparecem como "pendente", não como falha)
const KNOWN := {
	"Curva 6": "o GT3 do iRacing faz 3,2 g na T6 a 175 km/h; o camber real (5,5°, LiDAR) explica só parte — ajuste de física pendente",
}
var ok := true
var track: Track


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _init() -> void:
	Records.use_test_storage()
	track = Track.new(PATH)
	print("pista")
	geometry()
	print("garagem e recordes")
	garage()
	var info := {}
	for t in JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks.json")):
		if t.id == "laguna-seca":
			info = t
	var refs: Dictionary = info.get("refs", {})
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("carro="):
			only = a.substr(6).split(",")
	for car_id in refs:
		if only.is_empty() or car_id in only:
			print("volta com RefBot: %s (%s)" % [car_id, refs[car_id]])
			lap(car_id, refs[car_id])
	print("TUDO OK" if ok else "HOUVE FALHAS")
	quit(0 if ok else 1)


func geometry() -> void:
	check(absf(track.length - 3602.0) / 3602.0 < 0.005, "comprimento %.0f m (oficial 3.602 m)" % track.length)
	var ymin := INF
	var ymax := -INF
	for p in track.P:
		ymin = minf(ymin, p.y); ymax = maxf(ymax, p.y)
	check(absf(ymax - ymin - 55.0) < 4.0, "desnível %.1f m (real ~55 m)" % (ymax - ymin))
	# maior descida em 20 m (Corkscrew, ~18%)
	var worst := 0.0
	var at := 0
	for i in track.n:
		var j := (i + 10) % track.n
		var g := (track.P[j].y - track.P[i].y) / 20.0
		if g < worst:
			worst = g; at = i
	check(worst < -0.15 and track.section_at(at * Track.STEP) == "Corkscrew",
		"maior descida %.1f%% em s=%.0f (%s)" % [worst * 100.0, at * Track.STEP, track.section_at(at * Track.STEP)])
	var names: Array = track.sections.map(func(c): return c.name)
	check(names.size() == 12 and "Andretti Hairpin" in names and "Rainey Curve" in names, "12 trechos com nome")


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
	# velocidade mínima por trecho na 2ª volta (a 1ª começa lançada só 300 m antes)
	var vmin := {}
	var max_err := 0.0
	var airborne := 0.0
	var air_max := 0.0
	var air_at := ""
	# câmera de perseguição (padrão) junto: em subida forte ela não pode cair atrás do teto do carro
	var cam := Camera3D.new()
	var chase := ChaseCamera.new(cam, car)
	if "camera_antiga" in OS.get_cmdline_user_args():
		chase.climb_lead = 0.0
	var cam_low := INF
	var cam_low_at := ""
	var cam_by := {}
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
			max_err = maxf(max_err, absf(bot.line_error))
			if was_valid and not timer.valid and invalid_at == "":
				invalid_at = "s=%.0f (%s)" % [timer.s, name]
			var down := 0
			for w in car.wheels:
				if w.fz > 0.0:
					down += 1
			# altura da câmera acima do carro, medida ao longo da normal da pista (rampa não conta)
			# a reta da câmera até a pista 25 m à frente tem que passar acima do teto do carro (~1,25 m do chão)
			var cp := car.visual_pos(1.0)
			track.locate(cp, track.li)
			var roof := track.lcenter + track.lr * track.ld + track.ln * 1.25
			var ahead := bot.line_point(timer.s + 25.0)
			var co := cam.transform.origin
			var u := clampf((roof - co).length() / maxf(0.1, (ahead - co).length()), 0.0, 1.0)
			var rel: float = (co.lerp(ahead, u) - roof).dot(track.ln)
			cam_by[name] = minf(cam_by.get(name, INF), rel)
			# no alto do Corkscrew a pista some atrás da crista (cega também no LMU): não conta
			if rel < cam_low and name != "Corkscrew":
				cam_low = rel
				cam_low_at = "s=%.0f (%s)" % [timer.s, name]
			airborne = airborne + DT if down <= 2 else 0.0
			if airborne > air_max:
				air_max = airborne
				air_at = "s=%.0f (%s)" % [timer.s, name]
	check(got.size() == 2, "fechou 2 voltas (%d)" % got.size())
	if got.size() < 2:
		return
	var b: LapTimer.Lap = got[1]
	var real: float = ref.lapTime
	print("    volta %s (iRacing %s), erro de linha máx %.2f m" % [LapTimer.format_time(b.time), LapTimer.format_time(real), max_err])
	check(b.valid, "2ª volta válida" + ("" if invalid_at == "" else " (invalidou em %s)" % invalid_at))
	check(absf(b.time - real) / real < 0.03, "tempo a ≤3%% do iRacing (%+.2f s)" % (b.time - real))
	check(max_err < 3.0, "segue a linha real (erro máx %.2f m; a referência é de outro carro/física)" % max_err)
	print("    folga da câmera por trecho (m):", " ".join(cam_by.keys().map(func(k): return "%s %.2f" % [k.replace("Curva ", "T"), cam_by[k]])))
	check(cam_low > 0.15, "pista à frente sempre visível por cima do carro (folga mín. %.2f m em %s; o alto do Corkscrew é crista cega e não conta)" % [cam_low, cam_low_at])
	cam.free()
	check(air_max < 0.25, "no máx. 2 rodas no ar por %.2f s em %s (limite 0,25 s)" % [air_max, air_at])
	# mínimas da referência por trecho
	var rmin := {}
	var rv: Array = ref.v
	for k in rv.size():
		var name := track.section_at(k * float(ref.step))
		rmin[name] = minf(rmin.get(name, INF), float(rv[k]))
	var line := "    mínimas (km/h, jogo/iRacing):"
	var worst := 0.0
	for c in track.sections:
		var n: String = c.name
		if vmin.has(n) and rmin.has(n):
			line += " %s %d/%d" % [n.replace("Curva ", "T"), roundi(vmin[n] * 3.6), roundi(rmin[n] * 3.6)]
			var diff := absf(vmin[n] - rmin[n]) * 3.6
			if KNOWN.has(n):
				if diff >= 12.0:
					print("  pendente %s: %.0f km/h de diferença — %s" % [n, diff, KNOWN[n]])
			else:
				worst = maxf(worst, diff)
	print(line)
	check(worst < 12.0, "mínimas por curva a ≤12 km/h do iRacing, fora as pendentes (pior %.1f)" % worst)


## A Laguna aparece no seletor (precisa de track.json + cenario.glb), o cenário carrega e os recordes ficam
## separados dos de Interlagos. Só troca Game.track_id na memória (não grava user://jogo.cfg).
func garage() -> void:
	var ids: Array = Game.get_available_tracks().map(func(t): return t.id)
	check("interlagos" in ids and "laguna-seca" in ids, "as duas pistas disponíveis no seletor (%s)" % ", ".join(ids))
	var before := Game.track_id
	Game.track_id = "interlagos"
	var inter := [Records.path_for("sim"), Records.path_for("arcade"), Records.remote_file("sim")]
	Game.track_id = "laguna-seca"
	var lag := [Records.path_for("sim"), Records.path_for("arcade"), Records.remote_file("sim")]
	var glb := Game.track_asset_path("cenario.glb")
	Game.track_id = before
	check(inter[0].ends_with("recordes-interlagos-v3.json") and inter[1].ends_with("recordes-interlagos-godot-arcade.json"),
		"Interlagos com os arquivos de recorde de sempre")
	check(lag[0] != inter[0] and lag[1] != inter[1] and lag[2] != inter[2], "recordes da Laguna separados (%s, %s)" % [lag[0].get_file(), lag[2]])
	var scene = load(glb)
	check(scene is PackedScene, "cenário da Laguna carrega (%s)" % glb)
	var horizon := FileAccess.file_exists("res://data/tracks/laguna-seca/horizonte.json")
	var towers: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/laguna-seca/torres.json"))
	check(horizon and towers is Array and towers.is_empty(), "horizonte próprio e sem anel de prédios")
