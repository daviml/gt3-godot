# Botões de toque do celular (src/input/touch.ts do web): ◀ ▶ à esquerda, freio e acelerador à direita, ☰ abre
# o menu. São digitais como o teclado: só preenchem `keys` e o InputReader aplica a rampa e o limite.
# Medidas em px de CSS do web; a escala faz a altura da tela valer ~400 px, como um celular deitado no navegador.
# No PC dá para testar com `-- --touch` (o mouse vira toque).
class_name TouchControls
extends Control

signal menu_pressed

## teclas apertadas, o mesmo dicionário do InputReader.touch_keys
var keys := {}
## dedo (índice do toque) -> botão que ele apertou
var _fingers := {}
var _font: Font
# botão -> [retângulo desenhado, retângulo de toque] em px da tela
var _rects := {}
var _k := 1.0

const LABELS := {"left": "", "right": "", "brake": "FREIO", "gas": "ACEL.", "menu": ""}
const WHITE := Color(1, 1, 1)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_layout)
	_layout()


## margens de recorte da tela (câmera/entalhe) em px, como o env(safe-area-inset-*) do web
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
	# área de toque maior que o desenho (14 px acima/abaixo, 5 nos lados, 16 a mais na borda da tela):
	# o dedo que escapa um pouco continua no botão, sem invadir o vizinho
	var pad := func(r: Rect2, outer_left := 0.0, outer_right := 0.0) -> Array:
		return [r, Rect2(r.position - Vector2((5 + outer_left) * k, 14 * k),
			r.size + Vector2((10 + outer_left + outer_right) * k, 28 * k))]
	_rects = {
		"left": pad.call(Rect2(L + 16 * k, B - (16 + 92) * k, 92 * k, 92 * k), 16.0),
		"right": pad.call(Rect2(L + 124 * k, B - (16 + 92) * k, 92 * k, 92 * k)),
		"gas": pad.call(Rect2(R - (16 + 84) * k, B - (16 + 150) * k, 84 * k, 150 * k), 0.0, 16.0),
		"brake": pad.call(Rect2(R - (112 + 84) * k, B - (16 + 120) * k, 84 * k, 120 * k)),
		"menu": [Rect2(L + 16 * k, B - (124 + 40) * k, 52 * k, 40 * k), Rect2(L + 16 * k, B - (124 + 40) * k, 52 * k, 40 * k)],
	}
	queue_redraw()


func _hit(pos: Vector2) -> String:
	for name in _rects:
		if _rects[name][1].has_point(pos):
			return name
	return ""


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			var name := _hit(e.position)
			if name != "":
				_fingers[e.index] = name
				get_viewport().set_input_as_handled()
		elif _fingers.has(e.index):
			var name: String = _fingers[e.index]
			_fingers.erase(e.index)
			# o menu abre ao soltar (pointerup), e só se o dedo não saiu do botão
			if name == "menu" and not e.canceled:
				menu_pressed.emit()
			get_viewport().set_input_as_handled()
		_sync()
	elif e is InputEventScreenDrag and _fingers.has(e.index):
		# dedo saiu do botão (pointerleave do web): solta; arrastar para outro botão não aperta o outro
		if not _rects[_fingers[e.index]][1].has_point(e.position):
			_fingers.erase(e.index)
			_sync()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# app em segundo plano (blur do web): solta tudo
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_fingers.clear()
		_sync()


func _sync() -> void:
	keys.clear()
	for i in _fingers:
		if _fingers[i] != "menu":
			keys[_fingers[i]] = true
	queue_redraw()


func _draw() -> void:
	var k := _k
	var on := {}
	for i in _fingers:
		on[_fingers[i]] = true
	for name in _rects:
		var r: Rect2 = _rects[name][0]
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(maxi(2, roundi(2 * k * 0.6)))
		sb.anti_aliasing = true
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
		if on.has(name):
			fg = WHITE
			match name:
				"gas":
					bg = Color(47 / 255.0, 211 / 255.0, 107 / 255.0, 0.45)
					border = Color("#2fd36b")
				"brake":
					bg = Color(1.0, 90 / 255.0, 79 / 255.0, 0.45)
					border = Color("#ff5a4f")
				_:
					bg = Color(1, 1, 1, 0.3)
					border = WHITE
		sb.bg_color = bg
		sb.border_color = border
		sb.set_corner_radius_all(roundi(radius * k))
		draw_style_box(sb, r)
		var c := r.get_center()
		match name:
			"left", "right":
				# ◀ ▶ desenhados (a fonte padrão do Godot não tem as setas)
				var s := 1.0 if name == "right" else -1.0
				var h := 11.0 * k
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * h, 0), c + Vector2(-s * h * 0.8, -h), c + Vector2(-s * h * 0.8, h)]), fg)
			"menu":
				for dy in [-6.0, 0.0, 6.0]:
					draw_line(c + Vector2(-9 * k, dy * k), c + Vector2(9 * k, dy * k), fg, 2.0 * k * 0.8)
			_:
				var fs := roundi(17 * k)
				var t: String = LABELS[name]
				var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(_font, c + Vector2(-w / 2.0, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
