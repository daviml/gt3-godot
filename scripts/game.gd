# Estado que passa de uma cena para outra (garagem → pista) e o carro escolhido, guardado em user://.
class_name Game
extends RefCounted

const CFG := "user://jogo.cfg"
const CAR_CACHE_MAX_DESKTOP := 3
const CAR_CACHE_MAX_MOBILE := 2
const QUALITY_LEVELS := {"Mínimo": 0, "Leve": 1, "Médio": 2, "Extremo": 3}
const MODES := ["sim", "arcade"]
const MODE_NAMES := {"sim": "Simulador", "arcade": "Arcade"}
const MODE_GRIP := {"sim": 1.0, "arcade": 2.0}

## carro escolhido na garagem (o main.gd usa; --car=<id> na linha de comando tem prioridade)
static var car_id := _load_car()
## modo de condução atual ("sim" ou "arcade"; --arcade / --sim na linha de comando têm prioridade)
static var mode := _load_mode()
## a pista foi aberta pela garagem: Esc volta para ela em vez de fechar o jogo
static var from_garage := false
## alvo da próxima transição via scenes/loading.tscn ("track" ou "garage")
static var transition_target := ""

static var _car_scene_cache: Dictionary = {}
static var _car_scene_order: Array[String] = []
static var _car_data_cache: Dictionary = {}
static var _cars_list_cache: Array = []


static func is_mobile_platform() -> bool:
	return OS.has_feature("mobile") or "--mobile" in OS.get_cmdline_user_args() or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func is_compatibility_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func get_minimal_3d_scale(vp: Viewport) -> float:
	if vp == null:
		return 0.65
	var px_h := float(vp.size.y)
	if px_h <= 0.0:
		px_h = vp.get_visible_rect().size.y
	if px_h > 1080.0:
		return clampf(720.0 / px_h, 0.30, 0.65)
	return 0.65


static func get_quality_name() -> String:
	var args := OS.get_cmdline_user_args()
	var is_mobile := is_mobile_platform()
	if "--mobile" in args:
		return "Leve"
	var saved := String(get_setting("video", "qualidade", ""))
	if QUALITY_LEVELS.has(saved):
		return saved
	return "Leve" if is_mobile else "Extremo"


static func get_quality_level(name := "") -> int:
	var q_name := name if name != "" else get_quality_name()
	return int(QUALITY_LEVELS.get(q_name, 1 if is_mobile_platform() else 3))


static func get_cars_list() -> Array:
	if _cars_list_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
		if parsed is Array:
			_cars_list_cache = parsed
	return _cars_list_cache


static func get_car_info(id: String) -> Dictionary:
	for c in get_cars_list():
		if c is Dictionary and c.get("id", "") == id:
			return c
	return {}


static func get_car_data(id: String) -> Dictionary:
	if _car_data_cache.has(id):
		return _car_data_cache[id]
	var path := "res://data/cars/%s.json" % id
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_car_data_cache[id] = parsed
		return parsed
	return {}


static func get_car_glb_path(id: String) -> String:
	var d := get_car_data(id)
	var model = d.get("model", {})
	if model is Dictionary:
		return String(model.get("glb", ""))
	return ""


static func has_cached_car_scene(id: String) -> bool:
	return _car_scene_cache.has(id)


static func get_cached_car_scene(id: String) -> PackedScene:
	if not _car_scene_cache.has(id):
		return null
	_car_scene_order.erase(id)
	_car_scene_order.append(id)
	return _car_scene_cache[id] as PackedScene


static func cache_car_scene(id: String, scene: PackedScene) -> void:
	if id == "" or scene == null:
		return
	if _car_scene_cache.has(id):
		_car_scene_order.erase(id)
	else:
		var limit := CAR_CACHE_MAX_MOBILE if is_mobile_platform() else CAR_CACHE_MAX_DESKTOP
		while _car_scene_order.size() >= limit:
			var oldest: String = _car_scene_order.pop_front()
			_car_scene_cache.erase(oldest)
	_car_scene_cache[id] = scene
	_car_scene_order.append(id)


static func load_car_scene(id: String) -> PackedScene:
	var cached := get_cached_car_scene(id)
	if cached != null:
		return cached
	var path := get_car_glb_path(id)
	if path == "":
		return null
	var scene := ResourceLoader.load(path) as PackedScene
	if scene != null:
		cache_car_scene(id, scene)
	return scene


static func clear_car_cache(keep_id := "") -> void:
	if keep_id != "" and _car_scene_cache.has(keep_id):
		var kept: PackedScene = _car_scene_cache[keep_id]
		_car_scene_cache.clear()
		_car_scene_order.clear()
		_car_scene_cache[keep_id] = kept
		_car_scene_order.append(keep_id)
	else:
		_car_scene_cache.clear()
		_car_scene_order.clear()


static func _load_car() -> String:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		var id: String = c.get_value("garagem", "carro", "")
		if FileAccess.file_exists("res://data/cars/%s.json" % id):
			return id
	return "corvette-c6r-gt3"


static func save_car(id: String) -> void:
	car_id = id
	set_setting("garagem", "carro", id)


## ajuste guardado em user://jogo.cfg (qualidade, volume, assistências — menu de pausa da etapa 10)
static func get_setting(section: String, key: String, default: Variant) -> Variant:
	var c := ConfigFile.new()
	if c.load(CFG) != OK or not c.has_section_key(section, key):
		return default
	return c.get_value(section, key, default)


static func set_setting(section: String, key: String, value: Variant) -> void:
	var c := ConfigFile.new()
	c.load(CFG)
	c.set_value(section, key, value)
	c.save(CFG)


static func erase_setting(section: String, key: String) -> void:
	var c := ConfigFile.new()
	if c.load(CFG) != OK or not c.has_section_key(section, key):
		return
	c.erase_section_key(section, key)
	c.save(CFG)


static func _load_mode() -> String:
	var args := OS.get_cmdline_user_args()
	if "--arcade" in args:
		return "arcade"
	if "--sim" in args:
		return "sim"
	var saved := String(get_setting("jogo", "modo", "sim"))
	return saved if saved in MODES else "sim"


static func is_arcade() -> bool:
	return mode == "arcade"


static func get_grip_scale() -> float:
	return float(MODE_GRIP.get(mode, 1.0))


static func set_mode(m: String) -> void:
	if not (m in MODES):
		m = "sim"
	mode = m
	set_setting("jogo", "modo", m)


static func is_hide_touch_controls() -> bool:
	return bool(get_setting("controles", "ocultar_toque", false))


static func set_hide_touch_controls(hide: bool) -> void:
	set_setting("controles", "ocultar_toque", hide)


static func has_gamepad_connected() -> bool:
	return Input.get_connected_joypads().size() > 0


static func is_touch_device() -> bool:
	return is_mobile_platform() or "--touch" in OS.get_cmdline_user_args() or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())


static func should_show_touch_controls(touch_enabled: bool) -> bool:
	return touch_enabled and not is_hide_touch_controls() and not has_gamepad_connected()


static func weight_distribution_for_layout(layout: String) -> String:
	match layout:
		"traseiro":
			return "39% / 61%"
		"central":
			return "43% / 57%"
		_:
			return "49% / 51%"
