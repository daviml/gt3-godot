# Etapa 2: câmbio manual, auxílios ligáveis e superfícies da pista (zebra pulando, grama, escape).
# uso: godot --headless --path . --script res://scripts/tests/cambio_superficies.gd
extends SceneTree

const DT := 1.0 / Car.HZ
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func new_car(g: Ground, id := "porsche-992-gt3r") -> Car:
	var car := Car.load_car(g, id)
	car.reset(Vector3(0, car.p.cg, 0), 0.0)
	for i in Car.HZ:
		car.step(DT, 0, 0, 0)
	return car


func run(car: Car, secs: float, steer: float, thr: float, brk: float, up := false, down := false) -> void:
	for i in int(secs * Car.HZ):
		car.step(DT, steer, thr, brk, up, down)


func _init() -> void:
	var flat := FlatGround.new()

	print("câmbio manual")
	var car := new_car(flat)
	car.assists.auto = false
	run(car, 6.0, 0, 1, 0)
	check(car.gear == 1 and car.rpm > car.p.limiter - 300.0, "sem trocar fica em 1ª no corte (%d rpm, %.0f km/h)" % [car.rpm, car.speed() * 3.6])
	run(car, 0.2, 0, 1, 0, true)
	run(car, 0.5, 0, 1, 0, true)
	check(car.gear == 2, "segurar a borboleta sobe só uma marcha (%dª)" % car.gear)
	run(car, 0.2, 0, 1, 0)
	run(car, 0.1, 0, 1, 0, true)
	run(car, 0.2, 0, 1, 0)
	run(car, 0.1, 0, 1, 0, true)
	run(car, 3.0, 0, 1, 0)
	var g := car.gear
	run(car, 0.1, 0, 0, 0, false, true)
	run(car, 0.1, 0, 0, 0)
	run(car, 0.1, 0, 0, 0, false, true)
	run(car, 0.1, 0, 0, 0)
	run(car, 0.1, 0, 0, 0, false, true)
	check(car.gear >= 2, "proteção: não reduz para 1ª a %.0f km/h (estava em %dª, ficou em %dª)" % [car.speed() * 3.6, g, car.gear])
	check(car.shift_count >= 3, "contador de trocas (%d)" % car.shift_count)
	var rev := new_car(flat)
	rev.assists.auto = false
	run(rev, 0.1, 0, 0, 0, false, true)
	run(rev, 0.1, 0, 0, 0)
	run(rev, 0.1, 0, 0, 0, false, true)
	check(rev.gear == -1, "parado: Q duas vezes engata a ré (%d)" % rev.gear)
	run(rev, 2.0, 0, 0.5, 0)
	check(rev.fwd_speed() < -1.0, "de ré anda para trás (%.1f m/s)" % rev.fwd_speed())

	print("ABS e TC")
	var stops := []
	for abs_on in [true, false]:
		var c := new_car(flat)
		c.assists.auto = true
		c.assists.abs = abs_on
		while c.fwd_speed() < 150.0 / 3.6:
			c.step(DT, 0, 1, 0)
		var x0 := c.pos
		var locked := 0
		while c.fwd_speed() > 1.0:
			c.step(DT, 0, 0, 1)
			if c.wheels[0].omega < 1.0 and c.fwd_speed() > 10.0:
				locked += 1
		stops.append([c.pos.distance_to(x0), locked])
	check(stops[0][1] == 0 and stops[1][1] > 100, "sem ABS a dianteira trava (passos travada: com %d, sem %d)" % [stops[0][1], stops[1][1]])
	check(stops[1][0] > stops[0][0] + 3.0, "sem ABS freia pior: 150–0 em %.1f m com, %.1f m sem" % [stops[0][0], stops[1][0]])
	var spin := []
	for tc_on in [true, false]:
		# saída de curva lenta: 50 km/h em 1ª, volante virado e pé no fundo
		var c := new_car(flat)
		c.assists.tc = tc_on
		c.assists.auto = false
		c.vel = (c.basis() * Vector3.FORWARD) * 14.0
		for w in c.wheels:
			w.omega = 14.0 / c.p.radius
		var kmax := 0.0
		var cut := 0.0
		for i in Car.HZ:
			c.step(DT, 0.5, 1, 0)
			kmax = maxf(kmax, c.wheels[2].kappa)
			cut = maxf(cut, c.tc_cut)
		spin.append([kmax, cut])
	check(spin[0][1] > 0.0 and spin[1][1] == 0.0, "TC corta só ligado (corte máx %.2f / %.2f)" % [spin[0][1], spin[1][1]])
	check(spin[1][0] > spin[0][0], "sem TC a traseira patina mais (slip máx %.2f com, %.2f sem)" % [spin[0][0], spin[1][0]])

	print("superfícies")
	var track := Track.new("res://data/track/track.json")
	var seen := {}
	var bumps := 0.0
	var fz_var := 0.0
	# pela pista: para cada amostra com zebra, sonda centro, zebra, escape e grama
	for i in track.n:
		for side in [-1.0, 1.0]:
			var edge: float = track.wr[i] if side > 0 else track.wl[i]
			var kerb: float = track.kerb_r[i] if side > 0 else track.kerb_l[i]
			var run_w: float = track.run_r[i] if side > 0 else track.run_l[i]
			var wall: float = track.wall_r[i] if side > 0 else track.wall_l[i]
			for d in [0.0, edge + kerb * 0.5, edge + kerb + run_w * 0.5, wall - 0.5]:
				var at: Vector3 = track.P[i] + track.R[i] * side * d + Vector3.UP * 0.5
				if track.probe(at, Vector3.DOWN, 2.0, i) >= 0.0:
					seen[track.hit_surface] = seen.get(track.hit_surface, 0) + 1
					bumps = maxf(bumps, track.hit_bump)
	var names := []
	for k in seen:
		names.append("%s %d" % [Ground.NAMES[k], seen[k]])
	print("  sondas: ", ", ".join(names))
	check(seen.has(Ground.ASPHALT) and seen.has(Ground.KERB) and seen.has(Ground.RUNOFF) and seen.has(Ground.GRASS),
		"asfalto, zebra, escape e grama aparecem")
	check(bumps > 0.002, "zebra ondulada (relevo máx %.1f mm)" % (bumps * 1000.0))
	# carro andando com as rodas da direita na zebra de uma curva: Fz vibra
	var k := -1
	for i in track.n:
		if track.kerb_r[i] > 0.0 and track.kerb_r[(i + 15) % track.n] > 0.0 and absf(track.curv[i]) < 0.01:
			k = i
			break
	var c := Car.load_car(track, "porsche-992-gt3r")
	var t0 := track.T[k]
	var off: float = track.wr[k] + 0.3 - c.p.track_f / 2.0
	c.reset(track.P[k] + track.R[k] * off + Vector3.UP * (c.p.cg + 0.05), atan2(-t0.x, -t0.z))
	for i in Car.HZ / 2:
		c.step(DT, 0, 0, 0)
	c.vel = (c.basis() * Vector3.FORWARD) * 25.0
	for w in c.wheels:
		w.omega = 25.0 / c.p.radius
	c.gear = 3
	var fz_min := INF
	var fz_max := 0.0
	var on_kerb := 0
	for i in int(Car.HZ * 0.6):
		c.step(DT, 0, 0.3, 0)
		var w: Car.Wheel = c.wheels[1]
		if w.surface == Ground.KERB:
			on_kerb += 1
			fz_min = minf(fz_min, w.fz)
			fz_max = maxf(fz_max, w.fz)
	check(on_kerb > 50, "roda dianteira direita passou pela zebra (%d passos)" % on_kerb)
	check(fz_max - fz_min > 500.0, "zebra pula: carga na roda varia %.0f–%.0f N a 90 km/h" % [fz_min, fz_max])

	print("OK" if ok else "FALHOU")
	quit(0 if ok else 1)
