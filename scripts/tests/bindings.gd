# Configuração de controle: mapa de comandos (Bindings), escolha do controle (PadManager) e ajustes finos.
# Usa eventos sintéticos de aparelhos fictícios (ids 7 e 8); guarda e devolve o user://jogo.cfg.
# uso: godot --headless --path . --script res://scripts/tests/bindings.gd
extends SceneTree

const CFG := "user://jogo.cfg"
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func near(a: float, b: float, tol := 0.01) -> bool:
	return absf(a - b) <= tol


func axis(d: int, a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = d
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func button(d: int, b: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = d
	e.button_index = b
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _initialize() -> void:
	var backup := FileAccess.get_file_as_bytes(CFG) if FileAccess.file_exists(CFG) else PackedByteArray()
	_run()
	# devolve a configuração real
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	Bindings.load_settings()
	print("TUDO OK" if ok else "HOUVE FALHAS")
	quit(0 if ok else 1)


func _run() -> void:
	Bindings.reset_defaults()

	print("eixos: metade positiva, negativa e inteiro")
	check(near(Bindings.axis_part(0.6, 1), 0.6) and Bindings.axis_part(-0.6, 1) == 0.0, "s=1 pega só o lado positivo")
	check(near(Bindings.axis_part(-0.6, -1), 0.6), "s=-1 pega o lado negativo")
	check(Bindings.axis_part(-1.0, 2) == 0.0 and near(Bindings.axis_part(0.0, 2), 0.5) and Bindings.axis_part(1.0, 2) == 1.0, "s=2: gatilho -1..1 vira 0..1")

	print("padrões iguais aos de antes (analógico E, RT/LT, RB/A, LB/X, Y, Back)")
	axis(7, JOY_AXIS_LEFT_X, -0.6)
	axis(7, JOY_AXIS_TRIGGER_RIGHT, 0.8)
	check(near(Bindings.pad_value(7, "steer_left"), 0.6) and Bindings.pad_value(7, "steer_right") == 0.0, "analógico à esquerda = steer_left 0,6")
	check(near(Bindings.pad_value(7, "gas"), 0.8), "RT 0,8 = acelerador 0,8")
	button(7, JOY_BUTTON_A, true)
	check(Bindings.pad_value(7, "shift_up") == 1.0, "A sobe marcha")
	button(7, JOY_BUTTON_A, false)
	check(Bindings.pad_text("shift_up") == "RB / A", "texto do comando: RB / A")
	check(Bindings.key_text("gas") == "W / ↑", "teclado: W / ↑ (%s)" % Bindings.key_text("gas"))

	print("remapear e trocar comandos em conflito")
	Bindings.bind_pad("gas", {"t": "btn", "i": JOY_BUTTON_A})
	check(Bindings.pad_text("gas") == "A" and Bindings.pad_text("shift_up") == "RB", "acelerar no A tira o A da marcha (fica RB)")
	button(7, JOY_BUTTON_A, true)
	check(Bindings.pad_value(7, "gas") == 1.0, "A acelera")
	button(7, JOY_BUTTON_A, false)
	Bindings.bind_pad("camera", {"t": "btn", "i": JOY_BUTTON_RIGHT_SHOULDER})
	check(Bindings.pad_text("shift_up") == "Y", "câmera no RB: subir marcha herda o Y (troca)")
	Bindings.bind_pad("brake", {"t": "btn", "i": JOY_BUTTON_Y})
	check(Bindings.pad_text("shift_up") == "—", "frear no Y: subir marcha não herda o eixo LT (ação de botão fica sem ligação)")
	Bindings.bind_key("gas", KEY_C)
	check(Bindings.key_text("gas") == "C" and Bindings.key_text("camera") == "W / ↑", "tecla C no acelerador: câmera herda W / ↑")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = true
	check(Bindings.event_is(ev, "camera") and not Bindings.event_is(ev, "gas"), "evento W agora é câmera")
	var evb := InputEventJoypadButton.new()
	evb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	evb.pressed = true
	check(Bindings.event_is(evb, "camera"), "evento RB é câmera")

	print("salvar e carregar")
	Bindings.bind_pad("steer_right", {"t": "axis", "i": JOY_AXIS_RIGHT_X, "s": 1})
	Bindings.set_tuning("zona_morta", 0.15)
	Bindings.load_settings()
	check(Bindings.pad_text("gas") == "A" and Bindings.key_text("gas") == "C", "mapa volta do jogo.cfg")
	check(Bindings.pad_text("steer_right") == "Analógico D →", "eixo salvo com o sentido (%s)" % Bindings.pad_text("steer_right"))
	check(near(Bindings.deadzone, 0.15), "zona morta salva")
	Bindings.reset_defaults()
	check(Bindings.pad_text("shift_up") == "RB / A" and Bindings.key_text("camera") == "C" and near(Bindings.deadzone, 0.08), "restaurar padrão")

	print("PadManager: vale o controle que se mexe, não o primeiro da lista")
	PadManager._rest.clear()
	PadManager.active = 7
	axis(7, JOY_AXIS_LEFT_Y, -1.0) # aparelho fantasma com eixo travado
	axis(8, JOY_AXIS_LEFT_X, 0.0)
	check(PadManager.scan([7, 8]) == -1, "primeira varredura só grava o repouso")
	check(PadManager.scan([7, 8]) == -1, "eixo travado no repouso não conta como movimento")
	axis(8, JOY_AXIS_LEFT_X, 0.9)
	check(PadManager.scan([7, 8]) == 8, "analógico do aparelho 8 mexeu: ele assume")
	PadManager.active = 8
	axis(8, JOY_AXIS_LEFT_X, 0.0)
	button(7, JOY_BUTTON_B, true)
	check(PadManager.scan([7, 8]) == 7, "botão no aparelho 7: volta para ele")
	button(7, JOY_BUTTON_B, false)

	print("ajustes finos no InputReader")
	var inp := InputReader.new()
	inp.pedal_deadzone = 0.2
	var raw := {"left": false, "right": false, "gas": false, "brake": false, "up": false, "down": false,
		"pad": {"x": 0.0, "rt": 0.6, "lt": 0.1, "up": false, "down": false, "reset": false}}
	inp.filter(1.0 / 60.0, 10.0, raw)
	check(near(inp.throttle, 0.5) and inp.brake == 0.0, "zona morta 0,2 nos gatilhos: 0,6 vira 0,5 e 0,1 vira 0")
	var a := InputReader.new()
	var b := InputReader.new()
	b.deadzone = 0.3
	raw.pad = {"x": 0.25, "rt": 0.0, "lt": 0.0, "up": false, "down": false, "reset": false}
	for i in 30:
		a.filter(1.0 / 60.0, 10.0, raw)
		b.filter(1.0 / 60.0, 10.0, raw)
	check(a.steer > 0.0 and b.steer == 0.0, "zona morta 0,3: analógico em 0,25 não esterça")
	var c := InputReader.new()
	c.linearity = 1.0
	for i in 60:
		c.filter(1.0 / 60.0, 10.0, raw)
	check(c.steer > a.steer, "curva 1,0 é mais direta que 1,6 no mesmo analógico")

	print("captura de eixo no menu")
	var cp := ControlsPanel.new()
	var rest := PackedFloat32Array()
	rest.resize(JOY_AXIS_MAX)
	rest[JOY_AXIS_TRIGGER_RIGHT] = -1.0
	cp._capture_rest[3] = rest
	check(cp.capture_axis(3, JOY_AXIS_TRIGGER_RIGHT, -0.7).is_empty(), "mexeu pouco: ainda não liga")
	check(int(cp.capture_axis(3, JOY_AXIS_TRIGGER_RIGHT, 0.2).get("s", 0)) == 2, "gatilho que repousa em -1 vira eixo inteiro")
	check(int(cp.capture_axis(3, JOY_AXIS_LEFT_X, -0.7).get("s", 0)) == -1, "analógico para a esquerda: metade negativa")
	cp.free()
