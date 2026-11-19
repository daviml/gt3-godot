# Gerenciador leve de efeitos sonoros de interface (botões, abas, início de sessão e voltas).
class_name UiAudio
extends Node

const POOL_SIZE := 4

var _players: Array[AudioStreamPlayer] = []
var _pool_idx := 0
static var _stream_cache: Dictionary = {}


func _ready() -> void:
	_ensure_fx_bus()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "FX"
		add_child(p)
		_players.append(p)


func _ensure_fx_bus() -> void:
	if AudioServer.get_bus_index("FX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "FX")
		AudioServer.set_bus_send(idx, "Master")


func _get_stream(fx_name: String) -> AudioStreamWAV:
	if _stream_cache.has(fx_name):
		return _stream_cache[fx_name] as AudioStreamWAV
	var sounds := CarAudio.get_sounds_data()
	var fx_data: Dictionary = sounds.get("fx", {})
	var path: String = fx_data.get(fx_name, "")
	if path != "" and ResourceLoader.exists(path):
		var wav := load(path) as AudioStreamWAV
		if wav != null:
			_stream_cache[fx_name] = wav
			return wav
	return null


func play(fx_name: String, vol := 0.40, pitch := 1.0) -> void:
	if _players.is_empty() or not is_inside_tree():
		return
	var wav := _get_stream(fx_name)
	if wav == null:
		return
	var p := _players[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = wav
	p.volume_db = linear_to_db(maxf(0.0001, vol))
	p.pitch_scale = pitch
	p.play()
