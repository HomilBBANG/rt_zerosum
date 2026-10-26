class_name BaseWorldView
extends Node2D
## 기지 단면 그리기: 하늘·지면·흙, 시설(방) 내부, 잠금 방(검정), 오염, 마우스 강조.
## 미국 카툰풍 단순 셀 셰이딩 — 방마다 원색 조명 한 쌍(전투 조명 프리셋 g1~g4)을 단단한 경계의 색면으로.
## 대원 말풍선도 여기서 그린다 (클릭 판정은 BaseHub).

const OUTLINE := Color(0.06, 0.05, 0.08)
const LOCKED := Color(0.0, 0.0, 0.0)

var sim: BaseSim
var hover_fid: String = ""
var pick_mode: bool = false        # 청소 장소 고르는 중 → 청소 가능한 방 강조
var bubble_rects: Dictionary = {}  # chat key → Rect2 (월드 좌표, 클릭 판정용)
var _font: Font
var _bold: Font
var _t: float = 0.0


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var d := sim.data
	var br := d.base_rect()
	_draw_surroundings(br)
	for fid in d.facility_order:
		_draw_facility(fid)
	_draw_floor_labels(br)
	_draw_bubbles()


# ---------------------------------------------------------------- 바깥
func _draw_surroundings(br: Rect2) -> void:
	var d := sim.data
	var ground_y := OutgameData.FLOOR_H   # 지상 1층 바닥 = 지면
	var left := br.position.x - 1400.0
	var right := br.end.x + 1400.0
	# 하늘 (단순 색면 3단)
	draw_rect(Rect2(left, -900, right - left, 900 + ground_y), Color(0.98, 0.55, 0.36))
	draw_rect(Rect2(left, -900, right - left, 520), Color(0.97, 0.42, 0.42))
	draw_rect(Rect2(left, -900, right - left, 260), Color(0.62, 0.30, 0.55))
	# 먼 언덕 실루엣
	var hills := PackedVector2Array([Vector2(left, ground_y)])
	for i in 13:
		var x := left + i * (right - left) / 12.0
		hills.append(Vector2(x, ground_y - 80 - 60 * absf(sin(i * 1.7))))
	hills.append(Vector2(right, ground_y))
	draw_colored_polygon(hills, Color(0.36, 0.20, 0.38))
	# 지면·흙 (지하층 둘레)
	draw_rect(Rect2(left, ground_y, right - left, 1600), Color(0.24, 0.14, 0.12))
	draw_rect(Rect2(left, ground_y, right - left, 18), Color(0.46, 0.62, 0.22))
	draw_rect(Rect2(left, ground_y + 18, right - left, 10), Color(0.30, 0.18, 0.12))
	# 바위 무늬
	for i in 40:
		var px := left + fmod(i * 397.0, right - left)
		var py := ground_y + 60 + fmod(i * 173.0, 900.0)
		if br.grow(30).has_point(Vector2(px, py)):
			continue
		draw_colored_polygon(PackedVector2Array([Vector2(px, py), Vector2(px + 40, py - 12), Vector2(px + 70, py + 6), Vector2(px + 28, py + 22)]), Color(0.19, 0.11, 0.10))
	# 건물 외벽: 지상층 지붕과 벽, 지하 콘크리트 테두리
	var top := Rect2(br.position.x - 14, -26, br.size.x + 28, 26 + ground_y)
	draw_rect(top, Color(0.20, 0.22, 0.28))
	draw_rect(Rect2(br.position.x - 30, -44, br.size.x + 60, 22), Color(0.12, 0.13, 0.18))
	draw_rect(Rect2(br.position.x - 30, -44, br.size.x + 60, 22), OUTLINE, false, 3.0)
	var under := Rect2(br.position.x - 14, ground_y, br.size.x + 28, br.end.y - ground_y + 14)
	draw_rect(under, Color(0.16, 0.16, 0.20))
	# 비어 있는 칸 (방이 없는 자리) = 흙
	for f in d.floors:
		for c in range(floori(br.position.x / OutgameData.CELL_W), ceili(br.end.x / OutgameData.CELL_W)):
			var cell := Rect2(c * OutgameData.CELL_W, f.order * OutgameData.FLOOR_H, OutgameData.CELL_W, OutgameData.FLOOR_H)
			if d.facility_at(cell.get_center()) == "":
				draw_rect(cell.grow(-2), Color(0.20, 0.12, 0.10) if f.order > 0 else Color(0.20, 0.22, 0.28))



## 층 이름표 (각 층 왼쪽 아래) — 방 위에 그려야 하므로 시설 다음에 호출
func _draw_floor_labels(br: Rect2) -> void:
	for f in sim.data.floors:
		var y: float = (f.order + 1) * OutgameData.FLOOR_H - 8
		var w := _bold.get_string_size(f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_rect(Rect2(br.position.x + 6, y - 24, w + 16, 26), Color(0.95, 0.85, 0.2))
		draw_rect(Rect2(br.position.x + 6, y - 24, w + 16, 26), OUTLINE, false, 2.0)
		draw_string(_bold, Vector2(br.position.x + 14, y - 5), f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, OUTLINE)


# ---------------------------------------------------------------- 시설
func _draw_facility(fid: String) -> void:
	var d := sim.data
	var f: Dictionary = d.facilities[fid]
	var r := d.facility_rect(fid)
	var inner := r.grow(-4)
	if not sim.is_unlocked(fid):
		draw_rect(inner, LOCKED)
		var c := inner.get_center()
		_draw_lock(c + Vector2(0, -14))
		_text(c + Vector2(0, 36), "$%d" % f.cost, 22, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, _bold)
		if fid == hover_fid:
			draw_rect(inner, Color(1, 0.85, 0.3), false, 3.0)
			_text(c + Vector2(0, 62), "클릭: 해금", 15, Color(1, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
		return
	var p := LightingPresets.get_preset(f.light)
	var wall: Color = (p.ambient as Color).darkened(0.30)
	var shade: Color = (p.shadow as Color).lerp(wall, 0.35)
	var key: Color = p.key
	var acc: Color = p.accent
	draw_rect(inner, wall)
	# 그림자 면 (왼쪽 아래 사선) — 셀 경계
	var floor_y := inner.end.y - OutgameData.FLOOR_SLAB + 4
	draw_colored_polygon(PackedVector2Array([inner.position, Vector2(inner.position.x + inner.size.x * 0.22, inner.position.y),
		Vector2(inner.position.x + inner.size.x * 0.08, floor_y), Vector2(inner.position.x, floor_y)]), shade)
	# 벽 띠
	draw_rect(Rect2(inner.position.x, floor_y - 46, inner.size.x, 8), wall.darkened(0.25))
	if f.tag == "계단":
		_draw_stairs(inner, floor_y, p)
	elif f.tag == "출입":
		_draw_gate(inner, floor_y, p)
	else:
		# 천장 조명 원뿔 (핑크/빨강/주황/시안 원색) — 단단한 경계
		var lx := inner.position.x + inner.size.x * 0.62
		var spread := inner.size.x * 0.34
		draw_colored_polygon(PackedVector2Array([Vector2(lx - 16, inner.position.y + 12), Vector2(lx + 16, inner.position.y + 12),
			Vector2(lx + spread, floor_y), Vector2(lx - spread, floor_y)]), Color(key.r, key.g, key.b, 0.34))
		draw_rect(Rect2(lx - 22, inner.position.y + 4, 44, 10), OUTLINE)
		draw_rect(Rect2(lx - 16, inner.position.y + 10, 32, 5), key.lightened(0.4))
		_draw_furniture(f, inner, floor_y, p)
	# 바닥 슬래브 / 천장
	draw_rect(Rect2(inner.position.x, floor_y, inner.size.x, inner.end.y - floor_y), Color(0.13, 0.12, 0.16))
	draw_rect(Rect2(inner.position.x, floor_y, inner.size.x, 4), acc.darkened(0.15))
	draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x, 6), Color(0.10, 0.10, 0.13))
	# 오염
	for dd in sim.dirt_in(fid):
		_draw_dirt(Vector2(inner.position.x + inner.size.x * float(dd.x), floor_y), int(dd.kind))
	var clean := float(sim.cleanliness.get(fid, 100.0))
	if f.cleanable and clean < 60.0:
		draw_rect(inner, Color(0.35, 0.22, 0.05, (60.0 - clean) / 60.0 * 0.35))
	# 이름표
	var label: String = f.name
	var plate_col := Color(0.05, 0.06, 0.09, 0.85)
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var plate := Rect2(inner.position.x + 8, inner.position.y + 12, tw + 16 + (54 if f.cleanable else 0), 24)
	draw_rect(plate, plate_col)
	_text(plate.position + Vector2(8, 18), label, 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT)
	if f.cleanable:
		var cc := Color(0.45, 1.0, 0.55) if clean >= 80.0 else (Color(1.0, 0.85, 0.3) if clean >= 50.0 else Color(1.0, 0.4, 0.3))
		_text(plate.position + Vector2(tw + 16, 18), "청결 %d" % roundi(clean), 13, cc, HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(inner, OUTLINE, false, 3.0)
	if pick_mode and f.cleanable:
		draw_rect(inner.grow(-3), Color(1, 0.9, 0.2, 0.5 + 0.3 * sin(_t * 6.0)), false, 4.0)
	if fid == hover_fid:
		draw_rect(inner.grow(-1), Color(1, 1, 1, 0.75), false, 2.0)


func _draw_lock(c: Vector2) -> void:
	var col := Color(0.55, 0.55, 0.58)
	draw_arc(c + Vector2(0, -10), 13, PI, TAU, 16, col, 5.0)
	draw_rect(Rect2(c + Vector2(-19, -10), Vector2(38, 30)), col)
	draw_circle(c + Vector2(0, 3), 4, Color(0, 0, 0))


func _box(r: Rect2, col: Color, outline := true) -> void:
	draw_rect(r, col)
	if outline:
		draw_rect(r, OUTLINE, false, 2.5)


func _draw_furniture(f: Dictionary, inner: Rect2, floor_y: float, p: Dictionary) -> void:
	var x0 := inner.position.x
	var w := inner.size.x
	var key: Color = p.key
	var acc: Color = p.accent
	var amb: Color = p.ambient
	match str(f.tag):
		"행정":
			# 책상 2개 + 모니터 + 의뢰 게시판
			for i in 2:
				var dx := x0 + w * (0.18 + i * 0.42)
				_box(Rect2(dx, floor_y - 38, 92, 12), amb.darkened(0.45))
				_box(Rect2(dx + 6, floor_y - 26, 8, 26), amb.darkened(0.6))
				_box(Rect2(dx + 78, floor_y - 26, 8, 26), amb.darkened(0.6))
				_box(Rect2(dx + 26, floor_y - 74, 44, 30), Color(0.1, 0.1, 0.14))
				draw_rect(Rect2(dx + 30, floor_y - 70, 36, 22), acc.lightened(0.2))
			_box(Rect2(x0 + w * 0.40, inner.position.y + 52, 96, 62), Color(0.55, 0.36, 0.22))
			for i in 4:
				draw_rect(Rect2(x0 + w * 0.40 + 8 + (i % 2) * 44, inner.position.y + 60 + floori(i / 2.0) * 26, 36, 20), [Color(1, 0.95, 0.7), Color(0.8, 1, 0.9), Color(1, 0.8, 0.85), Color(0.85, 0.9, 1)][i])
		"공용":
			if str(f.id).contains("mess"):
				_box(Rect2(x0 + w * 0.12, floor_y - 40, w * 0.5, 12), Color(0.62, 0.40, 0.24))
				_box(Rect2(x0 + w * 0.15, floor_y - 18, w * 0.44, 8), Color(0.45, 0.28, 0.18))
				_box(Rect2(x0 + w * 0.70, floor_y - 62, w * 0.24, 62), amb.darkened(0.5))
				draw_rect(Rect2(x0 + w * 0.72, floor_y - 58, w * 0.20, 10), key.lightened(0.3))
			elif str(f.id).contains("storage"):
				for i in 5:
					var cx := x0 + w * (0.1 + i * 0.16)
					var h := 34.0 + (i % 3) * 22.0
					_box(Rect2(cx, floor_y - h, 52, h), Color(0.55, 0.42, 0.25))
					draw_line(Vector2(cx, floor_y - h), Vector2(cx + 52, floor_y), OUTLINE, 2.0)
			else:
				# 소파 + 탁자 + 벽 포스터
				_box(Rect2(x0 + w * 0.10, floor_y - 44, 130, 30), key.darkened(0.35))
				_box(Rect2(x0 + w * 0.10, floor_y - 66, 130, 24), key.darkened(0.5))
				_box(Rect2(x0 + w * 0.10 - 10, floor_y - 52, 14, 52), key.darkened(0.55))
				_box(Rect2(x0 + w * 0.10 + 126, floor_y - 52, 14, 52), key.darkened(0.55))
				_box(Rect2(x0 + w * 0.55, floor_y - 30, 80, 10), amb.darkened(0.4))
				_box(Rect2(x0 + w * 0.55 + 34, floor_y - 20, 12, 20), amb.darkened(0.55))
				_box(Rect2(x0 + w * 0.70, inner.position.y + 50, 70, 56), Color(0.12, 0.12, 0.16))
				draw_rect(Rect2(x0 + w * 0.70 + 5, inner.position.y + 55, 60, 46), acc)
		"생활":
			# 2층 침대 2개 + 사물함
			for i in 2:
				var bx := x0 + w * (0.08 + i * 0.36)
				for lvl in 2:
					var by := floor_y - 24 - lvl * 58
					_box(Rect2(bx, by - 12, 118, 12), Color(0.85, 0.85, 0.9))
					_box(Rect2(bx, by, 118, 8), amb.darkened(0.5))
				_box(Rect2(bx - 4, floor_y - 100, 8, 100), amb.darkened(0.6))
				_box(Rect2(bx + 114, floor_y - 100, 8, 100), amb.darkened(0.6))
			for i in 3:
				_box(Rect2(x0 + w * 0.82 + i * 22, floor_y - 92, 20, 92), amb.darkened(0.45))
		"작업":
			_box(Rect2(x0 + w * 0.12, floor_y - 44, w * 0.42, 14), Color(0.48, 0.32, 0.20))
			_box(Rect2(x0 + w * 0.14, floor_y - 30, 10, 30), Color(0.3, 0.3, 0.34))
			_box(Rect2(x0 + w * 0.50, floor_y - 30, 10, 30), Color(0.3, 0.3, 0.34))
			_box(Rect2(x0 + w * 0.12, inner.position.y + 52, w * 0.42, 70), Color(0.42, 0.36, 0.30))
			for i in 6:
				draw_line(Vector2(x0 + w * 0.16 + i * 26, inner.position.y + 62), Vector2(x0 + w * 0.16 + i * 26, inner.position.y + 102), Color(0.8, 0.8, 0.85), 4.0)
			_box(Rect2(x0 + w * 0.68, floor_y - 52, 70, 52), Color(0.25, 0.26, 0.30))
			draw_rect(Rect2(x0 + w * 0.68 + 10, floor_y - 44, 50, 8), key)
			if not sim.workshop.is_empty():
				var spark := 0.5 + 0.5 * sin(_t * 12.0)
				draw_circle(Vector2(x0 + w * 0.68 + 35, floor_y - 60), 6 + 4 * spark, Color(1, 0.85, 0.3, 0.9))
		"훈련":
			# 샌드백 + 역기 랙 + 매트
			var bx := x0 + w * 0.2
			draw_line(Vector2(bx, inner.position.y + 6), Vector2(bx, inner.position.y + 50), OUTLINE, 3.0)
			_box(Rect2(bx - 20, inner.position.y + 50, 40, 86), key.darkened(0.3))
			_box(Rect2(x0 + w * 0.45, floor_y - 10, w * 0.4, 10), acc.darkened(0.4))
			_box(Rect2(x0 + w * 0.72, floor_y - 70, 8, 70), Color(0.3, 0.3, 0.34))
			_box(Rect2(x0 + w * 0.90, floor_y - 70, 8, 70), Color(0.3, 0.3, 0.34))
			_box(Rect2(x0 + w * 0.66, floor_y - 74, w * 0.30, 6), Color(0.55, 0.55, 0.6))
			draw_circle(Vector2(x0 + w * 0.68, floor_y - 71), 14, OUTLINE)
			draw_circle(Vector2(x0 + w * 0.94, floor_y - 71), 14, OUTLINE)
		_:
			# 미정 구역: 봉인 테이프 + 상자
			for i in 3:
				_box(Rect2(x0 + w * (0.15 + i * 0.25), floor_y - 46, 56, 46), Color(0.40, 0.40, 0.44))
			for i in 2:
				draw_line(Vector2(x0 + 10, inner.position.y + 60 + i * 30), Vector2(x0 + w - 10, inner.position.y + 80 + i * 30), Color(1, 0.85, 0.1), 8.0)


func _draw_stairs(inner: Rect2, floor_y: float, p: Dictionary) -> void:
	var steps := 8
	var sw := inner.size.x / steps
	var col: Color = (p.ambient as Color).darkened(0.5)
	for i in steps:
		var h := (i + 1) * (floor_y - inner.position.y - 20) / steps
		draw_rect(Rect2(inner.position.x + i * sw, floor_y - h, sw + 1, h), col.lightened(0.04 * i))
	draw_line(Vector2(inner.position.x, floor_y - 40), Vector2(inner.end.x, inner.position.y + 30), OUTLINE, 3.0)
	draw_line(Vector2(inner.position.x + inner.size.x * 0.5, inner.position.y), Vector2(inner.position.x + inner.size.x * 0.5, inner.end.y), Color(1, 1, 1, 0.08), inner.size.x * 0.35)


func _draw_gate(inner: Rect2, floor_y: float, p: Dictionary) -> void:
	# 바깥으로 열린 문 — 노을빛이 들어옴
	draw_rect(Rect2(inner.position.x, inner.position.y + 30, inner.size.x * 0.55, floor_y - inner.position.y - 30), Color(0.98, 0.62, 0.40))
	draw_colored_polygon(PackedVector2Array([Vector2(inner.position.x + inner.size.x * 0.55, inner.position.y + 30), Vector2(inner.end.x, floor_y - 10),
		Vector2(inner.end.x, floor_y), Vector2(inner.position.x + inner.size.x * 0.55, floor_y)]), Color(0.98, 0.62, 0.40, 0.35))
	_box(Rect2(inner.position.x + inner.size.x * 0.55, inner.position.y + 26, 14, floor_y - inner.position.y - 26), Color(0.35, 0.36, 0.42))
	_text(Vector2(inner.get_center().x, inner.position.y + 50), "EXIT", 16, Color(0.3, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, _bold)


func _draw_dirt(at: Vector2, kind: int) -> void:
	match kind:
		0:   # 얼룩
			var pts := PackedVector2Array()
			for i in 10:
				var a := TAU * i / 10.0
				pts.append(at + Vector2(cos(a) * (26 + 6 * sin(i * 2.3)), sin(a) * 6 - 2))
			draw_colored_polygon(pts, Color(0.30, 0.22, 0.08))
		1:   # 쓰레기 봉투
			draw_circle(at + Vector2(0, -16), 16, Color(0.12, 0.12, 0.14))
			draw_circle(at + Vector2(0, -16), 16, OUTLINE, false, 2.0)
			draw_line(at + Vector2(-4, -32), at + Vector2(4, -36), Color(0.9, 0.8, 0.2), 3.0)
		_:   # 깡통·종이
			draw_rect(Rect2(at + Vector2(-18, -14), Vector2(12, 14)), Color(0.75, 0.75, 0.8))
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -2), at + Vector2(20, -8), at + Vector2(24, 0), at + Vector2(4, 2)]), Color(0.95, 0.95, 0.85))
	# 파리
	var fl := at + Vector2(sin(_t * 5.0 + at.x) * 14, -40 + cos(_t * 7.0 + at.x) * 8)
	draw_circle(fl, 2.5, OUTLINE)


# ---------------------------------------------------------------- 말풍선
func _draw_bubbles() -> void:
	bubble_rects.clear()
	for ch in sim.chats:
		var a: NpcAgent = sim.npcs.get(ch.a)
		var b: NpcAgent = sim.npcs.get(ch.b)
		if a == null or b == null:
			continue
		var top := minf(a.pos.y, b.pos.y) - NpcView.height_of(maxf(a.height_cm, b.height_cm)) - 40
		var c := Vector2((a.pos.x + b.pos.x) * 0.5, top)
		var r := Rect2(c - Vector2(34, 20), Vector2(68, 36))
		bubble_rects[ch.key] = r
		var bob := sin(_t * 3.0) * 2.0
		r.position.y += bob
		draw_rect(r, Color(1, 1, 1))
		draw_rect(r, OUTLINE, false, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 8, r.end.y), Vector2(c.x + 8, r.end.y), Vector2(c.x - 2, r.end.y + 12)]), Color(1, 1, 1))
		for i in 3:
			var on := int(_t * 3.0) % 3 >= i
			draw_circle(Vector2(c.x - 16 + i * 16, c.y + bob - 2), 5, OUTLINE if on else Color(0.6, 0.6, 0.6))


func _text(pos: Vector2, s: String, size: int, col: Color, align: int, font: Font = null) -> void:
	var fnt := font if font != null else _font
	var w := -1.0
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		w = fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		w = fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w
	draw_string_outline(fnt, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.75))
	draw_string(fnt, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
