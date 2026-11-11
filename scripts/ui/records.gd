# Melhores tempos guardados neste PC e sincronizados com o ranking compartilhado (gt3-time-attack.vercel.app):
# a melhor volta válida de cada nick em cada carro, separados por modo (Simulador vs Arcade).
class_name Records
extends RefCounted

# v3: R8 e motores centrais recalibrados (07/11/2026), igual à chave do web
const PATH_SIM := "user://recordes-interlagos-v3.json"
const PATH := PATH_SIM
const PATH_ARCADE := "user://recordes-interlagos-godot-arcade.json"
const SETTINGS := "user://ajustes.cfg"
const API_BASE := "https://gt3-time-attack.vercel.app"
const HTTP_TIMEOUT := 10.0


static func _mode_of(mode: String) -> String:
	var m := mode if mode != "" else Game.mode
	return "arcade" if m == "arcade" else "sim"


static func path_for(mode := "") -> String:
	return PATH_ARCADE if _mode_of(mode) == "arcade" else PATH_SIM


static func remote_mode(mode := "") -> String:
	return "godot-arcade" if _mode_of(mode) == "arcade" else "godot-sim"


static func ranking_url(mode := "") -> String:
	return "%s/api/ranking?modo=%s" % [API_BASE, remote_mode(mode)]


static func volta_url() -> String:
	return "%s/api/volta" % API_BASE


## [{nick, carId, time, sectors, date}]
static func load_all(mode := "") -> Array:
	var p := path_for(mode)
	if not FileAccess.file_exists(p):
		return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Array else []


## Grava a volta se for válida e o melhor tempo desse nick nesse carro. Devolve true se virou recorde pessoal.
static func save_lap(nick: String, car_id: String, lap: LapTimer.Lap, mode := "") -> bool:
	var clean_nick := nick.strip_edges()
	if not lap.valid or clean_nick == "":
		return false
	var all := load_all(mode)
	var i := -1
	for k in all.size():
		if all[k].nick == clean_nick and all[k].carId == car_id:
			i = k
	if i >= 0 and float(all[i].time) <= lap.time:
		return false
	var rec := {"nick": clean_nick, "carId": car_id, "time": lap.time, "sectors": Array(lap.sectors),
		"date": Time.get_datetime_string_from_system(true) + "Z"}
	if i >= 0:
		all[i] = rec
	else:
		all.append(rec)
	var f := FileAccess.open(path_for(mode), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
	return true


static func top(n: int, mode := "") -> Array:
	var all := load_all(mode)
	all.sort_custom(func(a, b): return float(a.time) < float(b.time))
	return all.slice(0, n)


static func build_volta_payload(nick: String, car_id: String, lap: LapTimer.Lap, mode := "") -> String:
	return JSON.stringify({
		"nick": nick.strip_edges(),
		"carId": car_id,
		"time": lap.time,
		"sectors": Array(lap.sectors),
		"valid": lap.valid,
		"modo": remote_mode(mode),
	})


static func parse_ranking_response(response_code: int, body: PackedByteArray, expected_remote_mode: String) -> Dictionary:
	if response_code < 200 or response_code >= 300:
		return {"ok": false}
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false}
	if String(parsed.get("modo", "")) != expected_remote_mode:
		return {"ok": false}
	var voltas = parsed.get("voltas", null)
	if not (voltas is Array):
		return {"ok": false}
	return {"ok": true, "voltas": voltas}


static func parse_volta_response(response_code: int, body: PackedByteArray, expected_remote_mode: String) -> Dictionary:
	if response_code < 200 or response_code >= 300:
		return {"ok": false}
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false}
	if String(parsed.get("modo", "")) != expected_remote_mode:
		return {"ok": false}
	var voltas = parsed.get("voltas", null)
	if not (voltas is Array):
		return {"ok": false}
	return {"ok": true, "recorde": bool(parsed.get("recorde", false)), "voltas": voltas}


## Cliente HTTP assíncrono para ler e gravar recordes no repositório compartilhado (mesma API do gt3-time-attack).
## Valida o campo "modo" na resposta do servidor antes de exibir ou enviar tempos, evitando misturar com o ranking web
## caso a API remota ainda não esteja atualizada.
class RemoteClient:
	extends Node

	var _fetch_req: HTTPRequest
	var _post_req: HTTPRequest
	var _fetch_cb: Callable
	var _fetch_expected_rmode := ""
	var _post_cb: Callable
	var _post_expected_rmode := ""
	var _verified_modes := {}
	var _pending_post: Dictionary = {}

	func _ready() -> void:
		_fetch_req = HTTPRequest.new()
		_fetch_req.timeout = HTTP_TIMEOUT
		_fetch_req.request_completed.connect(_on_fetch_done)
		add_child(_fetch_req)

		_post_req = HTTPRequest.new()
		_post_req.timeout = HTTP_TIMEOUT
		_post_req.request_completed.connect(_on_post_done)
		add_child(_post_req)

	func fetch_ranking(mode: String, on_done: Callable) -> void:
		if _fetch_req == null:
			return
		_fetch_req.cancel_request()
		_fetch_cb = on_done
		_fetch_expected_rmode = Records.remote_mode(mode)
		var err := _fetch_req.request(Records.ranking_url(mode), ["Accept: application/json"], HTTPClient.METHOD_GET)
		if err != OK and _fetch_cb.is_valid():
			_fetch_cb.call(false, [], mode)

	func post_lap(nick: String, car_id: String, lap: LapTimer.Lap, mode: String, on_done: Callable) -> void:
		var clean_nick := nick.strip_edges()
		if _post_req == null or clean_nick == "" or not lap.valid:
			return
		var rmode := Records.remote_mode(mode)
		var payload := Records.build_volta_payload(clean_nick, car_id, lap, mode)
		if not bool(_verified_modes.get(rmode, false)):
			# Verifica o suporte do servidor ao modo Godot antes de enviar POST
			_pending_post = {"rmode": rmode, "payload": payload, "mode": mode, "cb": on_done}
			if _fetch_expected_rmode != rmode or _fetch_req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				fetch_ranking(mode, _fetch_cb if _fetch_expected_rmode == rmode else Callable())
			return
		_send_post(rmode, payload, mode, on_done)

	func _send_post(rmode: String, payload: String, mode: String, on_done: Callable) -> void:
		_post_req.cancel_request()
		_post_cb = on_done
		_post_expected_rmode = rmode
		var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
		var err := _post_req.request(Records.volta_url(), headers, HTTPClient.METHOD_POST, payload)
		if err != OK and _post_cb.is_valid():
			_post_cb.call(false, false, [], mode)

	func _on_fetch_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var m := "arcade" if _fetch_expected_rmode == "godot-arcade" else "sim"
		if result != HTTPRequest.RESULT_SUCCESS:
			if _fetch_cb.is_valid():
				_fetch_cb.call(false, [], m)
			return
		var parsed := Records.parse_ranking_response(response_code, body, _fetch_expected_rmode)
		if bool(parsed.get("ok", false)):
			_verified_modes[_fetch_expected_rmode] = true
			if _fetch_cb.is_valid():
				_fetch_cb.call(true, parsed.voltas, m)
			if not _pending_post.is_empty() and String(_pending_post.get("rmode", "")) == _fetch_expected_rmode:
				var pp := _pending_post
				_pending_post = {}
				_send_post(pp.rmode, pp.payload, pp.mode, pp.cb)
		else:
			_pending_post = {}
			if _fetch_cb.is_valid():
				_fetch_cb.call(false, [], m)

	func _on_post_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var m := "arcade" if _post_expected_rmode == "godot-arcade" else "sim"
		if result != HTTPRequest.RESULT_SUCCESS:
			if _post_cb.is_valid():
				_post_cb.call(false, false, [], m)
			return
		var parsed := Records.parse_volta_response(response_code, body, _post_expected_rmode)
		if _post_cb.is_valid():
			if bool(parsed.get("ok", false)):
				_post_cb.call(true, bool(parsed.get("recorde", false)), parsed.voltas, m)
			else:
				_post_cb.call(false, false, [], m)


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
