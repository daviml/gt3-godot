# Física do carro portada do jogo web (src/physics/car.ts, tire.ts, rigidbody.ts): chassi rígido, 4 rodas
# com suspensão por raio, pneu Pacejka com slip combinado, motor, câmbio automático, autoblocante, ABS e TC.
# Eixos locais: +X direita, +Y cima, -Z frente (igual ao Three.js e ao Godot).
class_name Car
extends RefCounted

const G := 9.81
const AIR := 1.225
const V_LOW := 3.0
const RPM_TO_RAD := TAU / 60.0

# Porsche 992 GT3 R = GT3 base + acerto de motor traseiro + calibração com telemetria (data/cars/*.json)
var p := {
	"mass": 1300.0, "inertia": Vector3(2400, 2700, 600), "cg": 0.37, "wheelbase": 2.439, "wf": 0.39,
	"track_f": 1.628, "track_r": 1.6, "radius": 0.336, "wheel_inertia": 1.2,
	"front": {"k": 150000.0, "bump": 7000.0, "rebound": 9000.0, "arb": 80000.0, "rest": 0.08, "travel": 0.07, "rc": 0.05},
	"rear": {"k": 170000.0, "bump": 7500.0, "rebound": 9500.0, "arb": 25000.0, "rest": 0.08, "travel": 0.07, "rc": 0.08},
	"mu": 2.2, "mu_long": 0.6, "load_sens": 0.12, "fz0": 4000.0, "b_lat": 12.0, "c_lat": 1.55, "e_lat": 0.3,
	"b_long": 15.0, "c_long": 1.65, "e_long": 0.2, "relax": 0.15, "roll_res": 0.012, "rear_grip": 1.0,
	"clA": 2.2, "cdA": 0.9, "aero_front": 0.38,
	"torque": [[1000, 200], [3000, 320], [5000, 360], [6500, 385], [7500, 380], [8500, 350], [9400, 320], [9800, 300]],
	"idle": 1200.0, "limiter": 9400.0, "launch": 3500.0, "eng_inertia": 0.15, "fric_base": 20.0, "fric_rpm": 0.012,
	"ratios": [2.574, 1.994, 1.609, 1.336, 1.156, 1.0], "final": 4.02, "reverse": 3.0, "shift_time": 0.06, "eff": 0.92,
	"preload": 120.0, "ramp_power": 0.35, "ramp_coast": 0.2, "viscous": 150.0,
	"brake_max": 10000.0, "brake_bias": 0.57, "steer_deg": 18.0,
}

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

var track: Track
var pos := Vector3.ZERO
var rot := Quaternion.IDENTITY
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


func _init(t: Track) -> void:
	track = t
	kappa_peak = _peak_slip(p.b_long, p.c_long, p.e_long)
	alpha_peak = _peak_slip(p.b_lat, p.c_lat, p.e_lat)
	max_steer = deg_to_rad(p.steer_deg)
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
	return mu * fz * grip


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


func reset_at(i: int) -> void:
	var t := track.T[i]
	var r := track.R[i]
	var up := r.cross(t).normalized()
	pos = track.P[i] + up * (p.cg + 0.05)
	rot = Basis(r, up, -t).orthonormalized().get_rotation_quaternion()
	vel = Vector3.ZERO
	ang_vel = Vector3.ZERO
	for w in wheels:
		w.omega = 0; w.comp = 0; w.comp_vel = 0; w.fy = 0
	gear = 1
	rpm = p.idle
	shift_timer = 0
	tc_cut = 0
	hint = i


func basis() -> Basis:
	return Basis(rot)


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


func road_rpm(g: int) -> float:
	var om := maxf((wheels[2].omega + wheels[3].omega) / 2.0, fwd_speed() / p.radius)
	return om * gear_ratio(g) / RPM_TO_RAD


func _shift(throttle: float, brake: float, dt: float) -> void:
	if shift_timer > 0.0:
		shift_timer -= dt
		return
	var target := gear
	var lim: float = p.limiter
	if gear >= 1:
		if rpm > lim - 250.0 and gear < p.ratios.size() and throttle > 0.1:
			target = gear + 1
		elif gear > 1:
			var lower := road_rpm(gear - 1)
			if (brake > 0.05 and lower < lim - 550.0) or (brake <= 0.05 and throttle > 0.5 and lower < lim - 1200.0) \
					or (brake <= 0.05 and throttle <= 0.5 and rpm < lim * 0.45):
				target = gear - 1
	if target != gear:
		gear = target
		shift_timer = p.shift_time


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


const CORNERS := [Vector3(-1, 0, -2.35), Vector3(1, 0, -2.35), Vector3(-1, 0, 2.25), Vector3(1, 0, 2.25), Vector3(-1, 0, 0), Vector3(1, 0, 0)]

func step(dt: float, steer_in: float, throttle_in: float, brake_in: float) -> void:
	var B := basis()
	force = Vector3(0, -p.mass * G, 0)
	torque = Vector3.ZERO
	var up := B.y
	var fwd := -B.z
	var down := -up
	var vf := vel.dot(fwd)
	hint = track.nearest(pos, hint)

	# aerodinâmica
	var dn: float = 0.5 * AIR * vf * vf * p.clA
	var a: float = p.wheelbase * (1.0 - p.wf)
	var b: float = p.wheelbase * p.wf
	_force_at(down * dn * p.aero_front, pos + B * Vector3(0, 0, -a))
	_force_at(down * dn * (1.0 - p.aero_front), pos + B * Vector3(0, 0, b))
	force += -vel * (0.5 * AIR * p.cdA * vel.length())

	# câmbio, motor, TC
	_shift(throttle_in, brake_in, dt)
	var fz_r := wheels[2].fz + wheels[3].fz
	var rear_over := false
	for w in [wheels[2], wheels[3]]:
		if w.fz > 0.15 * fz_r and w.kappa > 0.3 * kappa_peak and Vector2(w.kappa / kappa_peak, w.alpha / alpha_peak).length() > 1.0:
			rear_over = true
	tc_cut = minf(0.9, tc_cut + dt * 15.0) if rear_over else maxf(0.0, tc_cut - dt * 3.0)
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
		var dist := track.probe(m, down, l, hint)
		var c := 0.0
		w.contact = dist >= 0.0
		if w.contact:
			c = l - dist
			w.cpoint = track.hit_point
			w.cnormal = track.hit_normal
			w.surface = track.hit_surface
		w.comp_vel = (c - w.comp) / dt
		w.comp = c

	var r: float = p.radius
	for i in 4:
		var w := wheels[i]
		var s: Dictionary = w.susp
		var other := wheels[i ^ 1]
		var iw: float = p.wheel_inertia + (0.0 if w.front else reflected)
		if not w.contact:
			w.fz = 0; w.fx = 0; w.fy = 0; w.kappa = 0; w.alpha = 0
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
		var grip: float = Track.GRIP[w.surface] * (1.0 if w.front else p.rear_grip)

		var k0 := (w.omega * r - vx) / denom
		var f0 := tire(w.fz, k0, alpha, grip)
		var f1 := tire(w.fz, k0 + 1e-4, alpha, grip)
		var slope := maxf(0.0, (f1.x - f0.x) / 1e-4) * r / denom
		var den := iw + dt * r * slope
		var om := w.omega + dt * (w.drive - r * f0.x) / den
		var bd := w.brake * dt / den
		# ABS: limita o freio para o escorregamento não passar do pico (descontando o que o pneu usa para virar)
		if vx > 2.0 and bd > 0.0:
			var side := alpha / alpha_peak
			var kT := kappa_peak * sqrt(maxf(0.04, 0.92 * 0.92 - side * side))
			var om_min := (vx - kT * denom) / r
			bd = minf(bd, maxf(0.0, om - om_min))
		om = maxf(0.0, om - bd) if om > 0.0 else minf(0.0, om + bd)
		w.omega = om
		w.spin += om * dt

		w.kappa = (om * r - vx) / denom
		w.alpha = alpha
		var ff := tire(w.fz, w.kappa, alpha, grip)
		var relax: float = minf(1.0, maxf(absf(vx), 8.0) * dt / p.relax)
		w.fy += (ff.y - w.fy) * relax
		var pk := peak_force(w.fz, grip)
		var fy_max := sqrt(maxf(0.0, pk * pk - ff.x * ff.x))
		w.fy = clampf(w.fy, -fy_max, fy_max)
		w.fx = ff.x - (p.roll_res + Track.DRAG[w.surface]) * w.fz * tanh(vx)
		_force_at(wf * w.fx + wr * w.fy, w.cpoint + up * s.rc)

	# muros: mola-amortecedor nos cantos da carroceria + atrito
	for c: Vector3 in CORNERS:
		var m := pos + B * c
		var pen := track.wall_penetration(m, hint)
		if pen <= 0.0:
			continue
		var wn := track.wall_normal
		var v := _point_vel(m)
		var vn := v.dot(wn)
		var fn := maxf(0.0, 2e6 * pen - 4e4 * vn)
		var f := wn * fn
		var vt := v - wn * vn
		vt.y = 0
		if vt.length() > 0.01:
			f += vt * (-0.35 * fn / vt.length())
		_force_at(f, m)

	_integrate(dt)


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
