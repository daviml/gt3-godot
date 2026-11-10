# Controles de toque para celular em 4 esquemas (porte do src/input/touch.ts do web):
# - Padrão: analógico horizontal suave à esquerda (deadzone 8%, curva 1.6) + pedais proporcionais de ACEL. e FREIO à direita
# - Fly-by-wire: analógico horizontal + barra vertical multifunção (cima acelera, baixo freia, vibração ao cruzar)
# - Inclinar: virar o celular como volante pelo acelerômetro + botão de recalibrar + pedais na tela
# - Legacy: botões digitais ◀ ▶ à esquerda e pedais liga/desliga à direita
# Suporte a pointer capture por dedo (e.index) e transição suave entre pedais sem cancelamento acidental.
class_name TouchControls
extends Control

signal menu_pressed
signal recenter_requested

const MODES := ["padrao", "fly", "inclinar", "legacy"]
const MODE_NAMES := {
	"padrao": "Padrão",
	"fly": "Fly-by-wire",
	"inclinar": "Inclinar",
	"legacy": "Legacy"
}

## modo ativo
var mode := "padrao":
	set(v):
		if mode != v and v in MODES:
			mode = v
			_clear_inputs()
			_layout()

## teclas digitais de toque ("left", "right", "gas", "brake")
var keys := {}
## eixos proporcionais de toque: steer (-1..1), gas (0..1), brake (0..1)
var axes := {"steer": 0.0, "gas": 0.0, "brake": 0.0}

## estado do sensor de inclinação (modo inclinar)
var tilt_raw := 0.0
var tilt_zero: Variant = null
var tilt_deg := 0.0
var tilt_live := false

## dedo (e.index) -> target dict { "type": String, "key": String, "rect_idx": int }
var _fingers := {}
var _font: Font
var _k := 1.0

# Áreas desenhadas e retângulos de toque expandidos
var _r_left: Array = []
var _r_right: Array = []
var _r_stick: Array = []
var _r_gas: Array = []
var _r_brake: Array = []
var _r_fly: Array = []
var _r_recenter: Array = []
var _r_menu: Array = []

var _stick_dx := 0.0
var _fly_side := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_layout)
	_layout()


func _insets() -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2()
	var safe := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	return Rect2(safe.position.x, safe.position.y, scr.x - safe.end.x, scr.y - safe.end.y)


func _layout() -> void:
	var size_px := get_viewport_rect().size
	_k = size_px.y / 400.0
	var k := _k
	var ins := _insets()
	var L := ins.position.x
	var R := size_px.x - ins.size.x
	var B := size_px.y - ins.size.y

	var pad := func(r: Rect2, ox := 6.0, oy := 14.0) -> Array:
		return [r, Rect2(r.position - Vector2(ox * k, oy * k), r.size + Vector2(ox * 2.0 * k, oy * 2.0 * k))]

	# Menu ☰ comum a todos os modos
	_r_menu = [
		Rect2(L + 16 * k, B - (124 + 40) * k, 52 * k, 40 * k),
		Rect2(L + 10 * k, B - (130 + 52) * k, 64 * k, 52 * k)
	]

	# Analógico horizontal (Padrão e Fly-by-wire)
	# slot de 170x76 px na base esquerda
	_r_stick = pad.call(Rect2(L + 16 * k, B - (16 + 76) * k, 170 * k, 76 * k), 12.0, 16.0)

	# Pedais proporcionais / digitais (Padrão, Inclinar, Legacy)
	# FREIO e ACEL. lado a lado à direita
	_r_gas = pad.call(Rect2(R - (16 + 84) * k, B - (16 + 150) * k, 84 * k, 150 * k), 10.0, 16.0)
	_r_brake = pad.call(Rect2(R - (112 + 84) * k, B - (16 + 124) * k, 84 * k, 124 * k), 10.0, 16.0)

	# Fly-by-wire: barra vertical única
	_r_fly = pad.call(Rect2(R - (16 + 90) * k, B - (16 + 180) * k, 90 * k, 180 * k), 16.0, 16.0)

	# Botões digitais Legacy (◀ ▶)
	_r_left = pad.call(Rect2(L + 16 * k, B - (16 + 92) * k, 92 * k, 92 * k), 16.0)
	_r_right = pad.call(Rect2(L + 124 * k, B - (16 + 92) * k, 92 * k, 92 * k), 10.0)

	# Botão de Calibrar Volante (modo Inclinar)
	_r_recenter = pad.call(Rect2(L + 16 * k, B - (16 + 46) * k, 130 * k, 46 * k), 8.0, 10.0)

	queue_redraw()


func set_enabled(on: bool) -> void:
	visible = on
	set_process_input(on)
	if not on:
		_clear_inputs()


func _clear_inputs() -> void:
	_fingers.clear()
	keys.clear()
	axes["steer"] = 0.0
	axes["gas"] = 0.0
	axes["brake"] = 0.0
	_stick_dx = 0.0
	_fly_side = 0
	queue_redraw()


# ------------------------------------------------------------------ inclinar (acelerômetro)

static func wrap_deg(a: float) -> float:
	return fposmod(a + 540.0, 360.0) - 180.0


func recenter_tilt() -> void:
	if tilt_live:
		tilt_zero = tilt_raw
	else:
		tilt_zero = 0.0
	tilt_deg = 0.0


func step_tilt(dt: float) -> void:
	var g := Input.get_accelerometer()
	if absf(g.x) + absf(g.y) >= 1.5:
		tilt_live = true
		tilt_raw = rad_to_deg(atan2(g.y, g.x))
		if tilt_zero == null:
			tilt_zero = tilt_raw

	var deg: float = wrap_deg(tilt_raw - (float(tilt_zero) if tilt_zero != null else 0.0)) if tilt_live else 0.0
	tilt_deg += (deg - tilt_deg) * (1.0 - exp(-dt / 0.08))
	axes["steer"] = signf(tilt_deg) * clampf((absf(tilt_deg) - 2.0) / 28.0, 0.0, 1.0)


# ------------------------------------------------------------------ curvas e cálculos

## Curva de pedal por altura: 0 a 15% de toque = 0 a 10% do pedal; 15 a 85% = proporcional; >85% = 100%
static func pedal_curve(t: float) -> float:
	if t <= 0.0:
		return 0.0
	elif t < 0.15:
		return (t / 0.15) * 0.1
	elif t > 0.85:
		return 1.0
	return 0.1 + ((t - 0.15) / 0.7) * 0.9


# ------------------------------------------------------------------ entrada de toque

func _hit_target(pos: Vector2) -> Dictionary:
	# Menu sempre checado primeiro
	if _r_menu[1].has_point(pos):
		return {"type": "menu"}

	match mode:
		"padrao":
			if _r_gas[1].has_point(pos):
				return {"type": "pedal", "key": "gas"}
			if _r_brake[1].has_point(pos):
				return {"type": "pedal", "key": "brake"}
			if _r_stick[1].has_point(pos):
				return {"type": "stick"}
		"fly":
			if _r_fly[1].has_point(pos):
				return {"type": "fly"}
			if _r_stick[1].has_point(pos):
				return {"type": "stick"}
		"inclinar":
			if _r_recenter[1].has_point(pos):
				return {"type": "recenter"}
			if _r_gas[1].has_point(pos):
				return {"type": "pedal", "key": "gas"}
			if _r_brake[1].has_point(pos):
				return {"type": "pedal", "key": "brake"}
		"legacy":
			if _r_gas[1].has_point(pos):
				return {"type": "btn", "key": "gas"}
			if _r_brake[1].has_point(pos):
				return {"type": "btn", "key": "brake"}
			if _r_left[1].has_point(pos):
				return {"type": "btn", "key": "left"}
			if _r_right[1].has_point(pos):
				return {"type": "btn", "key": "right"}
	return {}


func _update_stick(pos: Vector2) -> void:
	var r: Rect2 = _r_stick[0]
	var center_x: float = r.position.x + r.size.x * 0.5
	var max_travel: float = r.size.x * 0.36
	var dx := clampf((pos.x - center_x) / max_travel, -1.0, 1.0)
	_stick_dx = dx
	var mag := maxf(0.0, (absf(dx) - 0.08) / 0.92)
	axes["steer"] = signf(dx) * pow(mag, 1.6)


func _update_pedal(key: String, pos: Vector2) -> void:
	var r: Rect2 = _r_gas[0] if key == "gas" else _r_brake[0]
	var t := clampf((r.end.y - pos.y) / r.size.y, 0.0, 1.0)
	var v := pedal_curve(t)
	axes[key] = v
	if v > 0.05:
		keys[key] = true
	else:
		keys.erase(key)


func _update_fly(pos: Vector2) -> void:
	var r: Rect2 = _r_fly[0]
	var mid_y: float = r.position.y + r.size.y * 0.5
	var half_h: float = r.size.y * 0.5
	var d := (mid_y - clampf(pos.y, r.position.y, r.end.y)) / half_h
	var v := maxf(0.0, (absf(d) - 0.06) / 0.94)
	var g := v if d > 0.0 else 0.0
	var b := v if d < 0.0 else 0.0
	axes["gas"] = g
	axes["brake"] = b
	if g > 0.05: keys["gas"] = true
	else: keys.erase("gas")
	if b > 0.05: keys["brake"] = true
	else: keys.erase("brake")

	var now := 1 if g > 0.0 else (-1 if b > 0.0 else 0)
	if now != 0 and _fly_side != 0 and now != _fly_side:
		Input.vibrate_handheld(8)
	if now != 0:
		_fly_side = now


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			var target := _hit_target(e.position)
			if not target.is_empty():
				_fingers[e.index] = target
				match target.type:
					"stick":
						_update_stick(e.position)
					"pedal":
						_update_pedal(target.key, e.position)
					"fly":
						_update_fly(e.position)
					"btn":
						keys[target.key] = true
				get_viewport().set_input_as_handled()
				queue_redraw()
		elif _fingers.has(e.index):
			var target: Dictionary = _fingers[e.index]
			_fingers.erase(e.index)
			match target.type:
				"stick":
					_stick_dx = 0.0
					axes["steer"] = 0.0
				"pedal":
					axes[target.key] = 0.0
					keys.erase(target.key)
				"fly":
					axes["gas"] = 0.0
					axes["brake"] = 0.0
					keys.erase("gas")
					keys.erase("brake")
					_fly_side = 0
				"btn":
					keys.erase(target.key)
				"menu":
					if not e.canceled:
						menu_pressed.emit()
				"recenter":
					if not e.canceled:
						recenter_tilt()
						recenter_requested.emit()
			get_viewport().set_input_as_handled()
			queue_redraw()

	elif e is InputEventScreenDrag and _fingers.has(e.index):
		var target: Dictionary = _fingers[e.index]
		match target.type:
			"stick":
				_update_stick(e.position)
			"pedal":
				# Pointer capture aperfeiçoado com transição suave entre pedais:
				# deslizar o polegar entre FREIO e ACEL. transfere o comando sem cancelamento
				var cur_key: String = target.key
				var r_gas: Rect2 = _r_gas[0]
				var r_brk: Rect2 = _r_brake[0]
				if cur_key == "brake" and e.position.x > r_gas.position.x - 4.0 * _k:
					axes["brake"] = 0.0
					keys.erase("brake")
					target.key = "gas"
					_update_pedal("gas", e.position)
				elif cur_key == "gas" and e.position.x < r_brk.end.x + 4.0 * _k:
					axes["gas"] = 0.0
					keys.erase("gas")
					target.key = "brake"
					_update_pedal("brake", e.position)
				else:
					_update_pedal(cur_key, e.position)
			"fly":
				_update_fly(e.position)
			"btn":
				# Botões digitais legacy: deslizar entre ◀ ▶ ou FREIO/ACEL troca o botão
				if target.key in ["left", "right"]:
					var k_left: Rect2 = _r_left[0]
					var k_right: Rect2 = _r_right[0]
					if target.key == "left" and e.position.x > k_right.position.x:
						keys.erase("left")
						target.key = "right"
						keys["right"] = true
					elif target.key == "right" and e.position.x < k_left.end.x:
						keys.erase("right")
						target.key = "left"
						keys["left"] = true
				elif target.key in ["brake", "gas"]:
					var k_brk: Rect2 = _r_brake[0]
					var k_gas: Rect2 = _r_gas[0]
					if target.key == "brake" and e.position.x > k_gas.position.x - 4.0 * _k:
						keys.erase("brake")
						target.key = "gas"
						keys["gas"] = true
					elif target.key == "gas" and e.position.x < k_brk.end.x + 4.0 * _k:
						keys.erase("gas")
						target.key = "brake"
						keys["brake"] = true
		get_viewport().set_input_as_handled()
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_inputs()


# ------------------------------------------------------------------ renderização (draw)

func _draw() -> void:
	var k := _k

	# 1. Botão Menu ☰
	_draw_menu_btn(_r_menu[0])

	# 2. Desenho específico do esquema
	match mode:
		"padrao":
			_draw_stick(_r_stick[0])
			_draw_pedal("brake", _r_brake[0], axes["brake"], "FREIO")
			_draw_pedal("gas", _r_gas[0], axes["gas"], "ACEL.")
		"fly":
			_draw_stick(_r_stick[0])
			_draw_fly_bar(_r_fly[0])
		"inclinar":
			_draw_recenter_btn(_r_recenter[0])
			_draw_pedal("brake", _r_brake[0], axes["brake"] if axes["brake"] > 0.0 else (1.0 if keys.has("brake") else 0.0), "FREIO")
			_draw_pedal("gas", _r_gas[0], axes["gas"] if axes["gas"] > 0.0 else (1.0 if keys.has("gas") else 0.0), "ACEL.")
		"legacy":
			_draw_digital_btn("left", _r_left[0], "◀")
			_draw_digital_btn("right", _r_right[0], "▶")
			_draw_digital_btn("brake", _r_brake[0], "FREIO")
			_draw_digital_btn("gas", _r_gas[0], "ACEL.")


func _draw_menu_btn(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.35)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(maxi(2, roundi(2 * _k * 0.6)))
	sb.set_corner_radius_all(roundi(10.0 * _k))
	draw_style_box(sb, r)
	var c := r.get_center()
	var fg := Color(1, 1, 1, 0.8)
	for dy in [-6.0, 0.0, 6.0]:
		draw_line(c + Vector2(-9 * _k, dy * _k), c + Vector2(9 * _k, dy * _k), fg, 2.0 * _k * 0.8)


func _draw_stick(r: Rect2) -> void:
	var k := _k
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.35)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(maxi(2, roundi(2 * k * 0.6)))
	sb.set_corner_radius_all(roundi(r.size.y * 0.5))
	draw_style_box(sb, r)

	# Marca de centro neutro
	var c := r.get_center()
	draw_line(c + Vector2(0, -10 * k), c + Vector2(0, 10 * k), Color(1, 1, 1, 0.25), 2.0 * k)

	# Botão / Manípulo (Knob)
	var max_travel := r.size.x * 0.36
	var knob_center := c + Vector2(_stick_dx * max_travel, 0)
	var knob_r := roundi(28 * k)
	var active := absf(_stick_dx) > 0.05
	var knob_bg := Color(1, 1, 1, 0.45) if active else Color(1, 1, 1, 0.22)
	var knob_border := Color.WHITE if active else Color(1, 1, 1, 0.5)
	draw_circle(knob_center, knob_r, knob_bg)
	draw_arc(knob_center, knob_r, 0, TAU, 32, knob_border, maxi(2, roundi(2 * k)), true)


func _draw_pedal(key: String, r: Rect2, val: float, label: String) -> void:
	var k := _k
	var is_gas := key == "gas"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.35)
	var active := val > 0.05
	var col := Color("#2fd36b") if is_gas else Color("#ff5a4f")
	sb.border_color = col if active else (Color(47 / 255.0, 211 / 255.0, 107 / 255.0, 0.6) if is_gas else Color(1.0, 90 / 255.0, 79 / 255.0, 0.6))
	sb.set_border_width_all(maxi(2, roundi(2 * k * 0.6)))
	sb.set_corner_radius_all(roundi(18.0 * k))
	draw_style_box(sb, r)

	# Preenchimento proporcional de baixo para cima
	if val > 0.01:
		var fill_h := r.size.y * val
		var fill_r := Rect2(r.position.x + 2 * k, r.end.y - fill_h - 2 * k, r.size.x - 4 * k, fill_h)
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(col.r, col.g, col.b, 0.45)
		fsb.set_corner_radius_all(roundi(16.0 * k))
		draw_style_box(fsb, fill_r)

	var c := r.get_center()
	var fs := roundi(17 * k)
	var fg := Color.WHITE if active else Color(1, 1, 1, 0.8)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, c + Vector2(-w / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


func _draw_fly_bar(r: Rect2) -> void:
	var k := _k
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.35)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(maxi(2, roundi(2 * k * 0.6)))
	sb.set_corner_radius_all(roundi(20.0 * k))
	draw_style_box(sb, r)

	var mid_y := r.position.y + r.size.y * 0.5
	var half_h := r.size.y * 0.48

	# Preenchimento acelerador (para cima)
	if float(axes["gas"]) > 0.01:
		var gh: float = half_h * float(axes["gas"])
		var gr := Rect2(r.position.x + 2 * k, mid_y - gh, r.size.x - 4 * k, gh)
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = Color(47 / 255.0, 211 / 255.0, 107 / 255.0, 0.45)
		gsb.set_corner_radius_all(roundi(14.0 * k))
		draw_style_box(gsb, gr)

	# Preenchimento freio (para baixo)
	if float(axes["brake"]) > 0.01:
		var bh: float = half_h * float(axes["brake"])
		var br := Rect2(r.position.x + 2 * k, mid_y, r.size.x - 4 * k, bh)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(1.0, 90 / 255.0, 79 / 255.0, 0.45)
		bsb.set_corner_radius_all(roundi(14.0 * k))
		draw_style_box(bsb, br)

	# Linha neutra divisória
	draw_line(Vector2(r.position.x + 4 * k, mid_y), Vector2(r.end.x - 4 * k, mid_y), Color(1, 1, 1, 0.4), 2.0 * k)

	# Rótulos ACEL. e FREIO
	var fs := roundi(14 * k)
	var wag := _font.get_string_size("ACEL.", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(r.get_center().x - wag / 2.0, r.position.y + 24 * k), "ACEL.", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(47 / 255.0, 211 / 255.0, 107 / 255.0, 0.9))
	var wbr := _font.get_string_size("FREIO", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(r.get_center().x - wbr / 2.0, r.end.y - 12 * k), "FREIO", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 90 / 255.0, 79 / 255.0, 0.9))


func _draw_recenter_btn(r: Rect2) -> void:
	var k := _k
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.4)
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(maxi(2, roundi(2 * k * 0.6)))
	sb.set_corner_radius_all(roundi(12.0 * k))
	draw_style_box(sb, r)

	var fs := roundi(13 * k)
	var t := "⟳ RECALIBRAR"
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, r.get_center() + Vector2(-w / 2.0, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_digital_btn(name: String, r: Rect2, label: String) -> void:
	var k := _k
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(maxi(2, roundi(2 * k * 0.6)))
	var radius := 10.0
	var bg := Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.35)
	var border := Color(1, 1, 1, 0.35)
	var fg := Color(1, 1, 1, 0.8)

	match name:
		"left", "right":
			radius = 46.0
		"gas":
			radius = 18.0
			border = Color(47 / 255.0, 211 / 255.0, 107 / 255.0, 0.6)
		"brake":
			radius = 18.0
			border = Color(1.0, 90 / 255.0, 79 / 255.0, 0.6)

	if keys.has(name):
		fg = Color.WHITE
		match name:
			"gas":
				bg = Color(47 / 255.0, 211 / 255.0, 107 / 255.0, 0.45)
				border = Color("#2fd36b")
			"brake":
				bg = Color(1.0, 90 / 255.0, 79 / 255.0, 0.45)
				border = Color("#ff5a4f")
			_:
				bg = Color(1, 1, 1, 0.3)
				border = Color.WHITE

	sb.bg_color = bg
	sb.border_color = border
	sb.set_corner_radius_all(roundi(radius * k))
	draw_style_box(sb, r)

	var c := r.get_center()
	match name:
		"left", "right":
			var s := 1.0 if name == "right" else -1.0
			var h := 11.0 * k
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * h, 0), c + Vector2(-s * h * 0.8, -h), c + Vector2(-s * h * 0.8, h)]), fg)
		_:
			var fs := roundi(17 * k)
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, c + Vector2(-w / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
