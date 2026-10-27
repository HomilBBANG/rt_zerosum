@tool
extends Control
## 스킬 트리 에디터 가운데 그림: 한 캐릭터의 한 트리(액티브/패시브)를 게임과 같은 십자형으로.
## 노드 클릭 = 고르기, 갈래 끝 다음의 "+" 칸 클릭 = 그 갈래에 단계 추가 (중앙이 없으면 가운데에 "+").

signal node_clicked(id: String)
signal add_clicked(dir: String, tier: int)

const NODE := Vector2(124.0, 70.0)
const STEP := Vector2(138.0, 100.0)
const DIR_VEC := {"center": Vector2.ZERO, "n": Vector2(0, -1), "e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0)}
const DIR_COL := {"center": Color(1.0, 0.85, 0.35), "n": Color(1.0, 0.45, 0.35), "e": Color(0.35, 0.85, 1.0),
	"s": Color(0.45, 0.95, 0.55), "w": Color(0.8, 0.55, 1.0)}

var nodes: Array = []          # 이 트리의 노드만
var selected := ""
var hovered := ""              # 노드 id 또는 "+dir:tier"
var font: Font
var bold: Font


func show_tree(p_nodes: Array, p_selected: String) -> void:
	nodes = p_nodes
	selected = p_selected
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://assets/fonts/Pretendard-Medium.ttf")
	bold = load("res://assets/fonts/Pretendard-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Pretendard-Bold.ttf") else font
	resized.connect(queue_redraw)


func _end(dir: String) -> int:
	var t := 0
	for n in nodes:
		if n.dir == dir:
			t = maxi(t, int(n.tier))
	return t


func _has_center() -> bool:
	return nodes.any(func(n): return n.dir == "center")


## 갈래 끝 + "+" 칸까지 들어가게 줄임
func _k() -> float:
	var th := 1
	var tv := 1
	for d in ["e", "w"]:
		th = maxi(th, mini(_end(d) + 1, SkillTreeData.MAX_TIER))
	for d in ["n", "s"]:
		tv = maxi(tv, mini(_end(d) + 1, SkillTreeData.MAX_TIER))
	var kx := (size.x * 0.5 - NODE.x * 0.5 - 10.0) / (th * STEP.x)
	var ky := (size.y * 0.5 - NODE.y * 0.5 - 10.0) / (tv * STEP.y)
	return clampf(minf(kx, ky), 0.45, 1.0)


func _rect(dir: String, tier: int) -> Rect2:
	var k := _k()
	var c := size * 0.5 + Vector2(DIR_VEC[dir]) * STEP * k * float(tier)
	return Rect2(c - NODE * k * 0.5, NODE * k)


## "+" 칸들: [{dir, tier}]
func _slots() -> Array:
	var out := []
	if not _has_center():
		out.append({"dir": "center", "tier": 0})
	for d in ["n", "e", "s", "w"]:
		var e := _end(d)
		if e < SkillTreeData.MAX_TIER:
			out.append({"dir": d, "tier": e + 1})
	return out


func _hit(p: Vector2) -> String:
	for n in nodes:
		if _rect(n.dir, int(n.tier)).grow(2).has_point(p):
			return str(n.id)
	for s in _slots():
		if _rect(s.dir, s.tier).grow(2).has_point(p):
			return "+%s:%d" % [s.dir, s.tier]
	return ""


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _hit(ev.position)
		if h != hovered:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(ev.position)
		if h.begins_with("+"):
			var p := h.substr(1).split(":")
			add_clicked.emit(p[0], int(p[1]))
		elif h != "":
			node_clicked.emit(h)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.1))
	if font == null:
		return
	var k := _k()
	var c := size * 0.5
	# 갈래 선 (+ 칸까지 점선)
	for d in ["n", "e", "s", "w"]:
		var e := _end(d)
		for t in range(1, mini(e + 1, SkillTreeData.MAX_TIER) + 1):
			var a := c + Vector2(DIR_VEC[d]) * STEP * k * float(t - 1)
			var b := c + Vector2(DIR_VEC[d]) * STEP * k * float(t)
			if t <= e:
				draw_line(a, b, DIR_COL[d].darkened(0.25), 5.0, true)
			else:
				draw_dashed_line(a, b, Color(0.4, 0.42, 0.48), 2.0, 6.0)
		if e > 0:
			var tip := _rect(d, e)
			var name: String = SkillTreeData.DIR_NAME[d]
			var at := tip.position + (Vector2(tip.size.x + 10, tip.size.y * 0.5 + 5) if d in ["n", "s"] else Vector2(0, -8))
			draw_string(bold, at, "%s (끝 %d단계)" % [name, e], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIR_COL[d].lightened(0.2))
	for s in _slots():
		var r := _rect(s.dir, s.tier)
		var hov: bool = hovered == "+%s:%d" % [s.dir, s.tier]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.bg_color = Color(0.1, 0.11, 0.14, 0.6) if not hov else Color(0.16, 0.18, 0.22)
		sb.border_color = Color(0.4, 0.42, 0.48) if not hov else Color(DIR_COL[s.dir])
		draw_style_box(sb, r)
		draw_string(bold, r.position + Vector2(0, r.size.y * 0.5 + 6), "+ %s" % ("중앙" if s.dir == "center" else "%d단계" % s.tier),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, maxi(11, roundi(15 * k)), Color(0.7, 0.72, 0.78) if not hov else Color.WHITE)
	for n in nodes:
		_draw_node(n, k)


func _draw_node(n: Dictionary, k: float) -> void:
	var r := _rect(n.dir, int(n.tier))
	var col: Color = DIR_COL[n.dir]
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.bg_color = col.darkened(0.6)
	sb.border_color = col
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
	draw_string(font, r.position + Vector2(4, r.size.y - 8 * k), "Lv %d" % int(n.level), HORIZONTAL_ALIGNMENT_CENTER, cap, maxi(9, roundi(12 * k)), col.lightened(0.5))
