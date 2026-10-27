class_name SkillTreeView
extends Control
## 십자형 스킬 트리 (한 캐릭터의 액티브 또는 패시브 트리): 가운데 중앙 노드, 위 = 북(화력) · 오른쪽 = 동(기동) · 아래 = 남(생존) · 왼쪽 = 서(전술)로 1~4단계 (data/skill_tree.json · 에디터 스킬 트리 탭).
## 레벨이 모자란 노드는 회색 + 가운데 붉은 "경험 부족". 클릭하면 selected 신호 (배우기는 창에서).

signal node_selected(node_id: String)

const NODE := Vector2(100.0, 58.0)
const STEP := Vector2(106.0, 84.0)    # 단계 사이 간격 (가로 / 세로, 갈래가 길면 줄어듦)
const DIR_VEC := {"center": Vector2.ZERO, "n": Vector2(0, -1), "e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0)}
const DIR_COL := {"center": Color(1.0, 0.85, 0.35), "n": Color(1.0, 0.45, 0.35), "e": Color(0.35, 0.85, 1.0),
	"s": Color(0.45, 0.95, 0.55), "w": Color(0.8, 0.55, 1.0)}
const DIR_NAME := {"n": "북 · 화력", "e": "동 · 기동", "s": "남 · 생존", "w": "서 · 전술"}
const GRAY := Color(0.33, 0.34, 0.37)
const RED := Color(1.0, 0.28, 0.25)

var sim: BaseSim
var cid := ""
var kind := "active"
var selected := ""
var hovered := ""
var font: Font
var bold: Font


func setup(p_sim: BaseSim, p_cid: String, p_kind: String, p_font: Font, p_bold: Font) -> void:
	sim = p_sim
	cid = p_cid
	kind = p_kind
	font = p_font
	bold = p_bold
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


## 갈래가 길면(최대 SkillTreeData.MAX_TIER 단계) 칸·간격을 줄여서 창 안에 맞춤
func _k() -> float:
	var th := maxi(1, maxi(sim.max_tier(cid, "e", kind), sim.max_tier(cid, "w", kind)))
	var tv := maxi(1, maxi(sim.max_tier(cid, "n", kind), sim.max_tier(cid, "s", kind)))
	var kx := (size.x * 0.5 - NODE.x * 0.5 - 6.0) / (th * STEP.x)
	var ky := (size.y * 0.5 - NODE.y * 0.5 - 6.0) / (tv * STEP.y)
	return clampf(minf(kx, ky), 0.55, 1.0)


func _pos(dir: String, tier: float) -> Vector2:
	return size * 0.5 + Vector2(DIR_VEC[dir]) * STEP * _k() * tier


func node_rect(n: Dictionary) -> Rect2:
	var sz := NODE * _k()
	return Rect2(_pos(n.dir, float(n.tier)) - sz * 0.5, sz)


func _node_at(p: Vector2) -> String:
	if sim == null:
		return ""
	for n in sim.tree_nodes(cid, kind):
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
	var nodes := sim.tree_nodes(cid, kind)
	var k := _k()
	var nsz := NODE * k
	# 갈래 선: 배운 칸까지는 갈래 색, 나머지는 회색
	for n in nodes:
		if n.dir == "center":
			continue
		var a := _pos(n.dir, float(n.tier - 1))
		var b := _pos(n.dir, float(n.tier))
		var lit := sim.has_skill(cid, n.id)
		draw_line(a, b, DIR_COL[n.dir] if lit else Color(0.25, 0.27, 0.31), 6.0 if lit else 4.0, true)
	# 갈래 이름 (갈래 바깥쪽 끝 옆)
	for d in DIR_NAME:
		var mt := sim.max_tier(cid, d, kind)
		if mt == 0:
			continue
		var tip := _pos(d, float(mt))
		var at: Vector2
		match d:
			"n", "s": at = tip + Vector2(nsz.x * 0.5 + 10, 6)
			_: at = tip + Vector2(-nsz.x * 0.5, -nsz.y * 0.5 - 10)
		draw_string(bold, at, DIR_NAME[d], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIR_COL[d].lerp(Color(1, 1, 1), 0.2))
	for n in nodes:
		_draw_node(n)


func _draw_node(n: Dictionary) -> void:
	var r := node_rect(n)
	var st := sim.skill_state(cid, n.id)
	var col: Color = DIR_COL[n.dir]
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
			sub = "갈래 끝 하나만"
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
	if st == "no_level":
		# 레벨 미달: 회색 위에 가운데 붉은 "경험 부족"
		draw_rect(r.grow(-2), Color(0.1, 0.1, 0.1, 0.35))
		var t := "경험 부족"
		var rs := maxi(11, roundi(16 * k))
		var ts := bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, rs)
		var p := r.get_center() + Vector2(-ts.x * 0.5, ts.y * 0.35)
		draw_string_outline(bold, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, 4, Color(0, 0, 0, 0.8))
		draw_string(bold, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, RED)
