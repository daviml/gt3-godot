# Câmeras (a Camera3D deve ser filha de um nó na origem): perseguição (padrão, estilo LMU), capô e longe. Porte de gt3-time-attack/src/render/camera.ts.
# A perseguição fica presa atrás e acima do carro: gira quase junto com ele, com um atraso curto, altura
# filtrada e pouca variação de distância — dá para sentir a pista sem a câmera balançar.
class_name ChaseCamera
extends RefCounted

const MODES := ["perseguição", "capô", "longe"]


## Mola criticamente amortecida (SmoothDamp): segue o alvo em ~`time` segundos, sem passar dele.
class Spring:
	var value := 0.0
	var vel := 0.0

	func _init(v := 0.0) -> void:
		value = v

	func update(target: float, time: float, dt: float) -> float:
		var omega := 2.0 / maxf(time, 1e-4)
		var x := omega * dt
		var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var change := value - target
		var temp := (vel + omega * change) * dt
		vel = (vel - omega * temp) * e
		value = target + (change + temp) * e
		return value

	func reset(v: float) -> void:
		value = v
		vel = 0.0


var mode := 0
var cam: Camera3D
var car: Car
var heading := Vector3(0, 0, -1)
var dist := Spring.new(6.4)
var py := Spring.new()
var look_y := Spring.new()
var fov := Spring.new(50.0)
## força G longitudinal filtrada (sem os picos da troca de marcha)
var gl := Spring.new()
## intensidade da tremida (zebra / alta velocidade), suavizada
var shake := Spring.new()
var time := 0.0
var first := true


func _init(c: Camera3D, cr: Car) -> void:
	cam = c
	car = cr


func mode_name() -> String:
	return MODES[mode]


func next() -> void:
	mode = (mode + 1) % MODES.size()
	first = true


## depois de um reset do carro, a câmera pula direto para trás dele
func snap() -> void:
	first = true


## FOV vertical que mantém pelo menos a visão lateral de uma tela 16:9 em janelas estreitas/retrato.
static func fit_fov(fov16x9: float, aspect: float) -> float:
	if aspect >= 16.0 / 9.0:
		return fov16x9
	var half_h := tan(deg_to_rad(fov16x9) / 2.0) * (16.0 / 9.0)
	return minf(100.0, rad_to_deg(2.0 * atan(half_h / aspect)))


func update(dt: float, frac := 1.0) -> void:
	var v_pos := car.visual_pos(frac)
	var b := car.visual_basis(frac)
	var aspect := 16.0 / 9.0
	if cam.is_inside_tree():
		var vp := cam.get_viewport().get_visible_rect().size
		aspect = vp.x / maxf(1.0, vp.y)
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	if mode == 1:  # capô
		cam.transform = Transform3D(b, v_pos + b * Vector3(0, 0.85, -1.3))
		cam.fov = fit_fov(75.0, aspect)
		return

	# câmera presa atrás do carro: segue a frente dele com um atraso curto (só o bastante para sentir a curva)
	var speed := Vector2(car.vel.x, car.vel.z).length()
	if first:
		heading = fwd
	# atraso de ~0,15 s no giro (nas curvas aparece um pouco da lateral do carro, como no LMU), no máximo 6°
	heading = heading.lerp(fwd, 1.0 - exp(-dt * 6.5)).normalized()
	var lag := atan2(heading.x * fwd.z - heading.z * fwd.x, heading.dot(fwd))
	var max_lag := deg_to_rad(6.0)
	if absf(lag) > max_lag:
		# mesmo sentido do applyAxisAngle do three.js (rotação positiva em torno de +Y)
		heading = fwd.rotated(Vector3.UP, signf(lag) * max_lag)

	var far := mode == 2
	# FOV de 50° e posição da câmera de fora do LMU (vídeo de referência): o carro ocupa ~22% da largura da tela
	var base_dist := 11.0 if far else 6.8
	var height := 3.4 if far else 1.85
	if first:
		dist.reset(base_dist)
		py.reset(v_pos.y + height)
		look_y.reset(v_pos.y + 0.75)
		gl.reset(0.0)
		shake.reset(0.0)
		first = false
	# freada: a câmera chega um pouco para a frente (~35 cm na freada forte); aceleração: se afasta (~15–20 cm).
	# A força G é filtrada antes, para a troca de marcha não dar tranco.
	var g := gl.update(clampf(car.g_long, -2.2, 1.0), 0.25, dt)
	var d := dist.update(base_dist + (g * 0.16 if g < 0.0 else g * 0.24), 0.45, dt)
	var pos := v_pos - heading * d
	# altura bem filtrada: zebra e lombada não chacoalham a câmera
	pos.y = py.update(v_pos.y + height, 0.2, dt)
	# tremida bem leve: rodas na zebra e acima de 250 km/h
	time += dt
	var on_kerb := false
	for w in car.wheels:
		on_kerb = on_kerb or (w.contact and w.surface == Ground.KERB and w.fz > 500.0)
	var kmh := speed * 3.6
	var amp := shake.update((0.012 if on_kerb else 0.0) + smoothstep(250.0, 300.0, kmh) * 0.006, 0.08, dt)
	if amp > 1e-4:
		pos.y += amp * (sin(time * 61.0) * 0.6 + sin(time * 97.0 + 1.3) * 0.4)
		pos += Vector3(-heading.z, 0, heading.x) * (amp * 0.5 * sin(time * 73.0 + 0.7))
	var look := v_pos + heading * 3.0
	look.y = look_y.update(v_pos.y + 0.8, 0.2, dt)
	# transform local: a câmera é filha direta da cena (sem deslocamento), então vale como global
	cam.transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	# FOV abre um pouco com a velocidade (sensação de velocidade), suavizado
	cam.fov = fit_fov(fov.update(50.0 + minf(3.5, speed * 0.045), 0.8, dt), aspect)
