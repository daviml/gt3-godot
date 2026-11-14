# Melhores tempos guardados neste PC e sincronizados com o ranking compartilhado: o jogo lê e grava direto no repo
# privado daviml/gt3-tempos (API de conteúdo do GitHub), sem servidor no meio. O token fica em res://segredos.cfg,
# fora do Git, e só entra no executável/APK exportado num PC que tenha o arquivo (ver tools/segredos.md).
# A melhor volta válida de cada nick em cada carro, separados por modo (Simulador vs Arcade).
class_name Records
extends RefCounted

# v3: R8 e motores centrais recalibrados (07/11/2026), igual à chave do web
const PATH_SIM := "user://recordes-interlagos-v3.json"
const PATH := PATH_SIM
const PATH_ARCADE := "user://recordes-interlagos-godot-arcade.json"
const SETTINGS := "user://ajustes.cfg"

const SECRETS := "res://segredos.cfg"
const GH_CONTENTS := "https://api.github.com/repos/daviml/gt3-tempos/contents/"
const GH_BRANCH := "main"
## mesmos arquivos e limites que a antiga função da Vercel usava
const REMOTE_FILES := {"godot-sim": "interlagos-godot.json", "godot-arcade": "interlagos-godot-arcade.json"}
const MIN_TIME := {"godot-sim": 85.0, "godot-arcade": 60.0}
## chave só para o token não ficar em texto puro no pacote exportado (não é criptografia)
const SCRAMBLE_KEY := "gt3-interlagos-2026"
const HTTP_TIMEOUT := 20.0
## novas tentativas de leitura do ranking quando a rede falha
const FETCH_RETRIES := 3
const FETCH_RETRY_DELAY := 4.0
## tentativas de gravação quando outro amigo gravou no mesmo instante (GitHub responde 409)
const POST_RETRIES := 4

## Os testes chamam use_test_storage() para gravar em user://testes/ e nunca mexer nos recordes de verdade.
static var _dir := "user://"


static func use_test_storage() -> void:
	_dir = "user://testes/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))


static func _mode_of(mode: String) -> String:
	var m := mode if mode != "" else Game.mode
	return "arcade" if m == "arcade" else "sim"


## Interlagos usa os arquivos de sempre (PATH_SIM/PATH_ARCADE); as outras pistas, os de data/tracks.json → records
static func path_for(mode := "") -> String:
	var m := _mode_of(mode)
	var p := PATH_ARCADE if m == "arcade" else PATH_SIM
	if not _is_default_track():
		var recs = Game.get_track_info().get("records", {})
		p = String(recs.get(m, "")) if recs is Dictionary else ""
		if p == "":
			p = "user://recordes-%s-%s.json" % [Game.track_id, m]
	return p.replace("user://", _dir)


static func _is_default_track() -> bool:
	return Game.track_id == Game.DEFAULT_TRACK


## sufixo dos arquivos que não existiam antes do multi-pista (Interlagos: nenhum, nomes de sempre)
static func _track_suffix() -> String:
	return "" if _is_default_track() else "-" + Game.track_id


## Última cópia do ranking compartilhado, para mostrar já ao abrir o jogo (e sem internet)
static func cache_path(mode := "") -> String:
	return "%sranking-cache-%s%s.json" % [_dir, remote_mode(mode), _track_suffix()]


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


## arquivo do ranking no repo gt3-tempos: Interlagos usa os de sempre; as outras, <remote_key>-godot(-arcade).json
static func remote_file(mode := "") -> String:
	if _is_default_track():
		return REMOTE_FILES[remote_mode(mode)]
	var key := String(Game.get_track_info().get("remote_key", Game.track_id))
	if key == "":
		key = Game.track_id
	return "%s-%s.json" % [key, remote_mode(mode)]


## tempo mínimo aceito no ranking (anti-trapaça): Interlagos MIN_TIME; outras pistas, data/tracks.json → min_lap
static func min_time(mode := "") -> float:
	var rm := remote_mode(mode)
	if not _is_default_track():
		var ml = Game.get_track_info().get("min_lap", {})
		if ml is Dictionary and ml.has(_mode_of(mode)):
			return float(ml[_mode_of(mode)])
	return float(MIN_TIME[rm])


static func contents_url(mode := "", with_ref := true) -> String:
	return GH_CONTENTS + remote_file(mode) + ("?ref=" + GH_BRANCH if with_ref else "")


# ------------------------------------------------------------------ token (res://segredos.cfg)

static var _token := ""
static var _token_loaded := false


static func scramble(token: String) -> String:
	return Marshalls.raw_to_base64(_xor(token.to_utf8_buffer()))


static func unscramble(text: String) -> String:
	return _xor(Marshalls.base64_to_raw(text)).get_string_from_utf8()


static func _xor(data: PackedByteArray) -> PackedByteArray:
	var key := SCRAMBLE_KEY.to_utf8_buffer()
	var out := data.duplicate()
	for i in out.size():
		out[i] = out[i] ^ key[i % key.size()]
	return out


## Token do GitHub ("" se o jogo foi exportado sem o segredos.cfg: aí só mostra a cópia guardada do ranking)
static func github_token() -> String:
	if not _token_loaded:
		_token_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(SECRETS) == OK:
			_token = String(cfg.get_value("ranking", "github_token", "")).strip_edges()
			var x := String(cfg.get_value("ranking", "github_token_x", "")).strip_edges()
			if _token == "" and x != "":
				_token = unscramble(x).strip_edges()
	return _token


static func gh_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + github_token(),
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: gt3-time-attack-godot",
		"Content-Type: application/json",
	])


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


# ------------------------------------------------------------------ ranking compartilhado (GitHub)

## Confere a volta como a antiga função da Vercel fazia; devolve o registro limpo ou {} se não puder ir pro ranking.
static func validate_remote(nick: String, car_id: String, time: float, sectors: Array, valid: bool, mode := "") -> Dictionary:
	var clean := nick.strip_edges()
	for ch in ["<", ">", "\"", "'", "&"]:
		clean = clean.replace(ch, "")
	clean = clean.left(16)
	if clean == "" or not valid or Game.get_car_info(car_id).is_empty():
		return {}
	var min_t: float = min_time(mode)
	if not (time > min_t and time < 360.0) or sectors.size() != 3:
		return {}
	var secs := []
	var total := 0.0
	for x in sectors:
		if not (float(x) > 10.0):
			return {}
		secs.append(snappedf(float(x), 0.001))
		total += float(x)
	if absf(total - time) > 0.05:
		return {}
	return {"nick": clean, "carId": car_id, "time": snappedf(time, 0.001), "sectors": secs,
		"date": Time.get_datetime_string_from_system(true) + "Z"}


## Resposta da API de conteúdo do GitHub -> {ok, voltas, sha}. Arquivo ainda inexistente (404) = ranking vazio.
static func parse_contents(response_code: int, body: PackedByteArray) -> Dictionary:
	if response_code == 404:
		return {"ok": true, "voltas": [], "sha": ""}
	if response_code < 200 or response_code >= 300:
		return {"ok": false}
	var j = JSON.parse_string(body.get_string_from_utf8())
	if not (j is Dictionary) or not j.has("content"):
		return {"ok": false}
	var text := Marshalls.base64_to_utf8(String(j.content).replace("\n", ""))
	var data = JSON.parse_string(text)
	var voltas = data.get("voltas", []) if data is Dictionary else data
	if not (voltas is Array):
		return {"ok": false}
	return {"ok": true, "voltas": voltas, "sha": String(j.get("sha", ""))}


## Coloca a volta no ranking se for o recorde desse nick nesse carro -> {recorde, voltas}
static func merge_remote(voltas: Array, rec: Dictionary) -> Dictionary:
	var list := voltas.duplicate()
	var found := false
	for i in list.size():
		var v = list[i]
		if v is Dictionary and String(v.get("nick", "")) == rec.nick and String(v.get("carId", "")) == rec.carId:
			if float(v.get("time", INF)) <= float(rec.time):
				return {"recorde": false, "voltas": voltas}
			list[i] = rec
			found = true
			break
	if not found:
		list.append(rec)
	list.sort_custom(func(a, b): return float(a.time) < float(b.time))
	return {"recorde": true, "voltas": list}


## Mesmo formato que a Vercel gravava: {"voltas": [...]}, com a ordem dos campos preservada
static func encode_file(voltas: Array) -> String:
	return JSON.stringify({"voltas": voltas}, " ", false)


## Cliente assíncrono que lê e grava o ranking direto no GitHub. Ao ler, também envia os recordes deste PC que ainda
## não estão lá (voltas feitas sem internet ou enquanto o ranking estava fora do ar).
class RemoteClient:
	extends Node

	var _fetch_serial := 0
	var _queue: Array = []
	var _queued := {}
	var _posting := false

	func _http(url: String, method := HTTPClient.METHOD_GET, body := "") -> Array:
		var req := HTTPRequest.new()
		req.timeout = Records.HTTP_TIMEOUT
		add_child(req)
		if req.request(url, Records.gh_headers(), method, body) != OK:
			req.queue_free()
			return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray()]
		var r: Array = await req.request_completed
		req.queue_free()
		return [r[0], r[1], r[3]]

	func _read(m: String) -> Dictionary:
		var r: Array = await _http(Records.contents_url(m))
		if r[0] != HTTPRequest.RESULT_SUCCESS:
			return {"ok": false}
		return Records.parse_contents(r[1], r[2])

	func fetch_ranking(mode: String, on_done: Callable) -> void:
		_fetch_serial += 1
		var serial := _fetch_serial
		var m := Records._mode_of(mode)
		if Records.github_token() == "":
			if on_done.is_valid():
				on_done.call(false, [], m)
			return
		for t in Records.FETCH_RETRIES:
			var res: Dictionary = await _read(m)
			if serial != _fetch_serial:
				return
			if bool(res.get("ok", false)):
				Records.save_cache(m, res.voltas)
				if on_done.is_valid():
					on_done.call(true, res.voltas, m)
				_sync_local(m, res.voltas, on_done)
				return
			if t < Records.FETCH_RETRIES - 1:
				await get_tree().create_timer(Records.FETCH_RETRY_DELAY).timeout
				if serial != _fetch_serial:
					return
		push_warning("Ranking compartilhado indisponível (%s); mostrando a cópia guardada" % Records.remote_file(m))
		if on_done.is_valid():
			on_done.call(false, [], m)

	func post_lap(nick: String, car_id: String, lap: LapTimer.Lap, mode: String, on_done: Callable) -> void:
		var m := Records._mode_of(mode)
		var rec := Records.validate_remote(nick, car_id, lap.time, Array(lap.sectors), lap.valid, m)
		if rec.is_empty() or Records.github_token() == "":
			return
		_enqueue(rec, m, on_done)

	## Recordes deste PC melhores que os do ranking (ou que nem estão lá) vão para a fila de envio
	func _sync_local(m: String, remote: Array, on_done: Callable) -> void:
		for l in Records.load_all(m):
			if not (l is Dictionary):
				continue
			var rec := Records.validate_remote(String(l.get("nick", "")), String(l.get("carId", "")),
				float(l.get("time", 0.0)), Array(l.get("sectors", [])), true, m)
			if rec.is_empty():
				continue
			if l.has("date"):
				rec.date = String(l.date)
			if bool(Records.merge_remote(remote, rec).recorde):
				_enqueue(rec, m, func(ok: bool, is_rec: bool, voltas: Array, mm: String):
					if ok and is_rec and on_done.is_valid():
						on_done.call(true, voltas, mm))

	func _enqueue(rec: Dictionary, m: String, cb: Callable) -> void:
		var key := "%s|%s|%s|%s" % [m, rec.nick, rec.carId, rec.time]
		if _queued.has(key):
			return
		_queued[key] = true
		_queue.append({"rec": rec, "mode": m, "cb": cb, "key": key})
		if not _posting:
			_pump()

	func _pump() -> void:
		_posting = true
		while not _queue.is_empty():
			var item: Dictionary = _queue.pop_front()
			var res: Dictionary = await _register(item.rec, item.mode)
			_queued.erase(item.key)
			if bool(res.get("ok", false)):
				Records.save_cache(item.mode, res.voltas)
			var cb: Callable = item.cb
			if cb.is_valid():
				if bool(res.get("ok", false)):
					cb.call(true, bool(res.recorde), res.voltas, item.mode)
				else:
					cb.call(false, false, [], item.mode)
		_posting = false

	## Lê o arquivo, mescla a volta e grava (um commit). Se outro amigo gravou no meio (409/422), lê e tenta de novo.
	func _register(rec: Dictionary, m: String) -> Dictionary:
		for t in Records.POST_RETRIES:
			var cur: Dictionary = await _read(m)
			if not bool(cur.get("ok", false)):
				return {"ok": false}
			var merged := Records.merge_remote(cur.voltas, rec)
			if not bool(merged.recorde):
				return {"ok": true, "recorde": false, "voltas": cur.voltas}
			var body := {
				"message": "%s: %.3f s (%s, %s)" % [rec.nick, float(rec.time), rec.carId, Records.remote_mode(m)],
				"content": Marshalls.utf8_to_base64(Records.encode_file(merged.voltas)),
				"branch": Records.GH_BRANCH,
			}
			if String(cur.sha) != "":
				body["sha"] = cur.sha
			var r: Array = await _http(Records.contents_url(m, false), HTTPClient.METHOD_PUT, JSON.stringify(body))
			if r[0] == HTTPRequest.RESULT_SUCCESS and (r[1] == 200 or r[1] == 201):
				return {"ok": true, "recorde": true, "voltas": merged.voltas}
			if r[0] != HTTPRequest.RESULT_SUCCESS or not (r[1] == 409 or r[1] == 422):
				push_warning("Não foi possível gravar a volta no ranking (HTTP %d)" % r[1])
				return {"ok": false}
		return {"ok": false}


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
