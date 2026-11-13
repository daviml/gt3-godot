# HUD estilo LMU (porte de src/ui/hud.ts + minimap.ts do web), desenhado por código num único Control:
# - topo central: FPS + botão MENU (+ botões rápidos de Câmera e Reset no modo toque)
# - superior esquerdo: melhores tempos (expansível/recolhível ao clicar)
# - superior direito: Best / Current com 3 setores coloridos, delta ao vivo, aviso de volta inválida e nome da curva
# - minimapa (canto inferior esquerdo no PC; ao lado dos tempos no celular): modo RADAR dinâmico ou CIRCUITO (clicável)
# - mostrador principal: Barra Horizontal no topo (padrão, com RPM, pneus, ABS/TC/AUT, pedais, marcha/kmh, força G e delta)
#   ou Mostrador Circular clássico estilo LMU (alternável no menu de pausa)
# - Porsche na câmera de capô: painel no estilo do display real do 992 GT3 R, centralizado embaixo (PC) ou em cima (touch)
class_name Hud
extends Control

signal menu_requested
signal camera_requested
signal reset_requested

const MAX_RPM := 9000.0
## mostrador circular: arco de giro de 240° (150° → 390°) com raio 86 numa caixa de 200; pedais a 73 de raio, 70° cada
const GR := 86.0
const PR := 73.0
const GAUGE := 226.0
const HBAR_W := 536.0
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
const DASH_CARS := []
const DASH_LEDS := 16
const GAUGE_STYLES := ["barra", "circular"]
const MAP_MODES := ["dynamic", "circuit"]

## Radar dinâmico: amostras atrás/à frente (passo de 2 amostras = 4 m → 156 pontos leves)
const RADAR_BACK := 85
const RADAR_AHEAD := 225
const RADAR_STEP := 2
const RADAR_N := (RADAR_BACK + RADAR_AHEAD) / RADAR_STEP + 1

const INTERLAGOS_CORNERS := [
	[1, "S do Senna 1", 360.0],
	[2, "S do Senna 2", 460.0],
	[3, "Curva do Sol", 720.0],
	[4, "Descida do Lago 1", 1420.0],
	[5, "Descida do Lago 2", 1540.0],
	[6, "Ferradura", 2030.0],
	[7, "Laranjinha", 2180.0],
	[8, "Pinheirinho 1", 2330.0],
	[9, "Pinheirinho 2", 2460.0],
	[10, "Bico de Pato", 2780.0],
	[11, "Mergulho", 3120.0],
	[12, "Junção", 3280.0],
	[13, "Subida dos Boxes", 3600.0],
	[14, "Arquibancadas", 3950.0],
	[15, "Café", 4200.0],
]

var car: Car
var timer: LapTimer
var track: Track
var touch := false
var arcade := false
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
var gauge_style := "barra"
var map_mode := "dynamic"
var board_expanded := false
var menu_open := false
var section := ""
var toast_text := ""
var toast_t := 0.0
var fps := 0
var quality := ""
var quality_level := 2
var autopilot := false

var _font: Font
var _bold: Font
var _mono: Font
var _tyre_use := [0.0, 0.0, 0.0, 0.0]
var _g_trail: Array[Vector2] = []
var _fps_frames := 0
var _fps_since := 0.0
var _time := 0.0
var _redraw_t := 0.0
var _k := 1.0
var _kb := 1.0
var _kp := 1.0
var _top_sc := 1.0
var _shorts := {}
var _colors := {}

# mapa / radar: pontos da pista, curvas detectadas e buffers pré-alocados
var _map_pts := PackedVector2Array()
var _map_scale := 1.0
var _map_min := Vector2.ZERO
var _map_off := Vector2.ZERO
var _map_finish: Array = []
var _map_pos := Vector2.ZERO
var _map_origin := Vector2.ZERO
var _map_draw_pts := PackedVector2Array()
var _map_finish_draw: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _map_layout_sc := -1.0
var _corners: Array = []  # [{number, name, s, pos, map_pt}]
var _radar_angle := 0.0
var _radar_inited := false
var _radar_center := Vector2.ZERO
var _radar_radius := 76.0
var _radar_left := PackedVector2Array()
var _radar_right := PackedVector2Array()
var _radar_cline := PackedVector2Array()
var _radar_tri_pts := PackedVector2Array()
var _radar_tri_cols := PackedColorArray()
var _radar_tri_idx := PackedInt32Array()
var _radar_edge_segs := PackedVector2Array()
var _radar_cline_segs := PackedVector2Array()
var _radar_kerb_w_segs := PackedVector2Array()
var _radar_kerb_r_segs := PackedVector2Array()
var _cone_pts := PackedVector2Array()
var _arrow_pts := PackedVector2Array()
var _arrow_outline_pts := PackedVector2Array()
var _radar_tip_pts := PackedVector2Array()
var _reset_tip_pts := PackedVector2Array()
var _g_trail_pts := PackedVector2Array()

# áreas clicáveis (botões transparentes para respeitar PauseMenu e TouchControls)
var _btn_menu: Button
var _btn_cam: Button
var _btn_reset: Button
var _btn_board: Button
var _btn_map: Button
var _r_menu := Rect2()
var _r_cam := Rect2()
var _r_reset := Rect2()
var _r_board := Rect2()
var _r_map := Rect2()

# StyleBoxes e buffers pré-alocados (sem alocação por quadro em _draw)
var _fps_sb: StyleBoxFlat
var _tyres_panel_sb: StyleBoxFlat
var _tyres_body_sb: StyleBoxFlat
var _tyre_sbs: Array[StyleBoxFlat] = []
var _box_sb: StyleBoxFlat
var _hbar_sb: StyleBoxFlat
var _pill_sb: StyleBoxFlat
var _panel_pts := PackedVector2Array()


func _init(c: Car, t: LapTimer, tr: Track, car_id: String, is_touch: bool) -> void:
	car = c
	timer = t
	track = tr
	touch = is_touch
	dash = car_id in DASH_CARS
	var saved_g := String(Game.get_setting("hud", "mostrador", "barra"))
	gauge_style = saved_g if saved_g in GAUGE_STYLES else "barra"
	var saved_m := String(Game.get_setting("hud", "minimapa", "dynamic"))
	map_mode = saved_m if saved_m in MAP_MODES else "dynamic"
	var list = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	for e in list:
		_shorts[e.id] = e.get("short", e.id)
		_colors[e.id] = Color(e.get("color", "#ffffff"))
	car_color = _colors.get(car_id, Color.WHITE)
	_build_corners()
	_build_map()
	_init_radar_buffers()


func _init_radar_buffers() -> void:
	_radar_left.resize(RADAR_N)
	_radar_right.resize(RADAR_N)
	_radar_cline.resize(RADAR_N)
	_cone_pts.resize(3)
	_arrow_pts.resize(4)
	_arrow_outline_pts.resize(5)
	_radar_tip_pts.resize(3)
	_reset_tip_pts.resize(3)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _sys_font(500)
	_bold = _sys_font(700)
	_mono = SystemFont.new()
	(_mono as SystemFont).font_names = PackedStringArray(["Consolas", "Droid Sans Mono", "monospace"])
	_ensure_styleboxes()
	_build_interactive_nodes()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build_interactive_nodes() -> void:
	var make_btn := func(cb: Callable) -> Button:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, empty)
		b.pressed.connect(cb)
		add_child(b)
		return b

	_btn_board = make_btn.call(_toggle_board)
	_btn_map = make_btn.call(_toggle_map_mode)
	_btn_menu = make_btn.call(func(): menu_requested.emit())
	_btn_cam = make_btn.call(func(): camera_requested.emit())
	_btn_reset = make_btn.call(func(): reset_requested.emit())
	_sync_btn_visibility()


func _sync_btn_visibility() -> void:
	if _btn_menu == null:
		return
	var show_top := not menu_open
	_btn_menu.visible = show_top
	_btn_cam.visible = show_top and touch
	_btn_reset.visible = show_top and touch


func _toggle_board() -> void:
	board_expanded = not board_expanded
	_redraw_t = 1.0
	queue_redraw()


func _toggle_map_mode() -> void:
	map_mode = "circuit" if map_mode == "dynamic" else "dynamic"
	Game.set_setting("hud", "minimapa", map_mode)
	_sync_btn_visibility()
	_redraw_t = 1.0
	queue_redraw()


func set_gauge_style(style: String) -> void:
	gauge_style = style if style in GAUGE_STYLES else "barra"
	Game.set_setting("hud", "mostrador", gauge_style)
	_redraw_t = 1.0
	queue_redraw()


func set_menu_open(is_open: bool) -> void:
	menu_open = is_open
	_sync_btn_visibility()
	_redraw_t = 1.0
	queue_redraw()


func _ensure_styleboxes() -> void:
	if _fps_sb == null:
		_fps_sb = StyleBoxFlat.new()
		_fps_sb.bg_color = Color(10 / 255.0, 12 / 255.0, 16 / 255.0, 0.62)
	if _tyres_panel_sb == null:
		_tyres_panel_sb = StyleBoxFlat.new()
		_tyres_panel_sb.bg_color = Color(13 / 255.0, 24 / 255.0, 46 / 255.0, 0.86)
		_tyres_panel_sb.shadow_color = Color(0, 0, 0, 0.35)
	if _tyres_body_sb == null:
		_tyres_body_sb = StyleBoxFlat.new()
		_tyres_body_sb.bg_color = Color(0, 0, 0, 0)
		_tyres_body_sb.border_color = Color(1, 1, 1, 0.28)
	if _tyre_sbs.is_empty():
		for _i in 4:
			var tsb := StyleBoxFlat.new()
			tsb.border_color = Color(0, 0, 0, 0.25)
			tsb.set_border_width_all(1)
			_tyre_sbs.append(tsb)
	if _box_sb == null:
		_box_sb = StyleBoxFlat.new()
	if _hbar_sb == null:
		_hbar_sb = StyleBoxFlat.new()
		_hbar_sb.bg_color = Color(11 / 255.0, 20 / 255.0, 40 / 255.0, 0.90)
		_hbar_sb.border_color = Color(1, 1, 1, 0.14)
		_hbar_sb.shadow_color = Color(0, 0, 0, 0.42)
	if _pill_sb == null:
		_pill_sb = StyleBoxFlat.new()
	if _panel_pts.size() != 5:
		_panel_pts.resize(5)


## fonte do sistema no estilo condensado dos sims (Bahnschrift no Windows; Roboto no Android)
static func _sys_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "sans-serif"])
	f.font_weight = weight
	return f


func _layout() -> void:
	_ensure_styleboxes()
	var s := get_viewport_rect().size
	if touch:
		_k = clampf(s.y / 640.0, 1.10, 1.55)
		_kb = clampf(s.y / 560.0, 1.25, 1.65)
		_kp = clampf(s.y / 640.0, 1.15, 1.50)
		_top_sc = clampf(s.y / 360.0, 1.35, 1.90)
	else:
		_k = maxf(0.62, minf(1.15, s.y / 860.0))
		_kb = maxf(0.7, minf(1.05, _k * 0.92))
		_kp = maxf(_k, minf(1.67, 1.67 * minf(s.x / 2552.0, s.y / 1268.0)))
		_top_sc = clampf(s.y / 860.0, 0.85, 1.18)

	_fps_sb.set_corner_radius_all(roundi(4 * _top_sc))

	var low_gpu := touch or quality_level <= 1
	_tyres_panel_sb.set_corner_radius_all(roundi(10 * _k))
	_tyres_panel_sb.shadow_size = 0 if low_gpu else roundi(6 * _k)
	_tyres_panel_sb.shadow_offset = Vector2(0, 4 * _k)
	_tyres_body_sb.set_border_width_all(maxi(1, roundi(2 * _k)))
	_tyres_body_sb.corner_radius_top_left = roundi(12 * _k)
	_tyres_body_sb.corner_radius_top_right = roundi(12 * _k)
	_tyres_body_sb.corner_radius_bottom_left = roundi(8 * _k)
	_tyres_body_sb.corner_radius_bottom_right = roundi(8 * _k)
	var tyre_rad := roundi(4 * _k)
	for tsb in _tyre_sbs:
		tsb.set_corner_radius_all(tyre_rad)

	_hbar_sb.border_width_left = 1
	_hbar_sb.border_width_right = 1
	_hbar_sb.border_width_bottom = 1
	_hbar_sb.border_width_top = 0
	_hbar_sb.corner_radius_top_left = 0
	_hbar_sb.corner_radius_top_right = 0
	_hbar_sb.corner_radius_bottom_left = roundi(8 * _kb)
	_hbar_sb.corner_radius_bottom_right = roundi(8 * _kb)
	_hbar_sb.shadow_size = 0 if low_gpu else roundi(10 * _kb)
	_hbar_sb.shadow_offset = Vector2(0, 5 * _kb)

	var ins := _insets()
	var timing_w := (270.0 if touch else 250.0) * _kp
	var tr := Vector2(s.x - ins.size.x - 14 - timing_w, 14 + ins.position.y)
	var map_size := Vector2(196, 212) * _kp
	var map_pos := Vector2(tr.x - 10 * _kp - map_size.x, tr.y) if touch else Vector2(14 + ins.position.x, s.y - ins.size.y - 14 - map_size.y)
	_update_map_layout(map_pos, _kp)


func _update_map_layout(pos: Vector2, sc: float) -> void:
	_map_pos = pos
	_map_layout_sc = sc
	_map_origin = pos + Vector2(8 * sc, 34 * sc)
	_map_draw_pts.resize(_map_pts.size())
	for i in _map_pts.size():
		_map_draw_pts[i] = _map_origin + _map_pts[i] * sc
	if _map_finish.size() >= 2:
		_map_finish_draw[0] = _map_origin + _map_finish[0] * sc
		_map_finish_draw[1] = _map_origin + _map_finish[1] * sc

	_radar_center = pos + Vector2(93.0 * sc, 25.0 * sc + 79.0 * sc)
	_radar_radius = 74.0 * sc


## câmera atual: o painel do Porsche só aparece na de capô (nas de fora ele tampava a traseira do carro)
func set_view(mode: String) -> void:
	dash_on = dash and mode == "capô"


func toast(t: String) -> void:
	toast_text = t
	toast_t = 1.6
	_redraw_t = 1.0
	queue_redraw()


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
	# rastro recente de força G (até 2,8 G no raio útil de 24 unidades)
	var gx := clampf(car.g_lat / 2.8 * 24.0, -24.0, 24.0)
	var gy := clampf(-car.g_long / 2.8 * 24.0, -24.0, 24.0)
	if _g_trail.is_empty() or _g_trail[_g_trail.size() - 1].distance_to(Vector2(gx, gy)) > 0.6:
		_g_trail.append(Vector2(gx, gy))
		if _g_trail.size() > 14:
			_g_trail.pop_front()
	# suavização angular do radar dinâmico (heading-up)
	if map_mode == "dynamic":
		var fvec := car.rot * Vector3.FORWARD
		var target_ang := atan2(fvec.x, -fvec.z)
		if not _radar_inited:
			_radar_angle = target_ang
			_radar_inited = true
		else:
			var diff := wrapf(target_ang - _radar_angle, -PI, PI)
			_radar_angle += diff * clampf(dt * 10.0, 0.0, 1.0)
	# FPS 4x por segundo (média da janela, sem tremer)
	_fps_frames += 1
	_fps_since += dt
	if _fps_since >= 0.25:
		fps = roundi(_fps_frames / _fps_since)
		_fps_frames = 0
		_fps_since = 0.0
	toast_t -= dt
	section = track.section_at(timer.s)
	# Limita o redesenho do HUD a 30 Hz no mobile e nos presets Mínimo/Leve (60 Hz em Médio/Extremo),
	# evitando redesenhar ~100 strings via SystemFont em monitores de alta taxa de atualização.
	_redraw_t += dt
	var interval := (1.0 / 30.0) if (touch or quality_level <= 1) else (1.0 / 60.0)
	if _redraw_t >= interval:
		_redraw_t = 0.0
		queue_redraw()


# ------------------------------------------------------------------ desenho

func _draw() -> void:
	var s := get_viewport_rect().size
	var ins := _insets()
	var k := _k
	var kp := _kp
	# 1. barra superior central: FPS + MENU + botões rápidos (touch)
	var top_bottom := _draw_top_bar(Vector2(s.x / 2.0, 4.0 + ins.position.y))
	# 2. painéis: melhores tempos (esq. cima), tempos (dir. cima), mapa (esq. baixo no PC ou ao lado dos tempos no celular)
	_draw_board(Vector2(14 + ins.position.x, 14 + ins.position.y), kp)
	var timing_w := 250.0 * kp
	var tr := Vector2(s.x - ins.size.x - 14 - timing_w, 14 + ins.position.y)
	_draw_timing(tr, kp)
	var map_size := Vector2(186, 202) * kp
	if touch:
		_draw_map(Vector2(tr.x - 8 * kp - map_size.x, tr.y), kp)
	else:
		_draw_map(Vector2(14 + ins.position.x, s.y - ins.size.y - 14 - map_size.y), kp)
	# 3. mostrador principal (Barra Horizontal no topo, Circular LMU ou painel do Porsche na câmera de capô)
	var cl_w := (GAUGE + 8 + 86) * k
	if dash_on:
		var ks := minf(s.x * 0.21 / 640.0, s.y * 0.198 / 300.0)
		if touch:
			ks = 226.0 * k / 300.0
			_draw_dash(Vector2(s.x / 2.0 - 320 * ks, top_bottom + 4.0), ks)
		else:
			_draw_dash(Vector2(s.x / 2.0 - 320 * ks, s.y - 0.004 * s.x - 300 * ks), ks)
	elif gauge_style == "barra":
		_draw_hbar(Vector2(s.x / 2.0 - (HBAR_W * _kb) / 2.0, top_bottom + 4.0), _kb)
	elif touch:
		_draw_cluster(Vector2(s.x / 2.0 - cl_w / 2.0, top_bottom + 4.0), k)
	else:
		_draw_cluster(Vector2(s.x - ins.size.x - 16 - cl_w, s.y - ins.size.y - 14 - GAUGE * k), k)
	if toast_t > 0.0:
		_draw_toast(s)
	if telemetry:
		_draw_telemetry(Vector2(12, s.y * 0.5))
	_sync_hitboxes()


func _sync_hitboxes() -> void:
	if _btn_board:
		_btn_board.position = _r_board.position
		_btn_board.size = _r_board.size
	if _btn_map:
		_btn_map.position = _r_map.position
		_btn_map.size = _r_map.size
	if _btn_menu:
		_btn_menu.position = _r_menu.position
		_btn_menu.size = _r_menu.size
	if _btn_cam:
		_btn_cam.position = _r_cam.position
		_btn_cam.size = _r_cam.size
	if _btn_reset:
		_btn_reset.position = _r_reset.position
		_btn_reset.size = _r_reset.size


## margens de recorte da tela (câmera/entalhe), como o env(safe-area-inset-*) do web
func _insets() -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2()
	var safe := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	return Rect2(safe.position.x, safe.position.y, scr.x - safe.end.x, scr.y - safe.end.y)


## painel LMU: vidro escuro, filete de cor no topo e canto inferior direito cortado
func _panel(r: Rect2, sc: float, invalid := false) -> void:
	var cut := 10.0 * sc
	if _panel_pts.size() != 5:
		_panel_pts.resize(5)
	_panel_pts[0] = r.position
	_panel_pts[1] = Vector2(r.end.x, r.position.y)
	_panel_pts[2] = Vector2(r.end.x, r.end.y - cut)
	_panel_pts[3] = Vector2(r.end.x - cut, r.end.y)
	_panel_pts[4] = Vector2(r.position.x, r.end.y)
	var bg := Color(40 / 255.0, 14 / 255.0, 18 / 255.0, 0.84) if invalid else Color(14 / 255.0, 17 / 255.0, 22 / 255.0, 0.78)
	draw_colored_polygon(_panel_pts, bg)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2 * sc)), Color("#ff4b5c") if invalid else ACCENT)


func _text(f: Font, pos: Vector2, t: String, size: float, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var fs := maxi(6, roundi(size))
	draw_string(f, pos + Vector2(0, f.get_ascent(fs)), t, align, width, fs, c)


func _text_w(f: Font, t: String, size: float) -> float:
	return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(6, roundi(size))).x


# ------------------------------------------------------------------ barra superior (FPS + MENU + ações)

func _draw_top_bar(top_center: Vector2) -> float:
	_ensure_styleboxes()
	var sc := _top_sc
	var fs := 12.0 * sc
	var h := 22.0 * sc
	var gap := 6.0 * sc

	# FPS pill
	var fps_num := str(fps)
	var fps_lbl := " FPS"
	var fps_w := _text_w(_bold, fps_num, fs) + _text_w(_font, fps_lbl, fs) + 14.0 * sc
	var menu_lbl := "MENU"
	var menu_w := 14.0 * sc + _text_w(_bold, menu_lbl, fs * 0.92) + 16.0 * sc
	var icon_w := 44.0 * sc

	var total_w := fps_w
	if not menu_open:
		total_w += gap + menu_w
		if touch:
			total_w += gap * 2.0 + icon_w * 2.0

	var x := top_center.x - total_w / 2.0
	var y := top_center.y

	# 1. FPS
	var fps_r := Rect2(x, y, fps_w, h)
	draw_style_box(_fps_sb, fps_r)
	var fc := GREEN if fps >= 55 else (Color("#ffb020") if fps >= 30 else RED)
	var nw := _text_w(_bold, fps_num, fs)
	_text(_bold, Vector2(x + 7.0 * sc, y + (h - fs) * 0.42), fps_num, fs, fc)
	_text(_font, Vector2(x + 7.0 * sc + nw, y + (h - fs) * 0.42), fps_lbl, fs, Color(1, 1, 1, 0.6))
	x += fps_w + gap

	if not menu_open:
		# 2. Botão ❚❚ MENU
		_r_menu = Rect2(x, y, menu_w, h)
		var m_hot := _btn_menu != null and (_btn_menu.is_hovered() or _btn_menu.button_pressed)
		_draw_top_pill(_r_menu, sc, m_hot)
		var bar_x := x + 8.0 * sc
		var bar_y := y + h * 0.28
		var bar_h := h * 0.44
		draw_rect(Rect2(bar_x, bar_y, 2.2 * sc, bar_h), Color.WHITE if m_hot else Color(1, 1, 1, 0.9))
		draw_rect(Rect2(bar_x + 4.2 * sc, bar_y, 2.2 * sc, bar_h), Color.WHITE if m_hot else Color(1, 1, 1, 0.9))
		_text(_bold, Vector2(bar_x + 10.0 * sc, y + (h - fs * 0.92) * 0.42), menu_lbl, fs * 0.92, Color.WHITE if m_hot else Color(1, 1, 1, 0.92))
		x += menu_w + gap

		if touch:
			# 3. Botão Câmera
			_r_cam = Rect2(x, y, icon_w, h)
			var c_hot := _btn_cam != null and (_btn_cam.is_hovered() or _btn_cam.button_pressed)
			_draw_top_pill(_r_cam, sc, c_hot)
			var cc := _r_cam.get_center()
			var col_c := Color.WHITE if c_hot else Color(1, 1, 1, 0.9)
			draw_rect(Rect2(cc + Vector2(-7 * sc, -4 * sc), Vector2(14 * sc, 9.5 * sc)), col_c, true)
			draw_rect(Rect2(cc + Vector2(-3 * sc, -6.5 * sc), Vector2(6 * sc, 2.5 * sc)), col_c, true)
			draw_circle(cc + Vector2(0, 0.8 * sc), 3.0 * sc, Color(10 / 255.0, 12 / 255.0, 16 / 255.0, 0.9))
			draw_circle(cc + Vector2(0, 0.8 * sc), 1.6 * sc, col_c)
			x += icon_w + gap

			# 4. Botão Reset (voltar ao grid)
			_r_reset = Rect2(x, y, icon_w, h)
			var r_hot := _btn_reset != null and (_btn_reset.is_hovered() or _btn_reset.button_pressed)
			_draw_top_pill(_r_reset, sc, r_hot)
			var rc := _r_reset.get_center()
			var col_r := Color.WHITE if r_hot else Color(1, 1, 1, 0.9)
			draw_arc(rc + Vector2(0, 0.5 * sc), 5.2 * sc, deg_to_rad(-155), deg_to_rad(135), 14, col_r, 1.8 * sc, not (touch or quality_level <= 1))
			var tip := rc + Vector2(-4.8 * sc, -2.5 * sc)
			if _reset_tip_pts.size() != 3:
				_reset_tip_pts.resize(3)
			_reset_tip_pts[0] = tip + Vector2(-2.2 * sc, 2.2 * sc)
			_reset_tip_pts[1] = tip + Vector2(2.6 * sc, 1.6 * sc)
			_reset_tip_pts[2] = tip + Vector2(0.2 * sc, -2.6 * sc)
			draw_colored_polygon(_reset_tip_pts, col_r)

	return y + h


func _draw_top_pill(r: Rect2, sc: float, hot: bool) -> void:
	_pill_sb.bg_color = Color(225 / 255.0, 6 / 255.0, 0.0, 0.85) if hot else Color(10 / 255.0, 12 / 255.0, 16 / 255.0, 0.72)
	_pill_sb.border_color = Color(1, 1, 1, 0.65 if hot else 0.30)
	_pill_sb.set_border_width_all(1)
	_pill_sb.set_corner_radius_all(roundi(4 * sc))
	draw_style_box(_pill_sb, r)


func _draw_toast(s: Vector2) -> void:
	var sc := _kp
	var fs := 18.0 * sc
	var w := _text_w(_bold, toast_text, fs) + 32 * sc
	var a := clampf(toast_t / 0.5, 0.0, 1.0)
	var r := Rect2(Vector2(s.x / 2.0 - w / 2.0, s.y * 0.34), Vector2(w, 36 * sc))
	draw_rect(r, Color(12 / 255.0, 14 / 255.0, 18 / 255.0, 0.85 * a))
	_text(_bold, r.position + Vector2(16 * sc, 7 * sc), toast_text, fs, Color(1, 1, 1, a))


static func _clean_car_short(car_id: String) -> String:
	var cid := car_id.to_lower()
	if "mercedes" in cid or "amg" in cid:
		return "AMG"
	if "porsche" in cid or "992" in cid:
		return "992"
	if "ferrari" in cid or "488" in cid:
		return "488"
	if "corvette" in cid or "c6r" in cid:
		return "C6R"
	if "c7" in cid:
		return "C7R"
	if "m4" in cid:
		return "M4"
	if "m6" in cid:
		return "M6"
	if "huracan" in cid:
		return "HUR"
	if "gallardo" in cid:
		return "GAL"
	if "720s" in cid or "mclaren" in cid:
		return "720S"
	if "gtr" in cid or "nissan" in cid:
		return "GTR"
	if "bentley" in cid:
		return "BEN"
	if "nsx" in cid:
		return "NSX"
	if "vantage" in cid or "aston" in cid:
		return "V12"
	var parts := car_id.split("-")
	return (parts[0].substr(0, 4) if parts.size() > 0 else car_id.substr(0, 4)).to_upper()


func _get_car_short(car_id: String) -> String:
	if _shorts.has(car_id) and String(_shorts[car_id]).length() <= 5:
		return String(_shorts[car_id])
	return _clean_car_short(car_id)


# ------------------------------------------------------------------ melhores tempos (expansível)

func _draw_board(pos: Vector2, sc: float) -> void:
	var w := (330.0 if touch else 300.0) * sc
	var row := (30.0 if touch else 27.0) * sc
	var indices: Array[int] = []
	if not records.is_empty():
		if board_expanded or records.size() <= 3:
			for i in records.size():
				indices.append(i)
		else:
			indices.append(0)
			var me_idx := -1
			if nick != "":
				for i in range(1, records.size()):
					if String(records[i].get("nick", "")).to_lower() == nick.to_lower():
						me_idx = i
						break
			if me_idx > 0:
				indices.append(me_idx)
			elif records.size() > 1:
				indices.append(1)
	var n := maxi(indices.size(), 1)
	var h := 28 * sc + row * n + 6 * sc
	_r_board = Rect2(pos, Vector2(w, h))
	_panel(_r_board, sc)
	_text(_bold, pos + Vector2(12 * sc, 7 * sc), "MELHORES TEMPOS", 12 * sc, Color(1, 1, 1, 0.92))
	var dim := Color(1, 1, 1, 0.45)
	var chev := "▴" if board_expanded else "▾"
	var track_lbl := ("INTERLAGOS · ARCADE " if arcade else "INTERLAGOS ") + chev
	var tw := _text_w(_font, track_lbl, 12 * sc)
	_text(_font, pos + Vector2(w - 12 * sc - tw, 7 * sc), track_lbl, 12 * sc, Color("#ff5e57") if arcade else dim)
	var y := pos.y + 28 * sc
	if records.is_empty():
		_text(_font, Vector2(pos.x + 12 * sc, y + 6 * sc), "Nenhuma volta válida ainda", 13 * sc, Color(1, 1, 1, 0.5))
		return
	var best := float(records[0].time)
	for i in indices:
		var r: Dictionary = records[i]
		var me: bool = String(r.get("nick", "")).to_lower() == nick.to_lower() and nick != ""
		if me:
			draw_rect(Rect2(pos.x, y, w, row), Color(1, 1, 1, 0.11))
		# posição
		var pr := Rect2(pos.x + 10 * sc, y + 3.5 * sc, 22 * sc, (22.0 if touch else 20.0) * sc)
		draw_rect(pr, WHITE if i == 0 else Color(1, 1, 1, 0.1))
		_text(_bold, pr.position + Vector2(0, 2 * sc), str(i + 1), (14.0 if touch else 13.0) * sc, Color("#0b0d11") if i == 0 else WHITE, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
		# carro (filete na cor + sigla curta garantida sem sobreposição)
		var cx := pos.x + 40 * sc
		draw_rect(Rect2(cx, y + 5.5 * sc, 3 * sc, 16 * sc), _colors.get(r.carId, Color.WHITE))
		var c_short := _get_car_short(String(r.carId))
		_text(_bold, Vector2(cx + 8 * sc, y + 5 * sc), c_short, (13.5 if touch else 13.0) * sc, WHITE, HORIZONTAL_ALIGNMENT_LEFT, 46 * sc)
		# nick
		var nick_x := pos.x + (100.0 if not touch else 108.0) * sc
		var nick_max_w := maxf(40.0 * sc, w - (nick_x - pos.x) - (78.0 if touch else 70.0) * sc)
		_text(_font, Vector2(nick_x, y + 4 * sc), String(r.nick), (14.0 if touch else 13.5) * sc, WHITE, HORIZONTAL_ALIGNMENT_LEFT, nick_max_w)
		# tempo ou gap
		var t := LapTimer.format_time(float(r.time)) if i == 0 else "+%.3f" % (float(r.time) - best)
		var tw2 := _text_w(_font, t, 14 * sc)
		_text(_font, Vector2(pos.x + w - 10 * sc - tw2, y + 4 * sc), t, 14 * sc, PURPLE if i == 0 else Color(1, 1, 1, 0.85))
		y += row


# ------------------------------------------------------------------ tempos (Best / Current / setores / delta)

func _draw_timing(pos: Vector2, sc: float) -> void:
	var w := (270.0 if touch else 250.0) * sc
	var pad := 12.0 * sc
	var t := timer
	var invalid := t.current >= 0.0 and not t.valid
	var h := ((200.0 if invalid else 176.0) if touch else (192.0 if invalid else 170.0)) * sc
	_panel(Rect2(pos, Vector2(w, h)), sc, invalid)
	var y := pos.y + 8 * sc
	# curva atual (filete amarelo à esquerda)
	draw_rect(Rect2(pos.x + pad, y, 3 * sc, 16 * sc), Color("#e3bd1c"))
	_text(_bold, Vector2(pos.x + pad + 9 * sc, y), section.to_upper(), (14.0 if touch else 13.0) * sc, Color(1, 1, 1, 0.9))
	y += 22 * sc
	if invalid:
		var pulse := 0.79 + 0.21 * sin(_time * 5.2)
		var ir := Rect2(pos.x + pad, y, w - 2 * pad, 18 * sc)
		_box(ir, Color(1.0, 75 / 255.0, 92 / 255.0, 0.22 * pulse), Color(1.0, 75 / 255.0, 92 / 255.0, 0.7 * pulse), 1.0, 3.0 * sc)
		_text(_bold, Vector2(ir.position.x, ir.position.y + 2 * sc), "VOLTA INVÁLIDA · 4 RODAS FORA", 10.5 * sc, Color(1.0, 128 / 255.0, 139 / 255.0, pulse), HORIZONTAL_ALIGNMENT_CENTER, ir.size.x)
		y += 22 * sc
	var dim := Color(1, 1, 1, 0.55)
	var row := func(ry: float, label: String, value: String, vs: float, vc: Color, f: Font) -> void:
		_text(_bold, Vector2(pos.x + pad, ry + vs * 0.42 - 6 * sc), label, 12 * sc, dim)
		var vw := _text_w(f, value, vs)
		_text(f, Vector2(pos.x + w - pad - vw, ry), value, vs, vc)
	row.call(y, "BEST", LapTimer.format_time(t.best.time if t.best else -1.0), 20 * sc, PURPLE, _font)
	y += 23 * sc
	var cur_c := WHITE if t.valid else RED
	row.call(y, "CURRENT", LapTimer.format_time(t.current), (32.0 if touch else 30.0) * sc, cur_c, _bold)
	if not t.valid and t.current >= 0.0:
		var cw := _text_w(_bold, LapTimer.format_time(t.current), 30 * sc)
		draw_line(Vector2(pos.x + w - pad - cw, y + 18 * sc), Vector2(pos.x + w - pad, y + 18 * sc), RED, 2 * sc)
	y += 39 * sc
	# setores: 3 caixas
	var bw := (w - 2 * pad - 6 * sc) / 3.0
	for i in 3:
		var r := Rect2(pos.x + pad + i * (bw + 3 * sc), y, bw, (24.0 if touch else 22.0) * sc)
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
	y += (30.0 if touch else 28.0) * sc
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


# ------------------------------------------------------------------ minimapa (RADAR dinâmico / CIRCUITO)

func _build_corners() -> void:
	_corners.clear()
	if track == null or track.n <= 0:
		return
	var L := track.length
	# Interlagos (comprimento ~4309 m): usa os 15 nomes oficiais refinados pelo pico de curvatura
	if absf(L - 4309.0) < 250.0 or not track.sections.is_empty():
		for def in INTERLAGOS_CORNERS:
			var target_s: float = def[2]
			var best_i := 0
			var max_curv := -1.0
			for i in track.n:
				var s_val := i * Track.STEP
				var ds := absf(s_val - target_s)
				if ds < 70.0 or ds > L - 70.0:
					var c := absf(track.curv[i])
					if c > max_curv:
						max_curv = c
						best_i = i
			_corners.append({"number": def[0], "name": def[1], "s": best_i * Track.STEP, "pos": track.P[best_i]})
	else:
		var counter := 1
		for i in track.n:
			var c := absf(track.curv[i])
			if c > 0.009:
				var prev_c := absf(track.curv[(i - 1 + track.n) % track.n])
				var next_c := absf(track.curv[(i + 1) % track.n])
				if c >= prev_c and c >= next_c:
					var s_val := i * Track.STEP
					var near_other := false
					for cr in _corners:
						if absf(float(cr.s) - s_val) < 50.0:
							near_other = true
							break
					if not near_other:
						_corners.append({"number": counter, "name": "Curva %d" % counter, "s": s_val, "pos": track.P[i]})
						counter += 1


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


func _next_corner() -> Array:
	var L := track.length
	var track_s := timer.s
	var best_c: Dictionary = {}
	var best_dist := INF
	for c in _corners:
		var ds := float(c.s) - track_s
		if ds < -L * 0.5:
			ds += L
		elif ds > L * 0.5:
			ds -= L
		if ds >= -20.0 and ds < best_dist:
			best_dist = ds
			best_c = c
	return [best_c, best_dist]


static func _clip_to_circle(p: Vector2, rc: Vector2, r: float) -> Vector2:
	var v := p - rc
	var l_sq := v.length_squared()
	if l_sq > r * r:
		return rc + v * (r / sqrt(l_sq))
	return p


static func _seg_circle_range(p0: Vector2, p1: Vector2, rc: Vector2, r: float) -> Vector2:
	var d := p1 - p0
	var a := d.length_squared()
	var f := p0 - rc
	var r_sq := r * r
	if a < 1e-6:
		return Vector2(0.0, 1.0) if f.length_squared() <= r_sq else Vector2(1.0, 0.0)
	var b := 2.0 * f.dot(d)
	var c := f.length_squared() - r_sq
	var disc := b * b - 4.0 * a * c
	if disc <= 0.0:
		return Vector2(1.0, 0.0)
	var sq := sqrt(disc)
	var inv2a := 0.5 / a
	var t0 := maxf(0.0, (-b - sq) * inv2a)
	var t1 := minf(1.0, (-b + sq) * inv2a)
	return Vector2(t0, t1)


func _draw_map(pos: Vector2, sc: float) -> void:
	var w := 186.0 * sc
	var h := 202.0 * sc
	_r_map = Rect2(pos, Vector2(w, h))
	_panel(_r_map, sc)
	_text(_bold, pos + Vector2(12 * sc, 7 * sc), "MINIMAP", 12 * sc, Color(1, 1, 1, 0.92))
	# badge RADAR / CIRCUITO no topo direito do minimap
	var badge := "RADAR" if map_mode == "dynamic" else "CIRCUITO"
	var bfs := 9.5 * sc
	var bw := _text_w(_bold, badge, bfs) + 12 * sc
	var br := Rect2(pos.x + w - 8 * sc - bw, pos.y + 6 * sc, bw, 15 * sc)
	_box(br, Color(225 / 255.0, 6 / 255.0, 0.0, 0.25), Color(225 / 255.0, 6 / 255.0, 0.0, 0.55), 1.0, 3.0 * sc)
	_text(_bold, br.position + Vector2(0, 1.5 * sc), badge, bfs, Color("#ff5e57"), HORIZONTAL_ALIGNMENT_CENTER, bw)

	if _map_draw_pts.size() != _map_pts.size() or _map_pos != pos or _map_layout_sc != sc:
		_update_map_layout(pos, sc)

	var aa := not (touch or quality_level <= 1)
	if map_mode == "dynamic":
		_draw_radar(pos, sc, aa)
		draw_arc(_radar_center, _radar_radius, 0, TAU, 36 if not aa else 48, Color(1, 1, 1, 0.16), 1.5 * sc, aa)
		draw_arc(_radar_center, _radar_radius, -PI * 0.65, -PI * 0.35, 12, ACCENT, 2.5 * sc, aa)
		var tip := _radar_center + Vector2(0, -_radar_radius - 2 * sc)
		if _radar_tip_pts.size() != 3:
			_radar_tip_pts.resize(3)
		_radar_tip_pts[0] = tip
		_radar_tip_pts[1] = tip + Vector2(-4 * sc, 6 * sc)
		_radar_tip_pts[2] = tip + Vector2(4 * sc, 6 * sc)
		draw_colored_polygon(_radar_tip_pts, ACCENT)
		var nc := _next_corner()
		var c_info: Dictionary = nc[0]
		if not c_info.is_empty():
			var dist_m := maxi(0, roundi(float(nc[1])))
			var lbl := "T%d %s • %dm" % [int(c_info.number), String(c_info.name), dist_m]
			_text(_bold, Vector2(pos.x + 6 * sc, pos.y + h - 17 * sc), lbl, 10.0 * sc, Color(0.95, 0.96, 0.98, 0.95), HORIZONTAL_ALIGNMENT_CENTER, w - 12 * sc)
	else:
		draw_polyline(_map_draw_pts, Color(0, 0, 0, 0.6), 7 * sc, aa)
		draw_polyline(_map_draw_pts, Color(235 / 255.0, 238 / 255.0, 242 / 255.0, 0.9), 3.5 * sc, aa)
		draw_line(_map_finish_draw[0], _map_finish_draw[1], Color("#e5483b"), 2.5 * sc, aa)
		var c := _map_origin + _to_map(car.pos) * sc
		draw_circle(c, 5.5 * sc, Color.BLACK)
		draw_circle(c, 4.0 * sc, car_color)


func _draw_radar(pos: Vector2, sc: float, aa: bool) -> void:
	var rc := _radar_center
	var R := _radar_radius
	var cx := rc.x
	var cy := pos.y + 25.0 * sc + 158.0 * sc * 0.72
	var dy := cy - rc.y
	var cc := Vector2(cx, cy)
	var sc_m := R / 230.0  # ~340 m visíveis à frente do carro

	# fundo circular + anéis de distância recortados analiticamente ao círculo (sem CLIP_CHILDREN_ONLY / subpass GPU)
	draw_circle(rc, R, Color("#070a13"))
	draw_circle(rc, R * 0.55, Color(13 / 255.0, 19 / 255.0, 31 / 255.0, 0.65))
	var ring_col := Color(1, 1, 1, 0.06)
	for dm: float in [50.0, 100.0, 150.0, 200.0, 250.0, 300.0]:
		var rr := dm * sc_m
		if rr + dy <= R:
			draw_arc(cc, rr, 0.0, TAU, 24, ring_col, 1.0, false)
		elif absf(rr - dy) < R:
			var s_lim := (R * R - rr * rr - dy * dy) / (2.0 * dy * rr)
			if s_lim > -1.0:
				var phi := asin(clampf(s_lim, -1.0, 1.0))
				draw_arc(cc, rr, -PI - phi, phi, 20, ring_col, 1.0, false)
	draw_line(Vector2(cx, rc.y - R), Vector2(cx, rc.y + R), Color(1, 1, 1, 0.04), 1.0)
	var half_w := sqrt(maxf(0.0, R * R - dy * dy))
	draw_line(Vector2(cx - half_w, cy), Vector2(cx + half_w, cy), Color(1, 1, 1, 0.04), 1.0)

	if track == null or track.n <= 0:
		return

	var car_pos := car.pos
	var cur_idx := clampi(car.hint, 0, track.n - 1) if car.hint >= 0 else track.li
	var cos_a := cos(-_radar_angle)
	var sin_a := sin(-_radar_angle)
	var N := track.n

	_radar_tri_pts.clear()
	_radar_tri_cols.clear()
	_radar_tri_idx.clear()
	_radar_edge_segs.clear()
	_radar_cline_segs.clear()
	_radar_kerb_w_segs.clear()
	_radar_kerb_r_segs.clear()

	for k_idx in RADAR_N:
		var offset := -RADAR_BACK + k_idx * RADAR_STEP
		var idx := posmod(cur_idx + offset, N)
		var p := track.P[idx]
		var r := track.R[idx]
		var w_l := track.wl[idx]
		var w_r := track.wr[idx]
		var dlx := p.x - r.x * w_l - car_pos.x
		var dlz := p.z - r.z * w_l - car_pos.z
		var drx := p.x + r.x * w_r - car_pos.x
		var drz := p.z + r.z * w_r - car_pos.z
		var dcx := p.x - car_pos.x
		var dcz := p.z - car_pos.z
		_radar_left[k_idx] = Vector2(cx + (dlx * cos_a - dlz * sin_a) * sc_m, cy + (dlx * sin_a + dlz * cos_a) * sc_m)
		_radar_right[k_idx] = Vector2(cx + (drx * cos_a - drz * sin_a) * sc_m, cy + (drx * sin_a + drz * cos_a) * sc_m)
		_radar_cline[k_idx] = Vector2(cx + (dcx * cos_a - dcz * sin_a) * sc_m, cy + (dcx * sin_a + dcz * cos_a) * sc_m)

	var road_col := Color("#222735")
	var r_inner_sq := (R - 1.5 * sc) * (R - 1.5 * sc)
	for k_idx in RADAR_N - 1:
		var pc0 := _radar_cline[k_idx]
		var pc1 := _radar_cline[k_idx + 1]
		var tr := _seg_circle_range(pc0, pc1, rc, R)
		if tr.x >= tr.y:
			continue
		var pl0 := _radar_left[k_idx]
		var pl1 := _radar_left[k_idx + 1]
		var pr0 := _radar_right[k_idx]
		var pr1 := _radar_right[k_idx + 1]
		var l0 := _clip_to_circle(pl0.lerp(pl1, tr.x) if tr.x > 0.0 else pl0, rc, R)
		var l1 := _clip_to_circle(pl0.lerp(pl1, tr.y) if tr.y < 1.0 else pl1, rc, R)
		var r0 := _clip_to_circle(pr0.lerp(pr1, tr.x) if tr.x > 0.0 else pr0, rc, R)
		var r1 := _clip_to_circle(pr0.lerp(pr1, tr.y) if tr.y < 1.0 else pr1, rc, R)
		var cl0 := pc0.lerp(pc1, tr.x) if tr.x > 0.0 else pc0
		var cl1 := pc0.lerp(pc1, tr.y) if tr.y < 1.0 else pc1

		var base := _radar_tri_pts.size()
		_radar_tri_pts.append(l0)
		_radar_tri_pts.append(l1)
		_radar_tri_pts.append(r1)
		_radar_tri_pts.append(r0)
		_radar_tri_cols.append(road_col)
		_radar_tri_cols.append(road_col)
		_radar_tri_cols.append(road_col)
		_radar_tri_cols.append(road_col)
		_radar_tri_idx.append(base)
		_radar_tri_idx.append(base + 1)
		_radar_tri_idx.append(base + 2)
		_radar_tri_idx.append(base)
		_radar_tri_idx.append(base + 2)
		_radar_tri_idx.append(base + 3)

		_radar_edge_segs.append(l0)
		_radar_edge_segs.append(l1)
		_radar_edge_segs.append(r0)
		_radar_edge_segs.append(r1)
		_radar_cline_segs.append(cl0)
		_radar_cline_segs.append(cl1)

		var offset := -RADAR_BACK + k_idx * RADAR_STEP
		var idx := posmod(cur_idx + offset, N)
		var is_red := (offset % 4 == 0)
		if track.kerb_l[idx] > 0.0 and (l0 - rc).length_squared() <= r_inner_sq and (l1 - rc).length_squared() <= r_inner_sq:
			if is_red:
				_radar_kerb_r_segs.append(l0)
				_radar_kerb_r_segs.append(l1)
			else:
				_radar_kerb_w_segs.append(l0)
				_radar_kerb_w_segs.append(l1)
		if track.kerb_r[idx] > 0.0 and (r0 - rc).length_squared() <= r_inner_sq and (r1 - rc).length_squared() <= r_inner_sq:
			if is_red:
				_radar_kerb_r_segs.append(r0)
				_radar_kerb_r_segs.append(r1)
			else:
				_radar_kerb_w_segs.append(r0)
				_radar_kerb_w_segs.append(r1)

	if not _radar_tri_idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _radar_tri_idx, _radar_tri_pts, _radar_tri_cols)
	if not _radar_edge_segs.is_empty():
		draw_multiline(_radar_edge_segs, Color(1, 1, 1, 0.35), 1.2 * sc, false)
	if not _radar_kerb_w_segs.is_empty():
		draw_multiline(_radar_kerb_w_segs, Color.WHITE, 2.0 * sc, false)
	if not _radar_kerb_r_segs.is_empty():
		draw_multiline(_radar_kerb_r_segs, ACCENT, 2.0 * sc, false)
	if not _radar_cline_segs.is_empty():
		draw_multiline(_radar_cline_segs, Color(235 / 255.0, 238 / 255.0, 245 / 255.0, 0.9), 2.2 * sc, aa)

	# feixe de farol + seta do carro do jogador
	_cone_pts[0] = cc
	_cone_pts[1] = cc + Vector2(-18 * sc, -44 * sc)
	_cone_pts[2] = cc + Vector2(18 * sc, -44 * sc)
	draw_colored_polygon(_cone_pts, Color(1.0, 0.92, 0.63, 0.14))
	_arrow_pts[0] = cc + Vector2(0, -8 * sc)
	_arrow_pts[1] = cc + Vector2(-6 * sc, 7 * sc)
	_arrow_pts[2] = cc + Vector2(0, 4 * sc)
	_arrow_pts[3] = cc + Vector2(6 * sc, 7 * sc)
	draw_colored_polygon(_arrow_pts, Color("#22c55e"))
	for ai in 4:
		_arrow_outline_pts[ai] = _arrow_pts[ai]
	_arrow_outline_pts[4] = _arrow_pts[0]
	draw_polyline(_arrow_outline_pts, Color.BLACK, 1.5 * sc, aa)
	draw_circle(cc, 2.0 * sc, Color.WHITE)


# ------------------------------------------------------------------ barra horizontal (padrão, estilo foto)

func _draw_hbar(pos: Vector2, kb: float) -> void:
	_ensure_styleboxes()
	var w := HBAR_W * kb
	var pad_x := 14.0 * kb
	var pad_top := 8.0 * kb
	var pad_bot := 9.0 * kb
	var rpm_h := 10.0 * kb
	var main_h := 56.0 * kb
	var invalid := timer.current >= 0.0 and not timer.valid
	var show_delta := invalid or not is_nan(timer.delta)
	var delta_h := (24.0 * kb) if show_delta else 0.0
	var h := pad_top + rpm_h + 7.0 * kb + main_h + (7.0 * kb + delta_h if show_delta else 0.0) + pad_bot

	var r := Rect2(pos, Vector2(w, h))
	_hbar_sb.shadow_size = 0 if (touch or quality_level <= 1) else roundi(10 * kb)
	draw_style_box(_hbar_sb, r)
	draw_rect(Rect2(pos, Vector2(w, 2.0 * kb)), ACCENT)

	var inner_x := pos.x + pad_x
	var inner_w := w - 2.0 * pad_x
	var y := pos.y + pad_top

	# 1. Barra de RPM no topo
	var lim: float = car.p.limiter
	var red_frac := maxf(0.0, lim - 1000.0) / MAX_RPM
	var rpm_r := Rect2(inner_x, y, inner_w, rpm_h)
	_box(rpm_r, Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0.0, 3.0 * kb)
	var red_x := inner_x + inner_w * red_frac
	draw_rect(Rect2(red_x, y, inner_w * (1.0 - red_frac), rpm_h), Color(216 / 255.0, 52 / 255.0, 60 / 255.0, 0.42))
	draw_line(Vector2(red_x, y), Vector2(red_x, y + rpm_h), Color(1.0, 90 / 255.0, 85 / 255.0, 0.85), 2.0 * kb)
	var frac := clampf(car.rpm / MAX_RPM, 0.0, 1.0)
	var shift_now := car.rpm > lim - 300.0
	var blink := int(_time / 0.07) % 2 == 0
	var rpm_c := Color("#f4f6f8")
	if shift_now:
		rpm_c = Color("#3d8bff") if blink else Color("#1a3d78")
	elif car.rpm > lim - 700.0:
		rpm_c = Color("#ff5148")
	if frac > 0.005:
		_box(Rect2(inner_x, y, inner_w * frac, rpm_h), rpm_c, Color(0, 0, 0, 0), 0.0, 3.0 * kb)

	y += rpm_h + 7.0 * kb

	# 2. Linha principal: Pneus/Aids | Pedais + Marcha/KMH | Força G
	var row_cy := y + main_h * 0.5
	var x := inner_x

	# 2a. Pneus (4 pneus + contorno) + ABS/TC/AUT empilhados
	var car_cx := x + 23.0 * kb
	var body_top := row_cy - 26.0 * kb
	var body := Rect2(car_cx - 10.0 * kb, body_top, 20.0 * kb, 52.0 * kb)
	draw_style_box(_tyres_body_sb, body)
	draw_rect(Rect2(car_cx - 8.5 * kb, body_top + 25.0 * kb, 17.0 * kb, 1.5 * kb), Color(1, 1, 1, 0.18))
	for i in 4:
		var col := i % 2
		var rw := i / 2
		var tr := Rect2(car_cx + (-16.0 * kb if col == 0 else 5.0 * kb), body_top + 2.0 * kb + rw * 31.0 * kb, 11.0 * kb, 19.0 * kb)
		var tsb := _tyre_sbs[i]
		tsb.bg_color = tyre_color(_tyre_use[i])
		draw_style_box(tsb, tr)

	var abs_now := false
	for wh in car.wheels:
		abs_now = abs_now or wh.abs_active
	var aids := [["ABS", car.assists.abs, abs_now and car.assists.abs], ["TC", car.assists.tc, car.tc_cut > 0.05 and car.assists.tc], ["AUT", car.assists.auto, false]]
	var ax := x + 50.0 * kb
	var ay := row_cy - 24.5 * kb
	var aw := 30.0 * kb
	var ah := 15.0 * kb
	for a in aids:
		var ar := Rect2(ax, ay, aw, ah)
		var on: bool = a[1]
		var active: bool = a[2]
		var col := Color(1, 1, 1, 0.88 if on else 0.30)
		if active:
			_box(ar, Color("#ffb020"), Color("#ffb020"), 1.0, 2.0 * kb)
			col = Color("#0b0d11")
		else:
			_box(ar, Color(0, 0, 0, 0), Color(1, 1, 1, 0.24 if on else 0.08), 1.0, 2.0 * kb)
		_text(_bold, ar.position + Vector2(0, 2.0 * kb), a[0], 10.0 * kb, col, HORIZONTAL_ALIGNMENT_CENTER, aw)
		ay += ah + 2.5 * kb

	x += 90.0 * kb
	draw_line(Vector2(x, y + 2 * kb), Vector2(x, y + main_h - 2 * kb), Color(1, 1, 1, 0.14), 1.0)
	x += 12.0 * kb

	# 2b. Pedais empilhados (ACEL / FREIO)
	var ped_w := 112.0 * kb
	var ped_lbl_w := 32.0 * kb
	var peds := [["ACEL", throttle, GREEN], ["FREIO", brake, Color("#ff4b5c")]]
	var py := row_cy - 14.0 * kb
	for pd in peds:
		_text(_bold, Vector2(x, py), pd[0], 10.0 * kb, pd[2])
		var trk := Rect2(x + ped_lbl_w, py + 1.0 * kb, ped_w - ped_lbl_w, 9.5 * kb)
		_box(trk, Color(1, 1, 1, 0.10), Color(0, 0, 0, 0), 0.0, 3.0 * kb)
		var v := clampf(float(pd[1]), 0.0, 1.0)
		if v > 0.01:
			_box(Rect2(trk.position, Vector2(trk.size.x * v, trk.size.y)), pd[2], Color(0, 0, 0, 0), 0.0, 3.0 * kb)
		py += 18.0 * kb

	x += ped_w + 12.0 * kb

	# 2c. Marcha e Velocidade (caixa central)
	var g_box_w := inner_x + inner_w - x - 110.0 * kb
	var g_box := Rect2(x, row_cy - 26.0 * kb, g_box_w, 52.0 * kb)
	_box(g_box, Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.12), 1.0, 5.0 * kb)
	var gear := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	var gear_w := 42.0 * kb
	_text(_bold, g_box.position + Vector2(6 * kb, 3.0 * kb), gear, 44.0 * kb, Color("#6aa8ff") if shift_now else WHITE, HORIZONTAL_ALIGNMENT_CENTER, gear_w)
	var sep_x := g_box.position.x + gear_w + 10.0 * kb
	draw_line(Vector2(sep_x, g_box.position.y + 7 * kb), Vector2(sep_x, g_box.end.y - 7 * kb), Color(1, 1, 1, 0.2), 1.0)
	var kmh := str(roundi(absf(car.fwd_speed()) * 3.6))
	var kmh_lbl := "KM/H"
	var kmh_w := _text_w(_bold, kmh, 36.0 * kb)
	var unit_w := _text_w(_bold, kmh_lbl, 12.0 * kb)
	var readout_r := g_box.end.x - 10.0 * kb
	var unit_x := readout_r - unit_w
	var spd_x := unit_x - 5.0 * kb - kmh_w
	_text(_bold, Vector2(spd_x, g_box.position.y + 7.0 * kb), kmh, 36.0 * kb, WHITE)
	_text(_bold, Vector2(unit_x, g_box.position.y + 24.0 * kb), kmh_lbl, 12.0 * kb, Color(1, 1, 1, 0.72))

	# 2d. Radar de Força G
	var gx_start := inner_x + inner_w - 98.0 * kb
	draw_line(Vector2(gx_start, y + 2 * kb), Vector2(gx_start, y + main_h - 2 * kb), Color(1, 1, 1, 0.14), 1.0)
	var gc := Vector2(gx_start + 34.0 * kb, row_cy)
	var gr := 24.0 * kb
	var aa := not (touch or quality_level <= 1)
	draw_circle(gc, gr, Color(0, 0, 0, 0.36))
	draw_arc(gc, gr, 0, TAU, 24 if not aa else 32, Color(1, 1, 1, 0.22), 1.0, aa)
	draw_arc(gc, gr * (19.0 / 28.0), 0, TAU, 18 if not aa else 28, Color(1, 1, 1, 0.14), 0.8, aa)
	draw_arc(gc, gr * (9.5 / 28.0), 0, TAU, 14 if not aa else 20, Color(1, 1, 1, 0.12), 0.8, aa)
	draw_line(gc - Vector2(gr, 0), gc + Vector2(gr, 0), Color(1, 1, 1, 0.16), 0.8)
	draw_line(gc - Vector2(0, gr), gc + Vector2(0, gr), Color(1, 1, 1, 0.16), 0.8)

	var sc_g := gr / 24.0
	if _g_trail.size() >= 2:
		_g_trail_pts.resize(_g_trail.size())
		for ti in _g_trail.size():
			_g_trail_pts[ti] = gc + _g_trail[ti] * sc_g
		draw_polyline(_g_trail_pts, Color(1.0, 204 / 255.0, 48 / 255.0, 0.45), 1.5 * kb, aa)
	var g_pt := gc + Vector2(clampf(car.g_lat / 2.8 * 24.0, -24.0, 24.0), clampf(-car.g_long / 2.8 * 24.0, -24.0, 24.0)) * sc_g
	draw_line(gc, g_pt, Color(1, 1, 1, 0.45), 1.2 * kb, aa)
	var g_tot := Vector2(car.g_lat, car.g_long).length()
	var g_col := Color("#ff4b5c") if g_tot > 1.85 else (Color("#f2cc30") if g_tot > 1.1 else GREEN)
	draw_circle(g_pt, 3.8 * kb, Color.WHITE)
	draw_circle(g_pt, 2.8 * kb, g_col)

	var gm_x := gc.x + gr + 7.0 * kb
	_text(_bold, Vector2(gm_x, row_cy - 12.0 * kb), "FORÇA G", 8.0 * kb, Color(1, 1, 1, 0.55))
	_text(_bold, Vector2(gm_x, row_cy - 1.0 * kb), "%.1fG" % g_tot, 14.0 * kb, WHITE)

	# 3. Faixa inferior: VOLTA INVÁLIDA e/ou barra de Delta ao vivo
	if show_delta:
		y += main_h + 7.0 * kb
		draw_line(Vector2(inner_x, y - 3.5 * kb), Vector2(inner_x + inner_w, y - 3.5 * kb), Color(1, 1, 1, 0.1), 1.0)
		var dx := inner_x
		var dw := inner_w
		if invalid:
			var pulse := 0.79 + 0.21 * sin(_time * 5.2)
			var inv_w := 98.0 * kb
			_box(Rect2(dx, y + 2 * kb, inv_w, 18.0 * kb), Color(1.0, 75 / 255.0, 92 / 255.0, 0.25 * pulse), Color(1.0, 75 / 255.0, 92 / 255.0, 0.78 * pulse), 1.0, 3.0 * kb)
			_text(_bold, Vector2(dx, y + 4.5 * kb), "VOLTA INVÁLIDA", 10.5 * kb, Color(1.0, 128 / 255.0, 139 / 255.0, pulse), HORIZONTAL_ALIGNMENT_CENTER, inv_w)
			dx += inv_w + 8.0 * kb
			dw -= inv_w + 8.0 * kb
		if not is_nan(timer.delta) and dw > 30.0 * kb:
			var d := timer.delta
			var dr := Rect2(dx, y + 2 * kb, dw, 18.0 * kb)
			_box(dr, Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0.0, 3.0 * kb)
			var half := dr.size.x * 0.5
			var bw2 := minf(1.0, absf(d)) * half
			var dcx := dr.position.x + half
			var alpha := 0.55 if invalid else 0.85
			if d < 0.0:
				draw_rect(Rect2(dcx - bw2, dr.position.y, bw2, dr.size.y), Color(GREEN, alpha))
			else:
				draw_rect(Rect2(dcx, dr.position.y, bw2, dr.size.y), Color(1.0, 70 / 255.0, 60 / 255.0, alpha))
			draw_line(Vector2(dcx, dr.position.y), Vector2(dcx, dr.end.y), Color(1, 1, 1, 0.38), 1.0)
			var ds := ("−" if d < 0.0 else "+") + "%.2f" % absf(d)
			_text(_bold, Vector2(dr.position.x, dr.position.y + 1.5 * kb), ds, 13.5 * kb, WHITE, HORIZONTAL_ALIGNMENT_CENTER, dr.size.x)


# ------------------------------------------------------------------ mostrador LMU circular + pneus

func _polar(c: Vector2, deg: float, r: float) -> Vector2:
	return c + Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r


func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, width: float) -> void:
	if absf(a1 - a0) < 0.01:
		return
	draw_arc(c, r, deg_to_rad(a0), deg_to_rad(a1), maxi(8, int(absf(a1 - a0) / 3.0)), col, width, not (touch or quality_level <= 1))


func _draw_cluster(pos: Vector2, k: float) -> void:
	var tyres_w := 86.0 * k
	_draw_tyres(Vector2(pos.x, pos.y + GAUGE * k - 18 * k), k, tyres_w)
	_draw_gauge(Vector2(pos.x + tyres_w + 8 * k, pos.y), k)


func _draw_gauge(pos: Vector2, k: float) -> void:
	var u := GAUGE * k / 200.0
	var c := pos + Vector2(100, 100) * u
	var lim: float = car.p.limiter
	draw_circle(c + Vector2(0, 4 * u), 99 * u, Color(0, 0, 0, 0.3))
	draw_circle(c, 99 * u, NAVY)
	_arc(c, 99 * u, 0, 360, Color(1, 1, 1, 0.1), 1.2 * u)
	draw_circle(c, 64 * u, Color(1, 1, 1, 0.025))
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
	_arc(c, PR * u, 160, 230, Color(1, 1, 1, 0.08), 5 * u)
	_arc(c, PR * u, 20, -50, Color(1, 1, 1, 0.08), 5 * u)
	_arc(c, PR * u, 160, 160 + 70 * brake, Color("#ff4b5c"), 5 * u)
	_arc(c, PR * u, 20, 20 - 70 * throttle, GREEN, 5 * u)
	var gear := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	_text(_bold, pos + Vector2(0, 34 * k), gear, 96 * k, Color("#6aa8ff") if shift_now else WHITE, HORIZONTAL_ALIGNMENT_CENTER, GAUGE * k)
	var kmh := str(roundi(absf(car.fwd_speed()) * 3.6))
	_text(_bold, pos + Vector2(0, 132 * k), kmh, 40 * k, WHITE, HORIZONTAL_ALIGNMENT_CENTER, GAUGE * k)
	_text(_bold, pos + Vector2(0, 174 * k), "KM/H", 15 * k, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER, GAUGE * k)


## bloco dos 4 pneus (cor pelo slip) com ABS / TC / AUT embaixo; pos = canto inferior esquerdo
func _draw_tyres(bottom_left: Vector2, k: float, w: float) -> void:
	_ensure_styleboxes()
	var h := 110.0 * k
	var r := Rect2(bottom_left - Vector2(0, h), Vector2(w, h))
	draw_style_box(_tyres_panel_sb, r)
	var cx := r.position.x + w / 2.0
	var top := r.position.y + 10 * k
	var body := Rect2(cx - 13 * k, top, 26 * k, 74 * k)
	draw_style_box(_tyres_body_sb, body)
	draw_rect(Rect2(cx - 11 * k, top + 36 * k, 22 * k, 2 * k), Color(1, 1, 1, 0.18))
	for i in 4:
		var col := i % 2
		var row := i / 2
		var tr := Rect2(cx + (-20.5 * k if col == 0 else 5.5 * k), top + 4 * k + row * 48 * k, 15 * k, 26 * k)
		var tsb := _tyre_sbs[i]
		tsb.bg_color = tyre_color(_tyre_use[i])
		draw_style_box(tsb, tr)
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
	if radius <= 0.0 or ((touch or quality_level <= 1) and radius <= 3.5):
		if bg.a > 0.0:
			draw_rect(r, bg)
		if bw > 0.0 and border.a > 0.0:
			draw_rect(r, border, false, bw)
		return
	_ensure_styleboxes()
	_box_sb.bg_color = bg
	_box_sb.border_color = border
	_box_sb.set_border_width_all(maxi(1, roundi(bw)) if bw > 0.0 else 0)
	_box_sb.set_corner_radius_all(roundi(radius))
	draw_style_box(_box_sb, r)


func _draw_dash(pos: Vector2, ks: float) -> void:
	var lim: float = car.p.limiter
	var t := timer
	var body := Rect2(pos, Vector2(640, 300) * ks)
	_box(body, Color("#121316"), Color("#000000"), 1 * ks, 14 * ks)
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
	_text(_bold, Vector2(ix, iy + 4 * ks), "ARCADE 2×" if arcade else "TIME ATTACK", 15 * ks, Color("#ffb020") if arcade else Color("#ff3b3b"))
	var brand := "P O R S C H E"
	var bw := _text_w(_bold, brand, 24 * ks)
	draw_string_outline(_bold, Vector2(ix + iw / 2.0 - bw / 2.0, iy + _bold.get_ascent(roundi(24 * ks))), brand, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24 * ks), 1, Color("#8a9099"))
	var dry_w := _text_w(_bold, "SECO", 14 * ks) + 16 * ks
	var dry := Rect2(Vector2(ix + iw - dry_w, iy + 2 * ks), Vector2(dry_w, 22 * ks))
	_box(dry, Color(0, 0, 0, 0), Color("#3fd18a"), 1.5 * ks, 3 * ks)
	_text(_bold, dry.position + Vector2(8 * ks, 2 * ks), "SECO", 14 * ks, Color("#3fd18a"))
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
	var tab := [["RPM", str(roundi(car.rpm / 10.0) * 10)], ["Freio diant.", "%d%%" % roundi(car.p.brake_bias * 100)],
		["Lat. g", "%.2f" % absf(car.g_lat)], ["Long. g", "%.2f" % car.g_long], ["Volta", str(t.laps.size() + 1)]]
	for i in tab.size():
		var rr := Rect2(Vector2(cx[1], rows_y[1] + i * 24 * ks), Vector2(108 * ks, 22 * ks))
		draw_rect(rr, Color("#2a2d33"))
		_text(_font, rr.position + Vector2(6 * ks, 3 * ks), tab[i][0], 13 * ks, gray)
		_text(_bold, Vector2(rr.end.x - 6 * ks - _text_w(_bold, tab[i][1], 13 * ks), rr.position.y + 3 * ks), tab[i][1], 13 * ks, WHITE)
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
	var mode_txt := "arcade %.1f×" % car.grip_scale if arcade else "simulador"
	lines.append("%d fps  %s  %s  %s" % [fps, quality, mode_txt, "piloto automático" if autopilot else ""])
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



