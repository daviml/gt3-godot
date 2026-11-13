# Entrada (src/input/input.ts do web): controle + teclado com suavização, e os botões de toque do celular.
# Controle e teclado passam pelo limite de esterço por velocidade (o teclado ainda ganha rampa progressiva);
# no celular o toque mantém a direção antiga (commits 1177412 e 2fd40d5 do web).
# update() lê os aparelhos; filter() só faz a conta, para os testes alimentarem entradas sintéticas.
class_name InputReader
extends RefCounted

const DEADZONE := 0.08
## >1 deixa o centro do analógico mais suave (Simulador e Arcade)
const STEER_LINEARITY := 1.6
const STEER_LINEARITY_ARCADE := 1.9

## celular: os botões de toque usam a direção antiga (rampa constante e limite próprio)
var touch := false
## oculta leitura do toque (quando usuário desativa na tela ou há controle físico conectado)
var touch_hidden := false
## modo de controle mobile ("padrao", "fly", "inclinar", "legacy")
var touch_mode := "padrao"
## teclas de toque apertadas ("left", "right", "gas", "brake"), preenchidas pelo TouchControls
var touch_keys := {}
## comandos proporcionais de toque: steer (-1..1), gas (0..1), brake (0..1)
var touch_axes := {"steer": 0.0, "gas": 0.0, "brake": 0.0}
## escala de aderência do modo de jogo (Arcade > 1.0): pneu aguenta mais volante, então o limite sobe junto
var grip_scale := 1.0

# saída (o câmbio é "segurado"; o carro só troca uma marcha por aperto)
var steer := 0.0
var throttle := 0.0
var brake := 0.0
var shift_up := false
var shift_down := false
## verdadeiro só no passo em que o botão Back/Select do controle foi apertado
var reset := false
var source := "teclado"

var _kb_steer := 0.0
var _kb_throttle := 0.0
var _kb_brake := 0.0
var _kb_held := 0.0
var _kb_dir := 0.0
var _pad_steer := 0.0
var _touch_steer := 0.0
var _analog_steer := 0.0
var _analog_gas := 0.0
var _analog_brake := 0.0
var _prev_reset := false


## Fração do esterço máximo liberada a v m/s. Medido na física (g lateral × volante, pista plana): a curva mais
## forte acontece com ~0,6 do volante a 72 km/h, ~0,4 a 108 e ~0,17 a 216. 14/v fica ~25% acima desse pico;
## até ~50 km/h libera tudo.
static func steer_limit(speed_ms: float) -> float:
	return minf(1.0, maxf(0.18, 14.0 / maxf(speed_ms, 1.0)))


static func _key(a: Key, b: Key) -> bool:
	return Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b)


## estado cru dos aparelhos (teclado + toque + primeiro controle conectado)
func read_devices() -> Dictionary:
	var joy := Input.get_connected_joypads()
	var use_touch := touch and not touch_hidden and joy.is_empty()
	var raw := {
		"left": _key(KEY_LEFT, KEY_A) or (use_touch and touch_keys.has("left")),
		"right": _key(KEY_RIGHT, KEY_D) or (use_touch and touch_keys.has("right")),
		"gas": _key(KEY_UP, KEY_W) or (use_touch and touch_keys.has("gas")),
		"brake": _key(KEY_DOWN, KEY_S) or Input.is_physical_key_pressed(KEY_SPACE) or (use_touch and touch_keys.has("brake")),
		"up": _key(KEY_E, KEY_SHIFT),
		"down": _key(KEY_Q, KEY_CTRL),
		"pad": null,
	}
	if joy.size() > 0:
		var d: int = joy[0]
		raw.pad = {
			"x": Input.get_joy_axis(d, JOY_AXIS_LEFT_X),
			"rt": Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT),
			"lt": Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT),
			"up": Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_A),
			"down": Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_X),
			"reset": Input.is_joy_button_pressed(d, JOY_BUTTON_BACK),
		}
	return raw


## Rampa progressiva estilo "direção elétrica" para analógico (controle e toque proporcional):
## mais suave perto do centro e em alta velocidade (reta), mais direta em curvas e rápida no retorno.
static func _step_steer_ramp(cur: float, target: float, dt: float, speed_ms: float, arcade_blend: float) -> float:
	var returning := absf(target) < absf(cur) or (target * cur < 0.0)
	var rate: float
	if returning:
		rate = 8.0
	else:
		var speed_t := clampf((speed_ms - 18.0) / 45.0, 0.0, 1.0)
		var prog := clampf(absf(cur) / 0.35, 0.0, 1.0)
		var start_low := lerpf(3.8, 3.0, arcade_blend)
		var start_high := lerpf(2.8, 2.0, arcade_blend)
		var full_low := lerpf(5.0, 4.5, arcade_blend)
		var full_high := lerpf(4.2, 3.5, arcade_blend)
		var min_rate := lerpf(start_low, start_high, speed_t)
		var max_rate := lerpf(full_low, full_high, speed_t)
		rate = lerpf(min_rate, max_rate, prog)
	return cur + clampf(target - cur, -rate * dt, rate * dt)


func update(dt: float, speed_ms: float) -> void:
	filter(dt, speed_ms, read_devices())


func filter(dt: float, speed_ms: float, raw: Dictionary) -> void:
	dt = maxf(0.0, dt)
	# volante em fração do limite da velocidade: o batente é sempre a curva mais forte que o pneu aguenta,
	# e o resto do curso do analógico/botão vira precisão em vez de excesso.
	# No Arcade (grip_scale > 1), o limite sobe na mesma proporção.
	var limit := minf(1.0, steer_limit(speed_ms) * grip_scale)
	var arcade_blend := clampf(grip_scale - 1.0, 0.0, 1.0)

	# teclado / toque (digitais): segurar vira progressivamente — toque curto corrige, segurar vai ao batente
	var target := (1.0 if raw.right else 0.0) - (1.0 if raw.left else 0.0)
	_kb_held = _kb_held + dt if target != 0.0 and target == _kb_dir else 0.0
	_kb_dir = target
	var kb_rate := 7.0 if target == 0.0 else (1.5 if _kb_held < 0.25 else 5.0)
	_kb_steer += clampf(target - _kb_steer, -kb_rate * dt, kb_rate * dt)

	# celular: mantém a direção antiga (rampa constante e limite próprio) — a progressiva ficou ruim no toque
	var old_limit := minf(1.0, maxf(0.22, 0.15 + 8.0 / maxf(speed_ms, 1.0)) * grip_scale)
	var old_rate := (5.0 if target == 0.0 else 2.6) / (1.0 + speed_ms / 40.0)
	_touch_steer += clampf(target * old_limit - _touch_steer, -old_rate * dt, old_rate * dt)
	_kb_throttle = clampf(_kb_throttle + (4.0 if raw.gas else -8.0) * dt, 0.0, 1.0)
	_kb_brake = clampf(_kb_brake + (6.0 if raw.brake else -10.0) * dt, 0.0, 1.0)

	var allow_touch := touch and not touch_hidden and raw.pad == null
	var cur_steer: float = _touch_steer if (allow_touch and touch_mode == "legacy") else _kb_steer * limit
	var cur_thr: float = _kb_throttle
	var cur_brk: float = _kb_brake
	var up: bool = raw.up
	var down: bool = raw.down
	var rst := false
	source = "toque" if (allow_touch and touch_keys.size() > 0) else "teclado"

	# esquemas novos do celular: volante proporcional (analógico ou giro do celular) no limite antigo do toque,
	# com a mesma limitação de velocidade do analógico do controle; pedais proporcionais com filtro de 0,05 s
	var tm := touch_mode if allow_touch else "legacy"
	if tm != "legacy":
		var raw_analog: float = raw.get("tilt_steer", float(touch_axes.get("steer", 0.0))) if tm == "inclinar" else float(touch_axes.get("steer", 0.0))
		var target_analog := clampf(raw_analog, -1.0, 1.0)
		if arcade_blend > 0.0:
			target_analog = signf(target_analog) * pow(absf(target_analog), lerpf(1.0, 1.18, arcade_blend))
		_analog_steer = _step_steer_ramp(_analog_steer, target_analog, dt, speed_ms, arcade_blend)
		cur_steer = _analog_steer * old_limit
		if tm != "inclinar":
			var k := 1.0 - exp(-dt / 0.05)
			_analog_gas += (float(touch_axes.get("gas", 0.0)) - _analog_gas) * k
			_analog_brake += (float(touch_axes.get("brake", 0.0)) - _analog_brake) * k
			cur_thr = _analog_gas
			cur_brk = _analog_brake
		else:
			if float(touch_axes.get("gas", 0.0)) > 0.0 or float(touch_axes.get("brake", 0.0)) > 0.0:
				var k := 1.0 - exp(-dt / 0.05)
				_analog_gas += (float(touch_axes.get("gas", 0.0)) - _analog_gas) * k
				_analog_brake += (float(touch_axes.get("brake", 0.0)) - _analog_brake) * k
				cur_thr = _analog_gas
				cur_brk = _analog_brake
			else:
				cur_thr = _kb_throttle
				cur_brk = _kb_brake
		if float(touch_axes.get("steer", 0.0)) != 0.0 or float(touch_axes.get("gas", 0.0)) > 0.0 or float(touch_axes.get("brake", 0.0)) > 0.0 or touch_keys.size() > 0 or raw.has("tilt_steer"):
			source = "toque"

	var pad = raw.pad
	if pad != null:
		var ax: float = pad.x
		var mag := maxf(0.0, (absf(ax) - DEADZONE) / (1.0 - DEADZONE))
		var linearity := lerpf(STEER_LINEARITY, STEER_LINEARITY_ARCADE, arcade_blend)
		var stick := signf(ax) * pow(mag, linearity)
		_pad_steer = _step_steer_ramp(_pad_steer, stick, dt, speed_ms, arcade_blend)
		var pad_steer := _pad_steer * limit
		var pad_thr: float = pad.rt
		var pad_brk: float = pad.lt
		# usa o controle sempre que ele estiver sendo mexido ou o teclado estiver parado
		var pad_active := absf(pad_steer) > 0.01 or pad_thr > 0.02 or pad_brk > 0.02
		var kb_active := target != 0.0 or _kb_throttle > 0.0 or _kb_brake > 0.0
		if pad_active or not kb_active:
			cur_steer = pad_steer
			cur_thr = pad_thr
			cur_brk = pad_brk
			source = "controle"
		up = up or pad.up
		down = down or pad.down
		rst = pad.reset

	steer = cur_steer
	throttle = cur_thr
	brake = cur_brk
	shift_up = up
	shift_down = down
	reset = rst and not _prev_reset
	_prev_reset = rst
