# Qual controle o jogo lê. Antes era sempre o primeiro da lista (joy[0]), e no Windows esse costuma ser outro
# aparelho (controle virtual do Steam/DS4Windows/vJoy, volante, headset): o jogador mexia no controle de verdade
# e nada acontecia, só os botões lidos por evento (câmera, Start) funcionavam.
# Agora vale o último aparelho que se mexeu (modo automático) ou um aparelho fixo escolhido no menu (pelo GUID).
# Tudo estático: InputReader, Rumble e o menu consultam o mesmo estado sem precisar de autoload.
class_name PadManager
extends RefCounted

## variação de eixo, a partir do repouso, que conta como "mexeu neste controle"
const MOVE := 0.5
const SCAN_AXES := JOY_AXIS_MAX
const SCAN_BUTTONS := 32

## aparelho lido agora (-1 = nenhum)
static var active := -1
## GUID do aparelho fixo escolhido no menu ("" = automático)
static var preferred_guid := ""

static var _loaded := false
## repouso de cada aparelho: {id: {"axes": PackedFloat32Array, "btn": int (máscara)}}
static var _rest := {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	preferred_guid = String(Game.get_setting("controles", "aparelho", ""))


static func set_preferred(guid: String) -> void:
	ensure_loaded()
	preferred_guid = guid
	if guid == "":
		Game.erase_setting("controles", "aparelho")
	else:
		Game.set_setting("controles", "aparelho", guid)


## aparelhos conectados, para o menu e o log
static func list() -> Array:
	var out := []
	for d in Input.get_connected_joypads():
		out.append({"id": d, "name": device_name(d), "guid": Input.get_joy_guid(d), "known": Input.is_joy_known(d)})
	return out


static func device_name(d: int) -> String:
	if d < 0:
		return "nenhum"
	var n := Input.get_joy_name(d).strip_edges()
	return n if n != "" else "Controle %d" % d


## Aparelho que deve ser lido neste quadro. Chamar uma vez por quadro (InputReader.read_devices faz isso):
## a varredura é que descobre qual controle a pessoa está mexendo.
static func device() -> int:
	ensure_loaded()
	var joys := Input.get_connected_joypads()
	if joys.is_empty():
		active = -1
		_rest.clear()
		return -1
	for d in _rest.keys():
		if not d in joys:
			_rest.erase(d)
	if preferred_guid != "":
		for d in joys:
			if Input.get_joy_guid(d) == preferred_guid:
				active = d
				return d
		# o aparelho fixo não está conectado: segue no automático até ele voltar
	var moved := scan(joys)
	if moved >= 0:
		active = moved
	elif not active in joys:
		active = _best_default(joys)
	return active


## Varre os aparelhos e devolve o que se mexeu em relação ao próprio repouso (ou -1).
## O repouso é o estado do aparelho quando foi visto pela primeira vez, então um eixo travado
## de um aparelho fantasma (ex.: pedal de volante parado em -1) nunca conta como movimento.
static func scan(joys: Array) -> int:
	var moved := -1
	for d in joys:
		var axes := PackedFloat32Array()
		axes.resize(SCAN_AXES)
		var mask := 0
		for a in SCAN_AXES:
			axes[a] = Input.get_joy_axis(d, a)
		for b in SCAN_BUTTONS:
			if Input.is_joy_button_pressed(d, b):
				mask |= 1 << b
		if not _rest.has(d):
			_rest[d] = {"axes": axes, "btn": mask}
			continue
		var r: Dictionary = _rest[d]
		# botão que estava preso no repouso e foi solto passa a valer quando apertado de novo
		r.btn = int(r.btn) & mask
		var hit := (mask & ~int(r.btn)) != 0
		if not hit:
			var ra: PackedFloat32Array = r.axes
			for a in SCAN_AXES:
				if absf(axes[a] - ra[a]) > MOVE:
					hit = true
					break
		if hit and (moved < 0 or d != active):
			moved = d
	return moved


## sem movimento ainda: prefere um controle que o SDL reconhece (tem mapeamento de botões padrão)
static func _best_default(joys: Array) -> int:
	for d in joys:
		if Input.is_joy_known(d):
			return d
	return joys[0]


## linha de log com todos os aparelhos (vai para o arquivo de log do Godot; ajuda a diagnosticar no PC dos outros)
static func log_devices(prefix := "controles") -> void:
	var l := list()
	if l.is_empty():
		print("[%s] nenhum controle conectado" % prefix)
		return
	for e in l:
		print("[%s] #%d %s | guid %s | %s%s" % [prefix, e.id, e.name, e.guid,
			"mapeado" if e.known else "SEM mapeamento SDL", " | ATIVO" if e.id == active else ""])
