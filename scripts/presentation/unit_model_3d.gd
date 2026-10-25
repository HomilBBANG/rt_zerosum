class_name UnitModel3D
extends Node3D
## 3D 유닛: 기본 도형 조합 휴머노이드 + 셀 셰이더 + 역면 외곽선 + 얼굴 데칼 + 무기.
## 5번 레퍼런스의 '큰 눈, 정돈된 이목구비, 긴 실루엣' 을 큰 머리/가는 팔다리 비례로 근사.

const CEL := preload("res://shaders/cel_3d.gdshader")
const OUTLINE := preload("res://shaders/outline_3d.gdshader")
const UNLIT := preload("res://shaders/unlit_3d.gdshader")

var unit: UnitRuntime
var pivot: Node3D
var mats: Array[ShaderMaterial] = []
var weapon_root: Node3D
var ring: MeshInstance3D
var ring_mat: ShaderMaterial
var facing: float = 1.0
var _bob_t := 0.0
var _flash := 0.0
var head_height := 1.78
var highlight_kind := "none"


func _mat(color: Color, outline_mode: int = 0, outline_w: float = 0.016) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CEL
	m.set_shader_parameter("albedo", color)
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("mode", outline_mode)
	o.set_shader_parameter("width", outline_w)
	m.next_pass = o
	mats.append(m)
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.layers = 0b11  # 레이어 1(일반) + 2(캐릭터 전용 홍수광)
	(parent if parent else pivot).add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 24
	c.rings = 8
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 32
	s.rings = 16
	return s


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 24
	return c


func build(p_unit: UnitRuntime) -> void:
	unit = p_unit
	facing = 1.0 if unit.team == "ally" else -1.0
	var pal: Dictionary = unit.data.palette
	var skin := Color(pal.get("skin", "#f0c8a8"))
	var hair := Color(pal.get("hair", "#2b1d16"))
	var jacket := Color(pal.get("jacket", "#3b5d4a"))
	var pants := Color(pal.get("pants", "#2a3340"))
	var accent := Color(pal.get("accent", "#ffb347"))
	var style: String = pal.get("hair_style", "short")
	var boots := Color("#1e1c22")

	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	# 적/아군 모두 카메라 쪽을 보되 상대 진영 방향으로 약간 틀어 선다
	pivot.rotation_degrees.y = -28.0 * facing

	var m_skin := _mat(skin)
	var m_hair := _mat(hair)
	var m_jacket := _mat(jacket, 1)
	var m_jacket_r := _mat(jacket)
	var m_pants := _mat(pants)
	var m_boots := _mat(boots, 1)
	var m_accent := _mat(accent, 1, 0.01)
	var m_belt := _mat(Color(0.16, 0.14, 0.17), 1, 0.01)

	# 다리/부츠
	for side in [-1.0, 1.0]:
		var lx: float = side * 0.11
		_mesh(_capsule(0.075, 0.62), m_pants, Vector3(lx, 0.44, 0.0))
		_mesh(_box(Vector3(0.19, 0.16, 0.28)), m_boots, Vector3(lx, 0.08, 0.03))
	# 몸통(재킷) + 벨트 + 견장
	_mesh(_box(Vector3(0.46, 0.56, 0.26)), m_jacket, Vector3(0, 1.02, 0))
	_mesh(_box(Vector3(0.48, 0.07, 0.28)), m_belt, Vector3(0, 0.76, 0))
	_mesh(_box(Vector3(0.1, 0.06, 0.04)), m_accent, Vector3(0, 0.76, 0.145))
	for side in [-1.0, 1.0]:
		_mesh(_box(Vector3(0.16, 0.04, 0.22)), m_accent, Vector3(side * 0.2, 1.31, 0))
	# 칼라 (V)
	_mesh(_box(Vector3(0.2, 0.08, 0.06)), _mat(jacket.darkened(0.3), 1, 0.008), Vector3(0, 1.26, 0.13), Vector3(0, 0, 0))
	# 팔 (뒤팔 아래로, 앞팔 굽혀 무기 파지)
	var back_x := -0.3 * facing
	_mesh(_capsule(0.065, 0.5), m_jacket_r, Vector3(back_x, 1.02, -0.02), Vector3(0, 0, -8.0 * facing))
	_mesh(_sphere(0.07), m_skin, Vector3(back_x - 0.03 * facing, 0.72, 0.0))
	var front_x := 0.3 * facing
	_mesh(_capsule(0.065, 0.34), m_jacket_r, Vector3(front_x, 1.17, 0.02), Vector3(0, 0, 0))
	_mesh(_capsule(0.06, 0.32), m_jacket_r, Vector3(front_x + 0.02 * facing, 0.98, 0.14), Vector3(70, 0, 0))
	var hand_pos := Vector3(front_x + 0.02 * facing, 0.98, 0.30)
	_mesh(_sphere(0.07), m_skin, hand_pos)
	# 목/머리
	_mesh(_cyl(0.065, 0.075, 0.12), m_skin, Vector3(0, 1.34, 0))
	var head_r := 0.235
	var head_y := 1.60
	var head := _mesh(_sphere(head_r), m_skin, Vector3(0, head_y, 0))
	head.scale = Vector3(1.0, 1.08, 0.98)
	head_height = head_y + head_r * 1.08 + 0.32
	# 머리카락
	match style:
		"bald":
			var helm := _mesh(_sphere(head_r + 0.05), _mat(Color("#4b5a3c"), 0, 0.02), Vector3(0, head_y + 0.06, -0.01))
			helm.scale = Vector3(1.0, 0.85, 1.0)
			_mesh(_cyl(head_r + 0.09, head_r + 0.09, 0.05), _mat(Color("#36412c"), 1, 0.01), Vector3(0, head_y + 0.02, 0))
		"spiky":
			var cap := _mesh(_sphere(head_r + 0.03), m_hair, Vector3(0, head_y + 0.05, -0.04))
			cap.scale = Vector3(1.0, 0.8, 1.0)
			for i in 5:
				var a := -0.5 + i * 0.25
				_mesh(_cyl(0.0, 0.07, 0.26), m_hair, Vector3(a * 0.5, head_y + 0.3, -0.05 + abs(a) * 0.05), Vector3(0, 0, -a * 50.0))
		"long":
			var cap := _mesh(_sphere(head_r + 0.035), m_hair, Vector3(0, head_y + 0.04, -0.03))
			cap.scale = Vector3(1.02, 0.78, 1.0)
			_mesh(_box(Vector3(0.52, 0.62, 0.2)), _mat(hair, 1), Vector3(0, head_y - 0.26, -0.17))
		"bob":
			var cap := _mesh(_sphere(head_r + 0.035), m_hair, Vector3(0, head_y + 0.04, -0.02))
			cap.scale = Vector3(1.02, 0.8, 1.0)
			_mesh(_cyl(head_r + 0.04, head_r + 0.06, 0.3), m_hair, Vector3(0, head_y - 0.08, -0.04))
		"ponytail":
			var cap := _mesh(_sphere(head_r + 0.03), m_hair, Vector3(0, head_y + 0.05, -0.03))
			cap.scale = Vector3(1.0, 0.78, 1.0)
			_mesh(_capsule(0.07, 0.5), m_hair, Vector3(0.1 * facing, head_y - 0.12, -0.26), Vector3(15, 0, 10 * facing))
		"curly":
			var cap := _mesh(_sphere(head_r + 0.05), m_hair, Vector3(0, head_y + 0.07, -0.03))
			cap.scale = Vector3(1.05, 0.85, 1.05)
			for i in 6:
				var a := TAU * i / 6.0
				_mesh(_sphere(0.09), m_hair, Vector3(cos(a) * 0.2, head_y + 0.2 + sin(a) * 0.06, sin(a) * 0.18 - 0.03))
		_:
			var cap := _mesh(_sphere(head_r + 0.03), m_hair, Vector3(0, head_y + 0.05, -0.03))
			cap.scale = Vector3(1.0, 0.78, 1.0)
	# 귀
	for side in [-1.0, 1.0]:
		_mesh(_sphere(0.045), m_skin, Vector3(side * head_r, head_y - 0.02, 0.0))
	# 얼굴 데칼 (조명 무시: 눈 가독성)
	var face := QuadMesh.new()
	face.size = Vector2(0.4, 0.2)
	var fm := ShaderMaterial.new()
	fm.shader = UNLIT
	fm.set_shader_parameter("tex", load("res://assets/textures/face_%s.png" % unit.data.sprite_id))
	var fmi := _mesh(face, fm, Vector3(0, head_y - 0.01, head_r * 0.96))
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 무기
	weapon_root = Node3D.new()
	weapon_root.position = hand_pos
	pivot.add_child(weapon_root)
	refresh_weapon()
	# 하이라이트 링 (월드, pivot 회전 무관)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring = MeshInstance3D.new()
	ring.mesh = torus
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = UNLIT
	ring_mat.set_shader_parameter("tint", Color(1, 0.9, 0.4))
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.02, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	# 클릭 영역
	var area := Area3D.new()
	area.set_meta("unit", unit)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.9
	cs.shape = cap
	cs.position = Vector3(0, 0.95, 0)
	area.add_child(cs)
	add_child(area)


func refresh_weapon() -> void:
	for c in weapon_root.get_children():
		c.queue_free()
	var w := unit.current_weapon()
	var wid: String = w.get("id", "")
	var accent := Color(unit.data.palette.get("accent", "#ffd23f"))
	var m_metal := _mat(Color(0.23, 0.25, 0.29), 1, 0.008)
	var m_dark := _mat(Color(0.14, 0.15, 0.18), 1, 0.008)
	var m_wood := _mat(Color(0.42, 0.27, 0.16), 1, 0.008)
	var m_steel := _mat(Color(0.8, 0.84, 0.88), 1, 0.008)
	var m_acc := _mat(accent, 1, 0.006)
	var f := facing
	var root := Node3D.new()
	weapon_root.add_child(root)
	# 총기류는 앞쪽(+z)·상대 방향으로 기울여 파지
	match wid:
		"rifle", "sniper", "smg", "shotgun", "mg", "launcher":
			var L: float = {"rifle": 0.9, "sniper": 1.25, "smg": 0.55, "shotgun": 0.95, "mg": 1.05, "launcher": 0.7}[wid]
			var th: float = 0.1 if wid in ["mg", "launcher"] else 0.06
			root.rotation_degrees = Vector3(0, 0, 18.0 * f)
			_mesh(_box(Vector3(L, th, th)), m_metal, Vector3(L * 0.5 * f - 0.15 * f, 0, 0), Vector3.ZERO, root)
			_mesh(_box(Vector3(0.3, 0.09, 0.05)), m_wood if wid in ["rifle", "shotgun"] else m_dark, Vector3(-0.3 * f, -0.03, 0), Vector3.ZERO, root)
			_mesh(_box(Vector3(0.06, 0.16, 0.04)), m_dark, Vector3(0.0, -0.1, 0), Vector3.ZERO, root)
			if wid != "shotgun":
				_mesh(_box(Vector3(0.08, 0.2 if wid != "mg" else 0.26, 0.05)), m_dark, Vector3(0.18 * f, -0.12, 0), Vector3.ZERO, root)
			if wid == "sniper":
				_mesh(_box(Vector3(0.3, 0.06, 0.06)), m_dark, Vector3(0.3 * f, 0.08, 0), Vector3.ZERO, root)
			if wid == "launcher":
				_mesh(_cyl(0.07, 0.07, 0.3), m_metal, Vector3((L - 0.3) * f, 0, 0), Vector3(0, 0, 90), root)
			_mesh(_box(Vector3(0.05, th + 0.03, th + 0.03)), m_acc, Vector3(-0.06 * f, 0, 0), Vector3.ZERO, root)
		"pistol":
			root.rotation_degrees = Vector3(0, 0, 10.0 * f)
			_mesh(_box(Vector3(0.3, 0.07, 0.04)), m_metal, Vector3(0.1 * f, 0.04, 0), Vector3.ZERO, root)
			_mesh(_box(Vector3(0.07, 0.16, 0.04)), m_dark, Vector3(-0.03 * f, -0.06, 0), Vector3.ZERO, root)
		"axe", "mace", "club", "baton":
			root.rotation_degrees = Vector3(0, 0, -12.0 * f)
			_mesh(_cyl(0.025, 0.025, 1.0), m_wood if wid != "baton" else m_dark, Vector3(0, 0.3, 0), Vector3.ZERO, root)
			if wid == "axe":
				_mesh(_box(Vector3(0.36, 0.3, 0.03)), m_steel, Vector3(0.02 * f, 0.7, 0), Vector3.ZERO, root)
			elif wid == "mace":
				_mesh(_sphere(0.13), m_metal, Vector3(0, 0.82, 0), Vector3.ZERO, root)
			elif wid == "club":
				_mesh(_cyl(0.07, 0.035, 0.5), m_wood, Vector3(0, 0.6, 0), Vector3.ZERO, root)
			else:
				_mesh(_box(Vector3(0.12, 0.04, 0.04)), m_dark, Vector3(0.08 * f, 0.05, 0), Vector3.ZERO, root)
				_mesh(_cyl(0.03, 0.03, 0.06), m_acc, Vector3(0, 0.0, 0), Vector3.ZERO, root)
		"blade", "bayonet", "knife", "syringe":
			var L: float = {"blade": 1.0, "bayonet": 0.55, "knife": 0.4, "syringe": 0.45}[wid]
			root.rotation_degrees = Vector3(0, 0, -30.0 * f)
			if wid == "syringe":
				_mesh(_cyl(0.035, 0.035, 0.3), _mat(Color(0.93, 0.93, 0.95), 1, 0.006), Vector3(0, 0.15, 0), Vector3.ZERO, root)
				_mesh(_cyl(0.028, 0.028, 0.14), m_acc, Vector3(0, 0.12, 0), Vector3.ZERO, root)
				_mesh(_cyl(0.006, 0.006, 0.22), m_steel, Vector3(0, 0.41, 0), Vector3.ZERO, root)
			else:
				_mesh(_box(Vector3(0.05, 0.22, 0.05)), m_dark, Vector3(0, -0.1, 0), Vector3.ZERO, root)
				_mesh(_box(Vector3(0.18, 0.04, 0.06)), m_acc, Vector3(0, 0.02, 0), Vector3.ZERO, root)
				_mesh(_box(Vector3(0.07, L, 0.02)), m_steel, Vector3(0, L * 0.5 + 0.04, 0), Vector3.ZERO, root)
		_:
			pass


func set_flash(v: float) -> void:
	for m in mats:
		m.set_shader_parameter("flash", v)


func apply_lighting(p: Dictionary) -> void:
	# 3D 에서는 광원이 실제 색을 칠하므로 재질에는 그림자 색과 혼합률만 전달
	var amb: Color = p.ambient
	var char_amb := Color(minf(1.0, amb.r * 1.3), minf(1.0, amb.g * 1.3), minf(1.0, amb.b * 1.3))
	var char_shadow := Color(minf(1.0, p.shadow.r * 1.9), minf(1.0, p.shadow.g * 1.9), minf(1.0, p.shadow.b * 1.9))
	for m in mats:
		m.set_shader_parameter("shadow_tint", char_shadow)
		m.set_shader_parameter("ambient_tint", char_amb)
		m.set_shader_parameter("light_mix", p.char_key_mix + 0.05)
	ring_mat.set_shader_parameter("tint", p.get("ui_accent", Color(1, 0.9, 0.4)))


func set_highlight(kind: String) -> void:
	highlight_kind = kind
	ring.visible = kind != "none"
	match kind:
		"current":
			ring_mat.set_shader_parameter("tint", Color(1, 0.9, 0.4))
			ring.scale = Vector3(1.1, 1, 1.1)
		"target_ok":
			ring_mat.set_shader_parameter("tint", Color(1, 0.25, 0.2))
			ring.scale = Vector3.ONE
		"target_ally":
			ring_mat.set_shader_parameter("tint", Color(0.3, 1, 0.5))
			ring.scale = Vector3.ONE
		"target_bad":
			ring_mat.set_shader_parameter("tint", Color(0.5, 0.5, 0.5))
			ring.scale = Vector3(0.8, 1, 0.8)
		_:
			pass


func _process(delta: float) -> void:
	if not unit.alive:
		return
	_bob_t += delta * (2.2 if highlight_kind == "current" else 1.4)
	pivot.position.y = sin(_bob_t + float(unit.instance_id)) * (0.012 if highlight_kind == "current" else 0.007)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		set_flash(_flash)


func play_attack(ranged: bool) -> Tween:
	var tw := create_tween()
	var dir := facing
	if ranged:
		tw.tween_property(pivot, "position:x", -0.06 * dir, 0.08)
		tw.tween_property(pivot, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_BACK)
	else:
		tw.tween_property(pivot, "position:x", 0.4 * dir, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(pivot, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tw


func play_hit() -> void:
	_flash = 1.0
	var tw := create_tween()
	tw.tween_property(pivot, "rotation_degrees:z", -7.0 * facing, 0.06)
	tw.tween_property(pivot, "rotation_degrees:z", 0.0, 0.16)


func play_heal() -> void:
	var tw := create_tween()
	tw.tween_property(pivot, "scale", Vector3(1.05, 1.05, 1.05), 0.12)
	tw.tween_property(pivot, "scale", Vector3.ONE, 0.18)


func play_death() -> void:
	set_highlight("none")
	var tw := create_tween()
	tw.tween_property(pivot, "rotation_degrees:z", 80.0 * facing, 0.5).set_trans(Tween.TRANS_BOUNCE)
	for m in mats:
		var c: Color = m.get_shader_parameter("albedo")
		m.set_shader_parameter("albedo", c.darkened(0.45))
