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
## a função da Vercel lê o GitHub; na partida a frio pode passar de 10 s
const HTTP_TIMEOUT := 20.0
## novas tentativas de leitura do ranking quando a rede/servidor falha
const FETCH_RETRIES := 3
const FETCH_RETRY_DELAY := 4.0

## Os testes chamam use_test_storage() para gravar em user://testes/ e nunca mexer nos recordes de verdade.
static var _dir := "user://"


static func use_test_storage() -> void:
	_dir = "user://testes/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))


static func _mode_of(mode: String) -> String:
	var m := mode if mode != "" else Game.mode
	return "arcade" if m == "arcade" else "sim"


static func path_for(mode := "") -> String:
	var p := PATH_ARCADE if _mode_of(mode) == "arcade" else PATH_SIM
	return p.replace("user://", _dir)


## Última cópia do ranking compartilhado, para mostrar já ao abrir o jogo (e sem internet)
static func cache_path(mode := "") -> String:
	return "%sranking-cache-%s.json" % [_dir, remote_mode(mode)]


static func save_cache(mode: String, voltas: Array) -> void:
	if voltas.is_empty():
		return
	var f := FileAccess.open(cache_path(mode), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(voltas))


static func load_cache(mode := "") -> Array:
	var p := cache_path(mode)
	if not FileAccess.file_exists(p):
		return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Array else []


## Ranking para exibir: compartilhado (o recebido agora ou a cópia guardada) mesclado com os recordes deste PC
static func ranking(n: int, mode := "", remote: Array = []) -> Array:
	var shared := remote if not remote.is_empty() else load_cache(mode)
	return merge_records(shared, load_all(mode)).slice(0, n)


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


## Mescla recordes remotos e locais, mantendo o melhor tempo de cada nick em cada carro
static func merge_records(remote: Array, local: Array) -> Array:
	var by_key := {}
	for r in remote:
		if r is Dictionary and r.has("nick") and r.has("carId") and r.has("time"):
			var key := "%s|%s" % [String(r.nick).strip_edges().to_lower(), String(r.carId)]
			by_key[key] = r
	for l in local:
		if l is Dictionary and l.has("nick") and l.has("carId") and l.has("time"):
			var key := "%s|%s" % [String(l.nick).strip_edges().to_lower(), String(l.carId)]
			if not by_key.has(key) or float(l.time) < float(by_key[key].time):
				by_key[key] = l
	var res := by_key.values()
	res.sort_custom(func(a, b): return float(a.time) < float(b.time))
	return res


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
	var _fetch_mode := ""
	var _fetch_tries := 0

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
		_fetch_cb = on_done
		_fetch_mode = mode
		_fetch_tries = 0
		_start_fetch()

	func _start_fetch() -> void:
		_fetch_req.cancel_request()
		_fetch_tries += 1
		var mode := _fetch_mode
		_fetch_expected_rmode = Records.remote_mode(mode)
		var err := _fetch_req.request(Records.ranking_url(mode), ["Accept: application/json"], HTTPClient.METHOD_GET)
		if err != OK:
			_fetch_failed()

	## Falhou: tenta de novo algumas vezes antes de avisar (servidor frio, Wi-Fi do celular acordando...)
	func _fetch_failed() -> void:
		var m := "arcade" if _fetch_expected_rmode == "godot-arcade" else "sim"
		if _fetch_tries < Records.FETCH_RETRIES and is_inside_tree():
			var rmode := _fetch_expected_rmode
			await get_tree().create_timer(Records.FETCH_RETRY_DELAY).timeout
			# só tenta de novo se ninguém pediu outro modo nesse meio-tempo
			if is_inside_tree() and _fetch_expected_rmode == rmode and _fetch_req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				_start_fetch()
			return
		push_warning("Ranking compartilhado indisponível (%s); mostrando a cópia guardada" % Records.ranking_url(m))
		_pending_post = {}
		if _fetch_cb.is_valid():
			_fetch_cb.call(false, [], m)

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
			_fetch_failed()
			return
		var parsed := Records.parse_ranking_response(response_code, body, _fetch_expected_rmode)
		if bool(parsed.get("ok", false)):
			_verified_modes[_fetch_expected_rmode] = true
			Records.save_cache(m, parsed.voltas)
			if _fetch_cb.is_valid():
				_fetch_cb.call(true, parsed.voltas, m)
			if not _pending_post.is_empty() and String(_pending_post.get("rmode", "")) == _fetch_expected_rmode:
				var pp := _pending_post
				_pending_post = {}
				_send_post(pp.rmode, pp.payload, pp.mode, pp.cb)
		else:
			_fetch_failed()

	func _on_post_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var m := "arcade" if _post_expected_rmode == "godot-arcade" else "sim"
		if result != HTTPRequest.RESULT_SUCCESS:
			if _post_cb.is_valid():
				_post_cb.call(false, false, [], m)
			return
		var parsed := Records.parse_volta_response(response_code, body, _post_expected_rmode)
		if _post_cb.is_valid():
			if bool(parsed.get("ok", false)):
				Records.save_cache(m, parsed.voltas)
				_post_cb.call(true, bool(parsed.get("recorde", false)), parsed.voltas, m)
			else:
				_post_cb.call(false, false, [], m)


static func load_nick() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		var n := String(cfg.get_value("jogador", "nick", "")).strip_edges()
		if n != "":
			return n
	if cfg.load(Game.CFG) == OK:
		var n := String(cfg.get_value("jogador", "nick", "")).strip_edges()
		if n != "":
			save_nick(n)
			return n
	# Migração caso exista pasta antiga com nome diferente (ex.: protótipo)
	var user_dir := OS.get_user_data_dir()
	var base_dir := user_dir.get_base_dir()
	if base_dir != "":
		for candidate in ["GT3 Godot (protótipo)", "gt3-godot"]:
			var p := base_dir.path_join(candidate).path_join("ajustes.cfg")
			if FileAccess.file_exists(p):
				var old_cfg := ConfigFile.new()
				if old_cfg.load(p) == OK:
					var n := String(old_cfg.get_value("jogador", "nick", "")).strip_edges()
					if n != "":
						save_nick(n)
						return n
	var env_user := OS.get_environment("USERNAME").strip_edges()
	if env_user != "":
		return env_user
	return "Piloto"


static func save_nick(nick: String) -> void:
	var clean := nick.strip_edges()
	if clean == "":
		clean = "Piloto"
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("jogador", "nick", clean)
	cfg.save(SETTINGS)

	var gcfg := ConfigFile.new()
	gcfg.load(Game.CFG)
	gcfg.set_value("jogador", "nick", clean)
	gcfg.save(Game.CFG)
