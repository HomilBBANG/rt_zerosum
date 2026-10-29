@tool
extends Control
## 컷씬 에디터 (Godot 에디터 상단 "컷씬" 탭, addons/rtz_cutscene_editor) → data/cutscenes.json. 그림은 assets/cg/ 의 PNG.
## 왼쪽: 컷씬 목록 (분류 거르기 · 추가 · 복제 · 삭제 · 순서). 가운데: 고른 컷씬 — id · 이름 · 분류 · 계기(언제 나오나) · 한 번만 · 다음 컷씬(이어지기) + 컷 카드
##   (대사 · 나레이션 · CG · 배경 · 선택지 · 행동 — 카드 클릭 = 그 컷 미리보기, ↑↓ · 복제 · 삭제, 아래 버튼 = 고른 컷 다음에 추가).
## 오른쪽: 게임과 같은 재생 화면(CutscenePlayer) 미리보기 — '▶ 이 컷부터 재생' 뒤 미리보기 클릭 = 다음 · 흐름(어디서 오고 어디로 가는지, 눌러서 이동) · 검사.
## 이어지기: 다음 컷씬 / 선택지마다 이어질 컷씬 — '새 컷씬 만들어 잇기' 로 바로 만들 수 있음.

var history: EditorHistory   # Ctrl+Z 뒤로 감기 · Ctrl+Y 앞으로 감기 (addons/rtz_common/editor_history.gd)
var cuts: Array = []                 # data/cutscenes.json 컷씬 (CutsceneData)
var od: OutgameData
var gd: GameData
var quests: Array = []
var images: Array = []
var sel := ""                        # 고른 컷씬 id
var ssel := 0                        # 고른 컷 번호
var kind_filter := ""
var _previewing := false             # 미리보기 재생 중 (그동안은 고쳐도 미리보기를 다시 그리지 않음)
var dirty := false
var _rebuilding := false

var qlist: ItemList
var form: VBoxContainer
var cards: Array = []
var player: CutscenePlayer             # 미리보기 — 탭을 처음 열 때 만듦 (에디터 시작·임포트 중에는 아무것도 안 읽음)
var holder: Control
var flow: VBoxContainer
var check_label: RichTextLabel
var status: Label
var filter_btns: Dictionary = {}
var new_kind: OptionButton


func _ready() -> void:
	history = EditorHistory.new(_hist_snap, _hist_apply)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "컷씬"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	top.add_child(_btn("저장 (Ctrl+S)", _save))
	top.add_child(_btn("되돌리기", func(): _load()))
	var pv := _btn("▶ 이 컷부터 미리보기 재생", _preview_play)
	pv.tooltip_text = "오른쪽 미리보기에서 재생 — 미리보기를 클릭하면 다음 컷 (이어지는 컷씬·선택지도 그대로)"
	top.add_child(pv)
	var pb := _btn("기지 테스트 플레이 (이 컷부터)", _play)
	pb.tooltip_text = "저장 → 새 기지에서 이 컷씬을 고른 컷부터 재생 (행동 컷도 적용, 저장 파일은 건드리지 않음)"
	top.add_child(pb)
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	body.add_child(left)
	left.add_child(_head("컷씬 목록"))
	var fb := HFlowContainer.new()
	fb.add_theme_constant_override("h_separation", 2)
	left.add_child(fb)
	for k in [""] + CutsceneData.KIND_ORDER:
		var b := Button.new()
		b.text = "전체" if k == "" else CutsceneData.KINDS[k]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var kk: String = k
		b.pressed.connect(func():
			kind_filter = kk
			_refresh_side())
		fb.add_child(b)
		filter_btns[k] = b
	qlist = ItemList.new()
	qlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	qlist.item_selected.connect(func(i):
		sel = str(qlist.get_item_metadata(i))
		ssel = 0
		_rebuild())
	left.add_child(qlist)
	var lb := HFlowContainer.new()
	lb.add_theme_constant_override("h_separation", 4)
	left.add_child(lb)
	new_kind = OptionButton.new()
	for k in CutsceneData.KIND_ORDER:
		new_kind.add_item(CutsceneData.KINDS[k])
		new_kind.set_item_metadata(new_kind.item_count - 1, k)
	new_kind.select(CutsceneData.KIND_ORDER.find("event"))
	lb.add_child(new_kind)
	lb.add_child(_btn("추가", func(): _add_cut(str(new_kind.get_item_metadata(maxi(0, new_kind.selected))))))
	lb.add_child(_btn("복제", _dup_cut))
	lb.add_child(_btn("삭제", _delete_cut))
	lb.add_child(_btn("↑", func(): _move_cut(-1)))
	lb.add_child(_btn("↓", func(): _move_cut(1)))
	left.add_child(_small("▶ = 계기가 있음 (게임에서 저절로 나옴) · ↪ = 다른 컷씬에서 이어짐 · 같은 계기면 목록 순서대로."))

	var body2 := HSplitContainer.new()
	body2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(body2)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.x = 520
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body2.add_child(sc)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	sc.add_child(form)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	right.add_theme_constant_override("separation", 6)
	body2.add_child(right)
	right.add_child(_head("미리보기 (게임 재생 화면)"))
	holder = Control.new()
	holder.custom_minimum_size = Vector2(400, 225)
	holder.clip_contents = true
	right.add_child(holder)
	right.add_child(_small("배경 그림이 없는 컷은 게임에서 기지 화면이 어둡게 비침 (여기서는 검게)."))
	right.add_child(_head("흐름"))
	flow = VBoxContainer.new()
	flow.add_theme_constant_override("separation", 3)
	right.add_child(flow)
	right.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.custom_minimum_size.y = 130
	check_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	check_label.scroll_active = true
	right.add_child(check_label)
	if not Engine.is_editor_hint():   # 에디터 밖(스크린샷 스크립트)에서는 바로. 에디터에서는 탭을 열 때 (plugin._make_visible → reload_data)
		reload_data(false)


func _ensure_player() -> void:
	if player != null:
		return
	player = CutscenePlayer.new()
	player.keys = false
	player.dim_alpha = 1.0
	holder.add_child(player)
	player.cutscene_started.connect(_on_preview_started)
	player.finished.connect(_on_preview_finished)


func _on_preview_started(id: String) -> void:
	if player.playing and id != sel:
		status.text = "미리보기: '%s' 로 이어짐" % _cut(id).get("name", id)


func _on_preview_finished(_id: String) -> void:
	_previewing = false
	status.text = "미리보기 끝"
	_preview_static.call_deferred()


## 탭을 열 때마다 대원·퀘스트·그림 목록 다시 읽기 (편집 중인 컷씬은 유지)
func reload_data(keep_edit: bool = true) -> void:
	if DisplayServer.get_name() == "headless":   # play.bat 의 --headless --import 중에는 아무것도 안 함
		return
	_ensure_player()
	od = OutgameData.load_from()
	gd = GameData.load_from()
	quests = QuestData.read()
	images = CutsceneData.images()
	player.clear_textures()
	player.npcs = od.npcs if od != null else {}
	if keep_edit and dirty:
		_rebuild()
	else:
		_load()


func _load() -> void:
	cuts = CutsceneData.read()
	if _cut(sel).is_empty():
		sel = cuts[0].id if not cuts.is_empty() else ""
		ssel = 0
	dirty = false
	status.text = "data/cutscenes.json 컷씬 %d개 · assets/cg 그림 %d개" % [cuts.size(), images.size()]
	_rebuild()
	history.reset()


func _save() -> void:
	var err := CutsceneData.write(cuts)
	if err == OK:
		dirty = false
		var errs: int = _check().errors.size()
		status.text = "저장됨: data/cutscenes.json" + ("" if errs == 0 else "  (검사 오류 %d개 — 오른쪽 확인)" % errs)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(CutsceneData.PATH)
	else:
		status.text = "저장 실패 (%d)" % err


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 함)"
	_refresh_side()


func _play() -> void:
	if sel == "":
		status.text = "컷씬을 고르세요"
		return
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"base": true, "cutscene": sel, "step": ssel}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn")


func _preview_play() -> void:
	if sel == "" or player == null:
		return
	player.defs = CutsceneData.by_id(cuts)
	_previewing = true
	player.play(sel, ssel)
	status.text = "미리보기 재생 중 — 미리보기를 클릭하면 다음 컷"


func _preview_static() -> void:
	if player == null:
		return
	player.defs = CutsceneData.by_id(cuts)
	player.show_at(sel, ssel)


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 데이터 도우미
func _cut(id: String) -> Dictionary:
	for c in cuts:
		if c.id == id:
			return c
	return {}


func _new_id(base: String) -> String:
	var id := base
	var i := 2
	while not _cut(id).is_empty():
		id = "%s_%d" % [base, i]
		i += 1
	return id


func _npc_names() -> Dictionary:
	var out := {}
	if od != null:
		for id in od.npc_order:
			out[id] = str(od.npcs[id].name)
	return out


func _names() -> Dictionary:
	var out := {}
	for q in quests:
		out["quest:" + q.id] = str(q.name)
	if od != null:
		for id in od.npc_order:
			out["npc:" + id] = str(od.npcs[id].name)
		for c in od.conversations:
			out["conv:" + c.id] = "%s · %s (%s)" % [od.npc_name(c.a), od.npc_name(c.b), c.id]
	if gd != null:
		for id in gd.stage_order:
			out["stage:" + id] = str(gd.stages[id].get("name", id))
		for u in gd.allies:
			out["char:" + u.id] = u.display_name
	return out


func _divine_ids() -> Array:
	return gd.divine.keys() if gd != null else []


func _check() -> Dictionary:
	var convs: Array = od.conversations.map(func(c): return c.id) if od != null else []
	return CutsceneData.check(cuts, od.npcs if od != null else {}, quests, convs, _divine_ids())


## 계기 대상 고르기 [[id, 표시]]
func _trigger_targets(t: String) -> Array:
	var out := []
	match t:
		"quest_start", "quest_step", "quest_done":
			for q in quests:
				out.append([q.id, "%s (%s)" % [q.name, q.id]])
		"talk":
			if od != null:
				for id in od.npc_order:
					out.append([id, "%s (%s)" % [od.npcs[id].name, id]])
		"overhear":
			if od != null:
				for c in od.conversations:
					out.append([c.id, "%s · %s (%s)" % [od.npc_name(c.a), od.npc_name(c.b), c.id]])
		"divine":
			for cid in _divine_ids():
				out.append([cid, "%s (%s)" % [_names().get("char:" + cid, cid), cid]])
		"battle_win":
			out.append(["", "아무 전투"])
			if gd != null:
				for id in gd.stage_order:
					out.append([id, str(gd.stages[id].get("name", id))])
	return out


func _action_targets(d: String) -> Array:
	var out := []
	match d:
		"start_quest":
			for q in quests:
				out.append([q.id, "%s (%s)" % [q.name, q.id]])
		"unlock_divine":
			for cid in _divine_ids():
				out.append([cid, _names().get("char:" + cid, cid)])
		"affinity":
			if od != null:
				for id in od.npc_order:
					out.append([id, str(od.npcs[id].name)])
		"faith":   # 전투 캐릭터인 대원만 (무신앙이면 게임에서 안 쌓임)
			if od != null:
				for id in od.npc_order:
					var ch := str(od.npcs[id].get("character_id", ""))
					if ch == "":
						continue
					var g := str(gd.char_faith.get(ch, {}).get("god", "")) if gd != null else ""
					out.append([id, "%s%s" % [od.npcs[id].name, " (무신앙 — 안 쌓임)" if g == "" else ""]])
	return out


func _cut_options(exclude: String, none_label: String) -> Array:
	var out := [["", none_label]]
	for c in cuts:
		if c.id != exclude:
			out.append([c.id, "%s (%s)" % [c.name, c.id]])
	return out


# ================================================================ 목록 고치기
func _add_cut(kind: String) -> void:
	var c := CutsceneData.new_cutscene(_new_id("cs_new"), kind)
	cuts.append(c)
	sel = c.id
	ssel = 0
	_mark()
	_rebuild()


## 새 컷씬을 만들어 돌려줌 (이어지기 · 선택지에서 바로 만들 때 — 계기 없음, 같은 분류)
func _make_linked(from: Dictionary) -> String:
	var c := CutsceneData.new_cutscene(_new_id(str(from.id) + "_next"), str(from.kind))
	c.name = str(from.name) + " (이어짐)"
	c.trigger = {"type": "none", "target": "", "value": 1}
	cuts.insert(cuts.find(from) + 1, c)
	return c.id


func _dup_cut() -> void:
	var c := _cut(sel)
	if c.is_empty():
		return
	var d: Dictionary = c.duplicate(true)
	d.id = _new_id(c.id + "_copy")
	d.name = str(c.name) + " (복사)"
	cuts.insert(cuts.find(c) + 1, d)
	sel = d.id
	_mark()
	_rebuild()


func _delete_cut() -> void:
	var c := _cut(sel)
	if c.is_empty():
		return
	var inc := CutsceneData.incoming(cuts, c.id)
	var i := cuts.find(c)
	cuts.erase(c)
	sel = cuts[mini(i, cuts.size() - 1)].id if not cuts.is_empty() else ""
	ssel = 0
	dirty = true
	_rebuild()
	status.text = "'%s' 삭제 (저장 안 함)%s" % [c.name, " — 이 컷씬으로 이어지던 곳 %d개를 고치세요 (검사)" % inc.size() if not inc.is_empty() else ""]


func _move_cut(d: int) -> void:
	var c := _cut(sel)
	var i := cuts.find(c)
	if c.is_empty() or i + d < 0 or i + d >= cuts.size():
		return
	cuts[i] = cuts[i + d]
	cuts[i + d] = c
	_mark()


## id 바꾸기 — 이어지는 곳(다음 · 선택지)도 같이
func _rename(c: Dictionary, v: String) -> void:
	v = v.strip_edges()
	if v == "" or v == c.id:
		return
	if not _cut(v).is_empty():
		status.text = "id '%s' 는 이미 있습니다" % v
		return
	var old: String = c.id
	for o in cuts:
		if o.next == old:
			o.next = v
		for st in o.steps:
			if st.type == "choice":
				for op in st.options:
					if op.next == old:
						op.next = v
	c.id = v
	sel = v
	_mark()
	_rebuild()
	status.text = "id 바꿈 → 이어지는 곳도 같이 (퀘스트 단계 '컷씬 보기' · 미션 'cutscene:%s' 는 퀘스트 탭에서 확인)" % old


# ================================================================ 화면
func _rebuild() -> void:
	_rebuilding = true
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	cards.clear()
	_build_form()
	_rebuilding = false
	_refresh_side()


func _refresh_side() -> void:
	for k in filter_btns:
		filter_btns[k].button_pressed = k == kind_filter
	qlist.clear()
	var names := _names()
	for c in cuts:
		if kind_filter != "" and c.kind != kind_filter:
			continue
		var linked := not CutsceneData.incoming(cuts, c.id).is_empty()
		var mark := "▶" if c.trigger.type != "none" else ("↪" if linked else "·")
		qlist.add_item("%s [%s] %s — %s" % [mark, CutsceneData.KINDS.get(c.kind, c.kind), c.name, CutsceneData.trigger_text(c, names) if c.trigger.type != "none" else ("이어짐" if linked else "직접 재생")])
		qlist.set_item_metadata(qlist.item_count - 1, c.id)
		qlist.set_item_tooltip(qlist.item_count - 1, "%s · 컷 %d개%s" % [c.id, (c.steps as Array).size(), " → " + c.next if c.next != "" else ""])
		if c.trigger.type == "none":
			qlist.set_item_custom_fg_color(qlist.item_count - 1, Color(0.75, 0.82, 0.95))
		if c.id == sel:
			qlist.select(qlist.item_count - 1)
	_highlight_cards()
	_fill_flow()
	if not _previewing:
		_preview_static()
	var res := _check()
	var t := ""
	for e in res.errors:
		t += "[color=#ff7766]● %s[/color]\n" % e
	for n in res.notes:
		t += "[color=#aabbdd]· %s[/color]\n" % n
	check_label.text = t if t != "" else "[color=#77ee99]오류 없음[/color]"


func _select_step(i: int) -> void:
	ssel = i
	_previewing = false
	_highlight_cards()
	_preview_static()


func _highlight_cards() -> void:
	for i in cards.size():
		var sb: StyleBoxFlat = cards[i].get_theme_stylebox("panel")
		sb.border_color = Color(1, 0.85, 0.4) if i == ssel else Color(0.4, 0.45, 0.55, 0.6)
		sb.set_border_width_all(2 if i == ssel else 1)


func _fill_flow() -> void:
	for c in flow.get_children():
		flow.remove_child(c)
		c.queue_free()
	var cur := _cut(sel)
	if cur.is_empty():
		return
	var names := _names()
	if cur.trigger.type != "none":
		flow.add_child(_small("▶ 계기: %s%s" % [CutsceneData.trigger_text(cur, names), " (한 번만)" if cur.once else " (매번)"]))
	for inc in CutsceneData.incoming(cuts, cur.id):
		var o := _cut(str(inc[0]))
		flow.add_child(_jump("← %s 의 %s" % [o.name, inc[1]], str(inc[0])))
	if cur.trigger.type == "none" and CutsceneData.incoming(cuts, cur.id).is_empty():
		flow.add_child(_small("계기·이어지는 곳 없음 — 행동·스크립트에서 BaseSim.queue_cutscene(\"%s\")" % cur.id))
	for st in cur.steps:
		if st.type == "choice":
			for op in st.options:
				if str(op.next) != "":
					flow.add_child(_jump("→ 선택지 '%s' → %s" % [op.text, _cut(op.next).get("name", op.next)], str(op.next)))
	if str(cur.next) != "":
		flow.add_child(_jump("→ 끝나면 이어서: %s" % _cut(cur.next).get("name", cur.next), str(cur.next)))
	else:
		flow.add_child(_small("■ 끝나면 기지로"))
	for q in quests:   # 이 컷씬을 쓰는 퀘스트 (단계 '컷씬 보기' · 시작 조건 '미션 완료')
		for stq in q.steps:
			if stq.kind == "cutscene" and stq.target == cur.id:
				flow.add_child(_small("◆ 퀘스트 '%s' 단계: 이 컷씬 보기" % q.name))
		if str(q.start.get("target", "")) == "cutscene:" + cur.id:
			flow.add_child(_small("◆ 퀘스트 '%s' 시작 조건: 이 컷씬을 봄" % q.name))


func _jump(t: String, id: String) -> Button:
	var b := _btn(t, func():
		sel = id
		ssel = 0
		_rebuild())
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	return b


func _build_form() -> void:
	var c := _cut(sel)
	if c.is_empty():
		form.add_child(_head("왼쪽에서 컷씬을 고르거나 '추가'"))
		return
	form.add_child(_head("컷씬"))
	var grid := _grid()
	form.add_child(grid)
	var idl := LineEdit.new()
	idl.text = str(c.id)
	idl.placeholder_text = "고유 id (영문) — Enter 로 적용"
	idl.text_submitted.connect(func(v): _rename(c, v))
	_row(grid, "id", idl)
	_row(grid, "이름", _line(str(c.name), func(v): c.name = v))
	var kinds := []
	for k in CutsceneData.KIND_ORDER:
		kinds.append([k, CutsceneData.KINDS[k]])
	_row(grid, "분류", _option(kinds, c.kind, func(v):
		c.kind = str(v)
		_mark()))
	var tts := []
	for t in CutsceneData.TRIGGER_ORDER:
		tts.append([t, CutsceneData.TRIGGERS[t]])
	_row(grid, "계기 (언제)", _option(tts, c.trigger.type, func(v):
		c.trigger.type = str(v)
		var ts := _trigger_targets(str(v))
		c.trigger.target = str(ts[0][0]) if not ts.is_empty() else ""
		c.trigger.value = 1 if str(v) != "day" else 2
		_mark()
		_rebuild()))
	var tt: String = c.trigger.type
	if not _trigger_targets(tt).is_empty():
		_row(grid, "대상", _option(_trigger_targets(tt), c.trigger.target, func(v):
			c.trigger.target = str(v)
			_mark()))
	if tt in ["quest_step", "day"]:
		var sp := _spin(1, 999 if tt == "day" else 20, 1, int(c.trigger.value), "일차" if tt == "day" else "단계")
		sp.value_changed.connect(func(v):
			if not _rebuilding:
				c.trigger.value = int(v)
				_mark())
		_row(grid, "일차" if tt == "day" else "단계", sp)
	var once := CheckBox.new()
	once.text = "한 번만 (본 뒤로는 안 나옴)"
	once.button_pressed = bool(c.once)
	once.toggled.connect(func(v):
		if not _rebuilding:
			c.once = v
			_mark())
	_row(grid, "", once)
	var nx := HBoxContainer.new()
	nx.add_child(_option(_cut_options(c.id, "(없음 — 끝나면 기지로)"), c.next, func(v):
		c.next = str(v)
		_mark()))
	nx.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nx.add_child(_btn("새 컷씬 만들어 잇기", func():
		c.next = _make_linked(c)
		_mark()
		_rebuild()))
	_row(grid, "다음 컷씬", nx)
	form.add_child(_small({"none": "계기 없음 — 다른 컷씬의 '다음'·선택지로 이어지거나, 행동·스크립트(BaseSim.queue_cutscene)로만 나옴.",
		"new_game": "새 게임을 시작하면 바로 (오프닝).", "talk": "지휘관이 그 대원을 클릭해 말을 걸면 평소 대사 대신 이 컷씬.",
		"overhear": "대원끼리 대화하는 말풍선을 눌러 엿들으면 엿듣기 창 대신 이 컷씬.", "day": "그 일차 아침(0시)이 되면.",
		"quest_start": "그 퀘스트가 시작되면.", "quest_step": "그 퀘스트의 그 단계가 시작되면 (1단계 = 퀘스트 시작).", "quest_done": "그 퀘스트를 끝내면 (보상 뒤).",
		"divine": "그 캐릭터의 정체(신)가 드러나면.", "battle_win": "전투에서 이기고 기지로 돌아오면."}.get(tt, "")))

	form.add_child(HSeparator.new())
	form.add_child(_head("컷 (%d개) — 카드 클릭 = 미리보기" % (c.steps as Array).size()))
	var steps: Array = c.steps
	for i in steps.size():
		var card := _step_card(c, i)
		form.add_child(card)
		cards.append(card)
	var add := HFlowContainer.new()
	add.add_theme_constant_override("h_separation", 4)
	form.add_child(add)
	add.add_child(_lab("추가 (고른 컷 다음):"))
	for t in CutsceneData.STEP_ORDER:
		var tt2: String = t
		add.add_child(_btn("+ " + CutsceneData.STEP_TYPES[t], func(): _add_step(c, tt2)))
	form.add_child(_small("대사 = 말하는 대원이 왼쪽/오른쪽에 섬 (다른 쪽은 어둡게) · CG = 화면 전체 그림, 'CG 끄기' 나 배경 컷까지 대사가 그 위에 · 배경 = 뒤 그림 (없으면 기지 화면 어둡게) · 선택지 = 고른 것의 컷씬으로 이어짐(끝 = 이 컷씬 다음 컷) · 행동 = 퀘스트 시작 · 신 정체 해금 · 친밀도 · 현금. 그림은 assets/cg/ 에 PNG(1280x720)를 넣고 탭을 다시 열면 목록에 나옴."))


func _add_step(c: Dictionary, t: String) -> void:
	var st := CutsceneData.new_step(t)
	var steps: Array = c.steps
	if t == "say" and od != null and not od.npc_order.is_empty():
		var last := ""
		for k in range(mini(ssel, steps.size() - 1), -1, -1):   # 앞 대사의 반대편 대원으로
			if steps[k].type == "say":
				last = steps[k].speaker
				st.side = "right" if steps[k].side == "left" else "left"
				break
		st.speaker = last if last != "" else od.npc_order[0]
	if t in ["cg", "bg"] and not images.is_empty():   # cg_… / bg_… 이름 그림 먼저
		st.image = str(images[0])
		for img in images:
			if str(img).get_file().begins_with(t + "_"):
				st.image = str(img)
				break
	var at := mini(ssel + 1, steps.size())
	steps.insert(at, st)
	ssel = at
	_mark()
	_rebuild()


func _step_card(c: Dictionary, i: int) -> Control:
	var steps: Array = c.steps
	var st: Dictionary = steps[i]
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = {"say": Color(0.13, 0.15, 0.2), "narration": Color(0.12, 0.13, 0.16), "cg": Color(0.16, 0.12, 0.18), "bg": Color(0.1, 0.14, 0.16),
		"choice": Color(0.18, 0.15, 0.1), "action": Color(0.1, 0.16, 0.12)}.get(st.type, Color(0.13, 0.15, 0.2))
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	pc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select_step(i))
	var v := VBoxContainer.new()
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var hl := _head("%d. %s" % [i + 1, CutsceneData.STEP_TYPES[st.type]])
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(hl)
	var up := _btn("↑", func():
		steps[i] = steps[i - 1]
		steps[i - 1] = st
		ssel = i - 1
		_mark()
		_rebuild())
	up.disabled = i == 0
	head.add_child(up)
	var dn := _btn("↓", func():
		steps[i] = steps[i + 1]
		steps[i + 1] = st
		ssel = i + 1
		_mark()
		_rebuild())
	dn.disabled = i == steps.size() - 1
	head.add_child(dn)
	head.add_child(_btn("복제", func():
		steps.insert(i + 1, st.duplicate(true))
		ssel = i + 1
		_mark()
		_rebuild()))
	var del := _btn("삭제", func():
		steps.remove_at(i)
		ssel = clampi(ssel, 0, steps.size() - 1)
		_mark()
		_rebuild())
	del.disabled = steps.size() <= 1
	head.add_child(del)
	var g := _grid()
	v.add_child(g)
	var touch := func(): _select_step(i)
	match str(st.type):
		"say":
			var who := [["", "(대원 아님 — 표시 이름만)"]]
			if od != null:
				for id in od.npc_order:
					who.append([id, "%s (%s)" % [od.npcs[id].name, id]])
			_row(g, "말하는 대원", _option(who, st.speaker, func(nv):
				st.speaker = str(nv)
				touch.call()
				_mark()))
			var set_name := func(nv):
				st.name = nv
				touch.call()
			_row(g, "표시 이름", _line(str(st.name), set_name, "비우면 대원 이름 (예: ???, 테라)"))
			_row(g, "서는 곳", _option([["left", "왼쪽"], ["right", "오른쪽"]], st.side, func(nv):
				st.side = str(nv)
				touch.call()
				_mark()))
			_row(g, "대사", _text(str(st.text), func(nv):
				st.text = nv
				touch.call()))
		"narration":
			_row(g, "글", _text(str(st.text), func(nv):
				st.text = nv
				touch.call()))
		"cg", "bg":
			var opts := [["", "(CG 끄기)" if st.type == "cg" else "(없음 — 기지 화면 어둡게)"]]
			for p in images:
				opts.append([p, p.get_file()])
			if str(st.image) != "" and not images.has(st.image):
				opts.append([st.image, str(st.image).get_file() + " (없는 파일)"])
			var row := HBoxContainer.new()
			var thumb := TextureRect.new()
			thumb.custom_minimum_size = Vector2(128, 72)
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			thumb.texture = CutsceneData.texture(str(st.image))
			thumb.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(_option(opts, st.image, func(nv):
				st.image = str(nv)
				thumb.texture = CutsceneData.texture(str(nv))
				touch.call()
				_mark()))
			row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(thumb)
			_row(g, "그림", row)
			if st.type == "cg":
				var set_cg_text := func(nv):
					st.text = nv
					touch.call()
				_row(g, "글 (선택)", _line(str(st.text), set_cg_text, "CG 아래 상자에 나레이션으로"))
		"choice":
			_row(g, "질문", _line(str(st.text), func(nv):
				st.text = nv
				touch.call()))
			var opts2: Array = st.options
			for k in opts2.size():
				var op: Dictionary = opts2[k]
				var orow := HBoxContainer.new()
				var ol := _line(str(op.text), func(nv):
					op.text = nv
					touch.call())
				ol.custom_minimum_size.x = 150
				orow.add_child(ol)
				var on := _option(_cut_options("", "(끝 — 이 컷씬 다음 컷)"), op.next, func(nv):
					op.next = str(nv)
					touch.call()
					_mark())
				on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				orow.add_child(on)
				orow.add_child(_btn("새 컷씬", func():
					op.next = _make_linked(c)
					_mark()
					_rebuild()))
				var od2 := _btn("✕", func():
					opts2.remove_at(k)
					_mark()
					_rebuild())
				od2.disabled = opts2.size() <= 1
				orow.add_child(od2)
				_row(g, "선택지 %d" % (k + 1), orow)
			var addo := _btn("선택지 추가", func():
				opts2.append({"text": "선택지 %d" % (opts2.size() + 1), "next": ""})
				_mark()
				_rebuild())
			_row(g, "", addo)
		"action":
			var acts := []
			for a in CutsceneData.ACTION_ORDER:
				acts.append([a, CutsceneData.ACTIONS[a]])
			_row(g, "행동", _option(acts, st.do, func(nv):
				st.do = str(nv)
				var ts := _action_targets(str(nv))
				st.target = str(ts[0][0]) if not ts.is_empty() else ""
				st.value = 5 if str(nv) in ["affinity", "faith"] else (50 if str(nv) == "cash" else 0)
				_mark()
				_rebuild()))
			if st.do == "cash":
				var set_label := func(nv): st.target = nv
				_row(g, "장부 이름", _line(str(st.target), set_label, "주간 결산에 보일 이름"))
			else:
				_row(g, "대상", _option(_action_targets(st.do), st.target, func(nv):
					st.target = str(nv)
					_mark()))
			if st.do in ["affinity", "faith", "cash"]:
				var lo := -9999 if st.do == "cash" else -50
				var hi := 9999 if st.do == "cash" else (100 if st.do == "faith" else 50)
				var sp := _spin(lo, hi, 1, int(st.value), " $" if st.do == "cash" else "")
				sp.value_changed.connect(func(nv):
					if not _rebuilding:
						st.value = int(nv)
						_mark())
				_row(g, "값", sp)
	return pc


# ================================================================ 위젯
func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 6)
	return g


func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	grid.add_child(_lab(label))
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


## items = [[값, 표시], …]
func _option(items: Array, cur: Variant, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.clip_text = true   # 긴 이름이 가운데 칸을 넓히지 않게
	o.custom_minimum_size.x = 120
	for it in items:
		o.add_item(str(it[1]))
		o.set_item_metadata(o.item_count - 1, it[0])
		if str(it[0]) == str(cur):
			o.select(o.item_count - 1)
	o.item_selected.connect(func(i):
		if not _rebuilding:
			cb.call(o.get_item_metadata(i)))
	return o


func _line(t: String, cb: Callable, hint: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = t
	e.placeholder_text = hint
	e.custom_minimum_size.x = 200
	e.text_changed.connect(func(v):
		if not _rebuilding:
			cb.call(v)
			_mark())
	return e


func _text(t: String, cb: Callable) -> TextEdit:
	var e := TextEdit.new()
	e.text = t
	e.custom_minimum_size = Vector2(200, 54)
	e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.text_changed.connect(func():
		if not _rebuilding:
			cb.call(e.text)
			_mark())
	return e


func _spin(lo: float, hi: float, step: float, v: float, suffix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.suffix = suffix
	return s


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _lab(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
	return l


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	return l


# ================================================================ 뒤로 감기 (Ctrl+Z) · 앞으로 감기 (Ctrl+Y)
func _process(delta: float) -> void:
	if history != null and is_visible_in_tree():
		history.tick(delta)


func _input(event: InputEvent) -> void:
	EditorHistory.handle_input(self, event, history, status)


## 편집 중인 데이터 전체 (var_to_str — 정수·실수 그대로)
func _hist_snap() -> String:
	return var_to_str(cuts)


func _hist_apply(s: String) -> void:
	cuts = str_to_var(s)
	dirty = true
	_previewing = false
	if _cut(sel).is_empty():
		sel = cuts[0].id if not cuts.is_empty() else ""
	ssel = clampi(ssel, 0, maxi(0, (_cut(sel).get("steps", []) as Array).size() - 1))
	_rebuild()
