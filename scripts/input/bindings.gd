# Mapa de comandos (controle e teclado) e ajustes finos, salvos em user://jogo.cfg.
# Ligação de controle: {"t": "btn", "i": botão} ou {"t": "axis", "i": eixo, "s": 1 | -1 | 2}
#   s = 1/-1: metade positiva/negativa do eixo (analógico, gatilho 0..1); s = 2: eixo inteiro -1..1 virando 0..1
#   (gatilho de driver que repousa em -1). Teclado: lista de physical keycodes.
# O InputReader monta o mesmo dicionário "raw" de antes a partir daqui, então filter() e os testes não mudaram.
class_name Bindings
extends RefCounted

const ACTIONS := ["steer_left", "steer_right", "gas", "brake", "shift_up", "shift_down", "camera", "reset"]
## ações que aceitam eixo no controle; as outras só botão (câmera e reset chegam por evento)
const ANALOG := ["steer_left", "steer_right", "gas", "brake"]
const NAMES := {
	"steer_left": "Esterçar à esquerda",
	"steer_right": "Esterçar à direita",
	"gas": "Acelerar",
	"brake": "Frear",
	"shift_up": "Subir marcha",
	"shift_down": "Reduzir marcha",
	"camera": "Trocar câmera",
	"reset": "Voltar ao grid",
}

const PAD_DEFAULT := {
	"steer_left": [{"t": "axis", "i": JOY_AXIS_LEFT_X, "s": -1}],
	"steer_right": [{"t": "axis", "i": JOY_AXIS_LEFT_X, "s": 1}],
	"gas": [{"t": "axis", "i": JOY_AXIS_TRIGGER_RIGHT, "s": 1}],
	"brake": [{"t": "axis", "i": JOY_AXIS_TRIGGER_LEFT, "s": 1}],
	"shift_up": [{"t": "btn", "i": JOY_BUTTON_RIGHT_SHOULDER}, {"t": "btn", "i": JOY_BUTTON_A}],
	"shift_down": [{"t": "btn", "i": JOY_BUTTON_LEFT_SHOULDER}, {"t": "btn", "i": JOY_BUTTON_X}],
	"camera": [{"t": "btn", "i": JOY_BUTTON_Y}],
	"reset": [{"t": "btn", "i": JOY_BUTTON_BACK}],
}

const KEY_DEFAULT := {
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"gas": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN, KEY_SPACE],
	"shift_up": [KEY_E, KEY_SHIFT],
	"shift_down": [KEY_Q, KEY_CTRL],
	"camera": [KEY_C],
	"reset": [KEY_R],
}

const DEADZONE_DEFAULT := 0.08
const LINEARITY_DEFAULT := 1.6
const PEDAL_DEADZONE_DEFAULT := 0.0
const RUMBLE_DEFAULT := 1.0

const SECTION := "controles_mapa"

static var pad := {}
static var keys := {}
## zona morta do analógico do volante (fração do curso)
static var deadzone := DEADZONE_DEFAULT
## curva do volante no analógico (>1 = centro mais suave)
static var linearity := LINEARITY_DEFAULT
## zona morta dos gatilhos (fração do curso ignorada no começo)
static var pedal_deadzone := PEDAL_DEADZONE_DEFAULT
## força da vibração (0 = desligada)
static var rumble := RUMBLE_DEFAULT

static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_settings()


static func load_settings() -> void:
	_loaded = true
	pad = PAD_DEFAULT.duplicate(true)
	keys = KEY_DEFAULT.duplicate(true)
	for a in ACTIONS:
		var p = Game.get_setting(SECTION, "pad_" + a, null)
		if p is Array and _valid_pad_list(p):
			pad[a] = p
		var k = Game.get_setting(SECTION, "kb_" + a, null)
		if k is Array:
			keys[a] = k
	deadzone = clampf(float(Game.get_setting("controles", "zona_morta", DEADZONE_DEFAULT)), 0.0, 0.5)
	linearity = clampf(float(Game.get_setting("controles", "linearidade", LINEARITY_DEFAULT)), 1.0, 3.0)
	pedal_deadzone = clampf(float(Game.get_setting("controles", "zona_morta_pedal", PEDAL_DEADZONE_DEFAULT)), 0.0, 0.5)
	rumble = clampf(float(Game.get_setting("controles", "vibracao", RUMBLE_DEFAULT)), 0.0, 1.0)


static func _valid_pad_list(l: Array) -> bool:
	for b in l:
		if not (b is Dictionary and b.has("t") and b.has("i")):
			return false
	return true


static func reset_defaults() -> void:
	for a in ACTIONS:
		Game.erase_setting(SECTION, "pad_" + a)
		Game.erase_setting(SECTION, "kb_" + a)
	for k in ["zona_morta", "linearidade", "zona_morta_pedal", "vibracao"]:
		Game.erase_setting("controles", k)
	load_settings()


static func set_tuning(key: String, value: float) -> void:
	ensure_loaded()
	match key:
		"zona_morta": deadzone = value
		"linearidade": linearity = value
		"zona_morta_pedal": pedal_deadzone = value
		"vibracao": rumble = value
	Game.set_setting("controles", key, value)


# ------------------------------------------------------------------ leitura

static func same(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("t", "")) == String(b.get("t", "")) and int(a.get("i", -1)) == int(b.get("i", -1)) \
		and int(a.get("s", 0)) == int(b.get("s", 0))


static func bind_value(d: int, b: Dictionary) -> float:
	if String(b.t) == "btn":
		return 1.0 if Input.is_joy_button_pressed(d, int(b.i)) else 0.0
	return axis_part(Input.get_joy_axis(d, int(b.i)), int(b.get("s", 1)))


static func axis_part(v: float, s: int) -> float:
	if s == 2:
		return clampf((v + 1.0) * 0.5, 0.0, 1.0)
	return clampf(v * float(s), 0.0, 1.0)


## valor 0..1 da ação no controle d (o maior entre as ligações)
static func pad_value(d: int, action: String) -> float:
	ensure_loaded()
	var v := 0.0
	if d < 0:
		return v
	for b in pad.get(action, []):
		v = maxf(v, bind_value(d, b))
	return v


static func key_held(action: String) -> bool:
	ensure_loaded()
	for k in keys.get(action, []):
		if Input.is_physical_key_pressed(int(k)):
			return true
	return false


## evento de aperto (tecla ou botão do controle) ligado à ação; usado para câmera e reset
static func event_is(e: InputEvent, action: String) -> bool:
	ensure_loaded()
	if e is InputEventKey:
		if not e.pressed or e.echo:
			return false
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		for kk in keys.get(action, []):
			if int(kk) == k:
				return true
	elif e is InputEventJoypadButton:
		if not e.pressed:
			return false
		for b in pad.get(action, []):
			if String(b.t) == "btn" and int(b.i) == e.button_index:
				return true
	return false


# ------------------------------------------------------------------ remapeamento

## Liga b (controle) à ação. Se outra ação já usava b, ela fica com a ligação antiga desta (troca), desde que
## seja compatível (ações digitais só aceitam botão); senão fica sem ligação no controle.
static func bind_pad(action: String, b: Dictionary) -> void:
	ensure_loaded()
	var old: Array = pad.get(action, []).duplicate(true)
	for a2 in ACTIONS:
		if a2 == action:
			continue
		var l: Array = pad[a2]
		var kept := l.filter(func(x): return not same(x, b))
		if kept.size() == l.size():
			continue
		if kept.is_empty():
			kept = old.filter(func(x): return a2 in ANALOG or String(x.t) == "btn")
		pad[a2] = kept
		Game.set_setting(SECTION, "pad_" + a2, kept)
	pad[action] = [b]
	Game.set_setting(SECTION, "pad_" + action, pad[action])


## Liga a tecla à ação, com a mesma troca do controle.
static func bind_key(action: String, k: int) -> void:
	ensure_loaded()
	var old: Array = keys.get(action, []).duplicate()
	for a2 in ACTIONS:
		if a2 == action:
			continue
		var l: Array = keys[a2]
		var kept := l.filter(func(x): return int(x) != k)
		if kept.size() == l.size():
			continue
		if kept.is_empty():
			kept = old
		keys[a2] = kept
		Game.set_setting(SECTION, "kb_" + a2, kept)
	keys[action] = [k]
	Game.set_setting(SECTION, "kb_" + action, keys[action])


# ------------------------------------------------------------------ nomes para a tela

const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View/Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu/Start",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2",
	JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4", JOY_BUTTON_TOUCHPAD: "Touchpad",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["Analógico E ←", "Analógico E →"],
	JOY_AXIS_LEFT_Y: ["Analógico E ↑", "Analógico E ↓"],
	JOY_AXIS_RIGHT_X: ["Analógico D ←", "Analógico D →"],
	JOY_AXIS_RIGHT_Y: ["Analógico D ↑", "Analógico D ↓"],
	JOY_AXIS_TRIGGER_LEFT: ["LT −", "LT"],
	JOY_AXIS_TRIGGER_RIGHT: ["RT −", "RT"],
}


static func pad_label(b: Dictionary) -> String:
	var i := int(b.i)
	if String(b.t) == "btn":
		return BUTTON_NAMES.get(i, "Botão %d" % i)
	var s := int(b.get("s", 1))
	if AXIS_NAMES.has(i):
		var n: String = AXIS_NAMES[i][0 if s < 0 else 1]
		return n + (" (inteiro)" if s == 2 else "")
	return "Eixo %d%s" % [i, "" if s == 2 else ("−" if s < 0 else "+")]


static func key_label(k: int) -> String:
	# mostra a letra do layout do teclado (ex.: AZERTY); o servidor headless dos testes não sabe converter
	var shown := k
	if DisplayServer.get_name() != "headless":
		var kc := DisplayServer.keyboard_get_keycode_from_physical(k)
		if kc != KEY_NONE:
			shown = kc
	var s := OS.get_keycode_string(shown)
	match s:
		"Left": return "←"
		"Right": return "→"
		"Up": return "↑"
		"Down": return "↓"
		"Space": return "Espaço"
	return s if s != "" else "?"


static func pad_text(action: String) -> String:
	ensure_loaded()
	var l: Array = pad.get(action, [])
	return "—" if l.is_empty() else " / ".join(l.map(func(b): return pad_label(b)))


static func key_text(action: String) -> String:
	ensure_loaded()
	var l: Array = keys.get(action, [])
	return "—" if l.is_empty() else " / ".join(l.map(func(k): return key_label(int(k))))
