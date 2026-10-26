extends Control
## 스테이지 에디터: 스테이지별 적 배치(data/stages/<id>.json)를 칸에 놓아 편집.
## 스테이지 목록·조명·선공·배율은 밸런스 엑셀 "스테이지" 시트, 몬스터 목록·차지칸은 "몬스터" 시트.
## 왼쪽에서 몬스터를 고르고 칸을 클릭해 배치, 배치된 몬스터를 클릭(또는 우클릭)하면 제거. 저장 → 테스트 플레이.

const CELL := Vector2(170, 150)
const GAP := 10.0
const ROW_NAMES := ["전방", "중앙", "후방"]

var stage_list: OptionButton
var info: Label
var status: Label
var grid: Control
var palette_box: VBoxContainer
var stage_id := ""
var placement: Array = []      # [{monster, row, index}]
var selected := ""             # 고른 몬스터 id
var _hover := Vector2i(-1, -1)
var _palette_btns: Dictionary = {}


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
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "스테이지 에디터"
	title.add_theme_font_override("font", load("res://assets/fonts/Pretendard-Bold.ttf"))
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	stage_list = OptionButton.new()
	stage_list.custom_minimum_size.x = 220
	stage_list.item_selected.connect(func(i): _load(stage_list.get_item_metadata(i)))
	top.add_child(stage_list)
	top.add_child(_btn("저장", _save))
	top.add_child(_btn("테스트 플레이", _play))
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_btn("메뉴로", func(): Game.go_menu()))
	info = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
	root.add_child(info)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 230
	body.add_child(left)
	left.add_child(_small("몬스터 (엑셀 몬스터 시트)"))
	palette_box = VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 4)
	left.add_child(palette_box)
	var help := _small("· 몬스터를 고른 뒤 칸 클릭 = 배치\n· 배치된 몬스터 클릭/우클릭 = 제거\n· 2칸 몬스터는 고른 칸부터 뒤 열까지\n· 열: 전방이 아군과 가장 가까움\n· 줄 1 = 뒤쪽, 줄 2 = 카메라 쪽\n· 조명·선공·배율은 엑셀 스테이지 시트")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(help)
	grid = Control.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.draw.connect(_draw_grid)
	grid.gui_input.connect(_grid_input)
	grid.mouse_exited.connect(func(): _hover = Vector2i(-1, -1); grid.queue_redraw())
	body.add_child(grid)
	_build_palette()
	_refresh_stages()
	if Game.data != null and not Game.data.stage_order.is_empty():
		_load(Game.stage_id if Game.stage_id != "" else Game.data.stage_order[0])
	Game.data_reloaded.connect(func(_w): _build_palette(); _refresh_stages(); _update_info(); grid.queue_redraw())
	Game.maybe_cli_capture()


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l


func _monsters() -> Dictionary:
	return Game.data.monsters if Game.data != null else {}


func _build_palette() -> void:
	for c in palette_box.get_children():
		c.queue_free()
	_palette_btns.clear()
	for id in _monsters():
		var m: UnitData = _monsters()[id]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = "%s  (%d칸 · HP %d)" % [m.display_name, m.row_span, m.max_hp]
		b.icon = UnitArt.portrait(m.sprite_id, {})
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = id == selected
		var mid: String = id
		b.pressed.connect(func(): _select(mid))
		palette_box.add_child(b)
		_palette_btns[id] = b


func _select(id: String) -> void:
	selected = "" if selected == id else id
	for k in _palette_btns:
		_palette_btns[k].button_pressed = k == selected


func _refresh_stages() -> void:
	stage_list.clear()
	if Game.data == null:
		return
	for id in Game.data.stage_order:
		stage_list.add_item("%s  (%s)" % [Game.data.stages[id].name, id])
		stage_list.set_item_metadata(stage_list.item_count - 1, id)
		if id == stage_id:
			stage_list.select(stage_list.item_count - 1)


func _load(id: String) -> void:
	stage_id = id
	placement = GameData.load_placement(id).duplicate(true)
	_refresh_stages()
	_update_info()
	status.text = ""
	grid.queue_redraw()


func _update_info() -> void:
	if Game.data == null or not Game.data.stages.has(stage_id):
		info.text = ""
		return
	var st: Dictionary = Game.data.stages[stage_id]
	var amb: String = {"none": "동전", "ally": "기습(아군 선공)", "enemy": "매복(적 선공)"}.get(st.ambush, st.ambush)
	info.text = "조명 %s · 선공 %s · 적 HP ×%s · 적 공격 ×%s · 시드 %d   — %s   (엑셀 스테이지 시트에서 수정)" % [st.preset, amb, str(st.hp_mult), str(st.dmg_mult), st.seed, st.desc]


# ---------------------------------------------------------------- 칸
func _origin() -> Vector2:
	var w := 3 * CELL.x + 2 * GAP
	var h := 2 * CELL.y + GAP
	return Vector2(maxf(20.0, (grid.size.x - w) * 0.5), maxf(60.0, (grid.size.y - h) * 0.5))


func _cell_rect(row: int, index: int, span: int = 1) -> Rect2:
	var o := _origin()
	var pos := o + Vector2(row * (CELL.x + GAP), index * (CELL.y + GAP))
	return Rect2(pos, Vector2(span * CELL.x + (span - 1) * GAP, CELL.y))


func _cell_at(p: Vector2) -> Vector2i:
	for r in 3:
		for i in 2:
			if _cell_rect(r, i).has_point(p):
				return Vector2i(r, i)
	return Vector2i(-1, -1)


func _span_of(monster_id: String) -> int:
	var m: UnitData = _monsters().get(monster_id, null)
	return m.row_span if m != null else 1


func _occupant(r: int, i: int) -> int:
	for k in placement.size():
		var e: Dictionary = placement[k]
		if int(e.index) == i and r >= int(e.row) and r < int(e.row) + _span_of(str(e.monster)):
			return k
	return -1


func _grid_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := _cell_at(ev.position)
		if c != _hover:
			_hover = c
			grid.queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		var c := _cell_at(ev.position)
		if c.x < 0:
			return
		var occ := _occupant(c.x, c.y)
		if ev.button_index == MOUSE_BUTTON_RIGHT or (occ >= 0 and selected == ""):
			if occ >= 0:
				placement.remove_at(occ)
		elif ev.button_index == MOUSE_BUTTON_LEFT and selected != "":
			_place(selected, c.x, c.y)
		status.text = "저장 안 됨"
		grid.queue_redraw()


## 고른 칸부터 차지칸만큼 (넘치면 뒤 열에 맞춰 당김), 겹치는 기존 배치는 제거
func _place(monster_id: String, row: int, index: int) -> void:
	var span := _span_of(monster_id)
	row = mini(row, 3 - span)
	for r in range(row, row + span):
		var occ := _occupant(r, index)
		while occ >= 0:
			placement.remove_at(occ)
			occ = _occupant(r, index)
	placement.append({"monster": monster_id, "row": row, "index": index})


func _draw_grid() -> void:
	var font := get_theme_default_font()
	var o := _origin()
	grid.draw_string(font, o + Vector2(-4, -34), "◀ 아군 쪽", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.9, 0.7))
	for r in 3:
		var hr := _cell_rect(r, 0)
		grid.draw_string(font, Vector2(hr.position.x, o.y - 10), ROW_NAMES[r], HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 16, Color(0.85, 0.88, 0.95))
	for i in 2:
		var lr := _cell_rect(0, i)
		grid.draw_string(font, Vector2(o.x - 70, lr.get_center().y + 6), "줄 %d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.85))
	for r in 3:
		for i in 2:
			var rc := _cell_rect(r, i)
			var hov := _hover == Vector2i(r, i)
			grid.draw_rect(rc, Color(0.13, 0.15, 0.19) if not hov else Color(0.18, 0.22, 0.3))
			grid.draw_rect(rc, Color(1, 1, 1, 0.12), false, 1.0)
	# 놓을 자리 미리보기
	if selected != "" and _hover.x >= 0:
		var span := _span_of(selected)
		var pr := _cell_rect(mini(_hover.x, 3 - span), _hover.y, span)
		grid.draw_rect(pr, Color(0.3, 0.6, 1.0, 0.25))
		grid.draw_rect(pr, Color(0.4, 0.7, 1.0, 0.9), false, 2.0)
	for e in placement:
		var m: UnitData = _monsters().get(str(e.monster), null)
		var span := _span_of(str(e.monster))
		var rc := _cell_rect(int(e.row), int(e.index), span).grow(-6)
		grid.draw_rect(rc, Color(0.42, 0.12, 0.14, 0.95))
		grid.draw_rect(rc, Color(1.0, 0.45, 0.4), false, 2.0)
		if m != null:
			var tex := UnitArt.portrait(m.sprite_id, {})
			var side := minf(rc.size.y - 34, 96.0)
			grid.draw_texture_rect(tex, Rect2(rc.position + Vector2((rc.size.x - side) * 0.5, 8), Vector2(side, side)), false)
			grid.draw_string(font, Vector2(rc.position.x, rc.end.y - 10), "%s  HP %d" % [m.display_name, m.max_hp], HORIZONTAL_ALIGNMENT_CENTER, rc.size.x, 14, Color(1, 1, 1))
		else:
			grid.draw_string(font, rc.get_center(), "? " + str(e.monster), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.5))


# ---------------------------------------------------------------- 저장 / 실행
func _save() -> bool:
	if stage_id == "":
		return false
	if placement.is_empty():
		status.text = "적이 한 명 이상 있어야 합니다"
		return false
	DirAccess.make_dir_recursive_absolute(GameData.STAGE_DIR)
	var f := FileAccess.open(GameData.stage_path(stage_id), FileAccess.WRITE)
	if f == null:
		status.text = "저장 실패"
		return false
	var es := []
	for e in placement:
		es.append({"monster": str(e.monster), "row": int(e.row), "index": int(e.index)})
	f.store_string(JSON.stringify({"enemies": es}, "\t"))
	f.close()
	status.text = "저장됨: data/stages/%s.json" % stage_id
	return true


func _play() -> void:
	if not _save():
		return
	Game.set_stage(stage_id)
	Game.restart_count = 0
	Game.start_battle()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
		_save()
