# Etapa 3: curva e suavização da direção (input.ts do web), vibração (rumble.ts) e botões de toque (touch.ts).
# uso: godot --headless --path . --script res://scripts/tests/controles.gd
extends SceneTree

const DT := 1.0 / 60.0
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func raw(left := false, right := false, gas := false, brake := false, pad = null) -> Dictionary:
	return {"left": left, "right": right, "gas": gas, "brake": brake, "up": false, "down": false, "pad": pad}


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

	print("teclado: toque curto corrige, segurar vai ao batente")
	var kb := InputReader.new()
	hold(kb, 0.1, 10.0, raw(false, true))
	check(near(kb.steer, 0.15, 0.02), "0,1 s segurando: %.3f (≈0,15)" % kb.steer)
	hold(kb, 0.15, 10.0, raw(false, true))
	check(near(kb.steer, 0.375, 0.03), "0,25 s: %.3f (≈0,375)" % kb.steer)
	hold(kb, 0.15, 10.0, raw(false, true))
	check(near(kb.steer, 1.0), "0,4 s: batente (%.3f)" % kb.steer)
	hold(kb, 0.5, 60.0, raw(false, true))
	check(near(kb.steer, 0.2333), "a 216 km/h o batente é 0,23 (%.3f)" % kb.steer)
	hold(kb, 0.2, 60.0, raw())
	check(kb.steer == 0.0, "soltar volta ao centro (7/s)")
	hold(kb, 0.1, 10.0, raw(false, false, true))
	check(near(kb.throttle, 0.4, 0.02), "acelerador sobe a 4/s (%.2f)" % kb.throttle)
	hold(kb, 0.05, 10.0, raw(false, false, false, true))
	check(near(kb.throttle, 0.0, 0.01) and near(kb.brake, 0.3, 0.02), "solta a 8/s, freio sobe a 6/s")
	check(kb.source == "teclado", "fonte: teclado")

	print("toque no celular: direção antiga (rampa constante, limite próprio)")
	var tc := InputReader.new()
	tc.touch = true
	tc.touch_keys["left"] = true
	hold(tc, 0.1, 20.0, raw(true))
	check(near(tc.steer, -0.1733, 0.01), "0,1 s a 72 km/h: %.3f (2,6/1,5 por s)" % tc.steer)
	hold(tc, 2.0, 20.0, raw(true))
	check(near(tc.steer, -0.55), "batente a 72 km/h = 0,15+8/20 = 0,55 (%.3f)" % tc.steer)
	check(tc.source == "toque", "fonte: toque")

	print("controle: zona morta, curva 1,6 e velocidade do volante")
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
	check(near(gp.steer, expect, 0.002), "meio curso = %.3f (curva 1,6)" % expect)
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

	print("vibração")
	var flat := FlatGround.new()
	var car := Car.load_car(flat, "porsche-992-gt3r")
	car.reset(Vector3(0, car.p.cg, 0), 0.0)
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
	check(hit.x > 0.9, "batida (−90 m/s² num quadro): motor forte %.2f" % hit.x)

	print("botões de toque")
	var tcs := TouchControls.new()
	root.add_child(tcs)
	await process_frame
	var sz := tcs.get_viewport_rect().size
	var k := sz.y / 400.0
	var menu_hits := [0]
	tcs.menu_pressed.connect(func(): menu_hits[0] += 1)
	var touch_ev := func(i: int, p: Vector2, down: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = i
		e.position = p
		e.pressed = down
		tcs._input(e)
	var gas_c := Vector2(sz.x - (16 + 42) * k, sz.y - (16 + 75) * k)
	var left_c := Vector2((16 + 46) * k, sz.y - (16 + 46) * k)
	touch_ev.call(0, left_c, true)
	touch_ev.call(1, gas_c, true)
	check(tcs.keys.has("left") and tcs.keys.has("gas"), "dois dedos: esquerda + acelerador juntos")
	touch_ev.call(0, left_c, false)
	check(not tcs.keys.has("left") and tcs.keys.has("gas"), "solta um dedo, o outro segue")
	var d := InputEventScreenDrag.new()
	d.index = 1
	d.position = Vector2(sz.x / 2, sz.y / 2)
	tcs._input(d)
	check(tcs.keys.is_empty(), "arrastar para fora do botão solta")
	touch_ev.call(2, Vector2(sz.x - 6 * k, gas_c.y), true)
	check(tcs.keys.has("gas"), "área de toque passa 16 px da borda do acelerador")
	touch_ev.call(2, Vector2(), false)
	touch_ev.call(3, Vector2(sz.x / 2, sz.y / 2), true)
	check(tcs.keys.is_empty(), "meio da tela não aperta nada")
	var menu_c := Vector2((16 + 26) * k, sz.y - (124 + 20) * k)
	touch_ev.call(4, menu_c, true)
	check(menu_hits[0] == 0 and tcs.keys.is_empty(), "☰ não abre ao apertar nem vira tecla")
	touch_ev.call(4, menu_c, false)
	check(menu_hits[0] == 1, "☰ abre ao soltar")

	print("TUDO OK" if ok else "FALHOU")
	quit(0 if ok else 1)
