class_name BattleView3D
extends BattleViewBase
## 경로 B 의 3D 해석: 실제 색광원(SpotLight3D) + 셀 셰이더 단계 분할 + 하드 섀도우.
## 문/창문 개구부를 통과한 빛이 바닥에 '딱딱한 다각형' 광면을 만든다.

const CEL := preload("res://shaders/cel_3d.gdshader")
const OUTLINE := preload("res://shaders/outline_3d.gdshader")
const UNLIT := preload("res://shaders/unlit_3d.gdshader")
const MODEL := preload("res://scripts/presentation/unit_model_3d.gd")

var camera: Camera3D
var env: WorldEnvironment
var key_light: SpotLight3D
var key_light2: SpotLight3D
var accent_light: SpotLight3D
var accent_light2: SpotLight3D
var fill_light: DirectionalLight3D
var room: Node3D
var units_root: Node3D
var markers_root: Node3D
var models: Dictionary = {}
var room_mats: Array[ShaderMaterial] = []
var exterior_key: ShaderMaterial
var exterior_accent: ShaderMaterial
var _markers: Array[Node3D] = []


static func slot_position(team: String, row: int, index: int) -> Vector3:
	var x: float
	if team == "ally":
		x = -1.3 - row * 1.7
	else:
		x = 1.3 + row * 1.7
	var z := 0.1 + index * 1.15
	x += (-0.35 if team == "ally" else 0.35) * index
	return Vector3(x, 0.0, z)


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(0.0, 3.7, 11.6)
	camera.near = 0.2
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.6), Vector3.UP)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.06, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.glow_enabled = false
	env.environment = e
	add_child(env)
	room = Node3D.new()
	add_child(room)
	_build_room()
	_build_lights()
	units_root = Node3D.new()
	add_child(units_root)
	markers_root = Node3D.new()
	add_child(markers_root)


func _room_mat(color: Color, outline_mode: int = 1, outline_w: float = 0.02) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CEL
	m.set_shader_parameter("albedo", color)
	if outline_w > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("mode", outline_mode)
		o.set_shader_parameter("width", outline_w)
		m.next_pass = o
	room_mats.append(m)
	return m


func _box_at(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	(parent if parent else room).add_child(mi)
	return mi


func _build_room() -> void:
	var wall := _room_mat(Color(0.80, 0.77, 0.72), 1, 0.0)
	var floor_m := _room_mat(Color(0.72, 0.69, 0.63), 1, 0.0)
	var frame := _room_mat(Color(0.37, 0.34, 0.31))
	var prop := _room_mat(Color(0.56, 0.53, 0.50))
	var wood := _room_mat(Color(0.49, 0.42, 0.34))
	var crate := _room_mat(Color(0.63, 0.55, 0.45))
	var WZ := -3.4
	# 바닥 (평면) + 바닥 널빤지 선은 셀 스타일상 생략
	_box_at(Vector3(24, 0.2, 14), Vector3(0, -0.1, 1.0), floor_m)
	# 뒷벽: 창(x -4.6..-2.6, y 1.5..3.1), 문(x 3.4..4.8, y 0..3.2) 개구부를 남기고 분할
	var H := 5.2
	_box_at(Vector3(7.4, H, 0.3), Vector3(-8.3, H / 2, WZ), wall)        # -12 .. -4.6
	_box_at(Vector3(2.0, 1.5, 0.3), Vector3(-3.6, 0.75, WZ), wall)       # 창 아래
	_box_at(Vector3(2.0, H - 3.1, 0.3), Vector3(-3.6, 3.1 + (H - 3.1) / 2, WZ), wall)  # 창 위
	_box_at(Vector3(6.0, H, 0.3), Vector3(0.4, H / 2, WZ), wall)          # -2.6 .. 3.4
	_box_at(Vector3(1.4, H - 3.2, 0.3), Vector3(4.1, 3.2 + (H - 3.2) / 2, WZ), wall)  # 문 위
	_box_at(Vector3(7.2, H, 0.3), Vector3(8.4, H / 2, WZ), wall)          # 4.8 .. 12
	# 벽 패널 선: 외곽선 스타일 박스 (얇은 띠, 벽과 같은 색 → 외곽선만 보임)
	for y in [1.0, 2.0, 3.0, 4.0]:
		_box_at(Vector3(24, 0.05, 0.03), Vector3(0, y, WZ + 0.16), _room_mat(Color(0.80, 0.77, 0.72), 1, 0.012))
	# 천장 파이프
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.07
	pipe.bottom_radius = 0.07
	pipe.height = 24
	var pmi := MeshInstance3D.new()
	pmi.mesh = pipe
	pmi.material_override = _room_mat(Color(0.5, 0.47, 0.43))
	pmi.position = Vector3(0, 4.7, WZ + 0.5)
	pmi.rotation_degrees = Vector3(0, 0, 90)
	room.add_child(pmi)
	# 창틀
	_box_at(Vector3(2.3, 0.12, 0.2), Vector3(-3.6, 1.5, WZ), frame)
	_box_at(Vector3(2.3, 0.12, 0.2), Vector3(-3.6, 3.1, WZ), frame)
	_box_at(Vector3(0.12, 1.7, 0.2), Vector3(-4.6, 2.3, WZ), frame)
	_box_at(Vector3(0.12, 1.7, 0.2), Vector3(-2.6, 2.3, WZ), frame)
	_box_at(Vector3(0.08, 1.6, 0.08), Vector3(-3.6, 2.3, WZ), frame)
	_box_at(Vector3(2.0, 0.08, 0.08), Vector3(-3.6, 2.3, WZ), frame)
	# 문틀 + 반쯤 열린 문짝
	_box_at(Vector3(0.14, 3.3, 0.24), Vector3(3.4, 1.65, WZ), frame)
	_box_at(Vector3(0.14, 3.3, 0.24), Vector3(4.8, 1.65, WZ), frame)
	_box_at(Vector3(1.6, 0.14, 0.24), Vector3(4.1, 3.25, WZ), frame)
	var door := _box_at(Vector3(1.3, 3.1, 0.08), Vector3(3.4 + 0.62 * cos(deg_to_rad(55)), 1.55, WZ + 0.62 * sin(deg_to_rad(55))), _room_mat(Color(0.52, 0.45, 0.40)))
	door.rotation_degrees = Vector3(0, -55, 0)
	# 바깥: 문/창 너머 발광 면 (빛의 '출처' 를 보여줌)
	exterior_key = ShaderMaterial.new()
	exterior_key.shader = UNLIT
	exterior_key.set_shader_parameter("tint", Color(1.0, 0.12, 0.47))
	exterior_key.set_shader_parameter("dim", 1.0)
	var ext := _box_at(Vector3(6.0, 6.0, 0.1), Vector3(4.6, 2.0, WZ - 2.6), exterior_key)
	ext.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exterior_accent = ShaderMaterial.new()
	exterior_accent.shader = UNLIT
	exterior_accent.set_shader_parameter("tint", Color(0.22, 1.0, 0.73))
	exterior_accent.set_shader_parameter("dim", 1.0)
	var ext2 := _box_at(Vector3(5.0, 5.0, 0.1), Vector3(-3.6, 2.4, WZ - 2.0), exterior_accent)
	ext2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 소품: 사물함 2, 상자, 탁자, 게시판, 기둥
	for x in [-1.75, -1.1]:
		_box_at(Vector3(0.6, 2.3, 0.5), Vector3(x, 1.15, WZ + 0.42), prop)
	_box_at(Vector3(1.2, 1.0, 1.0), Vector3(-4.2, 0.5, WZ + 0.8), crate)
	_box_at(Vector3(0.8, 0.7, 0.8), Vector3(-4.1, 1.35, WZ + 0.8), crate)
	_box_at(Vector3(2.4, 0.1, 1.0), Vector3(1.6, 0.9, WZ + 0.9), wood)
	for dx in [-1.1, 1.1]:
		for dz in [-0.4, 0.4]:
			_box_at(Vector3(0.1, 0.9, 0.1), Vector3(1.6 + dx, 0.45, WZ + 0.9 + dz), wood)
	_box_at(Vector3(0.5, 0.2, 0.3), Vector3(1.5, 1.05, WZ + 0.9), _room_mat(Color(0.37, 0.5, 0.52)))
	_box_at(Vector3(1.8, 1.3, 0.08), Vector3(1.4, 2.6, WZ + 0.18), _room_mat(Color(0.48, 0.42, 0.35)))
	_box_at(Vector3(1.5, 1.0, 0.04), Vector3(1.4, 2.6, WZ + 0.24), _room_mat(Color(0.85, 0.81, 0.75), 1, 0.0))
	_box_at(Vector3(0.5, 5.2, 0.5), Vector3(6.3, 2.6, WZ + 0.3), wall)


func _build_lights() -> void:
	# 키: 문 밖 스폿(문 모양 광면) + 우측 상단 홍수광(적 진영 색 공간)
	key_light = _spot(Vector3(4.2, 2.6, -4.6), Vector3(0.6, 0.0, 5.5), 80.0, 5.0)
	# 홍수광: 캐릭터 전용(컬 마스크 레이어 2) — 바닥/벽과의 가산 누적 없이 캐릭터 정면을 색광으로 칠한다
	key_light2 = _spot(Vector3(7.4, 4.6, 6.4), Vector3(2.4, 0.9, 0.6), 42.0, 3.4)
	key_light2.light_cull_mask = 1 << 1
	# 보조: 창 밖 스폿(창 모양 광면) + 좌측 상단 홍수광(아군 진영 색 공간)
	accent_light = _spot(Vector3(-3.6, 3.4, -4.4), Vector3(-4.2, 0.0, 4.0), 56.0, 4.5)
	accent_light2 = _spot(Vector3(-7.4, 4.6, 6.4), Vector3(-2.6, 0.9, 0.6), 42.0, 3.4)
	accent_light2.light_cull_mask = 1 << 1
	# 채움: 카메라 쪽 위에서 오는 약한 방향광 → '주변광 구역', 가려진 곳은 '그림자 구역'
	fill_light = DirectionalLight3D.new()
	fill_light.light_energy = 0.5
	fill_light.shadow_enabled = true
	fill_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	fill_light.directional_shadow_max_distance = 40.0
	fill_light.shadow_bias = 0.05
	fill_light.shadow_normal_bias = 1.5
	add_child(fill_light)
	fill_light.rotation_degrees = Vector3(-52.0, 18.0, 0.0)


func _spot(pos: Vector3, target: Vector3, angle: float, energy: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.spot_range = 26.0
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.3
	l.spot_attenuation = 0.4
	l.light_energy = energy
	l.shadow_enabled = true
	l.shadow_bias = 0.06
	l.shadow_normal_bias = 1.6
	add_child(l)
	l.look_at(target, Vector3.UP)
	return l


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


## 전투 (재)시작 시 슬롯의 유닛으로 모델 재생성
func _spawn_units() -> void:
	for c in units_root.get_children():
		c.queue_free()
	models.clear()
	for u in controller.slots.all_units():
		var m: UnitModel3D = MODEL.new()
		units_root.add_child(m)
		m.build(u)
		m.position = slot_position(u.team, u.row, u.index)
		models[u.instance_id] = m
	apply_preset(preset)

func apply_preset(p: Dictionary) -> void:
	preset = p
	env.environment.background_color = p.clear
	key_light.light_color = p.key
	key_light2.light_color = p.key
	accent_light.light_color = p.accent
	accent_light2.light_color = p.accent
	fill_light.light_color = p.ambient
	exterior_key.set_shader_parameter("tint", p.key)
	exterior_accent.set_shader_parameter("tint", p.accent)
	for m in room_mats:
		m.set_shader_parameter("shadow_tint", p.shadow)
		m.set_shader_parameter("ambient_tint", p.ambient)
		m.set_shader_parameter("light_mix", p.key_mix)
	for id in models:
		models[id].apply_lighting(p)


func model_of(unit: UnitRuntime) -> UnitModel3D:
	return models.get(unit.instance_id, null)


func get_unit_screen_pos(unit: UnitRuntime) -> Vector2:
	var m := model_of(unit)
	if m == null:
		return Vector2.ZERO
	return camera.unproject_position(m.global_position + Vector3(0, m.head_height + 0.05, 0))


func get_slot_screen_pos(key: String) -> Vector2:
	var info := SlotManager.parse_key(key)
	return camera.unproject_position(slot_position(info.team, info.row, info.index))


func set_highlight(unit: UnitRuntime, kind: String) -> void:
	var m := model_of(unit)
	if m:
		m.set_highlight(kind)


func clear_highlights() -> void:
	for id in models:
		models[id].set_highlight("none")


func show_slot_markers(options: Array[Dictionary]) -> void:
	clear_slot_markers()
	for o in options:
		var info := SlotManager.parse_key(o.key)
		var n := Node3D.new()
		n.position = slot_position(info.team, info.row, info.index)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.04
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		var mat := ShaderMaterial.new()
		mat.shader = UNLIT
		mat.set_shader_parameter("tint", Color(0.4, 0.9, 1.0) if o.kind == "move" else Color(1.0, 0.8, 0.3))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		var area := Area3D.new()
		area.set_meta("slot", o.key)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.55
		sh.height = 0.3
		cs.shape = sh
		area.add_child(cs)
		n.add_child(area)
		markers_root.add_child(n)
		_markers.append(n)


func clear_slot_markers() -> void:
	for m in _markers:
		m.queue_free()
	_markers.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var from := camera.project_ray_origin(event.position)
		var dir := camera.project_ray_normal(event.position)
		var space := get_viewport().world_3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0)
		q.collide_with_areas = true
		q.collide_with_bodies = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return
		var col: Object = hit.collider
		if col.has_meta("slot"):
			slot_clicked.emit(col.get_meta("slot"))
			get_viewport().set_input_as_handled()
		elif col.has_meta("unit"):
			unit_clicked.emit(col.get_meta("unit"))
			get_viewport().set_input_as_handled()


func _on_action_resolved(event: Dictionary) -> void:
	var actor: UnitRuntime = event.actor
	var m := model_of(actor)
	if m == null:
		return
	_begin_busy()
	var ranged: bool = actor.is_ranged_now() or event.action.kind == "ultimate"
	var tw := m.play_attack(ranged)
	await get_tree().create_timer(0.12).timeout
	for r in event.results:
		var tm := model_of(r.target)
		if tm == null:
			continue
		if r.kind == "damage":
			tm.play_hit()
		else:
			tm.play_heal()
	if tw.is_valid():
		await tw.finished
	_end_busy()


func _on_unit_moved(unit: UnitRuntime, _f: String, _t: String) -> void:
	var m := model_of(unit)
	_begin_busy()
	var tw := create_tween()
	tw.tween_property(m, "position", slot_position(unit.team, unit.row, unit.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_end_busy()


func _on_units_swapped(a: UnitRuntime, b: UnitRuntime) -> void:
	var ma := model_of(a)
	var mb := model_of(b)
	_begin_busy()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ma, "position", slot_position(a.team, a.row, a.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(mb, "position", slot_position(b.team, b.row, b.index), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_end_busy()


func _on_weapon_changed(unit: UnitRuntime) -> void:
	var m := model_of(unit)
	if m:
		m.refresh_weapon()
		m.apply_lighting(preset)


func _on_unit_died(unit: UnitRuntime) -> void:
	var m := model_of(unit)
	if m:
		m.play_death()
