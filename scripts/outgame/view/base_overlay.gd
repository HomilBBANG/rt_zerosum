class_name BaseOverlay
extends Node2D
## 3D 기지 위에 화면 좌표로 그리는 2D 덮개 (3D 카메라로 투영).
## mode "under": 방 이름표, 잠긴 방 자물쇠·가격, 마우스 강조, 층 이름표 — 대원보다 아래.
## mode "over": 대원끼리 대화 말풍선 — 대원보다 위. 말풍선 화면 사각형은 클릭 판정용으로 bubble_rects 에 남긴다.

const OUTLINE := Color(0.06, 0.05, 0.08)

var sim: BaseSim
var v3d: BaseView3D
var hub: Node
var mode: String = "under"
var hover_fid: String = ""
var juke_hover := false   # 마우스가 주크박스 위 (대원 선택 없음) → 테두리 + "음악"
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
	_draw_floor_frames()
	for fid in sim.data.facility_order:
		_draw_room(fid)
	_draw_floor_labels()
	_draw_move_mark()
	if juke_hover:
		var jr: Rect2 = hub.jukebox_rect()
		draw_rect(jr, Color(1, 0.85, 0.3, 0.9), false, 2.0)
		_text(Vector2(jr.get_center().x, jr.position.y - 6), "클릭: 음악", 14, Color(1, 0.85, 0.3), _font)


func _draw_room(fid: String) -> void:
	var f: Dictionary = sim.data.facilities[fid]
	var b := v3d.room_box(fid)
	var q := front_quad(fid)
	if not sim.is_unlocked(fid):
		_locked_panel(q)   # 잠긴 방 = 볼트 달린 검은 패널 (UI 패키지, 원본 art_src/ui/locked_room_panel.webp)
		var c := (q[0] + q[2]) * 0.5
		var k := clampf((q[1].x - q[0].x) / float(maxi(1, int(f.width))) / 160.0, 0.45, 1.4)
		_draw_lock(c + Vector2(0, -12 * k), k)
		_text(c + Vector2(0, 30 * k), "$%d" % f.cost, int(22 * k), Color(0.85, 0.85, 0.85), _bold)
		if fid == hover_fid:
			draw_polyline(_closed(q), Color(1, 0.85, 0.3), 3.0)
			_text(c + Vector2(0, 54 * k), "클릭: 해금", int(15 * k), Color(1, 0.85, 0.3), _font)
		return
	# 이름표 = 방 왼쪽 위 모서리에 딱 맞춤 (방이 좁으면 글자를 줄이고 잘라 방 밖으로 안 나가게)
	var plate_at := _quad_rect(q).position
	var label: String = f.name
	var size := 10   # 이름표 0.7배 (예전 14)
	var room_w: float = _quad_rect(q).size.x
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	while tw + 25 > room_w and size > 7:
		size -= 1
		tw = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pw := minf(tw + 25, room_w)
	_plate(Rect2(plate_at, Vector2(pw, 20)))   # 방 이름표 = 사용자 제공 패널 (오른쪽 아래만 비스듬히 잘림)
	draw_string(_font, plate_at + Vector2(10, 14), label, HORIZONTAL_ALIGNMENT_LEFT, pw - 18, size, Color(0.95, 0.94, 0.9))
	if fid == hover_fid:
		draw_polyline(_closed(q), Color(1.0, 0.95, 0.8, 0.95), 3.0)   # 마우스를 올린 방 = 크림색 테두리 (최종 시안)
	if f.tag == "작업" and not sim.workshop.is_empty():
		var sp := proj(Vector3(b.x0 + (b.x1 - b.x0) * 0.78, b.y0 + 1.5, BaseView3D.BACK_Z + 0.5))
		draw_circle(sp, 5 + 4 * (0.5 + 0.5 * sin(_t * 12.0)), Color(1, 0.85, 0.3, 0.9))


func _closed(q: PackedVector2Array) -> PackedVector2Array:
	var c := q.duplicate()
	c.append(q[0])
	return c


## 층 표시 (UI 패키지 v2 태그): 지금 보는 층(마우스를 올린 방 · 선택한 대원의 층, 없으면 맨 위 층) = 금색 태그, 나머지 = 어두운 태그
func _draw_floor_labels() -> void:
	var bb := v3d.base_bounds()
	var active := ""
	if hover_fid != "":
		active = str(sim.data.facilities[hover_fid].floor)
	elif hub.selected != "" and sim.npcs.has(hub.selected):
		active = str(sim.data.facilities.get(sim.npcs[hub.selected].facility, {}).get("floor", ""))
	elif not sim.data.floors.is_empty():
		active = str(sim.data.floors[0].id)
	for f in sim.data.floors:
		var y0: float = -float(f.order) * BaseView3D.FLOOR_M
		var at := proj(Vector3(bb.position.x - 0.6, y0 + 0.2, BaseView3D.FRONT_Z + 0.3))
		var on: bool = str(f.id) == active
		var w := _bold.get_string_size(f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var r := Rect2(at - Vector2(w + 38, 34), Vector2(w + 38, 34))
		r.position.x = maxf(r.position.x, 8.0)   # 축소해도 화면 밖으로 안 나가게
		_tag(r, on)
		draw_string(_bold, r.position + Vector2(19, 24), f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, OUTLINE if on else Color(0.95, 0.94, 0.9))


## 잠긴 방 앞면을 덮는 패널: 그 방 단면 사각형(조금 안쪽)에 9칸 늘리기 — 둥근 모서리 · 볼트는 그대로, 2배 해상도 그림을 반으로
static var _lock_sb: StyleBoxTexture
const LOCK_K := 0.15    # 잠긴 방 패널 그림 배율 (볼트 지름 ≈ 5px)
const FRAME_K := 0.28   # 층 테두리(ui-room) 그림 배율 (위 · 아래 띠 ≈ 20px, 볼트 ≈ 7px)
static var _frame_sb: StyleBoxTexture


## 층 테두리 (최종 시안): 층마다 그 층 방 전체를 ui-room 으로 감쌈 — 위 · 아래 띠는 층 사이 슬래브 쪽으로, 네 귀 볼트
func _draw_floor_frames() -> void:
	var rects: Array = []   # 위층부터 [Rect2]
	for f in sim.data.floors:
		var r := Rect2()
		var first := true
		for fid in sim.data.facility_order:
			if str(sim.data.facilities[fid].floor) != str(f.id):
				continue
			var qr := _quad_rect(front_quad(fid))
			r = qr if first else r.merge(qr)
			first = false
		if not first:
			rects.append(r)
	rects.sort_custom(func(a, b): return a.position.y < b.position.y)
	for i in rects.size():
		var r: Rect2 = rects[i]
		# 위 · 아래 띠는 옆 층과의 틈 절반까지만 → 층 테두리끼리 안 겹침 (맨 위 · 맨 아래는 틈 대신 같은 폭)
		var up: float = (r.position.y - (rects[i - 1] as Rect2).end.y) * 0.5 if i > 0 else -1.0
		var dn: float = ((rects[i + 1] as Rect2).position.y - r.end.y) * 0.5 if i < rects.size() - 1 else -1.0
		if up < 0.0:
			up = dn
		if dn < 0.0:
			dn = up
		_room_frame(r, maxf(0.0, up), maxf(0.0, dn))


## 사용자 제공 ui-room (원본 art_src/ui/room_frame.png): 사각형 r 을 감싸는 9칸 늘리기 테두리, 가운데는 비어 있음.
## 띠가 방 안을 덜 가리게 바깥쪽으로 조금 키워 그림 (위 · 아래 띠는 층 사이 슬래브 위)
func _room_frame(r: Rect2, up: float = 1e9, dn: float = 1e9) -> void:
	if _frame_sb == null:
		_frame_sb = StyleBoxTexture.new()
		_frame_sb.texture = load("res://assets/ui/outgame/v2/room_frame.png")
		_frame_sb.draw_center = false
		_frame_sb.set_texture_margin(SIDE_LEFT, 110)
		_frame_sb.set_texture_margin(SIDE_RIGHT, 110)
		_frame_sb.set_texture_margin(SIDE_TOP, 100)
		_frame_sb.set_texture_margin(SIDE_BOTTOM, 100)
	var k := clampf(minf(r.size.x, r.size.y) / 700.0, 0.08, FRAME_K)
	k = minf(k, minf(up, dn) / (76.0 * 0.75))   # 층 사이 틈이 좁으면 띠도 가늘게
	k = maxf(k, 0.04)
	r = r.grow_individual(34.0 * k * 0.6, minf(76.0 * k * 0.75, up), 34.0 * k * 0.6, minf(73.0 * k * 0.75, dn))
	draw_set_transform(r.position, 0.0, Vector2(k, k))
	draw_style_box(_frame_sb, Rect2(Vector2.ZERO, r.size / k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _quad_rect(q: PackedVector2Array) -> Rect2:
	var r := Rect2(q[0], Vector2.ZERO)
	for pt in q:
		r = r.expand(pt)
	return r


func _locked_panel(q: PackedVector2Array) -> void:
	if _lock_sb == null:
		_lock_sb = StyleBoxTexture.new()
		_lock_sb.texture = load("res://assets/ui/outgame/v2/panel_locked.png")
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			_lock_sb.set_texture_margin(side, 90)
	var r := _quad_rect(q).grow(-3.0)
	var k := clampf(minf(r.size.x, r.size.y) / 400.0, 0.08, LOCK_K)   # 레퍼런스처럼 볼트 = 작은 점 (아주 작게 축소하면 더 작게)
	draw_set_transform(r.position, 0.0, Vector2(k, k))
	draw_style_box(_lock_sb, Rect2(Vector2.ZERO, r.size / k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 방 이름 패널 (사용자 제공, 원본 art_src/ui/room_name_panel.webp): 오른쪽 아래 비스듬한 모서리 · 위 밝은 줄은 그대로, 9칸 늘리기
static var _plate_sb: StyleBoxTexture
const PLATE_K := 0.063   # 0.7배 (높이 20)


func _plate(r: Rect2) -> void:
	if _plate_sb == null:
		_plate_sb = StyleBoxTexture.new()
		_plate_sb.texture = load("res://assets/ui/outgame/v2/plate_room.png")
		_plate_sb.set_texture_margin(SIDE_LEFT, 40)
		_plate_sb.set_texture_margin(SIDE_TOP, 52)
		_plate_sb.set_texture_margin(SIDE_RIGHT, 145)
		_plate_sb.set_texture_margin(SIDE_BOTTOM, 150)
	draw_set_transform(r.position, 0.0, Vector2(PLATE_K, PLATE_K))
	draw_style_box(_plate_sb, Rect2(Vector2.ZERO, r.size / PLATE_K))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## UI 패키지 v2 태그 (금색 / 어두운 팔각 띠) — 2배 해상도 그림을 반으로, 9칸 늘리기
static var _tag_sb := {}


func _tag(r: Rect2, gold: bool) -> void:
	var key := "gold" if gold else "dark"
	if not _tag_sb.has(key):
		var sb := StyleBoxTexture.new()
		sb.texture = load("res://assets/ui/outgame/v2/tag_%s.png" % key)
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			sb.set_texture_margin(side, 24)
		for side in [SIDE_TOP, SIDE_BOTTOM]:
			sb.set_texture_margin(side, 22)
		_tag_sb[key] = sb
	draw_set_transform(r.position, 0.0, Vector2(0.5, 0.5))
	draw_style_box(_tag_sb[key], Rect2(Vector2.ZERO, r.size * 2.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_lock(c: Vector2, k: float) -> void:
	var col := Color(0.55, 0.55, 0.58)
	draw_arc(c + Vector2(0, -10) * k, 13 * k, PI, TAU, 16, col, 5.0 * k)
	draw_rect(Rect2(c + Vector2(-19, -10) * k, Vector2(38, 30) * k), col)
	draw_circle(c + Vector2(0, 3) * k, 4 * k, Color(0, 0, 0))


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
