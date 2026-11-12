# Etapa 5: câmera de perseguição (porte do camera.ts do web). Confere distância, atraso, FOV e tremida
# numa reta (aceleração e freada) e numa volta do RefBot do Porsche, com a câmera a 60 quadros por segundo.
# uso: godot --headless --path . --script res://scripts/tests/camera.gd
extends SceneTree

const DT := 1.0 / Car.HZ
const FRAME := 1.0 / 60.0
var ok := true
var cam: Camera3D


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


## anda `secs` segundos atualizando a câmera a 60 Hz; `each` recebe a câmera depois de cada quadro
func drive(car: Car, chase: ChaseCamera, secs: float, inp: Callable, each: Callable) -> void:
	var acc := 0.0
	for i in int(secs * Car.HZ):
		var u: Array = inp.call()
		car.step(DT, u[0], u[1], u[2])
		acc += DT
		if acc >= FRAME:
			chase.update(acc)
			each.call(chase)
			acc = 0.0


## ângulo (graus) entre o rumo da câmera e a frente do carro no plano
func lag_deg(car: Car, chase: ChaseCamera) -> float:
	var f := -car.basis().z
	f.y = 0.0
	f = f.normalized()
	return rad_to_deg(absf(atan2(chase.heading.x * f.z - chase.heading.z * f.x, chase.heading.dot(f))))


func _initialize() -> void:
	cam = Camera3D.new()
	root.add_child(cam)

	print("reta: aceleração e freada")
	var flat := FlatGround.new()
	var car := Car.load_car(flat, "corvette-c6r-gt3")
	car.reset(Vector3(0, car.p.cg, 0), 0.0)
	for i in Car.HZ:
		car.step(DT, 0, 0, 0)
	var chase := ChaseCamera.new(cam, car)
	chase.update(FRAME)
	check(is_equal_approx(chase.dist.value, 6.8), "parado: 6,8 m atrás (%.2f m)" % chase.dist.value)
	check(absf(cam.position.y - car.pos.y - 1.85) < 0.01, "1,85 m acima do carro (%.2f m)" % (cam.position.y - car.pos.y))
	check(is_equal_approx(chase.fov.value, 50.0), "FOV 50° parado (%.1f°)" % chase.fov.value)
	var d_max := [0.0]
	drive(car, chase, 2.0, func(): return [0, 1, 0], func(c): d_max[0] = maxf(d_max[0], c.dist.value))
	check(d_max[0] > 6.92 and d_max[0] < 7.1, "acelerando, se afasta ~15–20 cm (máx. %.2f m)" % d_max[0])
	drive(car, chase, 16.0, func(): return [0, 1, 0], func(_c): pass)
	var kmh := car.speed() * 3.6
	var fov_alvo := 50.0 + minf(3.5, car.speed() * 0.045)
	check(chase.fov.value > 50.5 and absf(chase.fov.value - fov_alvo) < 0.1, "FOV abre com a velocidade: %.1f° a %.0f km/h (alvo %.1f°; +3,5° a partir de 280 km/h)" % [chase.fov.value, kmh, fov_alvo])
	var d_min := [99.0]
	var g_min := [0.0]
	drive(car, chase, 2.5, func(): return [0, 0, 1], func(c): d_min[0] = minf(d_min[0], c.dist.value); g_min[0] = minf(g_min[0], car.g_long))
	var d_alvo := 6.8 + 0.16 * maxf(g_min[0], -2.2)
	check(absf(d_min[0] - d_alvo) < 0.04, "freando (%.1f g), chega %.0f cm para a frente (alvo %.0f cm; ~35 cm a 2,2 g)" % [g_min[0], (6.8 - d_min[0]) * 100.0, (6.8 - d_alvo) * 100.0])
	check(chase.shake.value < 1e-3, "sem tremida na reta lisa abaixo de 250 km/h")

	print("volta do RefBot (Audi R8), câmera a 60 Hz")
	var track := Track.new("res://data/track/track.json")
	car = Car.load_car(track, "audi-r8-lms-gt3")
	car.assists.auto = true
	var bot := RefBot.new(track, car, RefBot.load_ref("interlagos-r8"))
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
	chase = ChaseCamera.new(cam, car)
	chase.update(FRAME)
	# estatísticas da volta
	var st := {"lag": 0.0, "dmin": 99.0, "dmax": 0.0, "shake": 0.0, "kerb_frames": 0, "frames": 0,
		"jy": 0.0, "car_jy": 0.0, "y": [cam.position.y, cam.position.y], "cy": [car.pos.y, car.pos.y], "fmax": 0.0, "vmax": 0.0}
	drive(car, chase, 100.0, func(): return bot.drive(), func(c):
		st.frames += 1
		st.lag = maxf(st.lag, lag_deg(car, c))
		st.dmin = minf(st.dmin, c.dist.value)
		st.dmax = maxf(st.dmax, c.dist.value)
		st.shake = maxf(st.shake, c.shake.value)
		if c.shake.value > 0.004:
			st.kerb_frames += 1
		st.fmax = maxf(st.fmax, c.fov.value)
		st.vmax = maxf(st.vmax, car.speed() * 3.6)
		# solavanco vertical: variação da velocidade vertical entre quadros (2ª diferença), câmera × carro.
		# Sem a tremida da zebra, que é proposital.
		var y := cam.position.y
		if c.shake.value < 1e-3:
			st.jy = maxf(st.jy, absf(y - 2.0 * st.y[1] + st.y[0]))
		st.car_jy = maxf(st.car_jy, absf(car.pos.y - 2.0 * st.cy[1] + st.cy[0]))
		st.y = [st.y[1], y]
		st.cy = [st.cy[1], car.pos.y])
	check(st.lag <= 6.01, "atraso no rumo nunca passa de 6° (máx. %.2f°)" % st.lag)
	check(st.lag > 2.0, "nas curvas aparece um pouco da lateral (atraso máx. %.2f°)" % st.lag)
	check(st.dmin > 6.3 and st.dmax < 7.1, "distância entre 6,3 e 7,1 m (%.2f–%.2f m)" % [st.dmin, st.dmax])
	check(st.fmax <= 53.5, "FOV no máximo 53,5° (%.1f° a %.0f km/h)" % [st.fmax, st.vmax])
	check(st.kerb_frames > 0 and st.shake <= 0.0181, "tremida leve na zebra (máx. %.1f mm, %d de %d quadros)" % [st.shake * 1000.0, st.kerb_frames, st.frames])
	check(st.jy < st.car_jy * 0.5, "altura calma: solavanco da câmera %.2f cm/quadro² (carro: %.2f)" % [st.jy * 100.0, st.car_jy * 100.0])

	print("modos")
	chase.next()
	chase.update(FRAME)
	var local := car.basis().inverse() * (cam.position - car.pos)
	check(chase.mode_name() == "capô" and local.distance_to(Vector3(0, 0.85, -1.3)) < 0.01, "C: capô, preso ao carro")
	chase.next()
	chase.update(FRAME)
	check(chase.mode_name() == "longe" and is_equal_approx(chase.dist.value, 11.0), "C: longe, 11 m (%.1f m)" % chase.dist.value)
	chase.next()
	check(chase.mode_name() == "perseguição", "C: volta para a perseguição")
	check(is_equal_approx(ChaseCamera.fit_fov(50.0, 16.0 / 9.0), 50.0) and ChaseCamera.fit_fov(50.0, 0.5) > 50.0, "tela estreita/retrato abre o FOV")

	print("TUDO OK" if ok else "FALHAS")
	quit(0 if ok else 1)
