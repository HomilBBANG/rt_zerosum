class_name BaseView3D
extends Node3D
## 기지 배경 3D: 시설 데이터(층·칸·폭)로 단면 건물을 만들고, 앞을 잘라 낸 방들을 위에서 살짝 내려다보는 원근 카메라로 본다.
## 셀 셰이더(cel_3d) + 방마다 원색 스폿 조명(전투 조명 프리셋 g1~g4) + 하드 섀도우. 잠긴 방은 앞을 검은 판으로 막는다.
## 카메라는 직교(원근 없음) + 살짝 내려다봄: 방 단면은 모두 같은 크기의 반듯한 사각형(한 칸 ≈ 정사각형), 방 안은 위에서 바닥이 보인다.
## 건물 바깥은 검정 (배경 없음).
## 대원(2D 리그)·이름표·말풍선은 BaseHub 가 이 카메라로 화면 좌표를 투영해 그 위에 그린다.
## 좌표: 시뮬레이션의 2D px (x 오른쪽, y 아래) → 3D m (x 오른쪽, y 위, z 화면 쪽). 칸 240px = CELL_M, 층 220px = FLOOR_M.

const CEL := preload("res://shaders/cel_3d.gdshader")
const OUTLINE := preload("res://shaders/outline_3d.gdshader")
const UNLIT := preload("res://shaders/unlit_3d.gdshader")

const CELL_M := 3.6          # 한 칸 폭 (m) — 층 높이 3.8m × cos(18°) ≈ 3.6m 라 기본 각도에서 한 칸이 정사각형으로 보임
const FLOOR_M := 3.8         # 층 높이 (바닥~바닥, m)
const SLAB := 0.35           # 층 사이 슬래브 두께
const BACK_Z := -3.0         # 방 뒷벽 안쪽 면
const FRONT_Z := 1.4         # 방 앞(잘라 낸 단면)
const WALL := 0.22           # 칸막이 벽 두께
const STAND_Z := [-1.45, -0.75, -1.1, -0.45, -1.7, -0.95]   # 대원이 서는 깊이 (대원 순서별로 엇갈림)

var sim: BaseSim
var camera: Camera3D
var fill: DirectionalLight3D
var rooms: Dictionary = {}    # fid → Node3D
var _mats: Dictionary = {}    # key → ShaderMaterial (색·조명 프리셋별 공유)


func build(p_sim: BaseSim) -> void:
	sim = p_sim
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.near = 0.3
	camera.far = 80.0
	add_child(camera)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	fill = DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.shadow_enabled = false   # 채움광은 그림자 없이 (가까이 보면 그림자 경계가 계단처럼 깨짐) — 그림자는 방 스폿 조명이 만듦
	add_child(fill)
	fill.rotation_degrees = Vector3(-24.0, -22.0, 0.0)   # 앞 위에서 비스듬히 → 천장이 뒷벽 위쪽에 단단한 그림자 띠
	_build_surroundings()
	for fid in sim.data.facility_order:
		rebuild_room(fid)


# ================================================================ 좌표
## 시뮬레이션 2D px → 3D m (depth = z)
func to3d(p: Vector2, depth: float = -1.0) -> Vector3:
	var x := p.x / OutgameData.CELL_W * CELL_M
	var y := (1.0 - (p.y + OutgameData.FLOOR_SLAB) / OutgameData.FLOOR_H) * FLOOR_M
	return Vector3(x, y, depth)


func stand_z(npc_id: String) -> float:
	var i := maxi(0, sim.data.npc_order.find(npc_id))
	return STAND_Z[i % STAND_Z.size()]


## 시설의 3D 상자: x0..x1, 바닥 y, 천장 y
func room_box(fid: String) -> Dictionary:
	var f: Dictionary = sim.data.facilities[fid]
	var x0: float = f.col * CELL_M
	var x1: float = (f.col + f.width) * CELL_M
	var y0: float = -float(f.order) * FLOOR_M
	return {"x0": x0, "x1": x1, "y0": y0, "y1": y0 + FLOOR_M - SLAB}


func base_bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for fid in sim.data.facility_order:
		var b := room_box(fid)
		var rr := Rect2(b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)
		r = rr if first else r.merge(rr)
		first = false
	return r


# ================================================================ 재질
func _mat(color: Color, light: String = "", outline: float = 0.0) -> ShaderMaterial:
	var key := "%s|%s|%.3f" % [color.to_html(), light, outline]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = CEL
	m.set_shader_parameter("albedo", color)
	if light != "":
		var p := LightingPresets.get_preset(light)
		m.set_shader_parameter("shadow_tint", (p.shadow as Color).lerp(Color(0.25, 0.25, 0.3), 0.35))
		m.set_shader_parameter("ambient_tint", (p.ambient as Color).lerp(Color(1, 1, 1), 0.15))
		m.set_shader_parameter("light_mix", 0.62)
	else:
		m.set_shader_parameter("shadow_tint", Color(0.42, 0.36, 0.42))
		m.set_shader_parameter("ambient_tint", Color(0.9, 0.86, 0.85))
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("mode", 1)
		o.set_shader_parameter("width", outline)
		m.next_pass = o
	_mats[key] = m
	return m


func _glow(color: Color) -> ShaderMaterial:
	var key := "glow|" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = UNLIT
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("dim", 1.0)
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ================================================================ 바깥 (하늘·지면·흙·건물 외곽)
func _build_surroundings() -> void:
	var out := Node3D.new()
	out.name = "Surroundings"
	add_child(out)
	var bb := base_bounds()
	var black := _glow(Color(0, 0, 0))
	# 방이 없는 칸 = 검정
	var d := sim.data
	for f in d.floors:
		for c in range(floori(bb.position.x / CELL_M), ceili(bb.end.x / CELL_M)):
			var px := Vector2((c + 0.5) * OutgameData.CELL_W, (f.order + 0.5) * OutgameData.FLOOR_H)
			if d.facility_at(px) == "":
				var y0: float = -float(f.order) * FLOOR_M
				_box(out, Vector3(CELL_M, FLOOR_M, FRONT_Z - BACK_Z), Vector3((c + 0.5) * CELL_M, y0 + FLOOR_M * 0.5 - SLAB * 0.5, (FRONT_Z + BACK_Z) * 0.5), black, false)
	# 층 사이 슬래브 (앞면이 방 사이 띠로 보임) + 맨 위 천장
	var slab := _mat(Color(0.20, 0.20, 0.25))
	for f in d.floors:
		var y0: float = -float(f.order) * FLOOR_M
		_box(out, Vector3(bb.size.x, SLAB, FRONT_Z - BACK_Z), Vector3(bb.get_center().x, y0 - SLAB * 0.5, (FRONT_Z + BACK_Z) * 0.5), slab)
	_box(out, Vector3(bb.size.x, SLAB, FRONT_Z - BACK_Z), Vector3(bb.get_center().x, bb.end.y + SLAB * 0.5, (FRONT_Z + BACK_Z) * 0.5), slab)


# ================================================================ 방
## 시설 하나를 (다시) 만든다 — 해금되면 검은 판을 치우고 내부·조명을 넣음
func rebuild_room(fid: String) -> void:
	if rooms.has(fid):
		var old: Node3D = rooms[fid]
		remove_child(old)   # 바로 빼야 같은 프레임 재렌더에 검은 판이 남지 않음
		old.queue_free()
	var n := Node3D.new()
	n.name = fid
	add_child(n)
	rooms[fid] = n
	var f: Dictionary = sim.data.facilities[fid]
	var b := room_box(fid)
	var w: float = b.x1 - b.x0
	var h: float = b.y1 - b.y0
	var cx: float = (b.x0 + b.x1) * 0.5
	var y0: float = b.y0
	var open := sim.is_unlocked(fid)
	var light: String = f.light
	var p := LightingPresets.get_preset(light)
	var wall_col: Color = (p.ambient as Color).lerp(Color(0.85, 0.82, 0.78), 0.45)
	var wall := _mat(wall_col, light)
	var floor_m := _mat(Color(0.55, 0.52, 0.50), light)
	# 뒷벽 · 칸막이 · 바닥 · 천장
	_box(n, Vector3(w, h, 0.3), Vector3(cx, y0 + h * 0.5, BACK_Z - 0.15), wall)
	_box(n, Vector3(WALL, h, FRONT_Z - BACK_Z), Vector3(b.x0 + WALL * 0.5, y0 + h * 0.5, (FRONT_Z + BACK_Z) * 0.5), _mat(wall_col.darkened(0.15), light))
	_box(n, Vector3(WALL, h, FRONT_Z - BACK_Z), Vector3(b.x1 - WALL * 0.5, y0 + h * 0.5, (FRONT_Z + BACK_Z) * 0.5), _mat(wall_col.darkened(0.15), light))
	_box(n, Vector3(w, 0.06, FRONT_Z - BACK_Z), Vector3(cx, y0 + 0.03, (FRONT_Z + BACK_Z) * 0.5), floor_m)
	_box(n, Vector3(w, 0.1, FRONT_Z - BACK_Z), Vector3(cx, b.y1 - 0.05, (FRONT_Z + BACK_Z) * 0.5), _mat(Color(0.30, 0.30, 0.36), light), false)
	if not open:
		# 잠긴 방: 단면 앞을 검은 판으로 막음 (자물쇠·가격은 2D 덮개가 그림)
		_box(n, Vector3(w + 0.03, h + 0.02, 0.06), Vector3(cx, y0 + h * 0.5, FRONT_Z + 0.04), _glow(Color(0, 0, 0)), false)
		return
	# 벽 띠 (허리 높이 몰딩)
	_box(n, Vector3(w - WALL * 2, 0.12, 0.06), Vector3(cx, y0 + 1.0, BACK_Z + 0.03), _mat(wall_col.darkened(0.3), light, 0.012), false)
	match str(f.tag):
		"계단":
			_stairs(n, b, light)
		"출입":
			_gate(n, b, light)
		_:
			_furniture(n, f, b, light)
	# 천장 조명 + 원색 스폿 (방 안에서만 닿도록 짧은 거리, 하드 섀도우)
	if f.tag != "출입":
		var lx := cx + w * 0.12
		_box(n, Vector3(0.9, 0.12, 0.5), Vector3(lx, b.y1 - 0.16, -1.1), _mat(Color(0.2, 0.2, 0.24), light, 0.015), false)
		_box(n, Vector3(0.7, 0.04, 0.35), Vector3(lx, b.y1 - 0.23, -1.1), _glow((p.key as Color).lightened(0.35)), false)
		var s := SpotLight3D.new()
		s.light_color = p.key
		s.light_energy = 5.0
		s.spot_range = h + 3.5
		s.spot_angle = 42.0 if f.width > 1 else 30.0
		s.spot_angle_attenuation = 0.3
		s.spot_attenuation = 0.35
		s.shadow_enabled = true
		s.shadow_bias = 0.05
		s.shadow_normal_bias = 1.4
		n.add_child(s)
		s.position = Vector3(lx, b.y1 - 0.3, -1.1)
		s.look_at(Vector3(lx + w * 0.08, y0, -2.4), Vector3.UP)
	# 보조색 띠 조명 (바닥 쪽 벽 모서리, 단색 발광)
	_box(n, Vector3(w - WALL * 2, 0.05, 0.05), Vector3(cx, y0 + 0.08, BACK_Z + 0.04), _glow((p.accent as Color).darkened(0.1)), false)


func _furniture(n: Node3D, f: Dictionary, b: Dictionary, light: String) -> void:
	var p := LightingPresets.get_preset(light)
	var x0: float = b.x0
	var w: float = b.x1 - b.x0
	var y: float = b.y0
	var key: Color = p.key
	var acc: Color = p.accent
	var amb: Color = p.ambient
	var BZ := BACK_Z + 0.02
	var wood := _mat(Color(0.55, 0.38, 0.26), light, 0.015)
	var metal := _mat(Color(0.45, 0.46, 0.52), light, 0.015)
	match str(f.tag):
		"행정":
			for i in 2:
				var dx := x0 + w * (0.24 + i * 0.44)
				_box(n, Vector3(1.5, 0.08, 0.75), Vector3(dx, y + 0.78, BZ + 0.6), wood)
				for sx in [-0.65, 0.65]:
					_box(n, Vector3(0.08, 0.76, 0.6), Vector3(dx + sx, y + 0.38, BZ + 0.6), metal)
				_box(n, Vector3(0.7, 0.45, 0.06), Vector3(dx, y + 1.1, BZ + 0.35), _mat(Color(0.12, 0.12, 0.15), light, 0.012))
				_box(n, Vector3(0.6, 0.36, 0.02), Vector3(dx, y + 1.1, BZ + 0.39), _glow(acc.lightened(0.25)), false)
			_box(n, Vector3(1.5, 0.95, 0.06), Vector3(x0 + w * 0.46, y + 2.1, BZ + 0.03), _mat(Color(0.55, 0.36, 0.22), light, 0.012))
			var notes := [Color(1, 0.95, 0.7), Color(0.8, 1, 0.9), Color(1, 0.8, 0.85), Color(0.85, 0.9, 1)]
			for i in 4:
				_box(n, Vector3(0.5, 0.32, 0.02), Vector3(x0 + w * 0.46 - 0.32 + (i % 2) * 0.64, y + 2.3 - floori(i / 2.0) * 0.42, BZ + 0.07), _mat(notes[i], light), false)
		"공용":
			if str(f.id).contains("mess"):
				_box(n, Vector3(w * 0.55, 0.1, 0.9), Vector3(x0 + w * 0.38, y + 0.78, BZ + 1.1), wood)
				for sx in [-1.0, 1.0]:
					_box(n, Vector3(0.1, 0.74, 0.7), Vector3(x0 + w * 0.38 + sx * w * 0.24, y + 0.37, BZ + 1.1), metal)
				_box(n, Vector3(w * 0.5, 0.42, 0.3), Vector3(x0 + w * 0.38, y + 0.21, BZ + 1.85), wood)
				_box(n, Vector3(w * 0.26, 1.05, 0.8), Vector3(x0 + w * 0.82, y + 0.53, BZ + 0.45), _mat(amb.darkened(0.45), light, 0.015))
				_box(n, Vector3(w * 0.22, 0.08, 0.6), Vector3(x0 + w * 0.82, y + 1.1, BZ + 0.45), _glow(key.lightened(0.2)), false)
			elif str(f.id).contains("storage"):
				for i in 6:
					var hh := 0.7 + (i % 3) * 0.45
					_box(n, Vector3(0.95, hh, 0.95), Vector3(x0 + w * (0.12 + i * 0.15), y + hh * 0.5, BZ + 0.6 + (i % 2) * 0.5), _mat(Color(0.62, 0.48, 0.30), light, 0.02))
			else:
				var sofa := _mat(key.darkened(0.25), light, 0.018)
				var sx := x0 + w * 0.28
				_box(n, Vector3(2.2, 0.45, 0.85), Vector3(sx, y + 0.28, BZ + 0.6), sofa)
				_box(n, Vector3(2.2, 0.6, 0.25), Vector3(sx, y + 0.75, BZ + 0.25), sofa)
				for ax in [-1.15, 1.15]:
					_box(n, Vector3(0.25, 0.7, 0.85), Vector3(sx + ax, y + 0.35, BZ + 0.6), sofa)
				_box(n, Vector3(1.1, 0.08, 0.6), Vector3(x0 + w * 0.62, y + 0.45, BZ + 1.3), wood)
				_box(n, Vector3(0.12, 0.42, 0.12), Vector3(x0 + w * 0.62, y + 0.21, BZ + 1.3), metal)
				_box(n, Vector3(1.2, 0.8, 0.08), Vector3(x0 + w * 0.78, y + 1.95, BZ + 0.04), _mat(Color(0.1, 0.1, 0.13), light, 0.012))
				_box(n, Vector3(1.05, 0.66, 0.02), Vector3(x0 + w * 0.78, y + 1.95, BZ + 0.09), _glow(acc), false)
		"생활":
			for i in 2:
				var bx := x0 + w * (0.22 + i * 0.36)
				for lvl in 2:
					var by := y + 0.45 + lvl * 1.1
					_box(n, Vector3(1.9, 0.18, 0.9), Vector3(bx, by, BZ + 0.55), _mat(Color(0.88, 0.88, 0.92), light, 0.012))
					_box(n, Vector3(1.95, 0.08, 0.95), Vector3(bx, by - 0.12, BZ + 0.55), metal)
				for sx in [-0.98, 0.98]:
					_box(n, Vector3(0.08, 2.0, 0.08), Vector3(bx + sx, y + 1.0, BZ + 0.98), metal)
			for i in 3:
				_box(n, Vector3(0.42, 1.9, 0.5), Vector3(x0 + w * 0.86 + (i - 1) * 0.44, y + 0.95, BZ + 0.27), _mat(amb.darkened(0.35), light, 0.012))
		"작업":
			_box(n, Vector3(w * 0.45, 0.12, 0.8), Vector3(x0 + w * 0.32, y + 0.9, BZ + 0.5), wood)
			for sx in [-1.0, 1.0]:
				_box(n, Vector3(0.12, 0.85, 0.7), Vector3(x0 + w * 0.32 + sx * w * 0.2, y + 0.43, BZ + 0.5), metal)
			_box(n, Vector3(w * 0.45, 1.1, 0.06), Vector3(x0 + w * 0.32, y + 1.95, BZ + 0.03), _mat(Color(0.48, 0.40, 0.33), light, 0.012))
			for i in 7:
				_box(n, Vector3(0.07, 0.6, 0.05), Vector3(x0 + w * 0.16 + i * w * 0.05, y + 1.95, BZ + 0.08), _mat(Color(0.85, 0.85, 0.9), light), false)
			_box(n, Vector3(1.1, 1.2, 0.9), Vector3(x0 + w * 0.78, y + 0.6, BZ + 0.5), _mat(Color(0.28, 0.29, 0.34), light, 0.02))
			_box(n, Vector3(0.8, 0.1, 0.05), Vector3(x0 + w * 0.78, y + 0.95, BZ + 0.96), _glow(key), false)
		"훈련":
			var bag := CylinderMesh.new()
			bag.top_radius = 0.28
			bag.bottom_radius = 0.28
			bag.height = 1.1
			var mi := MeshInstance3D.new()
			mi.mesh = bag
			mi.material_override = _mat(key.darkened(0.25), light, 0.02)
			mi.position = Vector3(x0 + w * 0.2, y + 1.75, BZ + 0.9)
			n.add_child(mi)
			_box(n, Vector3(0.04, 0.9, 0.04), Vector3(x0 + w * 0.2, y + 2.75, BZ + 0.9), metal, false)
			_box(n, Vector3(w * 0.42, 0.06, 1.4), Vector3(x0 + w * 0.55, y + 0.03, BZ + 1.2), _mat(acc.darkened(0.35), light), false)
			for sx in [0.0, 1.3]:
				_box(n, Vector3(0.1, 1.2, 0.1), Vector3(x0 + w * 0.72 + sx, y + 0.6, BZ + 0.45), metal)
			_box(n, Vector3(1.8, 0.06, 0.06), Vector3(x0 + w * 0.72 + 0.65, y + 1.15, BZ + 0.45), metal)
			for sx in [-0.15, 1.45]:
				_box(n, Vector3(0.12, 0.5, 0.5), Vector3(x0 + w * 0.72 + sx, y + 1.15, BZ + 0.45), _mat(Color(0.12, 0.12, 0.14), light, 0.015))
		_:
			for i in 3:
				_box(n, Vector3(1.0, 0.85, 0.9), Vector3(x0 + w * (0.2 + i * 0.28), y + 0.43, BZ + 0.55), _mat(Color(0.42, 0.42, 0.46), light, 0.02))
			for i in 2:
				var t := _box(n, Vector3(w - 0.8, 0.16, 0.04), Vector3(x0 + w * 0.5, y + 1.6 + i * 0.6, BZ + 0.06), _glow(Color(1, 0.85, 0.1)), false)
				t.rotation_degrees.z = -6.0 + i * 12.0


func _stairs(n: Node3D, b: Dictionary, light: String) -> void:
	var w: float = b.x1 - b.x0
	var h: float = b.y1 - b.y0
	var steps := 9
	var step_mat := _mat(Color(0.5, 0.5, 0.56), light, 0.01)
	for i in steps:
		var sh := (i + 1) * h / float(steps + 1)
		_box(n, Vector3(w / steps, sh, 1.2), Vector3(b.x0 + (i + 0.5) * w / steps, b.y0 + sh * 0.5, BACK_Z + 0.62), step_mat)
	var rail := _box(n, Vector3(w * 1.2, 0.07, 0.07), Vector3((b.x0 + b.x1) * 0.5, b.y0 + h * 0.62, BACK_Z + 1.3), _mat(Color(0.95, 0.8, 0.2), light), false)
	rail.rotation.z = atan2(h * 0.85, w)


func _gate(n: Node3D, b: Dictionary, light: String) -> void:
	var h: float = b.y1 - b.y0
	# 바깥으로 열린 출입문: 왼쪽 벽 대신 노을빛 발광 면 + 문틀 + EXIT 표시
	_box(n, Vector3(0.05, h * 0.78, FRONT_Z - BACK_Z - 1.4), Vector3(b.x0 + 0.3, b.y0 + h * 0.39, (FRONT_Z + BACK_Z) * 0.5 - 0.2), _glow(Color(1.0, 0.66, 0.42)), false)
	_box(n, Vector3(0.3, 0.2, FRONT_Z - BACK_Z), Vector3(b.x0 + 0.3, b.y0 + h * 0.8, (FRONT_Z + BACK_Z) * 0.5), _mat(Color(0.32, 0.33, 0.4), light, 0.015))
	_box(n, Vector3(0.7, 0.24, 0.05), Vector3((b.x0 + b.x1) * 0.5, b.y1 - 0.5, BACK_Z + 0.05), _glow(Color(0.25, 1.0, 0.45)), false)
	var s := SpotLight3D.new()
	s.light_color = Color(1.0, 0.62, 0.36)
	s.light_energy = 5.0
	s.spot_range = 9.0
	s.spot_angle = 50.0
	s.shadow_enabled = true
	n.add_child(s)
	s.position = Vector3(b.x0 - 1.5, b.y0 + h * 0.75, -0.8)
	s.look_at(Vector3(b.x1, b.y0, -1.2), Vector3.UP)


# ================================================================ 카메라
## target = 화면 가운데 점 (m), 직교 카메라가 위에서 pitch 만큼 내려다봄. size = 화면 세로에 들어가는 높이 (m, 작을수록 확대)
func set_camera(target: Vector3, size: float, pitch_deg: float) -> void:
	var p := deg_to_rad(pitch_deg)
	camera.size = size
	camera.position = target + Vector3(0.0, sin(p), cos(p)) * 30.0
	camera.look_at(target, Vector3.UP)
