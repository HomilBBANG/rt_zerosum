extends Control
## AI 노드 에디터: data/ai/<id>.json 을 노드 그래프로 편집.
## 왼쪽 목록에서 노드를 추가 → 출력 점을 끌어 다른 노드 입력에 연결 → 저장. 저장하면 실행 중인 게임에도 바로 반영.
## 몬스터가 어떤 AI 를 쓸지는 밸런스 엑셀 "몬스터" 시트의 AI 열.

const COL_IN := Color(0.85, 0.85, 0.9)
const COL_YES := Color(0.35, 0.9, 0.5)
const COL_NO := Color(1.0, 0.4, 0.35)
const COL_FAIL := Color(1.0, 0.7, 0.25)

var graph: GraphEdit
var ai_list: OptionButton
var new_id: LineEdit
var status: Label
var users_label: Label
var current_id := ""
var _counter := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -8
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	top.add_child(_title("AI 에디터"))
	ai_list = OptionButton.new()
	ai_list.custom_minimum_size.x = 160
	ai_list.item_selected.connect(func(i): _load(ai_list.get_item_text(i)))
	top.add_child(ai_list)
	new_id = LineEdit.new()
	new_id.placeholder_text = "새 AI 이름 (영문)"
	new_id.custom_minimum_size.x = 150
	top.add_child(new_id)
	top.add_child(_btn("새로 만들기", _create))
	top.add_child(_btn("저장", _save))
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_btn("메뉴로", func(): Game.go_menu()))
	users_label = Label.new()
	users_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	users_label.add_theme_font_size_override("font_size", 13)
	root.add_child(users_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	var pal := VBoxContainer.new()
	pal.custom_minimum_size.x = 210
	pal.add_theme_constant_override("separation", 4)
	body.add_child(pal)
	pal.add_child(_small("노드 추가"))
	for t in AIGraph.TYPES:
		if t == "start":
			continue
		var tt: String = t
		var b := _btn("＋ " + AIGraph.TYPES[t].title, func(): _add_at_center(tt))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pal.add_child(b)
	var help := _small("· 출력 점을 끌어 다른 노드의 입력 점에 연결\n· 연결 끝을 끌어 떼면 연결 해제\n· 노드 선택 후 Delete 로 삭제\n· 위에서부터: 조건은 예/아니오,\n  스킬은 성공하면 그 행동, 안 되면 '실패 시'\n· 행동 하나마다 시작부터 다시 평가\n· 저장하면 실행 중인 게임에 즉시 반영")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pal.add_child(help)
	graph = GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.zoom = 0.8
	graph.connection_request.connect(_on_connect)
	graph.disconnection_request.connect(func(f, fp, t, tp): graph.disconnect_node(f, fp, t, tp))
	graph.delete_nodes_request.connect(_on_delete)
	body.add_child(graph)
	_refresh_list()
	var ids := AIGraph.list_ids()
	if not ids.is_empty():
		_load(Game.cli.get("ai", ids[0]) if Game.cli.get("ai", "") in ids else ids[0])
	Game.maybe_cli_capture()


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", load("res://assets/fonts/Pretendard-Bold.ttf"))
	l.add_theme_font_size_override("font_size", 20)
	return l


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _refresh_list() -> void:
	ai_list.clear()
	for id in AIGraph.list_ids():
		ai_list.add_item(id)
		if id == current_id:
			ai_list.select(ai_list.item_count - 1)


# ---------------------------------------------------------------- 노드
func _skill_ids() -> Array:
	var out := []
	var acts: Dictionary = Game.actions
	for id in acts:
		if acts[id].kind not in ["move", "weapon"]:
			out.append(id)
	return out


func _make_node(id: String, type: String, params: Dictionary, pos: Vector2) -> GraphNode:
	var def: Dictionary = AIGraph.TYPES.get(type, AIGraph.TYPES.act_end)
	var gn := GraphNode.new()
	gn.name = id
	gn.title = def.title
	gn.position_offset = pos
	gn.set_meta("type", type)
	var p := params.duplicate()
	for pd in def.params:
		if not p.has(pd.key):
			p[pd.key] = pd.default
	gn.set_meta("params", p)
	var outs: Array = def.outputs
	# 0행: 입력(왼쪽) + 첫 출력(오른쪽)
	var row0 := HBoxContainer.new()
	var lin := Label.new()
	lin.text = "" if type == "start" else "입력"
	lin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row0.add_child(lin)
	var lout := Label.new()
	lout.text = outs[0] if not outs.is_empty() else ""
	row0.add_child(lout)
	gn.add_child(row0)
	gn.set_slot(0, type != "start", 0, COL_IN, not outs.is_empty(), 0, _out_color(def, 0))
	# 설정 행
	for pd in def.params:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = pd.label
		l.custom_minimum_size.x = 40
		row.add_child(l)
		row.add_child(_param_control(gn, pd, p[pd.key]))
		gn.add_child(row)
	# 나머지 출력 행 (아니오 등)
	for i in range(1, outs.size()):
		var l := Label.new()
		l.text = outs[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gn.add_child(l)
		gn.set_slot(gn.get_child_count() - 1, false, 0, COL_IN, true, 0, _out_color(def, i))
	graph.add_child(gn)
	return gn


func _out_color(def: Dictionary, i: int) -> Color:
	if def.kind == "cond":
		return COL_YES if i == 0 else COL_NO
	if def.kind == "act":
		return COL_FAIL
	return COL_IN


func _param_control(gn: GraphNode, pd: Dictionary, value: Variant) -> Control:
	var key: String = pd.key
	match str(pd.type):
		"int", "pct":
			var sb := SpinBox.new()
			sb.min_value = 0
			sb.max_value = 100 if pd.type == "pct" else 20
			sb.suffix = "%" if pd.type == "pct" else ""
			sb.value = float(value)
			sb.value_changed.connect(func(v): gn.get_meta("params")[key] = int(v))
			return sb
		"skill", "target":
			var ob := OptionButton.new()
			var opts: Array = _skill_ids() if pd.type == "skill" else AIGraph.TARGETS.keys()
			if pd.type == "skill" and not opts.has(str(value)):
				opts.append(str(value))
			for o in opts:
				var label: String = str(o)
				if pd.type == "skill" and Game.actions.has(o):
					label = "%s (%s)" % [Game.actions[o].display_name, o]
				elif pd.type == "target":
					label = AIGraph.TARGETS[o]
				ob.add_item(label)
				ob.set_item_metadata(ob.item_count - 1, str(o))
				if str(o) == str(value):
					ob.select(ob.item_count - 1)
			ob.item_selected.connect(func(i): gn.get_meta("params")[key] = ob.get_item_metadata(i))
			return ob
	return Label.new()


func _new_node_id(type: String) -> String:
	while true:
		_counter += 1
		var id := "%s_%d" % [type.trim_prefix("cond_").trim_prefix("act_"), _counter]
		if not graph.has_node(NodePath(id)):
			return id
	return ""


func _add_at_center(type: String) -> void:
	var center := (graph.scroll_offset + graph.size * 0.5) / graph.zoom
	var gn := _make_node(_new_node_id(type), type, {}, center - Vector2(90, 40))
	graph.set_selected(gn)


func _on_connect(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	# 출력 하나에는 연결 하나: 기존 연결을 바꿔 끼움
	for c in graph.get_connection_list():
		if c.from_node == from and c.from_port == from_port:
			graph.disconnect_node(c.from_node, c.from_port, c.to_node, c.to_port)
	graph.connect_node(from, from_port, to, to_port)


func _on_delete(names: Array) -> void:
	for n in names:
		var gn := graph.get_node_or_null(NodePath(str(n)))
		if gn == null or gn.get_meta("type") == "start":
			continue
		for c in graph.get_connection_list():
			if c.from_node == n or c.to_node == n:
				graph.disconnect_node(c.from_node, c.from_port, c.to_node, c.to_port)
		gn.queue_free()


# ---------------------------------------------------------------- 파일
func _clear() -> void:
	graph.clear_connections()
	for c in graph.get_children():
		if c is GraphNode:
			graph.remove_child(c)
			c.free()


func _load(id: String) -> void:
	current_id = id
	_clear()
	var g := AIGraph.load_graph(id)
	for n in g.get("nodes", []):
		var pos: Array = n.get("pos", [0, 0])
		_make_node(str(n.id), str(n.type), n.get("params", {}), Vector2(float(pos[0]), float(pos[1])))
	for c in g.get("connections", []):
		if graph.has_node(NodePath(str(c.from))) and graph.has_node(NodePath(str(c.to))):
			graph.connect_node(StringName(str(c.from)), int(c.port), StringName(str(c.to)), 0)
	_refresh_list()
	_frame_nodes.call_deferred()
	var users: PackedStringArray = []
	if Game.data != null:
		for mid in Game.data.monsters:
			if Game.data.monsters[mid].ai_id == id:
				users.append(Game.data.monsters[mid].display_name)
	users_label.text = "이 AI 를 쓰는 몬스터: %s   (엑셀 몬스터 시트 AI 열에서 지정)" % (", ".join(users) if not users.is_empty() else "없음")
	status.text = ""


## 불러온 노드가 화면 왼쪽 위부터 보이게 스크롤
func _frame_nodes() -> void:
	await get_tree().process_frame   # GraphEdit 가 스크롤 범위를 잡은 뒤에
	await get_tree().process_frame
	var mn := Vector2(INF, INF)
	for c in graph.get_children():
		if c is GraphNode:
			mn = mn.min(c.position_offset)
	if mn.x < INF:
		graph.scroll_offset = (mn - Vector2(30, 70)) * graph.zoom


func _save() -> void:
	if current_id == "":
		return
	var nodes := []
	for c in graph.get_children():
		if c is GraphNode:
			nodes.append({"id": str(c.name), "type": c.get_meta("type"), "params": c.get_meta("params"),
				"pos": [roundf(c.position_offset.x), roundf(c.position_offset.y)]})
	var conns := []
	for c in graph.get_connection_list():
		conns.append({"from": str(c.from_node), "port": int(c.from_port), "to": str(c.to_node)})
	var err := AIGraph.save_graph(current_id, {"nodes": nodes, "connections": conns})
	status.text = "저장됨: data/ai/%s.json" % current_id if err == OK else "저장 실패 (%d)" % err


func _create() -> void:
	var id := new_id.text.strip_edges().to_lower()
	var re := RegEx.create_from_string("^[a-z0-9_]+$")
	if re.search(id) == null:
		status.text = "영문 소문자·숫자·_ 로 이름을 정하세요"
		return
	if AIGraph.list_ids().has(id):
		status.text = "이미 있는 이름입니다"
		return
	AIGraph.save_graph(id, {"nodes": [{"id": "start", "type": "start", "params": {}, "pos": [40, 200]},
		{"id": "end", "type": "act_end", "params": {}, "pos": [320, 200]}],
		"connections": [{"from": "start", "port": 0, "to": "end"}]})
	new_id.text = ""
	_load(id)
	status.text = "새 AI: data/ai/%s.json" % id


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
		_save()
