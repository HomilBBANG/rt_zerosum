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


static func slot_position(team: String, row: int, index: int) -> Vector2:
	# 횡스크롤: 아군 좌측(후방→전방 = 왼쪽→오른쪽), 적 우측. index 1 이 카메라에 더 가깝다(아래쪽).
	var x: float
	if team == "ally":
		x = 470.0 - row * 150.0
	else:
		x = 810.0 + row * 150.0
	var y := 566.0 + index * 82.0
	x += (-34.0 if team == "ally" else 34.0) * index
	return Vector2(x, y)


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
	world.position.y = -96.0  # 하단 HUD 에 전열이 가리지 않도록 전장을 위로
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = ZONE_SHADER
	bg_mat.set_shader_parameter("zone_mask", load("res://assets/textures/bg_barracks_mask.png"))
	bg.material = bg_mat


func setup(p_controller: BattleController, p_preset: Dictionary) -> void:
	super.setup(p_controller, p_preset)
	controller.battle_started.connect(_spawn_units)
	if not controller.slots.all_units().is_empty():
		_spawn_units()
	controller.action_resolved.connect(_on_action_resolved)
	controller.unit_moved.connect(_on_unit_moved)
	controller.units_swapped.connect(_on_units_swapped)
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.unit_died.connect(_on_unit_died)


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
	return world.get_global_transform_with_canvas() * (s.position + s.head_screen_offset())


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
	tw.tween_property(s, "position", slot_position(unit.team, unit.row, unit.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
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
