extends Control
## 편성 화면: 아군 6인을 전방/중앙/후방 × 2 슬롯에 배치. 유닛 클릭 → 슬롯 클릭 (빈 슬롯 이동 / 점유 슬롯 교환).

var _font: Font
var manifest: Dictionary
var selected_unit: String = ""
var slot_buttons: Dictionary = {}   # key -> Button
var roster_buttons: Dictionary = {} # unit_id -> Button
var info_label: Label


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.1)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var head := "전투 배치 — %s" % Game.data.stages.get(Game.stage_id, {}).get("name", Game.stage_id) if Game.campaign and Game.data != null else "편성"
	var title := _label("%s — 아군 전방/중앙/후방 2슬롯 (유닛을 고른 뒤 슬롯을 클릭: 빈 슬롯 이동, 점유 슬롯 교환)" % head, 20, Color(1, 0.95, 0.7))
	title.position = Vector2(40, 24)
	add_child(title)
	info_label = _label("", 15, Color(0.8, 0.95, 1.0))
	info_label.position = Vector2(40, 60)
	add_child(info_label)

	# 슬롯 그리드 (좌: 후방 → 우: 전방, 전장 방향과 동일)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.position = Vector2(60, 120)
	add_child(grid)
	for idx in 2:
		for row in [2, 1, 0]:
			var key := SlotManager.make_key("ally", row, idx)
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 150)
			b.add_theme_font_override("font", _font)
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(func(): _on_slot(key))
			grid.add_child(b)
			slot_buttons[key] = b
	var row_labels := HBoxContainer.new()
	row_labels.position = Vector2(60, 440)
	row_labels.add_theme_constant_override("separation", 16)
	add_child(row_labels)
	for t in ["후방", "중앙", "전방 →적"]:
		var l := _label(t, 18, Color(0.9, 0.9, 0.9))
		l.custom_minimum_size.x = 190
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row_labels.add_child(l)

	# 로스터
	var roster := VBoxContainer.new()
	roster.position = Vector2(720, 120)
	roster.add_theme_constant_override("separation", 8)
	add_child(roster)
	roster.add_child(_label("아군 로스터", 18, Color(1, 1, 1)))
	for u0 in Game.allies:
		var u := Game.ally_view(u0)   # 기지 훈련·장비 반영
		var b := Button.new()
		b.custom_minimum_size = Vector2(480, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 15)
		b.text = "%s  %s  Lv%d  속도%d  HP%d  AP%d(+%d)  %s" % [u.display_name, u.role, u.level, u.speed, u.max_hp, u.max_ap, u.ap_recovery, "원거리" if u.range_type == "ranged" else "근접"]
		b.icon = _portrait(u)
		b.expand_icon = true
		var uid := u0.id
		b.pressed.connect(func(): _select(uid))
		roster.add_child(b)
		roster_buttons[u.id] = b

	var btns := HBoxContainer.new()
	btns.position = Vector2(720, 520)
	btns.add_theme_constant_override("separation", 12)
	add_child(btns)
	var start := _big_button("전투 시작 (%s)" % Game.mode.to_upper(), Color(1.0, 0.5, 0.3))
	start.pressed.connect(func(): Game.restart_count = 0; Game.start_battle())
	btns.add_child(start)
	var reset := _big_button("기본 편성", Color(0.5, 0.7, 0.9))
	reset.pressed.connect(func(): Game.reset_formation(); _refresh())
	btns.add_child(reset)
	var back := _big_button("기지로" if Game.campaign else "메뉴", Color(0.6, 0.6, 0.6))
	back.pressed.connect(func(): Game.go_menu())
	btns.add_child(back)
	_refresh()
	Game.maybe_cli_capture()


func _portrait(u: UnitData) -> Texture2D:
	return UnitArt.portrait(u.sprite_id, manifest)


func _select(uid: String) -> void:
	selected_unit = uid
	var d := Game.find_ally(uid)
	info_label.text = "선택: %s — 배치할 슬롯을 클릭하세요." % d.display_name
	_refresh()


func _entry_for(uid: String) -> Dictionary:
	for f in Game.formation:
		if f.unit_id == uid:
			return f
	return {}


func _entry_at(key: String) -> Dictionary:
	var info := SlotManager.parse_key(key)
	for f in Game.formation:
		if f.row == info.row and f.index == info.index:
			return f
	return {}


func _on_slot(key: String) -> void:
	var occupant := _entry_at(key)
	if selected_unit == "":
		if not occupant.is_empty():
			_select(occupant.unit_id)
		return
	var me := _entry_for(selected_unit)
	var info := SlotManager.parse_key(key)
	if occupant.is_empty():
		me.row = info.row
		me.index = info.index
		info_label.text = "%s → %s %d 이동" % [Game.find_ally(selected_unit).display_name, SlotManager.ROW_NAMES[info.row], info.index + 1]
	elif occupant != me:
		var r: int = me.row
		var i: int = me.index
		me.row = occupant.row
		me.index = occupant.index
		occupant.row = r
		occupant.index = i
		info_label.text = "%s ↔ %s 자리 교환" % [Game.find_ally(selected_unit).display_name, Game.find_ally(occupant.unit_id).display_name]
	selected_unit = ""
	_refresh()


func _refresh() -> void:
	for key in slot_buttons:
		var b: Button = slot_buttons[key]
		var e := _entry_at(key)
		if e.is_empty():
			b.text = "빈 슬롯"
			b.icon = null
			b.modulate = Color(0.75, 0.75, 0.8)
		else:
			var d := Game.find_ally(e.unit_id)
			b.text = "%s\n%s" % [d.display_name, d.role]
			b.icon = _portrait(d)
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.modulate = Color(1, 1, 0.6) if e.unit_id == selected_unit else Color(1, 1, 1)
	for uid in roster_buttons:
		roster_buttons[uid].modulate = Color(1, 1, 0.6) if uid == selected_unit else Color(1, 1, 1)


func _label(text: String, size: int, color: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load("res://assets/fonts/Pretendard-Bold.ttf") if size >= 20 else _font)   # 큰 글자는 Bold
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(170, 50)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.5)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate()
	h.bg_color = color.darkened(0.2)
	b.add_theme_stylebox_override("hover", h)
	return b
