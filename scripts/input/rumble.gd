# Vibração do controle (src/input/rumble.ts do web), o mais perto de force feedback sem volante:
# motor forte (grave) = zebra, grama, batida e ABS; motor fraco (agudo) = pneu escorregando e limitador.
# Chamar uma vez por quadro (como no web): a batida é medida pela queda de velocidade entre quadros.
class_name Rumble
extends RefCounted

var enabled := true
## último pedido aos motores (forte, fraco), para os testes e o HUD
var last := Vector2.ZERO

var _last_speed := 0.0
var _hit := 0.0
var _next := 0.0
var _clock := 0.0


func update(car: Car, dt: float) -> void:
	var m := compute(car, dt)
	var d := PadManager.active
	var k := Bindings.rumble
	if d < 0 or not enabled or k <= 0.0 or m == Vector2.ZERO:
		return
	# web: Gamepad weakMagnitude = 70% do motor fraco; Godot: start_joy_vibration(aparelho, fraco, forte, s)
	# vibra o controle que está sendo lido (o PadManager já foi atualizado pelo InputReader neste quadro)
	Input.start_joy_vibration(d, minf(1.0, m.y * 0.7 * k), minf(1.0, m.x * k), 0.07)


## intensidade (forte, fraco) do próximo efeito, ou zero quando não é hora de renovar ou não há o que vibrar
func compute(car: Car, dt: float) -> Vector2:
	_clock += dt
	# desaceleração brusca (batida) medida pela variação de velocidade
	var speed := car.speed()
	var decel := (_last_speed - speed) / maxf(dt, 1e-3)
	_last_speed = speed
	if decel > 25.0:
		_hit = minf(1.0, decel / 60.0)
	_hit = maxf(0.0, _hit - dt * 4.0)
	if _clock < _next:
		return Vector2.ZERO
	_next = _clock + 0.05 # um efeito curto a cada 50 ms, renovado enquanto durar a condição

	var strong := _hit
	var weak := 0.0
	for w in car.wheels:
		if not w.contact:
			continue
		if w.surface == Ground.KERB:
			strong = maxf(strong, 0.35 * minf(1.0, speed / 15.0))
		if w.surface == Ground.GRASS or w.surface == Ground.GRAVEL:
			strong = maxf(strong, 0.25 * minf(1.0, speed / 10.0))
		if w.abs_active:
			strong = maxf(strong, 0.3)
		var s := Vector2(w.kappa / car.kappa_peak, w.alpha / car.alpha_peak).length()
		weak = maxf(weak, minf(1.0, maxf(0.0, s - 0.9) * 2.0) * minf(1.0, speed / 8.0))
	if car.rpm > float(car.p.limiter) - 40.0:
		weak = maxf(weak, 0.2)
	if strong < 0.02 and weak < 0.02:
		return Vector2.ZERO
	last = Vector2(minf(1.0, strong), minf(1.0, weak))
	return last
