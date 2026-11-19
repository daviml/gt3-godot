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
var engine_reverb: AudioEffectReverb
var engine_reverb_idx := -1
var quality_level := 2
var wall_reverb_wet := 0.0

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
var kerb_player: AudioStreamPlayer
var brake_squeal_player: AudioStreamPlayer
var gearbox_player: AudioStreamPlayer

var turbo_gain := 0.0
var turbo_pitch := 1.0
var tyre_gain := 0.0
var tyre_pitch := 1.0
var grass_gain := 0.0
var gravel_gain := 0.0
var wind_gain := 0.0
var wind_pitch := 1.0
var kerb_gain := 0.0
var kerb_pitch := 1.0
var brake_squeal_gain := 0.0
var brake_squeal_pitch := 1.0
var gearbox_gain := 0.0
var gearbox_pitch := 1.0

# Estado para gatilhos de one-shot
var last_throttle := 0.0
var last_shift := 0
var last_gear := 1
var kerb_dist := 0.0
var scrape_cooldown := 0.0
var backfire_cooldown := 0.0
var downshift_blip_timer := 0.0
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
	if car:
		last_gear = car.gear
		last_shift = car.shift_count

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
	# Procura ou adiciona os efeitos na bus Engine (LowPassFilter, EQ6, Compressor e Reverb de muro)
	var has_eq := false
	var has_comp := false
	engine_reverb = null
	engine_reverb_idx = -1
	for e in AudioServer.get_bus_effect_count(engine_bus_idx):
		var fx := AudioServer.get_bus_effect(engine_bus_idx, e)
		if fx is AudioEffectLowPassFilter:
			engine_filter = fx
		elif fx is AudioEffectEQ6:
			has_eq = true
		elif fx is AudioEffectCompressor:
			has_comp = true
		elif fx is AudioEffectReverb:
			engine_reverb = fx
			engine_reverb_idx = e

	if engine_filter == null:
		engine_filter = AudioEffectLowPassFilter.new()
		engine_filter.cutoff_hz = 15000.0
		engine_filter.resonance = 0.7
		AudioServer.add_bus_effect(engine_bus_idx, engine_filter)

	if not has_eq:
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(0, 1.5)
		eq.set_band_gain_db(1, 3.0)
		eq.set_band_gain_db(2, 1.5)
		eq.set_band_gain_db(3, -1.0)
		eq.set_band_gain_db(4, 2.5)
		eq.set_band_gain_db(5, 1.0)
		AudioServer.add_bus_effect(engine_bus_idx, eq)

	if not has_comp:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14.0
		comp.ratio = 3.2
		comp.gain = 2.0
		comp.attack_us = 2500.0
		comp.release_ms = 90.0
		AudioServer.add_bus_effect(engine_bus_idx, comp)

	if engine_reverb == null:
		engine_reverb = AudioEffectReverb.new()
		engine_reverb.room_size = 0.20
		engine_reverb.damping = 0.72
		engine_reverb.spread = 0.65
		engine_reverb.hipass = 0.25
		engine_reverb.dry = 1.0
		engine_reverb.wet = 0.0
		AudioServer.add_bus_effect(engine_bus_idx, engine_reverb)
		engine_reverb_idx = AudioServer.get_bus_effect_count(engine_bus_idx) - 1

	set_quality(Game.get_quality_level())
	Game.apply_audio_volumes()


## Ativa ou desativa a ambiência sutil de muro conforme o preset gráfico (apenas Médio/Extremo)
func set_quality(level: int) -> void:
	quality_level = level
	var active := level >= 2
	if engine_bus_idx >= 0 and engine_reverb_idx >= 0:
		AudioServer.set_bus_effect_enabled(engine_bus_idx, engine_reverb_idx, active)
	if not active:
		wall_reverb_wet = 0.0
		if engine_reverb:
			engine_reverb.wet = 0.0


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
				"gain_comp": float(item.get("gain_comp", 1.0)),
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

	# 6. FX Contínuo: Zebra contínua
	if fx_streams.has("kerb_loop"):
		kerb_player = _create_loop_player(fx_streams["kerb_loop"], "Surface")

	# 7. Freio de carbono (brake_squeal) e zumbido de câmbio (gearbox_whine) desativados
	#    (samples sintéticos agudos removidos para evitar efeito de sirene nas freadas)

	# 8. Pool de One-Shots (trocas de marcha, batidas na zebra, raspagem, pipocos)
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

	for pl in [tyre_player, grass_player, gravel_player, wind_player, turbo_player, kerb_player, brake_squeal_player, gearbox_player]:
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

	# Detecta troca de marcha antes do filtro para aquecer o corpo grave no blip de redução
	var is_downshift := (car.gear < last_gear and car.gear >= 1)
	if is_downshift:
		downshift_blip_timer = 0.22
	else:
		downshift_blip_timer = maxf(0.0, downshift_blip_timer - safe_dt)
	var blip_env := clampf(downshift_blip_timer / 0.22, 0.0, 1.0)

	# Carga e filtro LowPass: acelerando o som abre; soltando fica abafado;
	# no blip de redução mantém corte médio-grave encorpado (~2600 Hz) sem agudos estridentes
	var load := pow(thr, 0.7)
	var target_cutoff := clampf(900.0 + load * 15000.0 + rpm * 0.3, 200.0, 20000.0)
	if blip_env > 0.01:
		var blip_cutoff := clampf(2100.0 + rpm * 0.20, 1800.0, 3600.0)
		target_cutoff = lerpf(target_cutoff, blip_cutoff, blip_env * 0.85)
	filter_cutoff = lerpf(target_cutoff, filter_cutoff, exp(-safe_dt / 0.05))
	if engine_filter:
		engine_filter.cutoff_hz = filter_cutoff
		engine_filter.resonance = lerpf(0.72 + (1.0 - load) * 0.28 + blip_env * 0.16, engine_filter.resonance, exp(-safe_dt / 0.08))

	# Limitador e oscilação de corte
	var limiter := car.rpm > (limiter_rpm - 40.0)
	var chop := (0.3 if sin(time_accum * 95.0) > 0.0 else 1.0) if limiter else 1.0
	var target_engine_gain := (0.42 + 0.58 * load + blip_env * 0.22) * chop
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
		var loop_vol: float = s.gain * float(s.get("gain_comp", 1.0)) * engine_overall_gain
		if loop_vol > 0.001 or target_w > 0.001:
			var target_pitch := rpm / float(s.rpm)
			s.pitch = lerpf(target_pitch, s.pitch, k_eng)
			_play_player(pl, loop_vol)
			pl.pitch_scale = s.pitch
		else:
			s.gain = 0.0
			_pause_player(pl)

	# -------------------------------------------------------------
	# 2. Turbo desativado (som agudo/incômodo removido) & Pipocos de Escape
	# -------------------------------------------------------------
	turbo_gain = 0.0
	backfire_cooldown = maxf(0.0, backfire_cooldown - safe_dt)
	scrape_cooldown = maxf(0.0, scrape_cooldown - safe_dt)

	var downshift_high := (is_downshift and rpm > 4200.0)
	var abrupt_liftoff := (last_throttle > 0.65 and thr < 0.15 and rpm > 7000.0)
	if (downshift_high or abrupt_liftoff) and backfire_cooldown <= 0.0:
		backfire_cooldown = 0.22
		var bf_idx := 1 + (randi() % 3)
		var bf_pitch := (0.80 + randf() * 0.12) if downshift_high else (0.88 + randf() * 0.12)
		play_oneshot("backfire_%d" % bf_idx, 0.44 + randf() * 0.10, bf_pitch)

	# -------------------------------------------------------------
	# 3. Troca de Marcha (diferencia upshift seco vs. downshift encorpado/grave)
	# -------------------------------------------------------------
	if car.shift_count != last_shift:
		last_shift = car.shift_count
		if is_downshift:
			play_oneshot("gear_shift1", 0.42, 0.72 + randf() * 0.07)
		else:
			play_oneshot("gear_shift1", 0.30, 0.96 + randf() * 0.06)

	last_throttle = thr
	last_gear = car.gear

	# -------------------------------------------------------------
	# 4. Pneu Cantando (diferencia escorregamento lateral vs. trava de freio) e Superfícies
	# -------------------------------------------------------------
	var skid := 0.0
	var lat_skid := 0.0
	var long_lock := 0.0
	var on_grass := 0.0
	var on_gravel := 0.0
	var on_kerb := false
	var max_bottom_excess := 0.0

	for w in car.wheels:
		if not w.contact:
			continue
		var travel: float = float(w.susp.get("travel", 0.08))
		if w.comp > travel and speed > 12.0 and (w.comp_vel > 0.05 or w.fz > 3500.0):
			max_bottom_excess = maxf(max_bottom_excess, w.comp - travel)
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
			lat_skid = maxf(lat_skid, clampf((absf(sa) - 0.85) * 2.1, 0.0, 1.0))
			if car.brake_out > 0.15 and w.kappa < 0.0:
				long_lock = maxf(long_lock, clampf((absf(sk) - 0.80) * 2.2, 0.0, 1.0))

	var moving := clampf(speed / 8.0, 0.0, 1.0)

	# Pneu cantando (curva = mais agudo/limpo; trava longitudinal/ABS = mais grave/pulsado)
	if tyre_player:
		var lock_ratio := clampf(long_lock / maxf(0.05, long_lock + lat_skid), 0.0, 1.0)
		var abs_pulse := (0.82 + 0.18 * sin(time_accum * 42.0)) if (lock_ratio > 0.55 and car.assists.get("abs", true) and car.brake_out > 0.4) else 1.0
		var target_tyre_gain := maxf(skid, long_lock * 0.95) * moving * 0.45 * abs_pulse
		if target_tyre_gain <= 0.001 and tyre_gain <= 0.001:
			tyre_gain = 0.0
			_pause_player(tyre_player)
		else:
			var lat_pitch := 0.90 + lat_skid * 0.26
			var lock_pitch := 0.66 + long_lock * 0.18
			var target_tyre_pitch := lerpf(lat_pitch, lock_pitch, lock_ratio)
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

	# Batida na zebra a cada ~1.5 m + zebra contínua (kerb_loop)
	if on_kerb and speed > 3.0:
		kerb_dist += speed * safe_dt
		if kerb_dist > 1.5:
			kerb_dist = 0.0
			play_oneshot("bump_front1", 0.25, 0.9 + randf() * 0.2)

	if kerb_player:
		var target_kerb_gain := clampf((speed - 3.0) / 45.0, 0.18, 1.0) * 0.42 if (on_kerb and speed > 3.0) else 0.0
		if target_kerb_gain <= 0.001 and kerb_gain <= 0.001:
			kerb_gain = 0.0
			_pause_player(kerb_player)
		else:
			var target_kerb_pitch := clampf(0.75 + speed / 65.0, 0.75, 1.65)
			kerb_gain = lerpf(target_kerb_gain, kerb_gain, exp(-safe_dt / 0.04))
			kerb_pitch = lerpf(target_kerb_pitch, kerb_pitch, exp(-safe_dt / 0.06))
			if kerb_gain <= 0.001 and target_kerb_gain <= 0.001:
				kerb_gain = 0.0
				_pause_player(kerb_player)
			else:
				_play_player(kerb_player, kerb_gain)
				kerb_player.pitch_scale = kerb_pitch

	# Freio de carbono e zumbido de câmbio desativados (samples sintéticos agudos removidos)
	brake_squeal_gain = 0.0
	gearbox_gain = 0.0
	wall_reverb_wet = 0.0
	if engine_reverb:
		engine_reverb.wet = 0.0

	# Fundo raspando no asfalto ao atingir o batente da suspensão
	if max_bottom_excess > 0.0 and scrape_cooldown <= 0.0:
		scrape_cooldown = 0.28
		play_oneshot("bottom_scrape", clampf(0.30 + max_bottom_excess * 18.0, 0.30, 0.55), 0.92 + randf() * 0.16)

	# -------------------------------------------------------------
	# 5. Ambiência Sutil de Pista (reverb curto próximo a muros nos presets Médio/Extremo)
	# -------------------------------------------------------------
	if quality_level >= 2 and engine_reverb != null:
		var target_wet := 0.0
		var track_obj := car.ground as Track
		if track_obj != null and car.hint >= 0 and car.hint < track_obj.P.size() and speed > 18.0:
			var off := car.pos - track_obj.P[car.hint]
			var r_h := track_obj.R[car.hint]
			var lat := off.x * r_h.x + off.z * r_h.z
			var dist_l := track_obj.wall_l[car.hint] + lat
			var dist_r := track_obj.wall_r[car.hint] - lat
			var min_wall := maxf(0.0, minf(dist_l, dist_r))
			if min_wall < 10.0:
				var prox := 1.0 - (min_wall / 10.0)
				var spd_k := clampf((speed - 18.0) / 45.0, 0.0, 1.0)
				target_wet = prox * prox * spd_k * 0.14
		wall_reverb_wet = lerpf(target_wet, wall_reverb_wet, exp(-safe_dt / 0.12))
		engine_reverb.wet = wall_reverb_wet


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
	if kerb_player:
		kerb_player.stream_paused = true if p else (kerb_gain <= 0.001)
	if brake_squeal_player:
		brake_squeal_player.stream_paused = true if p else (brake_squeal_gain <= 0.001)
	if gearbox_player:
		gearbox_player.stream_paused = true if p else (gearbox_gain <= 0.001)


## Zera contadores de estado (ex: ao reiniciar volta com R)
func reset() -> void:
	kerb_dist = 0.0
	scrape_cooldown = 0.0
	backfire_cooldown = 0.0
	downshift_blip_timer = 0.0
	if car:
		last_shift = car.shift_count
		last_gear = car.gear
	last_throttle = 0.0
	tyre_gain = 0.0
	grass_gain = 0.0
	gravel_gain = 0.0
	wind_gain = 0.0
	turbo_gain = 0.0
	kerb_gain = 0.0
	brake_squeal_gain = 0.0
	gearbox_gain = 0.0
	wall_reverb_wet = 0.0
	if engine_reverb:
		engine_reverb.wet = 0.0
	for pl in [tyre_player, grass_player, gravel_player, wind_player, turbo_player, kerb_player, brake_squeal_player, gearbox_player]:
		if pl:
			pl.volume_db = -80.0
			pl.stream_paused = true
