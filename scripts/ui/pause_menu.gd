# Menu de pausa e configurações (etapa 10; porte do src/ui/menu.ts do web): Esc no PC, ☰ / Voltar no Android,
# Start no controle. Nick, qualidade gráfica (Leve / Médio / Extremo) com o FPS ao vivo, volume, assistências
# (ABS, TC, câmbio automático), instruções, voltar para a garagem (trocar carro) e sair.
# Fica numa CanvasLayer própria escalada pela densidade da tela (no celular os botões ficam do tamanho do dedo).
# Qualidade, volume e assistências ficam guardados em user://jogo.cfg (Game.get_setting / set_setting).
class_name PauseMenu
extends CanvasLayer

signal resumed
signal garage
signal quit
signal nick_changed(nick: String)
signal quality_changed(name: String)
signal volume_changed(v: float)
signal assist_changed(key: String, on: bool)

const QUALITIES := ["Mínimo", "Leve", "Médio", "Extremo"]
const QUALITY_NOTE := {
	"Mínimo": "Máximo FPS no celular: FSR 0.70x, sem sombras de sol, sem pós-processamento",
	"Leve": "Recomendado para Galaxy S22: 60 FPS com FSR 0.80x, sombra curta, sem glow",
	"Médio": "Celular topo com refrigeração ou PC intermediário: resolução nativa, sombras e SSAO",
	"Extremo": "PC com placa de vídeo dedicada: SSAO, SSIL, SSR e sombras em 4 cortes",
}
const AIDS := [["abs", "ABS"], ["tc", "Controle de tração"], ["auto", "Câmbio automático"]]
const HELP := """Teclado: W/S ou ↑/↓ acelera e freia · A/D ou ←/→ esterça · E/Shift sobe marcha · Q/Ctrl reduz
1 = ABS · 2 = controle de tração · G = câmbio automático · C = câmera · R = volta para o grid
P = piloto automático · T = telemetria · F1 = qualidade · F12 = print · N = nick · Esc = este menu
Controle: analógico esterça · gatilhos aceleram e freiam · RB/A sobe marcha · LB/X reduz · Y câmera · Back grid · Start menu
Celular: ◀ ▶ esterçam · ACEL. e FREIO à direita · ☰ ou Voltar abre este menu · câmbio automático"""

var is_open := false
var _s := 1.0
var _root: Control
var _card: PanelContainer
var _fps: Label
var _nick: LineEdit
var _qbtn := {}
var _qnote: Label
var _vol: HSlider
var _vol_lbl: Label
var _aids := {}
var _help: Label
var _resume: Button
var _fps_hist: Array[int] = []


func _init() -> void:
	layer = 20
	visible = false


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()


## escala do menu: densidade do celular (dpi/160) ou altura da janela no PC
func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	if OS.has_feature("mobile"):
		_s = clampf(DisplayServer.screen_get_dpi() / 160.0, 1.0, 3.5)
		# em paisagem a tela é baixa: não deixa o cartão maior que ~1,2× a altura da tela
		_s = minf(_s, vp.y / 420.0)
	else:
		_s = clampf(vp.y / 1080.0, 0.8, 1.4)
	scale = Vector2(_s, _s)
	_root.size = vp / _s
	_card.custom_minimum_size.x = minf(760.0, _root.size.x - 32.0)


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(6 / 255.0, 8 / 255.0, 12 / 255.0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	center.add_child(margin)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(16 / 255.0, 19 / 255.0, 25 / 255.0, 0.94)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	_card.add_theme_stylebox_override("panel", sb)
	margin.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)

	# título + FPS ao vivo
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(_label("GT3 Time Attack", 24, Color.WHITE, true))
	var sub := _label("Interlagos", 15, Color(1, 1, 1, 0.6))
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_fps = _label("-- fps", 15, Color(1, 1, 1, 0.7))
	_fps.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_fps)

	# nick
	box.add_child(_field("Seu nick"))
	_nick = LineEdit.new()
	_nick.max_length = 16
	_nick.placeholder_text = "ex.: davi"
	_nick.add_theme_font_size_override("font_size", 18)
	_nick.text_submitted.connect(func(_t): _resume_pressed())
	_nick.text_changed.connect(func(t): nick_changed.emit(t.strip_edges()))
	box.add_child(_nick)

	# qualidade
	box.add_child(_field("Gráficos"))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	box.add_child(qrow)
	var group := ButtonGroup.new()
	for q in QUALITIES:
		var b := _button(q, 17)
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _pick_quality(q))
		qrow.add_child(b)
		_qbtn[q] = b
	_qnote = _label("", 12, Color(1, 1, 1, 0.7))
	_qnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_qnote)

	# volume
	box.add_child(_field("Volume"))
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 12)
	box.add_child(vrow)
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.05
	_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol.custom_minimum_size.y = 28
	_vol.value_changed.connect(_on_volume)
	vrow.add_child(_vol)
	_vol_lbl = _label("60%", 15, Color(1, 1, 1, 0.8))
	_vol_lbl.custom_minimum_size.x = 44
	vrow.add_child(_vol_lbl)

	# assistências
	box.add_child(_field("Assistências"))
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 16)
	box.add_child(arow)
	for a in AIDS:
		var cb := CheckButton.new()
		cb.text = a[1]
		cb.add_theme_font_size_override("font_size", 15)
		cb.focus_mode = Control.FOCUS_ALL
		cb.toggled.connect(func(on): _on_assist(a[0], on))
		arow.add_child(cb)
		_aids[a[0]] = cb

	# botões
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	box.add_child(brow)
	_resume = _button("CONTINUAR", 20, true)
	_resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume.pressed.connect(_resume_pressed)
	brow.add_child(_resume)
	var g := _button("GARAGEM", 17)
	g.tooltip_text = "Trocar de carro"
	g.pressed.connect(func(): _close(); garage.emit())
	brow.add_child(g)
	var h := _button("INSTRUÇÕES", 17)
	h.pressed.connect(func(): _help.visible = not _help.visible)
	brow.add_child(h)
	var x := _button("SAIR", 17)
	x.pressed.connect(func(): quit.emit())
	brow.add_child(x)
	_help = _label(HELP, 12, Color(1, 1, 1, 0.65))
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.visible = false
	box.add_child(_help)


func _label(t: String, size: int, c: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	if bold:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "sans-serif"])
		f.font_weight = 700
		l.add_theme_font_override("font", f)
	return l


func _field(t: String) -> Label:
	return _label(t.to_upper(), 12, Color(1, 1, 1, 0.55))


func _button(t: String, size: int, primary := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		if primary:
			sb.bg_color = Color("#e10600") if st == "normal" else Color("#f05a4d")
			sb.border_color = Color(1, 1, 1, 0.0 if st != "focus" else 0.8)
		else:
			var a := 0.08
			if st == "hover":
				a = 0.16
			elif st == "pressed":
				a = 0.28
			sb.bg_color = Color(1, 1, 1, a)
			sb.border_color = Color(1, 1, 1, 0.8 if st == "focus" else 0.25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		b.add_theme_stylebox_override(st, sb)
	return b


# ------------------------------------------------------------------ estado

## abre com o estado atual do jogo
func open(nick: String, quality: String, volume: float, assists: Dictionary, focus_nick := false) -> void:
	_nick.text = nick
	for q in _qbtn:
		_qbtn[q].button_pressed = q == quality
	_note_quality(quality)
	_vol.set_value_no_signal(volume)
	_vol_lbl.text = "%d%%" % roundi(volume * 100)
	for key in _aids:
		_aids[key].set_pressed_no_signal(bool(assists.get(key, false)))
	is_open = true
	visible = true
	_fps_hist.clear()
	if focus_nick or nick == "":
		_nick.grab_focus.call_deferred()
	else:
		_resume.grab_focus.call_deferred()


func _close() -> void:
	is_open = false
	visible = false
	var f := _root.get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()


func _resume_pressed() -> void:
	_close()
	resumed.emit()


## chamado pelo jogo a cada quadro enquanto aberto: FPS médio dos últimos ~2 s
func update_fps(fps: int) -> void:
	_fps_hist.append(fps)
	if _fps_hist.size() > 8:
		_fps_hist.pop_front()
	var sum := 0
	for v in _fps_hist:
		sum += v
	var avg := roundi(float(sum) / _fps_hist.size())
	_fps.text = "%d fps" % avg
	_fps.add_theme_color_override("font_color", Color("#2fd36b") if avg >= 55 else (Color("#ffb020") if avg >= 30 else Color("#ff5a4f")))
	var q := ""
	for k in _qbtn:
		if _qbtn[k].button_pressed:
			q = k
	_note_quality(q, avg)


func _pick_quality(q: String) -> void:
	Game.set_setting("video", "qualidade", q)
	quality_changed.emit(q)
	_note_quality(q)


func _note_quality(q: String, fps := 0) -> void:
	var parts := []
	if fps > 0:
		parts.append("rodando a %d fps" % fps)
	if QUALITY_NOTE.has(q):
		parts.append(QUALITY_NOTE[q])
	if q != "Leve" and fps > 0 and fps < 45:
		parts.append("se travar, use o Leve")
	_qnote.text = " · ".join(parts)


func _on_volume(v: float) -> void:
	_vol_lbl.text = "%d%%" % roundi(v * 100)
	Game.set_setting("audio", "volume", v)
	volume_changed.emit(v)


func _on_assist(key: String, on: bool) -> void:
	Game.set_setting("assistencias", key, on)
	assist_changed.emit(key, on)


## fecha por fora (Esc / Start / ☰ / Voltar, tratados no main.gd)
func close() -> void:
	_close()
	resumed.emit()
