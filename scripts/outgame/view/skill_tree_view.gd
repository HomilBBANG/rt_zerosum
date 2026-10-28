class_name SkillTreeView
extends Control
## 스킬 트리 (한 캐릭터의 액티브 또는 패시브 트리). 모양은 캐릭터마다 자유 — 노드를 격자 칸(x, y)에 그리고 선행 → 노드로 선을 잇는다 (data/skill_tree.json · 에디터 스킬 트리 탭).
## 선: 둘 다 배웠으면 갈래 색, 아니면 회색. 노드 오른쪽 위 '택1' = 택일 그룹(그중 하나만), '모두' = 선행을 모두 배워야.
## 레벨이 모자란 노드는 회색 + 가운데 붉은 "경험 부족". 클릭하면 selected 신호 (배우기는 창에서).

signal node_selected(node_id: String)

const NODE := Vector2(100.0, 58.0)
const STEP := Vector2(118.0, 84.0)    # 칸 사이 간격 (가로 / 세로, 트리가 크면 줄어듦)
const GRAY := Color(0.33, 0.34, 0.37)
const RED := Color(1.0, 0.28, 0.25)

var sim: BaseSim
var cid := ""
var kind := "active"
var selected := ""
var hovered := ""
var font: Font
var bold: Font


static func col_of(n: Dictionary) -> Color:
	return SkillTreeData.BRANCH_COL.get(str(n.get("branch", "core")), SkillTreeData.BRANCH_COL.core)


func setup(p_sim: BaseSim, p_cid: String, p_kind: String, p_font: Font, p_bold: Font) -> void:
	sim = p_sim
	cid = p_cid
	kind = p_kind
	font = p_font
	bold = p_bold
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _tree() -> Array:
	return sim.tree_nodes(cid, kind) if sim != null else []


## 트리가 크면 칸·간격을 줄여서 창 안에 맞춤
func _k() -> float:
	var b := SkillTreeData.bounds(_tree())
	var kx := (size.x - NODE.x - 16.0) / maxf(1.0, (b.size.x - 1) * STEP.x)
	var ky := (size.y - NODE.y - 40.0) / maxf(1.0, (b.size.y - 1) * STEP.y)
	return clampf(minf(kx, ky), 0.45, 1.0)


func _pos(x: float, y: float) -> Vector2:
	var b := SkillTreeData.bounds(_tree())
	var mid := Vector2(b.position) + Vector2(b.size - Vector2i.ONE) * 0.5
	return size * 0.5 + Vector2(0, 12) + (Vector2(x, y) - mid) * STEP * _k()


func node_rect(n: Dictionary) -> Rect2:
	var sz := NODE * _k()
	return Rect2(_pos(float(n.x), float(n.y)) - sz * 0.5, sz)


func _node_at(p: Vector2) -> String:
	for n in _tree():
		if node_rect(n).grow(2).has_point(p):
			return n.id
	return ""


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _node_at(ev.position)
		if h != hovered:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var id := _node_at(ev.position)
		if id != "":
			selected = id
			queue_redraw()
			node_selected.emit(id)


func _draw() -> void:
	if sim == null:
		return
	var nodes := _tree()
	var by := {}
	for n in nodes:
		by[n.id] = n
	# 선행 → 노드 선: 둘 다 배웠으면 갈래 색
	for n in nodes:
		for q in n.req:
			if not by.has(q):
				continue
			var a := _pos(float(by[q].x), float(by[q].y))
			var b := _pos(float(n.x), float(n.y))
			var lit := sim.has_skill(cid, n.id) and sim.has_skill(cid, q)
			var open := not lit and sim.has_skill(cid, q)
			draw_line(a, b, col_of(n) if lit else (col_of(n).darkened(0.45) if open else Color(0.25, 0.27, 0.31)), 6.0 if lit else 4.0, true)
	# 쓰는 갈래 (왼쪽 위)
	var used := []
	for n in nodes:
		if not used.has(n.branch):
			used.append(n.branch)
	var at := Vector2(8, 18)
	for br in SkillTreeData.BRANCHES:
		if not used.has(br):
			continue
		var c: Color = SkillTreeData.BRANCH_COL[br]
		draw_circle(at + Vector2(6, -5), 6.0, c)
		var t: String = SkillTreeData.BRANCH_NAME[br]
		draw_string(bold, at + Vector2(16, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c.lerp(Color.WHITE, 0.2))
		at.x += 30 + bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	for n in nodes:
		_draw_node(n)


func _draw_node(n: Dictionary) -> void:
	var r := node_rect(n)
	var st := sim.skill_state(cid, n.id)
	var col := col_of(n)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	var name_col := Color(1, 1, 1)
	var sub := "Lv %d" % int(n.level)
	var sub_col := Color(0.8, 0.84, 0.9)
	match st:
		"learned":
			sb.bg_color = col.darkened(0.35)
			sb.border_color = col.lightened(0.3)
			sub = "습득"
			sub_col = col.lightened(0.55)
		"ready":
			sb.bg_color = Color(0.1, 0.12, 0.16)
			sb.border_color = col
			sb.set_border_width_all(3)
			sub = "배우기 가능"
			sub_col = col
		"no_level":
			sb.bg_color = Color(0.17, 0.17, 0.18)
			sb.border_color = Color(0.28, 0.28, 0.3)
			name_col = GRAY.lightened(0.15)
			sub_col = GRAY.lightened(0.1)
		"capped":
			sb.bg_color = Color(0.1, 0.1, 0.12)
			sb.border_color = Color(0.3, 0.3, 0.34)
			name_col = Color(0.6, 0.62, 0.66)
			sub = "택일 — 다른 것 배움"
			sub_col = Color(0.6, 0.62, 0.66)
		_:   # need_prev / no_point
			sb.bg_color = Color(0.1, 0.11, 0.14)
			sb.border_color = col.darkened(0.45)
			name_col = Color(0.78, 0.8, 0.85)
	if n.id == hovered or n.id == selected:
		sb.border_color = Color(1, 1, 1) if n.id == selected else sb.border_color.lightened(0.4)
		sb.set_border_width_all(3)
	draw_style_box(sb, r)
	var cap := r.size.x - 10.0
	var k := r.size.y / NODE.y
	var fs := maxi(10, roundi((14 if str(n.name).length() <= 6 else 12) * k))
	draw_string(bold, r.position + Vector2(5, 21 * k), str(n.name), HORIZONTAL_ALIGNMENT_CENTER, cap, fs, name_col)
	draw_string(font, r.position + Vector2(5, r.size.y - 9 * k), sub, HORIZONTAL_ALIGNMENT_CENTER, cap, maxi(10, roundi(12 * k)), sub_col)
	# 작은 표시: 택1 (택일 그룹) · 모두 (선행 모두)
	var tags := PackedStringArray()
	if str(n.group) != "":
		tags.append("택1")
	if bool(n.req_all) and (n.req as Array).size() > 1:
		tags.append("모두")
	if not tags.is_empty():
		var tt := " ".join(tags)
		var ts := maxi(9, roundi(11 * k))
		var tw := font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x + 8
		var tr := Rect2(Vector2(r.end.x - tw, r.position.y - ts - 5), Vector2(tw, ts + 4))
		draw_rect(tr, Color(0.08, 0.09, 0.12, 0.95))
		draw_rect(tr, col.darkened(0.2), false, 1.0)
		draw_string(font, tr.position + Vector2(4, ts + 0.5), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, col.lightened(0.35))
	if st == "no_level":
		# 레벨 미달: 회색 위에 가운데 붉은 "경험 부족"
		draw_rect(r.grow(-2), Color(0.1, 0.1, 0.1, 0.35))
		var t := "경험 부족"
		var rs := maxi(11, roundi(16 * k))
		var tsz := bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, rs)
		var p := r.get_center() + Vector2(-tsz.x * 0.5, tsz.y * 0.35)
		draw_string_outline(bold, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, 4, Color(0, 0, 0, 0.8))
		draw_string(bold, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, RED)
