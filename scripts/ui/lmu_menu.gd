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

const VIEWS := ["home", "cars", "tracks", "settings", "records", "help"]
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


## Desenho do traçado de uma pista (cartões de pista do menu): contorno com brilho e o ponto da largada.
class _TrackOutline extends Control:
	var pts: Array = []
	var color := Color("#fbbf24")

	func _draw() -> void:
		if pts.size() < 3:
			return
		var side := minf(size.x, size.y) - 10.0
		var c := size * 0.5
		var line := PackedVector2Array()
		for p in pts:
			line.append(c + Vector2(p) * side)
		line.append(line[0])
		draw_polyline(line, Color(color, 0.22), 7.0, true)
		draw_polyline(line, color, 2.6, true)
		draw_circle(line[0], 4.5, Color(color, 0.35))
		draw_circle(line[0], 2.6, Color.WHITE)


## Mapa grande da pista (tela "Trocar pista"): traçado nas cores dos 3 setores (terços da volta, como o LapTimer),
## largada e o nome de cada trecho. Os dados vêm do track.json de cada pista (cache por id).
class _TrackMap extends Control:
	const SECTOR_COLORS := [Color("#ff3b30"), Color("#f2c230"), Color("#3d8bff")]
	static var _cache := {}
	var track_id := ""
	var font_size := 12

	## pontos normalizados [-0.5, 0.5], s de cada ponto, comprimento, desnível e trechos com nome
	static func data_for(id: String) -> Dictionary:
		if _cache.has(id):
			return _cache[id]
		var out := {"pts": [], "s": [], "length": 0.0, "drop": 0.0, "sections": []}
		var path := String(Game.get_track_info(id).get("data_dir", "")) + "track.json"
		var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if d is Dictionary:
			var n := int(d.n)
			var st := int(d.stride)
			var s: Array = d.s
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			var ylo := INF
			var yhi := -INF
			var raw: Array = []
			var k := maxi(1, n / 400)
			for i in range(0, n, k):
				var v := Vector2(s[i * st], s[i * st + 2])
				raw.append(v)
				out.s.append(i * Track.STEP)
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
			for i in n:
				ylo = minf(ylo, float(s[i * st + 1]))
				yhi = maxf(yhi, float(s[i * st + 1]))
			var span := maxf(hi.x - lo.x, hi.y - lo.y)
			var mid := (lo + hi) * 0.5
			for v in raw:
				out.pts.append((v - mid) / span)
			out.length = n * Track.STEP
			out.drop = yhi - ylo
			out.sections = d.get("sections", [])
			# Interlagos: o mesmo traçado oficial dos cartões e do load (já começa na largada, no sentido da
			# corrida); o s de cada ponto vem do comprimento acumulado
			if id == "interlagos":
				var off: Array = LoadingScreen.outline_for(id)
				var acc := [0.0]
				for i in range(1, off.size()):
					acc.append(float(acc[i - 1]) + Vector2(off[i]).distance_to(Vector2(off[i - 1])))
				var total := float(acc[acc.size() - 1]) + Vector2(off[0]).distance_to(Vector2(off[off.size() - 1]))
				out.pts = off
				out.s = acc.map(func(a): return float(a) / total * float(out.length))
		_cache[id] = out
		return out

	func _pt_at(dat: Dictionary, s_at: float, c: Vector2, side: float) -> Vector2:
		var ss: Array = dat.s
		var j := clampi(int(s_at / maxf(1.0, float(dat.length)) * ss.size()), 0, ss.size() - 1)
		return c + Vector2(dat.pts[j]) * side

	func _draw() -> void:
		var dat := data_for(track_id)
		var pts: Array = dat.pts
		if pts.size() < 3:
			return
		var side := minf(size.x, size.y) - 70.0
		var c := size * 0.5
		var L := float(dat.length)
		var ss: Array = dat.s
		# brilho por baixo, depois cada setor na sua cor
		var all := PackedVector2Array()
		for p in pts:
			all.append(c + Vector2(p) * side)
		all.append(all[0])
		draw_polyline(all, Color(1, 1, 1, 0.08), 14.0, true)
		for k in 3:
			var seg := PackedVector2Array()
			for i in pts.size() + 1:
				var j := i % pts.size()
				var s_i := float(ss[j]) if i < pts.size() else L
				if s_i >= L * k / 3.0 - 0.01 and s_i <= L * (k + 1) / 3.0 + L / pts.size() * 1.5:
					seg.append(all[i])
			if seg.size() >= 2:
				draw_polyline(seg, Color(SECTOR_COLORS[k], 0.25), 9.0, true)
				draw_polyline(seg, SECTOR_COLORS[k], 3.5, true)
		# nomes dos trechos, para fora do traçado
		var font := get_theme_default_font()
		for sec in dat.sections:
			var s0 := float(sec.s0)
			var s1 := float(sec.s1)
			if s1 < s0:
				s1 += L
			var p := _pt_at(dat, fmod((s0 + s1) * 0.5, L), c, side)
			var dir := (p - c).normalized()
			var name := String(sec.name).replace("Curva ", "T")
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var at := p + dir * 16.0 - Vector2(w * 0.5, -font_size * 0.35)
			at.x = clampf(at.x, 2.0, size.x - w - 2.0)
			draw_circle(p, 2.5, Color(1, 1, 1, 0.8))
			draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.78))
		# largada
		draw_circle(all[0], 7.0, Color(1, 1, 1, 0.3))
		draw_circle(all[0], 4.0, Color.WHITE)
		draw_string(font, all[0] + Vector2(10, -8), "LARGADA", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


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
var current_car_id := "corvette-c6r-gt3"
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
var _pause_studio_container: SubViewportContainer
var _pause_studio_vp: SubViewport
var _pause_studio: CarStudioView
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
	if _pause_studio != null and is_instance_valid(_pause_studio):
		_pause_studio.show_car_by_id(car_id)
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
	if view == "tracks":
		_track_pick = Game.track_id
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
	return active_view == "cars"


func cleanup_pause_studio() -> void:
	if _pause_studio_container != null and is_instance_valid(_pause_studio_container):
		_pause_studio_container.queue_free()
	_pause_studio_container = null
	_pause_studio_vp = null
	_pause_studio = null


func _sync_pause_studio(vp_size: Vector2) -> void:
	var need_studio := (context == Context.PAUSE and active_view == "cars" and visible)
	if not need_studio:
		cleanup_pause_studio()
		return
	if _pause_studio_container == null or not is_instance_valid(_pause_studio_container):
		_pause_studio_container = SubViewportContainer.new()
		_pause_studio_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pause_studio_container.stretch = true
		_pause_studio_container.mouse_filter = Control.MOUSE_FILTER_STOP
		_pause_studio_container.gui_input.connect(func(e: InputEvent):
			if _pause_studio != null and is_instance_valid(_pause_studio):
				_pause_studio.handle_drag_event(e)
		)
		add_child(_pause_studio_container)
		move_child(_pause_studio_container, 1)

		_pause_studio_vp = SubViewport.new()
		_pause_studio_vp.own_world_3d = true
		_pause_studio_vp.transparent_bg = false
		_pause_studio_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_pause_studio_vp.msaa_3d = Viewport.MSAA_2X if Game.get_quality_level() >= 2 else Viewport.MSAA_DISABLED
		_pause_studio_container.add_child(_pause_studio_vp)

		_pause_studio = CarStudioView.new()
		_pause_studio_vp.add_child(_pause_studio)
		_pause_studio.setup(cars, current_car_id, false, false)
		_pause_studio.show_car_by_id(current_car_id)

	if _pause_studio != null and is_instance_valid(_pause_studio):
		_pause_studio.set_cars_framing(true, vp_size)


func _rebuild_all() -> void:
	if _root_vbox == null:
		return
	if layout_profile.is_empty():
		layout_profile = LmuTheme.compute_layout_profile(Vector2(1920.0, 1080.0), Game.is_mobile_platform() or is_touch_device)
	var vp_size := Vector2(layout_profile.get("viewport_size", Vector2(1920.0, 1080.0)))
	_sync_full_rect(vp_size)
	_sync_pause_studio(vp_size)

	var transparent_center := _is_transparent_studio_view()
	var has_pause_studio := (_pause_studio_container != null and is_instance_valid(_pause_studio_container))
	_backdrop.visible = not transparent_center
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE if transparent_center else Control.MOUSE_FILTER_STOP
	mouse_filter = Control.MOUSE_FILTER_IGNORE if (transparent_center and not has_pause_studio) else Control.MOUSE_FILTER_STOP

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
			var b1 := LmuTheme.make_label("CIRCUITO: " + Game.track_name().to_upper(), roundi(13 * fs), LmuTheme.TEXT_MUTED, 700)
			var sep := LmuTheme.make_label(" / ", roundi(13 * fs), LmuTheme.TEXT_DIM, 600)
			var b2 := LmuTheme.make_label("GARAGEM 3D · CARROS", roundi(13 * fs), Color.WHITE, 800)
			_header_center.add_child(b1)
			_header_center.add_child(sep)
			_header_center.add_child(b2)
		elif active_view == "tracks":
			_header_center.add_child(LmuTheme.make_label("SELEÇÃO DE PISTA", roundi(13 * fs), Color.WHITE, 800))
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
			var circ := LmuTheme.make_label(_track_header_text(), roundi(12 * fs), LmuTheme.TEXT_SLATE, 700)
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
	gear_btn.custom_minimum_size = Vector2(roundi((28 if compact else 34) * fs), roundi((28 if compact else 32) * fs))
	gear_btn.add_theme_font_size_override("font_size", roundi((13 if compact else 15) * fs))
	LmuTheme.apply_button_styles(gear_btn, "active" if active_view == "settings" else "outline", 4, 6, 2)
	gear_btn.pressed.connect(func(): switch_view("settings"))
	right.add_child(gear_btn)

	if context == Context.PAUSE:
		var close_btn := Button.new()
		close_btn.text = "✕"
		close_btn.tooltip_text = "Voltar para a pista (Esc)"
		close_btn.custom_minimum_size = Vector2(roundi((28 if compact else 34) * fs), roundi((28 if compact else 32) * fs))
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
		"tracks":
			_build_tracks_view()
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
	btn.custom_minimum_size = Vector2(0, roundi(((28 if sub_mode else 34) if is_compact else (34 if sub_mode else 44)) * fs))
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
	bar.custom_minimum_size = Vector2(3 if is_compact else 4, roundi(((16 if sub_mode else 20) if is_compact else (20 if sub_mode else 28)) * fs))
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

# ------------------------------------------------------------------ pista (data/tracks.json)

## textos da pista atual; Interlagos mantém exatamente os de antes do multi-pista
func _track_header_text() -> String:
	if Game.track_id == Game.DEFAULT_TRACK:
		return "AUTÓDROMO DE INTERLAGOS · SÃO PAULO"
	var t := Game.get_track_info()
	return "%s · %s" % [String(t.get("name", "")).to_upper(), String(t.get("country", "")).to_upper()]


func _track_hero_text() -> String:
	if Game.track_id == Game.DEFAULT_TRACK:
		return "AUTÓDROMO DE INTERLAGOS · 4.309 M"
	var t := Game.get_track_info()
	return "%s · %s M" % [String(t.get("name", "")).to_upper(), _thousands(int(t.get("length_m", 0)))]


func _track_help_text() -> String:
	var limits := "Limites de pista: sair com as 4 rodas fora da pista/zebra invalida a volta atual.

"
	if Game.track_id == Game.DEFAULT_TRACK:
		return ("Circuito: Autódromo José Carlos Pace (Interlagos) · 4.309 m · 15 curvas · 3 setores cronometrados.

" +
			limits + "Licença DR/SR: seus melhores tempos válidos em Interlagos evoluem sua licença de Rookie até Pro (S).")
	var t := Game.get_track_info()
	return ("Circuito: %s · %s m · %d curvas · 3 setores cronometrados.

" % [t.get("name", ""),
		_thousands(int(t.get("length_m", 0))), int(t.get("corners", 0))] + limits +
		"Cada pista tem recordes e ranking próprios.")


static func _thousands(v: int) -> String:
	var txt := str(v)
	return txt if txt.length() <= 3 else txt.left(txt.length() - 3) + "." + txt.right(3)


# ------------------------------------------------------------------ cartões da home e troca de pista

## Painel clicável (cartões da home e lista de pistas): realça a borda ao passar o mouse; no toque, o Godot
## emula o mouse, então basta o clique.
func _make_click_card(on_click: Callable, accent: Color, enabled := true, selected := false) -> PanelContainer:
	var card := PanelContainer.new()
	var base := LmuTheme.panel_style(Color(accent, 0.12) if selected else Color(LmuTheme.BG_PANEL, 0.82),
		accent if selected else LmuTheme.BORDER_SUBTLE, 8, 0, 0)
	base.set_border_width_all(2 if selected else 1)
	var hover := base.duplicate() as StyleBoxFlat
	hover.border_color = accent
	hover.bg_color = Color(accent, 0.16) if selected else Color(LmuTheme.BG_CHIP_HOVER, 0.92)
	card.add_theme_stylebox_override("panel", base)
	if enabled:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover))
		card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", base))
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				on_click.call()
		)
	return card


func _card_margin(card: Control, is_compact: bool) -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + side, 12 if is_compact else 18)
	for side in ["top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 8 if is_compact else 14)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4 if is_compact else 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(v)
	return v


func _card_header(parent: Control, title: String, action: String, is_compact: bool, fs: float) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var t := LmuTheme.make_label(title, roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_MUTED, 700)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	if action != "":
		row.add_child(LmuTheme.make_label(action, roundi((9 if is_compact else 11) * fs), LmuTheme.ACCENT_RED_BRIGHT, 800))


## melhor volta do piloto numa pista (qualquer carro, ou só car_id) e modo. Os recordes ficam por pista e o
## Records lê os da pista atual: troca Game.track_id só durante a leitura, sem gravar nada.
func _track_best(track_id: String, mode: String, car_id := "") -> Dictionary:
	var prev := Game.track_id
	Game.track_id = track_id
	var recs := Records.load_all(mode)
	Game.track_id = prev
	var nick := current_nick.strip_edges().to_lower()
	var best := {}
	for r in recs:
		if not (r is Dictionary):
			continue
		if car_id != "" and String(r.get("carId", "")) != car_id:
			continue
		if nick != "" and String(r.get("nick", "")).strip_edges().to_lower() != nick:
			continue
		if best.is_empty() or float(r.get("time", INF)) < float(best.get("time", INF)):
			best = r
	return best


## linha "SIMULADOR 1:21.400 · ARCADE 1:04.333" (com o carro embaixo, se pedir)
func _times_row(parent: Control, sim: Dictionary, arc: Dictionary, show_car: bool, is_compact: bool, fs: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if is_compact else 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	for e in [["SIMULADOR", sim, LmuTheme.ACCENT_GREEN], ["ARCADE", arc, LmuTheme.ACCENT_AMBER]]:
		var rec: Dictionary = e[1]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		col.add_child(LmuTheme.make_label(e[0], roundi((8 if is_compact else 10) * fs), Color(e[2], 0.85), 800))
		var has := not rec.is_empty()
		col.add_child(LmuTheme.make_label(LapTimer.format_time(float(rec.time)) if has else "--:--.---",
			roundi((13 if is_compact else 17) * fs), Color.WHITE if has else LmuTheme.TEXT_DIM, 800))
		if show_car and has:
			var cn := String(Game.get_car_info(String(rec.get("carId", ""))).get("short", rec.get("carId", "")))
			col.add_child(LmuTheme.make_label(cn.to_upper(), roundi((8 if is_compact else 10) * fs), LmuTheme.TEXT_MUTED, 700))


func _build_car_card(is_compact: bool, fs: float) -> PanelContainer:
	var c := current_car()
	var c_col := Color(String(c.get("color", "#e10600")))
	var card := _make_click_card(func(): switch_view("cars"), c_col)
	card.clip_contents = true
	var v := _card_margin(card, is_compact)
	_card_header(v, "CARRO", "TROCAR ➔", is_compact, fs)
	var brand := LmuTheme.make_label(String(c.get("brand", "GT3")).to_upper(), roundi((10 if is_compact else 12) * fs), c_col.lightened(0.15), 800)
	v.add_child(brand)
	v.add_child(LmuTheme.make_label(String(c.get("name", current_car_id)), roundi((17 if is_compact else 24) * fs), Color.WHITE, 800))
	var specs := LmuTheme.make_label("%s · %d CV · %d KG" % [String(c.get("engine", "GT3")).to_upper(), int(c.get("power", 565)), int(c.get("weight", 1250))],
		roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_SLATE, 700)
	specs.clip_text = true
	v.add_child(specs)
	v.add_child(_make_h_divider(0.10))
	_times_row(v, _track_best(Game.track_id, "sim", current_car_id), _track_best(Game.track_id, "arcade", current_car_id), false, is_compact, fs)
	return card


func _build_track_card(is_compact: bool, fs: float) -> PanelContainer:
	var t := Game.get_track_info()
	var gold := Color("#fbbf24")
	var can := context != Context.PAUSE and Game.get_available_tracks().size() > 1
	var card := _make_click_card(func(): switch_view("tracks"), gold, can)
	var v := _card_margin(card, is_compact)
	_card_header(v, "PISTA", "TROCAR ➔" if can else "", is_compact, fs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10 if is_compact else 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var draw := _TrackOutline.new()
	draw.pts = LoadingScreen.outline_for(Game.track_id)
	draw.color = gold
	draw.custom_minimum_size = Vector2.ONE * (58.0 if is_compact else 92.0) * fs
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(draw)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	info.add_child(LmuTheme.make_label(String(t.get("short", Game.track_id)).to_upper(), roundi((17 if is_compact else 24) * fs), Color.WHITE, 800))
	var loc := LmuTheme.make_label(String(t.get("location", t.get("country", ""))).to_upper(), roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_SLATE, 700)
	loc.clip_text = true
	info.add_child(loc)
	info.add_child(LmuTheme.make_label("%s M · %d CURVAS" % [_thousands(int(t.get("length_m", 0))), int(t.get("corners", 0))],
		roundi((9 if is_compact else 11) * fs), gold, 700))
	v.add_child(_make_h_divider(0.10))
	_times_row(v, _track_best(Game.track_id, "sim"), _track_best(Game.track_id, "arcade"), true, is_compact, fs)
	return card


## pista escolhida na tela "Trocar pista" e ainda não confirmada
var _track_pick := ""


func _build_tracks_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_portrait: bool = (lp.profile == "portrait")
	var is_compact: bool = bool(lp.get("is_compact_mobile", false))
	if _track_pick == "" or not Game.is_track_available(_track_pick):
		_track_pick = Game.track_id
	var gold := Color("#fbbf24")
	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer
	var main: BoxContainer = VBoxContainer.new() if is_portrait else HBoxContainer.new()
	main.add_theme_constant_override("separation", 10 if is_compact else 20)
	outer.add_child(main)

	# lista de pistas
	var list: BoxContainer = HBoxContainer.new() if is_portrait else VBoxContainer.new()
	list.add_theme_constant_override("separation", 6 if is_compact else 10)
	list.custom_minimum_size.x = 0.0 if is_portrait else (210.0 if is_compact else 300.0) * fs
	main.add_child(list)
	if not is_portrait:
		list.add_child(LmuTheme.make_label("PISTAS", roundi((10 if is_compact else 12) * fs), LmuTheme.TEXT_MUTED, 800))
	for t in Game.get_available_tracks():
		var id := String(t.id)
		var item := _make_click_card(_select_track_pick.bind(id), gold, true, id == _track_pick)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_portrait else Control.SIZE_FILL
		list.add_child(item)
		var mc := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			mc.add_theme_constant_override("margin_" + side, 6 if is_compact else 10)
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(mc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8 if is_compact else 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(row)
		var draw := _TrackOutline.new()
		draw.pts = LoadingScreen.outline_for(id)
		draw.color = gold if id == _track_pick else Color("#94a3b8")
		draw.custom_minimum_size = Vector2.ONE * (40.0 if is_compact else 60.0) * fs
		draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(draw)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		col.add_child(LmuTheme.make_label(String(t.get("short", id)).to_upper(), roundi((12 if is_compact else 16) * fs), Color.WHITE, 800))
		col.add_child(LmuTheme.make_label(String(t.get("country", "")).to_upper(), roundi((8 if is_compact else 10) * fs), LmuTheme.TEXT_MUTED, 700))
		if id == Game.track_id:
			col.add_child(LmuTheme.make_label("ATUAL", roundi((8 if is_compact else 10) * fs), LmuTheme.ACCENT_GREEN, 800))

	# mapa grande da pista destacada
	var map := _TrackMap.new()
	map.track_id = _track_pick
	map.font_size = roundi((9 if is_compact else 12) * fs)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(0, 240.0 * fs) if is_portrait else Vector2.ZERO
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(map)

	# ficha + confirmar
	var t := Game.get_track_info(_track_pick)
	var dat := _TrackMap.data_for(_track_pick)
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(LmuTheme.BG_PANEL, 0.9), LmuTheme.BORDER_SUBTLE, 8, 0, 0))
	info.custom_minimum_size.x = 0.0 if is_portrait else (250.0 if is_compact else 340.0) * fs
	main.add_child(info)
	var v := _card_margin(info, is_compact)
	var name_lbl := LmuTheme.make_label(String(t.get("name", _track_pick)).to_upper(), roundi((14 if is_compact else 20) * fs), Color.WHITE, 800)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_lbl)
	v.add_child(LmuTheme.make_label(String(t.get("location", t.get("country", ""))).to_upper(), roundi((9 if is_compact else 11) * fs), LmuTheme.TEXT_SLATE, 700))
	v.add_child(_make_h_divider(0.10))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	v.add_child(grid)
	for e in [["COMPRIMENTO", "%s M" % _thousands(int(t.get("length_m", 0)))], ["CURVAS", str(int(t.get("corners", 0)))],
			["DESNÍVEL", "%d M" % roundi(float(dat.drop))]]:
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 0)
		sv.add_child(LmuTheme.make_label(e[0], roundi((8 if is_compact else 10) * fs), LmuTheme.TEXT_DIM, 700))
		sv.add_child(LmuTheme.make_label(e[1], roundi((12 if is_compact else 16) * fs), Color.WHITE, 800))
		grid.add_child(sv)
	v.add_child(_make_h_divider(0.10))
	v.add_child(LmuTheme.make_label("SEUS MELHORES TEMPOS", roundi((8 if is_compact else 10) * fs), LmuTheme.TEXT_MUTED, 800))
	_times_row(v, _track_best(_track_pick, "sim"), _track_best(_track_pick, "arcade"), true, is_compact, fs)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)
	var ok_btn := Button.new()
	ok_btn.text = "CONFIRMAR PISTA" if _track_pick != Game.track_id else "MANTER PISTA ATUAL"
	ok_btn.custom_minimum_size.y = roundi((34 if is_compact else 46) * fs)
	ok_btn.add_theme_font_size_override("font_size", roundi((12 if is_compact else 15) * fs))
	LmuTheme.apply_button_styles(ok_btn, "primary", 4, 12, 6)
	ok_btn.pressed.connect(_confirm_track_pick)
	v.add_child(ok_btn)
	var back_btn := Button.new()
	back_btn.text = "VOLTAR"
	back_btn.custom_minimum_size.y = roundi((28 if is_compact else 36) * fs)
	back_btn.add_theme_font_size_override("font_size", roundi((11 if is_compact else 13) * fs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 12, 4)
	back_btn.pressed.connect(func():
		_track_pick = ""
		switch_view("home")
	)
	v.add_child(back_btn)


func _select_track_pick(id: String) -> void:
	_track_pick = id
	_rebuild_view()


## confirma a pista escolhida (só aqui ela muda e é salva) e volta para a home
func _confirm_track_pick() -> void:
	if _track_pick != "" and _track_pick != Game.track_id:
		Game.set_track(_track_pick)
	_track_pick = ""
	switch_view("home")
func _build_home_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var is_portrait: bool = (lp.profile == "portrait")
	var is_compact: bool = bool(lp.get("is_compact_mobile", false))
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

	# o menu escrito fica maior: carro e pista viraram cartões na coluna da direita
	var hs := fs * (1.1 if is_compact else 1.25)
	var title_lbl := LmuTheme.make_label("GT3 TIME ATTACK", roundi((28 if is_compact else 54) * fs), Color.WHITE, 800, true)
	left_col.add_child(title_lbl)

	var nav_spacer := Control.new()
	nav_spacer.custom_minimum_size.y = 4 if is_compact else 12
	left_col.add_child(nav_spacer)

	var nav_list := VBoxContainer.new()
	nav_list.add_theme_constant_override("separation", 2 if is_compact else 4)
	left_col.add_child(nav_list)

	var primary_title := "CONTINUAR NA PISTA" if context == Context.PAUSE else "RACE WEEKEND"
	var primary_item := _make_home_nav_item(primary_title, Color.WHITE, LmuTheme.ACCENT_RED, true, hs, is_compact)
	primary_item.pressed.connect(func():
		if context == Context.PAUSE:
			resumed.emit()
		else:
			drive_requested.emit()
	)
	nav_list.add_child(primary_item)

	if context == Context.PAUSE:
		var restart_item := _make_home_nav_item("REINICIAR VOLTA", LmuTheme.ACCENT_AMBER, LmuTheme.ACCENT_AMBER, true, hs, is_compact)
		restart_item.pressed.connect(func(): restart_requested.emit())
		nav_list.add_child(restart_item)

	var nav_entries := [["TROCAR CARRO", "cars"]]
	# na pista não troca de pista (exigiria recarregar tudo)
	if context != Context.PAUSE:
		nav_entries.append(["TROCAR PISTA", "tracks"])
	nav_entries.append_array([["CONFIGURAÇÕES", "settings"], ["RECORDES", "records"], ["COMO JOGAR", "help"]])
	for item in nav_entries:
		var v_id: String = item[1]
		var nbtn := _make_home_nav_item(item[0], LmuTheme.TEXT_WHITE, LmuTheme.ACCENT_RED, false, hs, is_compact)
		nbtn.pressed.connect(func(): switch_view(v_id))
		nav_list.add_child(nbtn)

	if context == Context.PAUSE:
		var gar_item := _make_home_nav_item("GARAGEM 3D", LmuTheme.TEXT_SLATE, LmuTheme.ACCENT_RED, false, hs, is_compact, true)
		gar_item.pressed.connect(func(): garage_requested.emit())
		nav_list.add_child(gar_item)

	var quit_item := _make_home_nav_item("SAIR DO JOGO" if context != Context.PAUSE else "SAIR", LmuTheme.TEXT_MUTED, LmuTheme.ACCENT_RED, false, hs, is_compact, true)
	quit_item.pressed.connect(func(): quit_requested.emit())
	nav_list.add_child(quit_item)

	# Espaçador central em desktop/tablet/mobile_landscape para empurrar os cartões para a direita
	if not is_portrait:
		var mid_sp := Control.new()
		mid_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(mid_sp)

	# Coluna Direita: cartão do carro em cima e da pista embaixo (os dois abrem a troca)
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size.x = float(lp.home_right_width) if not is_portrait else 0.0
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_portrait else Control.SIZE_SHRINK_END
	right_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_col.add_theme_constant_override("separation", 8 if is_compact else 14)
	host.add_child(right_col)
	right_col.add_child(_build_car_card(is_compact, fs))
	right_col.add_child(_build_track_card(is_compact, fs))


# ------------------------------------------------------------------ CARS VIEW (GARAGE 3D LAYOUT)

func _build_cars_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var cfs := fs * float(lp.get("ui_scale", 1.0))
	var is_portrait: bool = (lp.profile == "portrait")
	var is_compact: bool = bool(lp.get("is_compact_mobile", false))
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
	mv.add_child(LmuTheme.make_label("MODO DE PILOTAGEM", roundi((10 if is_compact else 12) * cfs), LmuTheme.TEXT_MUTED, 700))

	var mgrid := HBoxContainer.new()
	mgrid.add_theme_constant_override("separation", 6)
	mv.add_child(mgrid)
	for m_entry in [["sim", "SIMULADOR", "Física real 1,0×"], ["arcade", "ARCADE", "2,0× aderência"]]:
		var m_id: String = m_entry[0]
		var mb := Button.new()
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.custom_minimum_size.y = roundi((34 if is_compact else 48) * float(lp.get("ui_scale", 1.0)))
		LmuTheme.apply_button_styles(mb, "active" if current_mode == m_id else "outline", 4, 6, 4)
		mb.pressed.connect(func(): _set_mode(m_id))
		var mbv := VBoxContainer.new()
		mbv.set_anchors_preset(Control.PRESET_FULL_RECT)
		mbv.alignment = BoxContainer.ALIGNMENT_CENTER
		mbv.add_theme_constant_override("separation", 0)
		mbv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mb.add_child(mbv)
		var mn := LmuTheme.make_label(m_entry[1], roundi((11 if is_compact else 13.5) * cfs), Color.WHITE, 800)
		mn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mbv.add_child(mn)
		if not is_compact:
			var md := LmuTheme.make_label(m_entry[2], roundi(10.5 * cfs), LmuTheme.TEXT_MUTED, 500)
			md.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mbv.add_child(md)
		mgrid.add_child(mb)

	# 2. Ficha Técnica (5 linhas no desktop, 4 no mobile landscape ocultando Downforce)
	var specs_sec := PanelContainer.new()
	specs_sec.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SUBTLE, 6, 10 if is_compact else 14, 6 if is_compact else 10))
	panel_col.add_child(specs_sec)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3 if is_compact else 6)
	specs_sec.add_child(sv)
	sv.add_child(LmuTheme.make_label("FICHA TÉCNICA DO GT3", roundi((10 if is_compact else 12) * cfs), LmuTheme.TEXT_MUTED, 700))

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
		var kl := LmuTheme.make_label(sk[1], roundi((11 if is_compact else 13.5) * cfs), LmuTheme.TEXT_MUTED, 500)
		kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sr.add_child(kl)
		var vl := LmuTheme.make_label("--", roundi((11 if is_compact else 13.5) * cfs), Color.WHITE, 700)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sr.add_child(vl)
		_car_spec_vals[sk[0]] = vl

	# 3. Melhor Tempo Pessoal
	var pb_sec := PanelContainer.new()
	pb_sec.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, Color(LmuTheme.ACCENT_GREEN.r, LmuTheme.ACCENT_GREEN.g, LmuTheme.ACCENT_GREEN.b, 0.42), 6, 10 if is_compact else 14, 6 if is_compact else 10))
	panel_col.add_child(pb_sec)
	var pbv := VBoxContainer.new()
	pbv.add_theme_constant_override("separation", 2)
	pb_sec.add_child(pbv)
	pbv.add_child(LmuTheme.make_label("SEU MELHOR TEMPO", roundi((10 if is_compact else 12) * cfs), LmuTheme.TEXT_MUTED, 700))

	if bool(lp.cars_pb_horizontal):
		var pbh := HBoxContainer.new()
		pbv.add_child(pbh)
		_car_pb_time_lbl = LmuTheme.make_label("--:--.---", roundi(16 * cfs), LmuTheme.ACCENT_GREEN, 800)
		_car_pb_time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbh.add_child(_car_pb_time_lbl)
		_car_pb_sub_lbl = LmuTheme.make_label("", roundi(10.5 * cfs), LmuTheme.TEXT_MUTED, 500)
		pbh.add_child(_car_pb_sub_lbl)
	else:
		_car_pb_time_lbl = LmuTheme.make_label("--:--.---", roundi(24 * cfs), LmuTheme.ACCENT_GREEN, 800)
		pbv.add_child(_car_pb_time_lbl)
		_car_pb_sub_lbl = LmuTheme.make_label("", roundi(11.5 * cfs), LmuTheme.TEXT_MUTED, 500)
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
		fb.add_theme_font_size_override("font_size", roundi((11 if is_compact else 12.5) * cfs))
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
	_drive_btn.custom_minimum_size.y = 42 if is_compact else 48
	_drive_btn.add_theme_font_size_override("font_size", roundi((13 if is_compact else 16) * fs))
	LmuTheme.apply_button_styles(_drive_btn, "primary", 4, 18 if is_compact else 24, 6 if is_compact else 8)
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
		var chip := _create_car_chip(c, ccol, chip_h, is_compact, cfs)
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

	if chip_h >= 46:
		var br := LmuTheme.make_label(String(c.get("brand", c.get("short", ""))), roundi(10.5 * fs), LmuTheme.TEXT_MUTED, 700)
		br.clip_text = true
		box.add_child(br)
	var nm := LmuTheme.make_label(String(c.get("name", cid)), roundi((12 if is_compact else 13.5) * fs), Color.WHITE, 700)
	nm.clip_text = true
	box.add_child(nm)
	var ly := LmuTheme.make_label(String(c.get("layout", "")).to_upper(), roundi((9.5 if is_compact else 10.5) * fs), ccol.lightened(0.25), 700)
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
	var ui_s := float(lp.get("ui_scale", 1.0))
	var cfs := fs * ui_s
	var is_compact: bool = bool(lp.get("is_compact_mobile", false))

	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10 if is_compact else 16)
	outer.add_child(col)

	# Barra horizontal das 5 abas (underline LMU)
	var tab_bar_wrap := VBoxContainer.new()
	tab_bar_wrap.add_theme_constant_override("separation", 0)
	col.add_child(tab_bar_wrap)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6 if is_compact else 12)
	tab_bar_wrap.add_child(tab_bar)

	for tab_id in SETTINGS_TABS:
		var tb := Button.new()
		tb.text = SETTINGS_TAB_LABELS[tab_id]
		tb.custom_minimum_size.y = roundi((40 if is_compact else 48) * cfs)
		tb.add_theme_font_size_override("font_size", roundi((13 if is_compact else 15) * cfs))
		LmuTheme.apply_button_styles(tb, "tab_active" if active_settings_tab == tab_id else "tab_idle", 0, 14 if is_compact else 18, 8 if is_compact else 10)
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
		_settings_search_edit.custom_minimum_size.y = roundi(38 * cfs)
		_settings_search_edit.add_theme_font_size_override("font_size", roundi(13.5 * cfs))
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
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8 if is_compact else 12)
	scroll.add_child(content)

	_populate_settings_tab(content, is_compact, cfs)

	_settings_empty_lbl = LmuTheme.make_label("Nenhuma configuração encontrada nesta aba para a busca atual.", roundi(14 * cfs), LmuTheme.TEXT_MUTED, 500)
	_settings_empty_lbl.visible = false
	content.add_child(_settings_empty_lbl)

	_apply_settings_filter()

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(footer)
	var back_btn := Button.new()
	back_btn.text = "APLICAR & VOLTAR"
	back_btn.custom_minimum_size = Vector2(roundi(190 * cfs), roundi((42 if is_compact else 48) * cfs))
	back_btn.add_theme_font_size_override("font_size", roundi((13 if is_compact else 14) * cfs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 18, 8)
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
	var is_mobile_ui := float(layout_profile.get("ui_scale", 1.0)) > 1.05
	var pad_v := 8 if is_compact else (14 if is_mobile_ui else 10)
	row_panel.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(1, 1, 1, 0.03), LmuTheme.BORDER_SOFT, 6, 16 if is_mobile_ui else 12, pad_v))
	if is_mobile_ui and not is_compact:
		row_panel.custom_minimum_size.y = roundi(62 * fs)
	parent.add_child(row_panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row_panel.add_child(h)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4 if is_mobile_ui else 2)
	h.add_child(info)
	info.add_child(LmuTheme.make_label(title, roundi((14 if is_compact else 16) * fs), Color.WHITE, 700))
	var dl := LmuTheme.make_label(desc, roundi((11 if is_compact else 13) * fs), LmuTheme.TEXT_MUTED, 500)
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
	p.add_theme_stylebox_override("panel", LmuTheme.panel_style(Color(1, 1, 1, 0.08), border, 4, 12, 6))
	p.add_child(LmuTheme.make_label(txt, roundi(13 * fs), col, 700))
	return p


func _populate_settings_tab(parent: Control, is_compact: bool, fs: float) -> void:
	match active_settings_tab:
		"controls":
			parent.add_child(LmuTheme.make_label("DISPOSITIVOS & ENTRADA", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			var show_touch := is_touch_device or OS.has_feature("mobile")

			var touch_opt := OptionButton.new()
			touch_opt.custom_minimum_size = Vector2(roundi(165 * fs), roundi(36 * fs))
			touch_opt.add_theme_font_size_override("font_size", roundi(13 * fs))
			touch_opt.get_popup().add_theme_font_size_override("font_size", roundi(13 * fs))
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

			# controle e teclado configuráveis (scripts/ui/controls_panel.gd + scripts/input/bindings.gd)
			var cp := ControlsPanel.new(fs)
			parent.add_child(cp)
			var show_kb := not OS.has_feature("mobile")
			_add_setting_row(
				parent,
				"Controle / Gamepad",
				"Qual aparelho o jogo lê. No automático vale o último controle que você mexer (útil quando o Windows lista controles virtuais do Steam/DS4Windows, volantes ou headsets).",
				"controle gamepad joystick xbox playstation bluetooth aparelho dispositivo",
				cp.make_device_picker(),
				is_compact,
				fs
			)
			_add_setting_row(
				parent,
				"Teste do Controle",
				"Mexa o analógico e os gatilhos: as barras mostram o que o jogo está recebendo.",
				"teste controle gamepad analogico gatilho diagnostico",
				cp.make_live_view(),
				is_compact,
				fs
			)
			if show_kb:
				var kb_row := _add_setting_row(
					parent,
					"Comandos de Teclado",
					cp.keyboard_summary(),
					"teclado comandos atalhos wasd",
					_make_badge("ATIVO", LmuTheme.ACCENT_GREEN, LmuTheme.ACCENT_GREEN, fs),
					is_compact,
					fs
				)
				var labels := kb_row.find_children("*", "Label", true, false)
				if labels.size() >= 2:
					cp.set_keyboard_label(labels[1])

			parent.add_child(LmuTheme.make_label("COMANDOS (CLIQUE PARA TROCAR · ESC CANCELA)", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			for action in Bindings.ACTIONS:
				_add_setting_row(
					parent,
					Bindings.NAMES[action],
					"Eixo ou botão" if action in Bindings.ANALOG else "Botão",
					"comando mapear remapear botao tecla " + String(Bindings.NAMES[action]),
					cp.make_binding_buttons(action, show_kb),
					is_compact,
					fs
				)

			parent.add_child(LmuTheme.make_label("AJUSTES DO CONTROLE", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))
			_add_setting_row(parent, "Zona Morta do Volante",
				"Quanto do centro do analógico é ignorado. Aumente se o carro esterça sozinho com o controle solto.",
				"zona morta deadzone analogico volante drift",
				cp.make_slider("zona_morta", 0.0, 0.3, 0.01, Bindings.deadzone, "%.2f"), is_compact, fs)
			_add_setting_row(parent, "Curva do Volante",
				"1,0 = linear (mais direto). Valores maiores deixam o centro mais suave para correções finas.",
				"sensibilidade curva linearidade volante analogico",
				cp.make_slider("linearidade", 1.0, 2.5, 0.05, Bindings.linearity, "%.2f"), is_compact, fs)
			_add_setting_row(parent, "Zona Morta dos Gatilhos",
				"Começo do curso do acelerador e do freio que é ignorado (gatilho gasto que não volta a zero).",
				"zona morta gatilho pedal acelerador freio",
				cp.make_slider("zona_morta_pedal", 0.0, 0.3, 0.01, Bindings.pedal_deadzone, "%.2f"), is_compact, fs)
			_add_setting_row(parent, "Vibração",
				"Força da vibração (zebra, grama, batida, ABS e pneu escorregando). 0 desliga.",
				"vibracao rumble force feedback",
				cp.make_slider("vibracao", 0.0, 1.0, 0.05, Bindings.rumble, "%.2f"), is_compact, fs)
			_add_setting_row(parent, "Restaurar Controles",
				"Volta todos os comandos e ajustes para o padrão e o aparelho para automático.",
				"restaurar padrao resetar controles",
				cp.make_reset_button(), is_compact, fs)

		"graphics":
			parent.add_child(LmuTheme.make_label("QUALIDADE VISUAL & DESEMPENHO", roundi(11 * fs), LmuTheme.TEXT_DIM, 800))

			var stepper := HBoxContainer.new()
			stepper.add_theme_constant_override("separation", 8)
			var q_val_lbl := LmuTheme.make_label(current_quality.to_upper(), roundi(13 * fs), Color.WHITE, 800)
			q_val_lbl.custom_minimum_size.x = roundi(86 * fs)
			q_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var q_prev := Button.new()
			q_prev.text = "◀"
			q_prev.custom_minimum_size = Vector2(roundi(34 * fs), roundi(34 * fs))
			q_prev.add_theme_font_size_override("font_size", roundi(13 * fs))
			LmuTheme.apply_button_styles(q_prev, "outline", 4, 10, 4)
			var q_next := Button.new()
			q_next.text = "▶"
			q_next.custom_minimum_size = Vector2(roundi(34 * fs), roundi(34 * fs))
			q_next.add_theme_font_size_override("font_size", roundi(13 * fs))
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
			gauge_opt.custom_minimum_size = Vector2(roundi(215 * fs), roundi(36 * fs))
			gauge_opt.add_theme_font_size_override("font_size", roundi(13 * fs))
			gauge_opt.get_popup().add_theme_font_size_override("font_size", roundi(13 * fs))
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
			slider.custom_minimum_size = Vector2(roundi((140 if is_compact else 200) * fs), roundi(26 * fs))
			slider.value = current_volume
			var v_lbl := LmuTheme.make_label("%d%%" % roundi(current_volume * 100.0), roundi(13 * fs), Color.WHITE, 700)
			v_lbl.custom_minimum_size.x = roundi(44 * fs)
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
			nick_edit.custom_minimum_size = Vector2(roundi((160 if is_compact else 210) * fs), roundi(36 * fs))
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
	var cfs := fs * float(lp.get("ui_scale", 1.0))
	var is_compact: bool = bool(lp.get("is_compact_mobile", false))

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
	hv.add_child(LmuTheme.make_label("QUADRO OFICIAL DE TEMPOS · " + Game.track_name().to_upper(), roundi((18 if is_compact else 26) * cfs), Color.WHITE, 800))
	hv.add_child(LmuTheme.make_label("Top 15 voltas válidas no modo %s" % Game.MODE_NAMES.get(records_mode, records_mode).to_upper(), roundi((11 if is_compact else 13.5) * cfs), LmuTheme.TEXT_MUTED, 500))

	var m_switch := HBoxContainer.new()
	m_switch.add_theme_constant_override("separation", 6)
	head.add_child(m_switch)
	for rm in [["sim", "SIMULADOR"], ["arcade", "ARCADE"]]:
		var rm_id: String = rm[0]
		var b := Button.new()
		b.text = rm[1]
		b.add_theme_font_size_override("font_size", roundi((11.5 if is_compact else 13.5) * cfs))
		LmuTheme.apply_button_styles(b, "primary" if records_mode == rm_id else "outline", 4, 14, 7)
		b.pressed.connect(func():
			records_mode = rm_id
			_rebuild_view()
		)
		m_switch.add_child(b)

	# Comparação pessoal do piloto no carro atual
	var pb := _car_pb(current_car_id, records_mode)
	var car_info := current_car()
	var pb_bar := PanelContainer.new()
	pb_bar.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL_DEEP, LmuTheme.BORDER_SUBTLE, 5, 14, 8))
	col.add_child(pb_bar)
	var pbh := HBoxContainer.new()
	pbh.add_theme_constant_override("separation", 12)
	pb_bar.add_child(pbh)
	var pb_left := LmuTheme.make_label("SEU MELHOR (%s · %s):" % [current_nick, String(car_info.get("name", current_car_id))], roundi((11.5 if is_compact else 13.5) * cfs), LmuTheme.TEXT_SLATE, 700)
	pb_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pbh.add_child(pb_left)
	if not pb.is_empty():
		var secs: Array = pb.get("sectors", [])
		var sec_txt := "%.2fs · %.2fs · %.2fs" % [float(secs[0]), float(secs[1]), float(secs[2])] if secs.size() == 3 else "--"
		pbh.add_child(LmuTheme.make_label("%s  [%s]" % [LapTimer.format_time(float(pb.get("time", 0.0))), sec_txt], roundi((12.5 if is_compact else 14.5) * cfs), LmuTheme.ACCENT_GREEN, 800))
	else:
		pbh.add_child(LmuTheme.make_label("--:--.---", roundi((12.5 if is_compact else 14.5) * cfs), LmuTheme.TEXT_DIM, 700))

	# Lista Top 15
	var remote: Array = []
	if shared_records_by_mode.get(records_mode) is Array:
		remote = shared_records_by_mode[records_mode]
	var recs: Array = Records.ranking(15, records_mode, remote)

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
			pos_p.custom_minimum_size = Vector2(roundi(28 * cfs), roundi(24 * cfs))
			pos_p.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.ACCENT_AMBER if i == 0 else Color(1, 1, 1, 0.1), Color.TRANSPARENT, 3, 4, 1))
			var pl := LmuTheme.make_label("%d" % (i + 1), roundi(12.5 * cfs), Color("#0b0d10") if i == 0 else Color.WHITE, 800)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pos_p.add_child(pl)
			rh.add_child(pos_p)

			var nl := LmuTheme.make_label(r_nick, roundi((12.5 if is_compact else 14.5) * cfs), Color.WHITE, 700)
			nl.custom_minimum_size.x = 100 if is_compact else 160
			nl.clip_text = true
			rh.add_child(nl)

			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(4, 14)
			dot.color = c_col
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rh.add_child(dot)

			var cl := LmuTheme.make_label(c_name, roundi((11.5 if is_compact else 13.5) * cfs), LmuTheme.TEXT_SLATE, 500)
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cl.clip_text = true
			rh.add_child(cl)

			var secs: Array = r.get("sectors", [])
			if lp.profile != "portrait" and secs.size() == 3:
				var sl_txt := "%.2fs · %.2fs · %.2fs" % [float(secs[0]), float(secs[1]), float(secs[2])]
				rh.add_child(LmuTheme.make_label(sl_txt, roundi((10.5 if is_compact else 12.5) * cfs), LmuTheme.TEXT_MUTED, 500))

			var tl := LmuTheme.make_label(LapTimer.format_time(float(r.get("time", 0.0))), roundi((13.5 if is_compact else 15.5) * cfs), LmuTheme.ACCENT_GREEN, 800)
			tl.custom_minimum_size.x = roundi(82 * cfs)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rh.add_child(tl)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(footer)
	var back_btn := Button.new()
	back_btn.text = "VOLTAR AO MENU"
	back_btn.add_theme_font_size_override("font_size", roundi((12 if is_compact else 14) * cfs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 16, 8)
	back_btn.pressed.connect(func(): switch_view("home"))
	footer.add_child(back_btn)


# ------------------------------------------------------------------ HELP VIEW (3 CARDS)

func _build_help_view() -> void:
	var lp := layout_profile
	var fs := float(lp.font_scale)
	var cfs := fs * float(lp.get("ui_scale", 1.0))
	var is_compact: bool = bool(lp.get("is_compact_mobile", false))
	var is_portrait: bool = (lp.profile == "portrait")

	var outer := _make_padded_container(float(lp.pad_x), float(lp.pad_y))
	_body_holder.add_child(outer)
	_view_root = outer

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10 if is_compact else 14)
	outer.add_child(col)

	col.add_child(LmuTheme.make_label("GUIA DE CONTROLES & PILOTAGEM", roundi((19 if is_compact else 26) * cfs), Color.WHITE, 800))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var cards_host: BoxContainer = VBoxContainer.new() if is_portrait else HBoxContainer.new()
	cards_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_host.add_theme_constant_override("separation", 12 if is_compact else 16)
	scroll.add_child(cards_host)

	var cards_data := [
		[
			"⌨️ CONTROLES",
			"Teclado: W/S ou ↑/↓ aceleram e freiam · A/D ou ←/→ esterçam · E/Shift sobe marcha · Q/Ctrl reduz.\n\n" +
			"Atalhos: C = câmera · R = voltar ao grid · P = piloto automático · T = telemetria · F1 = qualidade · Esc = menu.\n\n" +
			"Gamepad: RT/LT pedais · Analógico volante · RB/A e LB/X marchas · Y câmera · Back grid · Start menu.\n\n" +
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
			_track_help_text()
		],
	]

	for cd in cards_data:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 260.0
		card.add_theme_stylebox_override("panel", LmuTheme.panel_style(LmuTheme.BG_PANEL, LmuTheme.BORDER_SUBTLE, 8, 16 if is_compact else 18, 14 if is_compact else 16))
		cards_host.add_child(card)

		var cv := VBoxContainer.new()
		cv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_theme_constant_override("separation", 12)
		card.add_child(cv)
		cv.add_child(LmuTheme.make_label(cd[0], roundi((15 if is_compact else 17) * cfs), Color.WHITE, 800))
		var body_lbl := LmuTheme.make_label(cd[1], roundi((12.5 if is_compact else 14) * cfs), LmuTheme.TEXT_SLATE, 500)
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(body_lbl)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(footer)
	var back_btn := Button.new()
	back_btn.text = "VOLTAR AO MENU"
	back_btn.custom_minimum_size = Vector2(roundi(180 * cfs), roundi(46 * cfs))
	back_btn.add_theme_font_size_override("font_size", roundi((12.5 if is_compact else 14) * cfs))
	LmuTheme.apply_button_styles(back_btn, "outline", 4, 16, 8)
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

