# Som do carro em Godot 4 com gravações reais (engine-sim / Stunt Rally 3, CC-BY-4.0).
# Baseado na implementação de referência do web (src/audio/sound.ts):
# - Motor: gravações a cada 1000 rpm (ou 1100 rpm no tsp); os dois loops vizinhos tocam juntos com
#   crossfade de mesma potência (cos/sin) e pitch_scale corrigido para o giro exato.
# - Carga e corte: filtro low-pass nativo na bus "Engine" abrindo com o acelerador (900 Hz a 16+ kHz)
#   e abafando na desaceleração; oscilação e corte no limitador.
# - Turbo e blow-off: assobio proporcional a (giro/limitador)^2 * acelerador; válvula de alívio ao tirar o pé.
# - Pneus, superfícies, vento e batidas: pneu cantando proporcional ao slip além do pico,
#   sons de grama e brita/escape, vento em alta velocidade e batida periódica ao andar sobre zebras.
# - Native Audio Buses: Master, Engine (com AudioEffectLowPassFilter), Tires, Surface, Wind, FX.
class_name CarAudio
extends Node

const SOUNDS_JSON := "res://data/sounds.json"

var car: Car
var car_id: String
var sound_spec: Dictionary = {}
var limiter_rpm := 8500.0

# Buses nativas e efeitos
var engine_bus_idx := -1
var engine_filter: AudioEffectLowPassFilter

# Estrutura dos loops de motor: Array de { "rpm": float, "player": AudioStreamPlayer, "gain": float, "pitch": float }
var engine_loops: Array[Dictionary] = []
var filter_cutoff := 15000.0
var engine_overall_gain := 0.42
var time_accum := 0.0

# FX Contínuos (Loops)
var turbo_player: AudioStreamPlayer
var tyre_player: AudioStreamPlayer
var grass_player: AudioStreamPlayer
var gravel_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer

var turbo_gain := 0.0
var turbo_pitch := 1.0
var tyre_gain := 0.0
var tyre_pitch := 1.0
var grass_gain := 0.0
var gravel_gain := 0.0
var wind_gain := 0.0
var wind_pitch := 1.0

# Estado para gatilhos de one-shot
var last_throttle := 0.0
var last_shift := 0
var kerb_dist := 0.0
var is_audio_paused := false

# Cache de streams para one-shots
var fx_streams: Dictionary = {}
var oneshot_pool: Array[AudioStreamPlayer] = []
var oneshot_pool_idx := 0
const POOL_SIZE := 8
var _preloaded_streams: Dictionary = {}
static var _sounds_data_cache: Dictionary = {}


static func get_sounds_data() -> Dictionary:
	if _sounds_data_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS_JSON))
		if parsed is Dictionary:
			_sounds_data_cache = parsed
	return _sounds_data_cache


static func get_preload_paths(p_car_id: String) -> Array[String]:
	var paths: Array[String] = []
	var car_json := Game.get_car_data(p_car_id)
	var spec: Dictionary = car_json.get("sound", {"bank": "tsp", "turbo": false})
	var sounds_data := get_sounds_data()
	var banks: Dictionary = sounds_data.get("banks", {})
	var fx_data: Dictionary = sounds_data.get("fx", {})
	for k in fx_data:
		var p: String = fx_data[k]
		if ResourceLoader.exists(p) and not p in paths:
			paths.append(p)
	var bank_name: String = spec.get("bank", "tsp")
	for item in banks.get(bank_name, []):
		var p: String = item.file
		if ResourceLoader.exists(p) and not p in paths:
			paths.append(p)
	return paths


func _init(p_car: Car = null, p_car_id: String = "corvette-c6r-gt3", preloaded_streams: Dictionary = {}) -> void:
	_ensure_buses()
	if p_car != null:
		setup(p_car, p_car_id, preloaded_streams)


func _ready() -> void:
	_ensure_buses()
	_start_loops()


## Inicializa configuração do carro e dados sonoros
func setup(p_car: Car, p_car_id: String, preloaded_streams: Dictionary = {}) -> void:
	_ensure_buses()
	car = p_car
	car_id = p_car_id
	_preloaded_streams = preloaded_streams
	if car and car.p:
		limiter_rpm = float(car.p.get("limiter", 8500.0))

	# Carrega sound_spec do carro
	var car_json := Game.get_car_data(car_id)
	if not car_json.is_empty():
		sound_spec = car_json.get("sound", {"bank": "tsp", "turbo": false})
	else:
		sound_spec = {"bank": "tsp", "turbo": false}

	_build_nodes()


## Garante que as buses de áudio nativas da Godot existam e estejam configuradas
func _ensure_buses() -> void:
	var required_buses := ["Engine", "Tires", "Surface", "Wind", "FX"]
	for b in required_buses:
		var idx := AudioServer.get_bus_index(b)
		if idx == -1:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")

	engine_bus_idx = AudioServer.get_bus_index("Engine")
	# Procura ou adiciona o filtro LowPass na bus Engine
	for e in AudioServer.get_bus_effect_count(engine_bus_idx):
		var fx := AudioServer.get_bus_effect(engine_bus_idx, e)
		if fx is AudioEffectLowPassFilter:
			engine_filter = fx
			break

	if engine_filter == null:
		engine_filter = AudioEffectLowPassFilter.new()
		engine_filter.cutoff_hz = 15000.0
		engine_filter.resonance = 0.7
		AudioServer.add_bus_effect(engine_bus_idx, engine_filter)


## Constrói os players de áudio para motor, efeitos contínuos e pool de one-shots
func _build_nodes() -> void:
	# Limpa nós anteriores se houver
	for c in get_children():
		c.queue_free()
	engine_loops.clear()
	fx_streams.clear()
	oneshot_pool.clear()

	var sounds_data: Dictionary = get_sounds_data()
	var banks: Dictionary = sounds_data.get("banks", {})
	var fx_data: Dictionary = sounds_data.get("fx", {})

	# Pré-carrega efeitos FX
	for k in fx_data:
		var path: String = fx_data[k]
		var stream: AudioStreamWAV = _preloaded_streams.get(path) as AudioStreamWAV
		if stream == null and ResourceLoader.exists(path):
			stream = load(path)
		if stream != null:
			fx_streams[k] = stream

	# 1. Loops do Banco de Motor
	var bank_name: String = sound_spec.get("bank", "tsp")
	var bank_files: Array = banks.get(bank_name, [])
	for item in bank_files:
		var path: String = item.file
		var rpm: float = float(item.rpm)
		var wav: AudioStreamWAV = _preloaded_streams.get(path) as AudioStreamWAV
		if wav == null and ResourceLoader.exists(path):
			wav = load(path)
		if wav != null:
			var player := _create_loop_player(wav, "Engine")
			engine_loops.append({
				"rpm": rpm,
				"player": player,
				"gain": 0.0,
				"pitch": 1.0,
				"duration": wav.get_length()
			})

	# Ordena loops de motor por RPM crescente
	engine_loops.sort_custom(func(a, b): return a.rpm < b.rpm)

	# 2. FX Contínuo: Pneus cantando
	if fx_streams.has("tire_squeal_10"):
		tyre_player = _create_loop_player(fx_streams["tire_squeal_10"], "Tires")

	# 3. FX Contínuo: Grama
	if fx_streams.has("grass_10"):
		grass_player = _create_loop_player(fx_streams["grass_10"], "Surface")

	# 4. FX Contínuo: Brita / Escape
	if fx_streams.has("gravel_10"):
		gravel_player = _create_loop_player(fx_streams["gravel_10"], "Surface")

	# 5. FX Contínuo: Vento
	if fx_streams.has("wind"):
		wind_player = _create_loop_player(fx_streams["wind"], "Wind")

	# 6. Pool de One-Shots (trocas de marcha, batidas na zebra)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "FX"
		add_child(p)
		oneshot_pool.append(p)


func _create_loop_player(wav: AudioStreamWAV, bus_name: String) -> AudioStreamPlayer:
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	if wav.loop_end <= 0:
		# Godot não faz loop ao definir LOOP_FORWARD em runtime sem loop_end preenchido
		wav.loop_end = maxi(1, int(round(wav.get_length() * float(wav.mix_rate))))
	var pl := AudioStreamPlayer.new()
	pl.stream = wav
	pl.bus = bus_name
	pl.volume_db = -80.0
	add_child(pl)
	return pl


## Inicia todos os loops com fases desincronizadas para prevenir cancelamento de fase,
## mas já pausados até terem ganho > 0.001 no update().
func _start_loops() -> void:
	for entry in engine_loops:
		var p: AudioStreamPlayer = entry.player
		var dur: float = entry.duration
		p.play(randf() * maxf(0.05, dur * 0.8))
		p.stream_paused = true

	for pl in [tyre_player, grass_player, gravel_player, wind_player, turbo_player]:
		if pl and pl.stream:
			pl.play(randf() * minf(0.5, maxf(0.05, pl.stream.get_length() * 0.5)))
			pl.stream_paused = true


static func _pause_player(pl: AudioStreamPlayer) -> void:
	if pl and not pl.stream_paused:
		pl.volume_db = -80.0
		if pl.playing:
			pl.stream_paused = true


static func _play_player(pl: AudioStreamPlayer, gain: float) -> void:
	pl.volume_db = linear_to_db(maxf(0.0001, gain))
	if pl.stream_paused:
		pl.stream_paused = false
	elif not pl.playing and pl.is_inside_tree():
		pl.play()


## Toca um efeito sonoro pontual do pool de FX
func play_oneshot(fx_name: String, vol: float, pitch := 1.0) -> void:
	if not fx_streams.has(fx_name) or is_audio_paused:
		return
	var stream: AudioStreamWAV = fx_streams[fx_name]
	var player := oneshot_pool[oneshot_pool_idx]
	oneshot_pool_idx = (oneshot_pool_idx + 1) % POOL_SIZE

	player.stream = stream
	player.volume_db = linear_to_db(maxf(0.0001, vol))
	player.pitch_scale = pitch
	if player.is_inside_tree():
		player.play()


## Atualização do áudio chamada a cada quadro (em _process)
func update(dt: float) -> void:
	if car == null or engine_loops.is_empty():
		return
	if is_audio_paused:
		return

	time_accum += dt
	var safe_dt := clampf(dt, 0.001, 0.1)
	var rpm: float = maxf(800.0, car.rpm)
	var thr: float = clampf(car.throttle_out, 0.0, 1.0)
	var speed: float = car.speed()

	# -------------------------------------------------------------
	# 1. Motor: Crossfade de mesma potência entre dois loops vizinhos
	# -------------------------------------------------------------
	var E := engine_loops
	var idx := E.size() - 2
	for j in E.size() - 1:
		if rpm < E[j + 1].rpm:
			idx = j
			break
	var a: Dictionary = E[maxi(0, idx)]
	var b: Dictionary = E[mini(E.size() - 1, idx + 1)]
	var f := clampf((rpm - a.rpm) / maxf(1.0, float(b.rpm - a.rpm)), 0.0, 1.0)

	# Pesos de mesma potência (potência constante = cos^2 + sin^2 = 1)
	var w_a := cos(f * PI * 0.5)
	var w_b := sin(f * PI * 0.5)

	# Carga e filtro LowPass: acelerando o som abre; soltando fica abafado
	var load := pow(thr, 0.7)
	var target_cutoff := clampf(900.0 + load * 15000.0 + rpm * 0.3, 200.0, 20000.0)
	filter_cutoff = lerpf(target_cutoff, filter_cutoff, exp(-safe_dt / 0.05))
	if engine_filter:
		engine_filter.cutoff_hz = filter_cutoff

	# Limitador e oscilação de corte
	var limiter := car.rpm > (limiter_rpm - 40.0)
	var chop := (0.3 if sin(time_accum * 95.0) > 0.0 else 1.0) if limiter else 1.0
	var target_engine_gain := (0.42 + 0.58 * load) * chop
	engine_overall_gain = lerpf(target_engine_gain, engine_overall_gain, exp(-safe_dt / 0.04))

	var k_eng := exp(-safe_dt / 0.03)
	for s in E:
		var is_active := (s == a or s == b)
		var target_w := w_a if s == a else (w_b if s == b else 0.0)
		var pl: AudioStreamPlayer = s.player
		if not is_active and s.gain <= 0.001:
			s.gain = 0.0
			_pause_player(pl)
			continue
		s.gain = lerpf(target_w, s.gain, k_eng)
		var loop_vol: float = s.gain * engine_overall_gain
		if loop_vol > 0.001 or target_w > 0.001:
			var target_pitch := rpm / float(s.rpm)
			s.pitch = lerpf(target_pitch, s.pitch, k_eng)
			_play_player(pl, loop_vol)
			pl.pitch_scale = s.pitch
		else:
			s.gain = 0.0
			_pause_player(pl)

	# -------------------------------------------------------------
	# 2. Turbo desativado (som agudo/incômodo removido)
	# -------------------------------------------------------------
	turbo_gain = 0.0
	last_throttle = thr

	# -------------------------------------------------------------
	# 3. Troca de Marcha (Shift Click)
	# -------------------------------------------------------------
	if car.shift_count != last_shift:
		last_shift = car.shift_count
		play_oneshot("gear_shift1", 0.35, 1.0)

	# -------------------------------------------------------------
	# 4. Pneu Cantando (Slip além do pico) e Superfícies
	# -------------------------------------------------------------
	var skid := 0.0
	var on_grass := 0.0
	var on_gravel := 0.0
	var on_kerb := false

	for w in car.wheels:
		if not w.contact:
			continue
		if w.surface == Ground.GRASS:
			on_grass += 0.25
		elif w.surface == Ground.GRAVEL or w.surface == Ground.RUNOFF:
			on_gravel += 0.25
		else:
			if w.surface == Ground.KERB:
				on_kerb = true
			var sk := w.kappa / car.kappa_peak
			var sa := w.alpha / car.alpha_peak
			var s := sqrt(sk * sk + sa * sa)
			skid = maxf(skid, clampf((s - 0.9) * 2.2, 0.0, 1.0))

	var moving := clampf(speed / 8.0, 0.0, 1.0)

	# Pneu cantando
	if tyre_player:
		var target_tyre_gain := skid * moving * 0.45
		if target_tyre_gain <= 0.001 and tyre_gain <= 0.001:
			tyre_gain = 0.0
			_pause_player(tyre_player)
		else:
			var target_tyre_pitch := 0.85 + skid * 0.25
			tyre_gain = lerpf(target_tyre_gain, tyre_gain, exp(-safe_dt / 0.05))
			tyre_pitch = lerpf(target_tyre_pitch, tyre_pitch, exp(-safe_dt / 0.08))
			if tyre_gain <= 0.001 and target_tyre_gain <= 0.001:
				tyre_gain = 0.0
				_pause_player(tyre_player)
			else:
				_play_player(tyre_player, tyre_gain)
				tyre_player.pitch_scale = tyre_pitch

	# Grama e Brita (mesmo fator exp)
	var k_surf := exp(-safe_dt / 0.08) if (on_grass > 0.0 or grass_gain > 0.001 or on_gravel > 0.0 or gravel_gain > 0.001) else 0.0

	if grass_player:
		var target_grass_gain := on_grass * moving * 0.50
		if target_grass_gain <= 0.001 and grass_gain <= 0.001:
			grass_gain = 0.0
			_pause_player(grass_player)
		else:
			grass_gain = lerpf(target_grass_gain, grass_gain, k_surf)
			if grass_gain <= 0.001 and target_grass_gain <= 0.001:
				grass_gain = 0.0
				_pause_player(grass_player)
			else:
				_play_player(grass_player, grass_gain)

	if gravel_player:
		var target_gravel_gain := on_gravel * moving * 0.60
		if target_gravel_gain <= 0.001 and gravel_gain <= 0.001:
			gravel_gain = 0.0
			_pause_player(gravel_player)
		else:
			gravel_gain = lerpf(target_gravel_gain, gravel_gain, k_surf)
			if gravel_gain <= 0.001 and target_gravel_gain <= 0.001:
				gravel_gain = 0.0
				_pause_player(gravel_player)
			else:
				_play_player(gravel_player, gravel_gain)

	# Vento em alta velocidade
	if wind_player:
		var target_wind_gain := minf(0.35, pow(speed / 75.0, 2.0) * 0.35)
		if target_wind_gain <= 0.001 and wind_gain <= 0.001:
			wind_gain = 0.0
			_pause_player(wind_player)
		else:
			var k_wind := exp(-safe_dt / 0.20)
			var target_wind_pitch := 0.70 + speed / 160.0
			wind_gain = lerpf(target_wind_gain, wind_gain, k_wind)
			wind_pitch = lerpf(target_wind_pitch, wind_pitch, k_wind)
			if wind_gain <= 0.001 and target_wind_gain <= 0.001:
				wind_gain = 0.0
				_pause_player(wind_player)
			else:
				_play_player(wind_player, wind_gain)
				wind_player.pitch_scale = wind_pitch

	# Batida na zebra a cada ~1.5 m
	if on_kerb and speed > 3.0:
		kerb_dist += speed * safe_dt
		if kerb_dist > 1.5:
			kerb_dist = 0.0
			play_oneshot("bump_front1", 0.25, 0.9 + randf() * 0.2)


## Pausa ou despausa a emissão de sons (mantém loops silenciosos pausados)
func set_paused(p: bool) -> void:
	is_audio_paused = p
	for s in engine_loops:
		var pl: AudioStreamPlayer = s.player
		pl.stream_paused = true if p else (float(s.gain) * engine_overall_gain <= 0.001)
	if tyre_player:
		tyre_player.stream_paused = true if p else (tyre_gain <= 0.001)
	if grass_player:
		grass_player.stream_paused = true if p else (grass_gain <= 0.001)
	if gravel_player:
		gravel_player.stream_paused = true if p else (gravel_gain <= 0.001)
	if wind_player:
		wind_player.stream_paused = true if p else (wind_gain <= 0.001)
	if turbo_player:
		turbo_player.stream_paused = true if p else (turbo_gain <= 0.001)


## Zera contadores de estado (ex: ao reiniciar volta com R)
func reset() -> void:
	kerb_dist = 0.0
	if car:
		last_shift = car.shift_count
	last_throttle = 0.0
	tyre_gain = 0.0
	grass_gain = 0.0
	gravel_gain = 0.0
	wind_gain = 0.0
	turbo_gain = 0.0
	for pl in [tyre_player, grass_player, gravel_player, wind_player, turbo_player]:
		if pl:
			pl.volume_db = -80.0
			pl.stream_paused = true
