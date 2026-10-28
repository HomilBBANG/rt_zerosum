@tool
extends Control
## 스킬 트리 에디터 가운데 그림: 한 캐릭터의 한 트리(액티브/패시브)를 격자 위에 — 모양은 자유.
## 빈 칸 클릭 = 그 칸에 새 노드 (고른 노드가 있으면 그 노드에서 이어짐) · 노드 클릭 = 고르기 · 노드 끌기 = 다른 빈 칸으로 옮기기
## Shift+클릭 = 고른 노드 → 누른 노드 선행 잇기/끊기 · Delete = 고른 노드 삭제 · 선은 선행 → 노드 (화살표).

signal node_clicked(id: String)
signal cell_clicked(x: int, y: int)
signal node_moved(id: String, x: int, y: int)
signal link_toggled(from_id: String, to_id: String)
signal delete_pressed(id: String)

const NODE := Vector2(124.0, 70.0)
const STEP := Vector2(150.0, 100.0)

var nodes: Array = []          # 이 트리의 노드만
var selected := ""
var hovered := ""              # 노드 id 또는 "@x,y" (빈 칸)
var font: Font
var bold: Font
var _drag := ""                # 끄는 노드 id
var _drag_from := Vector2.ZERO
var _dragging := false


func show_tree(p_nodes: Array, p_selected: String) -> void:
	nodes = p_nodes
	selected = p_selected
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	font = load("res://assets/fonts/Pretendard-Medium.ttf")
	bold = load("res://assets/fonts/Pretendard-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Pretendard-Bold.ttf") else font
	resized.connect(queue_redraw)


## 보이는 칸 범위 = 노드 범위 + 둘레 한 칸 (최소 5x5, 0,0 포함)
func _area() -> Rect2i:
	var b := SkillTreeData.bounds(nodes)
	var lo := Vector2i(mini(b.position.x, 0) - 1, mini(b.position.y, 0) - 1)
	var hi := Vector2i(maxi(b.end.x - 1, 0) + 1, maxi(b.end.y - 1, 0) + 1)
	lo = lo.clamp(Vector2i(-SkillTreeData.GRID, -SkillTreeData.GRID), Vector2i(SkillTreeData.GRID, SkillTreeData.GRID))
	hi = hi.clamp(Vector2i(-SkillTreeData.GRID, -SkillTreeData.GRID), Vector2i(SkillTreeData.GRID, SkillTreeData.GRID))
	while hi.x - lo.x < 4:
		lo.x = maxi(-SkillTreeData.GRID, lo.x - 1)
		hi.x = mini(SkillTreeData.GRID, hi.x + 1)
	while hi.y - lo.y < 4:
		lo.y = maxi(-SkillTreeData.GRID, lo.y - 1)
		hi.y = mini(SkillTreeData.GRID, hi.y + 1)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _k() -> float:
	var a := _area()
	var kx := (size.x - 20.0) / (a.size.x * STEP.x)
	var ky := (size.y - 46.0) / (a.size.y * STEP.y)
	return clampf(minf(kx, ky), 0.3, 1.0)


func _center(x: int, y: int) -> Vector2:
	var a := _area()
	var mid := Vector2(a.position) + Vector2(a.size - Vector2i.ONE) * 0.5
	return size * 0.5 + Vector2(0, -8) + (Vector2(x, y) - mid) * STEP * _k()


func _rect(x: int, y: int) -> Rect2:
	var k := _k()
	return Rect2(_center(x, y) - NODE * k * 0.5, NODE * k)


func _node_at_cell(x: int, y: int) -> Dictionary:
	for n in nodes:
		if int(n.x) == x and int(n.y) == y:
			return n
	return {}


func _hit(p: Vector2) -> String:
	for n in nodes:
		if _rect(int(n.x), int(n.y)).grow(2).has_point(p):
			return str(n.id)
	var a := _area()
	for y in range(a.position.y, a.end.y):
		for x in range(a.position.x, a.end.x):
			if _rect(x, y).grow(6).has_point(p):
				return "@%d,%d" % [x, y]
	return ""


func _cell_of(h: String) -> Vector2i:
	var p := h.substr(1).split(",")
	return Vector2i(int(p[0]), int(p[1]))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		if _drag != "" and ev.position.distance_to(_drag_from) > 8.0:
			_dragging = true
		var h := _hit(ev.position)
		if h != hovered or _dragging:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_MOVE if _dragging else (Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(ev.position)
		if ev.pressed:
			grab_focus()
			if h.begins_with("@"):
				var c := _cell_of(h)
				cell_clicked.emit(c.x, c.y)
			elif h != "":
				if ev.shift_pressed and selected != "" and selected != h:
					link_toggled.emit(selected, h)
				else:
					_drag = h
					_drag_from = ev.position
					_dragging = false
					node_clicked.emit(h)
		else:
			if _dragging and _drag != "" and h.begins_with("@"):
				var c2 := _cell_of(h)
				node_moved.emit(_drag, c2.x, c2.y)
			_drag = ""
			_dragging = false
			queue_redraw()
	elif ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode in [KEY_DELETE, KEY_BACKSPACE] and selected != "":
		delete_pressed.emit(selected)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.1))
	if font == null:
		return
	var k := _k()
	var a := _area()
	# 빈 칸 (점선 테두리, 마우스를 올리면 '+')
	for y in range(a.position.y, a.end.y):
		for x in range(a.position.x, a.end.x):
			if not _node_at_cell(x, y).is_empty():
				continue
			var r := _rect(x, y)
			var hov := hovered == "@%d,%d" % [x, y]
			if hov:
				var sb := StyleBoxFlat.new()
				sb.set_corner_radius_all(10)
				sb.set_border_width_all(2)
				sb.bg_color = Color(0.16, 0.18, 0.22)
				sb.border_color = Color(0.75, 0.78, 0.85)
				draw_style_box(sb, r)
				var t := "여기로 옮기기" if _dragging else ("+ 새 노드" + (" (이어서)" if selected != "" else ""))
				draw_string(bold, r.position + Vector2(0, r.size.y * 0.5 + 5), t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, maxi(10, roundi(13 * k)), Color.WHITE)
			else:
				draw_rect(r.grow(-r.size.y * 0.32), Color(0.2, 0.22, 0.27, 0.35), false, 1.0)
			if x == 0 and y == 0:
				draw_string(font, r.position + Vector2(0, r.size.y - 4), "0,0", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, maxi(9, roundi(11 * k)), Color(0.4, 0.42, 0.5))
	# 선행 → 노드 화살표
	var by := {}
	for n in nodes:
		by[n.id] = n
	for n in nodes:
		for q in n.req:
			if not by.has(q):
				continue
			var p0 := _center(int(by[q].x), int(by[q].y))
			var p1 := _center(int(n.x), int(n.y))
			var col: Color = SkillTreeData.BRANCH_COL.get(n.branch, Color.WHITE).darkened(0.15)
			if n.id == selected or q == selected:
				col = col.lightened(0.35)
			draw_line(p0, p1, col, 4.0 if bool(n.req_all) else 3.0, true)
			# 화살촉: 노드 테두리 바로 앞
			var dir := (p1 - p0).normalized()
			var half := NODE * k * 0.5
			var t := minf(half.x / maxf(0.001, absf(dir.x)), half.y / maxf(0.001, absf(dir.y)))
			var tip := p1 - dir * (t + 2.0)
			var side := Vector2(-dir.y, dir.x)
			var hs := 9.0 * k + 3.0
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * hs + side * hs * 0.55, tip - dir * hs - side * hs * 0.55]), col)
	for n in nodes:
		_draw_node(n, k)
	draw_string(font, Vector2(10, size.y - 10), "빈 칸 클릭 = 새 노드 (고른 노드에서 이어짐) · 끌기 = 옮기기 · Shift+클릭 = 고른 노드 → 그 노드 선행 잇기/끊기 · Delete = 삭제",
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 12, Color(0.6, 0.64, 0.72))


func _draw_node(n: Dictionary, k: float) -> void:
	var r := _rect(int(n.x), int(n.y))
	if _dragging and n.id == _drag:
		draw_style_box(_box(Color(0.3, 0.32, 0.38), Color(0.1, 0.11, 0.14, 0.5), 2), r)
		r = Rect2(get_local_mouse_position() - r.size * 0.5, r.size)
	var col: Color = SkillTreeData.BRANCH_COL.get(n.branch, Color.WHITE)
	var sb := _box(col, col.darkened(0.6), 2)
	if bool(n.start):
		sb.set_border_width_all(3)
		sb.bg_color = col.darkened(0.45)
	if n.id == selected:
		sb.border_color = Color.WHITE
		sb.set_border_width_all(4)
	elif n.id == hovered:
		sb.border_color = col.lightened(0.4)
		sb.set_border_width_all(3)
	draw_style_box(sb, r)
	var ef: String = n.effect
	var new_skill := ef.begins_with("skill:")
	var cap := r.size.x - 8.0
	draw_string(bold, r.position + Vector2(4, 20 * k), str(n.name), HORIZONTAL_ALIGNMENT_CENTER, cap, maxi(10, roundi(15 * k)), Color.WHITE)
	var eff := "%s +%d" % [ef.split(":")[1] if ":" in ef else ef, int(n.value)] if not new_skill else "★ " + ef.substr(6)
	draw_string(font, r.position + Vector2(4, 40 * k), eff, HORIZONTAL_ALIGNMENT_CENTER, cap, maxi(9, roundi(12 * k)),
		Color(1, 0.85, 0.4) if new_skill else Color(0.8, 0.85, 0.92))
	var foot := ("시작 · " if bool(n.start) else "") + "Lv %d" % int(n.level)
	draw_string(font, r.position + Vector2(4, r.size.y - 8 * k), foot, HORIZONTAL_ALIGNMENT_CENTER, cap, maxi(9, roundi(12 * k)), col.lightened(0.5))
	var tags := PackedStringArray()
	if str(n.group) != "":
		tags.append("택1 " + str(n.group))
	if bool(n.req_all) and (n.req as Array).size() > 1:
		tags.append("모두")
	if not tags.is_empty():
		var tt := " · ".join(tags)
		var ts := maxi(9, roundi(11 * k))
		var tw := minf(font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x + 8, r.size.x + 20)
		var tr := Rect2(Vector2(r.end.x - tw, r.position.y - ts - 5), Vector2(tw, ts + 4))
		draw_rect(tr, Color(0.08, 0.09, 0.12, 0.95))
		draw_rect(tr, col.darkened(0.2), false, 1.0)
		draw_string(font, tr.position + Vector2(4, ts + 0.5), tt, HORIZONTAL_ALIGNMENT_LEFT, tw - 6, ts, col.lightened(0.35))


func _box(border: Color, bg: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(w)
	sb.bg_color = bg
	sb.border_color = border
	return sb
