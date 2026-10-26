class_name CoinFlip
extends CanvasLayer
## 선공 동전 연출: 화면 아래에서 동그란 금화가 튀어 올라 오른쪽으로 돌다가 떨어지며 결과 면을 보여준다.
## 앞면 = 고양이가 새겨진 면(아군 선공), 뒷면 = 아무것도 없는 매끈한 면(적 선공).
## 3D 금화(원기둥)를 투명 배경 SubViewport 에 그려 화면 위에 겹친다.

signal finished

const RISE_TIME := 0.55
const FALL_TIME := 0.6
const HOLD_TIME := 0.9
const FADE_TIME := 0.3
const SPINS := 4                     # 공중에서 도는 바퀴 수

var _vp: SubViewport
var _rect: TextureRect
var _coin: Node3D


func _ready() -> void:
	layer = 20
	_vp = SubViewport.new()
	_vp.size = Vector2i(2560, 1440)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 10)
	cam.fov = 30.0
	_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.6
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, 40, 0)
	fill.light_energy = 0.5
	_vp.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.9, 0.7)
	e.ambient_light_energy = 0.55
	env.environment = e
	_vp.add_child(env)
	_coin = _make_coin()
	_vp.add_child(_coin)
	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture = _vp.get_texture()
	_rect.size = Vector2(1280, 720)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # 연출 중 클릭 막기
	add_child(_rect)


## 금화: 얇은 원기둥(옆면·뒷면 매끈) + 앞면에 고양이 새김 원판
func _make_coin() -> Node3D:
	var root := Node3D.new()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.93, 0.72, 0.26)
	gold.metallic = 0.85
	gold.roughness = 0.32
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.14
	cyl.radial_segments = 64
	body.mesh = cyl
	body.material_override = gold
	body.rotation_degrees = Vector3(90, 0, 0)   # 원기둥 축을 카메라 방향(z)으로 → 면이 카메라를 봄
	root.add_child(body)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	face.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load("res://assets/textures/coin_cat.png")
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.metallic = 0.6
	fm.roughness = 0.5
	face.material_override = fm
	face.position = Vector3(0, 0, 0.072)       # 앞면 바로 위
	root.add_child(face)
	return root


## face: "front"(고양이) | "back"(민짜). 끝나면 finished.
func play(face: String) -> void:
	var final_y := 0.0 if face == "front" else 180.0
	_coin.position = Vector3(0, -6.0, 0)
	_coin.rotation_degrees = Vector3(0, 0, 0)
	_rect.modulate.a = 1.0
	# 회전: 오른쪽으로 (y 축 + 방향 = 면이 오른쪽으로 돌아감), 올라갔다 떨어지는 내내
	var spin := create_tween()
	spin.tween_property(_coin, "rotation_degrees:y", SPINS * 360.0 + final_y, RISE_TIME + FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 이동: 아래에서 튀어 오름 → 떨어져 통통 튐 → 잠시 보여줌 → 사라짐
	var tw := create_tween()
	tw.tween_property(_coin, "position:y", 1.6, RISE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_coin, "rotation_degrees:x", -25.0, RISE_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_coin, "position:y", 0.0, FALL_TIME).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_coin, "rotation_degrees:x", 0.0, FALL_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(_rect, "modulate:a", 0.0, FADE_TIME)
	await tw.finished
	finished.emit()
	queue_free()
