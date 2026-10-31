class_name BaseView3D
extends Node3D
## 기지 배경 3D: 시설 데이터(층·칸·폭)로 단면 건물을 만들고, 앞을 잘라 낸 방들을 위에서 살짝 내려다보는 원근 카메라로 본다.
## 셀 셰이더(cel_3d) + 방마다 원색 스폿 조명(전투 조명 프리셋 g1~g4) + 하드 섀도우. 잠긴 방은 앞을 검은 판으로 막는다.
## 카메라는 직교(원근 없음) + 살짝 내려다봄: 방 단면은 모두 같은 크기의 반듯한 사각형(한 칸 ≈ 정사각형), 방 안은 위에서 바닥이 보인다.
## 건물 바깥은 검정 (배경 없음).
## 대원(2D 리그)·이름표·말풍선은 BaseHub 가 이 카메라로 화면 좌표를 투영해 그 위에 그린다.
## 대원 조명: 방 스폿 조명을 탐침(light_probe)해 캐릭터 셰이더의 빛 방향·색·림을 실시간으로 (NpcView) (그림자는 NpcView 의 발밑 동그란 그림자).
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
## 오브젝트 깊이 (침대·소파는 뒷벽 쪽, 의자는 책상 앞)
const SEAT_Z := {"침대": -2.45, "의무침대": -2.05, "소파": -2.35, "의자": -1.55}

var sim: BaseSim
var camera: Camera3D
var fill: DirectionalLight3D
var rooms: Dictionary = {}    # fid → Node3D
var _mats: Dictionary = {}    # key → ShaderMaterial (색·조명 프리셋별 공유)
var _lights: Dictionary = {}  # fid → [SpotLight3D] (방 스폿 · 출입문 노을빛) — 대원 조명 탐침(light_probe)용
var jukebox: AABB = AABB()    # 공용실 주크박스 (3D 상자, 크기 0 = 없음) — 누르면 음악 카세트 창 (BaseHub)


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
	# 층 사이 슬래브 (앞면이 방 사이 띠로 보임) + 맨 위 천장. 계단이 올라오는 자리는 뚫음
	var slab := _mat(Color(0.20, 0.20, 0.25))
	for fid in d.facility_order:
		var b := room_box(fid)
		_floor_box(out, b, b.y0 - SLAB * 0.5, SLAB, slab, arrival_hole(fid))
	for f in d.floors:
		for c in range(floori(bb.position.x / CELL_M), ceili(bb.end.x / CELL_M)):
			var px := Vector2((c + 0.5) * OutgameData.CELL_W, (f.order + 0.5) * OutgameData.FLOOR_H)
			if d.facility_at(px) == "":
				var y0: float = -float(f.order) * FLOOR_M
				_box(out, Vector3(CELL_M, SLAB, FRONT_Z - BACK_Z), Vector3((c + 0.5) * CELL_M, y0 - SLAB * 0.5, (FRONT_Z + BACK_Z) * 0.5), slab)
	_box(out, Vector3(bb.size.x, SLAB, FRONT_Z - BACK_Z), Vector3(bb.get_center().x, bb.end.y + SLAB * 0.5, (FRONT_Z + BACK_Z) * 0.5), slab)


# ================================================================ 계단 (꺾인 계단: 층마다 방향이 바뀌고 앞뒤 깊이를 번갈아)
## 아래층 order k 의 계단 한 구간이 놓이는 깊이 (k 홀수 = 뒤쪽, 짝수 = 앞쪽)
static func flight_z(lower_order: int) -> float:
	return -2.45 if lower_order % 2 == 1 else -1.5


func stair_at(order: int, col: int) -> String:
	for fid in sim.data.facility_order:
		var f: Dictionary = sim.data.facilities[fid]
		if f.tag == "계단" and int(f.order) == order and int(f.col) == col:
			return fid
	return ""


## 이 계단 방에서 위층으로 올라가는 계단이 있는가
func has_flight(fid: String) -> bool:
	var f: Dictionary = sim.data.facilities[fid]
	return f.tag == "계단" and stair_at(int(f.order) - 1, int(f.col)) != ""


## 아래층 계단이 이 방 바닥으로 올라오는 구멍 {x0, x1, z0, z1} (없으면 {})
func arrival_hole(fid: String) -> Dictionary:
	var f: Dictionary = sim.data.facilities[fid]
	if f.tag != "계단":
		return {}
	var below := stair_at(int(f.order) + 1, int(f.col))
	if below == "":
		return {}
	var b := room_box(fid)
	var w: float = b.x1 - b.x0
	var z := flight_z(int(f.order) + 1)
	if RoomRouteService.flight_left_to_right(int(f.order) + 1):   # 위 끝 = 오른쪽
		return {"x0": b.x0 + w * 0.38, "x1": b.x1 - WALL, "z0": z - 0.55, "z1": z + 0.55}
	return {"x0": b.x0 + WALL, "x1": b.x1 - w * 0.38, "z0": z - 0.55, "z1": z + 0.55}


## 바닥/슬래브 상자 (구멍이 있으면 구멍을 뺀 조각들로)
func _floor_box(parent: Node3D, b: Dictionary, yc: float, thick: float, mat: Material, hole: Dictionary) -> void:
	var w: float = b.x1 - b.x0
	var cx: float = (b.x0 + b.x1) * 0.5
	if hole.is_empty():
		_box(parent, Vector3(w, thick, FRONT_Z - BACK_Z), Vector3(cx, yc, (FRONT_Z + BACK_Z) * 0.5), mat)
		return
	var z0: float = hole.z0
	var z1: float = hole.z1
	_box(parent, Vector3(w, thick, FRONT_Z - z1), Vector3(cx, yc, (FRONT_Z + z1) * 0.5), mat)
	_box(parent, Vector3(w, thick, z0 - BACK_Z), Vector3(cx, yc, (z0 + BACK_Z) * 0.5), mat)
	if hole.x0 > b.x0 + 0.01:
		_box(parent, Vector3(hole.x0 - b.x0, thick, z1 - z0), Vector3((b.x0 + hole.x0) * 0.5, yc, (z0 + z1) * 0.5), mat)
	if hole.x1 < b.x1 - 0.01:
		_box(parent, Vector3(b.x1 - hole.x1, thick, z1 - z0), Vector3((b.x1 + hole.x1) * 0.5, yc, (z0 + z1) * 0.5), mat)


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
	_lights[fid] = []
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
	# 방과 방 사이 칸막이 = 검은 벽 (연출만 — 이동 경로는 그대로 지나감). 빛을 안 받는 단색이라 어느 조명에서도 검정
	var part := _glow(Color(0.02, 0.02, 0.03))
	_box(n, Vector3(WALL, h, FRONT_Z - BACK_Z), Vector3(b.x0 + WALL * 0.5, y0 + h * 0.5, (FRONT_Z + BACK_Z) * 0.5), part)
	_box(n, Vector3(WALL, h, FRONT_Z - BACK_Z), Vector3(b.x1 - WALL * 0.5, y0 + h * 0.5, (FRONT_Z + BACK_Z) * 0.5), part)
	_floor_box(n, b, y0 + 0.03, 0.06, floor_m, arrival_hole(fid))
	if not has_flight(fid):   # 계단이 위층으로 뚫고 올라가는 방은 천장 없음
		_box(n, Vector3(w, 0.1, FRONT_Z - BACK_Z), Vector3(cx, b.y1 - 0.05, (FRONT_Z + BACK_Z) * 0.5), _mat(Color(0.30, 0.30, 0.36), light), false)
	if not open:
		# 잠긴 방: 단면 앞을 검은 판으로 막음 (자물쇠·가격은 2D 덮개가 그림)
		_box(n, Vector3(w + 0.03, h + 0.02, 0.06), Vector3(cx, y0 + h * 0.5, FRONT_Z + 0.04), _glow(Color(0, 0, 0)), false)
		return
	# 벽 띠 (허리 높이 몰딩)
	_box(n, Vector3(w - WALL * 2, 0.12, 0.06), Vector3(cx, y0 + 1.0, BACK_Z + 0.03), _mat(wall_col.darkened(0.3), light, 0.012), false)
	match str(f.tag):
		"계단":
			_stairs(n, fid, b, light)
		"출입":
			_gate(n, b, light)
		_:
			_furniture(n, f, b, light)
	_objects(n, fid, b, light)
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
		_lights[fid].append(s)
	# 보조색 띠 조명 (바닥 쪽 벽 모서리, 단색 발광)
	_box(n, Vector3(w - WALL * 2, 0.05, 0.05), Vector3(cx, y0 + 0.08, BACK_Z + 0.04), _glow((p.accent as Color).darkened(0.1)), false)


## 오브젝트 시트의 침대·소파·의자·의무침대 (대원이 실제로 눕거나 앉는 자리)
func _objects(n: Node3D, fid: String, b: Dictionary, light: String) -> void:
	var p := LightingPresets.get_preset(light)
	var metal := _mat(Color(0.45, 0.46, 0.52), light, 0.015)
	for oid in sim.data.objects_in(fid):
		var o: Dictionary = sim.data.objects[oid]
		var x := to3d(Vector2(sim.data.object_x(oid), 0)).x
		var h: float = o.height
		var z: float = SEAT_Z.get(o.kind, -1.6)
		var y: float = b.y0
		match str(o.kind):
			"침대":
				_box(n, Vector3(1.9, 0.18, 0.9), Vector3(x, y + h, z), _mat(Color(0.88, 0.88, 0.92), light, 0.012))
				_box(n, Vector3(1.95, 0.08, 0.95), Vector3(x, y + h - 0.13, z), metal)
				_box(n, Vector3(0.38, 0.12, 0.6), Vector3(x - 0.7, y + h + 0.13, z), _mat(Color(0.95, 0.95, 1.0), light), false)
				for sx in [-0.98, 0.98]:
					_box(n, Vector3(0.07, h + 0.35, 0.07), Vector3(x + sx, y + (h + 0.35) * 0.5, z + 0.44), metal)
			"의무침대":
				_box(n, Vector3(1.65, 0.16, 0.8), Vector3(x, y + h, z), _mat(Color(0.96, 0.97, 1.0), light, 0.012))
				for sx in [-0.72, 0.72]:
					_box(n, Vector3(0.06, h, 0.06), Vector3(x + sx, y + h * 0.5, z + 0.35), metal)
					_box(n, Vector3(0.06, h, 0.06), Vector3(x + sx, y + h * 0.5, z - 0.35), metal)
				_box(n, Vector3(0.36, 0.1, 0.55), Vector3(x - 0.6, y + h + 0.12, z), _mat(Color(1, 1, 1), light), false)
				_box(n, Vector3(0.04, 1.7, 0.04), Vector3(x - 0.95, y + 0.85, z - 0.3), metal, false)
				_box(n, Vector3(0.16, 0.24, 0.06), Vector3(x - 0.95, y + 1.6, z - 0.3), _glow(Color(0.7, 0.95, 1.0)), false)
			"소파":
				var sofa := _mat((p.key as Color).darkened(0.25), light, 0.018)
				_box(n, Vector3(1.0, h, 0.85), Vector3(x, y + h * 0.5, z), sofa)
				_box(n, Vector3(1.0, 0.6, 0.25), Vector3(x, y + h + 0.3, z - 0.32), sofa)
			"의자":
				var seat := _mat(Color(0.30, 0.32, 0.38), light, 0.014)
				_box(n, Vector3(0.5, 0.07, 0.5), Vector3(x, y + h, z), seat)
				_box(n, Vector3(0.5, 0.55, 0.06), Vector3(x, y + h + 0.3, z + 0.25), seat)
				_box(n, Vector3(0.06, h, 0.06), Vector3(x, y + h * 0.5, z), metal, false)


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
		"식당":
			_box(n, Vector3(w * 0.55, 0.1, 0.9), Vector3(x0 + w * 0.38, y + 0.78, BZ + 0.75), wood)
			for sx in [-1.0, 1.0]:
				_box(n, Vector3(0.1, 0.74, 0.7), Vector3(x0 + w * 0.38 + sx * w * 0.24, y + 0.37, BZ + 0.75), metal)
			_box(n, Vector3(w * 0.26, 1.05, 0.8), Vector3(x0 + w * 0.84, y + 0.53, BZ + 0.45), _mat(amb.darkened(0.45), light, 0.015))
			_box(n, Vector3(w * 0.22, 0.08, 0.6), Vector3(x0 + w * 0.84, y + 1.1, BZ + 0.45), _glow(key.lightened(0.2)), false)
			_box(n, Vector3(0.7, 1.9, 0.6), Vector3(x0 + w * 0.84, y + 0.95 + 1.1, BZ + 0.3), _mat(Color(0.85, 0.87, 0.9), light, 0.015))
			# 식재료 상자 (보유 수량만큼 보이게는 2D 이름표로)
			for i in 3:
				_box(n, Vector3(0.5, 0.35, 0.4), Vector3(x0 + w * 0.66 + i * 0.12, y + 0.18 + i * 0.35, BZ + 0.3), _mat(Color(0.62, 0.48, 0.30), light, 0.015))
		"상점":
			for i in 3:
				_box(n, Vector3(w * 0.7, 0.06, 0.5), Vector3(x0 + w * 0.5, y + 0.6 + i * 0.6, BZ + 0.26), wood)
				for j in 4:
					var cc: Color = [Color(1, 0.4, 0.4), Color(0.4, 0.8, 1), Color(1, 0.85, 0.3), Color(0.5, 1, 0.6)][(i + j) % 4]
					_box(n, Vector3(0.22, 0.3, 0.22), Vector3(x0 + w * (0.22 + j * 0.18), y + 0.78 + i * 0.6, BZ + 0.26), _mat(cc, light, 0.01), false)
			_box(n, Vector3(w * 0.6, 1.0, 0.5), Vector3(x0 + w * 0.5, y + 0.5, BZ + 1.4), _mat(amb.darkened(0.4), light, 0.015))
			_box(n, Vector3(0.9, 0.35, 0.05), Vector3(x0 + w * 0.5, y + 2.6, BZ + 0.05), _glow(Color(1.0, 0.85, 0.3)), false)
		"의무":
			_box(n, Vector3(0.9, 1.8, 0.45), Vector3(x0 + w * 0.94 - 0.45, y + 0.9, BZ + 0.24), _mat(Color(0.92, 0.94, 0.96), light, 0.015))
			_box(n, Vector3(0.6, 0.16, 0.04), Vector3(x0 + w * 0.5, y + 2.4, BZ + 0.05), _glow(Color(0.3, 1.0, 0.5)), false)
			_box(n, Vector3(0.16, 0.6, 0.04), Vector3(x0 + w * 0.5, y + 2.4, BZ + 0.05), _glow(Color(0.3, 1.0, 0.5)), false)
		"공용":
			if str(f.id).contains("storage"):
				for i in 6:
					var hh := 0.7 + (i % 3) * 0.45
					_box(n, Vector3(0.95, hh, 0.95), Vector3(x0 + w * (0.12 + i * 0.15), y + hh * 0.5, BZ + 0.6 + (i % 2) * 0.5), _mat(Color(0.62, 0.48, 0.30), light, 0.02))
			else:
				_box(n, Vector3(1.1, 0.08, 0.6), Vector3(x0 + w * 0.62, y + 0.45, BZ + 1.3), wood)
				_box(n, Vector3(0.12, 0.42, 0.12), Vector3(x0 + w * 0.62, y + 0.21, BZ + 1.3), metal)
				_box(n, Vector3(1.2, 0.8, 0.08), Vector3(x0 + w * 0.68, y + 1.95, BZ + 0.04), _mat(Color(0.1, 0.1, 0.13), light, 0.012))   # TV (주크박스 자리만큼 왼쪽)
				_box(n, Vector3(1.05, 0.66, 0.02), Vector3(x0 + w * 0.68, y + 1.95, BZ + 0.09), _glow(acc), false)
				_jukebox(n, Vector3(x1_in(b) - 0.62, y, BZ + 0.55), light)
		"생활":
			pass   # 침대는 오브젝트 시트로
		"작업", "무기고":
			_box(n, Vector3(w * 0.45, 0.12, 0.8), Vector3(x0 + w * 0.32, y + 0.9, BZ + 0.5), wood)
			for sx in [-1.0, 1.0]:
				_box(n, Vector3(0.12, 0.85, 0.7), Vector3(x0 + w * 0.32 + sx * w * 0.2, y + 0.43, BZ + 0.5), metal)
			_box(n, Vector3(w * 0.45, 1.1, 0.06), Vector3(x0 + w * 0.32, y + 1.95, BZ + 0.03), _mat(Color(0.48, 0.40, 0.33), light, 0.012))
			for i in 7:
				_box(n, Vector3(0.07, 0.6, 0.05), Vector3(x0 + w * 0.16 + i * w * 0.05, y + 1.95, BZ + 0.08), _mat(Color(0.85, 0.85, 0.9), light), false)
			_box(n, Vector3(1.1, 1.2, 0.9), Vector3(x0 + w * 0.78, y + 0.6, BZ + 0.5), _mat(Color(0.28, 0.29, 0.34), light, 0.02))
			_box(n, Vector3(0.8, 0.1, 0.05), Vector3(x0 + w * 0.78, y + 0.95, BZ + 0.96), _glow(key), false)
			# 무기 걸이 (소총 모양 막대들, 뒷벽 오른쪽 위)
			for i in 5:
				var r := _box(n, Vector3(0.09, 1.0, 0.06), Vector3(x0 + w * 0.64 + i * 0.26, y + 2.25, BZ + 0.08), _mat(Color(0.18, 0.18, 0.2), light, 0.01), false)
				r.rotation.z = 0.25
			_box(n, Vector3(1.5, 0.08, 0.1), Vector3(x0 + w * 0.76, y + 1.75, BZ + 0.08), wood, false)
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


## 방 오른쪽 벽 안쪽 x
func x1_in(b: Dictionary) -> float:
	return float(b.x1) - WALL


## 주크박스 (공용실 오른쪽 빈 곳): 몸통 · 둥근 윗부분 · 무지개 발광 띠 · 스피커 망 · 레코드 창. at = 바닥 가운데
func _jukebox(n: Node3D, at: Vector3, light: String) -> void:
	var W := 0.9
	var H := 1.25
	var D := 0.6
	var body := _mat(Color(0.42, 0.16, 0.12), light, 0.018)
	var chrome := _mat(Color(0.82, 0.82, 0.86), light, 0.01)
	_box(n, Vector3(W, H, D), Vector3(at.x, at.y + H * 0.5, at.z), body)
	var top := CylinderMesh.new()   # 둥근 윗부분 (앞에서 보면 반원)
	top.top_radius = W * 0.5
	top.bottom_radius = W * 0.5
	top.height = D
	var mi := MeshInstance3D.new()
	mi.mesh = top
	mi.material_override = body
	mi.rotation_degrees.x = 90.0
	mi.position = Vector3(at.x, at.y + H, at.z)
	n.add_child(mi)
	var fz := at.z + D * 0.5 + 0.01
	var cols := [Color(1.0, 0.35, 0.35), Color(1.0, 0.8, 0.3), Color(0.4, 1.0, 0.6), Color(0.35, 0.8, 1.0), Color(0.85, 0.45, 1.0)]
	for i in cols.size():   # 앞면 발광 띠 (위 반원을 따라 세운 막대들)
		var a := PI * (0.15 + 0.7 * i / float(cols.size() - 1))
		var r := _box(n, Vector3(0.06, 0.42, 0.02), Vector3(at.x + cos(a) * W * 0.3, at.y + H + sin(a) * W * 0.18 - 0.05, fz), _glow(cols[i]), false)
		r.rotation.z = a - PI * 0.5
	_box(n, Vector3(W * 0.62, 0.3, 0.02), Vector3(at.x, at.y + H - 0.25, fz), _glow(Color(1.0, 0.85, 0.55)), false)   # 레코드 창
	_box(n, Vector3(W * 0.7, 0.55, 0.02), Vector3(at.x, at.y + 0.55, fz), _mat(Color(0.12, 0.1, 0.1), light, 0.01), false)   # 스피커 망
	for i in 4:
		_box(n, Vector3(W * 0.66, 0.025, 0.01), Vector3(at.x, at.y + 0.36 + i * 0.12, fz + 0.012), chrome, false)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.06, H, 0.04), Vector3(at.x + sx * (W * 0.5 - 0.03), at.y + H * 0.5, fz), _glow(Color(1.0, 0.6, 0.85)), false)
	jukebox = AABB(Vector3(at.x - W * 0.5, at.y, at.z - D * 0.5), Vector3(W, H + W * 0.5, D))


func _stairs(n: Node3D, fid: String, b: Dictionary, light: String) -> void:
	if not has_flight(fid):
		return
	var order := int(sim.data.facilities[fid].order)
	var ends := RoomRouteService.flight_ends(sim.data, fid)   # 아래 끝 / 위 끝 (px)
	var xl: float = ends.x / OutgameData.CELL_W * CELL_M
	var xh: float = ends.y / OutgameData.CELL_W * CELL_M
	var z := flight_z(order)
	var steps := 11
	var step_mat := _mat(Color(0.52, 0.52, 0.58), light, 0.01)
	var sw := absf(xh - xl) / steps
	var dir := signf(xh - xl)
	for i in steps:
		var top := (i + 1) * FLOOR_M / steps
		_box(n, Vector3(sw + 0.01, 0.16, 1.0), Vector3(xl + dir * (i + 0.5) * sw, b.y0 + top - 0.08, z), step_mat)
		_box(n, Vector3(sw + 0.01, top - 0.16, 0.06), Vector3(xl + dir * (i + 0.5) * sw, b.y0 + (top - 0.16) * 0.5, z + 0.5), _mat(Color(0.36, 0.36, 0.42), light), false)
	# 난간 (계단 앞쪽, 노란 띠)
	var len := sqrt(pow(xh - xl, 2) + FLOOR_M * FLOOR_M)
	var rail := _box(n, Vector3(len, 0.07, 0.07), Vector3((xl + xh) * 0.5, b.y0 + FLOOR_M * 0.5 + 0.9, z + 0.52), _mat(Color(0.95, 0.8, 0.2), light), false)
	rail.rotation.z = atan2(FLOOR_M, xh - xl)


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
	_lights[String(n.name)].append(s)


# ================================================================ 대원 조명 탐침 · 그림자
## 그 자리(발 위치 p, 키 height m)에 실제로 닿는 방 스폿 조명들 — 세기 순 [{color, intensity, from_right, behind, light}].
## 벽이 빛을 막으므로 그 방(x·y 상자) 안의 조명만. 전투(BattleView3D.light_probe)와 같은 형식이라 캐릭터 셰이더에 같은 식으로 넣음.
func light_probe(p: Vector3, height: float = 1.7) -> Array:
	var out: Array = []
	for fid in _lights:
		var b := room_box(fid)
		if p.x < float(b.x0) - 0.05 or p.x > float(b.x1) + 0.05 or p.y < float(b.y0) - 0.3 or p.y > float(b.y1):
			continue
		for light in _lights[fid]:
			if not is_instance_valid(light) or not light.visible:
				continue
			var acc := 0.0
			for hk in [0.25, 0.55, 0.85]:
				acc += _spot_at(light, p + Vector3(0, height * hk, 0))
			acc /= 3.0
			if acc > 0.001:
				var lv: Vector3 = (light.global_position - (p + Vector3(0, height * 0.6, 0))).normalized()
				out.append({"color": light.light_color, "intensity": acc, "from_right": light.global_position.x > p.x,
					"behind": lv.z < -0.2, "dx": light.global_position.x - p.x, "light": light})
	out.sort_custom(func(a, b): return a.intensity > b.intensity)
	return out


func _spot_at(light: SpotLight3D, q: Vector3) -> float:
	var L := light.global_position
	var to := q - L
	var dist := to.length()
	if dist < 0.01 or dist > light.spot_range:
		return 0.0
	var fwd := -light.global_transform.basis.z
	var edge := cos(deg_to_rad(light.spot_angle))
	var c := (to / dist).dot(fwd)
	if c <= edge:
		return 0.0
	var cone := clampf((c - edge) / maxf(1.0 - edge, 0.001) * 3.0, 0.0, 1.0)
	return light.light_energy * cone * sqrt(clampf(1.0 - dist / light.spot_range, 0.0, 1.0))


## target = 화면 가운데 점 (m), 직교 카메라가 위에서 pitch 만큼 내려다봄. size = 화면 세로에 들어가는 높이 (m, 작을수록 확대)
func set_camera(target: Vector3, size: float, pitch_deg: float) -> void:
	var p := deg_to_rad(pitch_deg)
	camera.size = size
	camera.position = target + Vector3(0.0, sin(p), cos(p)) * 30.0
	camera.look_at(target, Vector3.UP)
