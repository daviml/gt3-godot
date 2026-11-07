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
	var c := ConfigFile.new()
	c.load(CFG)
	c.set_value("garagem", "carro", id)
	c.save(CFG)
