# Piloto que segue uma volta de referência do iRacing (src/track/refBot.ts): traçado + velocidade de uma volta
# real (data/reference/*.json). Mede a física: se o carro não segura o traçado na velocidade real, falta
# aderência. Pedais = os da referência (antecipação) + correção pelo erro de velocidade.
# O traçado é limitado à pista (e à zebra) e suavizado; onde a curva do jogo é mais fechada que a real, a
# velocidade alvo cai para o que a curva permite.
class_name RefBot
extends RefCounted

const ACCEL_GT3 := [[60, 0.75], [100, 0.6], [120, 0.52], [140, 0.45], [180, 0.27], [220, 0.24], [260, 0.08], [290, 0]]

var track: Track
var car: Car
var ref: Dictionary
## multiplica a velocidade da referência (1 = igual)
var speed_scale := 1.0
## posição (s) da última consulta, erro lateral ao traçado (m) e velocidade alvo
var s := 0.0
var line_error := 0.0
var target_speed := 0.0
## deslocamento lateral do traçado por amostra e velocidade máxima pela curvatura do traçado no jogo
var offset := PackedFloat32Array()
var v_cap := PackedFloat32Array()
var throttle := 0.0
var brake := 0.0
var hold_line := 0.0
var line_gain := 0.0
## malha fechada pela taxa de giro: compara a curvatura pedida pelo pure pursuit com a que o carro faz de verdade
## (giro / velocidade) e esterça mais quando ele sai de frente, como um piloto. 0 = desligado (paridade antiga).
var yaw_p := 0.0
var yaw_i := 0.0
var _yaw_int := 0.0
var _rv: PackedFloat32Array
var _rthr: PackedFloat32Array
var _rbrk: PackedFloat32Array


static func load_ref(ref_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/reference/%s.json" % ref_name))


static func _lerp_table(t: Array, x: float) -> float:
	if x <= t[0][0]: return t[0][1]
	for i in range(1, t.size()):
		if x <= t[i][0]:
			return t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (x - t[i - 1][0]) / (t[i][0] - t[i - 1][0])
	return t[t.size() - 1][1]


## opts: lat_g [g0, g1], brake_g, edge [asfalto, zebra], hold_line, line_gain (mesmos padrões do web)
func _init(t: Track, c: Car, reference: Dictionary, opts := {}) -> void:
	track = t
	car = c
	ref = reference
	_rv = PackedFloat32Array(ref.v)
	_rthr = PackedFloat32Array(ref.throttle)
	_rbrk = PackedFloat32Array(ref.brake)
	hold_line = opts.get("hold_line", 0.0)
	line_gain = opts.get("line_gain", 0.0)
	yaw_p = opts.get("yaw_p", 0.0)
	yaw_i = opts.get("yaw_i", 0.0)
	var n := t.n
	var raw := PackedFloat32Array()
	raw.resize(n)
	var edge: Array = opts.get("edge", [-0.5, 0.3])
	var rd: Array = ref.d
	for i in n:
		# sem zebra: centro do carro a 0,5 m da borda; com zebra, pode montar nela
		var d: float = rd[i]
		var lim: float = (t.wr[i] if d > 0.0 else t.wl[i]) + (edge[1] if t.has_kerb(i) else edge[0])
		raw[i] = clampf(d, -lim, lim)
	# suaviza (média móvel de ±12 m) para não ter dobra onde o limite cortou o traçado
	offset.resize(n)
	var W := 6
	for i in n:
		var acc := 0.0
		for k in range(-W, W + 1):
			acc += raw[(i + k + n) % n]
		offset[i] = acc / (2 * W + 1)
	# curvatura do traçado final (círculo por 3 pontos) e a velocidade que ela permite
	var lat: Array = opts.get("lat_g", [1.85, 2.4])
	var pts := PackedVector3Array()
	for i in n:
		pts.append(t.P[i] + t.R[i] * offset[i])
	v_cap.resize(n)
	for i in n:
		var a := pts[(i - 6 + n) % n]
		var b := pts[i]
		var c3 := pts[(i + 6) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z).length()
		var bc := Vector2(c3.x - b.x, c3.z - b.z).length()
		var ac := Vector2(c3.x - a.x, c3.z - a.z).length()
		var cross := absf((b.x - a.x) * (c3.z - a.z) - (b.z - a.z) * (c3.x - a.x))
		var kk := 2.0 * cross / maxf(1e-6, ab * bc * ac)
		var v := 90.0
		for _it in 4:
			var g: float = lat[0] + (lat[1] - lat[0]) * minf(1.0, v * v / (70.0 * 70.0))
			v = minf(90.0, sqrt(g * Car.G / maxf(kk, 1e-5)))
		v_cap[i] = v
	# saída: onde o limite da curva ficou abaixo da referência, só volta a ela acelerando como o carro real
	var acc_t: Array = opts.get("accel_g", ACCEL_GT3)
	for _pass in 2:
		for i in n:
			var prev := minf(v_cap[(i - 1 + n) % n], _rv[(i - 1 + n) % n])
			var a := _lerp_table(acc_t, prev * 3.6) * Car.G
			v_cap[i] = minf(v_cap[i], sqrt(prev * prev + 2.0 * a * Track.STEP) + 0.3)
	# entrada: chega nessas curvas freando
	var bg: float = opts.get("brake_g", 1.6) * Car.G
	for _pass in 2:
		for i in range(n - 1, -1, -1):
			var nx := v_cap[(i + 1) % n]
			v_cap[i] = minf(v_cap[i], sqrt(nx * nx + 2.0 * bg * Track.STEP))


## valor interpolado de uma série da referência em s (refAt do web)
func ref_at(series: PackedFloat32Array, at: float) -> float:
	var n := series.size()
	var x: float = at / float(ref.step)
	var fl := floorf(x)
	var i := posmod(int(fl), n)
	return series[i] + (series[(i + 1) % n] - series[i]) * (x - fl)


func line_offset(at: float) -> float:
	var n := offset.size()
	var x := fposmod(at / Track.STEP, n)
	var i := int(x)
	return offset[i] + (offset[(i + 1) % n] - offset[i]) * (x - i)


func line_point(at: float) -> Vector3:
	var n := track.n
	var x := fposmod(at / Track.STEP, n)
	var i := int(x)
	return track.P[i].lerp(track.P[(i + 1) % n], x - i) + track.R[i] * line_offset(at)


## velocidade alvo em s: a da referência (× escala), limitada pela curva do jogo
func speed_at(at: float) -> float:
	return minf(ref_at(_rv, at) * speed_scale, v_cap[track.index_at(at)])


## [esterço, acelerador, freio]
func drive() -> Array:
	track.locate(car.pos, car.hint)
	var v := maxf(0.0, car.fwd_speed())
	s = track.ls
	var fwd := car.basis() * Vector3.FORWARD
	var right := Vector3(-fwd.z, 0, fwd.x).normalized()
	line_error = track.ld - line_offset(s)
	var beta := atan2(car.vel.dot(right), car.vel.dot(fwd)) if car.speed() > 5.0 else 0.0

	# direção: pure pursuit num ponto à frente no traçado, medido a partir da direção do movimento
	var look := 5.0 + v * 0.3
	var target := line_point(s + look)
	if line_gain != 0.0:
		target += track.R[posmod(int(floorf((s + look) / Track.STEP)), track.n)] * (-line_error * line_gain)
	var to := target - car.pos
	var alpha := atan2(to.dot(right), to.dot(fwd)) - beta
	var k_want := 2.0 * sin(alpha) / maxf(to.length(), 1.0)
	var delta := atan(car.p.wheelbase * k_want) + beta
	if (yaw_p > 0.0 or yaw_i > 0.0) and v > 8.0:
		# curvatura real do caminho (+ = direita, como o esterço)
		var k_real := -car.ang_vel.dot(car.basis().y) / v
		var k_err := k_want - k_real
		_yaw_int = clampf(_yaw_int + k_err * yaw_i / Car.HZ, -0.06, 0.06)
		delta += car.p.wheelbase * k_err * yaw_p + _yaw_int
	var steer := clampf(delta / car.max_steer, -1.0, 1.0)

	# velocidade: alvo um pouco à frente (reação), pedais da referência + correção
	var ahead := s + v * 0.15
	var vt := speed_at(ahead)
	if hold_line > 0.0:
		vt *= 1.0 - minf(0.15, maxf(0.0, absf(line_error) - 1.0) * hold_line)
	target_speed = vt
	var err := vt - v
	var thr := ref_at(_rthr, ahead) + err * 0.4
	var brk := ref_at(_rbrk, ahead) - err * 0.25
	if err > 0.5: brk = 0.0
	if err < -0.5 or brk > 0.05: thr = 0.0
	thr *= clampf(1.0 - (absf(beta) - 0.05) / 0.08, 0.0, 1.0)
	thr = clampf(thr, 0.0, 1.0)
	brk = clampf(brk, 0.0, 1.0)
	throttle += (thr - throttle) * 0.25
	brake += (brk - brake) * 0.25
	return [steer, throttle, brake]
