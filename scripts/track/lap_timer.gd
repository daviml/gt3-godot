# Cronometragem (porte de src/track/timing.ts do web): volta lançada, 3 setores, limites de pista (4 rodas além da
# zebra por 0,2 s = volta inválida; escape pintado, grama e brita contam como fora) e delta ao vivo contra a melhor
# volta (tempo gravado a cada 10 m da pista).
class_name LapTimer
extends RefCounted

## passo da gravação do delta (m)
const TRACE_STEP := 10.0
## meia largura do pneu (m): basta a borda do pneu tocar a zebra para a roda contar como dentro
const TIRE_HALF_WIDTH := 0.15
## tempo (s) com as 4 rodas fora antes de invalidar: uma escorregada rápida não derruba a volta
const OFF_GRACE := 0.2


## Volta fechada: tempo, 3 setores, válida e o tempo ao passar por cada trecho de 10 m (para o delta).
class Lap:
	var time := 0.0
	var sectors: Array[float] = []
	var valid := true
	var trace: PackedFloat32Array


var track: Track
## tempo da volta atual (s); negativo = ainda não cruzou a linha pela primeira vez
var current := -1.0
var sectors: Array[float] = []
var valid := true
var last: Lap = null
var best: Lap = null
var laps: Array[Lap] = []
## chamado a cada volta fechada (com setores completos)
var on_lap: Callable
## diferença para a melhor volta no mesmo ponto da pista (s); NAN sem referência
var delta := NAN
## posição na pista (m) no último update, para o HUD
var s := 0.0

var _last_s := -1.0
var _off_time := 0.0
## última situação de cada roda (dentro/fora), mantida enquanto ela está no ar
var _wheel_in := [true, true, true, true]
var _trace: PackedFloat32Array
var _splits: Array[float]


func _init(t: Track) -> void:
	track = t
	_splits = [track.length / 3.0, 2.0 * track.length / 3.0]
	_trace = _new_trace()


func _new_trace() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(ceili(track.length / TRACE_STEP) + 1)
	a.fill(NAN)
	return a


## tempo da referência ao passar em s, interpolado entre os trechos gravados
func _ref_time(ref: PackedFloat32Array, at: float) -> float:
	var k := floori(at / TRACE_STEP)
	if k + 1 >= ref.size():
		return ref[k] if k < ref.size() else NAN
	var a := ref[k]
	var b := ref[k + 1]
	if is_nan(a):
		return NAN
	if is_nan(b):
		return a
	return a + (b - a) * (at / TRACE_STEP - k)


func reset() -> void:
	current = -1.0
	sectors = []
	valid = true
	_last_s = -1.0
	delta = NAN
	_off_time = 0.0
	_wheel_in = [true, true, true, true]
	_trace = _new_trace()


## Limite de pista como no LMU/iRacing: a roda está dentro enquanto a borda do pneu toca o asfalto ou a zebra (a
## linha branca e a zebra são pista; escape pintado, grama e brita não). Roda no ar mantém a última situação, para
## um pulo na zebra não contar como fora.
func all_wheels_out(car: Car) -> bool:
	for k in 4:
		var w: Car.Wheel = car.wheels[k]
		if not w.contact:
			continue
		track.locate(w.cpoint, car.hint)
		var limit := (track.lwl + track.lkl) if track.ld < 0.0 else (track.lwr + track.lkr)
		_wheel_in[k] = absf(track.ld) - TIRE_HALF_WIDTH <= limit
	return not (_wheel_in[0] or _wheel_in[1] or _wheel_in[2] or _wheel_in[3])


func _sum(a: Array[float]) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t


func update(dt: float, car: Car) -> void:
	track.locate(car.pos, car.hint)
	# locate() reaproveita o resultado: guarda s antes de consultar as rodas
	s = track.ls
	var L := track.length
	if current >= 0.0:
		current += dt
		# limite de pista: as 4 rodas além da zebra por mais de OFF_GRACE invalidam a volta
		_off_time = _off_time + dt if all_wheels_out(car) else 0.0
		if _off_time >= OFF_GRACE:
			valid = false
		var k10 := floori(s / TRACE_STEP)
		if k10 < _trace.size() and is_nan(_trace[k10]):
			_trace[k10] = current
		if best:
			var ref := _ref_time(best.trace, s)
			delta = NAN if is_nan(ref) else current - ref
		for k in 2:
			var split := _splits[k]
			if sectors.size() == k and _last_s < split and s >= split and s - _last_s < 50.0:
				sectors.append(current - _sum(sectors))
	# cruzou a linha de chegada andando para frente
	if _last_s > L - 60.0 and s < 60.0:
		if current >= 0.0 and sectors.size() == 2:
			var lap := Lap.new()
			lap.time = current
			lap.sectors = [sectors[0], sectors[1], current - sectors[0] - sectors[1]]
			lap.valid = valid
			lap.trace = _trace
			last = lap
			laps.append(lap)
			if lap.valid and (best == null or lap.time < best.time):
				best = lap
			if on_lap.is_valid():
				on_lap.call(lap)
		current = 0.0
		sectors = []
		valid = true
		_trace = _new_trace()
		_trace[0] = 0.0
	_last_s = s


static func format_time(t: float) -> String:
	if is_nan(t) or t < 0.0:
		return "-:--.---"
	var m := floori(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]
