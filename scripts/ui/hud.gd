# HUD estilo LMU (porte de src/ui/hud.ts + minimap.ts do web), desenhado por código num único Control:
# - superior esquerdo: melhores tempos (nick, carro, tempo/gap)
# - superior direito: Best / Current com 3 setores coloridos, delta ao vivo e nome da curva
# - inferior esquerdo: mapa da pista com o carro
# - inferior direito: mostrador redondo (fundo azul-marinho, arco branco de giro de 240°, marcha grande,
#   velocidade, acelerador/freio em arcos internos de 70°) com o bloco dos 4 pneus e ABS / TC / AUT ao lado
# - Porsche na câmera de capô: painel no estilo do display real do 992 GT3 R, centralizado embaixo
# - meio em cima: FPS. Aviso rápido (toast) no meio. Telemetria na tecla T.
# No celular (touch): painéis menores, mapa ao lado dos tempos e mostrador em cima no centro, longe dos botões.
# Medidas em px de CSS do web, escaladas por k (mostrador) e kp (painéis) a partir da altura da tela.
class_name Hud
extends Control

const MAX_RPM := 9000.0
## mostrador: arco de giro de 240° (150° → 390°) com raio 86 numa caixa de 200; pedais a 73 de raio, 70° cada
const GR := 86.0
const PR := 73.0
const GAUGE := 226.0
const ACCENT := Color("#e10600")
const WHITE := Color("#f2f4f7")
const PURPLE := Color("#c9a6ff")
const GREEN := Color("#2fd36b")
const YELLOW := Color("#f2c230")
const RED := Color("#ff5a4f")
const NAVY := Color("#0d182e")
## cor do pneu pelo uso (0 = solto, 1 = no pico): azul → verde → amarelo → vermelho
const TYRE_STOPS := [[0.0, Color("#3d8bff")], [0.45, Color("#2fd36b")], [0.8, Color("#f2cc30")], [1.02, Color("#ff3b30")]]
## carros com painel próprio na câmera de capô
const DASH_CARS := ["porsche-992-gt3r"]
const DASH_LEDS := 16

var car: Car
var timer: LapTimer
var track: Track
var touch := false
var nick := ""
## [{nick, carId, time}] em ordem crescente
var records: Array = []
## melhores setores da sessão (roxo), alimentados pelo main
var best_sectors: Array[float] = []
var car_color := Color.WHITE
var throttle := 0.0
var brake := 0.0
var telemetry := false
var dash := false
var dash_on := false
var section := ""
var toast_text := ""
var toast_t := 0.0
var fps := 0
var quality := ""
var autopilot := false

var _font: Font
var _bold: Font
var _mono: Font
var _tyre_use := [0.0, 0.0, 0.0, 0.0]
var _fps_frames := 0
var _fps_since := 0.0
var _time := 0.0
var _redraw_t := 0.0
var _k := 1.0
var _kp := 1.0
var _shorts := {}
var _colors := {}
# mapa: pontos da pista em px do mapa (170×150) e transformação
var _map_pts := PackedVector2Array()
var _map_scale := 1.0
var _map_min := Vector2.ZERO
var _map_off := Vector2.ZERO
var _map_finish: Array = []


func _init(c: Car, t: LapTimer, tr: Track, car_id: String, is_touch: bool) -> void:
	car = c
	timer = t
	track = tr
	touch = is_touch
	dash = car_id in DASH_CARS
	var list = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	for e in list:
		_shorts[e.id] = e.get("short", e.id)
		_colors[e.id] = Color(e.get("color", "#ffffff"))
	car_color = _colors.get(car_id, Color.WHITE)
	_build_map()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _sys_font(500)
	_bold = _sys_font(700)
	_mono = SystemFont.new()
	(_mono as SystemFont).font_names = PackedStringArray(["Consolas", "Droid Sans Mono", "monospace"])
	get_viewport().size_changed.connect(_layout)
	_layout()


## fonte do sistema no estilo condensado dos sims (Bahnschrift no Windows; Roboto no Android)
static func _sys_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "sans-serif"])
	f.font_weight = weight
	return f


func _layout() -> void:
	var s := get_viewport_rect().size
	if touch:
		_k = maxf(0.34, minf(1.15, minf(s.y / 860.0, s.x / 1760.0)))
		_kp = _k
	else:
		_k = maxf(0.62, minf(1.15, s.y / 860.0))
		_kp = maxf(_k, minf(1.67, 1.67 * minf(s.x / 2552.0, s.y / 1268.0)))


## câmera atual: o painel do Porsche só aparece na de capô (nas de fora ele tampava a traseira do carro)
func set_view(mode: String) -> void:
	dash_on = dash and mode == "capô"


func toast(t: String) -> void:
	toast_text = t
	toast_t = 1.6


## uso filtrado de cada pneu (0 = solto, 1 = no limite), pelo slip combinado em relação ao pico
static func tyre_use(c: Car, i: int) -> float:
	var w: Car.Wheel = c.wheels[i]
	if w.fz <= 0.0:
		return 0.0
	return Vector2(w.kappa / c.kappa_peak, w.alpha / c.alpha_peak).length()


static func tyre_color(u: float) -> Color:
	if u <= 0.0:
		return TYRE_STOPS[0][1]
	for i in range(1, TYRE_STOPS.size()):
		var b: float = TYRE_STOPS[i][0]
		if u > b:
			continue
		var a: float = TYRE_STOPS[i - 1][0]
		return (TYRE_STOPS[i - 1][1] as Color).lerp(TYRE_STOPS[i][1], (u - a) / (b - a))
	return TYRE_STOPS[TYRE_STOPS.size() - 1][1]


## cor do setor como no web: roxo = melhor da sessão, verde = melhor que a melhor volta, amarelo = mais lento
func sector_color(i: int, v: float) -> Color:
	if i >= best_sectors.size() or v <= best_sectors[i]:
		return PURPLE
	if timer.best == null or v <= timer.best.sectors[i]:
		return GREEN
	return YELLOW


func update(dt: float, thr: float, brk: float) -> void:
	_time += dt
	throttle = thr
	brake = brk
	for i in 4:
		_tyre_use[i] += (tyre_use(car, i) - _tyre_use[i]) * 0.15
	# FPS 4x por segundo (média da janela, sem tremer)
	_fps_frames += 1
	_fps_since += dt
	if _fps_since >= 0.25:
		fps = roundi(_fps_frames / _fps_since)
		_fps_frames = 0
		_fps_since = 0.0
	toast_t -= dt
	section = track.section_at(timer.s)
	# celular: redesenha o HUD a 30 Hz (são ~100 textos por quadro na CPU, que esquenta e derruba o clock)
	_redraw_t += dt
	if not touch or _redraw_t >= 1.0 / 30.0:
		_redraw_t = 0.0
		queue_redraw()


# ------------------------------------------------------------------ desenho

func _draw() -> void:
	var s := get_viewport_rect().size
	var ins := _insets()
	var k := _k
	var kp := _kp
	# painéis: melhores tempos (esq. cima), tempos (dir. cima), mapa (esq. baixo ou ao lado dos tempos no celular)
	_draw_board(Vector2(14 + ins.position.x, 14 + ins.position.y), kp)
	var timing_w := 250.0 * kp
	var tr := Vector2(s.x - ins.size.x - 14 - timing_w, 14 + ins.position.y)
	_draw_timing(tr, kp)
	var map_size := Vector2(186, 180) * kp
	if touch:
		_draw_map(Vector2(tr.x - 8 * kp - map_size.x, tr.y), kp)
	else:
		_draw_map(Vector2(14 + ins.position.x, s.y - ins.size.y - 14 - map_size.y), kp)
	# mostrador + pneus (ou painel do Porsche na câmera de capô)
	var cl_w := (GAUGE + 8 + 86) * k
	if dash_on:
		var ks := minf(s.x * 0.21 / 640.0, s.y * 0.198 / 300.0)
		if touch:
			ks = 226.0 * k / 300.0
			_draw_dash(Vector2(s.x / 2.0 - 320 * ks, 22 + ins.position.y), ks)
		else:
			_draw_dash(Vector2(s.x / 2.0 - 320 * ks, s.y - 0.004 * s.x - 300 * ks), ks)
	elif touch:
		_draw_cluster(Vector2(s.x / 2.0 - cl_w / 2.0, 22 + ins.position.y), k)
	else:
		_draw_cluster(Vector2(s.x - ins.size.x - 16 - cl_w, s.y - ins.size.y - 14 - GAUGE * k), k)
	_draw_fps(Vector2(s.x / 2.0, 4 + ins.position.y))
	if toast_t > 0.0:
		_draw_toast(s)
	if telemetry:
		_draw_telemetry(Vector2(12, s.y * 0.5))


## margens de recorte da tela (câmera/entalhe), como o env(safe-area-inset-*) do web
func _insets() -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2()
	var safe := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	return Rect2(safe.position.x, safe.position.y, scr.x - safe.end.x, scr.y - safe.end.y)


## painel LMU: vidro escuro, filete de cor no topo e canto inferior direito cortado
func _panel(r: Rect2, sc: float) -> void:
	var cut := 10.0 * sc
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - cut),
		Vector2(r.end.x - cut, r.end.y), Vector2(r.position.x, r.end.y)])
	draw_colored_polygon(pts, Color(14 / 255.0, 17 / 255.0, 22 / 255.0, 0.78))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2 * sc)), ACCENT)


func _text(f: Font, pos: Vector2, t: String, size: float, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	# pos = canto superior esquerdo da caixa de texto (o ascent desce a linha de base)
	var fs := maxi(6, roundi(size))
	draw_string(f, pos + Vector2(0, f.get_ascent(fs)), t, align, width, fs, c)


func _text_w(f: Font, t: String, size: float) -> float:
	return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(6, roundi(size))).x


func _draw_fps(top_center: Vector2) -> void:
	var sc := clampf(get_viewport_rect().size.y / 860.0, 0.75, 1.1)
	var fs := 12.0 * sc
	var t := "%d FPS" % fps
	var w := _text_w(_bold, t, fs) + 16 * sc
	var r := Rect2(top_center - Vector2(w / 2.0, 0), Vector2(w, 18 * sc))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(roundi(9 * sc))
	draw_style_box(sb, r)
	var c := GREEN if fps >= 55 else (Color("#ffb020") if fps >= 30 else RED)
	_text(_bold, r.position + Vector2(8 * sc, 2 * sc), t, fs, c)


func _draw_toast(s: Vector2) -> void:
	var sc := _kp
	var fs := 18.0 * sc
	var w := _text_w(_bold, toast_text, fs) + 32 * sc
	var a := clampf(toast_t / 0.5, 0.0, 1.0)
	var r := Rect2(Vector2(s.x / 2.0 - w / 2.0, s.y * 0.34), Vector2(w, 36 * sc))
	draw_rect(r, Color(12 / 255.0, 14 / 255.0, 18 / 255.0, 0.85 * a))
	_text(_bold, r.position + Vector2(16 * sc, 7 * sc), toast_text, fs, Color(1, 1, 1, a))


# ------------------------------------------------------------------ melhores tempos

func _draw_board(pos: Vector2, sc: float) -> void:
	var w := 300.0 * sc
	var row := 27.0 * sc
	var n := maxi(records.size(), 1)
	var h := 28 * sc + row * n + 6 * sc
	_panel(Rect2(pos, Vector2(w, h)), sc)
	_text(_bold, pos + Vector2(12 * sc, 7 * sc), "MELHORES TEMPOS", 12 * sc, Color(1, 1, 1, 0.92))
	var dim := Color(1, 1, 1, 0.45)
	var tw := _text_w(_font, "INTERLAGOS", 12 * sc)
	_text(_font, pos + Vector2(w - 12 * sc - tw, 7 * sc), "INTERLAGOS", 12 * sc, dim)
	var y := pos.y + 28 * sc
	if records.is_empty():
		_text(_font, Vector2(pos.x + 12 * sc, y + 6 * sc), "Nenhuma volta válida ainda", 13 * sc, Color(1, 1, 1, 0.5))
		return
	var best := float(records[0].time)
	for i in records.size():
		var r: Dictionary = records[i]
		var me: bool = r.nick == nick and nick != ""
		if me:
			draw_rect(Rect2(pos.x, y, w, row), Color(1, 1, 1, 0.09))
		# posição
		var pr := Rect2(pos.x + 12 * sc, y + 3.5 * sc, 22 * sc, 20 * sc)
		draw_rect(pr, WHITE if i == 0 else Color(1, 1, 1, 0.1))
		_text(_bold, pr.position + Vector2(0, 2 * sc), str(i + 1), 13 * sc, Color("#0b0d11") if i == 0 else WHITE, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
		# carro (filete na cor + sigla)
		var cx := pos.x + 46 * sc
		draw_rect(Rect2(cx, y + 5.5 * sc, 3 * sc, 16 * sc), _colors.get(r.carId, Color.WHITE))
		_text(_bold, Vector2(cx + 9 * sc, y + 5 * sc), String(_shorts.get(r.carId, r.carId)), 13 * sc, WHITE)
		# nick
		_text(_font, Vector2(pos.x + 108 * sc, y + 4 * sc), String(r.nick), 14 * sc, WHITE, HORIZONTAL_ALIGNMENT_LEFT, 120 * sc)
		# tempo ou gap
		var t := LapTimer.format_time(float(r.time)) if i == 0 else "+%.3f" % (float(r.time) - best)
		var tw2 := _text_w(_font, t, 14 * sc)
		_text(_font, Vector2(pos.x + w - 12 * sc - tw2, y + 4 * sc), t, 14 * sc, PURPLE if i == 0 else Color(1, 1, 1, 0.85))
		y += row


# ------------------------------------------------------------------ tempos (Best / Current / setores / delta)

func _draw_timing(pos: Vector2, sc: float) -> void:
	var w := 250.0 * sc
	var pad := 12.0 * sc
	var t := timer
	var h := 170.0 * sc
	_panel(Rect2(pos, Vector2(w, h)), sc)
	var y := pos.y + 8 * sc
	# curva atual (filete amarelo à esquerda)
	draw_rect(Rect2(pos.x + pad, y, 3 * sc, 16 * sc), Color("#e3bd1c"))
	_text(_bold, Vector2(pos.x + pad + 9 * sc, y), section.to_upper(), 13 * sc, Color(1, 1, 1, 0.9))
	y += 22 * sc
	var dim := Color(1, 1, 1, 0.55)
	# (o lambda recebe y: closures do GDScript copiam o valor na criação)
	var row := func(ry: float, label: String, value: String, vs: float, vc: Color, f: Font) -> void:
		_text(_bold, Vector2(pos.x + pad, ry + vs * 0.42 - 6 * sc), label, 12 * sc, dim)
		var vw := _text_w(f, value, vs)
		_text(f, Vector2(pos.x + w - pad - vw, ry), value, vs, vc)
	row.call(y, "BEST", LapTimer.format_time(t.best.time if t.best else -1.0), 19 * sc, PURPLE, _font)
	y += 22 * sc
	var cur_c := WHITE if t.valid else RED
	row.call(y, "CURRENT", LapTimer.format_time(t.current), 30 * sc, cur_c, _bold)
	if not t.valid and t.current >= 0.0:
		var cw := _text_w(_bold, LapTimer.format_time(t.current), 30 * sc)
		draw_line(Vector2(pos.x + w - pad - cw, y + 18 * sc), Vector2(pos.x + w - pad, y + 18 * sc), RED, 2 * sc)
	y += 38 * sc
	# setores: 3 caixas
	var bw := (w - 2 * pad - 6 * sc) / 3.0
	for i in 3:
		var r := Rect2(pos.x + pad + i * (bw + 3 * sc), y, bw, 22 * sc)
		var border := Color(1, 1, 1, 0.14)
		var bg := Color(1, 1, 1, 0.04)
		var txt := ""
		if i < t.sectors.size():
			var c := sector_color(i, t.sectors[i])
			border = c
			bg = Color(c, 0.2)
			txt = "%.2f" % t.sectors[i]
		draw_rect(r, bg)
		draw_rect(r, border, false, 1.0 * sc)
		_text(_font, r.position + Vector2(6 * sc, 5 * sc), "S%d" % (i + 1), 11 * sc, Color(1, 1, 1, 0.5))
		var tw := _text_w(_font, txt, 13 * sc)
		_text(_font, Vector2(r.end.x - 6 * sc - tw, r.position.y + 3.5 * sc), txt, 13 * sc, WHITE)
	y += 28 * sc
	# delta: barra do centro para a esquerda (ganhando, verde) ou para a direita (perdendo, vermelho); cheia = 1 s
	var dr := Rect2(pos.x + pad, y, w - 2 * pad, 18 * sc)
	if not is_nan(t.delta):
		var d := t.delta
		draw_rect(dr, Color(1, 1, 1, 0.05))
		var half := dr.size.x / 2.0
		var bw2 := minf(1.0, absf(d)) * half
		var cx := dr.position.x + half
		if d < 0.0:
			draw_rect(Rect2(cx - bw2, dr.position.y, bw2, dr.size.y), Color(GREEN, 0.75))
		else:
			draw_rect(Rect2(cx, dr.position.y, bw2, dr.size.y), Color(1.0, 70 / 255.0, 60 / 255.0, 0.75))
		draw_line(Vector2(cx, dr.position.y), Vector2(cx, dr.end.y), Color(1, 1, 1, 0.35), 1.0)
		var ds := ("−" if d < 0.0 else "+") + "%.2f" % absf(d)
		_text(_bold, Vector2(dr.position.x, dr.position.y + 1 * sc), ds, 14 * sc, WHITE, HORIZONTAL_ALIGNMENT_CENTER, dr.size.x)
	y += 24 * sc
	var last := t.last
	row.call(y, "ÚLTIMA", LapTimer.format_time(last.time if last else -1.0), 19 * sc, WHITE if (last == null or last.valid) else RED, _font)


# ------------------------------------------------------------------ mapa

func _build_map() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in track.P:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
	var pad := 10.0
	var size := Vector2(170, 150)
	_map_scale = minf((size.x - 2 * pad) / (mx.x - mn.x), (size.y - 2 * pad) / (mx.y - mn.y))
	_map_min = mn
	_map_off = (size - (mx - mn) * _map_scale) / 2.0
	_map_pts = PackedVector2Array()
	for i in range(0, track.n, 2):
		_map_pts.append(_to_map(track.P[i]))
	_map_pts.append(_map_pts[0])
	var p0 := track.P[0]
	var r0 := track.R[0]
	_map_finish = [_to_map(p0 - r0 * 9.0), _to_map(p0 + r0 * 9.0)]


func _to_map(p: Vector3) -> Vector2:
	return _map_off + (Vector2(p.x, p.z) - _map_min) * _map_scale


func _draw_map(pos: Vector2, sc: float) -> void:
	var w := 186.0 * sc
	var h := 180.0 * sc
	_panel(Rect2(pos, Vector2(w, h)), sc)
	_text(_bold, pos + Vector2(12 * sc, 7 * sc), "MAPA", 12 * sc, Color(1, 1, 1, 0.92))
	var o := pos + Vector2(8 * sc, 26 * sc)
	var pts := PackedVector2Array()
	pts.resize(_map_pts.size())
	for i in _map_pts.size():
		pts[i] = o + _map_pts[i] * sc
	draw_polyline(pts, Color(0, 0, 0, 0.6), 7 * sc, true)
	draw_polyline(pts, Color(235 / 255.0, 238 / 255.0, 242 / 255.0, 0.9), 3.5 * sc, true)
	draw_line(o + _map_finish[0] * sc, o + _map_finish[1] * sc, Color("#e5483b"), 2.5 * sc, true)
	var c := o + _to_map(car.pos) * sc
	draw_circle(c, 5.5 * sc, Color.BLACK)
	draw_circle(c, 4.0 * sc, car_color)


# ------------------------------------------------------------------ mostrador LMU + pneus

func _polar(c: Vector2, deg: float, r: float) -> Vector2:
	return c + Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r


func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, width: float) -> void:
	if absf(a1 - a0) < 0.01:
		return
	draw_arc(c, r, deg_to_rad(a0), deg_to_rad(a1), maxi(8, int(absf(a1 - a0) / 3.0)), col, width, true)


func _draw_cluster(pos: Vector2, k: float) -> void:
	var tyres_w := 86.0 * k
	_draw_tyres(Vector2(pos.x, pos.y + GAUGE * k - 18 * k), k, tyres_w)
	_draw_gauge(Vector2(pos.x + tyres_w + 8 * k, pos.y), k)


func _draw_gauge(pos: Vector2, k: float) -> void:
	var u := GAUGE * k / 200.0  # unidades do viewBox 200 → px
	var c := pos + Vector2(100, 100) * u
	var lim: float = car.p.limiter
	# sombra e disco azul-marinho
	draw_circle(c + Vector2(0, 4 * u), 99 * u, Color(0, 0, 0, 0.3))
	draw_circle(c, 99 * u, NAVY)
	_arc(c, 99 * u, 0, 360, Color(1, 1, 1, 0.1), 1.2 * u)
	draw_circle(c, 64 * u, Color(1, 1, 1, 0.025))
	# trilho do giro, faixa vermelha perto do corte e arco de giro
	_arc(c, GR * u, 150, 390, Color(1, 1, 1, 0.12), 10 * u)
	var red0 := 150.0 + maxf(0.0, lim - 1000.0) / MAX_RPM * 240.0
	_arc(c, (GR + 8) * u, red0, 390, Color(216 / 255.0, 52 / 255.0, 60 / 255.0, 0.9), 3 * u)
	var frac := minf(1.0, car.rpm / MAX_RPM)
	var shift_now := car.rpm > lim - 300.0
	var blink := int(_time / 0.07) % 2 == 0
	var rpm_c := Color("#f4f6f8")
	if shift_now:
		rpm_c = Color("#3d8bff") if blink else Color("#1a3d78")
	elif car.rpm > lim - 700.0:
		rpm_c = Color("#ff5148")
	_arc(c, GR * u, 150, 150 + 240 * frac, rpm_c, 10 * u)
	# pedais: arcos internos de 70°, enchendo de baixo para cima (freio à esquerda, acelerador à direita)
	_arc(c, PR * u, 160, 230, Color(1, 1, 1, 0.08), 5 * u)
	_arc(c, PR * u, 20, -50, Color(1, 1, 1, 0.08), 5 * u)
	_arc(c, PR * u, 160, 160 + 70 * brake, Color("#ff4b5c"), 5 * u)
	_arc(c, PR * u, 20, 20 - 70 * throttle, GREEN, 5 * u)
	# marcha grande, velocidade e KM/H
	var gear := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	_text(_bold, pos + Vector2(0, 34 * k), gear, 96 * k, Color("#6aa8ff") if shift_now else WHITE, HORIZONTAL_ALIGNMENT_CENTER, GAUGE * k)
	var kmh := str(roundi(absf(car.fwd_speed()) * 3.6))
	_text(_bold, pos + Vector2(0, 132 * k), kmh, 40 * k, WHITE, HORIZONTAL_ALIGNMENT_CENTER, GAUGE * k)
	_text(_bold, pos + Vector2(0, 174 * k), "KM/H", 15 * k, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER, GAUGE * k)


## bloco dos 4 pneus (cor pelo slip) com ABS / TC / AUT embaixo; pos = canto inferior esquerdo
func _draw_tyres(bottom_left: Vector2, k: float, w: float) -> void:
	var h := 110.0 * k
	var r := Rect2(bottom_left - Vector2(0, h), Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(13 / 255.0, 24 / 255.0, 46 / 255.0, 0.86)
	sb.set_corner_radius_all(roundi(10 * k))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = roundi(6 * k)
	sb.shadow_offset = Vector2(0, 4 * k)
	draw_style_box(sb, r)
	# contorno do carro entre os pneus e os 4 pneus (15×26, colunas a 26 de distância, linhas a 22)
	var cx := r.position.x + w / 2.0
	var top := r.position.y + 10 * k
	var body := Rect2(cx - 13 * k, top, 26 * k, 74 * k)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0, 0, 0, 0)
	bsb.border_color = Color(1, 1, 1, 0.28)
	bsb.set_border_width_all(maxi(1, roundi(2 * k)))
	bsb.corner_radius_top_left = roundi(12 * k)
	bsb.corner_radius_top_right = roundi(12 * k)
	bsb.corner_radius_bottom_left = roundi(8 * k)
	bsb.corner_radius_bottom_right = roundi(8 * k)
	draw_style_box(bsb, body)
	draw_rect(Rect2(cx - 11 * k, top + 36 * k, 22 * k, 2 * k), Color(1, 1, 1, 0.18))
	for i in 4:
		var col := i % 2
		var row := i / 2
		var tr := Rect2(cx + (-20.5 * k if col == 0 else 5.5 * k), top + 4 * k + row * 48 * k, 15 * k, 26 * k)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = tyre_color(_tyre_use[i])
		tsb.border_color = Color(0, 0, 0, 0.25)
		tsb.set_border_width_all(1)
		tsb.set_corner_radius_all(roundi(4 * k))
		draw_style_box(tsb, tr)
	# ABS / TC / AUT
	var abs_now := false
	for wh in car.wheels:
		abs_now = abs_now or wh.abs_active
	var aids := [["ABS", car.assists.abs, abs_now and car.assists.abs], ["TC", car.assists.tc, car.tc_cut > 0.05 and car.assists.tc],
		["AUT", car.assists.auto, false]]
	var fs := 10.0 * k
	var x := r.position.x + 8 * k
	var y := r.end.y - 20 * k
	for a in aids:
		var tw := _text_w(_bold, a[0], fs) + 8 * k
		var ar := Rect2(x, y, tw, 14 * k)
		var on: bool = a[1]
		var active: bool = a[2]
		var col := Color(1, 1, 1, 0.85 if on else 0.3)
		if active:
			draw_rect(ar, Color("#ffb020"))
			col = Color("#0b0d11")
		draw_rect(ar, Color("#ffb020") if active else Color(1, 1, 1, 0.22 if on else 0.08), false, 1.0)
		_text(_bold, ar.position + Vector2(4 * k, 1.5 * k), a[0], fs, col)
		x += tw + 3 * k


# ------------------------------------------------------------------ painel do Porsche 992 GT3 R (câmera de capô)

static func _led_color(i: int) -> Color:
	return Color("#2fd06b") if i < 6 else (Color("#f1d12b") if i < 11 else Color("#ff3b3b"))


func _box(r: Rect2, bg: Color, border: Color, bw: float, radius := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(maxi(1, roundi(bw)))
	sb.set_corner_radius_all(roundi(radius))
	draw_style_box(sb, r)


func _draw_dash(pos: Vector2, ks: float) -> void:
	var lim: float = car.p.limiter
	var t := timer
	# corpo preto 640×300
	var body := Rect2(pos, Vector2(640, 300) * ks)
	_box(body, Color("#121316"), Color("#000000"), 1 * ks, 14 * ks)
	# 16 luzes de troca nos ~1900 rpm antes do ponto de troca; todas azuis piscando na hora de trocar
	var shift_at := lim - 300.0
	var shift_now := car.rpm > shift_at
	var lit := ceili(clampf((car.rpm - (shift_at - 1900.0)) / 1900.0, 0.0, 1.0) * DASH_LEDS)
	var blink := shift_now and int(_time / 0.06) % 2 == 0
	var led_w := 13.0 * ks
	var gap := 9.0 * ks
	var x0 := pos.x + 320 * ks - (DASH_LEDS * led_w + (DASH_LEDS - 1) * gap) / 2.0
	for i in DASH_LEDS:
		var c := Vector2(x0 + i * (led_w + gap) + led_w / 2.0, pos.y + 12 * ks + led_w / 2.0)
		var on := blink if shift_now else i < lit
		var col := Color("#4aa3ff") if shift_now else _led_color(i)
		if on:
			draw_circle(c, led_w * 0.8, Color(col, 0.35))
		draw_circle(c, led_w / 2.0, col if on else Color("#1b1d22"))
	# luzes roxas dos lados: TC à esquerda, ABS à direita
	var abs_now := false
	for wh in car.wheels:
		abs_now = abs_now or wh.abs_active
	abs_now = abs_now and car.assists.abs
	var tc_now: bool = car.assists.tc and car.tc_cut > 0.05
	for i in 3:
		var y := pos.y + (58 + 7 + i * 26) * ks
		for side in [[14.0, tc_now], [626.0, abs_now]]:
			var c := Vector2(pos.x + side[0] * ks, y)
			if side[1]:
				draw_circle(c, 10 * ks, Color(192 / 255.0, 43 / 255.0, 1.0, 0.35))
			draw_circle(c, 7 * ks, Color("#c02bff") if side[1] else Color("#1b1d22"))
	# tela: grade 52 | 108 | 1fr | 150 (colunas), 26 | 1fr | 64 (linhas), vão 6×8, padding 8×10
	var scr := Rect2(pos + Vector2(42, 36) * ks, Vector2(640 - 84, 300 - 36 - 22) * ks)
	_box(scr, Color("#0b0c0e"), Color("#24272c"), 1 * ks, 6 * ks)
	var ix := scr.position.x + 10 * ks
	var iy := scr.position.y + 8 * ks
	var iw := scr.size.x - 20 * ks
	var ih := scr.size.y - 16 * ks
	var cols := [52.0, 108.0, 0.0, 150.0]
	cols[2] = iw / ks - 52 - 108 - 150 - 3 * 8
	var cx := [ix, ix + (52 + 8) * ks, ix + (52 + 108 + 16) * ks, ix + iw - 150 * ks]
	var rows_y := [iy, iy + (26 + 6) * ks, iy + ih - 64 * ks]
	var mid_h := ih - (26 + 6 + 64 + 6) * ks
	var gray := Color("#9aa1aa")
	# linha de cima: TIME ATTACK · PORSCHE · SECO
	_text(_bold, Vector2(ix, iy + 4 * ks), "TIME ATTACK", 15 * ks, Color("#ff3b3b"))
	var brand := "P O R S C H E"
	var bw := _text_w(_bold, brand, 24 * ks)
	draw_string_outline(_bold, Vector2(ix + iw / 2.0 - bw / 2.0, iy + _bold.get_ascent(roundi(24 * ks))), brand, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24 * ks), 1, Color("#8a9099"))
	var dry_w := _text_w(_bold, "SECO", 14 * ks) + 16 * ks
	var dry := Rect2(Vector2(ix + iw - dry_w, iy + 2 * ks), Vector2(dry_w, 22 * ks))
	_box(dry, Color(0, 0, 0, 0), Color("#3fd18a"), 1.5 * ks, 3 * ks)
	_text(_bold, dry.position + Vector2(8 * ks, 2 * ks), "SECO", 14 * ks, Color("#3fd18a"))
	# coluna 1: chaves ABS / TC / AUT (laranja = ligada; cheia = atuando)
	var keys := [["ABS", car.assists.abs, abs_now], ["TC", car.assists.tc, tc_now], ["AUT", car.assists.auto, false]]
	for i in keys.size():
		var kr := Rect2(Vector2(cx[0], rows_y[1] + i * 28 * ks), Vector2(52 * ks, 22 * ks))
		var on: bool = keys[i][1]
		var act: bool = keys[i][2]
		_box(kr, Color("#e08a1e") if act else Color(0, 0, 0, 0), Color("#e08a1e") if on else Color("#444444"), 1.5 * ks, 3 * ks)
		var fc := Color.BLACK if act else (Color("#e08a1e") if on else Color("#777777"))
		_text(_bold, kr.position + Vector2(4 * ks, 4 * ks), keys[i][0], 11 * ks, fc)
		var st := "ON" if on else "OFF"
		_text(_bold, Vector2(kr.end.x - 4 * ks - _text_w(_bold, st, 11 * ks), kr.position.y + 4 * ks), st, 11 * ks, Color.BLACK if act else (Color.WHITE if on else Color("#777777")))
	# coluna 2: tabela
	var tab := [["RPM", str(roundi(car.rpm / 10.0) * 10)], ["Freio diant.", "%d%%" % roundi(car.p.brake_bias * 100)],
		["Lat. g", "%.2f" % absf(car.g_lat)], ["Long. g", "%.2f" % car.g_long], ["Volta", str(t.laps.size() + 1)]]
	for i in tab.size():
		var rr := Rect2(Vector2(cx[1], rows_y[1] + i * 24 * ks), Vector2(108 * ks, 22 * ks))
		draw_rect(rr, Color("#2a2d33"))
		_text(_font, rr.position + Vector2(6 * ks, 3 * ks), tab[i][0], 13 * ks, gray)
		_text(_bold, Vector2(rr.end.x - 6 * ks - _text_w(_bold, tab[i][1], 13 * ks), rr.position.y + 3 * ks), tab[i][1], 13 * ks, WHITE)
	# coluna 3: velocidade, marcha grande e barra de giro
	var mw: float = cols[2] * ks
	var mx: float = cx[2]
	var spd := Rect2(Vector2(mx, rows_y[1]), Vector2(mw, 28 * ks))
	_box(spd, Color.BLACK, Color("#555a63"), 1 * ks)
	var kmh := str(roundi(absf(car.fwd_speed()) * 3.6))
	var sw := _text_w(_bold, kmh, 22 * ks) + 4 * ks + _text_w(_font, "km/h", 11 * ks)
	_text(_bold, Vector2(mx + mw / 2.0 - sw / 2.0, rows_y[1] + 1 * ks), kmh, 22 * ks, WHITE)
	_text(_font, Vector2(mx + mw / 2.0 - sw / 2.0 + _text_w(_bold, kmh, 22 * ks) + 4 * ks, rows_y[1] + 10 * ks), "km/h", 11 * ks, gray)
	var gr := Rect2(Vector2(mx, rows_y[1] + 32 * ks), Vector2(mw, mid_h - 32 * ks - 10 * ks))
	_box(gr, Color.BLACK, Color("#555a63"), 1 * ks)
	var gear := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	_text(_bold, Vector2(mx, gr.position.y + gr.size.y / 2.0 - 46 * ks), gear, 92 * ks, Color("#4aa3ff") if shift_now else WHITE, HORIZONTAL_ALIGNMENT_CENTER, mw)
	var rb := Rect2(Vector2(mx, gr.end.y + 4 * ks), Vector2(mw, 6 * ks))
	var rpm_frac := clampf((car.rpm - 3000.0) / (lim - 3000.0), 0.0, 1.0)
	# degradê fixo verde → amarelo → vermelho → azul; a parte apagada cobre da direita
	var segs := [[0.0, Color("#2fd06b")], [0.65, Color("#f1d12b")], [0.85, Color("#ff3b3b")], [1.0, Color("#4aa3ff")]]
	for i in range(1, segs.size()):
		var a: float = segs[i - 1][0]
		var b: float = segs[i][0]
		var n := 6
		for j in n:
			var f0 := a + (b - a) * j / n
			var f1 := a + (b - a) * (j + 1) / n
			var col: Color = (segs[i - 1][1] as Color).lerp(segs[i][1], (j + 0.5) / n)
			draw_rect(Rect2(rb.position.x + rb.size.x * f0, rb.position.y, rb.size.x * (f1 - f0) + 1, rb.size.y), col)
	draw_rect(Rect2(rb.position.x + rb.size.x * rpm_frac, rb.position.y, rb.size.x * (1.0 - rpm_frac), rb.size.y), Color("#222222"))
	# coluna 4: tempos
	var d := t.delta
	var dc := WHITE if is_nan(d) else (Color("#3fd18a") if d < 0.0 else Color("#ff4b4b"))
	var ds := "--" if is_nan(d) else (("+" if d > 0.0 else ("−" if d < 0.0 else "")) + "%.2f" % absf(d))
	var pred := "--" if (is_nan(d) or t.best == null) else LapTimer.format_time(t.best.time + d).left(-1)
	var boxes := [["Volta atual", LapTimer.format_time(t.current), 2, WHITE if t.valid else Color("#ff4b4b")],
		["Delta", ds, 1, dc], ["Previsão", pred, 1, dc],
		["Melhor", LapTimer.format_time(t.best.time if t.best else -1.0), 2, Color("#c58bff")]]
	var bx: float = cx[3]
	var by: float = rows_y[1]
	var half := (150 - 4) * ks / 2.0
	var col_i := 0
	for b in boxes:
		var wide: bool = b[2] == 2
		var bw2 := 150 * ks if wide else half
		var bxx: float = bx if (wide or col_i == 0) else bx + half + 4 * ks
		var br := Rect2(Vector2(bxx, by), Vector2(bw2, (46 if wide else 40) * ks))
		_box(br, Color.BLACK, Color("#555a63"), 1 * ks)
		draw_rect(Rect2(br.position + Vector2(1, 1) * ks, Vector2(br.size.x - 2 * ks, 16 * ks)), Color("#2a2d33"))
		_text(_font, br.position + Vector2(0, 1 * ks), b[0], 12 * ks, gray, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		_text(_bold, br.position + Vector2(0, 17 * ks), b[1], (25 if wide else 19) * ks, b[3], HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		if wide:
			by += br.size.y + 4 * ks
			col_i = 0
		else:
			col_i += 1
			if col_i == 2:
				by += br.size.y + 4 * ks
				col_i = 0
	# linha de baixo: CURVA · SETORES · pedais
	var byy: float = rows_y[2]
	_text(_font, Vector2(ix, byy + 12 * ks), "CURVA", 12 * ks, gray)
	_text(_bold, Vector2(ix, byy + 28 * ks), section, 16 * ks, WHITE, HORIZONTAL_ALIGNMENT_LEFT, 160 * ks)
	var sx := ix + 168 * ks
	var sw2 := iw - 168 * ks - 158 * ks
	var sr := Rect2(Vector2(sx, byy), Vector2(sw2, 64 * ks))
	_box(sr, Color(0, 0, 0, 0), Color("#e08a1e"), 1.5 * ks)
	draw_rect(Rect2(sr.position, Vector2(sr.size.x, 16 * ks)), Color("#e08a1e"))
	_text(_bold, sr.position + Vector2(0, 1 * ks), "SETORES", 12 * ks, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
	for i in 3:
		var cw := sr.size.x / 3.0
		var txt := "—"
		var col := WHITE
		if i < t.sectors.size():
			txt = "%.2f" % t.sectors[i]
			var sc := sector_color(i, t.sectors[i])
			col = Color("#3fd18a") if sc == GREEN else (Color("#f2c230") if sc == YELLOW else Color("#c58bff"))
		if i > 0:
			draw_line(Vector2(sr.position.x + cw * i, sr.position.y + 18 * ks), Vector2(sr.position.x + cw * i, sr.end.y - 2 * ks), Color("#333333"), 1.0)
		_text(_bold, Vector2(sr.position.x + cw * i, sr.position.y + 28 * ks), txt, 17 * ks, col, HORIZONTAL_ALIGNMENT_CENTER, cw)
	var px := ix + iw - 150 * ks
	for ped in [["FREIO", brake, Color("#ff3b3b")], ["ACEL.", throttle, Color("#2fd06b")]]:
		var pr := Rect2(Vector2(px, byy), Vector2(72 * ks, 64 * ks))
		_box(pr, Color("#2a2d33"), Color("#555a63"), 1 * ks)
		var fh: float = (pr.size.y - 2 * ks) * ped[1]
		draw_rect(Rect2(pr.position.x + 1 * ks, pr.end.y - 1 * ks - fh, pr.size.x - 2 * ks, fh), ped[2])
		_text(_bold, Vector2(pr.position.x, pr.end.y - 16 * ks), ped[0], 11 * ks, WHITE, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
		px += 78 * ks


# ------------------------------------------------------------------ telemetria (T)

func _draw_telemetry(pos: Vector2) -> void:
	var names := ["DE", "DD", "TE", "TD"]
	var lines := [
		"g lat %.2f  g long %.2f  rpm %d  TC corte %d%%" % [car.g_lat, car.g_long, int(car.rpm), int(car.tc_cut * 100)],
		"pico pneu: κ %.3f  α %.1f°" % [car.kappa_peak, rad_to_deg(car.alpha_peak)],
	]
	for i in 4:
		var w := car.wheels[i]
		lines.append("%s  Fz %5.2f kN  κ %6.3f  α %5.1f°  susp %3d mm  %s" % [names[i], w.fz / 1000.0, w.kappa, rad_to_deg(w.alpha),
			int(w.comp * 1000), Ground.NAMES[w.surface] if w.contact else "ar"])
	lines.append("%d fps  %s  %s" % [fps, quality, "piloto automático" if autopilot else ""])
	var fs := 13
	var h := lines.size() * fs * 1.45 + 16
	var w := 0.0
	for l in lines:
		w = maxf(w, _text_w(_mono, l, fs))
	draw_rect(Rect2(pos - Vector2(0, h / 2.0), Vector2(w + 20, h)), Color(0, 0, 0, 0.7))
	var y := pos.y - h / 2.0 + 8
	for l in lines:
		_text(_mono, Vector2(pos.x + 10, y), l, fs, Color("#d8f3dc"))
		y += fs * 1.45
