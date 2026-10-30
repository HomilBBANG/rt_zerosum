class_name BattleView2D
extends BattleViewBase
## 2D 캐릭터(원화 스프라이트) + 3D 배경 방(BattleView3D 를 SubViewport 로 렌더). 예전 2D 배경 판은 2026-10-27 제거.

const UNIT_SCRIPT := preload("res://scripts/presentation/unit_sprite_2d.gd")

@onready var world: Node2D = $World
@onready var units_root: Node2D = $World/Units
# ---------------------------------------------------------------- 카메라 (인스펙터에서 조절)
## battle_2d.tscn 의 View 노드를 선택하면 인스펙터에 보인다. 값을 바꾸면 캐릭터 위치·크기, 3D 배경, 조명이 그 구도로 다시 맞춰진다.
## 게임 실행 중에는 에디터 씬 트리의 "원격(Remote)" 탭 → View 를 골라 바꾸면 즉시 반영.
@export_group("카메라")
@export_range(10.0, 85.0, 0.5, "suffix:°") var cam_pitch_deg := 40.0:   ## 내려다보는 각도 (0 = 정면, 90 = 바로 위)
	set(v):
		cam_pitch_deg = v
		_camera_changed()
@export_range(5.0, 40.0, 0.1, "suffix:m") var cam_distance := 15.0:   ## 바라보는 점에서 카메라까지 거리 (클수록 작게 보임)
	set(v):
		cam_distance = v
		_camera_changed()
@export_range(10.0, 70.0, 0.5, "suffix:°") var cam_fov_deg := 32.0:   ## 세로 화각
	set(v):
		cam_fov_deg = v
		_camera_changed()
@export var cam_target := Vector3(0.0, 0.0, 0.6):   ## 카메라가 바라보는 바닥 위 점 (x 좌우, y 높이, z 앞뒤, m)
	set(v):
		cam_target = v
		_camera_changed()
@export var cam_screen_center := Vector2(640.0, 480.0):   ## 바라보는 점이 놓이는 화면 위치 (1280×720 기준 px) — y 를 키우면 구도가 위로
	set(v):
		cam_screen_center = v
		_camera_changed()
@export_group("행동 연출")
## 행동(스킬 · 공격): 카메라는 캐릭터가 아니라 **화면 가운데로 살짝 줌** + 행동한 캐릭터가 화면 가운데 쪽으로 나왔다가 → 행동 → 제자리로.
## 상황별 포즈 그림(shot · hit · miss · stun …)은 그동안 잠깐 바뀜 (그림이 있는 캐릭터만, tools/char_sprites.py poses)
@export_range(1.0, 2.0, 0.01) var pose_zoom := 1.12           ## 카메라 줌 배율 (화면 가운데 기준)
@export_range(0.02, 1.0, 0.01, "suffix:초") var pose_zoom_in := 0.22   ## 줌인 · 캐릭터가 가운데로 나오는 시간
@export_range(0.2, 5.0, 0.05, "suffix:초") var pose_time := 1.5        ## 포즈를 보여 주는 시간
@export_range(0.0, 1.0, 0.01, "suffix:초") var pose_back := 0.28       ## 원래 화면 · 제자리로 돌아오는 시간
@export_range(0.0, 400.0, 1.0, "suffix:px") var act_center_gap := 90.0   ## 가운데로 나온 캐릭터와 화면 가운데 사이 가로 거리 (자기 편 쪽으로, 0 = 정가운데)
@export var act_move := true   ## 행동한 캐릭터가 가운데로 나왔다가 돌아옴 (끄면 제자리에서)
@export_range(0.0, 1.0, 0.01, "suffix:초") var shake_time := 0.32      ## 공격이 명중했을 때 카메라 흔들림 시간
@export_range(0.0, 60.0, 0.5, "suffix:px") var shake_px := 16.0      ## 카메라 흔들림 세기 (처음 세기, 점점 약하게)
@export_group("")

var _cam_live := false


func pose_opts() -> Dictionary:
	return {"zoom": pose_zoom, "zoom_in": pose_zoom_in, "time": pose_time, "back": pose_back}


# ---------------------------------------------------------------- 포즈 카메라 (줌 · 흔들림)
## 카메라 자리·줌은 여기 값으로 _process 에서 (흔들림을 더해) bcam 에 넣음 → 3D 배경도 따라 다시 그림
var _cam_pos := Vector2(640, 360)
var _cam_zoom := 1.0
var _focus_tw: Tween
var _shake_left := 0.0


## 화면 가운데로 카메라 줌: zoom_in 초에 zoom 배 → time 초 유지 → back 초에 원래 화면. 캐릭터를 따라가지 않음 (s · at 은 예전 호출 호환용)
func focus_camera(_s: UnitSprite2D = null, o: Dictionary = {}, _at: Variant = null) -> void:
	if bcam == null:
		return
	var t_in := maxf(0.01, float(o.get("zoom_in", pose_zoom_in)))
	var t_hold := maxf(t_in, float(o.get("time", pose_time)))
	_zoom_camera(float(o.get("zoom", pose_zoom)), t_in, t_hold - t_in, float(o.get("back", pose_back)))


## 화면 가운데 줌: t_in 초에 k 배 → hold 초 유지 → t_back 초에 1배 (hold < 0 = 돌아가지 않고 그대로 — release_camera 로 돌아감)
func _zoom_camera(k: float, t_in: float, hold: float, t_back: float) -> void:
	if _focus_tw != null and _focus_tw.is_valid():
		_focus_tw.kill()
	_cam_pos = CAM_SCREEN * 0.5
	_focus_tw = create_tween()
	_focus_tw.tween_property(self, "_cam_zoom", k, t_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if hold < 0.0:
		return
	if hold > 0.0:
		_focus_tw.tween_interval(hold)
	release_camera(t_back, _focus_tw)


## 원래 화면(1배)으로 t 초에 (tw = 이어 붙일 트윈, 없으면 새로)
func release_camera(t: float = -1.0, tw: Tween = null) -> void:
	if t < 0.0:
		t = pose_back
	if tw == null:
		if _focus_tw != null and _focus_tw.is_valid():
			_focus_tw.kill()
		_focus_tw = create_tween()
		tw = _focus_tw
	if t > 0.0:
		tw.tween_property(self, "_cam_zoom", 1.0, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		tw.tween_property(self, "_cam_zoom", 1.0, 0.0)


## 행동 시작: 화면 가운데로 살짝 줌 + 행동한 캐릭터가 화면 가운데 쪽(자기 편 쪽으로 act_center_gap)으로 나옴 → 나오는 초
func _stage_in(s: UnitSprite2D) -> float:
	_zoom_camera(pose_zoom, pose_zoom_in, -1.0, 0.0)
	if not act_move:
		return pose_zoom_in
	var side := -1.0 if s.unit.team == "ally" else 1.0
	var to := Vector2(CAM_SCREEN.x * 0.5 + side * act_center_gap, s.position.y)
	if side * (to.x - s.position.x) > 0.0:   # 이미 가운데보다 안쪽이면 그대로
		to.x = s.position.x
	var tw := create_tween()
	tw.tween_property(s, "position", to, pose_zoom_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return pose_zoom_in


## 행동 끝: 제자리(지금 슬롯 자리)로 돌아가고 카메라도 원래 화면 → 돌아오는 초
func _stage_out(s: UnitSprite2D) -> float:
	release_camera(pose_back)
	if act_move and s.unit != null:
		var tw := create_tween()
		tw.tween_property(s, "position", unit_position(s.unit), pose_back).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return pose_back


## 카메라 흔들림 (처음 shake_time 초, 점점 약하게) — 줌과 함께 써도 됨
func shake_camera() -> void:
	if bcam == null or shake_time <= 0.0 or shake_px <= 0.0:
		return
	_shake_left = shake_time


func _apply_camera(delta: float) -> void:
	if bcam == null:
		return
	var off := Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var a := shake_px * (_shake_left / maxf(0.01, shake_time)) / _cam_zoom
		off = Vector2(randf_range(-a, a), randf_range(-a, a))
	bcam.zoom = Vector2.ONE * _cam_zoom
	bcam.position = _cam_pos + off


## 포즈 + 카메라 줌 (focus = 화면 가운데로 살짝 줌) → 포즈 초
func _pose(s: UnitSprite2D, pose: String, focus: bool, at: Variant = null) -> float:
	if s == null or pose == "" or not s.has_pose(pose):
		return 0.0
	var t := s.play_pose(pose, pose_opts())
	if focus and t > 0.0:
		focus_camera(s, pose_opts(), at)
	return t + (pose_back if focus else 0.0)


## 매니페스트 카메라(슬롯 배치·스프라이트 기준 키) + 인스펙터 값
func _camera_dict() -> Dictionary:
	var c: Dictionary = manifest.get("camera", {}).duplicate(true)
	c.pitch_deg = cam_pitch_deg
	c.dist = cam_distance
	c.vfov_deg = cam_fov_deg
	c.target = [cam_target.x, cam_target.y, cam_target.z]
	c.cx = cam_screen_center.x
	c.cy = cam_screen_center.y
	return c


func _camera_changed() -> void:
	if not _cam_live:
		return
	set_camera(_camera_dict())
	if bg3d != null:
		bg3d.configure_as_background(cam)
		bg3d.set_view(cam, bcam.position, bcam.zoom.x)
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		s.position = unit_position(s.unit)
		s.scale = Vector2.ONE * unit_scale(s.unit)
	relight()
	_rerender_bg()


var back_bars: Node2D   # 발밑 체력 칸 층: 캐릭터·하이라이트 링보다 위 (월드 안 제일 위)
@onready var markers_root: Node2D = $World/Markers
@onready var clear_rect: ColorRect = $Clear

var manifest: Dictionary = {}
var sprites: Dictionary = {}   # instance_id -> UnitSprite2D
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
	return _scale_at(slot_world(team, row, index))


static func _scale_at(w: Vector3) -> float:
	var v := w - _C
	var px := _focal * float(cam.get("unit_height_m", 1.75)) / v.dot(_F)
	return px / float(cam.get("sprite_px", 230.0))


## 유닛이 서는 월드 위치: 두 칸(전방+중앙) 큰 몸집은 차지한 칸들의 가운데
static func unit_world(u: UnitRuntime) -> Vector3:
	var w := Vector3.ZERO
	for r in range(u.row, u.row + u.data.row_span):
		w += slot_world(u.team, r, u.index)
	return w / float(u.data.row_span)


static func unit_position(u: UnitRuntime) -> Vector2:
	return project(unit_world(u))


static func unit_scale(u: UnitRuntime) -> float:
	return _scale_at(unit_world(u))


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
	skill_poses = SkillPoseData.read()
	weapon_poses = SkillPoseData.read_weapons()
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	set_camera(_camera_dict())
	_make_3d_background()
	_make_camera()
	back_bars = Node2D.new()
	back_bars.name = "BackBars"
	back_bars.z_index = 100   # 캐릭터·하이라이트 링보다 위 (제일 위)
	world.add_child(back_bars)
	back_bars.draw.connect(_draw_back_bars)
	_cam_live = true


func setup(p_controller: BattleController, p_preset: Dictionary) -> void:
	super.setup(p_controller, p_preset)
	controller.battle_started.connect(_spawn_units)
	controller.battle_started.connect(_play_intro)
	controller.unit_died.connect(func(_u): relight())   # 쓰러진 캐릭터의 바닥 그림자 제거
	if not controller.slots.all_units().is_empty():
		_spawn_units()
	controller.action_resolved.connect(_on_action_resolved)
	controller.status_ticked.connect(_on_status_ticked)
	controller.unit_moved.connect(_on_unit_moved)
	controller.units_swapped.connect(_on_units_swapped)
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.unit_died.connect(_on_unit_died)


# ---------------------------------------------------------------- 전투 카메라
## 전투 내내 전체 구도 고정 (차례 캐릭터 줌인은 적 선택을 가려서 제거, 2026-10-25).
## Camera2D 는 3D 배경이 2D 카메라를 따라 그리도록 남겨 둔다 (_process → set_view).
const CAM_SCREEN := Vector2(1280, 720)

var bcam: Camera2D


func _make_camera() -> void:
	bcam = Camera2D.new()
	bcam.name = "BattleCamera"
	bcam.position = CAM_SCREEN * 0.5
	world.add_child(bcam)
	bcam.make_current()


func _play_intro() -> void:
	bcam.zoom = Vector2.ONE
	bcam.position = CAM_SCREEN * 0.5
	_cam_pos = CAM_SCREEN * 0.5
	_cam_zoom = 1.0


## 전투 (재)시작 시 슬롯의 유닛으로 스프라이트 재생성
func _spawn_units() -> void:
	for c in units_root.get_children():
		c.queue_free()
	sprites.clear()
	for u in controller.slots.all_units():
		var s: UnitSprite2D = UNIT_SCRIPT.new()
		units_root.add_child(s)
		s.build(u, manifest)
		s.position = unit_position(u)
		s.scale = Vector2.ONE * unit_scale(u)
		s.clicked.connect(func(unit): unit_clicked.emit(unit))
		sprites[u.instance_id] = s
	_sort_units()
	apply_preset(preset)
	relight()

func apply_preset(p: Dictionary) -> void:
	preset = p
	clear_rect.color = p.clear
	if bg3d != null:
		bg3d.apply_preset(p)
		relight()
		return
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		var zone := zone_for_slot(s.unit.team, s.unit.row)
		s.apply_lighting(p, zone)
		# 빛 방향: 창문(좌) 영역은 왼쪽에서, 나머지는 문(우)에서
		s.set_light_direction(zone != "accent")


# ---------------------------------------------------------------- 3D 배경 (하이브리드)
## 배경은 3D 방(실제 스폿라이트·하드 섀도우)을 2D 가상 카메라와 같은 투영으로 렌더해 텍스처로 깔고,
## 2D 캐릭터는 자기 위치에 실제로 닿는 빛(원뿔·개구부 통과)으로 명암·림 색과 방향을 정한다.
const BG3D_SCRIPT := preload("res://scripts/presentation/battle_view_3d.gd")
const BG_RENDER_SIZE := Vector2i(2560, 1440)   # QHD. 카메라를 따라 다시 그리므로 줌해도 흐려지지 않음

var bg_vp: SubViewport
var bg3d: Node   # BattleView3D (배경 모드)


func _make_3d_background() -> void:
	bg_vp = SubViewport.new()
	bg_vp.name = "Background3D"
	bg_vp.size = BG_RENDER_SIZE
	bg_vp.own_world_3d = true
	bg_vp.msaa_3d = Viewport.MSAA_4X
	bg_vp.positional_shadow_atlas_size = 4096
	# 그림자 드리우는 스폿은 2개(문·창)뿐 → 사분면 하나씩 통째로 (광원당 2048², 발밑 그림자 계단 줄임)
	bg_vp.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	bg_vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(bg_vp)
	bg3d = Node3D.new()
	bg3d.set_script(BG3D_SCRIPT)
	bg_vp.add_child(bg3d)
	bg3d.configure_as_background(cam)
	# 배경은 화면 공간(카메라 영향 없음)에 화면 크기로 깔고, 3D 카메라가 2D 카메라의 위치·줌을 그대로 따라가 다시 그린다
	clear_rect.visible = false   # 화면 공간 3D 배경(레이어 -1)을 덮지 않게
	var layer := CanvasLayer.new()
	layer.name = "BackgroundLayer"
	layer.layer = -1
	add_child(layer)
	var tr := TextureRect.new()
	# 확장 모드를 먼저 지정해야 텍스처(2560×1440) 크기로 커지지 않고 화면(1280×720 논리)에 맞춰 늘어남
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = bg_vp.get_texture()
	tr.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tr.position = Vector2.ZERO
	tr.size = CAM_SCREEN
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)


func _rerender_bg() -> void:
	if bg_vp != null:
		bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


var _last_view := Vector3(-1, -1, -1)


var _shadow_poses: Dictionary = {}   # 유닛 id → 그림자에 쓴 포즈


## 포즈 그림이 바뀐 유닛만 그림자 판을 바꾸고 배경을 다시 그림
func _sync_shadow_poses() -> void:
	if bg3d == null:
		return
	var changed := false
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		var sp := s.shadow_pose()
		if str(_shadow_poses.get(id, "")) == sp:
			continue
		_shadow_poses[id] = sp
		var u: UnitRuntime = s.unit
		bg3d.set_shadow_proxy(id, unit_world(u), 1.75 * (u.data.height_cm / 175.0), u.alive or sp != "", u.data.sprite_id, s.is_mirrored(), sp)
		changed = true
	if changed:
		_rerender_bg()


func _process(delta: float) -> void:
	if back_bars != null:
		back_bars.queue_redraw()   # 이동 트윈·피해 반영
	_apply_camera(delta)
	_sync_shadow_poses()
	# 2D 카메라가 움직이거나 줌이 바뀌면 3D 배경 카메라를 맞추고 다시 렌더
	if bg3d == null or bcam == null:
		return
	var v := Vector3(bcam.position.x, bcam.position.y, bcam.zoom.x)
	if v.is_equal_approx(_last_view):
		return
	_last_view = v
	bg3d.set_view(cam, bcam.position, bcam.zoom.x)
	_rerender_bg()


## 모든 유닛의 조명을 3D 광원 기준으로 다시 계산 + 그림자 대리 물체 갱신 + 배경 재렌더
func relight() -> void:
	if bg3d == null:
		return
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		var u: UnitRuntime = s.unit
		var w := unit_world(u)
		var h := 1.75 * (u.data.height_cm / 175.0)
		var sp := s.shadow_pose()
		_shadow_poses[id] = sp
		bg3d.set_shadow_proxy(id, w, h, u.alive or sp != "", u.data.sprite_id, s.is_mirrored(), sp)   # 쓰러진 그림(dead)이 있으면 그림자도 남음
		var probes: Array = bg3d.light_probe(w, h)
		var key: Dictionary = probes[0] if not probes.is_empty() and probes[0].intensity > 0.3 else {}
		var rim: Dictionary = {}
		if not key.is_empty():
			for pr in probes.slice(1):
				if pr.from_right != key.from_right and pr.intensity > 0.3:
					rim = pr
					break
		s.apply_light_probe(preset, key, rim)
	_rerender_bg()


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


## 발밑 체력 칸: 월드 안에서 제일 위 층에 그려 하이라이트 링·캐릭터에 가리지 않는다.
func draws_back_bars() -> bool:
	return true


## 발밑 체력·AP 칸: 외곽선 없는 짧은 평행사변형 여러 개.
## 체력(붉은색) = 아군 3칸 / 적 10칸, 체력 비율만큼 차고 걸친 칸은 일부만 참.
## AP(파란색) = 체력 바로 아래, 최대 AP 수만큼 칸, 현재 AP 만큼 참.
const HP_SEGMENTS_ALLY := 3
const HP_SEGMENTS_ENEMY := 10
const HP_COLOR := Color(0.95, 0.16, 0.14)
const HP_EMPTY := Color(0.25, 0.04, 0.04, 0.7)
const AP_COLOR := Color(0.25, 0.6, 1.0)
const AP_EMPTY := Color(0.04, 0.1, 0.25, 0.7)


func _draw_back_bars() -> void:
	for id in sprites:
		var s: UnitSprite2D = sprites[id]
		var u: UnitRuntime = s.unit
		var k := s.scale.y
		var a := 1.0 if u.alive else 0.35
		var h := maxf(6.0, 8.0 * k)
		var y := s.position.y + 17.0 * k
		var n := HP_SEGMENTS_ALLY if u.team == "ally" else HP_SEGMENTS_ENEMY
		var hp_frac := clampf(float(u.hp) / float(maxi(u.data.max_hp, 1)), 0.0, 1.0)
		_draw_segments(s.position.x, y, n, (15.0 if n <= 3 else 8.0) * k, h, 3.0 * k, hp_frac * n, HP_COLOR, HP_EMPTY, a)
		if u.alive:
			var ah := maxf(4.0, 5.0 * k)
			_draw_segments(s.position.x, y + h + 3.0 * k, u.data.max_ap, 7.0 * k, ah, 2.5 * k, float(u.ap), AP_COLOR, AP_EMPTY, a)
			var head := s.position + s.head_screen_offset() * s.scale.y
			_draw_status_badges(u, head.x, head.y - 30.0 * k, k)


## 머리 위 전투 상태 이상 배지: 한 글자 + 남은 턴 (출혈 = 혈2, 동상은 터지기까지 남은 차례)
var _badge_font: Font
func _draw_status_badges(u: UnitRuntime, cx: float, y: float, k: float) -> void:
	var list := u.statuses.filter(func(sid): return StatusCatalog.get_def(sid).get("battle", false))
	if list.is_empty():
		return
	if _badge_font == null:
		_badge_font = load("res://assets/fonts/Pretendard-Bold.ttf")
	var fs := maxi(12, roundi(15.0 * k))
	var w := 34.0 * k
	var hgt := 21.0 * k
	var gap := 4.0 * k
	var x0 := cx - (list.size() * w + (list.size() - 1) * gap) * 0.5
	for i in list.size():
		var sid: String = list[i]
		var col := StatusCatalog.color_of(sid)
		var r := Rect2(x0 + i * (w + gap), y, w, hgt)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.darkened(0.55), 0.92)
		sb.border_color = col
		sb.set_border_width_all(maxi(1, roundi(1.5 * k)))
		sb.set_corner_radius_all(roundi(4 * k))
		back_bars.draw_style_box(sb, r)
		var t := "%s%d" % [StatusCatalog.get_def(sid).get("short", "?"), u.status_turns(sid)]
		back_bars.draw_string(_badge_font, Vector2(r.position.x, r.position.y + hgt * 0.5 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color.WHITE)


## 가운데 cx 에 n 칸, filled 칸만큼 채움 (소수면 마지막 칸 일부)
func _draw_segments(cx: float, y: float, n: int, seg_w: float, h: float, gap: float, filled: float, col: Color, empty: Color, a: float) -> void:
	var skew := h * 0.6   # 윗변을 오른쪽으로 밀어 기울임
	var total := n * seg_w + (n - 1) * gap + skew
	var x0 := cx - total * 0.5
	for i in n:
		var x := x0 + i * (seg_w + gap)
		back_bars.draw_colored_polygon(_para(x, y, seg_w, h, skew), Color(empty, empty.a * a))
		var f := clampf(filled - i, 0.0, 1.0)
		if f > 0.0:
			back_bars.draw_colored_polygon(_para(x, y, seg_w * f, h, skew), Color(col, a))


## 아래변 왼쪽이 (x, y+h) 인 평행사변형
func _para(x: float, y: float, w: float, h: float, skew: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x + skew, y), Vector2(x + skew + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


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
## 스킬마다 쓰는 포즈 (data/skill_poses.json — 에디터 '스킬 트리' 탭 → '스킬 포즈'). 규칙은 SkillPoseData
var skill_poses: Dictionary = {}
var weapon_poses: Dictionary = {}   # 캐릭터 · 무기별 공격 포즈 (같은 파일 "weapons")


## 후보 중 그 캐릭터에게 그림이 있는 첫 포즈 ("" = 없음)
func _pick_pose(s: UnitSprite2D, cands: Array) -> String:
	for p in cands:
		if s.has_pose(str(p)):
			return str(p)
	return ""


func _on_action_resolved(event: Dictionary) -> void:
	var actor: UnitRuntime = event.actor
	var s := sprite_of(actor)
	if s == null:
		return
	_begin_busy()
	# 화면 가운데로 살짝 줌 + 행동한 캐릭터가 가운데 쪽으로 나옴 (끝나면 제자리로)
	await get_tree().create_timer(_stage_in(s)).timeout
	var ranged: bool = actor.is_ranged_now() or event.action.kind == "ultimate"
	var start := Time.get_ticks_msec()
	var until := 0.0   # 시작부터 포즈가 끝나는 초
	var shook := false
	var tw: Tween = null
	# 쓰는 쪽: 스킬 포즈 (자동 = 적에게 쓰는 피해·상태 스킬 shot — 근접 무기면 slash, 그 밖 point_up) — 그림이 없으면 공격 애니메이션
	var tgt: Variant = (event.targets as Array)[0] if not (event.targets as Array).is_empty() else null
	var cp := _pick_pose(s, SkillPoseData.caster_poses(event.action, actor, tgt, skill_poses, weapon_poses))
	if cp != "":
		until = _pose(s, cp, false)   # 카메라는 _stage_in 에서 이미 화면 가운데로 줌
	else:
		tw = s.play_attack(actor.team == "ally", ranged)
	await get_tree().create_timer(0.12).timeout
	# 맞는 쪽: 이번에 걸린 상태 효과 (대상마다)
	var effs := {}
	for ap in event.get("applied", []):
		effs.get_or_add(ap.target.instance_id, []).append(StatusCatalog.effect_of(str(ap.status)))
	var posed := {}
	for r in event.results:
		var ts := sprite_of(r.target)
		if ts == null:
			continue
		var id: int = r.target.instance_id
		var pose := ""
		if not posed.has(id) and r.target.alive and r.kind in ["damage", "miss"]:
			pose = _pick_pose(ts, SkillPoseData.target_poses(r.kind, effs.get(id, [])))
		if r.kind == "damage" and not shook:   # 명중 → 카메라 흔들림 (한 행동에 한 번)
			shake_camera()
			shook = true
		if pose != "":
			posed[id] = true
			until = maxf(until, 0.12 + _pose(ts, pose, false))
		elif r.kind == "damage":
			ts.play_hit()
		elif r.kind == "miss":
			ts.play_dodge()
		else:
			ts.play_heal()
	# 피해 없이 상태만 걸린 대상 (기절 → stun, 디버프 → tired)
	for id in effs:
		var ts2: UnitSprite2D = sprites.get(id, null)
		if ts2 == null or posed.has(id) or not ts2.unit.alive or (id == actor.instance_id and cp != ""):
			continue
		var p2 := _pick_pose(ts2, SkillPoseData.target_poses("", effs[id]))
		if p2 != "":
			posed[id] = true
			until = maxf(until, 0.12 + _pose(ts2, p2, false))
	if tw != null and tw.is_valid():
		await tw.finished
	var left := until - (Time.get_ticks_msec() - start) / 1000.0
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	await get_tree().create_timer(_stage_out(s)).timeout
	# 탈진: AP 를 다 쓰면 그다음 tired
	if actor.alive and actor.ap <= 0 and s.has_pose("tired"):
		await get_tree().create_timer(_pose(s, "tired", true)).timeout
	_end_busy()


## 차례 시작 상태 이상 피해 → 맞는 연출
func _on_status_ticked(event: Dictionary) -> void:
	for r in event.results:
		var ts := sprite_of(r.target)
		if ts != null:
			ts.play_hit()


func _on_unit_moved(unit: UnitRuntime, _from_key: String, _to_key: String) -> void:
	var s := sprite_of(unit)
	_begin_busy()
	s.play_move_steps()
	_pose(s, "move", true, unit_position(unit) + Vector2(0.0, -s.chr_height * 0.5 * unit_scale(unit)))   # 자리 이동 포즈 (그림이 있으면, 도착할 자리로 줌, 기다리지 않음)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position", unit_position(unit), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(s, "scale", Vector2.ONE * unit_scale(unit), 0.35)
	await tw.finished
	_sort_units()
	apply_preset(preset)
	relight()
	_end_busy()


func _on_units_swapped(a: UnitRuntime, b: UnitRuntime) -> void:
	var sa := sprite_of(a)
	var sb := sprite_of(b)
	_begin_busy()
	sa.play_move_steps()
	sb.play_move_steps(0.09)   # 두 사람 발소리가 겹치지 않게 살짝 늦게
	_pose(sa, "move", true, unit_position(a) + Vector2(0.0, -sa.chr_height * 0.5 * unit_scale(a)))   # 자리를 바꾸자고 한 쪽만 (그림이 있으면, 기다리지 않음)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sa, "position", unit_position(a), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sb, "position", unit_position(b), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sa, "scale", Vector2.ONE * unit_scale(a), 0.35)
	tw.tween_property(sb, "scale", Vector2.ONE * unit_scale(b), 0.35)
	await tw.finished
	_sort_units()
	apply_preset(preset)
	relight()
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
