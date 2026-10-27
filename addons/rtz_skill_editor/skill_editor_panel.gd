@tool
extends Control
## 스킬 트리 에디터 (Godot 에디터 상단 "스킬 트리" 탭, addons/rtz_skill_editor) → data/skill_tree.json.
## 위: 캐릭터 · 액티브/패시브 고르기 · 다른 캐릭터 트리 가져오기 · 필요 레벨 자동.
## 가운데: 게임과 같은 십자형 그림 — 노드 클릭 = 고르기, "+" 칸 = 그 갈래 끝에 단계 추가(최대 SkillTreeData.MAX_TIER).
## 오른쪽: 고른 노드의 id · 이름 · 필요 레벨 · 효과 · 값 · 설명, 단계 옮기기 · 삭제, 아래 검사.
## 게임 규칙(BaseSim): 중앙은 처음부터 습득, 갈래 안은 앞 단계부터, 갈래 끝(마지막 단계)은 트리마다 하나만, 스킬 포인트는 두 트리 공용.

const CANVAS := preload("res://addons/rtz_skill_editor/skill_tree_canvas.gd")

var nodes: Array = []                # 전체 노드 (모든 캐릭터)
var dirty := false
var _rebuilding := false
var allies: Array = []               # UnitData
var actions: Dictionary = {}         # 스킬 id → ActionData
var cid := ""
var kind := "active"
var sel := ""                        # 고른 노드 id

var char_opt: OptionButton
var kind_btns: Dictionary = {}
var copy_opt: OptionButton
var play_level: SpinBox
var status: Label
var canvas: Control
var form: VBoxContainer
var check_label: RichTextLabel
var info_label: Label


func _ready() -> void:
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
	title.text = "스킬 트리"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	top.add_child(_btn("저장 (Ctrl+S)", _save))
	top.add_child(_btn("되돌리기", func(): _load()))
	top.add_child(_btn("기지 스킬 창 테스트 플레이", _play))
	top.add_child(_lab("레벨"))
	play_level = _spin(1, 20, 1, 9, "")
	play_level.tooltip_text = "테스트 플레이 때 이 대원의 레벨 (포인트도 그만큼)"
	top.add_child(play_level)
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)

	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 4)
	root.add_child(bar)
	bar.add_child(_lab("캐릭터"))
	char_opt = OptionButton.new()
	char_opt.custom_minimum_size.x = 170
	char_opt.item_selected.connect(func(i):
		cid = str(char_opt.get_item_metadata(i))
		sel = ""
		_rebuild())
	bar.add_child(char_opt)
	for k in SkillTreeData.KINDS:
		var b := Button.new()
		b.text = "%s 트리" % SkillTreeData.KIND_NAME[k]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var kk: String = k
		b.pressed.connect(func():
			kind = kk
			sel = ""
			_rebuild())
		kind_btns[k] = b
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	bar.add_child(_lab("다른 캐릭터 트리"))
	copy_opt = OptionButton.new()
	copy_opt.custom_minimum_size.x = 150
	bar.add_child(copy_opt)
	var cp := _btn("가져오기", _copy_from)
	cp.tooltip_text = "고른 캐릭터의 같은 종류 트리를 복사해서 지금 트리를 덮어씀 (id 는 새로, 필요 레벨은 시작 레벨 차이만큼)"
	bar.add_child(cp)
	bar.add_child(VSeparator.new())
	var auto := _btn("필요 레벨 자동", _auto_levels)
	auto.tooltip_text = "이 트리의 필요 레벨을 캐릭터 시작 레벨 + 2 × (단계 - 1) 로 (중앙 = 시작 레벨)"
	bar.add_child(auto)
	bar.add_child(_btn("트리 비우기", _clear_tree))
	info_label = _lab("")
	root.add_child(info_label)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	canvas = CANVAS.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(560, 420)
	canvas.node_clicked.connect(func(id):
		sel = id
		_rebuild())
	canvas.add_clicked.connect(_add_node)
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
	right.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.custom_minimum_size.y = 150
	check_label.fit_content = false
	check_label.scroll_active = true
	right.add_child(check_label)
	reload_data(false)


## 탭을 열 때마다 캐릭터·스킬 목록 다시 읽기 (편집 중인 노드는 유지)
func reload_data(keep_edit: bool = true) -> void:
	allies.clear()
	actions = {}
	var gd := GameData.load_from()
	if gd != null:
		allies.assign(gd.allies)
		actions = gd.actions
	char_opt.clear()
	copy_opt.clear()
	for u in allies:
		char_opt.add_item("%s (%s)" % [u.display_name, u.id])
		char_opt.set_item_metadata(char_opt.item_count - 1, u.id)
		copy_opt.add_item(u.display_name)
		copy_opt.set_item_metadata(copy_opt.item_count - 1, u.id)
	if cid == "" or _unit(cid) == null:
		cid = allies[0].id if not allies.is_empty() else ""
	if keep_edit and dirty:
		_rebuild()
	else:
		_load()


func _load() -> void:
	nodes = SkillTreeData.read()
	dirty = false
	status.text = "data/skill_tree.json — 노드 %d개" % nodes.size()
	_rebuild()


func _save() -> void:
	var err := SkillTreeData.write(nodes)
	if err == OK:
		dirty = false
		var errs: PackedStringArray = SkillTreeData.check(nodes, allies, actions).errors
		status.text = "저장됨: data/skill_tree.json" + ("" if errs.is_empty() else "  (검사 오류 %d개 — 아래 확인)" % errs.size())
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(SkillTreeData.PATH)
	else:
		status.text = "저장 실패 (%d)" % err


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 함)"
	_refresh_view()


## 저장 → 새 기지에서 이 대원 스킬 창 (레벨 올린 상태, 저장 파일은 건드리지 않음)
func _play() -> void:
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"base": true, "skills": {"char": cid, "kind": kind, "level": int(play_level.value)}}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn")


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 데이터 도우미
func _unit(id: String) -> UnitData:
	for u in allies:
		if u.id == id:
			return u
	return null


func _tree() -> Array:
	return nodes.filter(func(n): return n.char == cid and n.kind == kind)


func _node(id: String) -> Dictionary:
	for n in nodes:
		if n.id == id:
			return n
	return {}


func _at(dir: String, tier: int) -> Dictionary:
	for n in _tree():
		if n.dir == dir and int(n.tier) == tier:
			return n
	return {}


func _start_level() -> int:
	var u := _unit(cid)
	return u.level if u != null else 1


## 겹치지 않는 새 id: <캐릭터>_<a|p>_<방향><단계>
func _new_id(dir: String, tier: int) -> String:
	var short := cid.trim_prefix("a_")
	var base := "%s_%s_%s" % [short, "a" if kind == "active" else "p", "core" if dir == "center" else "%s%d" % [dir, tier]]
	var id := base
	var i := 2
	while not _node(id).is_empty():
		id = "%s_%d" % [base, i]
		i += 1
	return id


func _add_node(dir: String, tier: int) -> void:
	var n := SkillTreeData.new_node(cid, kind, dir, tier)
	n.id = _new_id(dir, tier)
	var prev := _at(dir, tier - 1) if dir != "center" else {}
	n.level = int(prev.level) + 2 if not prev.is_empty() else _start_level()
	n.desc = SkillTreeData.auto_desc(n.effect, int(n.value), actions)
	nodes.append(n)
	sel = n.id
	_mark()
	_rebuild()


func _delete(id: String) -> void:
	var n := _node(id)
	if n.is_empty():
		return
	nodes.erase(n)
	# 뒤 단계는 한 칸씩 당김
	if n.dir != "center":
		for o in _tree():
			if o.dir == n.dir and int(o.tier) > int(n.tier):
				o.tier = int(o.tier) - 1
	sel = ""
	_mark()
	_rebuild()


## 같은 갈래 이웃 단계와 자리 바꾸기 (d = -1 앞으로 / +1 뒤로)
func _swap(id: String, d: int) -> void:
	var n := _node(id)
	if n.is_empty() or n.dir == "center":
		return
	var o := _at(n.dir, int(n.tier) + d)
	if o.is_empty():
		return
	o.tier = int(n.tier)
	n.tier = int(n.tier) + d
	_mark()
	_rebuild()


func _copy_from() -> void:
	if copy_opt.selected < 0:
		return
	var src := str(copy_opt.get_item_metadata(copy_opt.selected))
	if src == cid:
		status.text = "같은 캐릭터입니다"
		return
	var su := _unit(src)
	var dl := _start_level() - (su.level if su != null else 1)
	for n in _tree():
		nodes.erase(n)
	for n in nodes.filter(func(x): return x.char == src and x.kind == kind):
		var c: Dictionary = n.duplicate()
		c.char = cid
		c.id = _new_id(c.dir, int(c.tier))
		c.level = maxi(1, int(c.level) + dl)
		nodes.append(c)
	sel = ""
	status.text = "%s 의 %s 트리를 가져왔습니다 (필요 레벨은 시작 레벨 차이 %+d 만큼)" % [su.display_name if su != null else src, SkillTreeData.KIND_NAME[kind], dl]
	dirty = true
	_rebuild()


func _auto_levels() -> void:
	var lv := _start_level()
	for n in _tree():
		n.level = lv if n.dir == "center" else lv + 2 * (int(n.tier) - 1)
	_mark()
	_rebuild()


func _clear_tree() -> void:
	for n in _tree():
		nodes.erase(n)
	sel = ""
	_mark()
	_rebuild()


# ================================================================ 화면
func _rebuild() -> void:
	_rebuilding = true
	for i in char_opt.item_count:
		if str(char_opt.get_item_metadata(i)) == cid:
			char_opt.select(i)
	for k in kind_btns:
		kind_btns[k].button_pressed = k == kind
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	_build_form()
	_rebuilding = false
	_refresh_view()


func _refresh_view() -> void:
	canvas.show_tree(_tree(), sel)
	var u := _unit(cid)
	var t := _tree()
	var ends := []
	for d in ["n", "e", "s", "w"]:
		ends.append(SkillTreeData.branch_end(nodes, cid, kind, d))
	info_label.text = "노드 %d개 · 갈래 길이 북 %d / 동 %d / 남 %d / 서 %d · 시작 Lv%d" % [t.size(), ends[0], ends[1], ends[2], ends[3], u.level if u != null else 1]
	var res := SkillTreeData.check(nodes, allies, actions)
	var txt := ""
	for e in res.errors:
		txt += "[color=#ff7766]✖ %s[/color]\n" % e
	for e in res.notes:
		txt += "[color=#ffd166]△ %s[/color]\n" % e
	check_label.text = txt if txt != "" else "[color=#77dd88]문제 없음[/color]"


func _build_form() -> void:
	var n := _node(sel)
	if n.is_empty() or n.char != cid or n.kind != kind:
		form.add_child(_head("노드를 고르세요"))
		form.add_child(_small("가운데 그림에서 노드를 누르면 여기서 고칩니다.\n'+' 칸을 누르면 그 갈래 끝에 새 단계를 붙입니다 (갈래마다 최대 %d단계, 중앙이 없으면 가운데 '+').\n\n" % SkillTreeData.MAX_TIER
			+ "게임 규칙\n· 중앙은 처음부터 배운 상태\n· 갈래 안에서는 앞 단계를 배워야 다음 단계\n· 갈래 끝(마지막 단계)은 트리마다 하나만 배울 수 있음 → 어느 방향으로 뻗을지가 빌드\n"
			+ "· 레벨이 필요 레벨보다 낮으면 게임에서 회색 + '경험 부족'\n· 스킬 포인트는 액티브·패시브 공용 (레벨 업마다 1, 처음 1)\n"
			+ "· 액티브 = 전투 스킬 강화·새 스킬, 패시브 = 능력치 (종류는 탭 구분일 뿐, 효과는 어느 쪽에도 넣을 수 있음)"))
		return
	var where := "%s · %s" % [SkillTreeData.KIND_NAME[kind], SkillTreeData.DIR_NAME[n.dir]]
	if n.dir != "center":
		where += " · %d단계%s" % [int(n.tier), " (갈래 끝)" if int(n.tier) == SkillTreeData.branch_end(nodes, cid, kind, n.dir) else ""]
	form.add_child(_head(where))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	form.add_child(grid)
	var id_edit := LineEdit.new()
	id_edit.text = str(n.id)
	id_edit.placeholder_text = "고유 id (영문) — Enter 로 적용"
	id_edit.text_submitted.connect(func(v): _rename(n, v))
	id_edit.focus_exited.connect(func(): _rename(n, id_edit.text))
	_row(grid, "id", id_edit)
	_row(grid, "이름", _line(str(n.name), func(v):
		n.name = v
		canvas.queue_redraw()))
	var lv := _spin(1, 99, 1, int(n.level), "")
	lv.value_changed.connect(func(v):
		if not _rebuilding:
			n.level = int(v)
			_mark())
	_row(grid, "필요 레벨", lv)
	var desc := TextEdit.new()
	desc.text = str(n.desc)
	desc.custom_minimum_size = Vector2(260, 64)
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.text_changed.connect(func():
		if not _rebuilding:
			n.desc = desc.text
			_mark())
	var ef: String = n.effect
	var ef_kind := ef.split(":")[0] if ":" in ef else ef
	var eff_items := []
	for e in SkillTreeData.EFFECTS:
		eff_items.append([e, SkillTreeData.EFFECT_NAME[e]])
	_row(grid, "효과", _option(eff_items, ef_kind, func(v):
		_set_effect(n, str(v), _first_skill(str(v)) if str(v) in ["skill", "skill_power"] else "")
		_rebuild()))
	if ef_kind in ["skill", "skill_power"]:
		var sk_items := []
		for sid in actions:
			var a: ActionData = actions[sid]
			if a.effect in ["move", "weapon_swap"]:
				continue
			sk_items.append([sid, "%s (%s)" % [a.display_name, sid]])
		_row(grid, "스킬", _option(sk_items, ef.split(":")[1] if ":" in ef else "", func(v):
			_set_effect(n, ef_kind, str(v))
			_rebuild()))
	if ef_kind != "skill":
		var val := _spin(-99, 999, 1, int(n.value), "")
		val.value_changed.connect(func(v):
			if not _rebuilding:
				var was_auto: bool = str(n.desc) == SkillTreeData.auto_desc(str(n.effect), int(n.value), actions)
				n.value = int(v)
				if was_auto:
					n.desc = SkillTreeData.auto_desc(str(n.effect), int(n.value), actions)
					_rebuilding = true
					desc.text = n.desc
					_rebuilding = false
				_mark())
		_row(grid, "값", val)
	_row(grid, "설명", desc)
	var auto := _btn("설명 자동 채우기", func():
		n.desc = SkillTreeData.auto_desc(str(n.effect), int(n.value), actions)
		_mark()
		_rebuild())
	form.add_child(auto)
	form.add_child(_small("설명이 자동 문장 그대로면 효과·값을 바꿀 때 같이 바뀝니다."))
	if ef_kind == "skill":
		form.add_child(_small("새 스킬은 전투 HUD 기본 스킬 칸(%d칸, 필살기 제외)에 붙습니다. 칸이 넘치면 안 보이므로 갈래 끝에 두는 것을 권장." % SkillTreeData.SKILL_SLOTS))
	var mv := HBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	form.add_child(mv)
	if n.dir != "center":
		var back := _btn("◀ 한 단계 안쪽으로", func(): _swap(str(n.id), -1))
		back.disabled = _at(n.dir, int(n.tier) - 1).is_empty()
		mv.add_child(back)
		var fwd := _btn("한 단계 바깥으로 ▶", func(): _swap(str(n.id), 1))
		fwd.disabled = _at(n.dir, int(n.tier) + 1).is_empty()
		mv.add_child(fwd)
	var del := _btn("이 노드 삭제", func(): _delete(str(n.id)))
	del.tooltip_text = "바깥 단계는 한 칸씩 안으로 당겨집니다"
	mv.add_child(del)
	form.add_child(_small("※ id 를 바꾸면 이미 그 스킬을 배운 저장 파일에서는 배운 것이 풀립니다 (포인트는 돌려받음)."))


func _rename(n: Dictionary, v: String) -> void:
	v = v.strip_edges()
	if v == "" or v == n.id:
		return
	if not _node(v).is_empty():
		status.text = "id '%s' 는 이미 있습니다" % v
		return
	n.id = v
	sel = v
	_mark()


func _first_skill(ef_kind: String) -> String:
	for sid in actions:
		var a: ActionData = actions[sid]
		if a.effect in ["move", "weapon_swap"] or (ef_kind == "skill" and a.kind == "ultimate"):
			continue
		return str(sid)
	return ""


func _set_effect(n: Dictionary, ef_kind: String, sid: String) -> void:
	var was_auto: bool = str(n.desc) == "" or str(n.desc) == SkillTreeData.auto_desc(str(n.effect), int(n.value), actions)
	n.effect = ef_kind if sid == "" else "%s:%s" % [ef_kind, sid]
	if ef_kind == "skill":
		n.value = 1
	if was_auto:
		n.desc = SkillTreeData.auto_desc(str(n.effect), int(n.value), actions)
	_mark()


# ================================================================ 작은 위젯
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
	l.custom_minimum_size.x = 360
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	return l
