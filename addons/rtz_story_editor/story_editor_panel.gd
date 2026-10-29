@tool
extends Control
## 스토리 흐름 탭 (Godot 에디터 상단 "스토리"): 퀘스트 · 컷씬 · 신 정체 해금 · 미션 · 계기가 어떻게 이어지는지 한 그림으로 (StoryGraph, 읽기 전용).
## 왼쪽 = 흐름 그림 (왼쪽이 먼저, 오른쪽이 나중 · 노드 클릭 = 자세히 · 끌기 = 옮기기 · 휠 = 확대 · 더블클릭 = 그 탭 열기)
## 오른쪽 = 고른 노드: 어디서 와서(들어오는 선) 어디로 가는지(나가는 선, 눌러서 따라가기) · 내용 · '퀘스트 탭 / 컷씬 탭에서 열기' · 아래 검사 (끊긴 흐름 · 없는 대상).
## 고치는 건 퀘스트 · 컷씬 · 스킬 트리(기적) 탭 — 이 탭을 다시 열면 저장된 파일을 다시 읽음.

const CANVAS := preload("res://addons/rtz_story_editor/story_canvas.gd")

var graph: StoryGraph
var sel := ""
var canvas: Control
var detail: RichTextLabel
var check_label: RichTextLabel
var status: Label
var info_label: Label
var kind_btns: Dictionary = {}
var open_btn: Button
var quests: Array = []
var cutscenes: Array = []
var divine: Dictionary = {}
var npc_names: Dictionary = {}
var char_names: Dictionary = {}
var names: Dictionary = {}
var _fit_pending := true


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	var title := Label.new()
	title.text = "스토리 흐름"
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	bar.add_child(_btn("다시 읽기", func(): reload_data()))
	bar.add_child(_btn("전체 보기", func(): canvas.fit()))
	bar.add_child(VSeparator.new())
	bar.add_child(_lab("보기:"))
	for k in ["quest", "cutscene", "divine", "mission", "start"]:
		var b := CheckBox.new()
		b.text = StoryGraph.KIND_NAME[k]
		b.button_pressed = true
		b.focus_mode = Control.FOCUS_NONE
		var kk: String = k
		b.toggled.connect(func(on):
			canvas.hide_kinds[kk] = not on
			canvas.queue_redraw())
		kind_btns[k] = b
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	open_btn = _btn("고른 것을 그 탭에서 열기", _open_selected)
	bar.add_child(open_btn)
	status = _lab("")
	status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	bar.add_child(status)
	info_label = _lab("")
	root.add_child(info_label)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	canvas = CANVAS.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(600, 400)
	canvas.node_clicked.connect(func(id):
		sel = id
		_fill_detail())
	canvas.node_double_clicked.connect(func(id):
		sel = id
		_fill_detail()
		_open_selected())
	body.add_child(canvas)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 380
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_head("고른 것"))
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.scroll_active = true
	detail.meta_clicked.connect(func(m):
		var id := str(m)
		if id.begins_with("open:"):
			sel = id.substr(5)
			_open_selected()
		elif graph != null and graph.nodes.has(id):
			sel = id
			canvas.selected = id
			canvas.focus_node(id)
			_fill_detail())
	right.add_child(detail)
	right.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.custom_minimum_size.y = 170
	check_label.scroll_active = true
	right.add_child(check_label)
	right.add_child(_small("읽기 전용 — 고치려면 퀘스트 · 컷씬 · 스킬 트리(기적) 탭. 왼쪽이 먼저, 오른쪽이 나중. 끌기 = 옮기기 · 휠 = 확대 · 더블클릭 = 그 탭 열기."))
	reload_data()


## 퀘스트 · 컷씬 · 신 해금 파일과 이름표(대원 · 의뢰 · 연구 · 스테이지)를 다시 읽어 그래프를 새로 짬
func reload_data() -> void:
	quests = QuestData.read()
	cutscenes = CutsceneData.read()
	divine = FaithData.read().get("divine", {})
	npc_names = {}
	char_names = {}
	names = {}
	var od := OutgameData.load_from()
	var gd := GameData.load_from()
	if od != null:
		for id in od.npc_order:
			npc_names[id] = str(od.npcs[id].name)
	if gd != null:
		for u in gd.allies:
			char_names[u.id] = u.display_name
	names = QuestData.target_names(od, gd, quests)
	graph = StoryGraph.new()
	graph.build(quests, cutscenes, divine, names, npc_names, char_names)
	if sel != "" and not graph.nodes.has(sel):
		sel = ""
	canvas.show_graph(graph, sel)
	info_label.text = "퀘스트 %d · 컷씬 %d · 신 정체 해금 %d · 미션 %d · 계기 %d · 선 %d" % [
		_count("quest"), _count("cutscene"), _count("divine"), _count("mission"), _count("start"), graph.edges.size()]
	status.text = "data/quests.json · cutscenes.json · faith.json 읽음"
	_fill_detail()
	_fill_check()
	if _fit_pending or canvas.size.x < 10.0:
		call_deferred("_fit_later")


func _fit_later() -> void:
	await get_tree().process_frame
	canvas.fit()
	_fit_pending = false


func _count(kind: String) -> int:
	var n := 0
	for id in graph.order:
		if graph.nodes[id].kind == kind:
			n += 1
	return n


func _fill_detail() -> void:
	canvas.selected = sel
	canvas.queue_redraw()
	open_btn.disabled = not (sel.begins_with("q:") or sel.begins_with("c:") or sel.begins_with("d:"))
	if graph == null or not graph.nodes.has(sel):
		detail.text = "[color=#9aa0ad]노드를 클릭하세요.\n\n[/color][color=#d9a03a]■[/color] 퀘스트  [color=#5c9eeb]■[/color] 컷씬  [color=#c773f2]■[/color] 신 정체 해금  [color=#66a975]■[/color] 미션(의뢰·전투·연구)  [color=#6b7085]■[/color] 계기(새 게임 · n일차 · 말 걸기 …)\n\n선 = 왼쪽 것이 먼저 일어나고 오른쪽 것으로 이어짐. 선 위 글 = 어떻게 이어지는지 (시작 · n단계 · 완료 때 · 다음 · 선택 · 퀘스트 시작 · 정체 해금)."
		return
	var n: Dictionary = graph.nodes[sel]
	var col: String = {"quest": "#d9a03a", "cutscene": "#5c9eeb", "divine": "#c773f2", "mission": "#66a975", "start": "#9aa0ad"}.get(n.kind, "#ffffff")
	var t := "[color=%s][b]%s[/b][/color]  [color=#9aa0ad]%s · %s[/color]\n" % [col, n.title, StoryGraph.KIND_NAME.get(n.kind, ""), n.ref]
	for line in n.sub:
		t += "  %s\n" % line
	if n.kind == "cutscene":
		var c := _cutscene(n.ref)
		if not c.is_empty():
			t += "[color=#9aa0ad]계기: %s%s[/color]\n" % [CutsceneData.TRIGGERS.get(c.trigger.type, c.trigger.type), " · " + str(c.trigger.target) if str(c.trigger.target) != "" else ""]
			var k := 0
			for st in c.steps:
				if str(st.type) in ["say", "narration"]:
					t += "  [color=#c8ccd8]%s[/color]\n" % _clip(CutsceneData.step_text(st, npc_names), 60)
					k += 1
					if k >= 4:
						t += "  [color=#6b7085]…[/color]\n"
						break
	elif n.kind == "quest":
		var q := _quest(n.ref)
		if not q.is_empty():
			t += "[color=#9aa0ad]시작 조건: %s · 의뢰인 %s[/color]\n" % [UnlockCond.describe(q.start, names), npc_names.get(q.giver, q.giver if str(q.giver) != "" else "없음")]
	var ins := graph.in_edges(sel)
	var outs := graph.out_edges(sel)
	t += "\n[b]어디서 오나[/b] (%d)\n" % ins.size()
	if ins.is_empty():
		t += "  [color=#6b7085](처음 — 아무 데서도 이어지지 않음)[/color]\n"
	for e in ins:
		t += "  ← [url=%s]%s[/url]  [color=#9aa0ad]%s[/color]\n" % [e.from, graph.nodes[e.from].title, e.label]
	t += "\n[b]어디로 가나[/b] (%d)\n" % outs.size()
	if outs.is_empty():
		t += "  [color=#6b7085](끝 — 더 이어지는 것이 없음)[/color]\n"
	for e in outs:
		t += "  → [url=%s]%s[/url]  [color=#9aa0ad]%s[/color]\n" % [e.to, graph.nodes[e.to].title, e.label]
	if not open_btn.disabled:
		t += "\n[url=open:%s]▶ %s 탭에서 열기[/url]" % [sel, {"q": "퀘스트", "c": "컷씬", "d": "스킬 트리 (기적)"}[sel.substr(0, 1)]]
	detail.text = t


func _fill_check() -> void:
	var txt := ""
	for e in graph.errors:
		txt += "[color=#ff7766]✖ %s[/color]\n" % e
	for e in graph.notes:
		txt += "[color=#ffd166]△ %s[/color]\n" % e
	check_label.text = txt if txt != "" else "[color=#77dd88]문제 없음 — 끊긴 흐름 · 없는 대상 없음[/color]"


func _quest(id: String) -> Dictionary:
	for q in quests:
		if q.id == id:
			return q
	return {}


func _cutscene(id: String) -> Dictionary:
	for c in cutscenes:
		if c.id == id:
			return c
	return {}


## 고른 퀘스트 · 컷씬 · 신 해금을 그 탭에서 열기 (그 탭 패널의 고른 항목을 바꾸고 탭 전환)
func _open_selected() -> void:
	if sel == "" or not Engine.is_editor_hint():
		status.text = "에디터에서만 탭을 옮길 수 있습니다" if sel != "" else ""
		return
	var ref := sel.substr(2)
	var want: Array = {"q": ["quest_editor_panel.gd", "퀘스트", "sel"], "c": ["cutscene_editor_panel.gd", "컷씬", "sel"], "d": ["skill_editor_panel.gd", "스킬 트리", "mchar"]}.get(sel.substr(0, 1), [])
	if want.is_empty():
		return
	for p in EditorInterface.get_editor_main_screen().get_children():
		var scr: Script = p.get_script()
		if scr != null and scr.resource_path.ends_with(str(want[0])):
			if str(want[2]) == "mchar":
				p.kind = "miracle"
			p.set(str(want[2]), ref)
			if p.has_method("_rebuild"):
				p._rebuild()
	EditorInterface.set_main_screen_editor(str(want[1]))


func _clip(t: String, n: int) -> String:
	return t if t.length() <= n else t.substr(0, n) + "…"


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _lab(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	return l


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l
