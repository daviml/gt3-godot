# Etapa 4: cronometragem (LapTimer) e recordes locais.
# - piloto automático do Porsche dá 2 voltas válidas (1:35,88, igual ao web), setores somando a volta, delta ~0 na 2ª;
# - limite de pista: roda na zebra é dentro; 4 rodas no escape invalidam só depois de 0,2 s;
# - recordes: grava só volta válida e melhor que a anterior do mesmo nick e carro.
# uso: godot --headless --path . --script res://scripts/tests/cronometragem.gd
extends SceneTree

const DT := 1.0 / Car.HZ
## mesmos ajustes do piloto automático do jogo (main.gd): segue a volta real do iRacing com a malha de giro
const BOT_OPTS := {"yaw_p": 2.0, "hold_line": 0.02}
var ok := true
var track: Track


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _init() -> void:
	Records.use_test_storage()  # nunca mexer nos recordes de verdade
	track = Track.new("res://data/track/track.json")
	print("volta lançada (RefBot R8)")
	bot_laps()
	print("limites de pista")
	limits()
	print("recordes")
	records()
	print("TUDO OK" if ok else "HOUVE FALHAS")
	quit(0 if ok else 1)


func bot_laps() -> void:
	var car := Car.load_car(track, "audi-r8-lms-gt3")
	car.assists.auto = true
	var bot := RefBot.new(track, car, RefBot.load_ref("interlagos-r8"), BOT_OPTS)
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
	var max_delta := 0.0
	var t := 0.0
	while got.size() < 2 and t < 260.0:
		var inp := bot.drive()
		car.step(DT, inp[0], inp[1], inp[2])
		var was_valid := timer.valid
		timer.update(DT, car)
		if was_valid and not timer.valid and OS.get_cmdline_user_args().has("--onde"):
			print("    inválida em s=%.0f (%s), volta %d" % [timer.s, track.section_at(timer.s), got.size() + 1])
		t += DT
		if got.size() == 1 and not is_nan(timer.delta) and timer.current > 2.0:
			max_delta = maxf(max_delta, absf(timer.delta))
	check(got.size() == 2, "fechou 2 voltas (%d)" % got.size())
	if got.size() < 2:
		return
	var a: LapTimer.Lap = got[0]
	var b: LapTimer.Lap = got[1]
	print("    voltas %s / %s, setores %.2f %.2f %.2f" % [LapTimer.format_time(a.time), LapTimer.format_time(b.time), a.sectors[0], a.sectors[1], a.sectors[2]])
	check(absf(a.time - 94.02) < 0.25, "1ª volta ≈ 1:34,02 (RefBot R8)")
	check(a.valid and b.valid, "as duas voltas válidas")
	check(absf(a.sectors[0] + a.sectors[1] + a.sectors[2] - a.time) < 1e-4, "setores somam a volta")
	check(a.sectors.all(func(x): return x > 20.0 and x < 45.0), "3 setores de tamanho plausível")
	check(timer.best != null and timer.best.time == minf(a.time, b.time), "melhor volta = a mais rápida")
	check(max_delta < 0.15, "delta na 2ª volta perto de zero (máx %.3f s)" % max_delta)
	check(timer.current >= 0.0 and timer.current < 2.0, "volta seguinte já correndo")


## Carro parado com o centro a d metros da linha central (lado direito) na amostra i.
func park(car: Car, i: int, d: float) -> void:
	var r := track.R[i]
	var tt := track.T[i]
	var up := r.cross(tt).normalized()
	car.reset_basis(track.P[i] + r * d + up * (car.p.cg + 0.03), Basis(r, up, -tt))
	car.hint = i
	for k in Car.HZ / 2:
		car.step(DT, 0, 0, 1)


func stay(car: Car, timer: LapTimer, secs: float) -> void:
	timer.current = 10.0
	timer.valid = true
	timer._off_time = 0.0
	for k in int(secs * Car.HZ):
		car.step(DT, 0, 0, 1)
		timer.update(DT, car)


func limits() -> void:
	# trecho com zebra e escape largos do lado direito, longe da linha de chegada
	var i := -1
	for k in range(100, track.n - 100):
		if track.kerb_r[k] > 1.0 and track.run_r[k] > 4.0 and track.kerb_r[k - 5] > 1.0 and track.kerb_r[k + 5] > 1.0:
			i = k
			break
	check(i >= 0, "achou zebra + escape largos (amostra %d)" % i)
	if i < 0:
		return
	var car := Car.load_car(track, "corvette-c6r-gt3")
	var half := absf(car.wheels[0].mount.x)
	var timer := LapTimer.new(track)
	var edge := track.wr[i]
	var kerb := track.kerb_r[i]
	# rodas de dentro sobre a zebra, de fora no escape: continua dentro
	park(car, i, edge + kerb - half + 0.3)
	stay(car, timer, 1.0)
	check(timer.valid, "2 rodas na zebra por 1 s: válida")
	# 4 rodas no escape: grace de 0,2 s
	park(car, i, edge + kerb + half + 0.6)
	stay(car, timer, 0.15)
	check(timer.valid, "4 rodas no escape por 0,15 s: ainda válida")
	stay(car, timer, 0.3)
	check(not timer.valid, "4 rodas no escape por 0,3 s: inválida")


func records() -> void:
	var path := Records.path_for()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var lap := LapTimer.Lap.new()
	lap.time = 97.5
	lap.sectors = [30.0, 35.0, 32.5]
	check(Records.save_lap("teste", "corvette-c6r-gt3", lap), "1ª volta válida vira recorde")
	lap.time = 98.0
	check(not Records.save_lap("teste", "corvette-c6r-gt3", lap), "volta mais lenta não substitui")
	lap.time = 96.9
	lap.valid = false
	check(not Records.save_lap("teste", "corvette-c6r-gt3", lap), "volta inválida não grava")
	lap.valid = true
	check(not Records.save_lap("", "corvette-c6r-gt3", lap), "sem nick não grava")
	check(Records.save_lap("teste", "corvette-c6r-gt3", lap), "volta mais rápida substitui")
	check(Records.save_lap("teste", "audi-r8-lms-gt3", lap), "outro carro = outro recorde")
	var all := Records.load_all()
	check(all.size() == 2 and absf(float(Records.top(1)[0].time) - 96.9) < 1e-6, "2 recordes, melhor 1:36,900")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
