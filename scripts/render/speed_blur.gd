# Desfoque radial de velocidade (etapa 8 do PLANO / PLANO-visual etapa 1). Porte de speedBlur.ts do web.
# Borra o cenário na direção do ponto de fuga entre ~90 e ~260 km/h, preservando o centro e mascarando o carro.
# Fica numa CanvasLayer própria (layer = 1, entre a cena 3D e o HUD no layer = 2).
class_name SpeedBlur
extends CanvasLayer

var enabled := true
var max_strength := 1.0

var rect: ColorRect
var mat: ShaderMaterial


func _init() -> void:
	name = "SpeedBlur"
	layer = 1
	rect = ColorRect.new()
	rect.name = "BlurRect"
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/speed_blur.gdshader")
	rect.material = mat
	rect.visible = false
	add_child(rect)


## Atualiza o desfoque com base na velocidade do carro, câmera e projeção
func update(cam: Camera3D, car: Car, chase_mode: int, _dt: float = 0.0) -> void:
	if not enabled or max_strength <= 0.001 or cam == null or car == null:
		rect.visible = false
		return

	var speed := Vector2(car.vel.x, car.vel.z).length()
	var kmh := speed * 3.6
	# começa a aparecer a ~90 km/h e chega no máximo a ~260 km/h
	var s := smoothstep(90.0, 260.0, kmh) * max_strength
	if s <= 0.001:
		rect.visible = false
		return

	var vp := cam.get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		rect.visible = false
		return
	var aspect := vp.x / maxf(1.0, vp.y)

	# Ponto de fuga: bem à frente do carro, na direção em que ele anda
	var b := car.basis()
	var fwd := -b.z
	var vanish_world := car.pos + fwd * 300.0
	var center := Vector2(0.5, 0.5)
	if not cam.is_position_behind(vanish_world):
		var p2 := cam.unproject_position(vanish_world)
		center = Vector2(p2.x / vp.x, p2.y / vp.y)

	# Caixa do carro (com folga para asa, rodas e sombra logo embaixo): vira máscara no shader
	var car_rect := Vector4.ZERO
	if chase_mode != 1:  # 1 = capô (o carro não aparece na frente da câmera)
		var x0 := 1.0
		var y0 := 1.0
		var x1 := 0.0
		var y1 := 0.0
		var valid_corners := 0
		for sx in [-1.15, 1.15]:
			for sy in [-0.55, 0.95]:
				for sz in [-2.5, 2.5]:
					var corner := car.pos + b * Vector3(sx, sy, sz)
					if not cam.is_position_behind(corner):
						var p := cam.unproject_position(corner)
						var uv := Vector2(p.x / vp.x, p.y / vp.y)
						x0 = minf(x0, uv.x)
						y0 = minf(y0, uv.y)
						x1 = maxf(x1, uv.x)
						y1 = maxf(y1, uv.y)
						valid_corners += 1
		if valid_corners > 0 and x1 > x0 and y1 > y0:
			car_rect = Vector4(x0, y0, x1, y1)

	rect.visible = true
	mat.set_shader_parameter("strength", s)
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("car_rect", car_rect)
	mat.set_shader_parameter("aspect", aspect)
