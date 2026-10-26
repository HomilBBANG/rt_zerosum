class_name BaseOverlay
extends Node2D
## 3D 기지 위에 화면 좌표로 그리는 2D 덮개 (3D 카메라로 투영).
## mode "under": 방 이름표·청결, 잠긴 방 자물쇠·가격, 마우스 강조, 청소 장소 고르기 강조, 오염, 층 이름표 — 대원보다 아래.
## mode "over": 대원끼리 대화 말풍선 — 대원보다 위. 말풍선 화면 사각형은 클릭 판정용으로 bubble_rects 에 남긴다.

const OUTLINE := Color(0.06, 0.05, 0.08)

var sim: BaseSim
var v3d: BaseView3D
var hub: Node
var mode: String = "under"
var hover_fid: String = ""
var pick_mode: bool = false
var move_mark: Dictionary = {}       # 이동 목표 표시 {pos, t, run} (BaseHub 가 채움)
var bubble_rects: Dictionary = {}   # chat key → Rect2 (화면)
var _font: Font
var _bold: Font
var _t: float = 0.0


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func proj(p: Vector3) -> Vector2:
	return hub.project(p)


## 시설 단면(앞면) 사각형의 화면 다각형 — 클릭 판정·강조
func front_quad(fid: String) -> PackedVector2Array:
	var b := v3d.room_box(fid)
	var z := BaseView3D.FRONT_Z
	return PackedVector2Array([proj(Vector3(b.x0, b.y0, z)), proj(Vector3(b.x1, b.y0, z)), proj(Vector3(b.x1, b.y1, z)), proj(Vector3(b.x0, b.y1, z))])


func facility_at_screen(p: Vector2) -> String:
	for fid in sim.data.facility_order:
		if Geometry2D.is_point_in_polygon(p, front_quad(fid)):
			return fid
	return ""


func _draw() -> void:
	if sim == null or v3d == null:
		return
	if mode == "over":
		_draw_bubbles()
		return
	for fid in sim.data.facility_order:
		_draw_room(fid)
	_draw_floor_labels()
	_draw_move_mark()


func _draw_room(fid: String) -> void:
	var f: Dictionary = sim.data.facilities[fid]
	var b := v3d.room_box(fid)
	var q := front_quad(fid)
	if not sim.is_unlocked(fid):
		var c := (q[0] + q[2]) * 0.5
		var k := clampf((q[1].x - q[0].x) / float(maxi(1, int(f.width))) / 160.0, 0.45, 1.4)
		_draw_lock(c + Vector2(0, -12 * k), k)
		_text(c + Vector2(0, 30 * k), "$%d" % f.cost, int(22 * k), Color(0.85, 0.85, 0.85), _bold)
		if fid == hover_fid:
			draw_polyline(_closed(q), Color(1, 0.85, 0.3), 3.0)
			_text(c + Vector2(0, 54 * k), "클릭: 해금", int(15 * k), Color(1, 0.85, 0.3), _font)
		return
	# 오염 (바닥 위, 방 폭 비율 위치)
	for dd in sim.dirt_in(fid):
		var w := Vector3(lerpf(b.x0 + 0.4, b.x1 - 0.4, float(dd.x)), b.y0 + 0.06, -0.15)
		var at := proj(w)
		var ppm := (proj(w + Vector3.UP) - at).length()
		_draw_dirt(at, int(dd.kind), ppm / 70.0)
	# 이름표 (단면 앞 왼쪽 위 — 위층 슬래브에 가리지 않게)
	var plate_at := q[3] + Vector2(6, 5)
	var label: String = f.name
	var size := 14
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var clean := float(sim.cleanliness.get(fid, 100.0))
	var extra := 0.0
	if f.cleanable:
		extra = _font.get_string_size("청결 100", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8
	draw_rect(Rect2(plate_at, Vector2(tw + 14 + extra, 22)), Color(0.05, 0.06, 0.09, 0.85))
	draw_string(_font, plate_at + Vector2(7, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1))
	if f.cleanable:
		var cc := Color(0.45, 1.0, 0.55) if clean >= 80.0 else (Color(1.0, 0.85, 0.3) if clean >= 50.0 else Color(1.0, 0.4, 0.3))
		draw_string(_font, plate_at + Vector2(tw + 14, 16), "청결 %d" % roundi(clean), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cc)
		if clean < 60.0:   # 더러운 방은 단면 테두리를 갈색으로
			draw_polyline(_closed(q), Color(0.55, 0.35, 0.1, 0.4 + 0.3 * (60.0 - clean) / 60.0), 4.0)
	if pick_mode and f.cleanable:
		draw_polyline(_closed(q), Color(1, 0.9, 0.2, 0.5 + 0.35 * sin(_t * 6.0)), 4.0)
	if fid == hover_fid:
		draw_polyline(_closed(q), Color(1, 1, 1, 0.8), 2.0)
	if f.tag == "작업" and not sim.workshop.is_empty():
		var sp := proj(Vector3(b.x0 + (b.x1 - b.x0) * 0.78, b.y0 + 1.5, BaseView3D.BACK_Z + 0.5))
		draw_circle(sp, 5 + 4 * (0.5 + 0.5 * sin(_t * 12.0)), Color(1, 0.85, 0.3, 0.9))


func _closed(q: PackedVector2Array) -> PackedVector2Array:
	var c := q.duplicate()
	c.append(q[0])
	return c


func _draw_floor_labels() -> void:
	var bb := v3d.base_bounds()
	for f in sim.data.floors:
		var y0: float = -float(f.order) * BaseView3D.FLOOR_M
		var at := proj(Vector3(bb.position.x - 0.6, y0 + 0.2, BaseView3D.FRONT_Z + 0.3))
		var w := _bold.get_string_size(f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var r := Rect2(at - Vector2(w + 18, 24), Vector2(w + 14, 24))
		r.position.x = maxf(r.position.x, 8.0)   # 축소해도 화면 밖으로 안 나가게
		draw_rect(r, Color(0.95, 0.85, 0.2))
		draw_rect(r, OUTLINE, false, 2.0)
		draw_string(_bold, r.position + Vector2(7, 18), f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, OUTLINE)


func _draw_lock(c: Vector2, k: float) -> void:
	var col := Color(0.55, 0.55, 0.58)
	draw_arc(c + Vector2(0, -10) * k, 13 * k, PI, TAU, 16, col, 5.0 * k)
	draw_rect(Rect2(c + Vector2(-19, -10) * k, Vector2(38, 30) * k), col)
	draw_circle(c + Vector2(0, 3) * k, 4 * k, Color(0, 0, 0))


func _draw_dirt(at: Vector2, kind: int, k: float) -> void:
	draw_set_transform(at, 0.0, Vector2(k, k))
	match kind:
		0:
			var pts := PackedVector2Array()
			for i in 10:
				var a := TAU * i / 10.0
				pts.append(Vector2(cos(a) * (30 + 7 * sin(i * 2.3)), sin(a) * 8))
			draw_colored_polygon(pts, Color(0.30, 0.22, 0.08, 0.92))
		1:
			draw_circle(Vector2(0, -18), 18, Color(0.12, 0.12, 0.14))
			draw_circle(Vector2(0, -18), 18, OUTLINE, false, 2.0)
			draw_line(Vector2(-4, -35), Vector2(4, -40), Color(0.9, 0.8, 0.2), 3.0)
		_:
			draw_rect(Rect2(Vector2(-20, -16), Vector2(13, 16)), Color(0.75, 0.75, 0.8))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -2), Vector2(22, -9), Vector2(26, 0), Vector2(4, 3)]), Color(0.95, 0.95, 0.85))
	var fl := Vector2(sin(_t * 5.0 + at.x) * 15, -44 + cos(_t * 7.0 + at.x) * 8)
	draw_circle(fl, 2.6, OUTLINE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bubbles() -> void:
	bubble_rects.clear()
	for ch in sim.chats:
		var va: NpcView = hub.npc_views.get(ch.a)
		var vb: NpcView = hub.npc_views.get(ch.b)
		if va == null or vb == null:
			continue
		var top := minf(va.position.y - va.screen_h, vb.position.y - vb.screen_h) - 34.0
		var c := Vector2((va.position.x + vb.position.x) * 0.5, top)
		var r := Rect2(c - Vector2(32, 18), Vector2(64, 34))
		bubble_rects[ch.key] = r
		var bob := sin(_t * 3.0) * 2.0
		r.position.y += bob
		draw_rect(r, Color(1, 1, 1))
		draw_rect(r, OUTLINE, false, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 8, r.end.y), Vector2(c.x + 8, r.end.y), Vector2(c.x - 2, r.end.y + 12)]), Color(1, 1, 1))
		for i in 3:
			var on := int(_t * 3.0) % 3 >= i
			draw_circle(Vector2(c.x - 15 + i * 15, c.y + bob - 1), 5, OUTLINE if on else Color(0.6, 0.6, 0.6))


func _text(pos: Vector2, s: String, size: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, 0)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.75))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## 방 클릭 = 이동 목표 표시: 걷기 = 초록 고리 하나, 뛰기(더블클릭) = 주황 고리 둘 + 빠르게 퍼짐
func _draw_move_mark() -> void:
	if move_mark.is_empty():
		return
	var t := float(move_mark.t) / 0.9
	var col := Color(1.0, 0.62, 0.2) if move_mark.get("run", false) else Color(0.45, 1.0, 0.6)
	var p: Vector2 = move_mark.pos
	var a := 1.0 - t
	draw_set_transform(p, 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, 10.0 + t * 26.0, 0.0, TAU, 32, Color(col, a), 3.0)
	if move_mark.get("run", false):
		draw_arc(Vector2.ZERO, 4.0 + t * 40.0, 0.0, TAU, 32, Color(col, a * 0.8), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(col, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
