# Estado que passa de uma cena para outra (garagem → pista) e o carro escolhido, guardado em user://.
class_name Game
extends RefCounted

const CFG := "user://jogo.cfg"

## carro escolhido na garagem (o main.gd usa; --car=<id> na linha de comando tem prioridade)
static var car_id := _load_car()
## a pista foi aberta pela garagem: Esc volta para ela em vez de fechar o jogo
static var from_garage := false


static func _load_car() -> String:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		var id: String = c.get_value("garagem", "carro", "")
		if FileAccess.file_exists("res://data/cars/%s.json" % id):
			return id
	return "porsche-992-gt3r"


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
