# Melhores tempos guardados neste PC (porte de src/ui/records.ts do web): a melhor volta válida de cada nick em cada
# carro, em user://. Mesmo formato e mesma versão (v3) do web, para o ranking compartilhado da etapa 11.
class_name Records
extends RefCounted

# v3: R8 e motores centrais recalibrados (07/11/2026), igual à chave do web
const PATH := "user://recordes-interlagos-v3.json"
const SETTINGS := "user://ajustes.cfg"


## [{nick, carId, time, sectors, date}]
static func load_all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return v if v is Array else []


## Grava a volta se for válida e o melhor tempo desse nick nesse carro. Devolve true se virou recorde pessoal.
static func save_lap(nick: String, car_id: String, lap: LapTimer.Lap) -> bool:
	if not lap.valid or nick == "":
		return false
	var all := load_all()
	var i := -1
	for k in all.size():
		if all[k].nick == nick and all[k].carId == car_id:
			i = k
	if i >= 0 and float(all[i].time) <= lap.time:
		return false
	var rec := {"nick": nick, "carId": car_id, "time": lap.time, "sectors": lap.sectors,
		"date": Time.get_datetime_string_from_system(true) + "Z"}
	if i >= 0:
		all[i] = rec
	else:
		all.append(rec)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
	return true


static func top(n: int) -> Array:
	var all := load_all()
	all.sort_custom(func(a, b): return float(a.time) < float(b.time))
	return all.slice(0, n)


static func load_nick() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return ""
	return String(cfg.get_value("jogador", "nick", ""))


static func save_nick(nick: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("jogador", "nick", nick)
	cfg.save(SETTINGS)
