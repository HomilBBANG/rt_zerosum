@tool
extends Control
## 출정 대사 에디터 (Godot 에디터 상단 "출정 대사" 탭, addons/rtz_sortie_editor).
## 출정 대기 화면에서 진형에 배치된 대원이 초상화 위 말풍선으로 하는 짧은 대사 (data/outgame/sortie_lines.json).
## 왼쪽: 대사 목록 (대원별 거르기) · 오른쪽 위: 고른 대사의 문장과 조건 · 오른쪽 아래: 상황을 정해 어떤 대사가 나오는지 시험 + 검사.
## 고르는 규칙은 SortieLines — 게임(출정 대기 화면)과 같은 코드.

const BUBBLE_W := 230.0

var lines: Array = []
var sel := -1
var dirty := false
var _rebuilding := false
var char_ids: Array[String] = []
var names: Dictionary = {}          # 캐릭터 id → 이름
var status_ids: Array[String] = []
var status_names: Dictionary = {}
var filter := "*"                   # "*" 전체, "" 공통, 캐릭터 id
var test := {"char": "", "affinity": 50.0, "fatigue": 20.0, "hp_pct": 100.0, "status": "", "row": 0, "with": []}

var line_list: ItemList
var filter_opt: OptionButton
var status: Label
var form: VBoxContainer
var bubble_box: Control
var test_box: VBoxContainer
var result_label: RichTextLabel
var test_bubble_box: Control
var check_label: RichTextLabel
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "출정 대사"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	top.add_child(_btn("저장 (Ctrl+S)", _save))
	top.add_child(_btn("되돌리기", func(): _load()))
	top.add_child(_btn("출정 대기 테스트 플레이 (대원 상태 섞기)", _play))
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# 왼쪽: 대사 목록
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 380
	body.add_child(left)
	var fr := HBoxContainer.new()
	left.add_child(fr)
	fr.add_child(_head("대사 목록"))
	filter_opt = OptionButton.new()
	filter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_opt.item_selected.connect(func(i):
		filter = str(filter_opt.get_item_metadata(i))
		_refresh_list())
	fr.add_child(filter_opt)
	line_list = ItemList.new()
	line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line_list.item_selected.connect(func(i): _select(int(line_list.get_item_metadata(i))))
	left.add_child(line_list)
	var lb := HBoxContainer.new()
	left.add_child(lb)
	lb.add_child(_btn("추가", _add_line))
	lb.add_child(_btn("복제", _dup_line))
	lb.add_child(_btn("삭제", _del_line))
	lb.add_child(_btn("▲", func(): _move_line(-1)))
	lb.add_child(_btn("▼", func(): _move_line(1)))
	left.add_child(_small("고르는 법: 조건이 모두 맞는 대사 중 우선순위가 가장 높은 것 → 같으면 그 대원 전용 대사가 공통보다 먼저 → 그래도 같으면 무작위.\n" +
		"조건이 없는 대사(우선순위 0)를 대원마다 하나 이상 두면 아무 상황에서도 말함."))
	# 오른쪽: 편집 + 시험
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var upper := HBoxContainer.new()
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper.add_theme_constant_override("separation", 12)
	right.add_child(upper)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	upper.add_child(scroll)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)
	var bcol := VBoxContainer.new()
	bcol.custom_minimum_size.x = 280
	upper.add_child(bcol)
	bcol.add_child(_head("말풍선 미리보기"))
	bubble_box = _bubble_area()
	bcol.add_child(bubble_box)
	bcol.add_child(_small("게임 화면과 같은 폭(230px). 두 줄을 넘으면 옆 칸 초상화를 가립니다."))
	var lower := HSplitContainer.new()
	lower.custom_minimum_size.y = 300
	right.add_child(lower)
	var tl := VBoxContainer.new()
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(tl)
	tl.add_child(_head("시험: 이런 상황이면 무슨 말을 하나"))
	test_box = VBoxContainer.new()
	tl.add_child(test_box)
	var tr := HBoxContainer.new()
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tl.add_child(tr)
	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tr.add_child(result_label)
	test_bubble_box = _bubble_area()
	tr.add_child(test_bubble_box)
	var ck := VBoxContainer.new()
	ck.custom_minimum_size.x = 340
	lower.add_child(ck)
	ck.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ck.add_child(check_label)
	reload_data(false)


func _bubble_area() -> Control:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(270, 120)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.23)
	sb.set_corner_radius_all(8)
	c.add_theme_stylebox_override("panel", sb)
	c.clip_contents = true
	return c


# ================================================================ 데이터
func reload_data(keep_edit: bool = true) -> void:
	char_ids.clear()
	names.clear()
	var gd := GameData.load_from()
	if gd != null:
		for u in gd.allies:
			char_ids.append(u.id)
			names[u.id] = u.display_name
	status_ids.clear()
	status_names.clear()
	for sid in StatusCatalog.all_ids():
		status_ids.append(sid)
		status_names[sid] = str(StatusCatalog.get_def(sid).name)
	if test.char == "" and not char_ids.is_empty():
		test.char = char_ids[0]
	_rebuild_filter()
	_rebuild_test()
	if keep_edit and dirty:
		_rebuild()
	else:
		_load()


func _load() -> void:
	lines = SortieLines.read()
	dirty = false
	sel = clampi(sel, 0, lines.size() - 1) if not lines.is_empty() else -1
	status.text = "%d개 대사" % lines.size()
	_rebuild()


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 됨)"
	_refresh_list()
	_refresh_bubble()
	_refresh_test()
	_refresh_check()


func _unique_id() -> String:
	var ids := lines.map(func(l): return str(l.get("id", "")))
	var i := lines.size() + 1
	while ids.has("line_%d" % i):
		i += 1
	return "line_%d" % i


func _add_line() -> void:
	var l := SortieLines.new_line(_unique_id(), filter if filter != "*" else "")
	l.text = "준비됐습니다."
	lines.append(l)
	sel = lines.size() - 1
	_rebuild()
	_mark()


func _dup_line() -> void:
	if sel < 0:
		return
	var l: Dictionary = lines[sel].duplicate(true)
	l.id = _unique_id()
	lines.insert(sel + 1, l)
	sel += 1
	_rebuild()
	_mark()


func _del_line() -> void:
	if sel < 0:
		return
	lines.remove_at(sel)
	sel = mini(sel, lines.size() - 1)
	_rebuild()
	_mark()


func _move_line(d: int) -> void:
	var j := sel + d
	if sel < 0 or j < 0 or j >= lines.size():
		return
	var l = lines[sel]
	lines[sel] = lines[j]
	lines[j] = l
	sel = j
	_rebuild()
	_mark()


func _select(i: int) -> void:
	sel = i
	_rebuild_form()
	_refresh_bubble()


# ================================================================ 화면 구성
func _rebuild() -> void:
	_refresh_list()
	_rebuild_form()
	_refresh_bubble()
	_refresh_test()
	_refresh_check()


func _rebuild_filter() -> void:
	filter_opt.clear()
	var opts := [["*", "전체"], ["", "공통 (모든 대원)"]]
	for c in char_ids:
		opts.append([c, names[c]])
	for o in opts:
		filter_opt.add_item(o[1])
		filter_opt.set_item_metadata(filter_opt.item_count - 1, o[0])
		if o[0] == filter:
			filter_opt.select(filter_opt.item_count - 1)


func _who(c: String) -> String:
	return "공통" if c == "" else str(names.get(c, c + "?"))


func _refresh_list() -> void:
	line_list.clear()
	for i in lines.size():
		var l: Dictionary = lines[i]
		if filter != "*" and str(l.get("char", "")) != filter:
			continue
		line_list.add_item("[%s] %s\n   %s" % [_who(str(l.get("char", ""))), l.get("text", ""), SortieLines.describe(l, status_names, names)])
		var k := line_list.item_count - 1
		line_list.set_item_metadata(k, i)
		if str(l.get("text", "")).strip_edges() == "":
			line_list.set_item_custom_fg_color(k, Color(1.0, 0.6, 0.4))
		elif str(l.get("char", "")) == "":
			line_list.set_item_custom_fg_color(k, Color(0.75, 0.85, 1.0))
		if i == sel:
			line_list.select(k)


func _rebuild_form() -> void:
	_rebuilding = true
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	if sel < 0 or sel >= lines.size():
		form.add_child(_small("대사가 없습니다. 왼쪽 '추가' 로 만드세요."))
		_rebuilding = false
		return
	var l: Dictionary = lines[sel]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	form.add_child(grid)
	var who := [["", "공통 (모든 대원)"]]
	for c in char_ids:
		who.append([c, names[c]])
	_row(grid, "누가", _option(who, str(l.get("char", "")), func(v):
		l.char = v
		_refresh_list()))
	_row(grid, "대사", _line(str(l.get("text", "")), func(t): l.text = t, "짧게 · {name} = 이 대원 이름, {with} = '함께 출정' 대원 이름"))
	var pr := _spin(-100, 100, 1, int(l.get("priority", 0)), "")
	pr.value_changed.connect(func(v):
		if not _rebuilding:
			l.priority = int(v)
			_mark())
	_row(grid, "우선순위 (클수록 먼저)", pr)
	_row(grid, "친밀도 (0~100)", _range(l, "aff_min", "aff_max"))
	_row(grid, "피로도 (0~100)", _range(l, "fat_min", "fat_max"))
	_row(grid, "체력 % (남은 체력 / 최대)", _range(l, "hp_min", "hp_max"))
	var sts := [[SortieLines.STATUS_ANY, "상관없음"], [SortieLines.STATUS_NONE, "상태 이상 없을 때"]]
	for sid in status_ids:
		sts.append([sid, "%s 일 때" % status_names[sid]])
	_row(grid, "상태 이상", _option(sts, str(l.get("status", "")), func(v): l.status = v))
	var rows := []
	for k in ["", "front", "middle", "back"]:
		rows.append([k, SortieLines.ROW_NAMES[k] + ("" if k == "" else " 에 배치됐을 때")])
	_row(grid, "자리", _option(rows, str(l.get("row", "")), func(v): l.row = v))
	var w := [["", "상관없음"]]
	for c in char_ids:
		w.append([c, "%s 도 출정할 때" % names[c]])
	_row(grid, "함께 출정", _option(w, str(l.get("with", "")), func(v): l["with"] = v))
	_row(grid, "메모", _line(str(l.get("note", "")), func(t): l.note = t))
	_row(grid, "id", _line(str(l.get("id", "")), func(t): l.id = t.strip_edges()))
	form.add_child(_small("※ 대원을 진형에 놓을 때(자리 교환 포함)와 출정 대기 화면을 열 때 한마디 합니다. 상태는 기지의 그 대원 상태 그대로."))
	_rebuilding = false


func _range(l: Dictionary, lo_key: String, hi_key: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lo := _spin(0, 100, 1, int(l.get(lo_key, 0)), "")
	var hi := _spin(0, 100, 1, int(l.get(hi_key, 100)), "")
	lo.value_changed.connect(func(v):
		if not _rebuilding:
			l[lo_key] = int(v)
			_mark())
	hi.value_changed.connect(func(v):
		if not _rebuilding:
			l[hi_key] = int(v)
			_mark())
	hb.add_child(lo)
	var t := Label.new()
	t.text = "~"
	hb.add_child(t)
	hb.add_child(hi)
	return hb


func _refresh_bubble() -> void:
	var t := ""
	if sel >= 0 and sel < lines.size():
		var l: Dictionary = lines[sel]
		var c := str(l.get("char", ""))
		if c == "":
			c = test.char
		t = SortieLines.format(str(l.get("text", "")), l, {"name": names.get(c, c), "names": names})
	_show_bubble(bubble_box, t)


func _show_bubble(box: Control, text: String) -> void:
	for c in box.get_children():
		c.queue_free()
	if text.strip_edges() == "":
		return
	var b := SpeechBubble.new()
	box.add_child(b)
	var w := maxf(box.size.x, box.custom_minimum_size.x)
	b.setup(text, _font, Vector2(w * 0.5, maxf(box.size.y, box.custom_minimum_size.y) - 14), -1.0, BUBBLE_W, 14, Vector2(4, w - 4))


# ================================================================ 시험
func _rebuild_test() -> void:
	for c in test_box.get_children():
		test_box.remove_child(c)
		c.queue_free()
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	test_box.add_child(g)
	var who := []
	for c in char_ids:
		who.append([c, names[c]])
	g.add_child(_lab("대원"))
	g.add_child(_option(who, str(test.char), func(v):
		test.char = v
		_refresh_bubble()
		_refresh_test(), false))
	g.add_child(_lab("자리"))
	g.add_child(_option([[0, "전방"], [1, "중간"], [2, "후방"]], int(test.row), func(v):
		test.row = int(v)
		_refresh_test(), false))
	for k in [["affinity", "친밀도"], ["fatigue", "피로도"], ["hp_pct", "체력 %"]]:
		g.add_child(_lab(k[1]))
		g.add_child(_slider(k[0]))
	g.add_child(_lab("상태 이상"))
	var sts := [["", "없음"]]
	for sid in status_ids:
		sts.append([sid, status_names[sid]])
	g.add_child(_option(sts, str(test.status), func(v):
		test.status = v
		_refresh_test(), false))
	var wb := HFlowContainer.new()
	wb.add_child(_lab("함께 출정:"))
	for c in char_ids:
		var cb := CheckBox.new()
		cb.text = names[c]
		cb.button_pressed = (test.with as Array).has(c)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on):
			if on and not (test.with as Array).has(c):
				test.with.append(c)
			elif not on:
				test.with.erase(c)
			_refresh_test())
		wb.add_child(cb)
	test_box.add_child(wb)


func _slider(key: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size.x = 220
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.value = float(test[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.text = str(int(test[key]))
	v.custom_minimum_size.x = 30
	s.value_changed.connect(func(x):
		test[key] = x
		v.text = str(int(x))
		_refresh_test())
	hb.add_child(s)
	hb.add_child(v)
	return hb


func _test_ctx() -> Dictionary:
	var dep: Array = (test.with as Array).duplicate()
	if not dep.has(test.char):
		dep.append(test.char)
	var sts := [] if str(test.status) == "" else [str(test.status)]
	return SortieLines.make_context(str(test.char), str(names.get(test.char, test.char)), float(test.affinity), float(test.fatigue),
		float(test.hp_pct), sts, int(test.row), dep, names)


func _refresh_test() -> void:
	if result_label == null:
		return
	var ctx := _test_ctx()
	var c := SortieLines.candidates(lines, ctx)
	if c.is_empty():
		result_label.text = "[color=#ffd166]맞는 대사가 없습니다 — 이 상황에서는 말풍선이 뜨지 않습니다.[/color]"
		_show_bubble(test_bubble_box, "")
		return
	var top: Dictionary = c[0]
	var t := PackedStringArray()
	t.append("[b]고르는 대상[/b] (우선순위 %d%s, 이 중 무작위):" % [int(top.priority), ", 전용" if str(top.char) != "" else ", 공통"])
	var sep := false
	for l in c:
		var first := int(l.priority) == int(top.priority) and (str(l.char) != "") == (str(top.char) != "")
		if not first and not sep:
			t.append("[color=#8899aa]— 그 밖에 맞지만 밀린 대사 —[/color]")
			sep = true
		var col := "#ffffff" if first else "#8899aa"
		t.append("[color=%s]· [%s] %s   (%s)[/color]" % [col, _who(str(l.char)), SortieLines.format(str(l.text), l, ctx), SortieLines.describe(l, status_names, names)])
	result_label.text = "\n".join(t)
	_show_bubble(test_bubble_box, SortieLines.format(str(top.text), top, ctx))


# ================================================================ 검사
func _refresh_check() -> void:
	if check_label == null:
		return
	var out := PackedStringArray()
	var ids := {}
	for l in lines:
		var nm := "%s [%s]" % [str(l.get("id", "")), _who(str(l.get("char", "")))]
		if ids.has(str(l.id)):
			out.append("[color=#ff7766]%s: id 가 겹침[/color]" % nm)
		ids[str(l.id)] = true
		if str(l.get("text", "")).strip_edges() == "":
			out.append("[color=#ff7766]%s: 대사가 비어 있음 (나오지 않음)[/color]" % nm)
		elif str(l.text).length() > 30:
			out.append("[color=#ffd166]%s: 대사가 김 (%d자) — 말풍선이 세 줄 이상[/color]" % [nm, str(l.text).length()])
		for p in [["aff_min", "aff_max", "친밀도"], ["fat_min", "fat_max", "피로도"], ["hp_min", "hp_max", "체력"]]:
			if int(l.get(p[0], 0)) > int(l.get(p[1], 100)):
				out.append("[color=#ff7766]%s: %s 최소가 최대보다 큼 (나오지 않음)[/color]" % [nm, p[2]])
		var c := str(l.get("char", ""))
		if c != "" and not names.has(c):
			out.append("[color=#ff7766]%s: 캐릭터 시트에 없는 대원 '%s'[/color]" % [nm, c])
		var w := str(l.get("with", ""))
		if w != "" and not names.has(w):
			out.append("[color=#ff7766]%s: '함께 출정' 대원 '%s' 없음[/color]" % [nm, w])
		if w != "" and w == c:
			out.append("[color=#ff7766]%s: 자기 자신과 함께 출정 (나오지 않음)[/color]" % nm)
		if str(l.get("text", "")).contains("{with}") and w == "":
			out.append("[color=#ffd166]%s: {with} 를 썼지만 '함께 출정' 조건이 없음[/color]" % nm)
	# 대원마다: 어떤 상황에서도 말풍선이 뜨는지 (대표 상황들을 훑어봄)
	for c in char_ids:
		var miss := ""
		for aff in [0, 15, 50, 70, 100]:
			for fat in [0, 50, 70, 90, 100]:
				for hp in [20, 40, 100]:
					for st in [[], ["injured"]]:
						for row in 3:
							var ctx := SortieLines.make_context(c, names[c], aff, fat, hp, st, row, [c], names)
							if miss == "" and SortieLines.candidates(lines, ctx).is_empty():
								miss = "친밀도 %d · 피로 %d · 체력 %d%%%s · %s" % [aff, fat, hp, " · 부상" if not st.is_empty() else "", ["전방", "중간", "후방"][row]]
		if miss != "":
			out.append("[color=#ffd166]%s: 대사가 없는 상황이 있음 (예: %s)[/color]" % [names[c], miss])
	check_label.text = "\n".join(out) if not out.is_empty() else "[color=#88ff99]문제 없음[/color]"


# ================================================================ 저장 · 테스트
func _save() -> void:
	var err := SortieLines.write(lines)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	dirty = err != OK
	status.text = "저장됨: data/outgame/sortie_lines.json" if err == OK else "저장 실패 (%d)" % err


## 저장 → 새 기지에서 출전한 출정 대기 화면 (대원 상태를 섞어서: 키라 피로 85, 단 부상, 니키타·하나 친밀도 높음, 이선 외부 의뢰)
func _play() -> void:
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"sortie": true, "demo": true}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_main_scene()


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 작은 위젯
func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


func _lab(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
	return l


## items = [[값, 표시], …]. mark = true 면 바꿀 때 '수정됨'
func _option(items: Array, cur: Variant, cb: Callable, mark: bool = true) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it[1]))
		o.set_item_metadata(o.item_count - 1, it[0])
		if str(it[0]) == str(cur):
			o.select(o.item_count - 1)
	o.item_selected.connect(func(i):
		if _rebuilding:
			return
		cb.call(o.get_item_metadata(i))
		if mark:
			_mark())
	return o


func _line(t: String, cb: Callable, hint: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = t
	e.placeholder_text = hint
	e.custom_minimum_size.x = 260
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


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	return l
