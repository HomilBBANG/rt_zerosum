@tool
extends Control
## 스킬 트리 에디터 (Godot 에디터 상단 "스킬 트리" 탭, addons/rtz_skill_editor) → data/skill_tree.json + data/faith.json.
## 위: 캐릭터 · 액티브/패시브/신앙 고르기 · 다른 캐릭터 트리 가져오기 · 필요 레벨 자동.
## 신앙: 왼쪽 신 목록(추가·삭제) · 가운데 그 신의 신앙 스킬(필요 신앙도 순) · 오른쪽 신·스킬 고치기. 누가 어느 신을 믿는지는 엑셀 캐릭터 시트.
## 상태 이상: 왼쪽 스킬 목록(누가 쓰는지·달린 상태 이상) · 오른쪽 그 스킬에 상태 이상 달기(여러 개, 턴·수치·확률) → data/skill_status.json.
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
## 신앙 (kind == "faith")
var faith: Dictionary = {"gods": [], "skills": []}
var char_faith: Dictionary = {}      # 캐릭터 id → {god, faith} (엑셀 캐릭터 시트)
var god_sel := ""
var fsel := ""                       # 고른 신앙 스킬 id
var faith_box: Control
var god_list: ItemList
var fs_list: ItemList
var fs_head: Label
var tree_only: Array[Control] = []   # 신앙·상태 이상 모드에서 숨길 위쪽 도구
## 상태 이상 (kind == "status")
var sstat: Array = []                # data/skill_status.json 항목 [{skill, status, turns, value, chance}]
var monsters: Dictionary = {}        # 몬스터 id → UnitData (누가 쓰는 스킬인지 표시)
var skill_sel := ""
var skill_filter := "all"
var status_box: Control
var skill_list: ItemList

var char_opt: OptionButton
var kind_btns: Dictionary = {}
var copy_opt: OptionButton
var play_level: SpinBox
var play_btn: Button
var level_lab: Label
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
	play_btn = _btn("기지 스킬 창 테스트 플레이", _play)
	top.add_child(play_btn)
	level_lab = _lab("레벨")
	top.add_child(level_lab)
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
	var cl := _lab("캐릭터")
	bar.add_child(cl)
	tree_only.append(cl)
	char_opt = OptionButton.new()
	char_opt.custom_minimum_size.x = 170
	char_opt.item_selected.connect(func(i):
		cid = str(char_opt.get_item_metadata(i))
		sel = ""
		_rebuild())
	bar.add_child(char_opt)
	tree_only.append(char_opt)
	for k in SkillTreeData.KINDS + ["faith", "status"]:
		var b := Button.new()
		b.text = "%s 트리" % SkillTreeData.KIND_NAME[k] if k in SkillTreeData.KINDS else ("신앙 스킬" if k == "faith" else "상태 이상")
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var kk: String = k
		b.pressed.connect(func():
			kind = kk
			sel = ""
			_rebuild())
		kind_btns[k] = b
		bar.add_child(b)
	var sep1 := VSeparator.new()
	var cl2 := _lab("다른 캐릭터 트리")
	copy_opt = OptionButton.new()
	copy_opt.custom_minimum_size.x = 150
	var cp := _btn("가져오기", _copy_from)
	cp.tooltip_text = "고른 캐릭터의 같은 종류 트리를 복사해서 지금 트리를 덮어씀 (id 는 새로, 필요 레벨은 시작 레벨 차이만큼)"
	var sep2 := VSeparator.new()
	var auto := _btn("필요 레벨 자동", _auto_levels)
	auto.tooltip_text = "이 트리의 필요 레벨을 캐릭터 시작 레벨 + 2 × (단계 - 1) 로 (중앙 = 시작 레벨)"
	var clr := _btn("트리 비우기", _clear_tree)
	for c in [sep1, cl2, copy_opt, cp, sep2, auto, clr]:
		bar.add_child(c)
		tree_only.append(c)
	info_label = _lab("")
	root.add_child(info_label)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var holder := VBoxContainer.new()   # 왼쪽: 트리 그림 또는 신앙 목록
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	canvas = CANVAS.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(560, 420)
	canvas.node_clicked.connect(func(id):
		sel = id
		_rebuild())
	canvas.add_clicked.connect(_add_node)
	holder.add_child(canvas)
	faith_box = _build_faith_box()
	faith_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	faith_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(faith_box)
	status_box = _build_status_box()
	status_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(status_box)
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
		char_faith = gd.char_faith
		monsters = gd.monsters
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
	faith = FaithData.read()
	sstat = SkillStatusData.read()
	if skill_sel == "" and not actions.is_empty():
		skill_sel = str(actions.keys()[0])
	if _god(god_sel).is_empty():
		god_sel = faith.gods[0].id if not faith.gods.is_empty() else ""
	dirty = false
	status.text = "data/skill_tree.json 노드 %d개 · data/faith.json 신 %d · 신앙 스킬 %d" % [nodes.size(), faith.gods.size(), faith.skills.size()]
	_rebuild()


## 스킬 트리 · 신앙 · 상태 이상 모두 저장
func _save() -> void:
	var err := SkillTreeData.write(nodes)
	var err2 := FaithData.write(faith)
	var err3 := SkillStatusData.write(sstat)
	if err == OK and err2 == OK and err3 == OK:
		dirty = false
		var errs: int = SkillTreeData.check(nodes, allies, actions).errors.size() + FaithData.check(faith, char_faith, actions).errors.size() \
			+ SkillStatusData.check(sstat, actions).errors.size()
		status.text = "저장됨: data/skill_tree.json · faith.json · skill_status.json" + ("" if errs == 0 else "  (검사 오류 %d개 — 아래 확인)" % errs)
		if Engine.is_editor_hint():
			for path in [SkillTreeData.PATH, FaithData.PATH, SkillStatusData.PATH]:
				EditorInterface.get_resource_filesystem().update_file(path)
	else:
		status.text = "저장 실패 (%d / %d / %d)" % [err, err2, err3]


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 함)"
	_refresh_view()


## 저장 → 새 기지에서 이 대원 스킬 창 (레벨 올린 상태, 저장 파일은 건드리지 않음)
## 상태 이상 모드: 전투 테스트 — 고른 스킬을 아군 모두에게 쥐여 주고 첫 스테이지
func _play() -> void:
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	if kind == "status":
		f.store_string(JSON.stringify({"try_skill": skill_sel}))
		f.close()
		if Engine.is_editor_hint():
			EditorInterface.play_custom_scene("res://scenes/battle_2d.tscn")
		return
	var who := cid
	if kind == "faith":   # 그 신을 믿는 첫 캐릭터
		for u in allies:
			if str(char_faith.get(u.id, {}).get("god", "")) == god_sel:
				who = u.id
				break
	f.store_string(JSON.stringify({"base": true, "skills": {"char": who, "kind": kind, "level": int(play_level.value)}}))
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
	var is_f := kind == "faith"
	var is_s := kind == "status"
	canvas.visible = not is_f and not is_s
	faith_box.visible = is_f
	status_box.visible = is_s
	for c in tree_only:
		c.visible = not is_f and not is_s
	play_level.visible = not is_s
	level_lab.visible = not is_s
	play_btn.text = "전투 테스트 플레이 (이 스킬 쥐여 주기)" if is_s else "기지 스킬 창 테스트 플레이"
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	if is_f:
		_fill_faith_lists()
		_build_faith_form()
	elif is_s:
		_fill_skill_list()
		_build_status_form()
	else:
		_build_form()
	_rebuilding = false
	_refresh_view()


func _refresh_view() -> void:
	if kind == "faith":
		_refresh_faith_view()
		return
	if kind == "status":
		info_label.text = "상태 이상 %d개 · 달린 스킬 %d개" % [sstat.size(), SkillStatusData.by_skill(sstat).size()]
		_show_check(SkillStatusData.check(sstat, actions))
		return
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


func _show_check(res: Dictionary) -> void:
	var txt := ""
	for e in res.errors:
		txt += "[color=#ff7766]✖ %s[/color]\n" % e
	for e in res.notes:
		txt += "[color=#ffd166]△ %s[/color]\n" % e
	check_label.text = txt if txt != "" else "[color=#77dd88]문제 없음[/color]"


# ================================================================ 상태 이상 (스킬에 달기)
const SKILL_FILTERS := [["all", "전체 스킬"], ["has", "상태 이상 달린 스킬"], ["ally", "아군이 쓰는 스킬"], ["monster", "괴물이 쓰는 스킬"]]


func _build_status_box() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var lc := VBoxContainer.new()
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lc)
	var fr := HBoxContainer.new()
	lc.add_child(fr)
	fr.add_child(_head("스킬"))
	var fo := OptionButton.new()
	for f in SKILL_FILTERS:
		fo.add_item(f[1])
		fo.set_item_metadata(fo.item_count - 1, f[0])
	fo.item_selected.connect(func(i):
		skill_filter = str(fo.get_item_metadata(i))
		_fill_skill_list())
	fr.add_child(fo)
	skill_list = ItemList.new()
	skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_list.item_selected.connect(func(i):
		skill_sel = str(skill_list.get_item_metadata(i))
		_rebuild())
	lc.add_child(skill_list)
	lc.add_child(_small("스킬 자체(AP·위력·대상)는 밸런스 엑셀 스킬 시트. 여기서는 맞은 대상에게 거는 상태 이상만 답니다 (한 스킬에 여러 개, 각각 따로 확률)."))
	# 상태 이상 설명 (참고)
	var rc := VBoxContainer.new()
	rc.custom_minimum_size.x = 300
	box.add_child(rc)
	rc.add_child(_head("상태 이상 종류"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rc.add_child(sc)
	var ref := VBoxContainer.new()
	ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(ref)
	for sid in StatusCatalog.BATTLE:
		var l := Label.new()
		l.text = "%s — %s" % [StatusCatalog.get_def(sid).name, str(StatusCatalog.get_def(sid).desc).replace("{t}", "n").replace("{v}", "v")]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 280
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", StatusCatalog.color_of(sid).lightened(0.2))
		ref.add_child(l)
	ref.add_child(_small("\n적용: 처음 걸릴 때 한 번 + 그 캐릭터 차례마다 행동보다 먼저. n턴 = 그 캐릭터 차례 n번 (차례가 끝날 때 1 감소, 동상은 차례 시작에 감소 → 0 이면 터짐). 다시 걸리면 남은 턴·수치 중 큰 쪽."))
	return box


## 이 스킬을 쓰는 쪽: 아군(기본 스킬 · 스킬 트리 새 스킬 · 신앙 새 스킬) / 괴물
func _users(sid: String) -> Dictionary:
	var al := PackedStringArray()
	var mo := PackedStringArray()
	for u in allies:
		if u.skill_ids.has(sid):
			al.append(u.display_name)
		elif nodes.any(func(n): return n.char == u.id and n.effect == "skill:" + sid):
			al.append(u.display_name + "(트리)")
	for f in faith.skills:
		if f.effect == "skill:" + sid:
			al.append("%s 신앙" % _god(f.god).get("name", f.god))
	for mid in monsters:
		if (monsters[mid] as UnitData).skill_ids.has(sid):
			mo.append((monsters[mid] as UnitData).display_name)
	return {"ally": al, "monster": mo}


func _skill_statuses(sid: String) -> Array:
	return sstat.filter(func(e): return e.skill == sid)


func _fill_skill_list() -> void:
	skill_list.clear()
	for sid in actions:
		var a: ActionData = actions[sid]
		if a.effect in ["move", "weapon_swap"]:
			continue
		var us := _users(sid)
		var mine := _skill_statuses(sid)
		match skill_filter:
			"has":
				if mine.is_empty():
					continue
			"ally":
				if us.ally.is_empty():
					continue
			"monster":
				if us.monster.is_empty():
					continue
		var tag := " · ".join(mine.map(func(e): return StatusCatalog.get_def(e.status).name)) if not mine.is_empty() else "-"
		skill_list.add_item("%s (%s)   [%s]" % [a.display_name, sid, tag])
		skill_list.set_item_metadata(skill_list.item_count - 1, sid)
		if not mine.is_empty():
			skill_list.set_item_custom_fg_color(skill_list.item_count - 1, StatusCatalog.color_of(mine[0].status).lightened(0.3))
		if sid == skill_sel:
			skill_list.select(skill_list.item_count - 1)


func _build_status_form() -> void:
	var a: ActionData = actions.get(skill_sel)
	if a == null:
		form.add_child(_head("스킬을 고르세요"))
		return
	form.add_child(_head("%s (%s)" % [a.display_name, a.id]))
	var eff := {"damage": "피해 %d" % a.power, "heal": "회복 %d" % a.power, "ap_grant": "AP +%d" % a.power, "status": "상태 이상만"}.get(a.effect, a.effect)
	form.add_child(_small("AP %d · 대상 %s · %s\n%s" % [a.ap_cost, a.target_rule, eff, a.description]))
	var us := _users(a.id)
	form.add_child(_small("쓰는 쪽: 아군 %s / 괴물 %s" % [", ".join(us.ally) if not us.ally.is_empty() else "-", ", ".join(us.monster) if not us.monster.is_empty() else "-"]))
	form.add_child(HSeparator.new())
	var mine := _skill_statuses(a.id)
	form.add_child(_head("맞은 대상에게 거는 상태 이상 (%d)" % mine.size()))
	if mine.is_empty():
		form.add_child(_small("없음 — 아래 '상태 이상 추가'"))
	var items := []
	for sid in StatusCatalog.BATTLE:
		items.append([sid, StatusCatalog.get_def(sid).name])
	for e in mine:
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(StatusCatalog.color_of(e.status).darkened(0.75), 0.9)
		sb.border_color = StatusCatalog.color_of(e.status)
		sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", sb)
		form.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		cv.add_child(grid)
		_row(grid, "상태 이상", _option(items, e.status, func(v):
			e.status = str(v)
			if SkillStatusData.VALUE_HINT.get(e.status, "") == "":
				e.value = 0
			elif int(e.value) <= 0:
				e.value = 10
			_mark()
			_rebuild()))
		var tu := _spin(1, 20, 1, int(e.turns), "")
		tu.value_changed.connect(func(v):
			if not _rebuilding:
				e.turns = int(v)
				_mark()
				_fill_skill_list())
		_row(grid, "턴 (차례 수)" if e.status != "frost" else "턴 (터지기까지)", tu)
		var hint: String = SkillStatusData.VALUE_HINT.get(e.status, "")
		if hint != "":
			var va := _spin(0, 999, 1, int(e.value), "")
			va.value_changed.connect(func(v):
				if not _rebuilding:
					e.value = int(v)
					_mark())
			_row(grid, "수치 (%s)" % hint, va)
		var ch := _spin(0, 100, 1, int(e.chance), " %")
		ch.value_changed.connect(func(v):
			if not _rebuilding:
				e.chance = int(v)
				_mark())
		_row(grid, "확률", ch)
		var bot := HBoxContainer.new()
		cv.add_child(bot)
		var prev := _small(StatusCatalog.describe(e.status, {"turns": e.turns, "value": e.value}))
		prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prev.custom_minimum_size.x = 260
		bot.add_child(prev)
		bot.add_child(_btn("빼기", func():
			sstat.erase(e)
			_mark()
			_rebuild()))
	var add := _btn("+ 상태 이상 추가", func():
		var used := mine.map(func(x): return x.status)
		var pick := "bleed"
		for sid in StatusCatalog.BATTLE:
			if not used.has(sid):
				pick = sid
				break
		sstat.append(SkillStatusData.new_entry(a.id, pick))
		_mark()
		_rebuild())
	form.add_child(add)
	if a.effect in ["heal", "ap_grant"]:
		form.add_child(_small("아군 대상 스킬이라 상태 이상도 아군에게 걸립니다 (가속 같은 긍정 상태에 쓰세요)."))
	form.add_child(_small("테스트 플레이 = 이 스킬을 아군 모두의 첫 스킬 칸에 넣고 첫 스테이지 전투."))


# ================================================================ 신앙
func _build_faith_box() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var gc := VBoxContainer.new()
	gc.custom_minimum_size.x = 240
	box.add_child(gc)
	gc.add_child(_head("신 (믿는 신 종류)"))
	god_list = ItemList.new()
	god_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	god_list.item_selected.connect(func(i):
		god_sel = str(god_list.get_item_metadata(i))
		fsel = ""
		_rebuild())
	gc.add_child(god_list)
	var gb := HBoxContainer.new()
	gc.add_child(gb)
	gb.add_child(_btn("신 추가", _add_god))
	gb.add_child(_btn("신 삭제", _delete_god))
	gc.add_child(_small("누가 어느 신을 믿는지·시작 신앙도는 밸런스 엑셀 캐릭터 시트 '신'·'신앙' 열 (신 id)."))
	var sc := VBoxContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(sc)
	fs_head = _head("")
	sc.add_child(fs_head)
	fs_list = ItemList.new()
	fs_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fs_list.item_selected.connect(func(i):
		fsel = str(fs_list.get_item_metadata(i))
		_rebuild())
	sc.add_child(fs_list)
	var sb := HBoxContainer.new()
	sc.add_child(sb)
	sb.add_child(_btn("신앙 스킬 추가", _add_faith_skill))
	sb.add_child(_btn("신앙 스킬 삭제", func():
		var fs := _fskill(fsel)
		if not fs.is_empty():
			faith.skills.erase(fs)
			fsel = ""
			_mark()
			_rebuild()))
	sc.add_child(_small("게임: 그 신을 믿는 대원만 배울 수 있음 · 신앙도(0~%d)가 필요 신앙도 이상이면 포인트 없이 배움 (모자라면 회색 + '신앙 부족') · 출전마다 신앙도 + (기지 설정 faith_battle)" % FaithData.FAITH_MAX))
	return box


func _god(id: String) -> Dictionary:
	for g in faith.gods:
		if g.id == id:
			return g
	return {}


func _fskill(id: String) -> Dictionary:
	for f in faith.skills:
		if f.id == id:
			return f
	return {}


func _god_skills() -> Array:
	var out := (faith.skills as Array).filter(func(f): return f.god == god_sel)
	out.sort_custom(func(a, b): return int(a.need) < int(b.need))
	return out


func _believers(gid: String) -> PackedStringArray:
	var out := PackedStringArray()
	for u in allies:
		var cf: Dictionary = char_faith.get(u.id, {})
		if str(cf.get("god", "")) == gid:
			out.append("%s(시작 %d)" % [u.display_name, int(cf.get("faith", 0))])
	return out


func _fill_faith_lists() -> void:
	god_list.clear()
	for g in faith.gods:
		god_list.add_item("%s  (%s)" % [g.name, g.id])
		god_list.set_item_metadata(god_list.item_count - 1, g.id)
		god_list.set_item_custom_fg_color(god_list.item_count - 1, FaithData.color_of(g))
		if g.id == god_sel:
			god_list.select(god_list.item_count - 1)
	fs_list.clear()
	var g := _god(god_sel)
	fs_head.text = "%s 의 신앙 스킬 (필요 신앙도 순)" % g.get("name", "-") if not g.is_empty() else "신을 고르세요"
	for f in _god_skills():
		fs_list.add_item("신앙 %3d  ·  %s  —  %s" % [int(f.need), f.name, f.desc])
		fs_list.set_item_metadata(fs_list.item_count - 1, f.id)
		if f.id == fsel:
			fs_list.select(fs_list.item_count - 1)


func _refresh_faith_view() -> void:
	info_label.text = "신 %d · 신앙 스킬 %d" % [faith.gods.size(), faith.skills.size()]
	_show_check(FaithData.check(faith, char_faith, actions))


func _new_god_id() -> String:
	var i: int = faith.gods.size() + 1
	while not _god("god_%d" % i).is_empty():
		i += 1
	return "god_%d" % i


func _add_god() -> void:
	var g := FaithData.new_god(_new_god_id())
	faith.gods.append(g)
	god_sel = g.id
	fsel = ""
	_mark()
	_rebuild()


func _delete_god() -> void:
	var g := _god(god_sel)
	if g.is_empty():
		return
	faith.gods.erase(g)
	faith.skills = (faith.skills as Array).filter(func(f): return f.god != g.id)
	god_sel = faith.gods[0].id if not faith.gods.is_empty() else ""
	fsel = ""
	status.text = "'%s' 와 그 신앙 스킬을 지웠습니다 (그 신을 믿던 캐릭터는 엑셀에서 바꿔야 함)" % g.name
	dirty = true
	_rebuild()


func _add_faith_skill() -> void:
	if _god(god_sel).is_empty():
		return
	var list := _god_skills()
	var need := mini(FaithData.FAITH_MAX, int(list.back().need) + 20) if not list.is_empty() else 20
	var base := "%s_%d" % [god_sel, list.size() + 1]
	var id := base
	var i := 2
	while not _fskill(id).is_empty():
		id = "%s_%d" % [base, i]
		i += 1
	var f := FaithData.new_skill(id, god_sel, need)
	f.desc = SkillTreeData.auto_desc(f.effect, int(f.value), actions)
	faith.skills.append(f)
	fsel = id
	_mark()
	_rebuild()


func _build_faith_form() -> void:
	var g := _god(god_sel)
	if g.is_empty():
		form.add_child(_head("신을 고르거나 '신 추가'"))
		return
	form.add_child(_head("신"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	form.add_child(grid)
	var gid := LineEdit.new()
	gid.text = str(g.id)
	gid.placeholder_text = "신 id (영문) — Enter 로 적용"
	var apply_gid := func(v: String):
		v = v.strip_edges()
		if v == "" or v == g.id:
			return
		if not _god(v).is_empty():
			status.text = "신 id '%s' 는 이미 있습니다" % v
			return
		for f in faith.skills:
			if f.god == g.id:
				f.god = v
		g.id = v
		god_sel = v
		status.text = "신 id 바꿈 — 엑셀 캐릭터 시트 '신' 열도 '%s' 로 바꾸세요" % v
		dirty = true
		_rebuild()
	gid.text_submitted.connect(apply_gid)
	_row(grid, "id", gid)
	_row(grid, "이름", _line(str(g.name), func(v):
		g.name = v
		_fill_faith_lists()))
	var cp := ColorPickerButton.new()
	cp.color = FaithData.color_of(g)
	cp.custom_minimum_size = Vector2(120, 28)
	cp.edit_alpha = false
	cp.color_changed.connect(func(c):
		g.color = "#" + c.to_html(false)
		_mark())
	cp.popup_closed.connect(func(): _fill_faith_lists())
	_row(grid, "상징색", cp)
	_row(grid, "설명", _line(str(g.desc), func(v): g.desc = v))
	var bl := _believers(str(g.id))
	_row(grid, "믿는 대원", _small(", ".join(bl) if not bl.is_empty() else "(없음 — 엑셀 캐릭터 시트 '신' 열)"))
	var f := _fskill(fsel)
	form.add_child(HSeparator.new())
	if f.is_empty() or f.god != g.id:
		form.add_child(_head("신앙 스킬을 고르거나 '신앙 스킬 추가'"))
		return
	form.add_child(_head("신앙 스킬"))
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 8)
	g2.add_theme_constant_override("v_separation", 6)
	form.add_child(g2)
	var fid := LineEdit.new()
	fid.text = str(f.id)
	fid.placeholder_text = "고유 id (영문) — Enter 로 적용"
	fid.text_submitted.connect(func(v):
		v = v.strip_edges()
		if v == "" or v == f.id:
			return
		if not _fskill(v).is_empty():
			status.text = "신앙 스킬 id '%s' 는 이미 있습니다" % v
			return
		f.id = v
		fsel = v
		_mark()
		_rebuild())
	_row(g2, "id", fid)
	_row(g2, "이름", _line(str(f.name), func(v):
		f.name = v
		_fill_faith_lists()))
	var need := _spin(0, FaithData.FAITH_MAX, 1, int(f.need), "")
	need.value_changed.connect(func(v):
		if not _rebuilding:
			f.need = int(v)
			_mark())
	need.get_line_edit().focus_exited.connect(func(): _fill_faith_lists())
	_row(g2, "필요 신앙도", need)
	_effect_rows(g2, f)
	form.add_child(_small("효과는 스킬 트리 노드와 같은 형식 — 전투에 나갈 때 복제본에 더해짐. ※ id 를 바꾸면 이미 배운 저장 파일에서는 배운 것이 풀립니다."))


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
	_effect_rows(grid, n)
	form.add_child(_small("설명이 자동 문장 그대로면 효과·값을 바꿀 때 같이 바뀝니다."))
	if str(n.effect).begins_with("skill:"):
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


## 효과 · 스킬 · 값 · 설명 줄 + '설명 자동 채우기' (스킬 트리 노드·신앙 스킬 공용 — 둘 다 effect/value/desc)
func _effect_rows(grid: GridContainer, n: Dictionary) -> void:
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
	grid.add_child(Control.new())
	grid.add_child(_btn("설명 자동 채우기", func():
		n.desc = SkillTreeData.auto_desc(str(n.effect), int(n.value), actions)
		_mark()
		_rebuild()))


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
