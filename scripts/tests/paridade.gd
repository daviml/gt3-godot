# Teste de paridade da física web × Godot. Roda os mesmos ensaios do tools/paridade.ts com a física do Godot
# (scripts/physics/car.gd) e compara com os números do web gravados em data/tests/paridade-web.json.
#
# uso: godot --headless --path . --script res://scripts/tests/paridade.gd [-- carro=<id>[,<id>]] [-- rapido]
#   rapido = sem as voltas (Bot e RefBot), que são o grosso do tempo.
# Antes, se a física ou os carros do web mudaram: (tools) npx vite-node paridade.ts
extends SceneTree

const DT := 1.0 / Car.HZ
const ENV_SPEEDS := [70, 90, 110, 130, 150, 170, 190, 220]
# tolerância por medida: [relativa, absoluta] — passa se cumprir qualquer uma
const TOL := {
	"parado_desliza": [0.0, 0.02], "parado_altura": [0.0, 0.005], "t0_100": [0.02, 0.05], "maxima": [0.01, 1.0],
	"freada_200_0_m": [0.02, 1.0], "freada_200_0_s": [0.02, 0.05], "freada_desvio": [0.0, 0.02],
	"lateral_72": [0.02, 0.02], "lateral_216": [0.02, 0.03], "envelope_lateral": [0.03, 0.03],
	"envelope_freada": [0.02, 0.02], "envelope_aceleracao": [0.03, 0.01], "velocidade_40s": [0.01, 1.0],
	"bot_volta": [0.01, 0.3], "bot_saida_max": [0.0, 0.3],
	"refbot_volta": [0.005, 0.3], "refbot_erro_max": [0.0, 0.6], "refbot_fora": [0.0, 0.5], "refbot_maxima": [0.01, 2.0],
}

var flat := FlatGround.new()
var track: Track
var refs := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only: Array = []
	var fast := "rapido" in args
	for a in args:
		if a.begins_with("carro="):
			only = a.substr(6).split(",")
	var web: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tests/paridade-web.json"))
	track = Track.new("res://data/track/track.json")
	var fails := 0
	var t_all := Time.get_ticks_msec()
	for id in web.carros:
		if not only.is_empty() and not (id in only):
			continue
		var entry: Dictionary = web.carros[id]
		var params: Dictionary = entry.params
		# o acerto exportado pelo prep.ts tem que ser o mesmo que o web usou agora
		if FileAccess.file_exists("res://data/cars/%s.json" % id):
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars/%s.json" % id))
			if Car.from_params(d.params) != Car.from_params(params):
				print("%s: data/cars/%s.json diferente do acerto do web — rodar tools/prep.ts -- dados" % [id, id])
				fails += 1
		var t0 := Time.get_ticks_msec()
		var got := measure(id, params, fast)
		fails += compare(id, entry.web, got)
		print("  (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("total %.0f s — %s" % [(Time.get_ticks_msec() - t_all) / 1000.0, "OK" if fails == 0 else "%d DIFERENÇAS" % fails])
	quit(0 if fails == 0 else 1)


# ------------------------------------------------------------------ comparação

func _close(key: String, a: float, b: float) -> bool:
	if is_nan(a) and is_nan(b):
		return true
	var tol: Array = TOL.get(key, [0.02, 0.0])
	return absf(a - b) <= maxf(tol[1], tol[0] * absf(a))


func compare(id: String, w: Dictionary, g: Dictionary) -> int:
	var bad := 0
	var lines: PackedStringArray = []
	for key in g:
		if not w.has(key):
			continue
		var a = w[key]
		var b = g[key]
		if a is Dictionary:
			var parts: PackedStringArray = []
			var ok := true
			for k in a:
				if a[k] is String:
					var same: bool = b.get(k, "") == a[k]
					ok = ok and same
					if not same:
						parts.append("%s: %s × %s" % [k, a[k], b.get(k, "-")])
					continue
				var bv: float = b.get(k, NAN)
				var c := _close(key, a[k], bv)
				ok = ok and c
				parts.append("%s: %.2f×%.2f%s" % [k, a[k], bv, "" if c else "!"])
			if not ok:
				bad += 1
			lines.append("  %-20s %s %s" % [key, "ok " if ok else "DIF", " | ".join(parts)])
		elif a is String:
			continue
		else:
			var c := _close(key, float(a), float(b))
			if not c:
				bad += 1
			var pct := 100.0 * (float(b) - float(a)) / float(a) if float(a) != 0.0 else 0.0
			lines.append("  %-20s %s web %9.3f  godot %9.3f  (%+.2f%%)" % [key, "ok " if c else "DIF", a, b, pct])
	print("%s %s" % [id, "" if bad == 0 else "— %d diferença(s)" % bad])
	for l in lines:
		print(l)
	return bad


# ------------------------------------------------------------------ ensaios (mesmos do tools/paridade.ts)

func new_car(params: Dictionary) -> Car:
	var car := Car.new(flat, params)
	car.reset(Vector3(0, car.p.cg, 0), 0.0)
	for i in Car.HZ:
		car.step(DT, 0, 0, 0)
	return car


func accelerate_to(car: Car, target: float, max_t := 60.0) -> float:
	car.assists.auto = true
	var t := 0.0
	while car.fwd_speed() < target and t < max_t:
		car.step(DT, 0, 1, 0)
		t += DT
	return t


func _beta(car: Car) -> float:
	var fwd := car.basis() * Vector3.FORWARD
	return acos(minf(1.0, car.vel.dot(fwd) / maxf(car.speed(), 1e-3)))


func max_lateral_g(params: Dictionary, v: float) -> float:
	var car := new_car(params)
	accelerate_to(car, v)
	var best := 0.0
	var T := 12.0
	var t := 0.0
	while t < T:
		var err := v - car.fwd_speed()
		car.step(DT, t / T * 0.7, clampf(err * 0.5 + 0.3, 0, 1), 0)
		t += DT
		if _beta(car) > 0.15:
			break
		best = maxf(best, absf(car.g_lat))
	return best


func rolling(params: Dictionary, v: float) -> Car:
	var car := Car.new(flat, params)
	car.assists.auto = true
	car.reset(Vector3(0, car.p.cg, 0), 0.0)
	for i in Car.HZ / 2:
		car.step(DT, 0, 0, 0)
	car.vel = Vector3(0, 0, -v)
	for w in car.wheels:
		w.omega = v / car.p.radius
	car.gear = 1
	for g in range(car.p.ratios.size(), 0, -1):
		var rpm: float = v / car.p.radius * car.p.ratios[g - 1] * car.p.final * 60.0 / TAU
		if rpm > 5000.0:
			car.gear = g
			break
	return car


func lateral(params: Dictionary, v: float) -> Array:
	var car := rolling(params, v)
	var best := 0.0
	var end := "segurou"
	var T := 10.0
	var gs: Array[float] = []
	var t := 0.0
	while t < T:
		var err := v - car.fwd_speed()
		car.step(DT, t / T * 0.6, clampf(err * 0.6 + 0.35, 0, 1), 0)
		t += DT
		if _beta(car) > 0.12:
			end = "traseira escapa"
			break
		if car.fwd_speed() < v * 0.9:
			end = "sai de frente"
			break
		gs.append(absf(car.g_lat))
		if gs.size() > 150:
			gs.pop_front()
		if gs.size() == 150:
			var acc := 0.0
			for x in gs:
				acc += x
			best = maxf(best, acc / 150.0)
	return [best, end]


func brake_curve(params: Dictionary) -> Dictionary:
	var car := rolling(params, 75)
	var out := {}
	var last := car.fwd_speed()
	var acc := 0.0
	var n := 0
	var bin := int(floor(last * 3.6 / 20.0))
	var t := 0.0
	while t < 10.0 and car.fwd_speed() > 15.0:
		car.step(DT, 0, 0, 1)
		var v := car.fwd_speed()
		acc += (last - v) / DT
		n += 1
		last = v
		var b := int(floor(v * 3.6 / 20.0))
		if b != bin:
			if t > 0.3 and bin * 20 >= 80:
				out[str(bin * 20)] = acc / n / 9.81
			acc = 0; n = 0; bin = b
		t += DT
	return out


func accel_curve(params: Dictionary) -> Array:
	var car := rolling(params, 20)
	var out := {}
	var last := car.fwd_speed()
	var acc := 0.0
	var n := 0
	var bin := int(floor(last * 3.6 / 20.0))
	var t := 0.0
	while t < 40.0:
		car.step(DT, 0, 1, 0)
		var v := car.fwd_speed()
		acc += (v - last) / DT
		n += 1
		last = v
		var b := int(floor(v * 3.6 / 20.0))
		if b != bin:
			if bin * 20 >= 100:
				out[str(bin * 20)] = acc / n / 9.81
			acc = 0; n = 0; bin = b
		t += DT
	return [out, car.fwd_speed() * 3.6]


func bot_lap(params: Dictionary) -> Array:
	var car := Car.new(track, params)
	car.assists.auto = true
	var i0 := track.index_at(-40)
	var t0 := track.T[i0]
	car.reset(track.P[i0] + Vector3(0, car.p.cg + 0.05, 0), atan2(-t0.x, -t0.z))
	var bot := Bot.new(track, car)
	var t := 0.0
	var lap_start := -1.0
	var lap := NAN
	var max_off := 0.0
	track.locate(car.pos, -1)
	var last_s := track.ls
	while t < 300.0:
		var inp := bot.drive()
		car.step(DT, inp[0], inp[1], inp[2])
		t += DT
		track.locate(car.pos, car.hint)
		max_off = maxf(max_off, absf(track.ld) - (track.lwl if track.ld < 0.0 else track.lwr))
		if last_s > track.length - 100.0 and track.ls < 100.0:
			if lap_start >= 0.0:
				lap = t - lap_start
				break
			lap_start = t
		last_s = track.ls
	return [lap, max_off]


func ref_lap(params: Dictionary, ref_name: String) -> Dictionary:
	if not refs.has(ref_name):
		refs[ref_name] = RefBot.load_ref(ref_name)
	var car := Car.new(track, params)
	car.assists.auto = true
	var bot := RefBot.new(track, car, refs[ref_name])
	var s0 := track.length - 300.0
	var p0 := bot.line_point(s0)
	var p1 := bot.line_point(s0 + 4.0)
	track.locate(p0, -1)
	car.reset(Vector3(p0.x, track.lcenter.y + car.p.cg + 0.02, p0.z), atan2(-(p1.x - p0.x), -(p1.z - p0.z)))
	var v0 := bot.ref_at(bot._rv, s0)
	car.vel = Vector3(p1.x - p0.x, 0, p1.z - p0.z).normalized() * v0
	car.gear = car.p.ratios.size()
	for w in car.wheels:
		w.omega = v0 / car.p.radius
	var t := 0.0
	var last_s := s0
	var lap_start := -1.0
	var crossed := 0
	var max_err := 0.0
	var off := 0.0
	var vmax := 0.0
	while t < 200.0:
		var inp := bot.drive()
		car.step(DT, inp[0], inp[1], inp[2])
		t += DT
		if bot.s < last_s - track.length / 2.0:
			crossed += 1
			if crossed == 1:
				lap_start = t
			else:
				break
		last_s = bot.s
		if crossed == 1:
			max_err = maxf(max_err, absf(bot.line_error))
			vmax = maxf(vmax, car.fwd_speed() * 3.6)
			track.locate(car.pos, car.hint)
			if absf(track.ld) > (track.lwr if track.ld > 0.0 else track.lwl) + 1.5:
				off += DT
		if car.pos.y < -50.0:
			break
	return {"refbot_volta": t - lap_start if crossed >= 2 else NAN, "refbot_erro_max": max_err, "refbot_fora": off, "refbot_maxima": vmax}


const REFS := {"audi-r8-lms-gt3": "interlagos-r8"}

func measure(id: String, params: Dictionary, fast: bool) -> Dictionary:
	var r := {}
	var car := new_car(params)
	var start := car.pos
	for i in Car.HZ * 5:
		car.step(DT, 0, 0, 0)
	r.parado_desliza = Vector2(car.pos.x - start.x, car.pos.z - start.z).length()
	r.parado_altura = car.pos.y
	r.t0_100 = accelerate_to(new_car(params), 100.0 / 3.6)
	car = new_car(params)
	accelerate_to(car, 200.0, 60.0)
	r.maxima = car.fwd_speed() * 3.6
	car = new_car(params)
	accelerate_to(car, 200.0 / 3.6)
	start = car.pos
	var q0 := car.rot
	var t := 0.0
	while car.fwd_speed() > 0.5 and t < 20.0:
		car.step(DT, 0, 0, 1)
		t += DT
	r.freada_200_0_m = car.pos.distance_to(start)
	r.freada_200_0_s = t
	r.freada_desvio = q0.angle_to(car.rot)
	r.lateral_72 = max_lateral_g(params, 20.0)
	r.lateral_216 = max_lateral_g(params, 60.0)
	var env := {}
	var ends := {}
	for kmh in ENV_SPEEDS:
		var L := lateral(params, kmh / 3.6)
		env[str(kmh)] = L[0]
		ends[str(kmh)] = L[1]
	r.envelope_lateral = env
	r.envelope_limite = ends
	r.envelope_freada = brake_curve(params)
	var ac := accel_curve(params)
	r.envelope_aceleracao = ac[0]
	r.velocidade_40s = ac[1]
	if not fast:
		var b := bot_lap(params)
		r.bot_volta = b[0]
		r.bot_saida_max = b[1]
		if REFS.has(id):
			r.merge(ref_lap(params, REFS[id]))
	return r
