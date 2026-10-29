@tool
extends Control
## 스토리 흐름 그림: StoryGraph 의 노드(상자)와 선(화살표)을 그림. 왼쪽 = 먼저, 오른쪽 = 나중.
## 노드 클릭 = 고르기 · 빈 곳 끌기 = 화면 옮기기 · 휠 = 확대/축소 · 더블클릭 = 그 탭으로 (panel 이 처리)

signal node_clicked(id: String)
signal node_double_clicked(id: String)

const COLORS := {
	"start": Color(0.42, 0.44, 0.52), "quest": Color(0.85, 0.62, 0.22), "cutscene": Color(0.36, 0.62, 0.92),
	"divine": Color(0.78, 0.45, 0.95), "mission": Color(0.40, 0.66, 0.46),
}

var graph: StoryGraph
var selected := ""
var hovered := ""
var hide_kinds: Dictionary = {}   # kind → true 면 숨김
var font: Font
var bold: Font
var offset := Vector2(0, 0)
var zoom := 1.0
var _drag_start := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _dragging := false
var _moved := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	font = load("res://assets/fonts/Pretendard-Medium.ttf")
	bold = load("res://assets/fonts/Pretendard-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Pretendard-Bold.ttf") else font
	resized.connect(queue_redraw)


func show_graph(g: StoryGraph, sel: String) -> void:
	graph = g
	selected = sel
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.12, 0.15))
	if graph == null:
		return
	var k := zoom
	var labels := []   # [자리, 글, 색] — 노드를 그린 뒤 맨 위에
	# 선 (노드 아래)
	for e in graph.edges:
		if not _visible(e.from) or not _visible(e.to):
			continue
		var a: Dictionary = graph.nodes[e.from]
		var b: Dictionary = graph.nodes[e.to]
		var p0 := _to_screen(a.pos + Vector2(a.size.x, a.size.y * 0.5))
		var p1 := _to_screen(b.pos + Vector2(0.0, b.size.y * 0.5))
		var lit: bool = e.from == selected or e.to == selected
		var col: Color = (COLORS.get(a.kind, Color.WHITE) as Color).lightened(0.25 if lit else 0.0)
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
		draw_polyline(pts, col, (3.0 if lit else 1.8) * k, true)
		# 화살촉
		var d := (pts[steps] - pts[steps - 1]).normalized()
		var nrm := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([p1, p1 - d * 10.0 * k + nrm * 5.0 * k, p1 - d * 10.0 * k - nrm * 5.0 * k]), col)
		if str(e.label) != "" and k >= 0.45:
			labels.append([pts[steps / 2] if not back else pts[steps / 2], str(e.label), col])
	# 노드
	for id in graph.order:
		if not _visible(id):
			continue
		var n: Dictionary = graph.nodes[id]
		var r := Rect2(_to_screen(n.pos), n.size * k)
		var col: Color = COLORS.get(n.kind, Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.17, 0.21) if n.kind != "start" else Color(0.14, 0.15, 0.18)
		sb.border_color = col.lightened(0.3) if id == selected else (col if id == hovered else col.darkened(0.25))
		sb.set_border_width_all(roundi((3.0 if id == selected else 1.5) * k))
		sb.set_corner_radius_all(roundi(6 * k))
		draw_style_box(sb, r)
		# 머리띠
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
		draw_string(bold, Vector2(20, 40), "퀘스트 · 컷씬 데이터가 없습니다", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.75))


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


func _gui_input(event: InputEvent) -> void:
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
				_dragging = true
				_moved = false
				_drag_start = mb.position
				_drag_off = offset
			else:
				_dragging = false
				if not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
					var id := node_at(mb.position)
					if mb.double_click and id != "":
						node_double_clicked.emit(id)
					else:
						selected = id
						node_clicked.emit(id)
						queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			if (mm.position - _drag_start).length() > 3.0:
				_moved = true
				offset = _drag_off + (mm.position - _drag_start)
				queue_redraw()
		else:
			var h := node_at(mm.position)
			if h != hovered:
				hovered = h
				queue_redraw()
