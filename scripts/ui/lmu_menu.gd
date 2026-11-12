# Componente único reutilizável estilo Le Mans Ultimate (LMU) para Garagem 3D e Menu de Pausa.
# Contextos: Context.GARAGE (centro transparente na aba Carros para exibir o estúdio 3D ao vivo)
# e Context.PAUSE (menu completo na pista com Continuar, Reiniciar Volta, Garagem 3D e Sair).
class_name LmuMenu
extends Control

enum Context { GARAGE, PAUSE }

signal resumed
signal garage_requested
signal quit_requested
signal drive_requested
signal restart_requested
signal car_selected(car_id: String)
signal nick_changed(nick: String)
signal mode_changed(mode: String)
signal quality_changed(name: String)
signal volume_changed(v: float)
signal assist_changed(key: String, on: bool)
signal touch_mode_changed(mode: String)
signal hide_touch_changed(hidden: bool)
signal hud_gauge_changed(style: String)
signal recenter_tilt

const VIEWS := ["home", "cars", "settings", "records", "help"]
const SETTINGS_TABS := ["controls", "graphics", "assists", "audio", "driver"]
const SETTINGS_TAB_LABELS := {
	"controls": "CONTROLES",
	"graphics": "GRÁFICOS",
	"assists": "ASSISTÊNCIAS",
	"audio": "ÁUDIO",
	"driver": "PILOTO",
}
const QUALITIES := ["Mínimo", "Leve", "Médio", "Extremo"]
const QUALITY_NOTES := {
	"Mínimo": "Máximo FPS (PC fraco/celular): resolução <=720p, sem sombras, materiais e árvores leves.",
	"Leve": "Ideal para celular ou PC modesto: 60 FPS estáveis, escala 0.75x, sombra curta e sem glow.",
	"Médio": "Resolução nativa completa, sombras em 2 cortes, reflexos e SSAO.",
	"Extremo": "Para GPUs dedicadas: SSAO, SSIL, SSR reflexivo e sombras em 4 cortes.",
}
const TOUCH_MODES := ["padrao", "fly", "inclinar", "legacy"]
const TOUCH_MODE_NAMES := {
	"padrao": "Padrão",
	"fly": "Fly-by-wire",
	"inclinar": "Inclinar",
	"legacy": "Legacy",
}
const TOUCH_MODE_NOTES := {
	"padrao": "Analógico suave à esquerda + pedais graduais de acelerador e freio por altura à direita.",
	"fly": "Analógico à esquerda + barra única multifunção: cima acelera, baixo freia.",
	"inclinar": "Vire o celular como volante usando o acelerômetro + botão de recalibrar + pedais.",
	"legacy": "Botões digitais clássicos ◀ ▶ à esquerda e pedais liga/desliga à direita.",
}
const GAUGE_STYLES := ["barra", "circular"]
const GAUGE_NAMES := {
	"barra": "Barra Horizontal (Padrão)",
	"circular": "Circular Clássico",
}
const LAYOUT_LABELS := {
	"dianteiro": "MOTOR DIANTEIRO",
	"central": "MOTOR CENTRAL",
	"traseiro": "MOTOR TRASEIRO",
}


class _Backdrop extends Control:
	var accent := LmuTheme.ACCENT_RED

	func _draw() -> void:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0:
			return
		# Base escura LMU com leve contraste azulado no quadrante direito
		var base_tl := Color(0.020, 0.024, 0.036, 0.96)
		var base_tr := Color(0.038, 0.048, 0.072, 0.95)
		var base_br := Color(0.020, 0.026, 0.042, 0.96)
		var base_bl := Color(0.018, 0.020, 0.030, 0.97)
		draw_polygon(
			PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
			PackedColorArray([base_tl, base_tr, base_br, base_bl])
		)

		# Faixa diagonal vermelha característica LMU na esquerda (gradiente suave vermelho -> escuro)
		var w := clampf(s.x * 0.46, 300.0, 860.0)
		var w_bot := w * 0.62
		var c_left_top := Color(accent.r * 0.88, accent.g * 0.10, accent.b * 0.10, 0.88)
		var c_left_bot := Color(accent.r * 0.46, 0.02, 0.03, 0.72)
		var c_edge_top := Color(accent.r * 0.35, 0.02, 0.03, 0.22)
		var c_edge_bot := Color(accent.r * 0.22, 0.01, 0.02, 0.12)
		draw_polygon(
			PackedVector2Array([Vector2.ZERO, Vector2(w, 0.0), Vector2(w_bot, s.y), Vector2(0.0, s.y)]),
			PackedColorArray([c_left_top, c_edge_top, c_edge_bot, c_left_bot])
		)

		# Realce luminoso sutil próximo à borda diagonal esquerda
		var c_stripe_l := Color(accent.r, 0.06, 0.04, 0.48)
		var c_stripe_r := Color(accent.r, 0.02, 0.02, 0.0)
		draw_polygon(
			PackedVector2Array([Vector2.ZERO, Vector2(w * 0.42, 0.0), Vector2(w_bot * 0.36, s.y), Vector2(0.0, s.y)]),
			PackedColorArray([c_stripe_l, c_stripe_r, c_stripe_r, Color(accent.r * 0.65, 0.03, 0.03, 0.28)])
		)

		# Chevron angular vermelho no canto inferior direito
		var ch := clampf(minf(s.x * 0.12, s.y * 0.36), 90.0, 210.0)
		draw_polygon(
			PackedVector2Array([Vector2(s.x, s.y - ch), s, Vector2(s.x - ch, s.y)]),
			PackedColorArray([
				Color(accent.r, 0.04, 0.02, 0.72),
				Color(accent.r * 0.82, 0.02, 0.02, 0.92),
				Color(accent.r * 0.68, 0.02, 0.02, 0.72),
			])
		)


var context: int = Context.GARAGE
var active_view := "home"
var active_settings_tab := "controls"
var category_filter := "todos"
var search_query := ""
var records_mode := ""

var cars: Array = []
var current_car_id := "porsche-992-gt3r"
var current_nick := "Piloto"
var current_mode := "sim"
var current_quality := "Extremo"
var current_volume := 0.6
var current_assists := {"abs": true, "tc": true, "auto": false}
var current_touch_mode := "padrao"
var current_hide_touch := false
var current_hud_gauge := "barra"
var is_touch_device := false
var live_fps := 0
var shared_records_by_mode := {}

var layout_profile := {}

var _backdrop: _Backdrop
var _root_vbox: VBoxContainer
var _header_panel: PanelContainer
var _header_hbox: HBoxContainer
var _header_center: Control
var _header_search_edit: LineEdit
var _driver_name_lbl: Label
var _driver_dr_lbl: Label
var _driver_sr_lbl: Label
var _mode_pill_btn: Button
var _body_holder: Control
var _view_root: Control

# Referências dinâmicas atualizadas sem reconstruir tudo
var _cars_grid_nodes := {}
var _car_hero_brand: Label
var _car_hero_name: Label
var _car_hero_engine: Label
var _car_spec_vals := {}
var _car_pb_time_lbl: Label
var _car_pb_sub_lbl: Label
var _drive_btn: Button
var _settings_search_edit: LineEdit
var _settings_rows: Array[Dictionary] = []
var _settings_empty_lbl: Label
var _fps_badge_lbl: Label
var _fps_explain_lbl: Label
var _fps_hist: Array[int] = []
var _driver_tab_rating_lbl: Label
var _recenter_row: Control


func _init(ctx := Context.GARAGE) -> void:
	context = ctx
	cars = Game.get_cars_list()
	current_car_id = Game.car_id
	current_mode = Game.mode
	records_mode = current_mode
	current_nick = Records.load_nick()
	current_quality = Game.get_quality_name()
	current_volume = float(Game.get_setting("audio", "volume", 0.6))
	current_assists = {
		"abs": bool(Game.get_setting("assistencias", "abs", true)),
		"tc": bool(Game.get_setting("assistencias", "tc", true)),
		"auto": bool(Game.get_setting("assistencias", "auto", false)),
	}
	current_touch_mode = String(Game.get_setting("controles", "modo_toque", "padrao"))
	if not (current_touch_mode in TOUCH_MODES):
		current_touch_mode = "padrao"
	current_hide_touch = Game.is_hide_touch_controls()
	current_hud_gauge = String(Game.get_setting("hud", "mostrador", "barra"))
	if not (current_hud_gauge in GAUGE_STYLES):
		current_hud_gauge = "barra"
	is_touch_device = Game.is_touch_device()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()
	get_viewport().size_changed.connect(relayout)
	relayout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and _root_vbox != null and is_inside_tree():
		var vp := get_viewport().get_visible_rect().size
		if vp.x > 0.0 and vp.y > 0.0 and (not is_equal_approx(size.x, vp.x) or not is_equal_approx(size.y, vp.y)):
			relayout()


## Calcula Driver Rating (DR) e Safety Rating (SR) com base nas voltas salvas.
static func compute_driver_rating(mode := "") -> Dictionary:
	var recs := Records.load_all(mode)
	if recs.is_empty():
		return {"dr": "ROOKIE", "sr": "B1", "best": -1.0}
	var best := INF
	for r in recs:
		if r is Dictionary and r.has("time"):
			best = minf(best, float(r.time))
	if best == INF:
		return {"dr": "ROOKIE", "sr": "B1", "best": -1.0}
	if best < 93.0:
		return {"dr": "PRO (S)", "sr": "S+", "best": best}
	if best < 95.0:
		return {"dr": "A+", "sr": "S", "best": best}
	if best < 98.0:
		return {"dr": "A", "sr": "A", "best": best}
	if best < 102.0:
		return {"dr": "B3", "sr": "B1", "best": best}
	return {"dr": "C2", "sr": "B2", "best": best}


static func _norm(txt: String) -> String:
	var s := txt.to_lower().strip_edges()
	var pairs := [
		["á", "a"], ["à", "a"], ["ã", "a"], ["â", "a"],
		["é", "e"], ["ê", "e"], ["í", "i"], ["ó", "o"],
		["ô", "o"], ["õ", "o"], ["ú", "u"], ["ç", "c"],
	]
	for p in pairs:
		s = s.replace(p[0], p[1])
	return s


func current_car() -> Dictionary:
	var info := Game.get_car_info(current_car_id)
	if info.is_empty() and not cars.is_empty():
		return cars[0]
	return info


func _car_pb(car_id: String, mode: String) -> Dictionary:
	var recs := Records.load_all(mode)
	var clean_nick := current_nick.strip_edges().to_lower()
	var best_rec := {}
	for r in recs:
		if r is Dictionary and String(r.get("carId", "")) == car_id:
			var r_nick := String(r.get("nick", "")).strip_edges().to_lower()
			if clean_nick == "" or r_nick == clean_nick:
				if best_rec.is_empty() or float(r.get("time", INF)) < float(best_rec.get("time", INF)):
					best_rec = r
	return best_rec


func configure(state: Dictionary) -> void:
	if state.has("nick"):
		current_nick = String(state.nick).strip_edges()
		if current_nick == "":
			current_nick = "Piloto"
	if state.has("car_id"):
		current_car_id = String(state.car_id)
	if state.has("mode"):
		current_mode = String(state.mode) if String(state.mode) in Game.MODES else "sim"
		records_mode = current_mode
	if state.has("quality"):
		current_quality = String(state.quality)
	if state.has("volume"):
		current_volume = float(state.volume)
	if state.has("assists") and state.assists is Dictionary:
		current_assists = state.assists.duplicate()
	if state.has("touch_mode"):
		current_touch_mode = String(state.touch_mode)
	if state.has("hide_touch"):
		current_hide_touch = bool(state.hide_touch)
	if state.has("hud_gauge"):
		current_hud_gauge = String(state.hud_gauge)
	if state.has("is_touch"):
		is_touch_device = bool(state.is_touch)
	if state.has("view") and String(state.view) in VIEWS:
		active_view = String(state.view)
	if state.has("settings_tab") and String(state.settings_tab) in SETTINGS_TABS:
		active_settings_tab = String(state.settings_tab)
	_fps_hist.clear()
	_rebuild_all()


func set_shared_records(mode: String, recs: Array) -> void:
	shared_records_by_mode[mode] = recs.duplicate()
	if active_view == "records" and records_mode == mode:
		_rebuild_view()


func set_selected_car(car_id: String, emit_sig := false) -> void:
	if car_id == "":
		return
	current_car_id = car_id
	Game.save_car(car_id)
	if active_view == "cars" and _car_hero_name != null:
		_refresh_cars_view_data()
	elif is_inside_tree():
		_rebuild_view()
	if emit_sig:
		car_selected.emit(car_id)


func switch_view(view: String) -> void:
	if not (view in VIEWS):
		view = "home"
	active_view = view
	if view == "records":
		records_mode = current_mode
	_rebuild_all()


func switch_settings_tab(tab: String) -> void:
	if not (tab in SETTINGS_TABS):
		tab = "controls"
	active_settings_tab = tab
	if active_view != "settings":
		active_view = "settings"
	_rebuild_all()


func update_fps(fps: int) -> void:
	_fps_hist.append(fps)
	if _fps_hist.size() > 8:
		_fps_hist.pop_front()
	var total := 0
	for v in _fps_hist:
		total += v
	live_fps = roundi(float(total) / maxf(1.0, float(_fps_hist.size())))
	if _fps_badge_lbl != null and is_instance_valid(_fps_badge_lbl):
		_fps_badge_lbl.text = "%d FPS" % live_fps if live_fps > 0 else "-- FPS"
		var col := LmuTheme.ACCENT_GREEN if live_fps >= 55 else (LmuTheme.ACCENT_AMBER if live_fps >= 30 else LmuTheme.ACCENT_RED_BRIGHT)
		_fps_badge_lbl.add_theme_color_override("font_color", col)
	if _fps_explain_lbl != null and is_instance_valid(_fps_explain_lbl):
		_fps_explain_lbl.text = ("%d FPS medidos na pista" % live_fps) if live_fps > 0 else "Inicie a pilotagem para medir"


func set_drive_busy(busy: bool) -> void:
	if _drive_btn != null and is_instance_valid(_drive_btn):
		_drive_btn.text = "CARREGANDO..." if busy else "PILOTAR ➔"
		_drive_btn.disabled = busy


## Recalcula o perfil responsivo a partir do tamanho de viewport informado (ou atual) e reconstrói a UI.
func relayout(custom_vp := Vector2.ZERO) -> void:
	var vp := custom_vp
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	if vp.x <= 0.0 or vp.y <= 0.0:
		var rect := get_viewport_rect()
		vp = rect.size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1920.0, 1080.0)
	layout_profile = LmuTheme.compute_layout_profile(vp, Game.is_mobile_platform() or is_touch_device)
	_sync_full_rect(vp)
	_rebuild_all()


func _sync_full_rect(vp: Vector2) -> void:
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var tree_vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	var use_full_anchors := (tree_vp.x > 0.0 and tree_vp.y > 0.0 and vp.is_equal_approx(tree_vp))
	var top_safe := float(layout_profile.get("safe_top", 0.0))
	var bot_safe := float(layout_profile.get("safe_bottom", 0.0))

	if use_full_anchors:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if _backdrop != null:
			_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_backdrop.queue_redraw()
		if _root_vbox != null:
			_root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_root_vbox.offset_top = top_safe
			_root_vbox.offset_bottom = -bot_safe
	else:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = Vector2.ZERO
		size = vp
		if _backdrop != null:
			_backdrop.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_backdrop.position = Vector2.ZERO
			_backdrop.size = vp
			_backdrop.queue_redraw()
		if _root_vbox != null:
			_root_vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_root_vbox.position = Vector2(0.0, top_safe)
			_root_vbox.size = Vector2(vp.x, maxf(0.0, vp.y - top_safe - bot_safe))


func _build_shell() -> void:
	_backdrop = _Backdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_root_vbox = VBoxContainer.new()
	_root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_vbox.add_theme_constant_override("separation", 0)
	_root_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_vbox)

	_header_panel = PanelContainer.new()
	_header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_vbox.add_child(_header_panel)

	_body_holder = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_body_holder.add_theme_constant_override(side, 0)
	_body_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_vbox.add_child(_body_holder)


func _is_transparent_studio_view() -> bool:
	return context == Context.GARAGE and active_view == "cars"


func _rebuild_all() -> void:
	if _root_vbox == null:
		return
	if layout_profile.is_empty():
		layout_profile = LmuTheme.compute_layout_profile(Vector2(1920.0, 1080.0), Game.is_mobile_platform() or is_touch_device)
	_sync_full_rect(Vector2(layout_profile.get("viewport_size", Vector2(1920.0, 1080.0))))

	var transparent_center := _is_transparent_studio_view()
	_backdrop.visible = not transparent_center
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE if transparent_center else Control.MOUSE_FILTER_STOP
	mouse_filter = Control.MOUSE_FILTER_IGNORE if transparent_center else Control.MOUSE_FILTER_STOP

	_rebuild_header()
	_rebuild_view()


func _rebuild_header() -> void:
	for c in _header_panel.get_children():
		c.queue_free()

	var lp := layout_profile
	var hh := int(lp.header_height)
	var fs := float(lp.font_scale)
	var sl := float(lp.safe_left)
	var sr := float(lp.safe_right)
	var compact := hh <= 44

	var hsb := StyleBoxFlat.new()
	hsb.bg_color = LmuTheme.BG_HEADER
	hsb.border_color = LmuTheme.BORDER_SOFT
	hsb.border_width_bottom = 1
	hsb.content_margin_left = int(14.0 + sl)
	hsb.content_margin_right = int(14.0 + sr)
	hsb.content_margin_top = 4
	hsb.content_margin_bottom = 4
	_header_panel.custom_minimum_size = Vector2(0, hh)
	_header_panel.add_theme_stylebox_override("panel", hsb)

	_header_hbox = HBoxContainer.new()
	_header_hbox.add_theme_constant_override("separation", 10 if compact else 14)
	_header_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_header_panel.add_child(_header_hbox)

	# Left: Brand + Back button
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	_header_hbox.add_child(left)

	var brand_btn := Button.new()
	LmuTheme.apply_button_styles(brand_btn, "ghost", 4, 8, 2)
	brand_btn.pressed.connect(func(): switch_view("home"))
	left.add_child(brand_btn)

	var brand_row := HBoxContainer.new()
	brand_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brand_row.add_theme_constant_override("separation", 6)
	brand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_btn.add_child(brand_row)
	var b_main := LmuTheme.make_label("GT3", roundi((20 if compact else 24) * fs), Color.WHITE, 800, true)
	brand_row.add_child(b_main)
	if lp.profile != "portrait":
		var b_sub := LmuTheme.make_label("TIME ATTACK", roundi((11 if compact else 13) * fs), LmuTheme.ACCENT_RED, 700)
		b_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		brand_row.add_child(b_sub)
	var brand_w := maxf(brand_row.get_combined_minimum_size().x + 16.0, (165.0 if lp.profile != "portrait" else 54.0) * fs)
	brand_btn.custom_minimum_size = Vector2(brand_w, hh - 10)

	if active_view != "home":
		var back := Button.new()
		var back_lbl := "◀ RACE WEEKEND" if active_view == "cars" else "◀ MENU PRINCIPAL"
		if compact or lp.profile == "portrait":
			back_lbl = "◀ MENU"
		back.text = back_lbl
		back.add_theme_font_size_override("font_size", roundi((11 if compact else 13) * fs))
		LmuTheme.apply_button_styles(back, "outline", 4, 12, 4)
		back.pressed.connect(func(): switch_view("home"))
		left.add_child(back)

	# Center: Breadcrumbs / Search / Circuit Indicator (limpo na home, centralizado nas sub-abas)
	if bool(lp.show_header_center) and active_view != "home":
		_header_center = HBoxContainer.new()
		_header_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_header_center.alignment = BoxContainer.ALIGNMENT_CENTER
		_header_hbox.add_child(_header_center)

		if active_view == "cars":
			var b1 := LmuTheme.make_label("CIRCUITO: INTERLAGOS", roundi(13 * fs), LmuTheme.TEXT_MUTED, 700)
			var sep := LmuTheme.make_label(" / ", roundi(13 * fs), LmuTheme.TEXT_DIM, 600)
			var b2 := LmuTheme.make_label("GARAGEM 3D · CARROS", roundi(13 * fs), Color.WHITE, 800)
			_header_center.add_child(b1)
			_header_center.add_child(sep)
			_header_center.add_child(b2)
		elif active_view == "settings":
			var sbox := HBoxContainer.new()
			sbox.add_theme_constant_override("separation", 6)
			_header_center.add_child(sbox)
			_header_search_edit = LineEdit.new()
			_header_search_edit.custom_minimum_size = Vector2(280, 32)
			_header_search_edit.placeholder_text = "🔍 Buscar configuração..."
			_header_search_edit.text = search_query
			_header_search_edit.add_theme_font_size_override("font_size", roundi(13 * fs))
			_header_search_edit.add_theme_stylebox_override("normal", LmuTheme.input_style(false))
			_header_search_edit.add_theme_stylebox_override("focus", LmuTheme.input_style(true))
			_header_search_edit.text_changed.connect(_on_search_changed)
			sbox.add_child(_header_search_edit)
		else:
			var dot := LmuTheme.make_label("● ", roundi(11 * fs), LmuTheme.ACCENT_GREEN, 700)
			var circ := LmuTheme.make_label("AUTÓDROMO DE INTERLAGOS · SÃO PAULO", roundi(12 * fs), LmuTheme.TEXT_SLATE, 700)
			_header_center.add_child(dot)
			_header_center.add_child(circ)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header_hbox.add_child(spacer)

	# Right: Driver Card + Mode Pill + Gear + Close (if PAUSE)
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 6 if compact else 8)
	_header_hbox.add_child(right)

	var rating := compute_driver_rating(current_mode)
	var drv_panel := PanelContainer.new()
	drv_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drv_panel.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(1, 1, 1, 0.06), LmuTheme.BORDER_SUBTLE, 4, 8 if compact else 10, 4))
	drv_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	drv_panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			switch_settings_tab("driver")
	)
	right.add_child(drv_panel)

	var drv_h := HBoxContainer.new()
	drv_h.add_theme_constant_override("separation", 6)
	drv_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drv_panel.add_child(drv_h)

	if lp.profile != "portrait":
		var av := LmuTheme.make_label("🏁", roundi((13 if compact else 15) * fs), Color.WHITE, 700)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		drv_h.add_child(av)

	var drv_v := VBoxContainer.new()
	drv_v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drv_v.add_theme_constant_override("separation", 1)
	drv_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drv_h.add_child(drv_v)

	_driver_name_lbl = LmuTheme.make_label(current_nick, roundi((10 if compact else 12) * fs), Color.WHITE, 700)
	drv_v.add_child(_driver_name_lbl)

	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 4)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drv_v.add_child(tags)

	var dr_tag := PanelContainer.new()
	dr_tag.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.TAG_DR_BG, Color.TRANSPARENT, 2, 4, 0))
	dr_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_driver_dr_lbl = LmuTheme.make_label("DR %s" % rating.dr, roundi((9 if compact else 10) * fs), Color("#0b0d10"), 800)
	dr_tag.add_child(_driver_dr_lbl)
	tags.add_child(dr_tag)

	var sr_tag := PanelContainer.new()
	sr_tag.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.TAG_SR_BG, Color.TRANSPARENT, 2, 4, 0))
	sr_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_driver_sr_lbl = LmuTheme.make_label("SR %s" % rating.sr, roundi((9 if compact else 10) * fs), Color.WHITE, 800)
	sr_tag.add_child(_driver_sr_lbl)
	tags.add_child(sr_tag)

	_mode_pill_btn = Button.new()
	_mode_pill_btn.text = "⚡ ARCADE" if current_mode == "arcade" else "🎯 SIMULADOR"
	_mode_pill_btn.add_theme_font_size_override("font_size", roundi((10 if compact else 12) * fs))
	LmuTheme.apply_button_styles(_mode_pill_btn, "arcade" if current_mode == "arcade" else "outline", 4, 8 if compact else 10, 4)
	_mode_pill_btn.pressed.connect(func():
		_set_mode("arcade" if current_mode == "sim" else "sim")
	)
	right.add_child(_mode_pill_btn)

	var gear_btn := Button.new()
	gear_btn.text = "⚙"
	gear_btn.tooltip_text = "Configurações"
	gear_btn.custom_minimum_size = Vector2(28 if compact else 34, 28 if compact else 32)
	gear_btn.add_theme_font_size_override("font_size", roundi((13 if compact else 15) * fs))
	LmuTheme.apply_button_styles(gear_btn, "active" if active_view == "settings" else "outline", 4, 6, 2)
	gear_btn.pressed.connect(func(): switch_view("settings"))
	right.add_child(gear_btn)

	if context == Context.PAUSE:
		var close_btn := Button.new()
		close_btn.text = "✕"
		close_btn.tooltip_text = "Voltar para a pista (Esc)"
		close_btn.custom_minimum_size = Vector2(28 if compact else 34, 28 if compact else 32)
		close_btn.add_theme_font_size_override("font_size", roundi((13 if compact else 15) * fs))
		LmuTheme.apply_button_styles(close_btn, "primary", 4, 6, 2)
		close_btn.pressed.connect(func(): resumed.emit())
		right.add_child(close_btn)


func _rebuild_view() -> void:
	for c in _body_holder.get_children():
		c.queue_free()
	_view_root = null
	_cars_grid_nodes.clear()
	_settings_rows.clear()
	_car_hero_brand = null
	_car_hero_name = null
	_car_hero_engine = null
	_car_spec_vals.clear()
	_car_pb_time_lbl = null
	_car_pb_sub_lbl = null
	_drive_btn = null
	_fps_badge_lbl = null
	_fps_explain_lbl = null
	_driver_tab_rating_lbl = null
	_recenter_row = null
	_settings_empty_lbl = null

	match active_view:
		"home":
			_build_home_view()
		"cars":
			_build_cars_view()
		"settings":
			_build_settings_view()
		"records":
			_build_records_view()
		"help":
			_build_help_view()
		_:
			_build_home_view()


func _make_padded_container(pad_x: float, pad_y: float, mouse_pass := false) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_left", int(pad_x + float(layout_profile.safe_left)))
	mc.add_theme_constant_override("margin_right", int(pad_x + float(layout_profile.safe_right)))
	mc.add_theme_constant_override("margin_top", int(pad_y))
	mc.add_theme_constant_override("margin_bottom", int(pad_y))
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE if mouse_pass else Control.MOUSE_FILTER_PASS
	return mc


func _make_h_divider(alpha := 0.08) -> ColorRect:
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(0, 1)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.color = Color(1.0, 1.0, 1.0, alpha)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _make_home_nav_item(title: String, text_col: Color, bar_col: Color, active_bar: bool, fs: float, is_compact: bool, sub_mode := false) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, (28 if sub_mode else 34) if is_compact else (36 if sub_mode else 46))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(0)
		sb.set_corner_radius_all(3)
		if st == "normal":
			sb.bg_color = Color(1, 1, 1, 0.04 if active_bar else 0.0)
		elif st == "hover":
			sb.bg_color = Color(bar_col.r, bar_col.g, bar_col.b, 0.14) if active_bar else Color(1, 1, 1, 0.07)
		else:
			sb.bg_color = Color(1, 1, 1, 0.12)
		btn.add_theme_stylebox_override(st, sb)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -8
	row.add_theme_constant_override("separation", 10 if is_compact else 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3 if is_compact else 4, (16 if sub_mode else 20) if is_compact else (20 if sub_mode else 28))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = bar_col if active_bar else Color(bar_col.r, bar_col.g, bar_col.b, 0.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	var fsz := roundi(((13 if sub_mode else 17) if is_compact else (16 if sub_mode else 27)) * fs)
	var lbl := LmuTheme.make_label(title, fsz, text_col, 700 if sub_mode else 800)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)

	btn.mouse_entered.connect(func():
		bar.color = bar_col
		if not sub_mode:
			lbl.add_theme_color_override("font_color", Color.WHITE)
	)
	btn.mouse_exited.connect(func():
		bar.color = bar_col if active_bar else Color(bar_col.r, bar_col.g, bar_col.b, 0.0)
		lbl.add_theme_color_override("font_color", text_col)
	)
	return btn


# ------------------------------------------------------------------ HOME VIEW

func _build_home_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_portrait: bool = (lp.profile == "portrait")
	var is_compact: bool = (lp.profile == "mobile_landscape")
	var home_pad_x := maxf(float(lp.pad_x), 56.0) if lp.profile == "desktop" else float(lp.pad_x)

	var outer := _make_padded_container(home_pad_x, float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer

	var host: Control
	if is_portrait:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(scroll)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 14)
		scroll.add_child(col)
		host = col
	else:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 16 if is_compact else 32)
		outer.add_child(row)
		host = row

	# Coluna Esquerda: Pista + Título GT3 + Lista vertical condensada estilo LMU
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size.x = float(lp.home_left_width) if not is_portrait else 0.0
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_portrait else Control.SIZE_SHRINK_BEGIN
	left_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_col.add_theme_constant_override("separation", 4 if is_compact else 8)
	host.add_child(left_col)

	var hero_tag_row := HBoxContainer.new()
	hero_tag_row.add_theme_constant_override("separation", 8)
	left_col.add_child(hero_tag_row)

	var track_pill := PanelContainer.new()
	track_pill.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color("#f59e0b", 0.16), Color("#f59e0b"), 3, 7, 2))
	track_pill.add_child(LmuTheme.make_label("PISTA", roundi((9 if is_compact else 11) * fs), Color("#fbbf24"), 800))
	hero_tag_row.add_child(track_pill)
	hero_tag_row.add_child(LmuTheme.make_label("AUTÓDROMO DE INTERLAGOS · 4.309 M", roundi((10 if is_compact else 13) * fs), LmuTheme.TEXT_SLATE, 700))

	var title_lbl := LmuTheme.make_label("GT3 TIME ATTACK", roundi((24 if is_compact else 44) * fs), Color.WHITE, 800, true)
	left_col.add_child(title_lbl)

	var nav_spacer := Control.new()
	nav_spacer.custom_minimum_size.y = 4 if is_compact else 10
	left_col.add_child(nav_spacer)

	var nav_list := VBoxContainer.new()
	nav_list.add_theme_constant_override("separation", 2 if is_compact else 4)
	left_col.add_child(nav_list)

	var primary_title := "CONTINUAR NA PISTA" if context == Context.PAUSE else "RACE WEEKEND"
	var primary_item := _make_home_nav_item(primary_title, Color.WHITE, LmuTheme.ACCENT_RED, true, fs, is_compact)
	primary_item.pressed.connect(func():
		if context == Context.PAUSE:
			resumed.emit()
		else:
			drive_requested.emit()
	)
	nav_list.add_child(primary_item)

	if context == Context.PAUSE:
		var restart_item := _make_home_nav_item("REINICIAR VOLTA", LmuTheme.ACCENT_AMBER, LmuTheme.ACCENT_AMBER, true, fs, is_compact)
		restart_item.pressed.connect(func(): restart_requested.emit())
		nav_list.add_child(restart_item)

	var nav_entries := [
		["GARAGEM & CARROS", "cars"],
		["CONFIGURAÇÕES", "settings"],
		["RECORDES", "records"],
		["COMO JOGAR", "help"],
	]
	for item in nav_entries:
		var v_id: String = item[1]
		var nbtn := _make_home_nav_item(item[0], LmuTheme.TEXT_WHITE, LmuTheme.ACCENT_RED, false, fs, is_compact)
		nbtn.pressed.connect(func(): switch_view(v_id))
		nav_list.add_child(nbtn)

	if context == Context.PAUSE:
		var gar_item := _make_home_nav_item("GARAGEM 3D", LmuTheme.TEXT_SLATE, LmuTheme.ACCENT_RED, false, fs, is_compact, true)
		gar_item.pressed.connect(func(): garage_requested.emit())
		nav_list.add_child(gar_item)

	var quit_item := _make_home_nav_item("SAIR DO JOGO" if context != Context.PAUSE else "SAIR", LmuTheme.TEXT_MUTED, LmuTheme.ACCENT_RED, false, fs, is_compact, true)
	quit_item.pressed.connect(func(): quit_requested.emit())
	nav_list.add_child(quit_item)

	# Espaçador central em desktop/tablet/mobile_landscape para empurrar o card do carro para a direita
	if not is_portrait:
		var mid_sp := Control.new()
		mid_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(mid_sp)

	# Coluna Direita: Card de Destaque do Carro (com faixa lateral na cor do carro) + linha discreta Piloto
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size.x = float(lp.home_right_width) if not is_portrait else 0.0
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_portrait else Control.SIZE_SHRINK_END
	right_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_col.add_theme_constant_override("separation", 6 if is_compact else 10)
	host.add_child(right_col)

	var c := current_car()
	var c_col := Color(String(c.get("color", "#e10600")))
	var spot := PanelContainer.new()
	spot.clip_contents = true
	spot.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SUBTLE, 6, 0, 0))
	right_col.add_child(spot)

	var spot_hwrap := HBoxContainer.new()
	spot_hwrap.add_theme_constant_override("separation", 0)
	spot.add_child(spot_hwrap)

	var accent_strip := ColorRect.new()
	accent_strip.custom_minimum_size = Vector2(4, 0)
	accent_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	accent_strip.color = c_col
	accent_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spot_hwrap.add_child(accent_strip)

	var spot_mc := MarginContainer.new()
	spot_mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spot_mc.add_theme_constant_override("margin_left", 12 if is_compact else 18)
	spot_mc.add_theme_constant_override("margin_right", 12 if is_compact else 18)
	spot_mc.add_theme_constant_override("margin_top", 10 if is_compact else 16)
	spot_mc.add_theme_constant_override("margin_bottom", 10 if is_compact else 16)
	spot_hwrap.add_child(spot_mc)

	var spot_v := VBoxContainer.new()
	spot_v.add_theme_constant_override("separation", 6 if is_compact else 10)
	spot_mc.add_child(spot_v)

	var spot_h := HBoxContainer.new()
	spot_v.add_child(spot_h)
	var sh_l := LmuTheme.make_label("CARRO SELECIONADO", roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700)
	sh_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spot_h.add_child(sh_l)
	spot_h.add_child(LmuTheme.make_label("GT3 CLASS", roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700))

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	spot_v.add_child(title_box)
	title_box.add_child(LmuTheme.make_label(String(c.get("brand", "GT3")), roundi((10 if is_compact else 12) * fs), LmuTheme.ACCENT_RED_BRIGHT, 800))
	title_box.add_child(LmuTheme.make_label(String(c.get("name", current_car_id)), roundi((17 if is_compact else 23) * fs), Color.WHITE, 800))

	spot_v.add_child(_make_h_divider(0.10))

	var spec_grid := GridContainer.new()
	spec_grid.columns = 2
	spec_grid.add_theme_constant_override("h_separation", 14)
	spec_grid.add_theme_constant_override("v_separation", 6 if is_compact else 10)
	spot_v.add_child(spec_grid)

	var specs := [
		["MOTOR", String(c.get("engine", LAYOUT_LABELS.get(c.get("layout", "central"), "GT3")))],
		["POTÊNCIA", "%d CV" % int(c.get("power", 565))],
		["PESO", "%d KG" % int(c.get("weight", 1250))],
		["CÂMBIO", "%d MARCHAS" % int(c.get("gears", 6))],
	]
	for sp in specs:
		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_theme_constant_override("separation", 1)
		sv.add_child(LmuTheme.make_label(sp[0], roundi((8 if is_compact else 10) * fs), LmuTheme.TEXT_DIM, 700))
		var val_lbl := LmuTheme.make_label(sp[1], roundi((11 if is_compact else 13) * fs), LmuTheme.TEXT_WHITE, 700)
		val_lbl.clip_text = true
		sv.add_child(val_lbl)
		spec_grid.add_child(sv)

	spot_v.add_child(_make_h_divider(0.10))

	var swap_btn := Button.new()
	swap_btn.text = "TROCAR DE CARRO ➔"
	swap_btn.custom_minimum_size.y = 32 if is_compact else 40
	swap_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(swap_btn, "outline", 4, 12, 4)
	swap_btn.pressed.connect(func(): switch_view("cars"))
	spot_v.add_child(swap_btn)

	# Resumo discreto do Piloto e Melhor Volta abaixo do card
	var rating := compute_driver_rating(current_mode)
	var drv_row := HBoxContainer.new()
	drv_row.add_theme_constant_override("separation", 8)
	right_col.add_child(drv_row)
	var dn := LmuTheme.make_label("%s · DR %s" % [current_nick.to_upper(), rating.dr], roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700)
	dn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drv_row.add_child(dn)
	var best_txt := LapTimer.format_time(float(rating.best)) if float(rating.best) > 0.0 else "--:--.---"
	var bt_lbl := LmuTheme.make_label("MELHOR (%s): %s" % [Game.MODE_NAMES.get(current_mode, "Simulador"), best_txt], roundi((9 if is_compact else 11) * fs), LmuTheme.ACCENT_GREEN if float(rating.best) > 0.0 else LmuTheme.TEXT_DIM, 700)
	drv_row.add_child(bt_lbl)


# ------------------------------------------------------------------ CARS VIEW (GARAGE 3D LAYOUT)

func _build_cars_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_portrait: bool = (lp.profile == "portrait")
	var is_compact: bool = (lp.profile == "mobile_landscape")
	var mouse_pass := _is_transparent_studio_view()

	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y), mouse_pass)
	_body_holder.add_child(outer)
	_view_root = outer

	var root_col := VBoxContainer.new()
	root_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_col.add_theme_constant_override("separation", 6 if is_compact else 12)
	root_col.mouse_filter = Control.MOUSE_FILTER_IGNORE if mouse_pass else Control.MOUSE_FILTER_PASS
	outer.add_child(root_col)

	var stage_parent: Control = root_col
	if is_portrait:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE if mouse_pass else Control.MOUSE_FILTER_PASS
		root_col.add_child(scroll)
		var pv := VBoxContainer.new()
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.add_theme_constant_override("separation", 10)
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE if mouse_pass else Control.MOUSE_FILTER_PASS
		scroll.add_child(pv)
		stage_parent = pv

	# Stage Superior: Showcase transparente (para o estúdio 3D) + Painel Direito
	var stage: BoxContainer
	if is_portrait:
		stage = VBoxContainer.new()
	else:
		stage = HBoxContainer.new()
		stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 12 if is_compact else 20)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE if mouse_pass else Control.MOUSE_FILTER_PASS
	stage_parent.add_child(stage)

	# Showcase Esquerda/Centro (transparente no centro!)
	var showcase := VBoxContainer.new()
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	showcase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(showcase)

	var hero_v := VBoxContainer.new()
	hero_v.add_theme_constant_override("separation", 2 if is_compact else 4)
	hero_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase.add_child(hero_v)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 8)
	brand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_v.add_child(brand_row)

	var brand_pill := PanelContainer.new()
	brand_pill.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.ACCENT_RED, Color.TRANSPARENT, 3, 8, 2))
	brand_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_hero_brand = LmuTheme.make_label("PORSCHE", roundi((10 if is_compact else 13) * fs), Color.WHITE, 800)
	brand_pill.add_child(_car_hero_brand)
	brand_row.add_child(brand_pill)

	brand_row.add_child(LmuTheme.make_label("GT3 CLASS · ESTÚDIO 3D INTERATIVO" if context == Context.GARAGE else "GT3 CLASS", roundi((10 if is_compact else 12) * fs), LmuTheme.TEXT_MUTED, 700))

	_car_hero_name = LmuTheme.make_label("", roundi((20 if is_compact else 42) * fs), Color.WHITE, 800)
	_car_hero_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_car_hero_name.add_theme_constant_override("shadow_offset_y", 2)
	hero_v.add_child(_car_hero_name)

	_car_hero_engine = LmuTheme.make_label("", roundi((10 if is_compact else 14) * fs), LmuTheme.TEXT_SLATE, 600)
	_car_hero_engine.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	hero_v.add_child(_car_hero_engine)

	# Espaço aberto central para ver e girar o carro 3D
	var center_gap := Control.new()
	center_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_gap.custom_minimum_size.y = 110.0 if is_portrait else 40.0
	center_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	showcase.add_child(center_gap)

	if context == Context.GARAGE and not is_compact and not is_portrait:
		var hint := LmuTheme.make_label("◀ ▶ trocar  ·  Arraste no carro para girar  ·  Roda do mouse aproxima  ·  Enter pilotar", roundi(12 * fs), LmuTheme.TEXT_DIM, 500)
		showcase.add_child(hint)

	# Painel Lateral Direito: Modo + Ficha Técnica + Personal Best
	var panel_col := VBoxContainer.new()
	panel_col.custom_minimum_size.x = float(lp.cars_panel_width) if not is_portrait else 0.0
	panel_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_portrait else Control.SIZE_SHRINK_END
	panel_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel_col.add_theme_constant_override("separation", 5 if is_compact else 10)
	panel_col.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(panel_col)

	# 1. Modo de Pilotagem
	var mode_sec := PanelContainer.new()
	mode_sec.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SUBTLE, 6, 9 if is_compact else 14, 5 if is_compact else 10))
	panel_col.add_child(mode_sec)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4 if is_compact else 6)
	mode_sec.add_child(mv)
	mv.add_child(LmuTheme.make_label("MODO DE PILOTAGEM", roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700))

	var mgrid := HBoxContainer.new()
	mgrid.add_theme_constant_override("separation", 6)
	mv.add_child(mgrid)
	for m_entry in [["sim", "SIMULADOR", "Física real 1,0×"], ["arcade", "ARCADE", "2,0× aderência"]]:
		var m_id: String = m_entry[0]
		var mb := Button.new()
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.custom_minimum_size.y = 32 if is_compact else 46
		LmuTheme.apply_button_styles(mb, "active" if current_mode == m_id else "outline", 4, 6, 4)
		mb.pressed.connect(func(): _set_mode(m_id))
		var mbv := VBoxContainer.new()
		mbv.set_anchors_preset(Control.PRESET_FULL_RECT)
		mbv.alignment = BoxContainer.ALIGNMENT_CENTER
		mbv.add_theme_constant_override("separation", 0)
		mbv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mb.add_child(mbv)
		var mn := LmuTheme.make_label(m_entry[1], roundi((10 if is_compact else 13) * fs), Color.WHITE, 800)
		mn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mbv.add_child(mn)
		if not is_compact:
			var md := LmuTheme.make_label(m_entry[2], roundi(10 * fs), LmuTheme.TEXT_MUTED, 500)
			md.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mbv.add_child(md)
		mgrid.add_child(mb)

	# 2. Ficha Técnica (5 linhas no desktop, 4 no mobile landscape ocultando Downforce)
	var specs_sec := PanelContainer.new()
	specs_sec.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SUBTLE, 6, 9 if is_compact else 14, 5 if is_compact else 10))
	panel_col.add_child(specs_sec)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 2 if is_compact else 5)
	specs_sec.add_child(sv)
	sv.add_child(LmuTheme.make_label("FICHA TÉCNICA DO GT3", roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700))

	var spec_keys := [
		["power", "Potência Estimada"],
		["weight", "Peso Homologado"],
		["ratio", "Relação Peso/Potência"],
		["dist", "Distribuição de Peso"],
	]
	if not bool(lp.cars_hide_aero):
		spec_keys.append(["aero", "Downforce Aero"])

	for idx_sk in spec_keys.size():
		var sk: Array = spec_keys[idx_sk]
		if idx_sk > 0:
			sv.add_child(_make_h_divider(0.06))
		var sr := HBoxContainer.new()
		sv.add_child(sr)
		var kl := LmuTheme.make_label(sk[1], roundi((10 if is_compact else 13) * fs), LmuTheme.TEXT_MUTED, 500)
		kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sr.add_child(kl)
		var vl := LmuTheme.make_label("--", roundi((10 if is_compact else 13) * fs), Color.WHITE, 700)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sr.add_child(vl)
		_car_spec_vals[sk[0]] = vl

	# 3. Melhor Tempo Pessoal
	var pb_sec := PanelContainer.new()
	pb_sec.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, Color(LmuTheme.ACCENT_GREEN.r, LmuTheme.ACCENT_GREEN.g, LmuTheme.ACCENT_GREEN.b, 0.42), 6, 9 if is_compact else 14, 5 if is_compact else 10))
	panel_col.add_child(pb_sec)
	var pbv := VBoxContainer.new()
	pbv.add_theme_constant_override("separation", 2)
	pb_sec.add_child(pbv)
	pbv.add_child(LmuTheme.make_label("SEU MELHOR TEMPO", roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700))

	if bool(lp.cars_pb_horizontal):
		var pbh := HBoxContainer.new()
		pbv.add_child(pbh)
		_car_pb_time_lbl = LmuTheme.make_label("--:--.---", roundi(15 * fs), LmuTheme.ACCENT_GREEN, 800)
		_car_pb_time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbh.add_child(_car_pb_time_lbl)
		_car_pb_sub_lbl = LmuTheme.make_label("", roundi(9 * fs), LmuTheme.TEXT_MUTED, 500)
		pbh.add_child(_car_pb_sub_lbl)
	else:
		_car_pb_time_lbl = LmuTheme.make_label("--:--.---", roundi(24 * fs), LmuTheme.ACCENT_GREEN, 800)
		pbv.add_child(_car_pb_time_lbl)
		_car_pb_sub_lbl = LmuTheme.make_label("", roundi(11 * fs), LmuTheme.TEXT_MUTED, 500)
		pbv.add_child(_car_pb_sub_lbl)

	# Barra Inferior: Toolbar (Filtros + Ações) + Grade 7 colunas (13 carros)
	var bottom_bar := PanelContainer.new()
	bottom_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(0.031, 0.043, 0.063, 0.94), LmuTheme.BORDER_SUBTLE, 8, 10 if is_compact else 16, 6 if is_compact else 12))
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	stage_parent.add_child(bottom_bar)

	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6 if is_compact else 10)
	bottom_bar.add_child(bv)

	var toolbar: BoxContainer = VBoxContainer.new() if is_portrait else HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	bv.add_child(toolbar)

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 4)
	frow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(frow)

	var filters := [
		["todos", "TODOS (%d)" % cars.size()],
		["traseiro", "TRASEIRO"],
		["central", "CENTRAL"],
		["dianteiro", "DIANTEIRO"],
	]
	for fl in filters:
		var f_id: String = fl[0]
		var fb := Button.new()
		fb.text = fl[1]
		fb.add_theme_font_size_override("font_size", roundi((10 if is_compact else 12) * fs))
		LmuTheme.apply_button_styles(fb, "primary" if category_filter == f_id else "outline", 3, 8 if is_compact else 12, 3 if is_compact else 6)
		fb.pressed.connect(func():
			category_filter = f_id
			_rebuild_view()
		)
		frow.add_child(fb)

	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 6)
	toolbar.add_child(arow)

	var prev_btn := Button.new()
	prev_btn.text = "◀"
	prev_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(prev_btn, "outline", 4, 10, 4)
	prev_btn.pressed.connect(func(): _step_car(-1))
	arow.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "▶"
	next_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(next_btn, "outline", 4, 10, 4)
	next_btn.pressed.connect(func(): _step_car(1))
	arow.add_child(next_btn)

	if context == Context.PAUSE:
		var gar_btn := Button.new()
		gar_btn.text = "GARAGEM 3D"
		gar_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
		LmuTheme.apply_button_styles(gar_btn, "outline", 4, 12, 4)
		gar_btn.pressed.connect(func(): garage_requested.emit())
		arow.add_child(gar_btn)

	_drive_btn = Button.new()
	_drive_btn.text = "CONTINUAR ➔" if context == Context.PAUSE else "PILOTAR ➔"
	_drive_btn.add_theme_font_size_override("font_size", roundi((12 if is_compact else 16) * fs))
	LmuTheme.apply_button_styles(_drive_btn, "primary", 4, 16 if is_compact else 24, 5 if is_compact else 8)
	_drive_btn.pressed.connect(func():
		if context == Context.PAUSE:
			resumed.emit()
		else:
			drive_requested.emit()
	)
	arow.add_child(_drive_btn)

	# Grade de carros
	var grid := GridContainer.new()
	grid.columns = int(lp.cars_grid_cols)
	grid.add_theme_constant_override("h_separation", 5 if is_compact else 8)
	grid.add_theme_constant_override("v_separation", 5 if is_compact else 8)
	bv.add_child(grid)

	var chip_h := int(lp.cars_chip_height)
	for c in cars:
		if not (c is Dictionary):
			continue
		if category_filter != "todos" and String(c.get("layout", "")) != category_filter:
			continue
		var cid := String(c.get("id", ""))
		var ccol := Color(String(c.get("color", "#e10600")))
		var chip := _create_car_chip(c, ccol, chip_h, is_compact, fs)
		grid.add_child(chip)
		_cars_grid_nodes[cid] = chip

	_refresh_cars_view_data()


func _create_car_chip(c: Dictionary, ccol: Color, chip_h: int, is_compact: bool, fs: float) -> Button:
	var cid := String(c.get("id", ""))
	var is_sel := (cid == current_car_id)
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, chip_h)
	btn.clip_contents = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_chip_style(btn, ccol, is_sel)
	btn.pressed.connect(func(): set_selected_car(cid, true))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.offset_left = 10
	box.offset_right = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	if not is_compact:
		var br := LmuTheme.make_label(String(c.get("brand", c.get("short", ""))), roundi(9 * fs), LmuTheme.TEXT_MUTED, 700)
		br.clip_text = true
		box.add_child(br)
	var nm := LmuTheme.make_label(String(c.get("name", cid)), roundi((10 if is_compact else 12) * fs), Color.WHITE, 700)
	nm.clip_text = true
	box.add_child(nm)
	var ly := LmuTheme.make_label(String(c.get("layout", "")).to_upper(), roundi((8 if is_compact else 9) * fs), ccol.lightened(0.25), 700)
	ly.clip_text = true
	box.add_child(ly)

	return btn


func _apply_chip_style(btn: Button, ccol: Color, selected: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		if selected:
			sb.bg_color = Color(0.14, 0.16, 0.22, 0.96) if st == "normal" else Color(0.18, 0.21, 0.28, 0.98)
			sb.border_color = Color.WHITE
			sb.set_border_width_all(2)
			sb.border_width_left = 5
		else:
			sb.bg_color = LmuTheme.BG_CHIP if st == "normal" else LmuTheme.BG_CHIP_HOVER
			sb.border_color = LmuTheme.BORDER_SUBTLE if st == "normal" else LmuTheme.BORDER_BRIGHT
			sb.set_border_width_all(1)
			sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override(st, sb)

	# Indicador colorido esquerdo dedicado (sempre na cor do carro)
	var bar := btn.get_node_or_null("ColorBar") as ColorRect
	if bar == null:
		bar = ColorRect.new()
		bar.name = "ColorBar"
		bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		bar.offset_right = 5 if selected else 4
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bar)
	bar.color = ccol
	bar.offset_right = 5 if selected else 4


func _refresh_cars_view_data() -> void:
	var c := current_car()
	if c.is_empty():
		return
	var layout_str := String(c.get("layout", "central"))
	var power := int(c.get("power", 565))
	var weight := int(c.get("weight", 1250))
	var gears := int(c.get("gears", 6))
	var engine_str := String(c.get("engine", LAYOUT_LABELS.get(layout_str, "GT3")))

	if _car_hero_brand:
		_car_hero_brand.text = String(c.get("brand", "GT3"))
	if _car_hero_name:
		_car_hero_name.text = String(c.get("name", current_car_id)).to_upper()
	if _car_hero_engine:
		_car_hero_engine.text = "%s  ·  %s  ·  CÂMBIO SEQUENCIAL %d MARCHAS" % [engine_str, LAYOUT_LABELS.get(layout_str, "GT3"), gears]

	if _car_spec_vals.has("power"):
		_car_spec_vals["power"].text = "%d cv" % power
	if _car_spec_vals.has("weight"):
		_car_spec_vals["weight"].text = "%d kg" % weight
	if _car_spec_vals.has("ratio"):
		_car_spec_vals["ratio"].text = "%.2f kg/cv" % (float(weight) / maxf(1.0, float(power)))
	if _car_spec_vals.has("dist"):
		_car_spec_vals["dist"].text = Game.weight_distribution_for_layout(layout_str)
	if _car_spec_vals.has("aero"):
		_car_spec_vals["aero"].text = "Asa Traseira Regulável GT3"

	var pb := _car_pb(String(c.get("id", "")), current_mode)
	if _car_pb_time_lbl:
		if not pb.is_empty():
			_car_pb_time_lbl.text = LapTimer.format_time(float(pb.get("time", 0.0)))
			_car_pb_time_lbl.add_theme_color_override("font_color", LmuTheme.ACCENT_GREEN)
			if _car_pb_sub_lbl:
				_car_pb_sub_lbl.text = "Recorde Pessoal (%s)" % Game.MODE_NAMES.get(current_mode, current_mode)
		else:
			_car_pb_time_lbl.text = "--:--.---"
			_car_pb_time_lbl.add_theme_color_override("font_color", LmuTheme.TEXT_DIM)
			if _car_pb_sub_lbl:
				_car_pb_sub_lbl.text = "Nenhuma volta válida ainda"

	for cid in _cars_grid_nodes:
		var btn: Button = _cars_grid_nodes[cid]
		var info := Game.get_car_info(cid)
		var col := Color(String(info.get("color", "#e10600")))
		_apply_chip_style(btn, col, cid == current_car_id)


func _step_car(delta: int) -> void:
	if cars.is_empty():
		return
	var cur_i := 0
	for i in cars.size():
		if String(cars[i].get("id", "")) == current_car_id:
			cur_i = i
			break
	var next_i := posmod(cur_i + delta, cars.size())
	set_selected_car(String(cars[next_i].get("id", "")), true)


# ------------------------------------------------------------------ SETTINGS VIEW (5 ABAS + BUSCA)

func _build_settings_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_compact: bool = (lp.profile == "mobile_landscape")

	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8 if is_compact else 14)
	outer.add_child(col)

	# Barra horizontal das 5 abas (underline LMU)
	var tab_bar_wrap := VBoxContainer.new()
	tab_bar_wrap.add_theme_constant_override("separation", 0)
	col.add_child(tab_bar_wrap)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4 if is_compact else 10)
	tab_bar_wrap.add_child(tab_bar)

	for tab_id in SETTINGS_TABS:
		var tb := Button.new()
		tb.text = SETTINGS_TAB_LABELS[tab_id]
		tb.add_theme_font_size_override("font_size", roundi((11 if is_compact else 14) * fs))
		LmuTheme.apply_button_styles(tb, "tab_active" if active_settings_tab == tab_id else "tab_idle", 0, 10 if is_compact else 16, 6 if is_compact else 10)
		tb.pressed.connect(func():
			active_settings_tab = tab_id
			_rebuild_all()
		)
		tab_bar.add_child(tb)
	tab_bar_wrap.add_child(_make_h_divider(0.10))

	# Em mobile/portrait (onde header_center fica oculto), oferece campo de busca inline
	if not bool(lp.show_header_center):
		_settings_search_edit = LineEdit.new()
		_settings_search_edit.placeholder_text = "🔍 Buscar configuração..."
		_settings_search_edit.text = search_query
		_settings_search_edit.custom_minimum_size.y = 32
		_settings_search_edit.add_theme_font_size_override("font_size", roundi(12 * fs))
		_settings_search_edit.add_theme_stylebox_override("normal", LmuTheme.input_style(false))
		_settings_search_edit.add_theme_stylebox_override("focus", LmuTheme.input_style(true))
		_settings_search_edit.text_changed.connect(_on_search_changed)
		col.add_child(_settings_search_edit)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6 if is_compact else 10)
	scroll.add_child(content)

	_populate_settings_tab(content, is_compact, fs)

	_settings_empty_lbl = LmuTheme.make_label("Nenhuma configuração encontrada nesta aba para a busca atual.", roundi(13 * fs), LmuTheme.TEXT_MUTED, 500)
	_settings_empty_lbl.visible = false
	content.add_child(_settings_empty_lbl)

	_apply_settings_filter()

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(footer)
	var back_btn := Button.new()
	back_btn.text = "APLICAR & VOLTAR"
	back_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 16, 6 if is_compact else 8)
	back_btn.pressed.connect(func(): switch_view("home"))
	footer.add_child(back_btn)


func _on_search_changed(q: String) -> void:
	search_query = q
	if _header_search_edit != null and is_instance_valid(_header_search_edit) and _header_search_edit.text != q:
		_header_search_edit.text = q
	if _settings_search_edit != null and is_instance_valid(_settings_search_edit) and _settings_search_edit.text != q:
		_settings_search_edit.text = q
	_apply_settings_filter()


func _apply_settings_filter() -> void:
	var q := _norm(search_query)
	var visible_count := 0
	for entry in _settings_rows:
		var node: Control = entry.node
		var kw: String = entry.keywords
		var cond: bool = entry.visible_cond
		var match_ok := (q == "" or kw.contains(q))
		var show := cond and match_ok
		node.visible = show
		if show:
			visible_count += 1
	if _settings_empty_lbl != null and is_instance_valid(_settings_empty_lbl):
		_settings_empty_lbl.visible = (visible_count == 0 and q != "")


func _add_setting_row(parent: Control, title: String, desc: String, keywords: String, control: Control, is_compact: bool, fs: float, visible_cond := true) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(1, 1, 1, 0.03), LmuTheme.BORDER_SOFT, 5, 12, 6 if is_compact else 10))
	parent.add_child(row_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row_panel.add_child(h)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)
	info.add_child(LmuTheme.make_label(title, roundi((13 if is_compact else 15) * fs), Color.WHITE, 700))
	var dl := LmuTheme.make_label(desc, roundi((10 if is_compact else 12) * fs), LmuTheme.TEXT_MUTED, 500)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(dl)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)

	_settings_rows.append({
		"node": row_panel,
		"keywords": _norm("%s %s %s" % [title, desc, keywords]),
		"visible_cond": visible_cond,
	})
	return row_panel


func _make_badge(txt: String, col := LmuTheme.TEXT_WHITE, border := LmuTheme.BORDER_SUBTLE, fs := 1.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(1, 1, 1, 0.08), border, 4, 10, 4))
	p.add_child(LmuTheme.make_label(txt, roundi(12 * fs), col, 700))
	return p


func _populate_settings_tab(parent: Control, is_compact: bool, fs: float) -> void:
	match active_settings_tab:
		"controls":
			parent.add_child(LmuTheme.make_label("DISPOSITIVOS & ENTRADA", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			var show_touch := is_touch_device or OS.has_feature("mobile")

			var touch_opt := OptionButton.new()
			touch_opt.custom_minimum_size = Vector2(160, 34)
			touch_opt.focus_mode = Control.FOCUS_NONE
			for tm in TOUCH_MODES:
				touch_opt.add_item(TOUCH_MODE_NAMES[tm])
			touch_opt.selected = maxi(0, TOUCH_MODES.find(current_touch_mode))
			touch_opt.item_selected.connect(func(i: int):
				current_touch_mode = TOUCH_MODES[i]
				Game.set_setting("controles", "modo_toque", current_touch_mode)
				touch_mode_changed.emit(current_touch_mode)
				if _recenter_row != null:
					for e in _settings_rows:
						if e.node == _recenter_row:
							e.visible_cond = show_touch and (current_touch_mode == "inclinar")
					_apply_settings_filter()
			)
			_add_setting_row(
				parent,
				"Esquema de Toque no Celular",
				TOUCH_MODE_NOTES.get(current_touch_mode, ""),
				"toque celular controles volante padrao fly inclinar legacy",
				touch_opt,
				is_compact,
				fs,
				show_touch
			)

			var rec_btn := Button.new()
			rec_btn.text = "⟳ RECENTRALIZAR"
			rec_btn.add_theme_font_size_override("font_size", roundi(12 * fs))
			LmuTheme.apply_button_styles(rec_btn, "outline", 4, 12, 6)
			rec_btn.pressed.connect(func(): recenter_tilt.emit())
			_recenter_row = _add_setting_row(
				parent,
				"Calibrar Volante (Giroscópio)",
				"Zera o ponto central na posição em que você está segurando o aparelho.",
				"calibrar volante recentralizar giroscopio acelerometro inclinar",
				rec_btn,
				is_compact,
				fs,
				show_touch and current_touch_mode == "inclinar"
			)

			var hide_cb := CheckButton.new()
			hide_cb.focus_mode = Control.FOCUS_NONE
			hide_cb.button_pressed = current_hide_touch
			hide_cb.toggled.connect(func(on: bool):
				current_hide_touch = on
				Game.set_hide_touch_controls(on)
				hide_touch_changed.emit(on)
			)
			_add_setting_row(
				parent,
				"Esconder controles na tela",
				"Oculta os controles de toque (também oculta automaticamente quando um gamepad físico é conectado).",
				"esconder ocultar controles na tela touch celular bluetooth gamepad",
				hide_cb,
				is_compact,
				fs,
				show_touch
			)

			_add_setting_row(
				parent,
				"Comandos de Teclado",
				"W/S ou ↑/↓ = Acelerar/Frear · A/D ou ←/→ = Esterçar · E/Q = Marchas · C = Câmera · R = Grid · Esc = Menu",
				"teclado comandos atalhos wasd",
				_make_badge("ATIVO", LmuTheme.ACCENT_GREEN, LmuTheme.ACCENT_GREEN, fs),
				is_compact,
				fs
			)

			var has_pad := Game.has_gamepad_connected()
			_add_setting_row(
				parent,
				"Controle / Gamepad (Xbox / PlayStation)",
				"RT/LT = Acelerar/Frear · Analógico = Volante · RB/LB = Marchas · Vibração Háptica (Rumble)",
				"controle gamepad joystick bluetooth rumble vibracao",
				_make_badge("CONECTADO" if has_pad else "PLUG & PLAY", LmuTheme.ACCENT_GREEN if has_pad else LmuTheme.TEXT_WHITE, LmuTheme.BORDER_SUBTLE, fs),
				is_compact,
				fs
			)

		"graphics":
			parent.add_child(LmuTheme.make_label("QUALIDADE VISUAL & DESEMPENHO", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))

			var stepper := HBoxContainer.new()
			stepper.add_theme_constant_override("separation", 8)
			var q_val_lbl := LmuTheme.make_label(current_quality.to_upper(), roundi(13 * fs), Color.WHITE, 800)
			q_val_lbl.custom_minimum_size.x = 86
			q_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var q_prev := Button.new()
			q_prev.text = "◀"
			LmuTheme.apply_button_styles(q_prev, "outline", 4, 10, 4)
			var q_next := Button.new()
			q_next.text = "▶"
			LmuTheme.apply_button_styles(q_next, "outline", 4, 10, 4)
			stepper.add_child(q_prev)
			stepper.add_child(q_val_lbl)
			stepper.add_child(q_next)

			var q_row := _add_setting_row(
				parent,
				"Preset Gráfico",
				QUALITY_NOTES.get(current_quality, ""),
				"graficos qualidade preset fps minimo leve medio extremo",
				stepper,
				is_compact,
				fs
			)
			var step_quality := func(delta: int):
				var i := QUALITIES.find(current_quality)
				if i < 0:
					i = 1
				current_quality = QUALITIES[posmod(i + delta, QUALITIES.size())]
				Game.set_setting("video", "qualidade", current_quality)
				q_val_lbl.text = current_quality.to_upper()
				quality_changed.emit(current_quality)
				_rebuild_view()
			q_prev.pressed.connect(func(): step_quality.call(-1))
			q_next.pressed.connect(func(): step_quality.call(1))
			var _unused_q_row := q_row

			var fps_p := PanelContainer.new()
			fps_p.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(1, 1, 1, 0.08), LmuTheme.BORDER_SUBTLE, 4, 10, 4))
			_fps_badge_lbl = LmuTheme.make_label("%d FPS" % live_fps if live_fps > 0 else "-- FPS", roundi(13 * fs), LmuTheme.ACCENT_GREEN if live_fps >= 55 else LmuTheme.TEXT_WHITE, 800)
			fps_p.add_child(_fps_badge_lbl)
			var fps_desc := ("%d FPS medidos na pista" % live_fps) if live_fps > 0 else "Inicie a pilotagem para medir"
			var fps_row := _add_setting_row(
				parent,
				"Taxa de Quadros Atual",
				fps_desc,
				"fps taxa de quadros desempenho gpu",
				fps_p,
				is_compact,
				fs
			)
			# Guarda referência à descrição de FPS para atualizar ao vivo
			_fps_explain_lbl = fps_row.get_child(0).get_child(0).get_child(1) as Label

			var gauge_opt := OptionButton.new()
			gauge_opt.custom_minimum_size = Vector2(210, 34)
			gauge_opt.focus_mode = Control.FOCUS_NONE
			for gs in GAUGE_STYLES:
				gauge_opt.add_item(GAUGE_NAMES[gs])
			gauge_opt.selected = maxi(0, GAUGE_STYLES.find(current_hud_gauge))
			gauge_opt.item_selected.connect(func(i: int):
				current_hud_gauge = GAUGE_STYLES[i]
				Game.set_setting("hud", "mostrador", current_hud_gauge)
				hud_gauge_changed.emit(current_hud_gauge)
			)
			_add_setting_row(
				parent,
				"Estilo do Conta-Giros / Velocímetro",
				"Barra Horizontal no topo libera visão da pista; Circular Clássico restaura o mostrador redondo.",
				"hud barra horizontal circular conta giros velocimetro mostrador",
				gauge_opt,
				is_compact,
				fs
			)

		"assists":
			parent.add_child(LmuTheme.make_label("ASSISTÊNCIAS DE PILOTAGEM", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			var aids_info := [
				["abs", "Sistema ABS (Anti-lock Braking)", "Impede o travamento das rodas nas freadas fortes de Interlagos.", "abs anti travamento freios"],
				["tc", "Controle de Tração (TC)", "Regula o escorregamento dos pneus traseiros na retomada de curva.", "tc tracao controle de tracao"],
				["auto", "Câmbio Automático", "Troca as marchas no giro ideal automaticamente (padrão no toque).", "cambio automatico marcha"],
			]
			for aid in aids_info:
				var a_key: String = aid[0]
				var cb := CheckButton.new()
				cb.focus_mode = Control.FOCUS_NONE
				cb.button_pressed = bool(current_assists.get(a_key, false))
				cb.toggled.connect(func(on: bool):
					current_assists[a_key] = on
					Game.set_setting("assistencias", a_key, on)
					assist_changed.emit(a_key, on)
				)
				_add_setting_row(parent, aid[1], aid[2], aid[3], cb, is_compact, fs)

		"audio":
			parent.add_child(LmuTheme.make_label("CONFIGURAÇÕES DE ÁUDIO", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			var vrow := HBoxContainer.new()
			vrow.add_theme_constant_override("separation", 10)
			var slider := HSlider.new()
			slider.min_value = 0.0
			slider.max_value = 1.0
			slider.step = 0.05
			slider.custom_minimum_size = Vector2(140 if is_compact else 200, 26)
			slider.value = current_volume
			var v_lbl := LmuTheme.make_label("%d%%" % roundi(current_volume * 100.0), roundi(13 * fs), Color.WHITE, 700)
			v_lbl.custom_minimum_size.x = 44
			v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			slider.value_changed.connect(func(v: float):
				current_volume = v
				v_lbl.text = "%d%%" % roundi(v * 100.0)
				Game.set_setting("audio", "volume", v)
				volume_changed.emit(v)
			)
			vrow.add_child(slider)
			vrow.add_child(v_lbl)
			_add_setting_row(
				parent,
				"Volume Geral",
				"Volume dos motores gravados, pneus cantando, zebras e vento.",
				"volume som audio efeitos",
				vrow,
				is_compact,
				fs
			)
			_add_setting_row(
				parent,
				"Ronco do Motor & Turbo",
				"Amostras reais sintetizadas com rotação, superfícies e corte de giro GT3.",
				"motor ronco banco de som turbo",
				_make_badge("ÁUDIO ESPACIAL ON", LmuTheme.ACCENT_GREEN, LmuTheme.BORDER_SUBTLE, fs),
				is_compact,
				fs
			)

		"driver":
			parent.add_child(LmuTheme.make_label("DADOS DO PILOTO", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			var nick_edit := LineEdit.new()
			nick_edit.custom_minimum_size = Vector2(160 if is_compact else 210, 34)
			nick_edit.max_length = 16
			nick_edit.placeholder_text = "ex.: davi"
			nick_edit.text = current_nick
			nick_edit.add_theme_font_size_override("font_size", roundi(14 * fs))
			nick_edit.add_theme_stylebox_override("normal", LmuTheme.input_style(false))
			nick_edit.add_theme_stylebox_override("focus", LmuTheme.input_style(true))
			nick_edit.text_changed.connect(func(t: String):
				var clean := t.strip_edges()
				current_nick = clean if clean != "" else "Piloto"
				Records.save_nick(current_nick)
				if _driver_name_lbl != null and is_instance_valid(_driver_name_lbl):
					_driver_name_lbl.text = current_nick
				nick_changed.emit(current_nick)
			)
			_add_setting_row(
				parent,
				"Nome de Exibição / Nickname",
				"Nome que aparece nas tabelas de tempos online e nos recordes de Interlagos.",
				"nick nome piloto apelido",
				nick_edit,
				is_compact,
				fs
			)

			var rating := compute_driver_rating(current_mode)
			var r_badge := _make_badge("DR: %s · SR: %s" % [rating.dr, rating.sr], LmuTheme.ACCENT_AMBER, LmuTheme.BORDER_SUBTLE, fs)
			_driver_tab_rating_lbl = r_badge.get_child(0) as Label
			_add_setting_row(
				parent,
				"Classificação de Licença (DR & SR)",
				"Calculada com base na consistência e nos tempos oficiais obtidos em Interlagos.",
				"licenca rating dr sr",
				r_badge,
				is_compact,
				fs
			)


# ------------------------------------------------------------------ RECORDS VIEW

func _build_records_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_compact: bool = (lp.profile == "mobile_landscape")

	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8 if is_compact else 14)
	outer.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)

	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(LmuTheme.make_label("QUADRO OFICIAL DE TEMPOS · INTERLAGOS", roundi((17 if is_compact else 26) * fs), Color.WHITE, 800))
	hv.add_child(LmuTheme.make_label("Top 15 voltas válidas no modo %s" % Game.MODE_NAMES.get(records_mode, records_mode).to_upper(), roundi((10 if is_compact else 13) * fs), LmuTheme.TEXT_MUTED, 500))

	var m_switch := HBoxContainer.new()
	m_switch.add_theme_constant_override("separation", 6)
	head.add_child(m_switch)
	for rm in [["sim", "SIMULADOR"], ["arcade", "ARCADE"]]:
		var rm_id: String = rm[0]
		var b := Button.new()
		b.text = rm[1]
		b.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
		LmuTheme.apply_button_styles(b, "primary" if records_mode == rm_id else "outline", 4, 12, 5)
		b.pressed.connect(func():
			records_mode = rm_id
			_rebuild_view()
		)
		m_switch.add_child(b)

	# Comparação pessoal do piloto no carro atual
	var pb := _car_pb(current_car_id, records_mode)
	var car_info := current_car()
	var pb_bar := PanelContainer.new()
	pb_bar.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL_DEEP, LmuTheme.BORDER_SUBTLE, 5, 12, 6))
	col.add_child(pb_bar)
	var pbh := HBoxContainer.new()
	pbh.add_theme_constant_override("separation", 12)
	pb_bar.add_child(pbh)
	var pb_left := LmuTheme.make_label("SEU MELHOR (%s · %s):" % [current_nick, String(car_info.get("name", current_car_id))], roundi((11 if is_compact else 13) * fs), LmuTheme.TEXT_SLATE, 700)
	pb_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pbh.add_child(pb_left)
	if not pb.is_empty():
		var secs: Array = pb.get("sectors", [])
		var sec_txt := "%.2fs · %.2fs · %.2fs" % [float(secs[0]), float(secs[1]), float(secs[2])] if secs.size() == 3 else "--"
		pbh.add_child(LmuTheme.make_label("%s  [%s]" % [LapTimer.format_time(float(pb.get("time", 0.0))), sec_txt], roundi((12 if is_compact else 14) * fs), LmuTheme.ACCENT_GREEN, 800))
	else:
		pbh.add_child(LmuTheme.make_label("--:--.---", roundi((12 if is_compact else 14) * fs), LmuTheme.TEXT_DIM, 700))

	# Lista Top 15
	var recs: Array = Records.top(15, records_mode)
	if shared_records_by_mode.has(records_mode) and shared_records_by_mode[records_mode] is Array:
		var remote: Array = shared_records_by_mode[records_mode]
		if not remote.is_empty():
			recs = Records.merge_records(remote, Records.load_all(records_mode)).slice(0, 15)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3 if is_compact else 5)
	scroll.add_child(list)

	if recs.is_empty():
		var emp := PanelContainer.new()
		emp.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SOFT, 6, 16, 20))
		var el := LmuTheme.make_label("Nenhum tempo registrado ainda neste modo. Entre na pista e marque a primeira volta rápida!", roundi(14 * fs), LmuTheme.TEXT_MUTED, 500)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		emp.add_child(el)
		list.add_child(emp)
	else:
		var clean_me := current_nick.strip_edges().to_lower()
		for i in recs.size():
			var r: Dictionary = recs[i]
			var r_nick := String(r.get("nick", "Piloto"))
			var r_car_id := String(r.get("carId", ""))
			var c_info := Game.get_car_info(r_car_id)
			var c_name := String(c_info.get("name", r_car_id))
			var c_col := Color(String(c_info.get("color", "#888888")))
			var is_me := (r_nick.strip_edges().to_lower() == clean_me)

			var row := PanelContainer.new()
			var bg := Color(LmuTheme.ACCENT_RED.r, LmuTheme.ACCENT_RED.g, LmuTheme.ACCENT_RED.b, 0.18) if is_me else LmuTheme.BG_PANEL
			row.add_theme_stylebox_override("panel", LmuTheme.panel_style(bg, LmuTheme.BORDER_SOFT, 4, 10, 4 if is_compact else 7))
			list.add_child(row)

			var rh := HBoxContainer.new()
			rh.add_theme_constant_override("separation", 10)
			row.add_child(rh)

			var pos_p := PanelContainer.new()
			pos_p.custom_minimum_size = Vector2(26, 22)
			pos_p.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.ACCENT_AMBER if i == 0 else Color(1, 1, 1, 0.1), Color.TRANSPARENT, 3, 4, 1))
			var pl := LmuTheme.make_label("%d" % (i + 1), roundi(12 * fs), Color("#0b0d10") if i == 0 else Color.WHITE, 800)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pos_p.add_child(pl)
			rh.add_child(pos_p)

			var nl := LmuTheme.make_label(r_nick, roundi((12 if is_compact else 14) * fs), Color.WHITE, 700)
			nl.custom_minimum_size.x = 100 if is_compact else 160
			nl.clip_text = true
			rh.add_child(nl)

			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(4, 14)
			dot.color = c_col
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rh.add_child(dot)

			var cl := LmuTheme.make_label(c_name, roundi((11 if is_compact else 13) * fs), LmuTheme.TEXT_SLATE, 500)
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cl.clip_text = true
			rh.add_child(cl)

			var secs: Array = r.get("sectors", [])
			if lp.profile != "portrait" and secs.size() == 3:
				var sl_txt := "%.2fs · %.2fs · %.2fs" % [float(secs[0]), float(secs[1]), float(secs[2])]
				rh.add_child(LmuTheme.make_label(sl_txt, roundi((10 if is_compact else 12) * fs), LmuTheme.TEXT_MUTED, 500))

			var tl := LmuTheme.make_label(LapTimer.format_time(float(r.get("time", 0.0))), roundi((13 if is_compact else 15) * fs), LmuTheme.ACCENT_GREEN, 800)
			tl.custom_minimum_size.x = 78
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rh.add_child(tl)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(footer)
	var back_btn := Button.new()
	back_btn.text = "VOLTAR AO MENU"
	back_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 14, 6)
	back_btn.pressed.connect(func(): switch_view("home"))
	footer.add_child(back_btn)


# ------------------------------------------------------------------ HELP VIEW (3 CARDS)

func _build_help_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_compact: bool = (lp.profile == "mobile_landscape")
	var is_portrait: bool = (lp.profile == "portrait")

	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8 if is_compact else 14)
	outer.add_child(col)

	col.add_child(LmuTheme.make_label("GUIA DE CONTROLES & PILOTAGEM", roundi((17 if is_compact else 26) * fs), Color.WHITE, 800))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var cards_host: BoxContainer = VBoxContainer.new() if is_portrait else HBoxContainer.new()
	cards_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_host.add_theme_constant_override("separation", 10 if is_compact else 16)
	scroll.add_child(cards_host)

	var cards_data := [
		[
			"⌨️ CONTROLES",
			"Teclado: W/S ou ↑/↓ aceleram e freiam · A/D ou ←/→ esterçam · E/Shift sobe marcha · Q/Ctrl reduz.\n" +
			"Atalhos: C = câmera · R = voltar ao grid · P = piloto automático · T = telemetria · F1 = qualidade · Esc = menu.\n" +
			"Gamepad: RT/LT pedais · Analógico volante · RB/A e LB/X marchas · Y câmera · Back grid · Start menu.\n" +
			"Celular: 4 modos (Padrão, Fly-by-wire, Inclinar com acelerômetro e Legacy)."
		],
		[
			"⚙️ MODOS DE FÍSICA",
			"Simulador (1,0×): física realista GT3 calibrada com telemetria real (distribuição de peso por motor dianteiro, central ou traseiro).\n\n" +
			"Arcade (2,0×): pneus com 2× mais aderência, direção ampliada e carros não capotam.\n\n" +
			"Assistências: 1 = ABS · 2 = Controle de Tração · G = Câmbio Automático. Cada modo possui ranking próprio."
		],
		[
			"🏁 PISTA & REGRAS",
			"Circuito: Autódromo José Carlos Pace (Interlagos) · 4.309 m · 15 curvas · 3 setores cronometrados.\n\n" +
			"Limites de pista: sair com as 4 rodas fora da pista/zebra invalida a volta atual.\n\n" +
			"Licença DR/SR: seus melhores tempos válidos em Interlagos evoluem sua licença de Rookie até Pro (S)."
		],
	]

	for cd in cards_data:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SUBTLE, 6, 14, 12))
		cards_host.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(LmuTheme.make_label(cd[0], roundi((13 if is_compact else 16) * fs), Color.WHITE, 800))
		var body_lbl := LmuTheme.make_label(cd[1], roundi((11 if is_compact else 13) * fs), LmuTheme.TEXT_SLATE, 500)
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(body_lbl)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(footer)
	var back_btn := Button.new()
	back_btn.text = "VOLTAR AO MENU"
	back_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 14, 6)
	back_btn.pressed.connect(func(): switch_view("home"))
	footer.add_child(back_btn)


# ------------------------------------------------------------------ AÇÕES COMPARTILHADAS

func _set_mode(m: String) -> void:
	if not (m in Game.MODES):
		m = "sim"
	if m == current_mode:
		return
	current_mode = m
	records_mode = m
	Game.set_mode(m)
	mode_changed.emit(m)
	_rebuild_all()

