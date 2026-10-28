@tool
extends Control
## 스킬 트리 에디터 (Godot 에디터 상단 "스킬 트리" 탭, addons/rtz_skill_editor) → data/skill_tree.json + data/faith.json.
## 위: 캐릭터 · 액티브/패시브/신앙 고르기 · 다른 캐릭터 트리 가져오기(모양째) · 필요 레벨 자동 · 모양 틀(십자형·두 갈래·일자·나무·그물).
## 신앙: 왼쪽 신 목록(추가·삭제) · 가운데 그 신의 신앙 스킬(필요 신앙도 순) · 오른쪽 신·스킬 고치기 + 대원별 믿는 신·시작 신앙도 (data/faith.json believers).
## 상태 이상: 왼쪽 스킬 목록(누가 쓰는지·달린 상태 이상) · 오른쪽 그 스킬에 상태 이상 달기(여러 개, 턴·수치·확률) → data/skill_status.json.
## 기적: 신 해금 캐릭터 고르기(정체인 신 · 처음부터 해금 / 해금 조건 · 시작 의지) + 그 캐릭터만의 기적(필요 의지) → data/faith.json divine · miracles.
## 상태 정의: 상태 이상 이름·머리 위 글자·색 + 쓰는 효과(규칙) → data/statuses.json. 같은 효과를 이름만 다르게 여러 개 (예: 진통제·자가 치유 = 재생).
## 가운데: 격자 위 자유 모양 (캐릭터마다 다르게) — 빈 칸 클릭 = 새 노드(고른 노드에서 이어짐), 끌기 = 옮기기, Shift+클릭 = 선행 잇기/끊기, Delete = 삭제.
## 오른쪽: 고른 노드의 id · 이름 · 갈래 색 · 시작 노드 · 필요 레벨 · 선행(하나라도/모두) · 택일 그룹 · 효과 · 값 · 설명, 옮기기 · 삭제, 아래 검사.
## 게임 규칙(BaseSim): 시작 노드는 처음부터 습득, 선행을 배워야 다음, 같은 택일 그룹은 트리마다 하나만, 스킬 포인트는 두 트리 공용.

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
var char_faith: Dictionary = {}      # 캐릭터 id → {god, faith} (= faith.believers, 이 화면에서 고침)
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
## 기적 · 신 해금 (kind == "miracle") — faith.divine · faith.miracles
var mchar := ""                      # 고른 캐릭터
var mir_sel := ""                    # 고른 기적 id
var miracle_box: Control
var mchar_list: ItemList
var mir_list: ItemList
var mir_head: Label
var missions: Array = []             # [[target, 표시]] 의뢰 · 전투 스테이지 · 연구 (조건 '미션 완료')
var mission_names: Dictionary = {}
## 상태 정의 (kind == "statusdef")
var sdefs: Array = []                # data/statuses.json [{id, name, effect, short, color, desc}]
var sdef_sel := ""
var sdef_box: Control
var sdef_list: ItemList
var sdef_new_eff: OptionButton
## 몬스터 스킬 (kind == "monster")
var mdata: Dictionary = {"skills": [], "kits": {}}
var sheet_skill_ids: Array = []      # 엑셀 스킬 시트 스킬 (공용, 여기서는 읽기만)
var first_stage := ""
var mon_sel := ""
var mskill_sel := ""
var monster_box: Control
var mon_list: ItemList
var kit_list: ItemList
var kit_add: OptionButton

var char_opt: OptionButton
var kind_btns: Dictionary = {}
var copy_opt: OptionButton
var tpl_opt: OptionButton
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
	for k in SkillTreeData.KINDS + ["faith", "miracle", "status", "statusdef", "monster"]:
		var b := Button.new()
		b.text = "%s 트리" % SkillTreeData.KIND_NAME[k] if k in SkillTreeData.KINDS else {"faith": "신앙 스킬", "miracle": "기적 (신 해금)", "status": "상태 이상", "statusdef": "상태 정의", "monster": "몬스터 스킬"}[k]
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
	auto.tooltip_text = "이 트리의 필요 레벨을 캐릭터 시작 레벨 + 2 × (단계 - 1) 로 — 단계 = 시작 노드에서 선을 따라 몇 번째인지 (시작 노드 = 시작 레벨)"
	var clr := _btn("트리 비우기", _clear_tree)
	var sep3 := VSeparator.new()
	var tl := _lab("모양 틀")
	tpl_opt = OptionButton.new()
	for t in SkillTreeData.TEMPLATE_ORDER:
		tpl_opt.add_item(SkillTreeData.TEMPLATES[t].name)
		tpl_opt.set_item_metadata(tpl_opt.item_count - 1, t)
	var tb := _btn("틀로 새로 짜기", func(): _apply_template(str(tpl_opt.get_item_metadata(maxi(0, tpl_opt.selected)))))
	tb.tooltip_text = "지금 트리를 지우고 고른 모양의 빈 노드로 새로 짬 (이름·효과는 '새 스킬' — 하나씩 고쳐 쓰기). 되돌리기 = 저장 전 '되돌리기'"
	for c in [sep1, cl2, copy_opt, cp, sep2, auto, clr, sep3, tl, tpl_opt, tb]:
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
		if id != sel:
			sel = id
			_rebuild())
	canvas.cell_clicked.connect(_add_node)
	canvas.node_moved.connect(_move_node)
	canvas.link_toggled.connect(_toggle_link)
	canvas.delete_pressed.connect(_delete)
	holder.add_child(canvas)
	faith_box = _build_faith_box()
	faith_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	faith_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(faith_box)
	status_box = _build_status_box()
	status_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(status_box)
	miracle_box = _build_miracle_box()
	miracle_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	miracle_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(miracle_box)
	sdef_box = _build_sdef_box()
	sdef_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sdef_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(sdef_box)
	monster_box = _build_monster_box()
	monster_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monster_box.custom_minimum_size = Vector2(560, 420)
	holder.add_child(monster_box)
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
		first_stage = gd.stage_order[0] if not gd.stage_order.is_empty() else ""
		var mids: Array = (MonsterSkillData.read().skills as Array).map(func(x): return x.id)
		sheet_skill_ids = actions.keys().filter(func(k): return not mids.has(k))
		var od := OutgameData.load_from()
		missions = UnlockCond.missions(od, gd)
		mission_names = UnlockCond.mission_names(od, gd)
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
		StatusCatalog.refresh(sdefs)   # GameData 가 파일로 다시 읽었으므로 저장 안 한 상태 정의를 다시 씌움
		_rebuild()
	else:
		_load()


func _load() -> void:
	nodes = SkillTreeData.read()
	faith = FaithData.read()
	if not faith.has_believers:   # 옛 파일: 엑셀 캐릭터 시트 '신'·'신앙' 열 값으로 시작
		faith.believers = char_faith.duplicate(true)
	for u in allies:
		if not faith.believers.has(u.id):
			faith.believers[u.id] = {"god": "", "faith": 0}
	char_faith = faith.believers
	sstat = SkillStatusData.read()
	sdefs = StatusCatalog.read()
	StatusCatalog.refresh(sdefs)
	if _sdef(sdef_sel).is_empty():
		sdef_sel = sdefs[0].id if not sdefs.is_empty() else ""
	mdata = MonsterSkillData.read()
	if not monsters.has(mon_sel) and not monsters.is_empty():
		mon_sel = str(monsters.keys()[0])
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
	err3 = maxi(err3, MonsterSkillData.write(mdata))
	err3 = maxi(err3, StatusCatalog.write(sdefs))
	if err == OK and err2 == OK and err3 == OK:
		dirty = false
		var errs: int = SkillTreeData.check(nodes, allies, actions).errors.size() + FaithData.check(faith, char_faith, actions).errors.size() \
			+ SkillStatusData.check(sstat, actions).errors.size() + MonsterSkillData.check(mdata, sheet_skill_ids, monsters).errors.size() \
			+ StatusCatalog.check(sdefs).errors.size()
		status.text = "저장됨: data/skill_tree.json · faith.json · skill_status.json · statuses.json · monster_skills.json" + ("" if errs == 0 else "  (검사 오류 %d개 — 아래 확인)" % errs)
		if Engine.is_editor_hint():
			for path in [SkillTreeData.PATH, FaithData.PATH, SkillStatusData.PATH, MonsterSkillData.PATH, StatusCatalog.PATH]:
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
	if kind == "monster":   # 첫 스테이지 전투 (괴물이 새 스킬을 쓰는지)
		f.store_string(JSON.stringify({"stage": first_stage}))
		f.close()
		if Engine.is_editor_hint():
			EditorInterface.play_custom_scene("res://scenes/battle_2d.tscn")
		return
	if kind in ["status", "statusdef"]:
		var try_id := skill_sel
		if kind == "statusdef":   # 그 상태가 달린 첫 스킬
			var users := sstat.filter(func(e): return e.status == sdef_sel)
			try_id = str(users[0].skill) if not users.is_empty() else skill_sel
		f.store_string(JSON.stringify({"try_skill": try_id}))
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
	if kind == "miracle":   # 그 캐릭터 정체 해금 + 의지 100 → 기적 탭
		f.store_string(JSON.stringify({"base": true, "skills": {"char": mchar, "kind": "faith", "level": int(play_level.value), "divine": true, "will": 100}}))
		f.close()
		if Engine.is_editor_hint():
			EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn")
		return
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


func _cell(x: int, y: int) -> Dictionary:
	for n in _tree():
		if int(n.x) == x and int(n.y) == y:
			return n
	return {}


func _start_level() -> int:
	var u := _unit(cid)
	return u.level if u != null else 1


## 겹치지 않는 새 id: <캐릭터>_<a|p>_<번호>
func _new_id() -> String:
	var base := "%s_%s_" % [cid.trim_prefix("a_"), "a" if kind == "active" else "p"]
	var i := 1
	while not _node(base + str(i)).is_empty():
		i += 1
	return base + str(i)


## 빈 칸에 새 노드. 고른 노드(같은 트리)가 있으면 그 노드에서 이어짐 (선행 · 같은 갈래 색 · 필요 레벨 +2), 트리가 비었으면 시작 노드
func _add_node(x: int, y: int) -> void:
	if not _cell(x, y).is_empty():
		return
	var n := SkillTreeData.new_node(cid, kind, x, y)
	n.id = _new_id()
	var parent := _node(sel)
	if parent.is_empty() or parent.char != cid or parent.kind != kind:
		parent = {}
	if _tree().is_empty():
		n.start = true
		n.branch = "core"
		n.level = _start_level()
	elif not parent.is_empty():
		n.req = [parent.id]
		n.branch = parent.branch if parent.branch != "core" else _branch_toward(x - int(parent.x), y - int(parent.y))
		n.level = int(parent.level) + 2
	else:
		n.level = _start_level()
	n.desc = SkillTreeData.auto_desc(n.effect, int(n.value), actions)
	nodes.append(n)
	sel = n.id
	_mark()
	_rebuild()


## 중앙에서 뻗을 때 방향으로 갈래 색 (위 화력 · 오른쪽 기동 · 아래 생존 · 왼쪽 전술)
func _branch_toward(dx: int, dy: int) -> String:
	if absi(dy) >= absi(dx):
		return "fire" if dy < 0 else "guard"
	return "move" if dx > 0 else "tactic"


func _delete(id: String) -> void:
	var n := _node(id)
	if n.is_empty():
		return
	nodes.erase(n)
	for o in nodes:   # 이 노드를 선행으로 쓰던 노드는 그 선행을 이어받음 (사슬이 끊기지 않게)
		if (o.req as Array).has(id):
			o.req.erase(id)
			for q in n.req:
				if not o.req.has(q) and q != o.id:
					o.req.append(q)
	sel = ""
	_mark()
	_rebuild()


func _move_node(id: String, x: int, y: int) -> void:
	var n := _node(id)
	if n.is_empty() or not _cell(x, y).is_empty():
		return
	n.x = clampi(x, -SkillTreeData.GRID, SkillTreeData.GRID)
	n.y = clampi(y, -SkillTreeData.GRID, SkillTreeData.GRID)
	sel = id
	_mark()
	_rebuild()


## from → to 선행 잇기/끊기 (to 가 from 을 먼저 배워야). 고리가 생기면 안 이음
func _toggle_link(from: String, to: String) -> void:
	var t := _node(to)
	if t.is_empty() or from == to:
		return
	if (t.req as Array).has(from):
		t.req.erase(from)
		status.text = "선 끊음: %s → %s" % [_node(from).get("name", from), t.name]
	else:
		t.req.append(from)
		if not SkillTreeData.cycles(_tree()).is_empty():
			t.req.erase(from)
			status.text = "잇지 않음 — 선행이 돌고 돌게 됩니다"
			return
		status.text = "선 이음: %s → %s" % [_node(from).get("name", from), t.name]
	dirty = true
	_refresh_view()
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
	var remap := {}
	var copies := []
	for n in nodes.filter(func(x): return x.char == src and x.kind == kind):
		var c: Dictionary = n.duplicate(true)
		c.char = cid
		c.id = _new_id_from(str(n.id), src)
		remap[n.id] = c.id
		c.level = maxi(1, int(c.level) + dl)
		nodes.append(c)
		copies.append(c)
	for c in copies:
		c.req = (c.req as Array).map(func(q): return remap.get(q, q))
	sel = ""
	status.text = "%s 의 %s 트리 모양·노드를 가져왔습니다 (필요 레벨은 시작 레벨 차이 %+d 만큼)" % [su.display_name if su != null else src, SkillTreeData.KIND_NAME[kind], dl]
	dirty = true
	_rebuild()


## 다른 캐릭터 노드 id → 이 캐릭터 id (dan_a_n1 → kira_a_n1, 겹치면 번호)
func _new_id_from(old: String, src: String) -> String:
	var base := old.replace(src.trim_prefix("a_") + "_", cid.trim_prefix("a_") + "_")
	if base == old:
		return _new_id()
	var id := base
	var i := 2
	while not _node(id).is_empty():
		id = "%s_%d" % [base, i]
		i += 1
	return id


func _auto_levels() -> void:
	var lv := _start_level()
	var dep := SkillTreeData.depths(_tree())
	for n in _tree():
		var d := int(dep.get(n.id, 1))
		n.level = lv if d == 0 else lv + 2 * (d - 1)
	_mark()
	_rebuild()


func _clear_tree() -> void:
	for n in _tree():
		nodes.erase(n)
	sel = ""
	_mark()
	_rebuild()


## 모양 틀로 새로 짜기 (지금 트리는 지움, 필요 레벨은 단계대로)
func _apply_template(t: String) -> void:
	var cells: Array = SkillTreeData.TEMPLATES.get(t, {}).get("cells", [])
	if cells.is_empty():
		return
	for n in _tree():
		nodes.erase(n)
	var ids := []
	for c in cells:
		var n := SkillTreeData.new_node(cid, kind, int(c.x), int(c.y))
		n.id = _new_id()
		n.branch = str(c.get("branch", "core"))
		n.start = bool(c.get("start", false))
		n.group = str(c.get("group", ""))
		n.req_all = bool(c.get("all", false))
		n.req = (c.get("req", []) as Array).map(func(i): return ids[int(i)])
		n.name = "시작" if n.start else "새 스킬"
		n.desc = SkillTreeData.auto_desc(n.effect, int(n.value), actions)
		nodes.append(n)
		ids.append(n.id)
	sel = ids[0]
	_auto_levels()
	status.text = "'%s' 틀로 새로 짰습니다 — 노드를 눌러 이름·효과를 고치세요 (저장 전 '되돌리기' 로 취소)" % SkillTreeData.TEMPLATES[t].name


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
	var is_m := kind == "monster"
	var is_d := kind == "statusdef"
	var is_mi := kind == "miracle"
	var tree_mode := not is_f and not is_s and not is_m and not is_d and not is_mi
	canvas.visible = tree_mode
	faith_box.visible = is_f
	status_box.visible = is_s
	sdef_box.visible = is_d
	miracle_box.visible = is_mi
	monster_box.visible = is_m
	for c in tree_only:
		c.visible = tree_mode
	play_level.visible = not is_s and not is_m and not is_d
	level_lab.visible = play_level.visible
	play_btn.text = "전투 테스트 플레이 (이 스킬 쥐여 주기)" if is_s else ("전투 테스트 플레이 (첫 스테이지)" if is_m else ("전투 테스트 플레이 (이 상태가 달린 스킬)" if is_d else ("기지 기적 탭 테스트 플레이 (정체 해금 · 의지 100)" if is_mi else "기지 스킬 창 테스트 플레이")))
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	if is_f:
		_fill_faith_lists()
		_build_faith_form()
	elif is_s:
		_fill_skill_list()
		_fill_status_ref()
		_build_status_form()
	elif is_m:
		_fill_monster_lists()
		_build_monster_form()
	elif is_d:
		_fill_sdef_list()
		_build_sdef_form()
	elif is_mi:
		_fill_miracle_lists()
		_build_miracle_form()
	else:
		_build_form()
	_rebuilding = false
	_refresh_view()


func _refresh_view() -> void:
	if kind == "faith":
		_refresh_faith_view()
		return
	if kind == "monster":
		info_label.text = "몬스터 %d · 몬스터 전용 스킬 %d" % [monsters.size(), mdata.skills.size()]
		_show_check(MonsterSkillData.check(mdata, sheet_skill_ids, monsters, _ai_uses()))
		return
	if kind == "status":
		info_label.text = "상태 이상 %d개 · 달린 스킬 %d개" % [sstat.size(), SkillStatusData.by_skill(sstat).size()]
		_show_check(SkillStatusData.check(sstat, actions))
		return
	if kind == "miracle":
		info_label.text = "신 해금 캐릭터 %d · 기적 %d" % [faith.divine.size(), faith.miracles.size()]
		_show_check(FaithData.check(faith, char_faith, actions))
		return
	if kind == "statusdef":
		var effs := {}
		for d in sdefs:
			effs[d.effect] = true
		info_label.text = "상태 %d개 · 쓰는 효과 %d / %d가지" % [sdefs.size(), effs.size(), StatusCatalog.EFFECTS.size()]
		_show_check(StatusCatalog.check(sdefs, _sdef_use_counts()))
		return
	canvas.show_tree(_tree(), sel)
	var u := _unit(cid)
	var t := _tree()
	var groups := {}
	for n in t:
		if str(n.group) != "":
			groups[n.group] = true
	var b := SkillTreeData.bounds(t)
	info_label.text = "노드 %d개 · 시작 노드 %d · 택일 그룹 %d · 크기 %d×%d칸 · 시작 Lv%d" % [t.size(), t.filter(func(n): return bool(n.start)).size(), groups.size(), b.size.x, b.size.y, u.level if u != null else 1]
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
	rc.add_child(_head("상태 이상 (이름 → 효과)"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rc.add_child(sc)
	var ref := VBoxContainer.new()
	ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(ref)
	status_ref = ref
	return box


## 오른쪽 참고 목록: 상태마다 '이름 (효과) — 설명' (상태 정의를 고치면 다시)
var status_ref: VBoxContainer
func _fill_status_ref() -> void:
	for c in status_ref.get_children():
		c.queue_free()
	for sid in StatusCatalog.battle_ids():
		var d := StatusCatalog.get_def(sid)
		var l := Label.new()
		var en: String = StatusCatalog.EFFECTS.get(d.effect, {}).get("name", d.effect)
		l.text = "%s%s — %s" % [d.name, "" if en == d.name else " (%s)" % en, str(d.desc).replace("{t}", "n").replace("{v}", "v")]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 280
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", StatusCatalog.color_of(sid).lightened(0.2))
		status_ref.add_child(l)
	status_ref.add_child(_small("\n적용: 처음 걸릴 때 한 번 + 그 캐릭터 차례마다 행동보다 먼저. n턴 = 그 캐릭터 차례 n번 (차례가 끝날 때 1 감소, 동상은 차례 시작에 감소 → 0 이면 터짐). 다시 걸리면 남은 턴·수치 중 큰 쪽. 넉백·끌어당김은 맞는 순간 한 번(턴 없음).\n이름·글자·색·새 상태는 '상태 정의'."))


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
	_status_cards(a.id, a.effect)
	form.add_child(_small("테스트 플레이 = 이 스킬을 아군 모두의 첫 스킬 칸에 넣고 첫 스테이지 전투."))


## 그 스킬에 달린 상태 이상 카드들 + '상태 이상 추가' (상태 이상 · 몬스터 스킬 화면 공용)
func _status_cards(skill_id: String, effect: String) -> void:
	var mine := _skill_statuses(skill_id)
	form.add_child(_head("맞은 대상에게 거는 상태 이상 (%d)" % mine.size()))
	if mine.is_empty():
		form.add_child(_small("없음 — 아래 '상태 이상 추가'"))
	var items := []
	for sid in StatusCatalog.battle_ids():
		var d := StatusCatalog.get_def(sid)
		var en: String = StatusCatalog.EFFECTS.get(d.effect, {}).get("name", d.effect)
		items.append([sid, d.name if en == d.name else "%s (%s)" % [d.name, en]])
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
			var same := StatusCatalog.effect_of(str(v)) == StatusCatalog.effect_of(e.status)
			e.status = str(v)
			if StatusCatalog.hint(e.status) == "":
				e.value = 0
			elif not same or int(e.value) <= 0:
				e.value = StatusCatalog.default_value(e.status)   # 효과가 바뀌면 그 효과의 기본 수치
			_mark()
			_rebuild()))
		var tu := _spin(1, 20, 1, int(e.turns), "")
		tu.value_changed.connect(func(v):
			if not _rebuilding:
				e.turns = int(v)
				_mark()
				_fill_skill_list())
		if not StatusCatalog.is_instant(e.status):   # 넉백·끌어당김은 맞는 순간 한 번 (턴 없음)
			_row(grid, "턴 (차례 수)" if StatusCatalog.effect_of(e.status) != "frost" else "턴 (터지기까지)", tu)
		else:
			tu.queue_free()
		var hint := StatusCatalog.hint(e.status)
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
		for sid in StatusCatalog.battle_ids():
			if not used.has(sid):
				pick = sid
				break
		sstat.append(SkillStatusData.new_entry(skill_id, pick))
		_mark()
		_rebuild())
	form.add_child(add)
	if effect in ["heal", "ap_grant"]:
		form.add_child(_small("아군 대상 스킬이라 상태 이상도 아군에게 걸립니다 (가속 같은 긍정 상태에 쓰세요)."))


# ================================================================ 기적 · 신 해금 캐릭터
func _build_miracle_box() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var lc := VBoxContainer.new()
	lc.custom_minimum_size.x = 280
	box.add_child(lc)
	lc.add_child(_head("대원 (✦ = 신 해금 캐릭터)"))
	mchar_list = ItemList.new()
	mchar_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mchar_list.item_selected.connect(func(i):
		mchar = str(mchar_list.get_item_metadata(i))
		mir_sel = ""
		_rebuild())
	lc.add_child(mchar_list)
	lc.add_child(_small("대원을 골라 오른쪽에서 '정체가 신' 을 켜면 신 해금 캐릭터. 해금되면 게임 스킬 창의 신앙 탭이 '기적' 으로 바뀌고, 기적은 신앙이 아니라 의지로 배움."))
	var mc := VBoxContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(mc)
	mir_head = _head("")
	mc.add_child(mir_head)
	mir_list = ItemList.new()
	mir_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mir_list.item_selected.connect(func(i):
		mir_sel = str(mir_list.get_item_metadata(i))
		_rebuild())
	mc.add_child(mir_list)
	var bb := HBoxContainer.new()
	mc.add_child(bb)
	bb.add_child(_btn("기적 추가", _add_miracle))
	bb.add_child(_btn("기적 삭제", func():
		var m := _miracle(mir_sel)
		if not m.is_empty():
			faith.miracles.erase(m)
			mir_sel = ""
			_mark()
			_rebuild()))
	mc.add_child(_small("게임: 정체가 드러난 뒤에만 · 의지(해금될 때 시작 의지, 출전마다 + 기지 설정 will_battle)가 필요 의지 이상이면 포인트 없이 배움 (모자라면 회색 + '의지 부족'). 전에 배운 신앙 스킬 효과는 그대로."))
	return box


func _divine(cid: String) -> Dictionary:
	return faith.divine.get(cid, {})


func _miracle(id: String) -> Dictionary:
	for m in faith.miracles:
		if m.id == id:
			return m
	return {}


func _char_miracles() -> Array:
	var out := (faith.miracles as Array).filter(func(m): return m.char == mchar)
	out.sort_custom(func(a, b): return int(a.need) < int(b.need))
	return out


## 새 게임을 시작하면 잠김인지 해금인지 (편집 중 확인용)
func _divine_start_text(cid: String, dv: Dictionary) -> String:
	var c: Dictionary = dv.condition
	if bool(dv.unlocked) or c.type == "always":
		return "새 게임: 처음부터 해금 (신앙 탭 = 기적)"
	var u := _unit(cid)
	var v := int(c.value)
	match str(c.type):
		"level":
			var lv := u.level if u != null else 1
			return "새 게임: 잠김 → 레벨 %d 이 되면 해금 (시작 Lv%d)%s" % [v, lv, " — 이미 충족, 첫날 해금" if lv >= v else ""]
		"faith":
			var f0 := int(char_faith.get(cid, {}).get("faith", 0))
			return "새 게임: 잠김 → 신앙도 %d 이 되면 해금 (시작 %d, 출전마다 +)%s" % [v, f0, " — 이미 충족, 첫날 해금" if f0 >= v else ""]
		"affinity":
			return "새 게임: 잠김 → 친밀도 %d 이 되면 해금 (대화·요청·선물로 오름)" % v
		"day":
			return "새 게임: 잠김 → %d일차가 되면 해금%s" % [v, " — 첫날 해금" if v <= 1 else ""]
		"quest":
			return "새 게임: 잠김 → %s 하면 해금" % UnlockCond.describe(c, mission_names).trim_prefix("미션 완료: ") + " (미션 완료)"
	return "새 게임: 잠김 → 이벤트·대사에서 직접 해금 (BaseSim.unlock_divine)"


func _fill_miracle_lists() -> void:
	if _unit(mchar) == null and not allies.is_empty():
		mchar = allies[0].id
	mchar_list.clear()
	for u in allies:
		var dv := _divine(u.id)
		var t: String = u.display_name
		if not dv.is_empty():
			var gname: String = _god(str(dv.god)).get("name", str(dv.god))
			t = "✦ %s — %s · %s" % [u.display_name, gname, "처음부터 해금" if bool(dv.unlocked) or dv.condition.type == "always" else "잠김: " + UnlockCond.describe(dv.condition, mission_names)]
		mchar_list.add_item(t)
		mchar_list.set_item_metadata(mchar_list.item_count - 1, u.id)
		if not dv.is_empty():
			mchar_list.set_item_custom_fg_color(mchar_list.item_count - 1, FaithData.color_of(_god(str(dv.god))).lightened(0.2))
		if u.id == mchar:
			mchar_list.select(mchar_list.item_count - 1)
	mir_list.clear()
	var u0 := _unit(mchar)
	mir_head.text = "%s 의 기적 (필요 의지 순)" % (u0.display_name if u0 != null else "-")
	for m in _char_miracles():
		mir_list.add_item("의지 %3d  ·  %s  —  %s" % [int(m.need), m.name, m.desc])
		mir_list.set_item_metadata(mir_list.item_count - 1, m.id)
		if m.id == mir_sel:
			mir_list.select(mir_list.item_count - 1)


func _add_miracle() -> void:
	if _divine(mchar).is_empty():
		status.text = "먼저 오른쪽에서 '정체가 신' 을 켜세요"
		return
	var list := _char_miracles()
	var dv := _divine(mchar)
	var start := maxi(10, int(dv.get("will", 0)))
	var need := mini(FaithData.FAITH_MAX, int(list.back().need) + 15) if not list.is_empty() else start
	var base := "%s_m%d" % [mchar.trim_prefix("a_"), list.size() + 1]
	var id := base
	var i := 2
	while not _miracle(id).is_empty() or not _fskill(id).is_empty():
		id = "%s_%d" % [base, i]
		i += 1
	var m := FaithData.new_miracle(id, mchar, need)
	m.desc = SkillTreeData.auto_desc(m.effect, int(m.value), actions)
	faith.miracles.append(m)
	mir_sel = id
	_mark()
	_rebuild()


func _build_miracle_form() -> void:
	var u := _unit(mchar)
	if u == null:
		form.add_child(_head("대원을 고르세요"))
		return
	form.add_child(_head("%s — 신 해금" % u.display_name))
	var dv := _divine(mchar)
	var on := CheckBox.new()
	on.text = "이 캐릭터는 정체가 신 (해금되면 신앙 탭 → 기적)"
	on.button_pressed = not dv.is_empty()
	on.toggled.connect(func(v):
		if _rebuilding:
			return
		if v:
			var g0: String = str(char_faith.get(mchar, {}).get("god", ""))
			faith.divine[mchar] = FaithData.new_divine(g0 if g0 != "" else (faith.gods[0].id if not faith.gods.is_empty() else ""))
		else:
			faith.divine.erase(mchar)
			var mine := _char_miracles()
			for m in mine:
				faith.miracles.erase(m)
			if not mine.is_empty():
				status.text = "신 해금을 끄면서 기적 %d개도 지웠습니다 (저장 안 함)" % mine.size()
		_mark()
		_rebuild())
	form.add_child(on)
	if dv.is_empty():
		form.add_child(_small("켜면: 정체인 신 · 처음부터 해금인지 · 해금 조건 · 그 캐릭터만의 기적을 정합니다."))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	form.add_child(grid)
	var gods := []
	for g in faith.gods:
		gods.append([g.id, "%s (%s)" % [g.name, g.id]])
	_row(grid, "정체인 신", _option(gods, dv.god, func(v):
		dv.god = str(v)
		_mark()
		_rebuild()))
	var unl := CheckBox.new()
	unl.text = "이미 해금됨 (처음부터 신)"
	unl.button_pressed = bool(dv.unlocked)
	unl.toggled.connect(func(v):
		if not _rebuilding:
			dv.unlocked = v
			_mark()
			_rebuild())
	_row(grid, "해금 상태", unl)
	if not bool(dv.unlocked):
		var ct := []
		for t in UnlockCond.ORDER:
			if t != "always":
				ct.append([t, UnlockCond.TYPES[t]])
		_row(grid, "해금 조건", _option(ct, dv.condition.type, func(v):
			dv.condition = UnlockCond.norm({"type": str(v), "value": dv.condition.value, "target": dv.condition.get("target", "")})
			if dv.condition.type == "quest" and dv.condition.target == "" and not missions.is_empty():
				dv.condition.target = str(missions[0][0])
			_mark()
			_rebuild()))
		if dv.condition.type == "quest":   # 어느 미션을 끝내면 해금
			_row(grid, "미션", _option(missions, dv.condition.get("target", ""), func(v):
				dv.condition.target = str(v)
				_mark()
				_rebuild()))
		if UnlockCond.uses_value(dv.condition.type):
			var r: Array = UnlockCond.RANGE[dv.condition.type]
			var sp := _spin(r[0], r[1], 1, int(dv.condition.value), "")
			sp.value_changed.connect(func(v):
				if not _rebuilding:
					dv.condition.value = int(v)
					_mark()
					_fill_miracle_lists())
			_row(grid, "값 (%s)" % UnlockCond.describe(dv.condition), sp)
	var wsp := _spin(0, FaithData.FAITH_MAX, 1, int(dv.get("will", 0)), "")
	wsp.tooltip_text = "정체가 드러날 때의 의지 (기적을 배우는 데 씀, 그 뒤 출전마다 + 기지 설정 will_battle)"
	wsp.value_changed.connect(func(v):
		if not _rebuilding:
			dv.will = int(v)
			_mark())
	_row(grid, "시작 의지", wsp)
	var stl := _small(_divine_start_text(mchar, dv))
	stl.add_theme_color_override("font_color", Color(1, 0.9, 0.5) if bool(dv.unlocked) or dv.condition.type == "always" else Color(0.7, 0.85, 1.0))
	form.add_child(stl)
	form.add_child(_small("게임에서 확인: BaseSim.divine_state(캐릭터) = 잠김 / 해금 · 조건은 미션(의뢰·전투·연구·퀘스트 — 퀘스트는 '퀘스트' 탭)을 끝낼 때, 레벨·신앙도·친밀도가 바뀔 때, 날이 바뀔 때 검사. 지금 믿는 신(신앙 스킬 화면): %s" % _god(str(char_faith.get(mchar, {}).get("god", ""))).get("name", "무신앙")))
	var m := _miracle(mir_sel)
	form.add_child(HSeparator.new())
	if m.is_empty() or m.char != mchar:
		form.add_child(_head("기적을 고르거나 '기적 추가'"))
		return
	form.add_child(_head("기적"))
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 8)
	g2.add_theme_constant_override("v_separation", 6)
	form.add_child(g2)
	var mid := LineEdit.new()
	mid.text = str(m.id)
	mid.placeholder_text = "고유 id (영문) — Enter 로 적용"
	mid.text_submitted.connect(func(v):
		v = v.strip_edges()
		if v == "" or v == m.id:
			return
		if not _miracle(v).is_empty() or not _fskill(v).is_empty():
			status.text = "id '%s' 는 이미 있습니다" % v
			return
		m.id = v
		mir_sel = v
		_mark()
		_rebuild())
	_row(g2, "id", mid)
	_row(g2, "이름", _line(str(m.name), func(v):
		m.name = v
		_fill_miracle_lists()))
	var need := _spin(0, FaithData.FAITH_MAX, 1, int(m.need), "")
	need.value_changed.connect(func(v):
		if not _rebuilding:
			m.need = int(v)
			_mark())
	need.get_line_edit().focus_exited.connect(func(): _fill_miracle_lists())
	_row(g2, "필요 의지", need)
	_effect_rows(g2, m)


# ================================================================ 상태 정의 (이름 · 글자 · 색 → 효과)
func _build_sdef_box() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var lc := VBoxContainer.new()
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(lc)
	lc.add_child(_head("상태 (이름 → 효과)"))
	sdef_list = ItemList.new()
	sdef_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sdef_list.item_selected.connect(func(i):
		sdef_sel = str(sdef_list.get_item_metadata(i))
		_rebuild())
	lc.add_child(sdef_list)
	var add := HBoxContainer.new()
	lc.add_child(add)
	add.add_child(_lab("새 상태 — 효과"))
	sdef_new_eff = OptionButton.new()
	for eff in StatusCatalog.EFFECT_ORDER:
		sdef_new_eff.add_item(StatusCatalog.EFFECTS[eff].name)
		sdef_new_eff.set_item_metadata(sdef_new_eff.item_count - 1, eff)
	add.add_child(sdef_new_eff)
	add.add_child(_btn("+ 추가", _add_sdef))
	add.add_child(_btn("삭제", _delete_sdef))
	lc.add_child(_small("같은 효과를 이름만 다르게 여러 개 만들 수 있습니다 — id 는 효과 id, 두 번째부터 _2, _3 (예: regen 재생 · regen_2 진통제 · regen_3 자가 치유). 같은 id 는 겹치지 않고(다시 걸리면 갱신), id 가 다르면 따로 걸립니다. 스킬에는 상태를 답니다 ('상태 이상' 화면)."))
	# 효과 설명 (참고)
	var rc := VBoxContainer.new()
	rc.custom_minimum_size.x = 300
	box.add_child(rc)
	rc.add_child(_head("효과 (규칙)"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rc.add_child(sc)
	var ref := VBoxContainer.new()
	ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(ref)
	for eff in StatusCatalog.EFFECT_ORDER:
		var e: Dictionary = StatusCatalog.EFFECTS[eff]
		var l := Label.new()
		l.text = "%s (%s)%s — %s" % [e.name, eff, "" if str(e.hint) == "" else " · 수치 = " + str(e.hint), str(e.desc).replace("{t}", "n").replace("{v}", "v")]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 280
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", (e.color as Color).lightened(0.2))
		ref.add_child(l)
	return box


func _sdef(id: String) -> Dictionary:
	for d in sdefs:
		if d.id == id:
			return d
	return {}


## 상태 id → 그 상태가 달린 스킬 수
func _sdef_use_counts() -> Dictionary:
	var out := {}
	for d in sdefs:
		out[d.id] = 0
	for e in sstat:
		out[e.status] = int(out.get(e.status, 0)) + 1
	return out


func _fill_sdef_list() -> void:
	sdef_list.clear()
	var uses := _sdef_use_counts()
	for d in sdefs:
		var en: String = StatusCatalog.EFFECTS.get(d.effect, {}).get("name", d.effect)
		sdef_list.add_item("[%s] %s (%s)  → %s   · 스킬 %d" % [d.short, d.name, d.id, en, int(uses.get(d.id, 0))])
		sdef_list.set_item_metadata(sdef_list.item_count - 1, d.id)
		sdef_list.set_item_custom_fg_color(sdef_list.item_count - 1, StatusCatalog.color_of(d.id).lightened(0.25))
		if d.id == sdef_sel:
			sdef_list.select(sdef_list.item_count - 1)


## 편집 중인 정의를 바로 게임 쪽 조회(StatusCatalog)에도 (저장 전 미리보기)
func _sdef_changed() -> void:
	StatusCatalog.refresh(sdefs)
	_mark()
	_fill_sdef_list()


func _add_sdef() -> void:
	var eff := str(sdef_new_eff.get_item_metadata(sdef_new_eff.selected))
	var id := StatusCatalog.next_id(eff, sdefs)   # 효과 id → regen_2, regen_3 …
	var d := StatusCatalog.new_status(id, eff)
	if id != eff:
		d.name = "%s %s" % [d.name, id.trim_prefix(eff + "_")]
	sdefs.append(d)
	sdef_sel = id
	StatusCatalog.refresh(sdefs)
	_mark()
	_rebuild()


func _delete_sdef() -> void:
	var d := _sdef(sdef_sel)
	if d.is_empty():
		return
	var used := sstat.filter(func(e): return e.status == d.id)
	for e in used:
		sstat.erase(e)
	sdefs.erase(d)
	sdef_sel = sdefs[0].id if not sdefs.is_empty() else ""
	StatusCatalog.refresh(sdefs)
	_mark()
	status.text = "상태 '%s' 삭제%s (저장 안 함)" % [d.name, "" if used.is_empty() else " — 달려 있던 스킬 %d개에서도 뺌" % used.size()]
	_rebuild()


func _build_sdef_form() -> void:
	var d := _sdef(sdef_sel)
	if d.is_empty():
		form.add_child(_head("상태를 고르세요"))
		return
	form.add_child(_head("%s (%s)" % [d.name, d.id]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	form.add_child(grid)
	var idl := _lab(d.id)
	idl.tooltip_text = "id = 효과 id, 같은 효과 두 번째부터 _2, _3 … (자동). 같은 id 는 겹치지 않고, id 가 다르면 같은 효과라도 따로 걸림"
	_row(grid, "id (자동)", idl)
	_row(grid, "이름", _line(d.name, func(v):
		d.name = str(v)
		_sdef_changed()))
	var effs := []
	for eff in StatusCatalog.EFFECT_ORDER:
		effs.append([eff, "%s (%s)" % [StatusCatalog.EFFECTS[eff].name, eff]])
	_row(grid, "효과", _option(effs, d.effect, func(v):
		var old_id: String = d.id
		d.effect = str(v)
		d.id = StatusCatalog.next_id(d.effect, sdefs, d)   # 효과가 바뀌면 id 도 그 효과 번호로
		sdef_sel = d.id
		StatusCatalog.refresh(sdefs)
		for e in sstat:   # 달린 스킬도 새 id, 수치는 그 효과 기본값으로
			if e.status == old_id:
				e.status = d.id
				e.value = StatusCatalog.default_value(d.id) if StatusCatalog.hint(d.id) != "" else 0
		status.text = "효과 바꿈: %s → %s (저장 안 함)" % [old_id, d.id]
		_sdef_changed()
		_rebuild()))
	var on_short := func(v):
		d.short = str(v)
		_sdef_changed()
	_row(grid, "머리 위 글자", _line(d.short, on_short, "한 글자"))
	var cp := ColorPickerButton.new()
	cp.color = Color.html(d.color) if str(d.color).begins_with("#") else StatusCatalog.color_of(d.id)
	cp.custom_minimum_size = Vector2(80, 26)
	cp.color_changed.connect(func(c):
		d.color = "#" + c.to_html(false)
		_sdef_changed())
	_row(grid, "색", cp)
	var on_desc := func(v):
		d.desc = str(v)
		_sdef_changed()
	_row(grid, "설명", _line(d.get("desc", ""), on_desc, "비우면 효과 설명 ({t} = 턴, {v} = 수치)"))
	var e0: Dictionary = StatusCatalog.EFFECTS.get(d.effect, {})
	form.add_child(_small("효과 '%s': %s%s" % [e0.get("name", d.effect), str(e0.get("desc", "")).replace("{t}", "n").replace("{v}", "v"),
		"" if str(e0.get("hint", "")) == "" else "\n스킬에 달 때 수치 = " + str(e0.hint)]))
	form.add_child(HSeparator.new())
	var users := sstat.filter(func(e): return e.status == d.id)
	form.add_child(_head("이 상태가 달린 스킬 (%d)" % users.size()))
	if users.is_empty():
		form.add_child(_small("없음 — '상태 이상' 화면에서 스킬에 답니다."))
	for e in users:
		var a: ActionData = actions.get(e.skill)
		var row := HBoxContainer.new()
		form.add_child(row)
		var l := _small("%s (%s) — %s" % [a.display_name if a != null else e.skill, e.skill, SkillStatusData.summary({"id": d.id, "turns": e.turns, "value": e.value, "chance": e.chance})])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 260
		row.add_child(l)
		var sk: String = e.skill
		row.add_child(_btn("열기", func():
			skill_sel = sk
			kind = "status"
			_rebuild()))


# ================================================================ 몬스터 스킬
func _build_monster_box() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var mc := VBoxContainer.new()
	mc.custom_minimum_size.x = 220
	box.add_child(mc)
	mc.add_child(_head("몬스터"))
	mon_list = ItemList.new()
	mon_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mon_list.item_selected.connect(func(i):
		mon_sel = str(mon_list.get_item_metadata(i))
		mskill_sel = ""
		_rebuild())
	mc.add_child(mon_list)
	mc.add_child(_small("HP·속도·AI 등 스탯은 밸런스 엑셀 몬스터 시트."))
	var kc := VBoxContainer.new()
	kc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(kc)
	kc.add_child(_head("이 몬스터가 쓰는 스킬 (순서대로)"))
	kit_list = ItemList.new()
	kit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	kit_list.item_selected.connect(func(i):
		mskill_sel = str(kit_list.get_item_metadata(i))
		_rebuild())
	kc.add_child(kit_list)
	var r1 := HBoxContainer.new()
	kc.add_child(r1)
	kit_add = OptionButton.new()
	kit_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(kit_add)
	r1.add_child(_btn("넣기", func():
		if kit_add.selected < 0:
			return
		var sid := str(kit_add.get_item_metadata(kit_add.selected))
		var kit := _kit()
		if not kit.has(sid):
			kit.append(sid)
		mskill_sel = sid
		_mark()
		_rebuild()))
	var r2 := HBoxContainer.new()
	kc.add_child(r2)
	r2.add_child(_btn("▲", func(): _kit_move(-1)))
	r2.add_child(_btn("▼", func(): _kit_move(1)))
	r2.add_child(_btn("빼기", func():
		_kit().erase(mskill_sel)
		mskill_sel = ""
		_mark()
		_rebuild()))
	r2.add_child(_btn("+ 새 몬스터 스킬", _new_monster_skill))
	r2.add_child(_btn("AI 그래프에 넣기", _add_to_ai))
	kc.add_child(_small("공용 스킬(기본 공격·강공격·필살기 등 = 엑셀 스킬 시트)도 넣을 수 있음. 몬스터 전용 스킬은 여기서 만들고 고침. AI 가 쓰려면 그 몬스터 AI 그래프에 노드가 있어야 함 → 'AI 그래프에 넣기' (필살기 다음 칸, 실패하면 다음으로)."))
	return box


func _kit() -> Array:
	if not mdata.kits.has(mon_sel):
		mdata.kits[mon_sel] = []
	return mdata.kits[mon_sel]


func _mskill(id: String) -> Dictionary:
	for s in mdata.skills:
		if s.id == id:
			return s
	return {}


func _ai_uses() -> Dictionary:
	var out := {}
	for mid in monsters:
		out[mid] = AIGraph.skills_used(AIGraph.load_graph((monsters[mid] as UnitData).ai_id))
	return out


## 이름·AP·효과 한 줄 (엑셀 공용 스킬 또는 몬스터 전용 스킬)
func _skill_line(sid: String) -> String:
	var m := _mskill(sid)
	var eff := ""
	if not m.is_empty():
		eff = "%s (%s) · AP %d · %s %d" % [m.name, sid, int(m.ap), MonsterSkillData.EFFECTS.get(m.effect, m.effect), int(m.power)]
	elif actions.has(sid):
		var a: ActionData = actions[sid]
		eff = "%s (%s) · AP %d · %s %d · 공용" % [a.display_name, sid, a.ap_cost, MonsterSkillData.EFFECTS.get(a.effect, a.effect), a.power]
	else:
		eff = "%s (없는 스킬)" % sid
	var st := _skill_statuses(sid)
	if not st.is_empty():
		eff += " · [%s]" % " · ".join(st.map(func(e): return StatusCatalog.get_def(e.status).name))
	return eff


func _fill_monster_lists() -> void:
	mon_list.clear()
	var uses := _ai_uses()
	for mid in monsters:
		var m: UnitData = monsters[mid]
		mon_list.add_item("%s (%s) · AI %s" % [m.display_name, mid, m.ai_id])
		mon_list.set_item_metadata(mon_list.item_count - 1, mid)
		if mid == mon_sel:
			mon_list.select(mon_list.item_count - 1)
	kit_list.clear()
	var used: Array = uses.get(mon_sel, [])
	for sid in _kit():
		kit_list.add_item(("" if used.has(sid) else "⚠ AI 안 씀 · ") + _skill_line(sid))
		kit_list.set_item_metadata(kit_list.item_count - 1, sid)
		if not used.has(sid):
			kit_list.set_item_custom_fg_color(kit_list.item_count - 1, Color(1, 0.82, 0.4))
		if sid == mskill_sel:
			kit_list.select(kit_list.item_count - 1)
	kit_add.clear()
	var all := []
	for s in mdata.skills:
		all.append([s.id, "%s (%s) · 몬스터" % [s.name, s.id]])
	for sid in sheet_skill_ids:
		var a: ActionData = actions[sid]
		if not a.effect in ["move", "weapon_swap"]:
			all.append([sid, "%s (%s) · 공용" % [a.display_name, sid]])
	for it in all:
		if not _kit().has(it[0]):
			kit_add.add_item(it[1])
			kit_add.set_item_metadata(kit_add.item_count - 1, it[0])


func _kit_move(d: int) -> void:
	var kit := _kit()
	var i := kit.find(mskill_sel)
	if i < 0 or i + d < 0 or i + d >= kit.size():
		return
	kit[i] = kit[i + d]
	kit[i + d] = mskill_sel
	_mark()
	_rebuild()


func _new_monster_skill() -> void:
	var base := "%s_skill" % mon_sel
	var id := base
	var i := 2
	while not _mskill(id).is_empty() or actions.has(id):
		id = "%s_%d" % [base, i]
		i += 1
	var s := MonsterSkillData.new_skill(id)
	mdata.skills.append(s)
	actions[id] = MonsterSkillData.to_action(s)
	_kit().append(id)
	mskill_sel = id
	_mark()
	_rebuild()


## 고른 스킬을 이 몬스터 AI 그래프에 '스킬 사용' 노드로 (같은 AI 를 쓰는 다른 몬스터는 그 스킬이 없으면 건너뜀)
func _add_to_ai() -> void:
	if mskill_sel == "" or not monsters.has(mon_sel):
		return
	var ai_id: String = (monsters[mon_sel] as UnitData).ai_id
	var g: Dictionary = AIGraph.load_graph(ai_id).duplicate(true)
	if g.is_empty():
		status.text = "AI 그래프 '%s' 가 없습니다 (AI 탭에서 만드세요)" % ai_id
		return
	var target := "no_status" if not _skill_statuses(mskill_sel).is_empty() else "hp_pct_low"
	if not AIGraph.insert_skill(g, mskill_sel, target):
		status.text = "이미 AI 그래프 '%s' 에 있거나 끼울 '스킬 사용' 노드가 없습니다" % ai_id
		return
	AIGraph.save_graph(ai_id, g)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(AIGraph.path_of(ai_id))
	status.text = "AI 그래프 '%s' 에 '%s' 노드를 넣었습니다 (저장됨, AI 탭에서 위치·대상 규칙 조정)" % [ai_id, mskill_sel]
	_rebuild()


func _build_monster_form() -> void:
	if not monsters.has(mon_sel):
		form.add_child(_head("몬스터를 고르세요"))
		return
	var mu: UnitData = monsters[mon_sel]
	form.add_child(_head("%s — HP %d · 속도 %d · AP %d(+%d) · 방어 %d" % [mu.display_name, mu.max_hp, mu.speed, mu.max_ap, mu.ap_recovery, mu.defense]))
	if mskill_sel == "":
		form.add_child(_small("가운데 목록에서 스킬을 고르면 여기서 고칩니다. '+ 새 몬스터 스킬' 로 이 몬스터 전용 스킬을 만들 수 있습니다."))
		return
	form.add_child(HSeparator.new())
	var m := _mskill(mskill_sel)
	if m.is_empty():
		var a: ActionData = actions.get(mskill_sel)
		if a == null:
			form.add_child(_head("없는 스킬 '%s'" % mskill_sel))
			return
		form.add_child(_head("%s (%s) — 공용 스킬" % [a.display_name, a.id]))
		form.add_child(_small("아군과 같이 쓰는 스킬이라 수치는 밸런스 엑셀 스킬 시트에서 고칩니다.\nAP %d · 대상 %s · %s %d\n%s" % [a.ap_cost,
			MonsterSkillData.TARGETS.get(a.target_rule, a.target_rule), MonsterSkillData.EFFECTS.get(a.effect, a.effect), a.power, a.description]))
		form.add_child(HSeparator.new())
		_status_cards(a.id, a.effect)
		form.add_child(_small("※ 공용 스킬에 단 상태 이상은 아군이 쓸 때도 걸립니다."))
		return
	form.add_child(_head("몬스터 전용 스킬"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	form.add_child(grid)
	var idl := LineEdit.new()
	idl.text = str(m.id)
	idl.placeholder_text = "고유 id (영문) — Enter 로 적용"
	idl.text_submitted.connect(func(v):
		v = v.strip_edges()
		if v == "" or v == m.id:
			return
		if not _mskill(v).is_empty() or sheet_skill_ids.has(v):
			status.text = "스킬 id '%s' 는 이미 있습니다" % v
			return
		for k in mdata.kits:
			var kit: Array = mdata.kits[k]
			var at := kit.find(m.id)
			if at >= 0:
				kit[at] = v
		for e in sstat:
			if e.skill == m.id:
				e.skill = v
		actions.erase(m.id)
		m.id = v
		mskill_sel = v
		_sync_mskill(m)
		status.text = "id 바꿈 — AI 그래프에 옛 id 노드가 있으면 AI 탭에서 바꾸세요"
		_mark()
		_rebuild())
	_row(grid, "id", idl)
	_row(grid, "이름", _line(str(m.name), func(v):
		m.name = v
		_sync_mskill(m)
		_fill_monster_lists()))
	var kinds := []
	for k in MonsterSkillData.KINDS:
		kinds.append([k, MonsterSkillData.KINDS[k]])
	_row(grid, "종류", _option(kinds, m.kind, func(v):
		m.kind = str(v)
		_sync_mskill(m)
		_mark()))
	var ap := _spin(0, 20, 1, int(m.ap), "")
	ap.value_changed.connect(func(v):
		if not _rebuilding:
			m.ap = int(v)
			_sync_mskill(m)
			_mark()
			_fill_monster_lists())
	_row(grid, "AP 비용", ap)
	var tg := []
	for k in MonsterSkillData.TARGETS:
		tg.append([k, MonsterSkillData.TARGETS[k]])
	_row(grid, "대상", _option(tg, m.target, func(v):
		m.target = str(v)
		_sync_mskill(m)
		_mark()))
	var ef := []
	for k in MonsterSkillData.EFFECTS:
		ef.append([k, MonsterSkillData.EFFECTS[k]])
	_row(grid, "효과", _option(ef, m.effect, func(v):
		m.effect = str(v)
		_sync_mskill(m)
		_mark()
		_rebuild()))
	if m.effect != "status":
		var pw := _spin(0, 999, 1, int(m.power), "")
		pw.value_changed.connect(func(v):
			if not _rebuilding:
				m.power = int(v)
				_sync_mskill(m)
				_mark()
				_fill_monster_lists())
		_row(grid, "위력" if m.effect == "damage" else ("회복량" if m.effect == "heal" else "AP"), pw)
	_row(grid, "설명", _line(str(m.desc), func(v):
		m.desc = v
		_sync_mskill(m)))
	var del := _btn("이 몬스터 스킬 삭제 (모든 몬스터에서)", func():
		mdata.skills.erase(m)
		for k in mdata.kits:
			(mdata.kits[k] as Array).erase(m.id)
		sstat = sstat.filter(func(e): return e.skill != m.id)
		actions.erase(m.id)
		mskill_sel = ""
		_mark()
		_rebuild())
	form.add_child(del)
	form.add_child(HSeparator.new())
	_status_cards(m.id, m.effect)


## 고친 몬스터 스킬을 actions 에도 (상태 이상 화면·검사가 같은 스킬을 보게)
func _sync_mskill(m: Dictionary) -> void:
	actions[m.id] = MonsterSkillData.to_action(m)


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
	gc.add_child(_small("누가 어느 신을 믿는지·시작 신앙도는 오른쪽 아래 '대원 신앙'."))
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
	for cid2 in char_faith:   # 그 신을 믿던 대원 = 무신앙
		if char_faith[cid2].god == g.id:
			char_faith[cid2].god = ""
	status.text = "'%s' 와 그 신앙 스킬을 지웠습니다 (믿던 대원은 무신앙, 저장 안 함)" % g.name
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
		for cid2 in char_faith:   # 믿는 대원도 새 id 로
			if char_faith[cid2].god == g.id:
				char_faith[cid2].god = v
		status.text = "신 id 바꿈 → '%s' (믿는 대원도 따라감, 저장 안 함)" % v
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
	var on_sym := func(v): g.symbol = v
	_row(grid, "아이콘 글자", _line(str(g.get("symbol", "")), on_sym, "비우면 '%s' (이름 끝 단어 첫 글자)" % FaithData.symbol_of({"name": g.name})))
	_row(grid, "설명", _line(str(g.desc), func(v): g.desc = v))
	var bl := _believers(str(g.id))
	_row(grid, "믿는 대원", _small(", ".join(bl) if not bl.is_empty() else "(없음 — 아래 '대원 신앙')"))
	form.add_child(_small("세계관 설명(도감 '종교(신)' 탭)은 data/codex.json 의 gods."))
	_believer_rows()
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


## 대원마다 믿는 신 · 시작 신앙도 (모든 대원, data/faith.json believers)
func _believer_rows() -> void:
	form.add_child(HSeparator.new())
	form.add_child(_head("대원 신앙 (믿는 신 · 시작 신앙도)"))
	var gods := [["", "무신앙"]]
	for g in faith.gods:
		gods.append([g.id, g.name])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	form.add_child(grid)
	for u in allies:
		var cf: Dictionary = char_faith.get(u.id, {"god": "", "faith": 0})
		char_faith[u.id] = cf
		grid.add_child(_lab(u.display_name))
		var o := _option(gods, cf.god, func(v):
			cf.god = str(v)
			_mark()
			_rebuild())
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(o)
		var sp := _spin(0, FaithData.FAITH_MAX, 1, int(cf.faith), "")
		sp.tooltip_text = "시작 신앙도 (출전마다 + 기지 설정 faith_battle)"
		sp.value_changed.connect(func(v):
			if not _rebuilding:
				cf.faith = int(v)
				_mark())
		grid.add_child(sp)


func _build_form() -> void:
	var n := _node(sel)
	if n.is_empty() or n.char != cid or n.kind != kind:
		form.add_child(_head("노드를 고르세요"))
		form.add_child(_small("트리 모양은 캐릭터마다 자유롭게 — 가운데 그림에서\n· 빈 칸 클릭 = 그 칸에 새 노드 (노드를 골라 둔 채면 그 노드에서 이어짐)\n· 노드 끌기 = 다른 빈 칸으로 옮기기\n"
			+ "· Shift+클릭 = 고른 노드 → 누른 노드로 선 잇기/끊기 (누른 노드가 고른 노드를 먼저 배워야)\n· Delete = 고른 노드 삭제\n· 위 '모양 틀' = 십자형 · 두 갈래 · 일자 · 나무 · 그물 모양으로 새로 짜기, '다른 캐릭터 트리 가져오기' = 모양째 복사\n\n"
			+ "게임 규칙\n· 시작 노드는 처음부터 배운 상태\n· 선행이 있으면 선행을 먼저 (하나라도 / '모두 필요' 면 전부)\n· 같은 택일 그룹은 트리마다 하나만 → 어느 쪽으로 뻗을지가 빌드\n"
			+ "· 레벨이 필요 레벨보다 낮으면 게임에서 회색 + '경험 부족'\n· 스킬 포인트는 액티브·패시브 공용 (레벨 업마다 1, 처음 1)\n"
			+ "· 갈래 색은 보이기만 (규칙과 무관)"))
		return
	form.add_child(_head("%s · (%d, %d) 칸%s" % [SkillTreeData.KIND_NAME[kind], int(n.x), int(n.y), " · 시작 노드" if bool(n.start) else ""]))
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
	var brs := []
	for b in SkillTreeData.BRANCHES:
		brs.append([b, SkillTreeData.BRANCH_NAME[b]])
	_row(grid, "갈래 (색)", _option(brs, n.branch, func(v):
		n.branch = str(v)
		_mark()))
	var st := CheckBox.new()
	st.text = "시작 노드 (처음부터 배운 상태, 포인트 안 씀)"
	st.button_pressed = bool(n.start)
	st.toggled.connect(func(v):
		if not _rebuilding:
			n.start = v
			_mark()
			_rebuild())
	_row(grid, "시작", st)
	var lv := _spin(1, 99, 1, int(n.level), "")
	lv.value_changed.connect(func(v):
		if not _rebuilding:
			n.level = int(v)
			_mark())
	_row(grid, "필요 레벨", lv)
	# 선행
	if not bool(n.start):
		var rv := VBoxContainer.new()
		for q in n.req:
			var rr := HBoxContainer.new()
			var qn := _node(str(q))
			var ql := _lab("← %s (%s)" % [qn.get("name", "?"), q])
			ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rr.add_child(ql)
			var qq: String = q
			rr.add_child(_btn("✕", func():
				n.req.erase(qq)
				_mark()
				_rebuild()))
			rv.add_child(rr)
		var cands := [["", "(선행 추가…)"]]
		for o in _tree():
			if o.id != n.id and not (n.req as Array).has(o.id):
				cands.append([o.id, "%s (%s)" % [o.name, o.id]])
		rv.add_child(_option(cands, "", func(v):
			if str(v) != "":
				_toggle_link(str(v), str(n.id))))
		if (n.req as Array).size() > 1:
			var all := CheckBox.new()
			all.text = "선행을 모두 배워야 (끄면 하나라도)"
			all.button_pressed = bool(n.req_all)
			all.toggled.connect(func(v):
				if not _rebuilding:
					n.req_all = v
					_mark())
			rv.add_child(all)
		if (n.req as Array).is_empty():
			rv.add_child(_small("선행 없음 — 레벨만 되면 바로 배울 수 있음"))
		_row(grid, "선행", rv)
	# 택일 그룹
	var gv := HBoxContainer.new()
	var set_group := func(v):
		n.group = str(v).strip_edges()
		canvas.queue_redraw()
	var gl := _line(str(n.group), set_group, "비우면 없음 (같은 이름끼리 하나만)")
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.add_child(gl)
	var used := {}
	for o in _tree():
		if str(o.group) != "":
			used[o.group] = true
	if not used.is_empty():
		var gi := [["", "기존 그룹…"]]
		for g in used:
			gi.append([g, g])
		gv.add_child(_option(gi, "", func(v):
			if str(v) != "":
				n.group = str(v)
				_mark()
				_rebuild()))
	_row(grid, "택일 그룹", gv)
	_effect_rows(grid, n)
	form.add_child(_small("설명이 자동 문장 그대로면 효과·값을 바꿀 때 같이 바뀝니다."))
	if str(n.effect).begins_with("skill:"):
		form.add_child(_small("새 스킬은 전투 HUD 기본 스킬 칸(%d칸, 필살기 제외)에 붙습니다. 칸이 넘치면 안 보이므로 택일 그룹으로 묶는 것을 권장." % SkillTreeData.SKILL_SLOTS))
	var mv := HBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	form.add_child(mv)
	mv.add_child(_lab("옮기기"))
	for d in [[Vector2i(-1, 0), "←"], [Vector2i(0, -1), "↑"], [Vector2i(0, 1), "↓"], [Vector2i(1, 0), "→"]]:
		var dv: Vector2i = d[0]
		var mb := _btn(str(d[1]), func(): _move_node(str(n.id), int(n.x) + dv.x, int(n.y) + dv.y))
		mb.disabled = not _cell(int(n.x) + dv.x, int(n.y) + dv.y).is_empty()
		mv.add_child(mb)
	var del := _btn("이 노드 삭제", func(): _delete(str(n.id)))
	del.tooltip_text = "이 노드를 선행으로 쓰던 노드는 이 노드의 선행을 이어받습니다"
	mv.add_child(del)
	form.add_child(_small("※ id 를 바꾸면 이미 그 스킬을 배운 저장 파일에서는 배운 것이 풀립니다 (포인트는 돌려받음). 선행 목록의 id 는 같이 바뀝니다."))


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
	for o in nodes:   # 선행 목록도 새 id 로
		var i: int = (o.get("req", []) as Array).find(n.id)
		if i >= 0:
			o.req[i] = v
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
