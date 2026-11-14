# Aba Controles do menu (garagem e pausa): escolha do controle, teste ao vivo, remapeamento e ajustes finos.
# É um Node sem desenho próprio, adicionado junto das linhas da aba: o LmuMenu monta as linhas com
# _add_setting_row (para a busca funcionar) usando os widgets criados aqui, e este nó atualiza o teste ao vivo
# a cada quadro e captura o próximo botão/tecla quando a pessoa pede para trocar um comando.
class_name ControlsPanel
extends Node

const CAPTURE_TIMEOUT := 8.0

var fs := 1.0
## botões de cada ação: {acao: {"pad": Button, "kb": Button}}
var _bind_btns := {}
var _device_opt: OptionButton
var _device_badge: Label
var _live_dev: Label
var _live_last: Label
var _bar_left: ProgressBar
var _bar_right: ProgressBar
var _bar_gas: ProgressBar
var _bar_brake: ProgressBar
var _sliders := {}
var _keyboard_label: Label

## captura em andamento: {"kind": "pad"|"kb", "action": String, "t": segundos} ou vazio
var _capture := {}
## repouso dos eixos de cada aparelho no início da captura (para achar o eixo que mexeu e o sentido)
var _capture_rest := {}


func _init(font_scale := 1.0) -> void:
	fs = font_scale
	process_mode = Node.PROCESS_MODE_ALWAYS
	Bindings.ensure_loaded()


func _ready() -> void:
	if not Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.connect(_on_joy_changed)


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.disconnect(_on_joy_changed)


# ------------------------------------------------------------------ widgets

func _btn(text: String, kind := "outline") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", roundi(12 * fs))
	LmuTheme.apply_button_styles(b, kind, 4, 12, 6)
	return b


func _bar(col: Color, fill_from_end := false) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.show_percentage = false
	p.fill_mode = ProgressBar.FILL_END_TO_BEGIN if fill_from_end else ProgressBar.FILL_BEGIN_TO_END
	p.custom_minimum_size = Vector2(roundi(60 * fs), roundi(10 * fs))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p


## escolha do aparelho: automático ou um controle fixo
func make_device_picker() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_device_opt = OptionButton.new()
	_device_opt.custom_minimum_size = Vector2(roundi(220 * fs), roundi(36 * fs))
	_device_opt.add_theme_font_size_override("font_size", roundi(13 * fs))
	_device_opt.get_popup().add_theme_font_size_override("font_size", roundi(13 * fs))
	_device_opt.focus_mode = Control.FOCUS_NONE
	_device_opt.item_selected.connect(_on_device_selected)
	v.add_child(_device_opt)
	_device_badge = LmuTheme.make_label("", roundi(11 * fs), LmuTheme.TEXT_MUTED, 600)
	v.add_child(_device_badge)
	_refresh_devices()
	return v


## teste ao vivo: volante (esquerda/direita), acelerador, freio, aparelho lido e último botão
func make_live_view() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size.x = roundi(220 * fs)
	var steer := HBoxContainer.new()
	steer.add_theme_constant_override("separation", 2)
	_bar_left = _bar(LmuTheme.ACCENT_BLUE, true)
	_bar_right = _bar(LmuTheme.ACCENT_BLUE)
	steer.add_child(LmuTheme.make_label("Volante", roundi(11 * fs), LmuTheme.TEXT_MUTED, 600))
	steer.add_child(_bar_left)
	steer.add_child(_bar_right)
	v.add_child(steer)
	var ped := HBoxContainer.new()
	ped.add_theme_constant_override("separation", 6)
	_bar_brake = _bar(LmuTheme.ACCENT_RED)
	_bar_gas = _bar(LmuTheme.ACCENT_GREEN)
	ped.add_child(LmuTheme.make_label("Freio", roundi(11 * fs), LmuTheme.TEXT_MUTED, 600))
	ped.add_child(_bar_brake)
	ped.add_child(LmuTheme.make_label("Acel.", roundi(11 * fs), LmuTheme.TEXT_MUTED, 600))
	ped.add_child(_bar_gas)
	v.add_child(ped)
	_live_dev = LmuTheme.make_label("", roundi(11 * fs), LmuTheme.TEXT_SLATE, 600)
	_live_last = LmuTheme.make_label("Último botão: —", roundi(11 * fs), LmuTheme.TEXT_MUTED, 600)
	v.add_child(_live_dev)
	v.add_child(_live_last)
	return v


## botões "Controle: X" e "Teclado: Y" de uma ação
func make_binding_buttons(action: String, show_keyboard := true) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var bp := _btn("")
	bp.custom_minimum_size = Vector2(roundi(150 * fs), roundi(32 * fs))
	bp.pressed.connect(func(): start_capture("pad", action))
	h.add_child(bp)
	var bk: Button = null
	if show_keyboard:
		bk = _btn("")
		bk.custom_minimum_size = Vector2(roundi(130 * fs), roundi(32 * fs))
		bk.pressed.connect(func(): start_capture("kb", action))
		h.add_child(bk)
	_bind_btns[action] = {"pad": bp, "kb": bk}
	_refresh_binding(action)
	return h


## slider de ajuste fino; mostra o valor ao lado
func make_slider(key: String, lo: float, hi: float, step: float, value: float, fmt: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(roundi(150 * fs), roundi(24 * fs))
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := LmuTheme.make_label(fmt % value, roundi(13 * fs), Color.WHITE, 700)
	l.custom_minimum_size.x = roundi(48 * fs)
	s.value_changed.connect(func(x: float):
		l.text = fmt % x
		Bindings.set_tuning(key, x)
	)
	h.add_child(s)
	h.add_child(l)
	_sliders[key] = {"slider": s, "label": l, "fmt": fmt}
	return h


func make_reset_button() -> Control:
	var b := _btn("↺ RESTAURAR PADRÃO")
	b.pressed.connect(func():
		cancel_capture()
		Bindings.reset_defaults()
		PadManager.set_preferred("")
		refresh_all()
	)
	return b


## texto da linha "Comandos de Teclado" (acompanha o mapa)
func keyboard_summary() -> String:
	var parts := []
	for e in [["gas", "Acelerar"], ["brake", "Frear"], ["steer_left", "Esquerda"], ["steer_right", "Direita"],
			["shift_up", "Sobe"], ["shift_down", "Reduz"], ["camera", "Câmera"], ["reset", "Grid"]]:
		parts.append("%s %s" % [e[1], Bindings.key_text(e[0])])
	return " · ".join(parts) + " · Menu Esc"


func set_keyboard_label(l: Label) -> void:
	_keyboard_label = l


# ------------------------------------------------------------------ estado

func refresh_all() -> void:
	for a in _bind_btns:
		_refresh_binding(a)
	for key in _sliders:
		var e: Dictionary = _sliders[key]
		var v: float = {"zona_morta": Bindings.deadzone, "linearidade": Bindings.linearity,
			"zona_morta_pedal": Bindings.pedal_deadzone, "vibracao": Bindings.rumble}.get(key, 0.0)
		e.slider.set_value_no_signal(v)
		e.label.text = String(e.fmt) % v
	_refresh_devices()
	if _keyboard_label:
		_keyboard_label.text = keyboard_summary()


func _refresh_binding(action: String) -> void:
	var e: Dictionary = _bind_btns.get(action, {})
	if e.is_empty():
		return
	var capturing: bool = not _capture.is_empty() and String(_capture.action) == action
	var bp: Button = e.pad
	bp.text = ("Aperte no controle…" if capturing and _capture.kind == "pad" else "🎮 " + Bindings.pad_text(action))
	var bk = e.kb
	if bk != null:
		bk.text = ("Aperte uma tecla…" if capturing and _capture.kind == "kb" else "⌨ " + Bindings.key_text(action))


func _refresh_devices() -> void:
	if _device_opt == null:
		return
	PadManager.ensure_loaded()
	_device_opt.clear()
	_device_opt.add_item("Automático (o que você mexer)")
	_device_opt.set_item_metadata(0, "")
	var sel := 0
	for e in PadManager.list():
		_device_opt.add_item(String(e.name))
		var i := _device_opt.item_count - 1
		_device_opt.set_item_metadata(i, String(e.guid))
		if PadManager.preferred_guid != "" and String(e.guid) == PadManager.preferred_guid:
			sel = i
	if PadManager.preferred_guid != "" and sel == 0:
		# fixo num controle desconectado: mostra para a pessoa poder voltar ao automático
		_device_opt.add_item("(fixo, desconectado)")
		sel = _device_opt.item_count - 1
		_device_opt.set_item_metadata(sel, PadManager.preferred_guid)
	_device_opt.select(sel)
	var n := Input.get_connected_joypads().size()
	_device_badge.text = "Nenhum controle conectado" if n == 0 else "%d aparelho(s) conectado(s)" % n


func _on_device_selected(i: int) -> void:
	PadManager.set_preferred(String(_device_opt.get_item_metadata(i)))


func _on_joy_changed(_d: int, _c: bool) -> void:
	_refresh_devices()


func _process(dt: float) -> void:
	if _bar_gas == null or not is_inside_tree():
		return
	var d := PadManager.device()
	if d >= 0:
		var x := Bindings.pad_value(d, "steer_right") - Bindings.pad_value(d, "steer_left")
		_bar_left.value = maxf(0.0, -x)
		_bar_right.value = maxf(0.0, x)
		_bar_gas.value = Bindings.pad_value(d, "gas")
		_bar_brake.value = Bindings.pad_value(d, "brake")
		_live_dev.text = "Lendo: " + PadManager.device_name(d) + ("" if Input.is_joy_known(d) else " (sem mapeamento)")
	else:
		_bar_left.value = 0.0
		_bar_right.value = 0.0
		_bar_gas.value = 0.0
		_bar_brake.value = 0.0
		_live_dev.text = "Nenhum controle conectado"
	if not _capture.is_empty():
		_capture.t = float(_capture.t) + dt
		if float(_capture.t) > CAPTURE_TIMEOUT:
			cancel_capture()


# ------------------------------------------------------------------ captura

func start_capture(kind: String, action: String) -> void:
	var prev := _capture.duplicate()
	_capture = {"kind": kind, "action": action, "t": 0.0}
	_capture_rest.clear()
	for d in Input.get_connected_joypads():
		var axes := PackedFloat32Array()
		axes.resize(JOY_AXIS_MAX)
		for a in JOY_AXIS_MAX:
			axes[a] = Input.get_joy_axis(d, a)
		_capture_rest[d] = axes
	if not prev.is_empty():
		_refresh_binding(String(prev.action))
	_refresh_binding(action)


func cancel_capture() -> void:
	if _capture.is_empty():
		return
	var a := String(_capture.action)
	_capture = {}
	_refresh_binding(a)


func is_capturing() -> bool:
	return not _capture.is_empty()


func _finish(apply: Callable) -> void:
	apply.call()
	_capture = {}
	refresh_all()


func _input(e: InputEvent) -> void:
	# último botão apertado (diagnóstico), mesmo fora da captura
	if e is InputEventJoypadButton and e.pressed and _live_last:
		_live_last.text = "Último botão: %s (%s)" % [Bindings.pad_label({"t": "btn", "i": e.button_index}), PadManager.device_name(e.device)]
	if _capture.is_empty():
		return
	var action := String(_capture.action)
	if e is InputEventKey:
		if not e.pressed or e.echo:
			return
		get_viewport().set_input_as_handled()
		if e.keycode == KEY_ESCAPE:
			cancel_capture()
			return
		if _capture.kind == "kb":
			var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			_finish(func(): Bindings.bind_key(action, k))
		return
	if _capture.kind != "pad":
		return
	if e is InputEventJoypadButton:
		if not e.pressed:
			return
		get_viewport().set_input_as_handled()
		var b := {"t": "btn", "i": e.button_index}
		_finish(func(): Bindings.bind_pad(action, b))
	elif e is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		if not action in Bindings.ANALOG:
			return
		var b := capture_axis(e.device, e.axis, e.axis_value)
		if not b.is_empty():
			_finish(func(): Bindings.bind_pad(action, b))


## Ligação de eixo a partir do movimento, ou {} se ainda não mexeu o bastante.
## Eixo que repousava perto de -1 (gatilho em alguns drivers) vira eixo inteiro (s = 2).
func capture_axis(device: int, axis: int, v: float) -> Dictionary:
	var rest := 0.0
	if _capture_rest.has(device) and axis < (_capture_rest[device] as PackedFloat32Array).size():
		rest = _capture_rest[device][axis]
	if absf(v - rest) < 0.5:
		return {}
	var s := 2 if rest < -0.8 else (1 if v > 0.0 else -1)
	return {"t": "axis", "i": axis, "s": s}
