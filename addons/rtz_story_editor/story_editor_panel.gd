@tool
extends Control
## 스토리 흐름 탭 (Godot 에디터 상단 "스토리"): 퀘스트 · 컷씬 · 신 정체 해금 · 미션 · 계기가 어떻게 이어지는지 한 그림으로 (StoryGraph) + 여기서 바로 편집 (StoryEdit).
## 왼쪽 = 흐름 그림 (왼쪽이 먼저, 오른쪽이 나중 · 노드 클릭 = 자세히 · 노드 끌기 = 자리 옮기기 · 빈 곳 끌기 = 화면 옮기기 · 휠 = 확대 · 더블클릭 = 그 탭 열기)
##   **Shift+노드에서 끌어 다른 노드에 놓기 = 선 긋기** (무슨 뜻으로 이을지 고르는 창) · 선 클릭 → Delete = 선 지우기 (데이터에서 그 연결을 뺌) · 노드 고르고 Delete = 퀘스트·컷씬 삭제
## 위: + 퀘스트 · + 컷씬 · + 계기(새 게임 · n일차 · 말 걸기 · 엿듣기 · 전투 승리 · 처음부터 · 직접) · 저장(Ctrl+S) · 되돌리기 · 자동 배치 · 전체 보기 · 보기 필터
## 오른쪽 = 고른 노드: 이름 · (퀘스트) 의뢰인 · 설명 / (컷씬) 분류 · 한 번만 · 설명 바로 고치기, 어디서 와서 어디로 가는지(눌러서 따라가기), '그 탭에서 열기'(단계·대사 같은 세부). 아래 검사.
## 저장 = data/quests.json · cutscenes.json · faith.json(divine) · story_layout.json(끌어 놓은 자리). Ctrl+Z / Ctrl+Y 뒤로·앞으로 감기.

const CANVAS := preload("res://addons/rtz_story_editor/story_canvas.gd")
const LAYOUT_PATH := "res://data/story_layout.json"

var history: EditorHistory
var graph: StoryGraph
var d: Dictionary = {"quests": [], "cutscenes": [], "divine": {}}   # 편집 중인 데이터
var faith: Dictionary = {}          # faith.json 전체 (divine 만 여기서 고침)
var layout: Dictionary = {}         # 노드 id → [x, y]
var extra_starts: Array = []        # [[key, title]] 아직 안 이은 계기 노드
var dirty := false
var _rebuilding := false
var sel := ""
var sel_edge := -1
var canvas: Control
var detail: RichTextLabel
var form: VBoxContainer
var check_label: RichTextLabel
var status: Label
var info_label: Label
var kind_btns: Dictionary = {}
var open_btn: Button
var npc_names: Dictionary = {}
var npc_order: Array = []
var char_names: Dictionary = {}
var names: Dictionary = {}
var _fit_pending := true
var _popup: PopupMenu
var _popup_link: Array = []         # [from, to, options]
var _start_popup: PopupMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var bar := HFlowContainer.new()   # 좁으면 줄바꿈
	bar.add_theme_constant_override("h_separation", 8)
	root.add_child(bar)
	var title := Label.new()
	title.text = "스토리 흐름"
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	bar.add_child(_btn("저장 (Ctrl+S)", _save))
	bar.add_child(_btn("되돌리기", func(): reload_data(false)))
	bar.add_child(VSeparator.new())
	bar.add_child(_btn("+ 퀘스트", _add_quest))
	bar.add_child(_btn("+ 컷씬", _add_cutscene))
	var sbtn := _btn("+ 계기 ▾", func(): _start_popup.position = Vector2i(get_global_mouse_position()); _start_popup.popup())
	bar.add_child(sbtn)
	bar.add_child(VSeparator.new())
	bar.add_child(_btn("자동 배치", func():
		layout.clear()
		_mark()
		_rebuild()
		canvas.fit()))
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
	open_btn = _btn("그 탭에서 열기", _open_selected)
	bar.add_child(open_btn)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	root.add_child(row2)
	info_label = _lab("")
	row2.add_child(info_label)
	status = _lab("")
	status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	row2.add_child(status)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	canvas = CANVAS.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(600, 400)
	canvas.node_clicked.connect(func(id):
		sel = id
		sel_edge = -1
		_fill_detail())
	canvas.node_double_clicked.connect(func(id):
		sel = id
		_fill_detail()
		_open_selected())
	canvas.node_moved.connect(func(id, pos):
		layout[id] = [pos.x, pos.y]
		_mark())
	canvas.edge_clicked.connect(func(i):
		sel_edge = i
		sel = ""
		_fill_detail())
	canvas.background_clicked.connect(func():
		sel = ""
		sel_edge = -1
		_fill_detail())
	canvas.link_requested.connect(_ask_link)
	canvas.delete_pressed.connect(_delete_selected)
	body.add_child(canvas)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(sc)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	sc.add_child(form)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.scroll_active = false
	detail.meta_clicked.connect(func(m):
		var id := str(m)
		if id.begins_with("open:"):
			sel = id.substr(5)
			_open_selected()
		elif id.begins_with("edge:"):
			sel_edge = int(id.substr(5))
			sel = ""
			canvas.selected_edge = sel_edge
			_fill_detail()
		elif graph != null and graph.nodes.has(id):
			sel = id
			sel_edge = -1
			canvas.selected = id
			canvas.focus_node(id)
			_fill_detail())
	right.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.custom_minimum_size.y = 150
	check_label.scroll_active = true
	right.add_child(check_label)
	right.add_child(_small("Shift+노드 끌어서 다른 노드에 놓기 = 선 긋기 · 선 클릭 → Delete = 선 지우기 · 노드 끌기 = 자리 옮기기 · 휠 = 확대 · 더블클릭 = 그 탭 열기. 단계·대사 같은 세부는 퀘스트 · 컷씬 탭에서 (이 탭에서 저장한 뒤 그 탭을 열면 반영)."))
	_popup = PopupMenu.new()
	_popup.id_pressed.connect(_on_link_chosen)
	add_child(_popup)
	_start_popup = PopupMenu.new()
	for it in [["new_game", "새 게임 (오프닝)"], ["day", "n일차…"], ["talk", "대원에게 말 걸기…"], ["overhear", "대원끼리 대화 엿듣기"], ["battle_win", "전투 승리"], ["always", "처음부터"], ["manual", "직접 (스크립트)"]]:
		_start_popup.add_item(it[1])
		_start_popup.set_item_metadata(_start_popup.item_count - 1, it[0])
	_start_popup.id_pressed.connect(func(i): _add_start(str(_start_popup.get_item_metadata(i))))
	add_child(_start_popup)
	history = EditorHistory.new(_hist_snap, _hist_apply)
	reload_data(false)


func _process(delta: float) -> void:
	if history != null and is_visible_in_tree():
		history.tick(delta)


func _input(event: InputEvent) -> void:
	EditorHistory.handle_input(self, event, history, status)


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 읽기 · 저장
## keep_edit = 편집 중이면 데이터는 두고 이름표만 다시 읽음 (탭을 다시 열 때)
func reload_data(keep_edit: bool = true) -> void:
	var od := OutgameData.load_from()
	var gd := GameData.load_from()
	npc_names = {}
	npc_order = []
	char_names = {}
	if od != null:
		for id in od.npc_order:
			npc_names[id] = str(od.npcs[id].name)
			npc_order.append(id)
	if gd != null:
		for u in gd.allies:
			char_names[u.id] = u.display_name
	if not (keep_edit and dirty):
		faith = FaithData.read()
		d = {"quests": QuestData.read(), "cutscenes": CutsceneData.read(), "divine": faith.get("divine", {})}
		layout = {}
		if FileAccess.file_exists(LAYOUT_PATH):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
			if j is Dictionary and j.get("pos") is Dictionary:
				layout = j.pos
		extra_starts = []
		dirty = false
		status.text = "data/quests.json · cutscenes.json · faith.json 읽음"
		history.reset()
	names = QuestData.target_names(od, gd, d.quests)
	_rebuild()
	if _fit_pending or canvas.size.x < 10.0:
		call_deferred("_fit_later")


func _save() -> void:
	var e1 := QuestData.write(d.quests)
	var e2 := CutsceneData.write(d.cutscenes)
	faith.divine = d.divine
	var e3 := FaithData.write(faith)
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	var e4 := OK
	if f != null:
		f.store_string(JSON.stringify({"version": 1, "pos": layout}, "\t", false))
	else:
		e4 = FileAccess.get_open_error()
	if e1 == OK and e2 == OK and e3 == OK and e4 == OK:
		dirty = false
		status.text = "저장됨: quests.json · cutscenes.json · faith.json · story_layout.json" + ("" if graph.errors.is_empty() else "  (검사 오류 %d개)" % graph.errors.size())
		if Engine.is_editor_hint():
			for path in [QuestData.PATH, CutsceneData.PATH, FaithData.PATH, LAYOUT_PATH]:
				EditorInterface.get_resource_filesystem().update_file(path)
	else:
		status.text = "저장 실패 (%d / %d / %d / %d)" % [e1, e2, e3, e4]


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 함)"


func _hist_snap() -> String:
	return var_to_str([d, layout, extra_starts])


func _hist_apply(s: String) -> void:
	var v: Array = str_to_var(s)
	d = v[0]
	layout = v[1]
	extra_starts = v[2]
	dirty = true
	_rebuild()


# ================================================================ 그래프
func _rebuild() -> void:
	_rebuilding = true
	graph = StoryGraph.new()
	graph.extra_starts = extra_starts
	for id in layout:
		var p: Array = layout[id]
		graph.manual_pos[id] = Vector2(float(p[0]), float(p[1]))
	graph.build(d.quests, d.cutscenes, d.divine, names, npc_names, char_names)
	if sel != "" and not graph.nodes.has(sel):
		sel = ""
	if sel_edge >= graph.edges.size():
		sel_edge = -1
	canvas.selected_edge = sel_edge
	canvas.show_graph(graph, sel)
	info_label.text = "퀘스트 %d · 컷씬 %d · 신 정체 해금 %d · 미션 %d · 계기 %d · 선 %d" % [
		_count("quest"), _count("cutscene"), _count("divine"), _count("mission"), _count("start"), graph.edges.size()]
	_fill_detail()
	_fill_check()
	_rebuilding = false


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


# ================================================================ 편집
func _add_quest() -> void:
	var q := StoryEdit.add_quest(d)
	sel = "q:" + str(q.id)
	_mark()
	_rebuild()
	canvas.focus_node(sel)


func _add_cutscene() -> void:
	var c := StoryEdit.add_cutscene(d)
	sel = "c:" + str(c.id)
	_mark()
	_rebuild()
	canvas.focus_node(sel)


## 계기 노드 추가 (아직 아무것도 안 이음 — Shift 끌기로 퀘스트·컷씬에 이어 주면 그 조건이 됨)
func _add_start(kind: String) -> void:
	var key := kind
	var title := ""
	match kind:
		"new_game": title = "새 게임"
		"overhear": title = "대원끼리 대화 엿듣기"
		"battle_win": title = "전투 승리"
		"always": title = "처음부터"
		"manual": title = "직접 (스크립트)"
		"day":
			var day := 2
			while extra_starts.any(func(e): return e[0] == "day:%d" % day) or graph.nodes.has("s:day:%d" % day):
				day += 1
			key = "day:%d" % day
			title = "%d일차" % day
		"talk":
			if npc_order.is_empty():
				status.text = "대원이 없습니다"
				return
			var pm := PopupMenu.new()
			for id in npc_order:
				pm.add_item(str(npc_names[id]))
				pm.set_item_metadata(pm.item_count - 1, id)
			pm.id_pressed.connect(func(i):
				var nid := str(pm.get_item_metadata(i))
				extra_starts.append(["talk:" + nid, "말 걸기: %s" % npc_names[nid]])
				_mark()
				_rebuild()
				pm.queue_free())
			add_child(pm)
			pm.position = Vector2i(get_global_mouse_position())
			pm.popup()
			return
	if graph.nodes.has("s:" + key) or extra_starts.any(func(e): return e[0] == key):
		sel = "s:" + key
		_fill_detail()
		canvas.focus_node(sel)
		status.text = "이미 있는 계기 — 고름"
		return
	extra_starts.append([key, title])
	sel = "s:" + key
	_mark()
	_rebuild()
	canvas.focus_node(sel)


## Shift 끌기로 두 노드를 이었을 때: 가능한 뜻을 창으로 (하나뿐이면 바로)
func _ask_link(from: String, to: String) -> void:
	var opts := StoryEdit.link_options(from, to, d)
	if opts.is_empty():
		status.text = "'%s' → '%s' 는 이을 수 없습니다 (%s → %s)" % [graph.nodes[from].title, graph.nodes[to].title, StoryGraph.KIND_NAME[graph.nodes[from].kind], StoryGraph.KIND_NAME[graph.nodes[to].kind]]
		return
	_popup_link = [from, to, opts]
	if opts.size() == 1:
		_on_link_chosen(0)
		return
	_popup.clear()
	for i in opts.size():
		_popup.add_item(str(opts[i].label), i)
	_popup.position = Vector2i(get_global_mouse_position())
	_popup.popup()


func _on_link_chosen(i: int) -> void:
	if _popup_link.is_empty():
		return
	var from: String = _popup_link[0]
	var to: String = _popup_link[1]
	var opt: Dictionary = _popup_link[2][i]
	var err := StoryEdit.apply_link(str(opt.id), from, to, d)
	if err != "":
		status.text = err
		return
	# 이었으니 임시 계기 노드는 더 이상 따로 둘 필요 없음 (데이터에서 생김)
	extra_starts = extra_starts.filter(func(e): return "s:" + str(e[0]) != from)
	_mark()
	_rebuild()
	sel = to
	sel_edge = -1
	canvas.selected = sel
	_fill_detail()
	status.text = "이음: %s" % opt.label


func _delete_selected() -> void:
	if sel_edge >= 0 and sel_edge < graph.edges.size():
		var e: Dictionary = graph.edges[sel_edge]
		var err := StoryEdit.unlink(e.src, d)
		if err != "":
			status.text = err
			return
		status.text = "선 지움: %s → %s (%s)" % [graph.nodes[e.from].title, graph.nodes[e.to].title, e.label]
		sel_edge = -1
		_mark()
		_rebuild()
		return
	if sel == "":
		return
	var kind := sel.substr(0, 1)
	var ref := sel.substr(2)
	match kind:
		"q":
			StoryEdit.remove_quest(d, ref)
			status.text = "퀘스트 삭제: %s (가리키던 곳도 정리)" % ref
		"c":
			StoryEdit.remove_cutscene(d, ref)
			status.text = "컷씬 삭제: %s (가리키던 곳도 정리)" % ref
		"s":
			var n0 := extra_starts.size()
			extra_starts = extra_starts.filter(func(e): return "s:" + str(e[0]) != sel)
			if extra_starts.size() == n0:
				status.text = "이 계기는 퀘스트·컷씬이 쓰고 있어 선을 지워야 사라집니다"
				return
		_:
			status.text = "신 해금 · 미션은 여기서 지우지 않습니다 (스킬 트리 · 엑셀)"
			return
	layout.erase(sel)
	sel = ""
	_mark()
	_rebuild()


# ================================================================ 오른쪽
func _fill_detail() -> void:
	canvas.selected = sel
	canvas.selected_edge = sel_edge
	canvas.queue_redraw()
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	open_btn.disabled = not (sel.begins_with("q:") or sel.begins_with("c:") or sel.begins_with("d:"))
	if sel_edge >= 0 and graph != null and sel_edge < graph.edges.size():
		var e: Dictionary = graph.edges[sel_edge]
		form.add_child(_head("고른 선"))
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "[url=%s]%s[/url]  →  [url=%s]%s[/url]\n[color=#ffd166]%s[/color]\n\n[color=#9aa0ad]%s[/color]" % [e.from, graph.nodes[e.from].title, e.to, graph.nodes[e.to].title, e.label if str(e.label) != "" else "(이어짐)", _src_text(e.src)]
		l.meta_clicked.connect(func(m): detail.meta_clicked.emit(m))
		form.add_child(l)
		form.add_child(_btn("이 선 지우기 (Delete)", _delete_selected))
		form.add_child(detail)
		detail.text = ""
		return
	if graph == null or not graph.nodes.has(sel):
		form.add_child(_head("고른 것"))
		form.add_child(detail)
		detail.text = "[color=#9aa0ad]노드를 클릭하세요.\n\n[/color][color=#d9a03a]■[/color] 퀘스트  [color=#5c9eeb]■[/color] 컷씬  [color=#c773f2]■[/color] 신 정체 해금  [color=#66a975]■[/color] 미션(의뢰·전투·연구)  [color=#6b7085]■[/color] 계기(새 게임 · n일차 · 말 걸기 …)\n\n선 = 왼쪽 것이 먼저 일어나고 오른쪽 것으로 이어짐. 선 위 글 = 어떻게 이어지는지.\n\n[b]선 긋기[/b]: Shift 를 누른 채 노드를 끌어 다른 노드에 놓으면 무슨 뜻으로 이을지 고르는 창이 뜹니다 (예: 퀘스트 → 컷씬: 시작 때 · 완료 때 재생 / 컷씬 → 컷씬: 다음 · 선택지).\n[b]선 지우기[/b]: 선을 클릭하고 Delete."
		return
	var n: Dictionary = graph.nodes[sel]
	var col: String = {"quest": "#d9a03a", "cutscene": "#5c9eeb", "divine": "#c773f2", "mission": "#66a975", "start": "#9aa0ad"}.get(n.kind, "#ffffff")
	form.add_child(_head("%s · %s" % [StoryGraph.KIND_NAME.get(n.kind, ""), n.ref]))
	if n.kind == "quest":
		_quest_form(StoryEdit.quest(d, n.ref))
	elif n.kind == "cutscene":
		_cutscene_form(StoryEdit.cutscene(d, n.ref))
	form.add_child(detail)
	var t := "[color=%s][b]%s[/b][/color]\n" % [col, n.title]
	for line in n.sub:
		t += "  %s\n" % line
	if n.kind == "cutscene":
		var c := StoryEdit.cutscene(d, n.ref)
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
		var q := StoryEdit.quest(d, n.ref)
		if not q.is_empty():
			t += "[color=#9aa0ad]시작 조건: %s[/color]\n" % UnlockCond.describe(q.start, names)
	var ins: Array = graph.in_edges(sel)
	var outs: Array = graph.out_edges(sel)
	t += "\n[b]어디서 오나[/b] (%d)\n" % ins.size()
	if ins.is_empty():
		t += "  [color=#6b7085](처음 — 아무 데서도 이어지지 않음)[/color]\n"
	for e in ins:
		t += "  ← [url=%s]%s[/url]  [url=edge:%d][color=#9aa0ad]%s[/color][/url]\n" % [e.from, graph.nodes[e.from].title, graph.edges.find(e), e.label if str(e.label) != "" else "(선)"]
	t += "\n[b]어디로 가나[/b] (%d)\n" % outs.size()
	if outs.is_empty():
		t += "  [color=#6b7085](끝 — 더 이어지는 것이 없음)[/color]\n"
	for e in outs:
		t += "  → [url=%s]%s[/url]  [url=edge:%d][color=#9aa0ad]%s[/color][/url]\n" % [e.to, graph.nodes[e.to].title, graph.edges.find(e), e.label if str(e.label) != "" else "(선)"]
	if not open_btn.disabled:
		t += "\n[url=open:%s]▶ %s 탭에서 열기[/url] (단계 · 대사 · 보상 같은 세부)" % [sel, {"q": "퀘스트", "c": "컷씬", "d": "스킬 트리 (기적)"}[sel.substr(0, 1)]]
	if n.kind in ["quest", "cutscene"]:
		t += "\n[color=#6b7085]Delete = 이 %s 삭제 (가리키던 곳도 정리)[/color]" % StoryGraph.KIND_NAME[n.kind]
	detail.text = t


func _src_text(src: Dictionary) -> String:
	match str(src.get("k", "")):
		"qstart": return "퀘스트 시작 조건 — 지우면 '직접 시작' 이 됨"
		"qstep": return "퀘스트 %d단계 — 지우면 그 단계가 빠짐" % (int(src.i) + 1)
		"ctrig": return "컷씬 계기 — 지우면 '없음' 이 됨"
		"cnext": return "다음 컷씬 — 지우면 비움"
		"cchoice": return "선택지가 이어 주는 컷씬 — 지우면 그 선택지는 '끝' 으로"
		"caction": return "컷씬 행동 — 지우면 그 행동이 빠짐"
		"dcond": return "신 해금 조건 — 지우면 '직접 해금' 이 됨"
	return ""


func _quest_form(q: Dictionary) -> void:
	if q.is_empty():
		return
	var g := _grid()
	form.add_child(g)
	_row(g, "이름", _line(str(q.name), func(v):
		q.name = v
		_mark()
		_rebuild_keep()))
	var who := [["", "(없음)"]]
	for id in npc_order:
		who.append([id, str(npc_names[id])])
	_row(g, "의뢰인", _option(who, str(q.giver), func(v):
		q.giver = str(v)
		_mark()
		_rebuild_keep()))
	_row(g, "설명", _line(str(q.desc), func(v):
		q.desc = v
		_mark()))


func _cutscene_form(c: Dictionary) -> void:
	if c.is_empty():
		return
	var g := _grid()
	form.add_child(g)
	_row(g, "이름", _line(str(c.name), func(v):
		c.name = v
		_mark()
		_rebuild_keep()))
	var kinds := []
	for k in CutsceneData.KIND_ORDER:
		kinds.append([k, CutsceneData.KINDS[k]])
	_row(g, "분류", _option(kinds, str(c.kind), func(v):
		c.kind = str(v)
		_mark()
		_rebuild_keep()))
	var once := CheckBox.new()
	once.text = "한 번만 재생"
	once.button_pressed = bool(c.get("once", true))
	once.toggled.connect(func(on):
		c.once = on
		_mark()
		_rebuild_keep())
	_row(g, "", once)


## 글자를 치는 중에도 그래프는 갱신하되 오른쪽 칸은 다시 만들지 않음 (커서가 안 튀게)
func _rebuild_keep() -> void:
	var keep_sel := sel
	var keep_edge := sel_edge
	graph = StoryGraph.new()
	graph.extra_starts = extra_starts
	for id in layout:
		var p: Array = layout[id]
		graph.manual_pos[id] = Vector2(float(p[0]), float(p[1]))
	graph.build(d.quests, d.cutscenes, d.divine, names, npc_names, char_names)
	sel = keep_sel
	sel_edge = keep_edge
	canvas.show_graph(graph, sel)
	_fill_check()


func _fill_check() -> void:
	var txt := ""
	for e in graph.errors:
		txt += "[color=#ff7766]✖ %s[/color]\n" % e
	for e in graph.notes:
		txt += "[color=#ffd166]△ %s[/color]\n" % e
	check_label.text = txt if txt != "" else "[color=#77dd88]문제 없음 — 끊긴 흐름 · 없는 대상 없음[/color]"


## 고른 퀘스트 · 컷씬 · 신 해금을 그 탭에서 열기 (그 탭 패널의 고른 항목을 바꾸고 탭 전환). 저장 안 한 편집이 있으면 먼저 저장
func _open_selected() -> void:
	if sel == "" or not Engine.is_editor_hint():
		status.text = "에디터에서만 탭을 옮길 수 있습니다" if sel != "" else ""
		return
	if dirty:
		_save()
	var ref := sel.substr(2)
	var want: Array = {"q": ["quest_editor_panel.gd", "퀘스트", "sel"], "c": ["cutscene_editor_panel.gd", "컷씬", "sel"], "d": ["skill_editor_panel.gd", "스킬 트리", "mchar"]}.get(sel.substr(0, 1), [])
	if want.is_empty():
		return
	for p in EditorInterface.get_editor_main_screen().get_children():
		var scr: Script = p.get_script()
		if scr != null and scr.resource_path.ends_with(str(want[0])):
			if p.has_method("reload_data"):
				p.reload_data(false)   # 여기서 저장한 것을 읽게
			if str(want[2]) == "mchar":
				p.kind = "miracle"
			p.set(str(want[2]), ref)
			if p.has_method("_rebuild"):
				p._rebuild()
	EditorInterface.set_main_screen_editor(str(want[1]))


# ================================================================ 위젯
func _clip(t: String, n: int) -> String:
	return t if t.length() <= n else t.substr(0, n) + "…"


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 4)
	return g


func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	grid.add_child(_lab(label))
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


func _line(t: String, cb: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = t
	le.text_changed.connect(cb)
	return le


func _option(items: Array, cur: Variant, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i][1]))
		o.set_item_metadata(i, items[i][0])
		if items[i][0] == cur:
			o.select(i)
	o.item_selected.connect(func(i): cb.call(o.get_item_metadata(i)))
	return o


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
	l.custom_minimum_size.x = 380
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l
