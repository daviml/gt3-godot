# Piloto automático simples (src/track/bot.ts): segue a linha central (pure pursuit) com um perfil de
# velocidade tirado da curvatura. Serve para os testes (volta limpa de todos os carros).
class_name Bot
extends RefCounted

var track: Track
var car: Car
var v_target := PackedFloat32Array()
var throttle := 0.0
var brake := 0.0


func _init(t: Track, c: Car, lat_g := 1.3, brake_g := 1.25) -> void:
	track = t
	car = c
	var n := t.n
	v_target.resize(n)
	for i in n:
		v_target[i] = minf(85.0, sqrt(lat_g * Car.G / maxf(absf(t.curv[i]), 1e-4)))
	# de trás para frente duas vezes (volta fechada), limitando pela frenagem
	for _pass in 2:
		for k in range(n - 1, -1, -1):
			var nx := v_target[(k + 1) % n]
			v_target[k] = minf(v_target[k], sqrt(nx * nx + 2.0 * brake_g * Car.G * Track.STEP))


## [esterço, acelerador, freio]
func drive() -> Array:
	track.locate(car.pos, car.hint)
	var n := track.n
	var speed := car.fwd_speed()
	var look := 7.0 + maxf(0.0, speed) * 0.45
	var target := track.P[(track.li + roundi(look / Track.STEP)) % n]
	var to := target - car.pos
	var fwd := car.basis() * Vector3.FORWARD
	var right := Vector3(-fwd.z, 0, fwd.x).normalized()
	# deriva (β): mirando a partir do movimento, o bot contra-esterça quando a traseira escapa
	var beta := atan2(car.vel.dot(right), car.vel.dot(fwd)) if car.speed() > 5.0 else 0.0
	var alpha := atan2(to.dot(right), to.dot(fwd)) - beta
	var delta := atan(2.0 * car.p.wheelbase * sin(alpha) / maxf(to.length(), 1.0)) + beta
	var steer := clampf(delta / car.max_steer, -1.0, 1.0)

	var vt := v_target[(track.li + roundi(maxf(0.0, speed) * 0.25 / Track.STEP)) % n]
	var err := vt - speed
	# pedais suavizados; alivia quando a traseira escapa
	var lift := clampf(1.0 - (absf(beta) - 0.05) / 0.08, 0.0, 1.0)
	var thr := clampf(0.35 + err * 0.25, 0.0, 1.0) * lift
	var brk := minf(1.0, (-err - 2.0) * 0.2) if err < -2.0 else 0.0
	throttle += ((0.0 if brk > 0.0 else thr) - throttle) * 0.05
	brake += (brk - brake) * 0.08
	return [steer, throttle, brake]
