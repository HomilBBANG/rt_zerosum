@tool
extends Control
## 퀘스트 에디터 (Godot 에디터 상단 "퀘스트" 탭, addons/rtz_quest_editor) → data/quests.json (+ 신 해금 연결은 data/faith.json divine).
## 왼쪽: 퀘스트 목록 (추가 · 복제 · 삭제 · 순서). 가운데: 고른 퀘스트 — id · 이름 · 의뢰인 · 설명 · 시작 조건 · 단계 카드(종류 · 대상 · 횟수/값 · 표시 글) · 보상.
## 오른쪽: 게임 퀘스트 창 미리보기 · 이 퀘스트로 해금되는 신 / 이 퀘스트를 쓰는 다른 퀘스트 · 검사.
## 게임 규칙(BaseSim): 시작 조건을 채우면 자동 시작(직접 시작은 BaseSim.start_quest) → 단계를 앞에서부터 하나씩 → 마지막 단계를 끝내면 완료 + 보상.
##   횟수 단계(의뢰 완료 · 전투 승리 · 대화)는 그 단계가 시작된 뒤부터 셈. 완료한 퀘스트는 신 해금 조건 '미션 완료 → 퀘스트' 로 쓸 수 있음.

const START_NAMES := {"always": "처음부터 (새 게임 시작 때)", "manual": "직접 시작 (이벤트·대사 — BaseSim.start_quest)", "quest": "미션 완료 후",
	"level": "의뢰인 레벨", "faith": "의뢰인 신앙도", "affinity": "의뢰인 친밀도", "day": "n일차부터"}
const COUNT_LABEL := {"contract": "횟수", "stage": "횟수", "talk": "횟수", "affinity": "친밀도 이상", "level": "레벨 이상", "day": "일차"}
const COUNT_RANGE := {"contract": [1, 99], "stage": [1, 99], "talk": [1, 99], "affinity": [1, 100], "level": [1, 20], "day": [1, 999]}

var history: EditorHistory   # Ctrl+Z 뒤로 감기 · Ctrl+Y 앞으로 감기 (addons/rtz_common/editor_history.gd)
var quests: Array = []               # data/quests.json 퀘스트 (QuestData)
var faith: Dictionary = {}           # data/faith.json (신 해금 연결만 고침)
var faith_dirty := false
var od: OutgameData
var gd: GameData
var sel := ""                        # 고른 퀘스트 id
var dirty := false
var _rebuilding := false

var qlist: ItemList
var form: VBoxContainer
var preview: RichTextLabel
var links: VBoxContainer
var check_label: RichTextLabel
var status: Label
var step_spin: SpinBox
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
	title.text = "퀘스트"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	top.add_child(_btn("저장 (Ctrl+S)", _save))
	top.add_child(_btn("되돌리기", func(): _load()))
	var pb := _btn("기지 테스트 플레이", _play)
	pb.tooltip_text = "저장 → 새 기지에서 이 퀘스트를 시작하고(시작 단계까지 건너뛰기) 퀘스트 창. 저장 파일은 건드리지 않음"
	top.add_child(pb)
	top.add_child(_lab("시작 단계"))
	step_spin = _spin(1, 20, 1, 1, "단계")
	step_spin.tooltip_text = "테스트 플레이 때 이 단계부터 (앞 단계는 끝낸 것으로)"
	top.add_child(step_spin)
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	body.add_child(left)
	left.add_child(_head("퀘스트 목록"))
	qlist = ItemList.new()
	qlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	qlist.item_selected.connect(func(i):
		sel = str(qlist.get_item_metadata(i))
		_rebuild())
	left.add_child(qlist)
	var lb := HFlowContainer.new()
	lb.add_theme_constant_override("h_separation", 4)
	left.add_child(lb)
	lb.add_child(_btn("추가", _add_quest))
	lb.add_child(_btn("복제", _dup_quest))
	lb.add_child(_btn("삭제", _delete_quest))
	lb.add_child(_btn("↑", func(): _move_quest(-1)))
	lb.add_child(_btn("↓", func(): _move_quest(1)))
	left.add_child(_small("목록 순서 = 게임 퀘스트 창 순서 (진행 중 → 완료). 시작 안 한 퀘스트는 게임에서 안 보임."))

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
	right.custom_minimum_size.x = 380
	right.add_theme_constant_override("separation", 6)
	body2.add_child(right)
	right.add_child(_head("게임 퀘스트 창 미리보기"))
	preview = RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.custom_minimum_size.y = 230
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(preview)
	right.add_child(_head("연결"))
	links = VBoxContainer.new()
	links.add_theme_constant_override("separation", 4)
	right.add_child(links)
	right.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.custom_minimum_size.y = 150
	check_label.scroll_active = true
	right.add_child(check_label)
	reload_data(false)


## 탭을 열 때마다 대원·의뢰·연구·스테이지 목록 다시 읽기 (편집 중인 퀘스트는 유지)
func reload_data(keep_edit: bool = true) -> void:
	od = OutgameData.load_from()
	gd = GameData.load_from()
	if keep_edit and dirty:
		_rebuild()
	else:
		_load()


func _load() -> void:
	quests = QuestData.read()
	faith = FaithData.read()
	faith_dirty = false
	if _quest(sel).is_empty():
		sel = quests[0].id if not quests.is_empty() else ""
	dirty = false
	status.text = "data/quests.json 퀘스트 %d개" % quests.size()
	_rebuild()
	history.reset()


func _save() -> void:
	var err := QuestData.write(quests)
	var with_faith := faith_dirty
	var err2 := FaithData.write(faith) if with_faith else OK
	if err == OK and err2 == OK:
		dirty = false
		faith_dirty = false
		var errs: int = QuestData.check(quests, od, gd).errors.size()
		status.text = "저장됨: data/quests.json" + (" · faith.json (신 해금 연결)" if with_faith else "") + ("" if errs == 0 else "  (검사 오류 %d개 — 오른쪽 확인)" % errs)
		if Engine.is_editor_hint():
			for path in [QuestData.PATH, FaithData.PATH]:
				EditorInterface.get_resource_filesystem().update_file(path)
	else:
		status.text = "저장 실패 (%d / %d)" % [err, err2]


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 함)"
	_refresh_side()


## 저장 → 새 기지에서 이 퀘스트 시작 (시작 단계까지 건너뛰기) + 퀘스트 창
func _play() -> void:
	if sel == "":
		status.text = "퀘스트를 고르세요"
		return
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"base": true, "quest": sel, "step": int(step_spin.value) - 1}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn")


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 데이터 도우미
func _quest(id: String) -> Dictionary:
	for q in quests:
		if q.id == id:
			return q
	return {}


func _new_id(base: String) -> String:
	var id := base
	var i := 2
	while not _quest(id).is_empty():
		id = "%s_%d" % [base, i]
		i += 1
	return id


func _names() -> Dictionary:
	return QuestData.target_names(od, gd, quests)


## 시작 조건 '미션 완료' 로 고를 수 있는 미션 (의뢰 · 전투 · 연구 + 지금 편집 중인 다른 퀘스트)
func _missions(self_id: String) -> Array:
	var out := UnlockCond.missions(od, gd).filter(func(m): return not str(m[0]).begins_with("quest:"))
	for q in quests:
		if q.id != self_id:
			out.append(["quest:" + q.id, "퀘스트 · %s 완료" % q.name])
	return out


func _mission_names() -> Dictionary:
	var out := UnlockCond.mission_names(od, gd)
	for q in quests:
		out["quest:" + q.id] = str(q.name)
	return out


func _npc_name(id: String) -> String:
	return str(od.npcs.get(id, {}).get("name", id)) if od != null else id


func _start_text(q: Dictionary) -> String:
	var c: Dictionary = q.start
	match str(c.type):
		"always":
			return "처음부터"
		"manual":
			return "직접 시작"
		"level", "faith", "affinity":
			return "%s %s %d 이상" % [_npc_name(str(q.giver)), UnlockCond.TYPES[c.type], int(c.value)]
	return UnlockCond.describe(c, _mission_names())


## 이 퀘스트 완료로 정체가 드러나는 신 해금 캐릭터
func _divine_of(qid: String) -> Array:
	var out := []
	for cid in faith.get("divine", {}):
		var c: Dictionary = faith.divine[cid].condition
		if str(c.type) == "quest" and str(c.get("target", "")) == "quest:" + qid:
			out.append(cid)
	return out


func _char_name(cid: String) -> String:
	if gd != null:
		for u in gd.allies:
			if u.id == cid:
				return u.display_name
	return cid


# ================================================================ 목록 고치기
func _add_quest() -> void:
	var q := QuestData.new_quest(_new_id("q_new"))
	var t := QuestData.targets("contract", od, gd)
	if not t.is_empty():
		q.steps[0].target = str(t[0][0])
	quests.append(q)
	sel = q.id
	_mark()
	_rebuild()


func _dup_quest() -> void:
	var q := _quest(sel)
	if q.is_empty():
		return
	var c: Dictionary = q.duplicate(true)
	c.id = _new_id(q.id + "_copy")
	c.name = str(q.name) + " (복사)"
	quests.insert(quests.find(q) + 1, c)
	sel = c.id
	_mark()
	_rebuild()


func _delete_quest() -> void:
	var q := _quest(sel)
	if q.is_empty():
		return
	var i := quests.find(q)
	quests.erase(q)
	sel = quests[mini(i, quests.size() - 1)].id if not quests.is_empty() else ""
	var used := _divine_of(q.id)
	status.text = "'%s' 삭제 (저장 안 함)%s" % [q.name, " — 이 퀘스트로 해금되던 %s 는 해금 조건을 다시 고르세요 (스킬 트리 탭 → 기적)" % ", ".join(PackedStringArray(used.map(_char_name))) if not used.is_empty() else ""]
	dirty = true
	_rebuild()


func _move_quest(d: int) -> void:
	var q := _quest(sel)
	var i := quests.find(q)
	if q.is_empty() or i + d < 0 or i + d >= quests.size():
		return
	quests[i] = quests[i + d]
	quests[i + d] = q
	_mark()
	_rebuild()


## id 바꾸기 — 다른 퀘스트의 시작 조건·단계, 신 해금 조건도 같이
func _rename(q: Dictionary, v: String) -> void:
	v = v.strip_edges()
	if v == "" or v == q.id:
		return
	if not _quest(v).is_empty():
		status.text = "id '%s' 는 이미 있습니다" % v
		return
	var old: String = q.id
	for o in quests:
		if str(o.start.get("target", "")) == "quest:" + old:
			o.start.target = "quest:" + v
		for st in o.steps:
			if st.kind == "quest" and st.target == old:
				st.target = v
	for cid in _divine_of(old):
		faith.divine[cid].condition.target = "quest:" + v
		faith_dirty = true
	q.id = v
	sel = v
	_mark()
	_rebuild()


# ================================================================ 화면
func _rebuild() -> void:
	_rebuilding = true
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	_build_form()
	_rebuilding = false
	_refresh_side()


func _refresh_side() -> void:
	qlist.clear()
	for q in quests:
		var dv := _divine_of(q.id)
		qlist.add_item("◆ %s — %s · %d단계%s" % [q.name, _start_text(q), (q.steps as Array).size(), "  ✦" if not dv.is_empty() else ""])
		qlist.set_item_metadata(qlist.item_count - 1, q.id)
		qlist.set_item_tooltip(qlist.item_count - 1, "%s\n%s" % [q.id, q.desc])
		if q.start.type == "manual":
			qlist.set_item_custom_fg_color(qlist.item_count - 1, Color(0.75, 0.8, 0.95))
		if q.id == sel:
			qlist.select(qlist.item_count - 1)
	_fill_preview()
	_fill_links()
	var res := QuestData.check(quests, od, gd)
	var t := ""
	for e in res.errors:
		t += "[color=#ff7766]● %s[/color]\n" % e
	for cid in faith.get("divine", {}):
		var c: Dictionary = faith.divine[cid].condition
		var tg := str(c.get("target", ""))
		if str(c.type) == "quest" and tg.begins_with("quest:") and _quest(tg.substr(6)).is_empty():
			t += "[color=#ff7766]● 신 해금 %s: 없는 퀘스트 '%s' (저장하면 해금 안 됨)[/color]\n" % [_char_name(cid), tg.substr(6)]
	for n in res.notes:
		t += "[color=#aabbdd]· %s[/color]\n" % n
	check_label.text = t if t != "" else "[color=#77ee99]오류 없음[/color]"


func _fill_preview() -> void:
	var q := _quest(sel)
	if q.is_empty():
		preview.text = ""
		return
	var names := _names()
	var t := "[font_size=17][color=#f2bf66]◆ %s[/color][/font_size]  [color=#aab4c8]1 / %d 단계[/color]" % [q.name, (q.steps as Array).size()]
	if str(q.giver) != "":
		t += "  [color=#b3d9ff]의뢰인 %s[/color]" % _npc_name(str(q.giver))
	t += "\n"
	if str(q.desc) != "":
		t += "[color=#d9e0f2]%s[/color]\n" % q.desc
	for i in (q.steps as Array).size():
		var st: Dictionary = q.steps[i]
		var txt := str(st.desc) if str(st.desc) != "" else QuestData.step_text(st, names)
		t += ("[color=#fff2bf]  ▶ 1. %s[/color]\n" % txt) if i == 0 else "[color=#8c94a6]  · %d. %s   (게임: ??? 로 보임)[/color]\n" % [i + 1, txt]
	var got := PackedStringArray()
	if int(q.rewards.cash) > 0:
		got.append("$%d" % int(q.rewards.cash))
	if int(q.rewards.affinity) != 0 and str(q.giver) != "":
		got.append("%s 친밀도 %+d" % [_npc_name(str(q.giver)), int(q.rewards.affinity)])
	for cid in _divine_of(q.id):
		got.append("??? (%s의 비밀 — 완료하면 정체 해금)" % _char_name(cid))
	if not got.is_empty():
		t += "[color=#ffd95a]보상: %s[/color]\n" % " · ".join(got)
	t += "\n[color=#aab4c8]시작: %s[/color]" % _start_text(q)
	preview.text = t


func _fill_links() -> void:
	for c in links.get_children():
		links.remove_child(c)
		c.queue_free()
	var q := _quest(sel)
	if q.is_empty():
		return
	var dv := _divine_of(q.id)
	for cid in dv:
		var l := _small("✦ 완료하면 %s의 정체(신) 해금 — faith.json divine" % _char_name(cid))
		l.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		links.add_child(l)
	var users := PackedStringArray()
	for o in quests:
		if o.id == q.id:
			continue
		if str(o.start.get("target", "")) == "quest:" + q.id:
			users.append("%s (시작 조건)" % o.name)
		for st in o.steps:
			if st.kind == "quest" and st.target == q.id:
				users.append("%s (단계)" % o.name)
	if not users.is_empty():
		links.add_child(_small("이 퀘스트를 쓰는 퀘스트: " + ", ".join(users)))
	# 신 해금 캐릭터를 이 퀘스트에 연결 (그 캐릭터의 해금 조건 = 이 퀘스트 완료)
	var cands := []
	for cid in faith.get("divine", {}):
		if not dv.has(cid) and not bool(faith.divine[cid].get("unlocked", false)):
			cands.append([cid, "%s (지금: %s)" % [_char_name(cid), UnlockCond.describe(faith.divine[cid].condition, _mission_names())]])
	if not cands.is_empty():
		var row := HBoxContainer.new()
		links.add_child(row)
		var o := OptionButton.new()
		for c in cands:
			o.add_item(str(c[1]))
			o.set_item_metadata(o.item_count - 1, c[0])
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(o)
		row.add_child(_btn("이 퀘스트로 신 해금", func():
			var cid := str(o.get_item_metadata(maxi(0, o.selected)))
			faith.divine[cid].condition = {"type": "quest", "value": 0, "target": "quest:" + q.id}
			faith_dirty = true
			status.text = "%s 해금 조건 = 퀘스트 '%s' 완료 (저장 안 함)" % [_char_name(cid), q.name]
			dirty = true
			_refresh_side()))
	if dv.is_empty() and cands.is_empty():
		links.add_child(_small("신 해금 캐릭터 없음 (스킬 트리 탭 → 기적 에서 '정체가 신' 을 켜면 여기서 연결)"))


func _build_form() -> void:
	var q := _quest(sel)
	if q.is_empty():
		form.add_child(_head("왼쪽에서 퀘스트를 고르거나 '추가'"))
		return
	form.add_child(_head("퀘스트"))
	var grid := _grid()
	form.add_child(grid)
	var idl := LineEdit.new()
	idl.text = str(q.id)
	idl.placeholder_text = "고유 id (영문) — Enter 로 적용"
	idl.text_submitted.connect(func(v): _rename(q, v))
	_row(grid, "id", idl)
	_row(grid, "이름", _line(str(q.name), func(v): q.name = v))
	var givers := [["", "(없음)"]]
	if od != null:
		for id in od.npc_order:
			givers.append([id, "%s (%s)" % [od.npcs[id].name, id]])
	_row(grid, "의뢰인", _option(givers, q.giver, func(v):
		q.giver = str(v)
		_mark()
		_rebuild()))
	var desc := TextEdit.new()
	desc.text = str(q.desc)
	desc.custom_minimum_size = Vector2(0, 64)
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.placeholder_text = "퀘스트 창에 보이는 설명"
	desc.text_changed.connect(func():
		if not _rebuilding:
			q.desc = desc.text
			_mark())
	_row(grid, "설명", desc)

	form.add_child(HSeparator.new())
	form.add_child(_head("시작 조건"))
	var g2 := _grid()
	form.add_child(g2)
	var ct := []
	for t in UnlockCond.ORDER:
		ct.append([t, START_NAMES[t]])
	_row(g2, "언제", _option(ct, q.start.type, func(v):
		q.start = UnlockCond.norm({"type": str(v), "value": q.start.value, "target": q.start.get("target", "")})
		var ms := _missions(q.id)
		if q.start.type == "quest" and q.start.target == "" and not ms.is_empty():
			q.start.target = str(ms[0][0])
		_mark()
		_rebuild()))
	if q.start.type == "quest":
		_row(g2, "미션", _option(_missions(q.id), q.start.get("target", ""), func(v):
			q.start.target = str(v)
			_mark()))
	if UnlockCond.uses_value(q.start.type):
		var r: Array = UnlockCond.RANGE[q.start.type]
		var sp := _spin(r[0], r[1], 1, int(q.start.value), "")
		sp.value_changed.connect(func(v):
			if not _rebuilding:
				q.start.value = int(v)
				_mark())
		_row(g2, "값", sp)
	if q.start.type in ["level", "faith", "affinity"] and str(q.giver) == "":
		form.add_child(_warn("의뢰인을 골라야 합니다 (그 대원의 %s)" % UnlockCond.TYPES[q.start.type]))
	form.add_child(_small({"always": "새 게임을 시작하면 바로 진행 중.", "manual": "자동으로는 시작 안 함 — 이벤트·대사 스크립트에서 BaseSim.start_quest(\"%s\")." % q.id,
		"quest": "그 미션(의뢰·전투·연구·다른 퀘스트)을 끝내면 시작.", "level": "의뢰인의 전투 캐릭터 레벨이 값 이상이 되면 시작.", "faith": "의뢰인의 신앙도가 값 이상이 되면 시작.",
		"affinity": "의뢰인 친밀도가 값 이상이 되면 시작 (대화·요청·선물로 오름).", "day": "그 일차가 되면 시작."}.get(q.start.type, "")))

	form.add_child(HSeparator.new())
	form.add_child(_head("단계 (앞에서부터 하나씩)"))
	var steps: Array = q.steps
	for i in steps.size():
		form.add_child(_step_card(q, i))
	var add := HBoxContainer.new()
	form.add_child(add)
	new_kind = OptionButton.new()
	for k in QuestData.STEP_ORDER:
		new_kind.add_item(QuestData.STEP_KINDS[k])
		new_kind.set_item_metadata(new_kind.item_count - 1, k)
	add.add_child(new_kind)
	add.add_child(_btn("단계 추가", func():
		var k := str(new_kind.get_item_metadata(maxi(0, new_kind.selected)))
		var st := QuestData.new_step(k)
		var t := QuestData.targets(k, od, gd, quests.filter(func(x): return x.id != q.id))
		if not t.is_empty():
			st.target = str(t[0][0])
		steps.append(st)
		_mark()
		_rebuild()))
	form.add_child(_small("횟수 단계(의뢰 완료 · 전투 승리 · 대원과 대화)는 그 단계가 시작된 뒤부터 셈 — 전에 한 것은 안 셈. 나머지(연구 · 친밀도 · 레벨 · 일차 · 다른 퀘스트)는 그 단계가 되었을 때 이미 맞으면 바로 넘어감."))

	form.add_child(HSeparator.new())
	form.add_child(_head("보상 (마지막 단계를 끝내면)"))
	var g3 := _grid()
	form.add_child(g3)
	var cash := _spin(0, 9999, 5, int(q.rewards.cash), " $")
	cash.value_changed.connect(func(v):
		if not _rebuilding:
			q.rewards.cash = int(v)
			_mark())
	_row(g3, "현금 (주간 결산 때)", cash)
	var aff := _spin(-50, 50, 1, int(q.rewards.affinity), "")
	aff.value_changed.connect(func(v):
		if not _rebuilding:
			q.rewards.affinity = int(v)
			_mark())
	_row(g3, "의뢰인 친밀도", aff)
	if int(q.rewards.affinity) != 0 and str(q.giver) == "":
		form.add_child(_warn("의뢰인이 없으면 친밀도 보상은 안 줌"))


func _step_card(q: Dictionary, i: int) -> Control:
	var steps: Array = q.steps
	var st: Dictionary = steps[i]
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.2)
	sb.border_color = Color(0.95, 0.75, 0.4, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var hl := _head("%d단계" % (i + 1))
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var up := _btn("↑", func():
		steps[i] = steps[i - 1]
		steps[i - 1] = st
		_mark()
		_rebuild())
	up.disabled = i == 0
	head.add_child(up)
	var dn := _btn("↓", func():
		steps[i] = steps[i + 1]
		steps[i + 1] = st
		_mark()
		_rebuild())
	dn.disabled = i == steps.size() - 1
	head.add_child(dn)
	var del := _btn("삭제", func():
		steps.remove_at(i)
		_mark()
		_rebuild())
	del.disabled = steps.size() <= 1
	head.add_child(del)
	var g := _grid()
	v.add_child(g)
	var kinds := []
	for k in QuestData.STEP_ORDER:
		kinds.append([k, QuestData.STEP_KINDS[k]])
	_row(g, "종류", _option(kinds, st.kind, func(nv):
		var fresh := QuestData.new_step(str(nv))
		var t := QuestData.targets(str(nv), od, gd, quests.filter(func(x): return x.id != q.id))
		fresh.target = str(t[0][0]) if not t.is_empty() else ""
		fresh.desc = st.desc
		steps[i] = fresh
		_mark()
		_rebuild()))
	if st.kind != "day":
		var opts := QuestData.targets(st.kind, od, gd, quests.filter(func(x): return x.id != q.id))
		if st.kind in ["talk", "affinity"]:
			opts = opts.map(func(x): return [x[0], "%s (%s)" % [x[1], x[0]]])
		_row(g, {"contract": "의뢰", "stage": "스테이지", "research": "연구", "talk": "대원", "affinity": "대원", "level": "캐릭터", "quest": "퀘스트"}.get(st.kind, "대상"),
			_option(opts, st.target, func(nv):
				st.target = str(nv)
				_mark()
				_rebuild()))
	if COUNT_LABEL.has(st.kind):
		var r: Array = COUNT_RANGE[st.kind]
		var sp := _spin(r[0], r[1], 1, int(st.count), "")
		sp.value_changed.connect(func(nv):
			if not _rebuilding:
				st.count = int(nv)
				_mark())
		_row(g, COUNT_LABEL[st.kind], sp)
	var auto := QuestData.step_text(st, _names())
	_row(g, "표시 글", _line(str(st.desc), func(nv): st.desc = nv, auto))
	v.add_child(_small("비워 두면 자동: " + auto))
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
	e.custom_minimum_size.x = 220
	e.text_changed.connect(func(v):
		if not _rebuilding:
			cb.call(v)
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


func _warn(t: String) -> Label:
	var l := _small("⚠ " + t)
	l.add_theme_color_override("font_color", Color(1, 0.6, 0.45))
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
	return var_to_str([quests, faith])


func _hist_apply(s: String) -> void:
	var v: Array = str_to_var(s)
	quests = v[0]
	faith = v[1]
	faith_dirty = true
	dirty = true
	if _quest(sel).is_empty():
		sel = quests[0].id if not quests.is_empty() else ""
	_rebuild()
