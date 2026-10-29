@tool
extends Control
## 스토리 흐름 그림: StoryGraph 의 노드(상자)와 선(화살표)을 그림. 왼쪽 = 먼저, 오른쪽 = 나중.
## 노드 클릭 = 고르기 · 노드 끌기 = 자리 옮기기 · 빈 곳 끌기 = 화면 옮기기 · 휠 = 확대/축소 · 더블클릭 = 그 탭으로
## **Shift+노드에서 끌어 다른 노드에 놓기 = 선 긋기** (뜻은 panel 이 물어봄) · 선 클릭 = 선 고르기 · Delete = 고른 선/노드 지우기 (panel 이 처리)

signal node_clicked(id: String)
signal node_double_clicked(id: String)
signal node_moved(id: String, pos: Vector2)
signal edge_clicked(index: int)
signal link_requested(from_id: String, to_id: String)
signal delete_pressed()
signal background_clicked()

const COLORS := {
	"start": Color(0.42, 0.44, 0.52), "quest": Color(0.85, 0.62, 0.22), "cutscene": Color(0.36, 0.62, 0.92),
	"divine": Color(0.78, 0.45, 0.95), "mission": Color(0.40, 0.66, 0.46),
}

var graph: StoryGraph
var selected := ""
var selected_edge := -1
var hovered := ""
var hide_kinds: Dictionary = {}   # kind → true 면 숨김
var font: Font
var bold: Font
var offset := Vector2(0, 0)
var zoom := 1.0
var _drag_start := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _dragging := false            # 화면 옮기기
var _drag_node := ""              # 노드 옮기기
var _drag_node_from := Vector2.ZERO
var _link_from := ""              # Shift 끌기 선 긋기
var _link_pos := Vector2.ZERO
var _moved := false
var _edge_pts: Array = []         # 그린 선의 점들 (선 클릭 판정)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true   # 그림이 캔버스 밖(툴바 · 오른쪽 칸 · 에디터 메뉴)으로 넘치지 않게
	font = load("res://assets/fonts/Pretendard-Medium.ttf")
	bold = load("res://assets/fonts/Pretendard-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Pretendard-Bold.ttf") else font
	resized.connect(queue_redraw)


func show_graph(g: StoryGraph, sel: String) -> void:
	graph = g
	selected = sel
	if graph != null and selected_edge >= graph.edges.size():
		selected_edge = -1
	queue_redraw()


## 전체가 보이게 (처음 · '전체 보기')
func fit() -> void:
	if graph == null or graph.order.is_empty():
		return
	var b := graph.bounds().grow(30.0)
	zoom = clampf(minf(size.x / maxf(b.size.x, 1.0), size.y / maxf(b.size.y, 1.0)), 0.25, 1.2)
	offset = -b.position * zoom + (size - b.size * zoom) * 0.5
	queue_redraw()


## 그 노드가 화면 가운데에 오게
func focus_node(id: String) -> void:
	if graph == null or not graph.nodes.has(id):
		return
	var n: Dictionary = graph.nodes[id]
	var c: Vector2 = n.pos + n.size * 0.5
	offset = size * 0.5 - c * zoom
	queue_redraw()


func _visible(id: String) -> bool:
	return graph != null and graph.nodes.has(id) and not hide_kinds.get(graph.nodes[id].kind, false)


func _to_screen(p: Vector2) -> Vector2:
	return p * zoom + offset


func _to_world(p: Vector2) -> Vector2:
	return (p - offset) / zoom


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.12, 0.15))
	if graph == null:
		return
	var k := zoom
	var labels := []   # [자리, 글, 색] — 노드를 그린 뒤 맨 위에
	_edge_pts.clear()
	# 선 (노드 아래)
	for ei in graph.edges.size():
		var e: Dictionary = graph.edges[ei]
		if not _visible(e.from) or not _visible(e.to):
			_edge_pts.append(PackedVector2Array())
			continue
		var a: Dictionary = graph.nodes[e.from]
		var b: Dictionary = graph.nodes[e.to]
		var p0 := _to_screen(a.pos + Vector2(a.size.x, a.size.y * 0.5))
		var p1 := _to_screen(b.pos + Vector2(0.0, b.size.y * 0.5))
		var lit: bool = e.from == selected or e.to == selected or ei == selected_edge
		var col: Color = (COLORS.get(a.kind, Color.WHITE) as Color).lightened(0.25 if lit else 0.0)
		if ei == selected_edge:
			col = Color(1.0, 0.95, 0.6)
		col.a = 1.0 if lit else 0.55
		var back := p1.x < p0.x + 20.0 * k   # 되돌아가는 선: 아래로 크게 돌아감
		var pts := PackedVector2Array()
		var steps := 24
		var c0 := p0 + Vector2(60.0 * k, 0.0)
		var c1 := p1 - Vector2(60.0 * k, 0.0)
		if back:
			var dy := 70.0 * k
			c0 = p0 + Vector2(80.0 * k, dy)
			c1 = p1 + Vector2(-80.0 * k, dy)
		for i in steps + 1:
			var t := float(i) / steps
			pts.append(p0.bezier_interpolate(c0, c1, p1, t))
		_edge_pts.append(pts)
		draw_polyline(pts, col, (3.5 if ei == selected_edge else (3.0 if lit else 1.8)) * k, true)
		# 화살촉
		var d := (pts[steps] - pts[steps - 1]).normalized()
		var nrm := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([p1, p1 - d * 10.0 * k + nrm * 5.0 * k, p1 - d * 10.0 * k - nrm * 5.0 * k]), col)
		if str(e.label) != "" and k >= 0.45:
			labels.append([pts[steps / 2], str(e.label), col])
	# 선 긋는 중 (고무줄)
	if _link_from != "" and graph.nodes.has(_link_from):
		var a: Dictionary = graph.nodes[_link_from]
		var p0 := _to_screen(a.pos + Vector2(a.size.x, a.size.y * 0.5))
		draw_line(p0, _link_pos, Color(1.0, 0.95, 0.6), 2.5 * k, true)
		draw_circle(_link_pos, 5.0 * k, Color(1.0, 0.95, 0.6))
	# 노드
	for id in graph.order:
		if not _visible(id):
			continue
		var n: Dictionary = graph.nodes[id]
		var r := Rect2(_to_screen(n.pos), n.size * k)
		var col: Color = COLORS.get(n.kind, Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.17, 0.21) if n.kind != "start" else Color(0.14, 0.15, 0.18)
		var target_hi := _link_from != "" and id == hovered and id != _link_from
		sb.border_color = Color(1.0, 0.95, 0.6) if target_hi else (col.lightened(0.3) if id == selected else (col if id == hovered else col.darkened(0.25)))
		sb.set_border_width_all(roundi((3.0 if id == selected or target_hi else 1.5) * k))
		sb.set_corner_radius_all(roundi(6 * k))
		draw_style_box(sb, r)
		draw_rect(Rect2(r.position, Vector2(r.size.x, StoryGraph.HEAD_H * k)), Color(col, 0.28 if n.kind != "start" else 0.18))
		var fs := maxi(8, roundi(13.0 * k))
		var tag: String = StoryGraph.KIND_NAME.get(n.kind, "")
		draw_string(bold, r.position + Vector2(8 * k, 19 * k), _clip(n.title, StoryGraph.W - 16.0, fs / k, bold), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		if n.kind != "start" and k >= 0.5:
			var tfs := maxi(7, roundi(10.0 * k))
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
			draw_string(font, r.position + Vector2(r.size.x - tw - 6 * k, 10 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, col.lightened(0.2))
		if k >= 0.45:
			var sfs := maxi(7, roundi(11.0 * k))
			var y := StoryGraph.HEAD_H * k + 13.0 * k
			for line in n.sub:
				draw_string(font, r.position + Vector2(8 * k, y), _clip(str(line), StoryGraph.W - 16.0, sfs / k, font), HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(0.8, 0.83, 0.9))
				y += StoryGraph.LINE_H * k
	# 선 위 글 (열 사이 빈 자리에, 맨 위)
	for lb in labels:
		var mid: Vector2 = lb[0]
		var fs := maxi(9, roundi(12.0 * k))
		var w := font.get_string_size(lb[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(mid - Vector2(w * 0.5 + 4, fs * 0.8), Vector2(w + 8, fs + 4)), Color(0.11, 0.12, 0.15, 0.9))
		draw_string(font, mid - Vector2(w * 0.5, 0), lb[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, (lb[2] as Color).lightened(0.2))
	if graph.order.is_empty():
		draw_string(bold, Vector2(20, 40), "퀘스트 · 컷씬이 없습니다 — 위 '+ 퀘스트' · '+ 컷씬' 으로 시작", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.75))


func _clip(t: String, max_w: float, fs: float, f: Font) -> String:
	if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x <= max_w:
		return t
	var s := t
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x > max_w:
		s = s.substr(0, s.length() - 1)
	return s + "…"


func node_at(p: Vector2) -> String:
	if graph == null:
		return ""
	var ids := graph.order.duplicate()
	ids.reverse()
	for id in ids:
		if not _visible(id):
			continue
		var n: Dictionary = graph.nodes[id]
		if Rect2(_to_screen(n.pos), n.size * zoom).has_point(p):
			return id
	return ""


func edge_at(p: Vector2) -> int:
	var best := -1
	var best_d := 7.0
	for i in _edge_pts.size():
		var pts: PackedVector2Array = _edge_pts[i]
		for j in range(1, pts.size()):
			var d := Geometry2D.get_closest_point_to_segment(p, pts[j - 1], pts[j]).distance_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
		delete_pressed.emit()
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var f := 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
				var nz := clampf(zoom * f, 0.2, 2.0)
				offset = mb.position - (mb.position - offset) * (nz / zoom)   # 마우스 자리를 기준으로
				zoom = nz
				queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				grab_focus()
				_moved = false
				_drag_start = mb.position
				var id := node_at(mb.position)
				if mb.button_index == MOUSE_BUTTON_LEFT and id != "" and mb.shift_pressed:
					_link_from = id   # Shift+끌기 = 선 긋기
					_link_pos = mb.position
				elif mb.button_index == MOUSE_BUTTON_LEFT and id != "":
					_drag_node = id
					_drag_node_from = graph.nodes[id].pos
				else:
					_dragging = true
					_drag_off = offset
			else:
				if _link_from != "":
					var to := node_at(mb.position)
					if to != "" and to != _link_from:
						link_requested.emit(_link_from, to)
					_link_from = ""
					queue_redraw()
				elif _drag_node != "":
					if _moved:
						node_moved.emit(_drag_node, graph.nodes[_drag_node].pos)
					else:
						if mb.double_click:
							node_double_clicked.emit(_drag_node)
						else:
							selected = _drag_node
							selected_edge = -1
							node_clicked.emit(_drag_node)
					_drag_node = ""
					queue_redraw()
				else:
					_dragging = false
					if not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
						var ei := edge_at(mb.position)
						selected_edge = ei
						if ei >= 0:
							edge_clicked.emit(ei)
						else:
							selected = ""
							background_clicked.emit()
						queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _link_from != "":
			_link_pos = mm.position
			hovered = node_at(mm.position)
			queue_redraw()
		elif _drag_node != "":
			if (mm.position - _drag_start).length() > 3.0:
				_moved = true
				graph.nodes[_drag_node].pos = _drag_node_from + (mm.position - _drag_start) / zoom
				queue_redraw()
		elif _dragging:
			if (mm.position - _drag_start).length() > 3.0:
				_moved = true
				offset = _drag_off + (mm.position - _drag_start)
				queue_redraw()
		else:
			var h := node_at(mm.position)
			if h != hovered:
				hovered = h
				queue_redraw()
