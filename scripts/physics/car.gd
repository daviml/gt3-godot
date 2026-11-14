# Física do carro portada do jogo web (src/physics/car.ts, tire.ts, rigidbody.ts): chassi rígido, 4 rodas
# com suspensão por raio, pneu Pacejka com slip combinado, motor, câmbio (manual ou automático), autoblocante,
# ABS e TC ligáveis. Eixos locais: +X direita, +Y cima, -Z frente (igual ao Three.js e ao Godot).
# O acerto vem de data/cars/<id>.json ("params"), gerado pelo carParams() do web no tools/prep.ts.
class_name Car
extends RefCounted

const HZ := 500
const SUB_DT := 1.0 / 500.0
const G := 9.81
const AIR := 1.225
const V_LOW := 3.0
const RPM_TO_RAD := TAU / 60.0

## acerto em nomes curtos (ver from_params)
var p: Dictionary
var id := ""
var name := ""

class Wheel:
	var mount := Vector3.ZERO
	var front := true
	var left := true
	var susp: Dictionary
	var comp := 0.0
	var comp_vel := 0.0
	var omega := 0.0
	var spin := 0.0
	var steer := 0.0
	var contact := false
	var fz := 0.0
	var kappa := 0.0
	var alpha := 0.0
	var fx := 0.0
	var fy := 0.0
	var surface := 0
	var drive := 0.0
	var brake := 0.0
	var cpoint := Vector3.ZERO
	var cnormal := Vector3.UP
	## relevo da zebra sob a roda (m), para vibração
	var bump := 0.0
	## ABS segurando o freio desta roda neste passo (HUD e vibração)
	var abs_active := false

var ground: Ground
var assists := {"abs": true, "tc": true, "auto": false, "brake_reverse": false}
var grip_scale: float = 1.0
## Máximo de sub-passos por tick de 60 Hz (4 no mobile/Mínimo = 240 Hz; 8 no Desktop = 480 Hz)
var max_sub_steps := 4 if OS.has_feature("mobile") else 8
var pos := Vector3.ZERO
var rot := Quaternion.IDENTITY
var prev_pos := Vector3.ZERO
var prev_rot := Quaternion.IDENTITY
var vel := Vector3.ZERO
var ang_vel := Vector3.ZERO
var force := Vector3.ZERO
var torque := Vector3.ZERO
var wheels: Array[Wheel] = []
var gear := 1
var rpm := 1200.0
var shift_timer := 0.0
var clutch_locked := false
var tc_cut := 0.0
var throttle_out := 0.0
var hint := -1
var kappa_peak := 0.0
var alpha_peak := 0.0
var max_steer := 0.0
## trocas de marcha feitas (o som detecta a mudança)
var shift_count := 0
var reverse_hold := 0.0
## aceleração no referencial do carro, em g (filtrada), para HUD e testes
var g_lat := 0.0
var g_long := 0.0
var _last_vel := Vector3.ZERO
var _last_up := false
var _last_down := false
var _right := Vector3.RIGHT
var _fwd := Vector3.FORWARD


## Converte o "params" do JSON (CarParams do web) para os nomes curtos usados aqui.
static func from_params(j: Dictionary) -> Dictionary:
	var susp := func(s: Dictionary) -> Dictionary:
		return {"k": float(s.k), "bump": float(s.bump), "rebound": float(s.rebound), "arb": float(s.arb),
			"rest": float(s.restLength), "travel": float(s.travel), "rc": float(s.rollCenter)}
	var t: Dictionary = j.tire
	var e: Dictionary = j.engine
	var gb: Dictionary = j.gearbox
	var ratios: Array = []
	for r in gb.ratios:
		ratios.append(float(r))
	var torque: Array = []
	for pt in e.torque:
		torque.append([float(pt[0]), float(pt[1])])
	return {
		"mass": float(j.mass), "inertia": Vector3(j.inertia[0], j.inertia[1], j.inertia[2]), "cg": float(j.cgHeight),
		"wheelbase": float(j.wheelbase), "wf": float(j.weightFront), "track_f": float(j.trackFront),
		"track_r": float(j.trackRear), "radius": float(j.wheelRadius), "wheel_inertia": float(j.wheelInertia),
		"front": susp.call(j.suspension.front), "rear": susp.call(j.suspension.rear),
		"mu": float(t.mu), "mu_long": float(t.get("muLong", 1.0)), "load_sens": float(t.loadSens), "fz0": float(t.fz0),
		"b_lat": float(t.bLat), "c_lat": float(t.cLat), "e_lat": float(t.eLat),
		"b_long": float(t.bLong), "c_long": float(t.cLong), "e_long": float(t.eLong),
		"relax": float(t.relaxLen), "roll_res": float(t.rollingResistance), "rear_grip": float(j.get("rearGrip", 1.0)),
		"clA": float(j.aero.clA), "cdA": float(j.aero.cdA), "aero_front": float(j.aero.balanceFront),
		"torque": torque, "idle": float(e.idle), "limiter": float(e.limiter), "launch": float(e.launchRpm),
		"eng_inertia": float(e.inertia), "fric_base": float(e.frictionBase), "fric_rpm": float(e.frictionPerRpm),
		"ratios": ratios, "final": float(gb.final), "reverse": float(gb.reverse), "shift_time": float(gb.shiftTime),
		"eff": float(gb.efficiency),
		"preload": float(j.diff.preload), "ramp_power": float(j.diff.rampPower), "ramp_coast": float(j.diff.rampCoast),
		"viscous": float(j.diff.viscous),
		"brake_max": float(j.brakes.maxTorque), "brake_bias": float(j.brakes.bias),
		"steer_deg": float(j.steering.maxAngleDeg),
	}


## Carro a partir de data/cars/<id>.json (o arquivo inteiro, com "params", ou só o CarParams).
static func load_car(g: Ground, car_id: String) -> Car:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars/%s.json" % car_id))
	return Car.new(g, d.get("params", d))


func _init(g: Ground, params: Dictionary) -> void:
	ground = g
	id = params.get("id", "")
	name = params.get("name", "")
	p = from_params(params)
	kappa_peak = _peak_slip(p.b_long, p.c_long, p.e_long)
	alpha_peak = _peak_slip(p.b_lat, p.c_lat, p.e_lat)
	max_steer = deg_to_rad(p.steer_deg)
	rpm = p.idle
	var a: float = p.wheelbase * (1.0 - p.wf)
	var b: float = p.wheelbase * p.wf
	for k in 4:
		var w := Wheel.new()
		w.front = k < 2
		w.left = k % 2 == 0
		w.susp = p.front if w.front else p.rear
		var tr: float = p.track_f if w.front else p.track_r
		var static_comp: float = p.mass * G * (p.wf if w.front else 1.0 - p.wf) / 2.0 / w.susp.k
		w.mount = Vector3((-1.0 if w.left else 1.0) * tr * 0.5, p.radius - p.cg + w.susp.rest - static_comp, -a if w.front else b)
		wheels.append(w)


static func magic(x: float, B: float, C: float, E: float) -> float:
	var bx := B * x
	return sin(C * atan(bx - E * (bx - atan(bx))))


static func _peak_slip(B: float, C: float, E: float) -> float:
	var best := 0.0
	var bx := 0.0
	var x := 0.001
	while x < 1.0:
		var y := magic(x, B, C, E)
		if y > best:
			best = y; bx = x
		x += 0.0005
	return bx


func peak_force(fz: float, grip: float) -> float:
	var mu: float = p.mu * maxf(0.5, 1.0 - p.load_sens * (fz / p.fz0 - 1.0))
	return mu * fz * grip * grip_scale


## Forças do pneu: x = longitudinal, y = lateral (+ direita)
func tire(fz: float, kappa: float, alpha: float, grip: float) -> Vector2:
	if fz <= 0.0:
		return Vector2.ZERO
	var sk := kappa / kappa_peak
	var sa := alpha / alpha_peak
	var s := sqrt(sk * sk + sa * sa)
	if s < 1e-9:
		return Vector2.ZERO
	var D := peak_force(fz, grip)
	return Vector2(D * p.mu_long * magic(s * kappa_peak, p.b_long, p.c_long, p.e_long) * (sk / s),
		-D * magic(s * alpha_peak, p.b_lat, p.c_lat, p.e_lat) * (sa / s))


## Coloca o carro parado em pos, com a frente apontando para heading (rad, 0 = -Z), como o reset do web.
func reset(at: Vector3, heading: float) -> void:
	reset_basis(at, Basis(Vector3.UP, heading))


func reset_basis(at: Vector3, b: Basis) -> void:
	pos = at
	rot = b.orthonormalized().get_rotation_quaternion()
	prev_pos = pos
	prev_rot = rot
	vel = Vector3.ZERO
	ang_vel = Vector3.ZERO
	_last_vel = Vector3.ZERO
	for w in wheels:
		w.omega = 0; w.comp = 0; w.comp_vel = 0; w.fy = 0
	gear = 1
	rpm = p.idle
	shift_timer = 0
	tc_cut = 0
	hint = -1


## Parado na amostra i da pista, inclinado com ela.
func reset_at(i: int) -> void:
	var track := ground as Track
	var t := track.T[i]
	var r := track.R[i]
	var up := r.cross(t).normalized()
	reset_basis(track.P[i] + up * (p.cg + 0.05), Basis(r, up, -t))
	hint = i


func basis() -> Basis:
	return Basis(rot)


## Interpolação de física sub-frame para movimento 100% fluido em qualquer taxa de quadros (30/60/120 Hz)
func visual_pos(frac: float) -> Vector3:
	return prev_pos.lerp(pos, frac)


func visual_rot(frac: float) -> Quaternion:
	return prev_rot.slerp(rot, frac)


func visual_basis(frac: float) -> Basis:
	return Basis(visual_rot(frac))


func speed() -> float:
	return vel.length()


func fwd_speed() -> float:
	return vel.dot(basis() * Vector3.FORWARD)


func gear_ratio(g: int) -> float:
	if g == 0: return 0.0
	if g < 0: return -p.reverse * p.final
	return p.ratios[g - 1] * p.final


func engine_torque(r: float) -> float:
	var t: Array = p.torque
	if r <= t[0][0]: return t[0][1]
	for i in range(1, t.size()):
		if r <= t[i][0]:
			return t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (r - t[i - 1][0]) / (t[i][0] - t[i - 1][0])
	return t[t.size() - 1][1]


## Giro que o motor teria nessa marcha pela velocidade do carro (não pelas rodas, que quase travam na freada).
func road_rpm(g: int) -> float:
	var om := maxf((wheels[2].omega + wheels[3].omega) / 2.0, fwd_speed() / p.radius)
	return om * gear_ratio(g) / RPM_TO_RAD


func _shift(throttle: float, brake: float, up_in: bool, down_in: bool, dt: float) -> void:
	var up := up_in and not _last_up
	var down := down_in and not _last_down
	_last_up = up_in
	_last_down = down_in
	if shift_timer > 0.0:
		shift_timer -= dt
		return
	var max_gear: int = p.ratios.size()
	var lim: float = p.limiter
	var target := gear
	if up and gear < max_gear: target = gear + 1
	if down and gear > -1: target = gear - 1
	if assists.auto and gear >= 1:
		if rpm > lim - 250.0 and gear < max_gear and throttle > 0.1:
			target = gear + 1
		# reduz assim que a marcha de baixo cabe; acelerando exige mais folga; aliviando só se o motor morre
		elif gear > 1:
			var lower := road_rpm(gear - 1)
			var go := false
			if brake > 0.05: go = lower < lim - 550.0
			elif throttle > 0.5: go = lower < lim - 1200.0
			else: go = rpm < lim * 0.45
			if go: target = gear - 1
	if target == gear:
		return
	# proteção contra redução que estoura o motor (como nos GT3 reais)
	if target > 0 and target < gear and road_rpm(target) > lim + 300.0:
		return
	# ré/neutro só quase parado
	if target <= 0 and gear >= 1 and absf(fwd_speed()) > 2.0:
		return
	gear = target
	shift_timer = p.shift_time
	shift_count += 1


func _drivetrain(throttle: float, dt: float) -> float:
	var Gr := gear_ratio(gear)
	var rear := (wheels[2].omega + wheels[3].omega) / 2.0
	clutch_locked = false
	if Gr == 0.0 or shift_timer > 0.0:
		var target: float = p.idle + throttle * (p.limiter - p.idle)
		rpm += (target - rpm) * minf(1.0, dt * 6.0)
		return 0.0
	var rpm_w := rear * Gr / RPM_TO_RAD
	var launch: float = p.idle + throttle * (p.launch - p.idle)
	if rpm_w < launch and throttle > 0.02:
		rpm = launch
		return throttle * engine_torque(rpm) * Gr * p.eff
	if rpm_w < p.idle:
		rpm = p.idle
		return 0.0
	clutch_locked = true
	rpm = rpm_w
	var fric: float = p.fric_base + p.fric_rpm * rpm
	var te := throttle * engine_torque(rpm) - (1.0 - throttle) * fric
	if rpm > p.limiter:
		te = minf(te, -fric)
	return te * Gr * (p.eff if te > 0.0 else 1.0)


func _force_at(f: Vector3, at: Vector3) -> void:
	force += f
	torque += (at - pos).cross(f)


func _point_vel(at: Vector3) -> Vector3:
	return ang_vel.cross(at - pos) + vel


# cantos e meios da carroceria (local) para bater no muro
const CORNERS := [Vector3(-1, 0, -2.35), Vector3(1, 0, -2.35), Vector3(-1, 0, 2.25), Vector3(1, 0, 2.25), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
const WALL_K := 2e6
const WALL_C := 4e4
const WALL_FRICTION := 0.35

func step(dt: float, steer_in: float, throttle_in: float, brake_in: float, shift_up := false, shift_down := false) -> void:
	prev_pos = pos
	prev_rot = rot
	# Sub-stepping interno para manter estabilidade e paridade da simulação.
	# No mobile, limitamos o número máximo de sub-passos por tick a 4 (240 Hz a 60 Hz),
	# o que reduz o custo de CPU pela metade com 100% de estabilidade.
	if dt > SUB_DT * 1.5:
		var max_sub := max_sub_steps
		var n_steps := clampi(int(roundf(dt / SUB_DT)), 1, max_sub)
		var sub_dt := dt / float(n_steps)
		# o câmbio recebe o botão "segurado" em todos os sub-passos: a borda (_last_up/_last_down) é detectada
		# dentro de _shift. Passar false nos sub-passos seguintes "soltava" o botão a cada frame, e segurar
		# a borboleta por mais que o tempo de troca engatava outra marcha (1ª -> 3ª).
		for s in n_steps:
			_single_step(sub_dt, steer_in, throttle_in, brake_in, shift_up, shift_down)
	else:
		_single_step(dt, steer_in, throttle_in, brake_in, shift_up, shift_down)


func _single_step(dt: float, steer_in: float, throttle_in: float, brake_in: float, shift_up := false, shift_down := false) -> void:
	var B := basis()
	force = Vector3(0, -p.mass * G, 0)
	torque = Vector3.ZERO
	var up := B.y
	var fwd := -B.z
	_fwd = fwd
	_right = B.x
	var down := -up
	var vf := vel.dot(fwd)
	hint = ground.nearest(pos, hint)

	# aerodinâmica
	var dn: float = 0.5 * AIR * vf * vf * p.clA
	var a: float = p.wheelbase * (1.0 - p.wf)
	var b: float = p.wheelbase * p.wf
	_force_at(down * dn * p.aero_front, pos + B * Vector3(0, 0, -a))
	_force_at(down * dn * (1.0 - p.aero_front), pos + B * Vector3(0, 0, b))
	force += -vel * (0.5 * AIR * p.cdA * vel.length())

	# Ré pelo freio (celular): parado (<0.5 m/s), segurar freio >30% sem acelerar por 0.4s engata ré
	if assists.get("brake_reverse", false):
		var stopped := absf(vf) < 0.5
		if gear >= 1:
			reverse_hold = reverse_hold + dt if (stopped and brake_in > 0.3 and throttle_in < 0.05) else 0.0
			if reverse_hold > 0.4:
				gear = -1
				shift_count += 1
				reverse_hold = 0.0
		elif gear == -1 and stopped and throttle_in > 0.1:
			gear = 1
			shift_count += 1
			reverse_hold = 0.0
		if gear == -1:
			var orig_thr := throttle_in
			throttle_in = brake_in
			brake_in = orig_thr

	# câmbio, motor, TC: corta quando uma traseira, acelerando, passa do pico no slip combinado
	_shift(throttle_in, brake_in, shift_up, shift_down, dt)
	var fz_r := wheels[2].fz + wheels[3].fz
	var rear_over := false
	for wi in range(2, 4):
		var w := wheels[wi]
		if w.fz > 0.15 * fz_r and w.kappa > 0.3 * kappa_peak and Vector2(w.kappa / kappa_peak, w.alpha / alpha_peak).length() > 1.0:
			rear_over = true
	tc_cut = minf(0.9, tc_cut + dt * 15.0) if assists.tc and rear_over else maxf(0.0, tc_cut - dt * 3.0)
	var throttle := throttle_in * (1.0 - tc_cut)
	throttle_out = throttle
	var diff_in := _drivetrain(throttle, dt)
	var Gr := gear_ratio(gear)
	var reflected: float = p.eng_inertia * Gr * Gr / 2.0 if clutch_locked else 0.0

	# autoblocante
	var rl := wheels[2]
	var rr := wheels[3]
	var cap: float = p.preload + (p.ramp_power if diff_in >= 0.0 else p.ramp_coast) * absf(diff_in)
	var lock := clampf(p.viscous * (rl.omega - rr.omega), -cap, cap)
	rl.drive = diff_in / 2.0 - lock
	rr.drive = diff_in / 2.0 + lock
	wheels[0].drive = 0.0
	wheels[1].drive = 0.0

	var steer := clampf(steer_in, -1.0, 1.0) * max_steer
	for w in wheels:
		var share: float = p.brake_bias if w.front else 1.0 - p.brake_bias
		w.brake = brake_in * p.brake_max * share / 2.0
		w.steer = steer if w.front else 0.0

	# suspensão: compressões primeiro (barra estabilizadora)
	for w in wheels:
		var m := pos + B * w.mount
		var l: float = w.susp.rest + p.radius
		var dist := ground.probe(m, down, l, hint)
		var c := 0.0
		w.contact = dist >= 0.0
		if w.contact:
			c = l - dist
			w.cpoint = ground.hit_point
			w.cnormal = ground.hit_normal
			w.surface = ground.hit_surface
			w.bump = ground.hit_bump
		w.comp_vel = (c - w.comp) / dt
		w.comp = c

	var r: float = p.radius
	for i in 4:
		var w := wheels[i]
		var s: Dictionary = w.susp
		var other := wheels[i ^ 1]
		var iw: float = p.wheel_inertia + (0.0 if w.front else reflected)
		w.abs_active = false
		if not w.contact:
			w.fz = 0; w.fx = 0; w.fy = 0; w.kappa = 0; w.alpha = 0; w.bump = 0
			w.omega += w.drive * dt / iw
			var bd0 := w.brake * dt / iw
			w.omega = maxf(0.0, w.omega - bd0) if w.omega > 0.0 else minf(0.0, w.omega + bd0)
			w.spin += w.omega * dt
			continue
		var damper: float = s.bump if w.comp_vel > 0.0 else s.rebound
		var fs: float = s.k * w.comp + damper * w.comp_vel
		fs += s.arb * (w.comp - (other.comp if other.contact else 0.0))
		if w.comp > s.travel:
			fs += 1e6 * (w.comp - s.travel)
		fs = maxf(0.0, fs)
		w.fz = fs
		_force_at(up * fs, pos + B * w.mount)

		var nrm := w.cnormal
		var wf := fwd
		if w.steer != 0.0:
			wf = wf.rotated(up, -w.steer)
		wf = (wf - nrm * wf.dot(nrm)).normalized()
		var wr := wf.cross(nrm).normalized()
		var vc := _point_vel(w.cpoint)
		var vx := vc.dot(wf)
		var vy := vc.dot(wr)
		var denom := maxf(absf(vx), V_LOW)
		var alpha := atan2(vy, denom)
		var grip: float = Ground.GRIP[w.surface] * (1.0 if w.front else p.rear_grip)

		# rotação da roda: integração semi-implícita (o termo Fx·r é rígido)
		var k0 := (w.omega * r - vx) / denom
		var f0 := tire(w.fz, k0, alpha, grip)
		var f1 := tire(w.fz, k0 + 1e-4, alpha, grip)
		var slope := maxf(0.0, (f1.x - f0.x) / 1e-4) * r / denom
		var den := iw + dt * r * slope
		var om := w.omega + dt * (w.drive - r * f0.x) / den
		var bd := w.brake * dt / den
		# ABS: limita o freio para o escorregamento não passar do pico (descontando o que o pneu usa para virar)
		if assists.abs and vx > 2.0 and bd > 0.0:
			var side := alpha / alpha_peak
			var kT := kappa_peak * sqrt(maxf(0.04, 0.92 * 0.92 - side * side))
			var om_min := (vx - kT * denom) / r
			var max_bd := maxf(0.0, om - om_min)
			if bd > max_bd:
				w.abs_active = true
				bd = max_bd
		om = maxf(0.0, om - bd) if om > 0.0 else minf(0.0, om + bd)
		w.omega = om
		w.spin += om * dt

		w.kappa = (om * r - vx) / denom
		w.alpha = alpha
		var ff := tire(w.fz, w.kappa, alpha, grip)
		# comprimento de relaxação: a força lateral demora a se formar, sem passar do que o pneu aguenta agora
		var relax: float = minf(1.0, maxf(absf(vx), 8.0) * dt / p.relax)
		w.fy += (ff.y - w.fy) * relax
		var pk := peak_force(w.fz, grip)
		var fy_max := sqrt(maxf(0.0, pk * pk - ff.x * ff.x))
		w.fy = clampf(w.fy, -fy_max, fy_max)
		w.fx = ff.x - (p.roll_res + Ground.DRAG[w.surface]) * w.fz * tanh(vx)
		var pt: Vector3 = w.cpoint + up * float(s.rc)
		if grip_scale > 1.0:
			var dh: float = (pos - pt).dot(up)
			pt += up * (dh * (1.0 - 1.0 / (grip_scale * grip_scale)))
		_force_at(wf * w.fx + wr * w.fy, pt)

	# muros: mola-amortecedor nos cantos da carroceria + atrito
	# Otimização mobile: se o carro está no miolo da pista (longe dos muros com margem de 3.5m),
	# nenhum canto pode estar colidindo, dispensando 6 queries pesadas por sub-passo.
	var track_obj := ground as Track
	var near_wall := true
	if track_obj != null and hint >= 0:
		var off := pos - track_obj.P[hint]
		var r_h := track_obj.R[hint]
		var lat := absf(off.x * r_h.x + off.z * r_h.z)
		var wall_dist := minf(track_obj.wall_l[hint], track_obj.wall_r[hint])
		if lat < wall_dist - 3.5:
			near_wall = false

	if near_wall:
		for c: Vector3 in CORNERS:
			var m := pos + B * c
			var pen := ground.wall_penetration(m, hint)
			if pen <= 0.0:
				continue
			var wn := ground.wall_normal
			var v := _point_vel(m)
			var vn := v.dot(wn)
			var fn := maxf(0.0, WALL_K * pen - WALL_C * vn)
			var f := wn * fn
			var vt := v - wn * vn
			vt.y = 0
			if vt.length() > 0.01:
				f += vt * (-WALL_FRICTION * fn / vt.length())
			_force_at(f, m)

	_integrate(dt)

	# aceleração no referencial do carro (filtrada) para HUD e testes
	var acc := (vel - _last_vel) / dt
	_last_vel = vel
	var kf := minf(1.0, dt * 20.0)
	g_lat += (acc.dot(_right) / G - g_lat) * kf
	g_long += (acc.dot(_fwd) / G - g_long) * kf


func _integrate(dt: float) -> void:
	vel += force * (dt / p.mass)
	var inv := rot.inverse()
	var w := inv * ang_vel
	var t := inv * torque
	var I: Vector3 = p.inertia
	t -= w.cross(Vector3(I.x * w.x, I.y * w.y, I.z * w.z))
	w += Vector3(t.x / I.x, t.y / I.y, t.z / I.z) * dt
	ang_vel = rot * w
	pos += vel * dt
	var dq := Quaternion(ang_vel.x * dt * 0.5, ang_vel.y * dt * 0.5, ang_vel.z * dt * 0.5, 0) * rot
	rot = Quaternion(rot.x + dq.x, rot.y + dq.y, rot.z + dq.z, rot.w + dq.w).normalized()

