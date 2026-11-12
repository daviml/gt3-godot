# Etapa 3: novos esquemas de controles mobile (Padrão, Fly-by-wire, Inclinar, Legacy),
# limites de esterço escalados por grip_scale, ré pelo freio (brake_to_reverse) e paridade com o web.
# uso: godot --headless --path . --script res://scripts/tests/controles.gd
extends SceneTree

const TouchControls = preload("res://scripts/input/touch_controls.gd")
const DT := 1.0 / 60.0
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func raw(left := false, right := false, gas := false, brake := false, pad = null, tilt = null) -> Dictionary:
	var d := {"left": left, "right": right, "gas": gas, "brake": brake, "up": false, "down": false, "pad": pad}
	if tilt != null:
		d["tilt_steer"] = float(tilt)
	return d


func pad(x: float, rt := 0.0, lt := 0.0, rst := false) -> Dictionary:
	return {"x": x, "rt": rt, "lt": lt, "up": false, "down": false, "reset": rst}


## segura a entrada por `secs` segundos a `v` m/s
func hold(inp: InputReader, secs: float, v: float, r: Dictionary) -> void:
	for i in roundi(secs / DT):
		inp.filter(DT, v, r)


func near(a: float, b: float, tol := 0.01) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	print("limite de esterço pela velocidade (14/v, entre 0,18 e 1)")
	check(InputReader.steer_limit(10.0) == 1.0, "36 km/h libera tudo")
	check(near(InputReader.steer_limit(20.0), 0.7), "72 km/h: 0,70")
	check(near(InputReader.steer_limit(60.0), 0.2333), "216 km/h: 0,23")
	check(InputReader.steer_limit(90.0) == 0.18, "324 km/h: piso 0,18")

	print("escala do limite de esterço no arcade (grip_scale)")
	var inp_arc := InputReader.new()
	inp_arc.grip_scale = 1.8
	hold(inp_arc, 0.5, 60.0, raw(false, true))
	var arc_limit: float = minf(1.0, InputReader.steer_limit(60.0) * 1.8)
	check(near(inp_arc.steer, arc_limit), "a 216 km/h no Arcade com 1.8x grip: limite subiu para %.3f (vs 0,23)" % inp_arc.steer)

	print("teclado: toque curto corrige, segurar vai ao batente")
	var kb := InputReader.new()
	hold(kb, 0.1, 10.0, raw(false, true))
	check(near(kb.steer, 0.15, 0.02), "0,1 s segurando: 0.150 (≈0,15)")
	hold(kb, 0.15, 10.0, raw(false, true))
	check(near(kb.steer, 0.375, 0.03), "0,25 s: 0.375 (≈0,375)")
	hold(kb, 0.15, 10.0, raw(false, true))
	check(near(kb.steer, 1.0), "0,4 s: batente (1.000)")
	hold(kb, 0.5, 60.0, raw(false, true))
	check(near(kb.steer, 0.2333), "a 216 km/h o batente é 0,23 (0.233)")
	hold(kb, 0.2, 60.0, raw())
	check(kb.steer == 0.0, "soltar volta ao centro (7/s)")
	hold(kb, 0.1, 10.0, raw(false, false, true))
	check(near(kb.throttle, 0.4, 0.02), "acelerador sobe a 4/s (0.40)")
	hold(kb, 0.05, 10.0, raw(false, false, false, true))
	check(near(kb.throttle, 0.0, 0.01) and near(kb.brake, 0.3, 0.02), "solta a 8/s, freio sobe a 6/s")
	check(kb.source == "teclado", "fonte: teclado")

	print("toque mobile: 4 esquemas no InputReader")
	# 1. Legacy
	var tc_leg := InputReader.new()
	tc_leg.touch = true
	tc_leg.touch_mode = "legacy"
	tc_leg.touch_keys["left"] = true
	hold(tc_leg, 0.1, 20.0, raw(true))
	check(near(tc_leg.steer, -0.1733, 0.01), "legacy: 0,1 s a 72 km/h: -0.173")
	hold(tc_leg, 2.0, 20.0, raw(true))
	check(near(tc_leg.steer, -0.55), "legacy: batente a 72 km/h = -0.55")
	check(tc_leg.source == "toque", "legacy fonte: toque")

	# 2. Padrão (analógico proporcional + pedais proporcionais com filtro)
	var tc_pad := InputReader.new()
	tc_pad.touch = true
	tc_pad.touch_mode = "padrao"
	tc_pad.touch_axes["steer"] = 0.5
	tc_pad.touch_axes["gas"] = 0.8
	tc_pad.touch_axes["brake"] = 0.0
	hold(tc_pad, 0.3, 20.0, raw())
	var pad_target: float = 0.5 * minf(1.0, maxf(0.22, 0.15 + 8.0 / 20.0))
	check(near(tc_pad.steer, pad_target, 0.02), "padrao: esterço proporcional analógico = %.3f" % tc_pad.steer)
	check(near(tc_pad.throttle, 0.8, 0.02), "padrao: acelerador proporcional = %.2f" % tc_pad.throttle)
	check(tc_pad.source == "toque", "padrao fonte: toque")

	# 3. Fly-by-wire (barra vertical multifunção)
	var tc_fly := InputReader.new()
	tc_fly.touch = true
	tc_fly.touch_mode = "fly"
	tc_fly.touch_axes["gas"] = 0.0
	tc_fly.touch_axes["brake"] = 0.9
	hold(tc_fly, 0.3, 20.0, raw())
	check(near(tc_fly.brake, 0.9, 0.02) and tc_fly.throttle == 0.0, "fly: barra puxada para baixo freia a 0.90 (%.2f)" % tc_fly.brake)

	# 4. Inclinar (giroscópio / acelerômetro com filtro)
	var tc_tilt := InputReader.new()
	tc_tilt.touch = true
	tc_tilt.touch_mode = "inclinar"
	hold(tc_tilt, 0.3, 20.0, raw(false, false, false, false, null, 0.6))
	var tilt_target: float = 0.6 * minf(1.0, maxf(0.22, 0.15 + 8.0 / 20.0))
	check(near(tc_tilt.steer, tilt_target, 0.02), "inclinar: direção lida do sensor = %.3f" % tc_tilt.steer)

	print("controle físico: zona morta, curva 1,6 e velocidade do volante")
	var gp := InputReader.new()
	hold(gp, 0.5, 10.0, raw(false, false, false, false, pad(0.07)))
	check(gp.steer == 0.0, "dentro da zona morta (0,07) fica parado")
	gp = InputReader.new()
	gp.filter(DT, 10.0, raw(false, false, false, false, pad(1.0)))
	check(near(gp.steer, 5.0 * DT), "tranco no analógico: um quadro só vira 5/60")
	hold(gp, 0.2, 10.0, raw(false, false, false, false, pad(1.0)))
	check(near(gp.steer, 1.0), "~0,2 s até o batente")
	hold(gp, 1.0, 10.0, raw(false, false, false, false, pad(0.5)))
	var expect := pow((0.5 - 0.08) / 0.92, 1.6)
	check(near(gp.steer, expect, 0.002), "meio curso = 0.285 (curva 1,6)")
	hold(gp, 1.0, 20.0, raw(false, false, false, false, pad(0.5)))
	check(near(gp.steer, expect * 0.7, 0.002), "a 72 km/h vezes o limite 0,7")
	hold(gp, 0.1, 20.0, raw(false, false, false, false, pad(0.0, 0.8, 0.1)))
	check(gp.throttle == 0.8 and gp.brake == 0.1 and gp.source == "controle", "gatilhos analógicos direto")
	hold(gp, 0.1, 20.0, raw(false, false, true, false, pad(0.0)))
	check(gp.source == "teclado" and gp.throttle > 0.0, "controle parado + teclado mexendo: vale o teclado")
	gp.filter(DT, 20.0, raw(false, false, false, false, pad(0.0, 0, 0, true)))
	check(gp.reset, "Back aperta o reset")
	gp.filter(DT, 20.0, raw(false, false, false, false, pad(0.0, 0, 0, true)))
	check(not gp.reset, "segurar Back não repete o reset")

	print("ré automática no toque (brake_to_reverse)")
	var flat := FlatGround.new()
	var car := Car.load_car(flat, "corvette-c6r-gt3")
	car.reset(Vector3(0, car.p.cg, 0), 0.0)
	car.assists["brake_reverse"] = true
	check(car.gear == 1, "inicia em 1a marcha")
	# parado, segurar freio por 0.5s (>0.4s) engata ré
	for i in roundi(0.5 / DT):
		car.step(DT, 0, 0, 0.8)
	check(car.gear == -1, "parado com freio por 0,5s engatou ré (gear = -1)")
	# em ré, segurar acelerador por 0.1s volta para 1a marcha
	for i in roundi(0.2 / DT):
		car.step(DT, 0, 0.5, 0)
	check(car.gear == 1, "acelerar parado em ré voltou para 1a marcha")

	print("vibração háptica")
	var rb := Rumble.new()
	for i in Car.HZ:
		car.step(1.0 / Car.HZ, 0, 0, 0)
	check(rb.compute(car, DT) == Vector2.ZERO, "parado: nada")
	car.assists.auto = true
	for i in 10 * Car.HZ:
		car.step(1.0 / Car.HZ, 0, 1, 0)
	var max_strong := 0.0
	for f in 120:
		for i in Car.HZ / 60:
			car.step(1.0 / Car.HZ, 0, 0, 1)
		max_strong = maxf(max_strong, rb.compute(car, DT).x)
	check(max_strong >= 0.3, "freada com ABS vibra o motor forte (%.2f)" % max_strong)
	rb = Rumble.new()
	rb.compute(car, DT)
	car.vel = car.vel.normalized() * maxf(car.speed() - 1.5, 0.0)
	rb._next = 0.0
	var hit := rb.compute(car, DT)
	check(hit.x > 0.9, "batida (−90 m/s² num quadro): motor forte 0.93")

	print("UI TouchControls: interação, pointer capture e transição suave")
	var tcs := TouchControls.new()
	root.add_child(tcs)
	await process_frame

	print("curva de pedal e sensor de inclinação")
	check(tcs.pedal_curve(0.0) == 0.0, "pedal 0%: 0")
	check(near(tcs.pedal_curve(0.1), 0.0667), "pedal 10% de toque: 0,067 (zona inicial amortecida)")
	check(near(tcs.pedal_curve(0.5), 0.55), "pedal meio curso: 0,55")
	check(tcs.pedal_curve(0.9) == 1.0, "pedal 90% de toque: já é 100%")
	check(tcs.wrap_deg(190.0) == -170.0, "wrap_deg: 190 vira -170")
	check(tcs.wrap_deg(-200.0) == 160.0, "wrap_deg: -200 vira 160")
	var sz := tcs.get_viewport_rect().size
	var k := sz.y / 400.0
	var menu_hits := [0]
	var recenter_hits := [0]
	tcs.menu_pressed.connect(func(): menu_hits[0] += 1)
	tcs.recenter_requested.connect(func(): recenter_hits[0] += 1)

	var touch_down := func(i: int, p: Vector2) -> void:
		var e := InputEventScreenTouch.new()
		e.index = i; e.position = p; e.pressed = true
		tcs._input(e)

	var touch_up := func(i: int, p: Vector2) -> void:
		var e := InputEventScreenTouch.new()
		e.index = i; e.position = p; e.pressed = false
		tcs._input(e)

	var touch_drag := func(i: int, p: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = i; e.position = p
		tcs._input(e)

	# 1. Modo Padrão: analógico esquerdo + pedais com transição suave
	tcs.mode = "padrao"
	var stick_c := Vector2((16 + 85) * k, sz.y - (16 + 38) * k)
	var gas_c := Vector2(sz.x - (16 + 42) * k, sz.y - (16 + 75) * k)
	var brake_c := Vector2(sz.x - (112 + 42) * k, sz.y - (16 + 62) * k)

	# analógico: arrasta para a direita
	touch_down.call(0, stick_c)
	touch_drag.call(0, stick_c + Vector2(60 * k, 0))
	check(tcs.axes["steer"] > 0.8, "analógico para direita: steer = %.2f" % tcs.axes["steer"])
	touch_up.call(0, stick_c)
	check(tcs.axes["steer"] == 0.0, "soltar analógico volta a zero")

	# transição suave entre pedais: começa no freio e desliza para o acelerador
	touch_down.call(1, brake_c)
	check(tcs.axes["brake"] > 0.3 and tcs.axes["gas"] == 0.0, "polegar no freio ativa freio")
	touch_drag.call(1, gas_c)
	check(tcs.axes["brake"] == 0.0 and tcs.axes["gas"] > 0.3, "deslizar para o acelerador transfere sem soltar o dedo")
	touch_up.call(1, gas_c)
	check(tcs.axes["gas"] == 0.0, "soltar pedal volta a zero")

	# 2. Modo Fly-by-wire: barra vertical multifunção
	tcs.mode = "fly"
	var fly_c := Vector2(sz.x - (16 + 45) * k, sz.y - (16 + 90) * k)
	touch_down.call(2, fly_c)
	check(tcs.axes["gas"] == 0.0 and tcs.axes["brake"] == 0.0, "fly-by-wire: centro neutro = 0")
	touch_drag.call(2, fly_c - Vector2(0, 50 * k))
	check(tcs.axes["gas"] > 0.4 and tcs.axes["brake"] == 0.0, "fly-by-wire: para cima acelera (%.2f)" % tcs.axes["gas"])
	touch_drag.call(2, fly_c + Vector2(0, 50 * k))
	check(tcs.axes["gas"] == 0.0 and tcs.axes["brake"] > 0.4, "fly-by-wire: para baixo freia (%.2f)" % tcs.axes["brake"])
	touch_up.call(2, fly_c)

	# 3. Modo Inclinar: botão recalibrar
	tcs.mode = "inclinar"
	var rec_c := Vector2((16 + 65) * k, sz.y - (16 + 23) * k)
	touch_down.call(3, rec_c)
	touch_up.call(3, rec_c)
	check(recenter_hits[0] == 1, "modo inclinar: botão recalibrar emitido")

	# 4. Menu comum a todos os modos
	var menu_c := Vector2((16 + 26) * k, sz.y - (124 + 20) * k)
	touch_down.call(4, menu_c)
	check(menu_hits[0] == 0, "☰ não abre no touch down")
	touch_up.call(4, menu_c)
	check(menu_hits[0] == 1, "☰ abre no touch up")

	print("TUDO OK" if ok else "FALHOU")
	quit(0 if ok else 1)
