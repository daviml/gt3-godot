extends Control

## Auto-Updater do GT3 Time Attack
## Verifica se há novidades e baixa o patch leve (2~4 MB).
## Apresenta o visual de automobilismo e telemetria da LoadingScreen desde o primeiro quadro!

const CURRENT_CLIENT_VERSION: int = 6
const VERSION_URL: String = "https://raw.githubusercontent.com/daviml/gt3-godot/main/version.json"
const PATCH_PCK_PATH: String = "user://patch.pck"
const LOCAL_VERSION_PATH: String = "user://installed_version.json"
const GARAGEM_SCENE: String = "res://scenes/garagem.tscn"

const HTTP_HEADERS: PackedStringArray = [
	"User-Agent: GT3TimeAttack-Mobile/1.0",
	"Accept: application/json, */*"
]

const TIPS := [
	"Dica: Pressione C (ou Y no controle) para alternar entre as câmeras.",
	"Dica: Use R para reiniciar a volta imediatamente no grid de largada.",
	"Dica: Ajuste qualidade gráfica e assistências (ABS/TC) no menu de pausa.",
	"Dica: Reduza a marcha antes da tangência para aproveitar o freio-motor.",
	"Dica: Pressione T durante a corrida para visualizar a telemetria em tempo real.",
	"Dica: Conecte um controle via Bluetooth ou USB para acelerar e esterçar com precisão analógica.",
]

const TRACK_OUTLINE := [
	Vector2(-0.2626, 0.1883), Vector2(-0.2553, 0.218), Vector2(-0.248, 0.2477), Vector2(-0.2401, 0.2772),
	Vector2(-0.2324, 0.3068), Vector2(-0.2251, 0.3365), Vector2(-0.2179, 0.3662), Vector2(-0.2099, 0.3957),
	Vector2(-0.2017, 0.4251), Vector2(-0.1933, 0.4545), Vector2(-0.1792, 0.4816), Vector2(-0.155, 0.5),
	Vector2(-0.1257, 0.4963), Vector2(-0.1048, 0.4737), Vector2(-0.0779, 0.4593), Vector2(-0.049, 0.4638),
	Vector2(-0.0196, 0.4741), Vector2(0.0094, 0.4837), Vector2(0.0397, 0.4876), Vector2(0.0701, 0.4845),
	Vector2(0.0985, 0.4736), Vector2(0.1234, 0.4559), Vector2(0.1433, 0.4329), Vector2(0.1582, 0.4062),
	Vector2(0.1685, 0.3774), Vector2(0.1783, 0.3485), Vector2(0.1857, 0.3188), Vector2(0.1932, 0.2893),
	Vector2(0.2012, 0.2598), Vector2(0.209, 0.2302), Vector2(0.2164, 0.2006), Vector2(0.2239, 0.171),
	Vector2(0.2315, 0.1413), Vector2(0.2392, 0.1118), Vector2(0.2471, 0.0823), Vector2(0.255, 0.0528),
	Vector2(0.2629, 0.0233), Vector2(0.2709, -0.0062), Vector2(0.2789, -0.0357), Vector2(0.2869, -0.0652),
	Vector2(0.295, -0.0947), Vector2(0.303, -0.1242), Vector2(0.311, -0.1537), Vector2(0.3187, -0.1832),
	Vector2(0.3161, -0.2136), Vector2(0.2951, -0.2349), Vector2(0.2658, -0.2439), Vector2(0.2363, -0.2512),
	Vector2(0.2057, -0.2526), Vector2(0.1755, -0.2486), Vector2(0.1466, -0.2386), Vector2(0.1193, -0.225),
	Vector2(0.0969, -0.2042), Vector2(0.0774, -0.1807), Vector2(0.059, -0.1563), Vector2(0.0427, -0.1304),
	Vector2(0.0267, -0.1044), Vector2(0.0096, -0.0792), Vector2(-0.0083, -0.0546), Vector2(-0.0264, -0.03),
	Vector2(-0.0446, -0.0054), Vector2(-0.0628, 0.0191), Vector2(-0.0819, 0.0429), Vector2(-0.1053, 0.0625),
	Vector2(-0.1334, 0.0727), Vector2(-0.1641, 0.0725), Vector2(-0.1928, 0.0625), Vector2(-0.2191, 0.0468),
	Vector2(-0.2384, 0.0235), Vector2(-0.2482, -0.0054), Vector2(-0.2549, -0.0352), Vector2(-0.2594, -0.0654),
	Vector2(-0.2615, -0.0961), Vector2(-0.2476, -0.1219), Vector2(-0.2176, -0.1238), Vector2(-0.1921, -0.1071),
	Vector2(-0.1637, -0.0962), Vector2(-0.1365, -0.1082), Vector2(-0.1248, -0.1362), Vector2(-0.1315, -0.1658),
	Vector2(-0.1512, -0.1891), Vector2(-0.1731, -0.2102), Vector2(-0.1935, -0.2329), Vector2(-0.2102, -0.2584),
	Vector2(-0.2198, -0.2873), Vector2(-0.2266, -0.3174), Vector2(-0.2134, -0.3434), Vector2(-0.1844, -0.3443),
	Vector2(-0.1639, -0.3211), Vector2(-0.1439, -0.2982), Vector2(-0.1235, -0.2755), Vector2(-0.0992, -0.2573),
	Vector2(-0.0701, -0.2482), Vector2(-0.0397, -0.2492), Vector2(-0.0109, -0.259), Vector2(0.0144, -0.2757),
	Vector2(0.0351, -0.2983), Vector2(0.0517, -0.324), Vector2(0.0678, -0.3499), Vector2(0.084, -0.3759),
	Vector2(0.0996, -0.4022), Vector2(0.1105, -0.4309), Vector2(0.1058, -0.4597), Vector2(0.0806, -0.4775),
	Vector2(0.0525, -0.4895), Vector2(0.0231, -0.4979), Vector2(-0.0072, -0.5), Vector2(-0.0374, -0.4953),
	Vector2(-0.0673, -0.4898), Vector2(-0.0967, -0.4821), Vector2(-0.1251, -0.4709), Vector2(-0.1528, -0.4583),
	Vector2(-0.1795, -0.4437), Vector2(-0.2047, -0.4266), Vector2(-0.2275, -0.4062), Vector2(-0.2447, -0.381),
	Vector2(-0.2577, -0.3533), Vector2(-0.2681, -0.3246), Vector2(-0.2767, -0.2953), Vector2(-0.2827, -0.2654),
	Vector2(-0.2883, -0.2353), Vector2(-0.2937, -0.2053), Vector2(-0.3002, -0.1754), Vector2(-0.3077, -0.1458),
	Vector2(-0.3142, -0.116), Vector2(-0.3181, -0.0857), Vector2(-0.3187, -0.0551), Vector2(-0.3155, -0.0248),
	Vector2(-0.3093, 0.0051), Vector2(-0.302, 0.0349), Vector2(-0.2948, 0.0645), Vector2(-0.2873, 0.0942),
	Vector2(-0.2795, 0.1237), Vector2(-0.2717, 0.1532), Vector2(-0.264, 0.1828),
]

class _BackdropGraphic extends Control:
	var accent := Color("#3b82f6")
	var watermark_top := "INTERLAGOS"
	var watermark_bottom := "GT3"
	var bold_font: Font
	var time := 0.0

	func _draw() -> void:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0:
			return

		var step := clampf(s.y / 8.5, 90.0, 140.0)
		var grid_col := Color(1, 1, 1, 0.028)
		var tick_col := Color(1, 1, 1, 0.065)
		var cols := int(ceil(s.x / step)) + 1
		var rows := int(ceil(s.y / step)) + 1
		var ox := fmod(s.x, step) * 0.5
		var oy := fmod(s.y, step) * 0.5
		for c in cols:
			var x := ox + c * step
			draw_line(Vector2(x, 0.0), Vector2(x, s.y), grid_col, 1.0)
		for r in rows:
			var y := oy + r * step
			draw_line(Vector2(0.0, y), Vector2(s.x, y), grid_col, 1.0)
		for c in cols:
			var x := ox + c * step
			for r in rows:
				var y := oy + r * step
				draw_line(Vector2(x - 5.0, y), Vector2(x + 5.0, y), tick_col, 1.0)
				draw_line(Vector2(x, y - 5.0), Vector2(x, y + 5.0), tick_col, 1.0)

		var slant := s.y * 0.28
		var stripe_w := clampf(s.x * 0.032, 34.0, 68.0)
		var left_offsets := [0.0, stripe_w * 1.45, stripe_w * 2.65]
		var left_alphas := [0.22, 0.11, 0.05]
		for i in left_offsets.size():
			var x0: float = left_offsets[i]
			var poly := PackedVector2Array([
				Vector2(x0 - slant * 0.3, 0.0),
				Vector2(x0 + stripe_w - slant * 0.3, 0.0),
				Vector2(x0 + stripe_w - slant, s.y),
				Vector2(x0 - slant, s.y),
			])
			draw_colored_polygon(poly, Color(accent.r, accent.g, accent.b, left_alphas[i]))

		var right_offsets := [0.0, stripe_w * 1.45, stripe_w * 2.65]
		var right_alphas := [0.22, 0.11, 0.05]
		for i in right_offsets.size():
			var rx0: float = s.x - right_offsets[i]
			var rpoly := PackedVector2Array([
				Vector2(rx0 + slant, 0.0),
				Vector2(rx0 - stripe_w + slant, 0.0),
				Vector2(rx0 - stripe_w + slant * 0.3, s.y),
				Vector2(rx0 + slant * 0.3, s.y),
			])
			draw_colored_polygon(rpoly, Color(accent.r, accent.g, accent.b, right_alphas[i]))

		if bold_font:
			var top_fs := clampi(roundi(s.y * 0.18), 96, 220)
			draw_string(
				bold_font,
				Vector2(s.x * 0.04, top_fs * 0.92),
				watermark_top,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				top_fs,
				Color(1, 1, 1, 0.032)
			)
			var bot_fs := clampi(roundi(s.y * 0.24), 120, 280)
			draw_string(
				bold_font,
				Vector2(0.0, s.y - s.y * 0.04),
				watermark_bottom,
				HORIZONTAL_ALIGNMENT_RIGHT,
				s.x * 0.96,
				bot_fs,
				Color(accent.r, accent.g, accent.b, 0.055)
			)

		if s.x >= 1500.0:
			var ghost_scale := s.y * 0.62
			var ghost_center := Vector2(s.x * 0.11, s.y * 0.56)
			var ghost_pts := PackedVector2Array()
			ghost_pts.resize(TRACK_OUTLINE.size() + 1)
			for i in TRACK_OUTLINE.size():
				ghost_pts[i] = ghost_center + TRACK_OUTLINE[i] * ghost_scale
			ghost_pts[TRACK_OUTLINE.size()] = ghost_pts[0]
			draw_polyline(ghost_pts, Color(accent.r, accent.g, accent.b, 0.08), 5.0, true)

class _VisualWidget extends Control:
	var accent := Color("#3b82f6")
	var progress := 0.0
	var time := 0.0
	var bold_font: Font
	var _loop_pts := PackedVector2Array()
	var _last_size := Vector2.ZERO

	func _ensure_points() -> void:
		if _loop_pts.size() == TRACK_OUTLINE.size() + 1 and _last_size == size:
			return
		_last_size = size
		var pad := 26.0
		var usable := Vector2(maxf(40.0, size.x - pad * 2.0), maxf(40.0, size.y - pad * 2.0))
		var sc := minf(usable.x / 0.66, usable.y / 1.02)
		var center := size * 0.5
		_loop_pts.resize(TRACK_OUTLINE.size() + 1)
		for i in TRACK_OUTLINE.size():
			_loop_pts[i] = center + TRACK_OUTLINE[i] * sc
		_loop_pts[TRACK_OUTLINE.size()] = _loop_pts[0]

	func _draw() -> void:
		if size.x <= 10.0 or size.y <= 10.0:
			return
		_ensure_points()
		if _loop_pts.size() < 4:
			return
		draw_polyline(_loop_pts, Color(accent.r, accent.g, accent.b, 0.14), 14.0, true)
		draw_polyline(_loop_pts, Color(1, 1, 1, 0.16), 5.0, true)

		var n_pts := _loop_pts.size()
		var t_clamped := clampf(progress, 0.0, 1.0)
		var f_idx := t_clamped * float(n_pts - 1)
		var whole := mini(int(floor(f_idx)), n_pts - 2)
		var frac := f_idx - float(whole)
		var tip := _loop_pts[whole].lerp(_loop_pts[whole + 1], frac)

		if whole >= 1 or frac > 0.01:
			var prog_pts := PackedVector2Array()
			for i in range(whole + 1):
				prog_pts.append(_loop_pts[i])
			prog_pts.append(tip)
			if prog_pts.size() >= 2:
				draw_polyline(prog_pts, Color(accent.r, accent.g, accent.b, 0.45), 11.0, true)
				draw_polyline(prog_pts, accent, 5.5, true)

		var pulse := 1.0 + 0.25 * sin(time * 6.0)
		draw_circle(tip, 11.0 * pulse, Color(accent.r, accent.g, accent.b, 0.28))
		draw_circle(tip, 6.5, Color.WHITE)
		draw_circle(tip, 4.0, accent)

		var p0 := _loop_pts[0]
		var tangent := (_loop_pts[1] - _loop_pts[0]).normalized()
		var perp := Vector2(-tangent.y, tangent.x)
		draw_line(p0 - perp * 11.0, p0 + perp * 11.0, Color("#ef4444"), 3.5, true)


var http_version: HTTPRequest
var http_download: HTTPRequest

var status_label: Label
var details_label: Label
var progress_bar: ProgressBar
var is_downloading: bool = false
var is_loading_game: bool = false
var next_version_to_save: int = CURRENT_CLIENT_VERSION
var _initial_car_id: String = ""
var _initial_car_glb: String = ""
var _garagem_done: bool = false
var _car_done: bool = false
var _garagem_packed: PackedScene = null

var _car_info: Dictionary = {}
var _car_data: Dictionary = {}
var _accent := Color("#3b82f6")
var _accent_ui := Color("#60a5fa")
var _anim_time := 0.0
var _font: Font
var _bold_font: Font
var _mono_font: Font

var _layer: CanvasLayer
var _backdrop: _BackdropGraphic
var _visual_widget: _VisualWidget
var _panel: PanelContainer
var _main_hbox: HBoxContainer
var _right_panel: PanelContainer
var _header_bar: HBoxContainer
var _footer_bar: HBoxContainer
var _top_brand_lbl: Label
var _top_meta_lbl: Label
var _bot_left_lbl: Label
var _bot_right_lbl: Label
var _badge_lbl: Label
var _title_lbl: Label
var _car_lbl: Label
var _spec_value_lbls: Array[Label] = []
var _spec_title_lbls: Array[Label] = []
var _pct_lbl: Label
var _tip_lbl: Label
var _accent_bar: ColorRect
var _right_title_lbl: Label
var _right_sub_lbl: Label
var _sector_lbls: Array[Label] = []


func _ready() -> void:
	_initial_car_id = Game.car_id
	if _initial_car_id.is_empty():
		_initial_car_id = "porsche-992-gt3r"
	_car_info = Game.get_car_info(_initial_car_id)
	_car_data = Game.get_car_data(_initial_car_id)

	_font = _sys_font(500)
	_bold_font = _sys_font(700)
	_mono_font = SystemFont.new()
	(_mono_font as SystemFont).font_names = PackedStringArray(["Consolas", "Droid Sans Mono", "monospace"])

	_setup_ui()
	get_viewport().size_changed.connect(_fit)
	_fit()

	_cleanup_stale_or_incompatible_patches()
	_setup_network()

	if OS.has_feature("editor"):
		_finish_and_enter_game()
		return

	status_label.text = "Verificando atualizações..."
	_check_for_patches()


func _sys_font(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "sans-serif"])
	f.font_weight = weight
	return f


func _make_radial_glow(col: Color, alpha: float) -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, alpha))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	gt.gradient = g
	return gt


func _setup_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_accent = Color(_car_info.get("color", "#3b82f6"))
	_accent_ui = _accent.lightened(0.28) if _accent.get_luminance() < 0.25 else _accent

	var bg := ColorRect.new()
	bg.color = Color(0.028, 0.036, 0.052, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(bg)

	var glow_center := TextureRect.new()
	glow_center.texture = _make_radial_glow(_accent_ui, 0.24)
	glow_center.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow_center.stretch_mode = TextureRect.STRETCH_SCALE
	glow_center.set_anchors_preset(PRESET_FULL_RECT)
	glow_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(glow_center)

	var glow_corner := TextureRect.new()
	glow_corner.texture = _make_radial_glow(_accent, 0.20)
	glow_corner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow_corner.stretch_mode = TextureRect.STRETCH_SCALE
	glow_corner.anchor_left = 0.45
	glow_corner.anchor_top = 0.25
	glow_corner.anchor_right = 1.15
	glow_corner.anchor_bottom = 1.25
	glow_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(glow_corner)

	_backdrop = _BackdropGraphic.new()
	_backdrop.set_anchors_preset(PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.accent = _accent_ui
	_backdrop.bold_font = _bold_font
	_backdrop.watermark_top = "INTERLAGOS"
	_backdrop.watermark_bottom = String(_car_info.get("short", "GT3")).to_upper()
	_layer.add_child(_backdrop)

	_accent_bar = ColorRect.new()
	_accent_bar.color = _accent_ui
	_accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	_accent_bar.offset_bottom = 6
	_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_accent_bar)

	# Barra superior
	_header_bar = HBoxContainer.new()
	_header_bar.set_anchors_preset(PRESET_TOP_WIDE)
	_header_bar.offset_left = 48
	_header_bar.offset_right = -48
	_header_bar.offset_top = 24
	_header_bar.offset_bottom = 64
	_header_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_header_bar)

	_top_brand_lbl = _make_label("GT3 TIME ATTACK", 20, Color(1, 1, 1, 0.85), _bold_font)
	_top_brand_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_bar.add_child(_top_brand_lbl)

	_top_meta_lbl = _make_label(
		"AUTÓDROMO JOSÉ CARLOS PACE  ·  4.309 M",
		18,
		Color("#94a3b8"),
		_font
	)
	_top_meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header_bar.add_child(_top_meta_lbl)

	# Barra inferior
	_footer_bar = HBoxContainer.new()
	_footer_bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_footer_bar.offset_left = 48
	_footer_bar.offset_right = -48
	_footer_bar.offset_top = -54
	_footer_bar.offset_bottom = -20
	_footer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_footer_bar)

	_bot_left_lbl = _make_label(
		"SÃO PAULO, BRASIL  ·  15 CURVAS",
		16,
		Color(1, 1, 1, 0.45),
		_font
	)
	_bot_left_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_bar.add_child(_bot_left_lbl)

	_bot_right_lbl = _make_label("INICIALIZANDO SISTEMA", 16, Color(_accent_ui.r, _accent_ui.g, _accent_ui.b, 0.85), _bold_font)
	_bot_right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer_bar.add_child(_bot_right_lbl)

	# Painel central
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(1320, 540)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.062, 0.075, 0.102, 0.90)
	panel_sb.border_color = Color(_accent_ui.r, _accent_ui.g, _accent_ui.b, 0.30)
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(20)
	panel_sb.shadow_color = Color(0, 0, 0, 0.55)
	panel_sb.shadow_size = 28
	panel_sb.shadow_offset = Vector2(0, 12)
	panel_sb.content_margin_left = 48
	panel_sb.content_margin_right = 44
	panel_sb.content_margin_top = 42
	panel_sb.content_margin_bottom = 40
	_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_panel)

	_main_hbox = HBoxContainer.new()
	_main_hbox.add_theme_constant_override("separation", 40)
	_panel.add_child(_main_hbox)

	# Coluna esquerda
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 14)
	_main_hbox.add_child(left_vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	left_vbox.add_child(header_row)

	var badge_panel := PanelContainer.new()
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = Color(_accent_ui.r, _accent_ui.g, _accent_ui.b, 0.18)
	badge_sb.border_color = Color(_accent_ui.r, _accent_ui.g, _accent_ui.b, 0.55)
	badge_sb.set_border_width_all(1)
	badge_sb.set_corner_radius_all(6)
	badge_sb.content_margin_left = 12
	badge_sb.content_margin_right = 12
	badge_sb.content_margin_top = 5
	badge_sb.content_margin_bottom = 5
	badge_panel.add_theme_stylebox_override("panel", badge_sb)
	header_row.add_child(badge_panel)

	_badge_lbl = _make_label("INICIALIZAÇÃO", 16, _accent_ui, _bold_font)
	badge_panel.add_child(_badge_lbl)

	_title_lbl = _make_label("AUTÓDROMO DE INTERLAGOS", 24, Color("#cbd5e1"), _bold_font)
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(_title_lbl)

	_car_lbl = _make_label(
		String(_car_info.get("name", _initial_car_id)).to_upper(),
		56,
		Color.WHITE,
		_bold_font
	)
	_car_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(_car_lbl)

	# Fichas técnicas do carro
	var specs_row := HBoxContainer.new()
	specs_row.add_theme_constant_override("separation", 12)
	left_vbox.add_child(specs_row)
	_spec_title_lbls.clear()
	_spec_value_lbls.clear()
	for spec in _get_car_spec_items():
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(1, 1, 1, 0.045)
		card_sb.border_color = Color(1, 1, 1, 0.10)
		card_sb.set_border_width_all(1)
		card_sb.set_corner_radius_all(10)
		card_sb.content_margin_left = 16
		card_sb.content_margin_right = 16
		card_sb.content_margin_top = 12
		card_sb.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", card_sb)
		specs_row.add_child(card)

		var svbox := VBoxContainer.new()
		svbox.add_theme_constant_override("separation", 3)
		card.add_child(svbox)

		var stitle := _make_label(spec[0], 13, Color("#94a3b8"), _bold_font)
		var sval := _make_label(spec[1], 22, Color("#f8fafc"), _bold_font)
		svbox.add_child(stitle)
		svbox.add_child(sval)
		_spec_title_lbls.append(stitle)
		_spec_value_lbls.append(sval)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 14)
	left_vbox.add_child(spacer)

	# Barra de progresso
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 28)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.09)
	bar_bg.border_color = Color(1, 1, 1, 0.08)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(14)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = _accent_ui
	bar_fill.set_corner_radius_all(14)
	progress_bar.add_theme_stylebox_override("background", bar_bg)
	progress_bar.add_theme_stylebox_override("fill", bar_fill)
	left_vbox.add_child(progress_bar)

	# Linha de status e porcentagem
	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left_vbox.add_child(status_row)

	status_label = _make_label("Iniciando...", 24, Color("#e2e8f0"), _font)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_row.add_child(status_label)

	_pct_lbl = _make_label("0%", 34, _accent_ui, _mono_font)
	_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_row.add_child(_pct_lbl)

	details_label = _make_label("", 17, Color("#94a3b8"), _font)
	details_label.visible = false
	left_vbox.add_child(details_label)

	# Dicas oficiais
	var tip_panel := PanelContainer.new()
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	tip_sb.border_color = Color(1, 1, 1, 0.07)
	tip_sb.set_border_width_all(1)
	tip_sb.set_corner_radius_all(10)
	tip_sb.content_margin_left = 18
	tip_sb.content_margin_right = 18
	tip_sb.content_margin_top = 12
	tip_sb.content_margin_bottom = 12
	tip_panel.add_theme_stylebox_override("panel", tip_sb)
	left_vbox.add_child(tip_panel)

	_tip_lbl = _make_label(TIPS[randi() % TIPS.size()], 19, Color("#94a3b8"), _font)
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_panel.add_child(_tip_lbl)

	# Coluna direita: mapa vivo de Interlagos
	_right_panel = PanelContainer.new()
	_right_panel.custom_minimum_size = Vector2(390, 0)
	var right_sb := StyleBoxFlat.new()
	right_sb.bg_color = Color(0.032, 0.042, 0.060, 0.86)
	right_sb.border_color = Color(_accent_ui.r, _accent_ui.g, _accent_ui.b, 0.22)
	right_sb.set_border_width_all(1)
	right_sb.set_corner_radius_all(14)
	right_sb.content_margin_left = 22
	right_sb.content_margin_right = 22
	right_sb.content_margin_top = 20
	right_sb.content_margin_bottom = 20
	_right_panel.add_theme_stylebox_override("panel", right_sb)
	_main_hbox.add_child(_right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	_right_panel.add_child(right_vbox)

	_right_title_lbl = _make_label("TRAÇADO OFICIAL", 16, _accent_ui, _bold_font)
	_right_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(_right_title_lbl)

	_right_sub_lbl = _make_label("4.309 M · 15 CURVAS", 15, Color("#94a3b8"), _font)
	_right_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(_right_sub_lbl)

	_visual_widget = _VisualWidget.new()
	_visual_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_visual_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_visual_widget.custom_minimum_size = Vector2(300, 300)
	_visual_widget.accent = _accent_ui
	_visual_widget.bold_font = _bold_font
	right_vbox.add_child(_visual_widget)

	var sectors_row := HBoxContainer.new()
	sectors_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sectors_row.add_theme_constant_override("separation", 10)
	right_vbox.add_child(sectors_row)

	_sector_lbls.clear()
	for tag in ["SETOR 1", "SETOR 2", "SETOR 3"]:
		var sl := _make_label(tag, 14, Color(1, 1, 1, 0.35), _bold_font)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sectors_row.add_child(sl)
		_sector_lbls.append(sl)


func _make_label(txt: String, font_size: int, col: Color, f: Font) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	if f:
		l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _get_car_spec_items() -> Array:
	if _car_info.is_empty() or _car_data.is_empty():
		return [
			["MOTOR", "TRASEIRO"],
			["POTÊNCIA", "565 CV"],
			["PESO", "1250 KG"],
			["CÂMBIO", "6 MARCHAS"],
		]
	var p: Dictionary = _car_data.get("params", {})
	var eng: Dictionary = p.get("engine", {})
	var torque: Array = eng.get("torque", [])
	var cv := 0.0
	for pt in torque:
		cv = maxf(cv, float(pt[0]) * float(pt[1]) * TAU / 60.0 / 735.5)
	var gears: Array = p.get("gearbox", {}).get("ratios", [])
	var layout := String(_car_info.get("layout", "")).to_upper()
	if layout == "":
		layout = "GT3"
	return [
		["MOTOR", layout],
		["POTÊNCIA", "%d CV" % (roundi(cv / 5.0) * 5)],
		["PESO", "%d KG" % int(p.get("mass", 0))],
		["CÂMBIO", "%d MARCHAS" % gears.size()],
	]


func _fit() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var sc := clampf(minf(vp.x / 1920.0, vp.y / 1080.0), 0.55, 1.35)
	var show_right := vp.x >= 980.0
	_right_panel.visible = show_right
	var target_w := clampf(vp.x * 0.72, 680.0, 1460.0) if show_right else clampf(vp.x - 64.0, 480.0, 960.0)
	var target_h := clampf(vp.y * 0.54, 380.0, 620.0)
	_panel.custom_minimum_size = Vector2(target_w, target_h)
	_right_panel.custom_minimum_size.x = clampf(target_w * 0.30, 280.0, 430.0)
	_main_hbox.add_theme_constant_override("separation", roundi(36.0 * sc))

	_top_brand_lbl.add_theme_font_size_override("font_size", roundi(20.0 * sc))
	_top_meta_lbl.add_theme_font_size_override("font_size", roundi(18.0 * sc))
	_bot_left_lbl.add_theme_font_size_override("font_size", roundi(16.0 * sc))
	_bot_right_lbl.add_theme_font_size_override("font_size", roundi(16.0 * sc))

	_badge_lbl.add_theme_font_size_override("font_size", roundi(16.0 * sc))
	_title_lbl.add_theme_font_size_override("font_size", roundi(24.0 * sc))
	_car_lbl.add_theme_font_size_override("font_size", roundi(56.0 * sc))
	for l in _spec_title_lbls:
		l.add_theme_font_size_override("font_size", roundi(13.0 * sc))
	for l in _spec_value_lbls:
		l.add_theme_font_size_override("font_size", roundi(22.0 * sc))
	progress_bar.custom_minimum_size.y = roundi(28.0 * sc)
	status_label.add_theme_font_size_override("font_size", roundi(24.0 * sc))
	_pct_lbl.add_theme_font_size_override("font_size", roundi(34.0 * sc))
	_tip_lbl.add_theme_font_size_override("font_size", roundi(19.0 * sc))
	_right_title_lbl.add_theme_font_size_override("font_size", roundi(16.0 * sc))
	_right_sub_lbl.add_theme_font_size_override("font_size", roundi(15.0 * sc))
	for l in _sector_lbls:
		l.add_theme_font_size_override("font_size", roundi(14.0 * sc))


func _setup_network() -> void:
	http_version = HTTPRequest.new()
	http_version.timeout = 1.5
	add_child(http_version)

	http_download = HTTPRequest.new()
	http_download.timeout = 30.0
	http_download.use_threads = true
	add_child(http_download)


func _get_saved_version_on_disk() -> int:
	if not FileAccess.file_exists(LOCAL_VERSION_PATH):
		return 0
	var f = FileAccess.open(LOCAL_VERSION_PATH, FileAccess.READ)
	if not f:
		return 0
	var json = JSON.parse_string(f.get_as_text())
	if json and json is Dictionary and json.has("version"):
		return int(json["version"])
	return 0


func _get_local_version() -> int:
	var saved = _get_saved_version_on_disk()
	return maxi(saved, CURRENT_CLIENT_VERSION)


func _save_local_version(ver: int) -> void:
	var f = FileAccess.open(LOCAL_VERSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": ver}))


func _is_pck_compatible(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	if f.get_length() < 20:
		f.close()
		return false
	var magic = f.get_32()
	if magic != 0x43504447:
		f.close()
		return false
	var _pck_format = f.get_32()
	var major = f.get_32()
	var minor = f.get_32()
	f.close()
	var engine_info = Engine.get_version_info()
	var cur_major = int(engine_info.get("major", 0))
	var cur_minor = int(engine_info.get("minor", 0))
	if major != cur_major or minor != cur_minor:
		print("[Updater] PCK gerado para Godot %d.%d, mas engine atual é %d.%d! Incompatível." % [major, minor, cur_major, cur_minor])
		return false
	return true


func _cleanup_stale_or_incompatible_patches() -> void:
	var saved_ver = _get_saved_version_on_disk()
	if CURRENT_CLIENT_VERSION >= saved_ver:
		if FileAccess.file_exists(PATCH_PCK_PATH):
			print("[Updater] Novo APK instalado (v%d >= v%d). Removendo patch antigo..." % [CURRENT_CLIENT_VERSION, saved_ver])
			DirAccess.remove_absolute(PATCH_PCK_PATH)
		_save_local_version(CURRENT_CLIENT_VERSION)
	elif FileAccess.file_exists(PATCH_PCK_PATH):
		if not _is_pck_compatible(PATCH_PCK_PATH):
			print("[Updater] Patch existente é incompatível com o Godot atual. Removendo...")
			DirAccess.remove_absolute(PATCH_PCK_PATH)
			_save_local_version(CURRENT_CLIENT_VERSION)


func _check_for_patches() -> void:
	http_version.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[Updater] Sem internet ou servidor inacessível (%d). Entrando no jogo..." % response_code)
			_finish_and_enter_game()
			return

		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data or not data is Dictionary:
			_finish_and_enter_game()
			return

		var remote_ver: int = int(data.get("version", 1))
		var patch_url: String = data.get("patch_url", "")
		var local_ver: int = _get_local_version()

		if remote_ver > local_ver and not patch_url.is_empty():
			next_version_to_save = remote_ver
			status_label.text = "Nova atualização encontrada (v%d)!" % remote_ver
			details_label.visible = true
			_badge_lbl.text = "ATUALIZAÇÃO"
			_download_patch(patch_url)
		else:
			status_label.text = "Tudo atualizado!"
			_finish_and_enter_game()
	, CONNECT_ONE_SHOT)

	var err = http_version.request(VERSION_URL, HTTP_HEADERS)
	if err != OK:
		_finish_and_enter_game()


func _download_patch(url: String) -> void:
	is_downloading = true
	var temp_patch = PATCH_PCK_PATH + ".tmp"
	http_download.download_file = temp_patch

	http_download.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading = false

		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 302):
			if not _is_pck_compatible(temp_patch):
				print("[Updater] Patch baixado é incompatível com a versão do engine Godot! Descartando.")
				DirAccess.remove_absolute(temp_patch)
				status_label.text = "Atualização incompatível com este app."
				await get_tree().create_timer(1.0).timeout
			else:
				if FileAccess.file_exists(PATCH_PCK_PATH):
					DirAccess.remove_absolute(PATCH_PCK_PATH)
				DirAccess.rename_absolute(temp_patch, PATCH_PCK_PATH)
				_save_local_version(next_version_to_save)
				status_label.text = "Atualização instalada com sucesso!"
				progress_bar.value = 100.0
				await get_tree().create_timer(0.4).timeout
		else:
			print("[Updater] Falha ao baixar patch (%d). Usando versão instalada." % response_code)

		_finish_and_enter_game()
	, CONNECT_ONE_SHOT)

	var err = http_download.request(url, HTTP_HEADERS)
	if err != OK:
		_finish_and_enter_game()


func _process(delta: float) -> void:
	_anim_time += delta
	if _backdrop:
		_backdrop.time = _anim_time
		_backdrop.queue_redraw()
	if _visual_widget:
		_visual_widget.time = _anim_time
		_visual_widget.progress = progress_bar.value / 100.0
		_visual_widget.queue_redraw()

	if _pct_lbl:
		_pct_lbl.text = "%d%%" % roundi(progress_bar.value)

	if _sector_lbls.size() == 3:
		var thresholds: Array[float] = [25.0, 55.0, 85.0]
		for i in 3:
			var active: bool = progress_bar.value >= thresholds[i]
			_sector_lbls[i].add_theme_color_override(
				"font_color",
				_accent_ui if active else Color(1, 1, 1, 0.32)
			)

	if _bot_right_lbl:
		if progress_bar.value >= 99.5:
			_bot_right_lbl.text = "PRONTO"
		else:
			var dots := ".".repeat(int(_anim_time * 2.5) % 4)
			_bot_right_lbl.text = "CARREGANDO RECURSOS" + dots

	if is_downloading and is_instance_valid(http_download):
		var downloaded: int = http_download.get_downloaded_bytes()
		var total: int = http_download.get_body_size()
		if total > 0:
			var pct: float = (float(downloaded) / float(total)) * 100.0
			progress_bar.value = pct
			var down_mb: float = float(downloaded) / (1024.0 * 1024.0)
			var total_mb: float = float(total) / (1024.0 * 1024.0)
			details_label.text = "Baixando patch: %.1f MB / %.1f MB (%.0f%%)" % [down_mb, total_mb, pct]
			details_label.visible = true
		return

	if is_loading_game:
		var gar_pct: float = 100.0 if _garagem_done else 0.0
		var car_pct: float = 100.0 if _car_done else 0.0

		if not _garagem_done:
			var g_prog: Array = []
			var g_status := ResourceLoader.load_threaded_get_status(GARAGEM_SCENE, g_prog)
			if g_prog.size() > 0:
				gar_pct = clampf(float(g_prog[0]) * 100.0, 0.0, 100.0)
			match g_status:
				ResourceLoader.THREAD_LOAD_LOADED:
					_garagem_packed = ResourceLoader.load_threaded_get(GARAGEM_SCENE) as PackedScene
					_garagem_done = true
					gar_pct = 100.0
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					print("[Updater] Falha no carregamento assíncrono da garagem (%d). Fallback direto." % g_status)
					_garagem_done = true
					gar_pct = 100.0

		if not _car_done:
			var c_prog: Array = []
			var c_status := ResourceLoader.load_threaded_get_status(_initial_car_glb, c_prog)
			if c_prog.size() > 0:
				car_pct = clampf(float(c_prog[0]) * 100.0, 0.0, 100.0)
			match c_status:
				ResourceLoader.THREAD_LOAD_LOADED:
					var car_scene := ResourceLoader.load_threaded_get(_initial_car_glb) as PackedScene
					Game.cache_car_scene(_initial_car_id, car_scene)
					_car_done = true
					car_pct = 100.0
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					print("[Updater] Falha ao pré-carregar carro inicial (%d): %s" % [c_status, _initial_car_glb])
					_car_done = true
					car_pct = 100.0

		var combined_pct: float = gar_pct * 0.2 + car_pct * 0.8
		progress_bar.value = maxf(progress_bar.value, minf(combined_pct, 100.0 if (_garagem_done and _car_done) else 99.0))

		if _garagem_done and _car_done:
			progress_bar.value = 100.0
			is_loading_game = false
			if _garagem_packed:
				get_tree().change_scene_to_packed.call_deferred(_garagem_packed)
			else:
				get_tree().change_scene_to_file.call_deferred(GARAGEM_SCENE)


func _load_existing_patch() -> void:
	if FileAccess.file_exists(PATCH_PCK_PATH):
		if not _is_pck_compatible(PATCH_PCK_PATH):
			print("[Updater] Patch incompatível ignorado e removido.")
			DirAccess.remove_absolute(PATCH_PCK_PATH)
			return
		var ok = ProjectSettings.load_resource_pack(PATCH_PCK_PATH)
		print("[Updater] patch.pck carregado com sucesso: ", ok)
		if not ok:
			DirAccess.remove_absolute(PATCH_PCK_PATH)


func _finish_and_enter_game() -> void:
	if is_loading_game:
		return
	is_loading_game = true

	_load_existing_patch()

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car=") or a.begins_with("--shot=") or a == "--auto":
			is_loading_game = false
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return

	_initial_car_id = Game.car_id
	if _initial_car_id.is_empty():
		_initial_car_id = "porsche-992-gt3r"
	_initial_car_glb = Game.get_car_glb_path(_initial_car_id)
	var car_info := Game.get_car_info(_initial_car_id)
	var car_name := String(car_info.get("name", _initial_car_id))

	status_label.text = "Carregando estúdio e garagem..."
	progress_bar.value = 5.0
	details_label.text = "Pré-carregando: %s" % car_name
	details_label.visible = true

	_garagem_done = false
	_garagem_packed = null
	var err = ResourceLoader.load_threaded_request(GARAGEM_SCENE, "", true)
	if err != OK:
		print("[Updater] Falha ao iniciar carregamento assíncrono da garagem (%d). Fallback direto." % err)
		_garagem_done = true

	if _initial_car_glb.is_empty() or Game.get_cached_car_scene(_initial_car_id) != null:
		_car_done = true
	else:
		_car_done = false
		var car_err = ResourceLoader.load_threaded_request(_initial_car_glb, "PackedScene", true)
		if car_err != OK:
			print("[Updater] Falha ao iniciar pré-carga do carro (%d): %s" % [car_err, _initial_car_glb])
			_car_done = true

	if _garagem_done and _car_done:
		is_loading_game = false
		get_tree().change_scene_to_file.call_deferred(GARAGEM_SCENE)
