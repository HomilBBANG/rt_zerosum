class_name BattleView2D
extends BattleViewBase
## 경로 A (02_graphics v0.2 §4): 원화 + 구역 마스크 + cel_zoned_lighting 셰이더.

const ZONE_SHADER := preload("res://shaders/cel_zoned_lighting.gdshader")
const UNIT_SCRIPT := preload("res://scripts/presentation/unit_sprite_2d.gd")

@onready var world: Node2D = $World
@onready var bg: Sprite2D = $World/Background
@onready var units_root: Node2D = $World/Units
@onready var markers_root: Node2D = $World/Markers
@onready var clear_rect: ColorRect = $Clear

var manifest: Dictionary = {}
var sprites: Dictionary = {}   # instance_id -> UnitSprite2D
var bg_mat: ShaderMaterial
var _marker_nodes: Array[Node2D] = []


## 가상 카메라 (tools/gen_sprites.py CAMERA 와 같은 값, manifest.json "camera").
## 40° 내려다보는 원근: 바닥 위 슬롯(월드 m)을 화면으로 투영하고, 거리로 캐릭터 크기를 정한다.
static var cam: Dictionary = {}
static var _cam_ready := false
static var _C := Vector3.ZERO
static var _F := Vector3.ZERO
static var _U := Vector3.ZERO
static var _focal := 1255.0


static func set_camera(c: Dictionary) -> void:
	cam = c
	var p := deg_to_rad(float(c.get("pitch_deg", 40.0)))
	var t: Array = c.get("target", [0.0, 0.0, 0.6])
	var d := float(c.get("dist", 15.0))
	var scr: Array = c.get("screen", [1280, 720])
	_focal = (float(scr[1]) * 0.5) / tan(deg_to_rad(float(c.get("vfov_deg", 32.0)) * 0.5))
	_C = Vector3(float(t[0]), float(t[1]) + d * sin(p), float(t[2]) + d * cos(p))
	_F = Vector3(0.0, -sin(p), -cos(p))
	_U = Vector3(0.0, cos(p), -sin(p))
	_cam_ready = true


static func project(w: Vector3) -> Vector2:
	var v := w - _C
	var zc := v.dot(_F)
	return Vector2(float(cam.cx) + _focal * v.x / zc, float(cam.cy) - _focal * v.dot(_U) / zc)


static func slot_world(team: String, row: int, index: int) -> Vector3:
	# 아군 왼쪽(전방이 중앙 쪽), 적 오른쪽. index 1 이 카메라에 가까운 줄, 진영 바깥으로 살짝 엇갈림.
	var sl: Dictionary = cam.get("slot", {})
	var rx: Array = sl.get("row_x", [1.3, 3.0, 4.7])
	var iz: Array = sl.get("index_z", [-0.3, 1.5])
	var sign := -1.0 if team == "ally" else 1.0
	var x := sign * (float(rx[row]) + float(sl.get("index_dx", 0.4)) * index)
	return Vector3(x, 0.0, float(iz[index]))


static func slot_position(team: String, row: int, index: int) -> Vector2:
	return project(slot_world(team, row, index))


## 슬롯에 선 캐릭터의 화면 배율 (스프라이트 기준 키 sprite_px 가 원근 키가 되도록)
static func slot_scale(team: String, row: int, index: int) -> float:
	var v := slot_world(team, row, index) - _C
	var px := _focal * float(cam.get("unit_height_m", 1.75)) / v.dot(_F)
	return px / float(cam.get("sprite_px", 230.0))


static func zone_for_slot(team: String, row: int) -> String:
	# 배경 마스크의 빛 영역과 대응: 아군 후방 = 창문 보조광, 적 = 문 주조명, 그 사이 = 주변광
	if team == "enemy":
		return "key"
	if row == 2:
		return "accent"
	if row == 1:
		return "ambient"
	return "ambient"


func _ready() -> void:
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	set_camera(manifest.get("camera", {}))
	# 배경은 2배 해상도(레티나 대응)로 생성되어 있으므로 화면 크기에 맞춰 축소
	bg.scale = Vector2.ONE * (1280.0 / float(bg.texture.get_width()))
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = ZONE_SHADER
	bg_mat.set_shader_parameter("zone_mask", load("res://assets/textures/bg_barracks_mask.png"))
	bg.material = bg_mat
	_make_camera()


func setup(p_controller: BattleController, p_preset: Dictionary) -> void:
	super.setup(p_controller, p_preset)
	controller.battle_started.connect(_spawn_units)
	controller.battle_started.connect(_play_intro)
	controller.actor_started.connect(func(u, _r): focus_unit(u, CAM_MOVE_TIME))
	if not controller.slots.all_units().is_empty():
		_spawn_units()
	controller.action_resolved.connect(_on_action_resolved)
	controller.unit_moved.connect(_on_unit_moved)
	controller.units_swapped.connect(_on_units_swapped)
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.unit_died.connect(_on_unit_died)


# ---------------------------------------------------------------- 전투 카메라
## 전투 시작 시 전체 구도(배치 확인) → 잠시 뒤 줌인 → 차례가 온 캐릭터를 화면 중심으로 따라감.
## 배경(1280×720) 밖이 보이지 않도록 중심을 제한. HUD 는 CanvasLayer 라 카메라 영향 없음.
const CAM_INTRO_HOLD := 1.1     # 전체 구도 유지 시간(초)
const CAM_INTRO_TIME := 0.9     # 줌인 시간
const CAM_MOVE_TIME := 0.55     # 캐릭터 간 이동 시간
const CAM_BATTLE_ZOOM := 1.4    # 전투 중 줌 배율
const CAM_SCREEN := Vector2(1280, 720)
const CAM_HUD_BOTTOM := 140.0   # 하단 명령 패널 높이: 그만큼 위쪽 영역의 중심에 캐릭터를 둔다

var bcam: Camera2D
var cam_ready := false
var _cam_tween: Tween


func _make_camera() -> void:
	bcam = Camera2D.new()
	bcam.name = "BattleCamera"
	bcam.position = CAM_SCREEN * 0.5
	world.add_child(bcam)
	bcam.make_current()


func _cam_center_for(point: Vector2, zoom: float) -> Vector2:
	var half := CAM_SCREEN * 0.5 / zoom
	return Vector2(clampf(point.x, half.x, CAM_SCREEN.x - half.x), clampf(point.y, half.y, CAM_SCREEN.y - half.y))


func _cam_to(center: Vector2, zoom: float, dur: float) -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	var target := _cam_center_for(center, zoom)
	if dur <= 0.0:
		bcam.zoom = Vector2.ONE * zoom
		bcam.position = target
		return
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(bcam, "zoom", Vector2.ONE * zoom, dur)
	_cam_tween.tween_property(bcam, "position", target, dur)


## 캐릭터 몸 중앙이 HUD 위쪽 영역의 가운데에 오도록 하는 카메라 중심 (월드 좌표)
func _focus_point(unit: UnitRuntime, zoom: float) -> Vector2:
	var s := sprite_of(unit)
	var feet := slot_position(unit.team, unit.row, unit.index) if s == null else s.position
	var body_h := 150.0 if s == null else (-s.head_screen_offset().y) * s.scale.y
	var body_mid := feet - Vector2(0, body_h * 0.5)
	return body_mid + Vector2(0, CAM_HUD_BOTTOM * 0.5 / zoom)


func focus_unit(unit: UnitRuntime, dur: float) -> void:
	if not cam_ready or unit == null:
		return
	_cam_to(_focus_point(unit, CAM_BATTLE_ZOOM), CAM_BATTLE_ZOOM, dur)


func _play_intro() -> void:
	cam_ready = false
	_cam_to(CAM_SCREEN * 0.5, 1.0, 0.0)
	# 스크린샷 자동화는 기본적으로 인트로를 건너뜀 (--intro=1 이면 재생, --intro=hold 면 전체 구도에서 멈춤)
	var mode: String = Game.cli.get("intro", "0" if Game.cli.has("shot") else "1")
	if mode == "hold":
		return
	if mode == "1":
		await get_tree().create_timer(CAM_INTRO_HOLD).timeout
		cam_ready = true
		focus_unit(controller.current, CAM_INTRO_TIME)
	else:
		cam_ready = true
		focus_unit(controller.current, 0.0)


## 전투 (재)시작 시 슬롯의 유닛으로 스프라이트 재생성
func _spawn_units() -> void:
	for c in units_root.get_children():
		c.queue_free()
	sprites.clear()
	for u in controller.slots.all_units():
		var s: UnitSprite2D = UNIT_SCRIPT.new()
		units_root.add_child(s)
		s.build(u, manifest)
		s.position = slot_position(u.team, u.row, u.index)
		s.scale = Vector2.ONE * slot_scale(u.team, u.row, u.index)
		s.clicked.connect(func(unit): unit_clicked.emit(unit))
		sprites[u.instance_id] = s
	_sort_units()
	apply_preset(preset)

func apply_preset(p: Dictionary) -> void:
	preset = p
	LightingPresets.apply_to_material(bg_mat, p)
	clear_rect.color = p.clear
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		var zone := zone_for_slot(s.unit.team, s.unit.row)
		s.apply_lighting(p, zone)
		# 빛 방향: 창문(좌) 영역은 왼쪽에서, 나머지는 문(우)에서
		s.set_light_direction(zone != "accent")


func _sort_units() -> void:
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		s.z_index = 10 + s.unit.index * 2


func sprite_of(unit: UnitRuntime) -> UnitSprite2D:
	return sprites.get(unit.instance_id, null)


func get_unit_screen_pos(unit: UnitRuntime) -> Vector2:
	var s := sprite_of(unit)
	if s == null:
		return Vector2.ZERO
	return world.get_global_transform_with_canvas() * (s.position + s.head_screen_offset() * s.scale.y)


func get_slot_screen_pos(key: String) -> Vector2:
	var info := SlotManager.parse_key(key)
	return world.get_global_transform_with_canvas() * slot_position(info.team, info.row, info.index)


func set_highlight(unit: UnitRuntime, kind: String) -> void:
	var s := sprite_of(unit)
	if s:
		s.set_highlight(kind)


func clear_highlights() -> void:
	for id in sprites:
		sprites[id].set_highlight("none")


func show_slot_markers(options: Array[Dictionary]) -> void:
	clear_slot_markers()
	for o in options:
		var info := SlotManager.parse_key(o.key)
		var m := SlotMarker2D.new()
		m.kind = o.kind
		m.key = o.key
		m.position = slot_position(info.team, info.row, info.index)
		m.scale = Vector2.ONE * slot_scale(info.team, info.row, info.index)
		m.clicked.connect(func(k): slot_clicked.emit(k))
		markers_root.add_child(m)
		_marker_nodes.append(m)


func clear_slot_markers() -> void:
	for m in _marker_nodes:
		m.queue_free()
	_marker_nodes.clear()


# ---------------------------------------------------------------- 컨트롤러 이벤트 → 연출
func _on_action_resolved(event: Dictionary) -> void:
	var actor: UnitRuntime = event.actor
	var s := sprite_of(actor)
	if s == null:
		return
	_begin_busy()
	var ranged: bool = actor.is_ranged_now() or event.action.kind == "ultimate"
	var tw := s.play_attack(actor.team == "ally", ranged)
	await get_tree().create_timer(0.12).timeout
	for r in event.results:
		var ts := sprite_of(r.target)
		if ts == null:
			continue
		if r.kind == "damage":
			ts.play_hit()
		else:
			ts.play_heal()
	if tw.is_valid():
		await tw.finished
	_end_busy()


func _on_unit_moved(unit: UnitRuntime, _from_key: String, _to_key: String) -> void:
	var s := sprite_of(unit)
	_begin_busy()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position", slot_position(unit.team, unit.row, unit.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(s, "scale", Vector2.ONE * slot_scale(unit.team, unit.row, unit.index), 0.35)
	await tw.finished
	_sort_units()
	apply_preset(preset)
	_end_busy()


func _on_units_swapped(a: UnitRuntime, b: UnitRuntime) -> void:
	var sa := sprite_of(a)
	var sb := sprite_of(b)
	_begin_busy()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sa, "position", slot_position(a.team, a.row, a.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sb, "position", slot_position(b.team, b.row, b.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sa, "scale", Vector2.ONE * slot_scale(a.team, a.row, a.index), 0.35)
	tw.tween_property(sb, "scale", Vector2.ONE * slot_scale(b.team, b.row, b.index), 0.35)
	await tw.finished
	_sort_units()
	apply_preset(preset)
	_end_busy()


func _on_weapon_changed(unit: UnitRuntime) -> void:
	var s := sprite_of(unit)
	if s:
		s.refresh_weapon()
		s.apply_lighting(preset, zone_for_slot(unit.team, unit.row))


func _on_unit_died(unit: UnitRuntime) -> void:
	var s := sprite_of(unit)
	if s:
		s.play_death()
