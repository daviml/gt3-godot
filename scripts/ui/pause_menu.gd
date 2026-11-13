# Menu de pausa e configurações em estilo LMU (envolve LmuMenu no Context.PAUSE).
# Esc no PC, ☰ / Voltar no Android, Start no controle. Preserva todos os sinais e constantes públicas
# esperadas pelo main.gd, adicionando restart_requested, car_selected e hide_touch_changed.
class_name PauseMenu
extends CanvasLayer

signal resumed
signal garage
signal quit
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

const MODES := ["sim", "arcade"]
const MODE_NAMES := {"sim": "Simulador", "arcade": "Arcade (2× grip)"}
const MODE_NOTES := {
	"sim": "Física realista GT3 (aderência 1,0×) · ranking próprio",
	"arcade": "Pneus com 2,0× mais aderência e carros não capotam · ranking próprio",
}
const QUALITIES := ["Mínimo", "Leve", "Médio", "Extremo"]
const QUALITY_NOTE := {
	"Mínimo": "Máximo FPS (PC fraco/celular): resolução <=720p, sem sombras, materiais e árvores leves",
	"Leve": "Recomendado para Galaxy S22: 60 FPS com escala 0.75x, sombra curta, sem glow",
	"Médio": "Celular topo com refrigeração ou PC intermediário: resolução nativa, sombras e SSAO",
	"Extremo": "PC com placa de vídeo dedicada: SSAO, SSIL, SSR e sombras em 4 cortes",
}
const TOUCH_MODES := ["padrao", "fly", "inclinar", "legacy"]
const TOUCH_MODE_NAMES := {
	"padrao": "Padrão",
	"fly": "Fly-by-wire",
	"inclinar": "Inclinar",
	"legacy": "Legacy",
}
const TOUCH_MODE_NOTES := {
	"padrao": "Analógico suave à esquerda + pedais de acelerador e freio por altura à direita",
	"fly": "Analógico à esquerda + barra única multifunção: cima acelera, baixo freia (com vibração no meio)",
	"inclinar": "Vire o celular como volante usando o acelerômetro + botão de recalibrar + pedais na tela",
	"legacy": "Botões digitais clássicos ◀ ▶ à esquerda e pedais liga/desliga à direita",
}
const AIDS := [["abs", "ABS"], ["tc", "Controle de tração"], ["auto", "Câmbio automático"]]
const GAUGE_STYLES := ["barra", "circular"]
const GAUGE_NAMES := {"barra": "Barra Horizontal (Padrão)", "circular": "Circular Clássico"}
const HELP := """Teclado: W/S ou ↑/↓ acelera e freia · A/D ou ←/→ esterça · E/Shift sobe marcha · Q/Ctrl reduz
1 = ABS · 2 = controle de tração · G = câmbio automático · C = câmera · R = volta para o grid
P = piloto automático · T = telemetria · F1 = qualidade · F12 = print · N = nick · Esc = este menu
Controle: analógico esterça · gatilhos aceleram e freiam · RB/A sobe marcha · LB/X reduz · Y câmera · Back grid · Start menu
Celular: 4 esquemas (Padrão com pedais por altura, Fly-by-wire, Inclinar com acelerômetro e Legacy) · ☰ ou Voltar abre este menu"""

var is_open := false
var lmu_menu: LmuMenu


func _ready() -> void:
	layer = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	lmu_menu = LmuMenu.new(LmuMenu.Context.PAUSE)
	lmu_menu.resumed.connect(func(): resumed.emit())
	lmu_menu.garage_requested.connect(func(): garage.emit())
	lmu_menu.quit_requested.connect(func(): quit.emit())
	lmu_menu.restart_requested.connect(func(): restart_requested.emit())
	lmu_menu.car_selected.connect(func(car_id: String): car_selected.emit(car_id))
	lmu_menu.nick_changed.connect(func(nick: String): nick_changed.emit(nick))
	lmu_menu.mode_changed.connect(func(mode: String): mode_changed.emit(mode))
	lmu_menu.quality_changed.connect(func(qname: String): quality_changed.emit(qname))
	lmu_menu.volume_changed.connect(func(v: float): volume_changed.emit(v))
	lmu_menu.assist_changed.connect(func(key: String, on: bool): assist_changed.emit(key, on))
	lmu_menu.touch_mode_changed.connect(func(tm: String): touch_mode_changed.emit(tm))
	lmu_menu.hide_touch_changed.connect(func(hidden: bool): hide_touch_changed.emit(hidden))
	lmu_menu.hud_gauge_changed.connect(func(style: String): hud_gauge_changed.emit(style))
	lmu_menu.recenter_tilt.connect(func(): recenter_tilt.emit())
	add_child(lmu_menu)


func open(nick: String, quality: String, volume: float, assists: Dictionary, touch_mode := "padrao", is_touch := false, focus_nick := false, mode := "sim", hud_gauge := "barra", car_id := "") -> void:
	is_open = true
	visible = true
	if lmu_menu == null:
		return
	var state := {
		"nick": nick,
		"car_id": car_id if car_id != "" else Game.car_id,
		"mode": mode,
		"quality": quality,
		"volume": volume,
		"assists": assists,
		"touch_mode": touch_mode,
		"hide_touch": Game.is_hide_touch_controls(),
		"hud_gauge": hud_gauge,
		"is_touch": is_touch,
		"view": "settings" if focus_nick else "home",
		"settings_tab": "driver" if focus_nick else lmu_menu.active_settings_tab,
	}
	lmu_menu.configure(state)
	lmu_menu.relayout()


func set_shared_records(mode: String, recs: Array) -> void:
	if lmu_menu:
		lmu_menu.set_shared_records(mode, recs)


func update_fps(fps: int) -> void:
	if not is_open or lmu_menu == null:
		return
	lmu_menu.update_fps(fps)


## Navega de volta à Home dentro do menu antes de retomar a corrida. Retorna true se consumiu a ação.
func handle_back() -> bool:
	if not is_open or lmu_menu == null:
		return false
	if lmu_menu.active_view != "home":
		lmu_menu.switch_view("home")
		return true
	return false


func close() -> void:
	is_open = false
	visible = false
	if lmu_menu:
		lmu_menu.cleanup_pause_studio()
