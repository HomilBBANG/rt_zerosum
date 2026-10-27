extends Control
## 출정 대기 (편성) 화면.
## 왼쪽: 출정 가능한 대원 목록 (체력·피로·친밀도·상태 이상, 외부 의뢰 중이면 출정 불가로 흐리게)
## 오른쪽 위: 진형 — 후방 2 · 중간 2 · 전방 2 (오른쪽이 적 방향, 전장과 같은 방향)
## 조작: 목록에서 대원을 끌어다 진형 칸에 놓기 / 진형끼리 끌면 이동·자리 교환 / 진형에서 목록으로 끌거나 우클릭하면 빼기.
##       (클릭으로도 가능: 대원 클릭 → 칸 클릭)
## 배치된 대원은 지금 상태에 맞는 짧은 대사를 초상화 위 말풍선으로 말한다 (data/outgame/sortie_lines.json, Godot 에디터 '출정 대사' 탭).

const ROW_COLS := [2, 1, 0]   # 화면 왼쪽부터 후방(2) · 중간(1) · 전방(0)
const COL_NAMES := ["후방", "중간", "전방"]
const SLOT_SIZE := Vector2(250, 172)
const FORM_ORIGIN := Vector2(476, 128)
const FORM_GAP := Vector2(12, 22)
const CARD_SIZE := Vector2(420, 90)
const C_PANEL := Color(0.09, 0.12, 0.15)
const C_BORDER := Color(0.28, 0.34, 0.4)
const C_ACCENT := Color(1.0, 0.8, 0.35)
const C_HP := Color(0.95, 0.35, 0.32)
const C_FATIGUE := Color(1.0, 0.62, 0.25)
const C_AFFINITY := Color(1.0, 0.45, 0.72)
const BUBBLE_LIFE := 4.5

var _font: Font
var _bold: Font
var manifest: Dictionary
var lines: Array = []
var rng := RandomNumberGenerator.new()
var selected_unit: String = ""
var slot_nodes: Dictionary = {}     # key -> Control
var card_nodes: Dictionary = {}     # unit_id -> Control
var bubbles: Dictionary = {}        # unit_id -> SpeechBubble
var info_label: Label
var count_label: Label
var start_btn: Button
var roster_panel: Panel
var bubble_layer: Control
var _dragging := false


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	lines = SortieLines.read()
	rng.seed = Game.seed_value if Game.cli.has("shot") else int(Time.get_ticks_usec())
	Game.prune_formation()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var stage_name := str(Game.data.stages.get(Game.stage_id, {}).get("name", Game.stage_id)) if Game.data != null else ""
	var title := _label("출정 대기" + (" — " + stage_name if stage_name != "" else ""), 24, C_ACCENT, true)
	title.position = Vector2(24, 14)
	add_child(title)
	var hint := _label("대원을 끌어다 진형에 놓으세요 · 진형끼리 끌면 자리 교환 · 목록으로 끌거나 우클릭하면 빼기", 14, Color(0.7, 0.78, 0.85))
	hint.position = Vector2(24, 50)
	add_child(hint)
	_build_roster()
	_build_formation()
	_build_bottom()
	bubble_layer = Control.new()
	bubble_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bubble_layer)
	_refresh()
	# 화면을 열면 배치된 대원들이 차례로 한마디
	var order := Game.formation.duplicate()
	order.sort_custom(func(a, b): return _col_of(int(a.row)) * 2 + int(a.index) < _col_of(int(b.row)) * 2 + int(b.index))
	for i in order.size():
		get_tree().create_timer(0.05 + 0.12 * i).timeout.connect(_say.bind(str(order[i].unit_id)))
	if Game.cli.has("sortie_ops"):
		_cli_ops(str(Game.cli.sortie_ops))
	if Game.cli.get("sortie_go", "0") == "1" and not Game.formation.is_empty():   # CLI: 이 편성으로 바로 출정
		Game.cli.erase("sortie_go")
		Game.start_battle.call_deferred()
		return
	Game.maybe_cli_capture()


## CLI 확인용: 끌어 놓기와 같은 처리 — "drop:<대원>:<열 0후방~2전방>:<칸 0~1>;out:<대원>" (; 로 여러 개)
func _cli_ops(spec: String) -> void:
	for op in spec.split(";", false):
		var p := op.split(":")
		if p[0] == "drop" and p.size() >= 4:
			var key := SlotManager.make_key("ally", ROW_COLS[clampi(int(p[2]), 0, 2)], clampi(int(p[3]), 0, 1))
			var data := {"sortie_unit": p[1], "from": ""}
			var e := _entry_for(p[1])
			if not e.is_empty():
				data.from = SlotManager.make_key("ally", int(e.row), int(e.index))
			if _can_drop_slot(Vector2.ZERO, data, key):
				_drop_slot(Vector2.ZERO, data, key)
		elif p[0] == "out" and p.size() >= 2:
			var e := _entry_for(p[1])
			var data := {"sortie_unit": p[1], "from": SlotManager.make_key("ally", int(e.row), int(e.index)) if not e.is_empty() else ""}
			if _can_drop_roster(Vector2.ZERO, data):
				_drop_roster(Vector2.ZERO, data)
	print("[sortie] formation = ", Game.formation.map(func(f): return "%s@%s%d" % [f.unit_id, COL_NAMES[_col_of(int(f.row))], int(f.index) + 1]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_dragging = true
		_refresh()
	elif what == NOTIFICATION_DRAG_END:
		_dragging = false
		_refresh()


# ================================================================ 왼쪽: 대원 목록
func _build_roster() -> void:
	roster_panel = _panel(Rect2(16, 84, 444, 620))
	add_child(roster_panel)
	roster_panel.set_drag_forwarding(Callable(), _can_drop_roster, _drop_roster)
	var avail := Game.allies.filter(func(u): return Game.sortie_block_reason(u.id) == "").size()
	var head := _label("출정 가능 대원 %d / %d" % [avail, Game.allies.size()], 17, Color(1, 1, 1), true)
	head.position = Vector2(14, 10)
	roster_panel.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 42)
	scroll.size = Vector2(430, 570)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	roster_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(box)
	# 출정 가능한 대원 먼저, 못 나가는 대원은 맨 아래
	var list := Game.allies.duplicate()
	list.sort_custom(func(a, b): return (Game.sortie_block_reason(a.id) == "") and (Game.sortie_block_reason(b.id) != ""))
	for u in list:
		var card := Control.new()
		card.custom_minimum_size = CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var uid: String = u.id
		card.draw.connect(_draw_card.bind(card, uid))
		card.set_drag_forwarding(_drag_from_card.bind(uid), _can_drop_roster, _drop_roster)
		card.gui_input.connect(_card_input.bind(uid))
		card.mouse_entered.connect(func(): _show_info(uid))
		var tex := TextureRect.new()
		tex.texture = _portrait(u)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.position = Vector2(8, 7)
		tex.size = Vector2(76, 76)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tex)
		box.add_child(card)
		card_nodes[uid] = card


func _draw_card(card: Control, uid: String) -> void:
	var u := Game.ally_view(Game.find_ally(uid))
	var blocked := Game.sortie_block_reason(uid)
	var placed := not _entry_for(uid).is_empty()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.16, 0.2) if blocked == "" else Color(0.1, 0.1, 0.11)
	sb.border_color = C_ACCENT if uid == selected_unit else (Color(0.4, 0.75, 1.0) if placed else C_BORDER)
	sb.set_border_width_all(2 if uid == selected_unit or placed else 1)
	sb.set_corner_radius_all(8)
	card.draw_style_box(sb, Rect2(Vector2.ZERO, card.size))
	var nc := Color(1, 1, 1) if blocked == "" else Color(0.55, 0.55, 0.58)
	card.draw_string(_bold, Vector2(100, 26), u.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, nc)
	var nw := _bold.get_string_size(u.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	card.draw_string(_font, Vector2(108 + nw, 26), "%s · Lv%d" % [u.role, u.level], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.75, 0.82))
	var st := Game.sortie_state(uid)
	if st.known:
		_bar(card, Vector2(100, 40), "체력", float(st.hp) / maxf(1.0, float(st.max_hp)), "%d/%d" % [floori(float(st.hp)), int(st.max_hp)], C_HP)
		_bar(card, Vector2(100, 58), "피로", float(st.fatigue) / 100.0, "%d" % roundi(float(st.fatigue)), C_FATIGUE)
		_bar(card, Vector2(100, 76), "친밀", float(st.affinity) / 100.0, "%d" % roundi(float(st.affinity)), C_AFFINITY)
	else:
		card.draw_string(_font, Vector2(100, 56), "HP %d · AP %d(+%d) · 속도 %d" % [u.max_hp, u.max_ap, u.ap_recovery, u.speed], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.85, 0.9))
		card.draw_string(_font, Vector2(100, 76), "(기지 상태 없음 — 전투 테스트)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.6, 0.66))
	# 오른쪽: 배치 위치 / 출정 불가 / 상태 이상
	var tag := ""
	var tc := Color(0.6, 0.85, 1.0)
	if blocked != "":
		tag = blocked
		tc = Color(1.0, 0.55, 0.45)
	elif placed:
		var e := _entry_for(uid)
		tag = "%s %d" % [COL_NAMES[_col_of(int(e.row))], int(e.index) + 1]
	else:
		tag = "대기"
		tc = Color(0.62, 0.66, 0.72)
	var tw := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	card.draw_string(_font, Vector2(card.size.x - 12 - tw, 24), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
	var x := card.size.x - 12.0
	for sid in st.statuses:
		var def := StatusCatalog.get_def(str(sid))
		var nm := str(def.get("name", sid))
		var w := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12
		x -= w
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color(0.25, 0.5, 0.3) if def.get("positive", false) else Color(0.55, 0.16, 0.16)
		chip.set_corner_radius_all(4)
		card.draw_style_box(chip, Rect2(x, 34, w, 18))
		card.draw_string(_font, Vector2(x + 6, 48), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))
		x -= 4
	if blocked != "":
		card.draw_rect(Rect2(Vector2.ZERO, card.size), Color(0, 0, 0, 0.35))


func _bar(c: Control, at: Vector2, label: String, t: float, value: String, color: Color) -> void:
	c.draw_string(_font, at + Vector2(0, 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.84))
	var r := Rect2(at + Vector2(32, 1), Vector2(150, 10))
	c.draw_rect(r, Color(0.05, 0.06, 0.08))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(t, 0.0, 1.0), r.size.y)), color)
	c.draw_rect(r, Color(0.3, 0.33, 0.38), false, 1.0)
	c.draw_string(_font, at + Vector2(190, 10), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.9, 0.95))


func _card_input(ev: InputEvent, uid: String) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT and Game.sortie_block_reason(uid) == "":
			selected_unit = "" if selected_unit == uid else uid
			_show_info(uid)
			_refresh()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and not _entry_for(uid).is_empty():
			_remove(uid)


func _drag_from_card(_at: Vector2, uid: String) -> Variant:
	if Game.sortie_block_reason(uid) != "":
		return null
	card_nodes[uid].set_drag_preview(_drag_preview(uid))
	return {"sortie_unit": uid, "from": ""}


func _can_drop_roster(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("sortie_unit") and str(data.get("from", "")) != ""


func _drop_roster(_at: Vector2, data: Variant) -> void:
	_remove(str(data.sortie_unit))


# ================================================================ 오른쪽 위: 진형
func _build_formation() -> void:
	var area := _panel(Rect2(FORM_ORIGIN.x - 8, FORM_ORIGIN.y - 44, SLOT_SIZE.x * 3 + FORM_GAP.x * 2 + 16, SLOT_SIZE.y * 2 + FORM_GAP.y + 52))
	add_child(area)
	for c in 3:
		var t := _label(COL_NAMES[c] + ("  ▶ 적" if c == 2 else ""), 17, Color(1, 1, 1) if c != 2 else Color(1.0, 0.7, 0.55), true)
		t.position = Vector2(8 + c * (SLOT_SIZE.x + FORM_GAP.x), 8)
		t.size = Vector2(SLOT_SIZE.x, 24)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		area.add_child(t)
	for c in 3:
		for idx in 2:
			var key := SlotManager.make_key("ally", ROW_COLS[c], idx)
			var s := Control.new()
			s.position = _slot_pos(c, idx)
			s.size = SLOT_SIZE
			s.mouse_filter = Control.MOUSE_FILTER_STOP
			s.draw.connect(_draw_slot.bind(s, key))
			s.set_drag_forwarding(_drag_from_slot.bind(key), _can_drop_slot.bind(key), _drop_slot.bind(key))
			s.gui_input.connect(_slot_input.bind(key))
			var tex := TextureRect.new()
			tex.name = "Portrait"
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex.position = Vector2(10, 34)
			tex.size = Vector2(118, 118)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s.add_child(tex)
			add_child(s)
			slot_nodes[key] = s


func _slot_pos(col: int, idx: int) -> Vector2:
	return FORM_ORIGIN + Vector2(col * (SLOT_SIZE.x + FORM_GAP.x), idx * (SLOT_SIZE.y + FORM_GAP.y))


func _col_of(row: int) -> int:
	return ROW_COLS.find(row)


func _draw_slot(s: Control, key: String) -> void:
	var info := SlotManager.parse_key(key)
	var e := _entry_at(key)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	var cap := "%s %d" % [COL_NAMES[_col_of(int(info.row))], int(info.index) + 1]
	if e.is_empty():
		sb.bg_color = Color(0.1, 0.13, 0.16) if not _dragging else Color(0.12, 0.2, 0.26)
		sb.border_color = Color(0.4, 0.75, 1.0) if _dragging or selected_unit != "" else Color(0.25, 0.3, 0.36)
		sb.set_border_width_all(2)
		s.draw_style_box(sb, Rect2(Vector2.ZERO, s.size))
		s.draw_string(_font, Vector2(12, 24), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.65, 0.72))
		var msg := "여기에 놓기" if _dragging or selected_unit != "" else "비어 있음"
		s.draw_string(_font, Vector2(0, s.size.y * 0.55), msg, HORIZONTAL_ALIGNMENT_CENTER, s.size.x, 15, Color(0.55, 0.62, 0.7))
		return
	var uid := str(e.unit_id)
	var u := Game.ally_view(Game.find_ally(uid))
	sb.bg_color = Color(0.14, 0.18, 0.23)
	sb.border_color = C_ACCENT if uid == selected_unit else Color(0.45, 0.6, 0.75)
	sb.set_border_width_all(2)
	s.draw_style_box(sb, Rect2(Vector2.ZERO, s.size))
	s.draw_string(_font, Vector2(12, 24), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 0.95))
	s.draw_rect(Rect2(9, 33, 120, 120), Color(0.05, 0.06, 0.08))
	s.draw_string(_bold, Vector2(140, 54), u.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1))
	s.draw_string(_font, Vector2(140, 74), "%s · Lv%d" % [u.role, u.level], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.72, 0.77, 0.84))
	var st := Game.sortie_state(uid)
	if st.known:
		_mini_bar(s, Vector2(140, 86), "체력", float(st.hp) / maxf(1.0, float(st.max_hp)), C_HP)
		_mini_bar(s, Vector2(140, 104), "피로", float(st.fatigue) / 100.0, C_FATIGUE)
		_mini_bar(s, Vector2(140, 122), "친밀", float(st.affinity) / 100.0, C_AFFINITY)
	var y := 152.0
	for sid in st.statuses:
		var def := StatusCatalog.get_def(str(sid))
		s.draw_string(_font, Vector2(140, y), "● " + str(def.get("name", sid)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.5, 1.0, 0.6) if def.get("positive", false) else Color(1.0, 0.45, 0.4))
		y += 14


func _mini_bar(c: Control, at: Vector2, label: String, t: float, color: Color) -> void:
	c.draw_string(_font, at + Vector2(0, 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.74, 0.8))
	var r := Rect2(at + Vector2(28, 1), Vector2(72, 8))
	c.draw_rect(r, Color(0.05, 0.06, 0.08))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(t, 0.0, 1.0), r.size.y)), color)


func _slot_input(ev: InputEvent, key: String) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var e := _entry_at(key)
	if ev.button_index == MOUSE_BUTTON_RIGHT:
		if not e.is_empty():
			_remove(str(e.unit_id))
	elif ev.button_index == MOUSE_BUTTON_LEFT:
		if selected_unit != "":
			_place(selected_unit, key)
		elif not e.is_empty():
			selected_unit = str(e.unit_id)
			_show_info(selected_unit)
			_refresh()


func _drag_from_slot(_at: Vector2, key: String) -> Variant:
	var e := _entry_at(key)
	if e.is_empty():
		return null
	slot_nodes[key].set_drag_preview(_drag_preview(str(e.unit_id)))
	return {"sortie_unit": str(e.unit_id), "from": key}


func _can_drop_slot(_at: Vector2, data: Variant, _key: String) -> bool:
	return data is Dictionary and data.has("sortie_unit")


func _drop_slot(_at: Vector2, data: Variant, key: String) -> void:
	_place(str(data.sortie_unit), key)


func _drag_preview(uid: String) -> Control:
	var holder := Control.new()
	var t := TextureRect.new()
	t.texture = _portrait(Game.find_ally(uid))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.size = Vector2(84, 84)
	t.position = Vector2(-42, -42)
	t.modulate.a = 0.85
	holder.add_child(t)
	return holder


# ================================================================ 배치 규칙
## uid 를 칸 key 에: 빈 칸이면 이동/배치, 다른 대원이 있으면 — 끌어온 대원이 진형에 있었으면 자리 교환, 목록에서 왔으면 그 대원과 교체(빠진 대원은 목록으로)
func _place(uid: String, key: String) -> void:
	if Game.sortie_block_reason(uid) != "":
		return
	var info := SlotManager.parse_key(key)
	var me := _entry_for(uid)
	var occ := _entry_at(key)
	var said := [uid]
	if not occ.is_empty() and str(occ.unit_id) == uid:
		selected_unit = ""
		_refresh()
		return
	if occ.is_empty():
		if me.is_empty():
			Game.formation.append({"unit_id": uid, "row": int(info.row), "index": int(info.index)})
		else:
			me.row = int(info.row)
			me.index = int(info.index)
		_info("%s → %s %d" % [_name(uid), COL_NAMES[_col_of(int(info.row))], int(info.index) + 1])
	elif me.is_empty():
		Game.formation.erase(occ)
		_hush(str(occ.unit_id))
		Game.formation.append({"unit_id": uid, "row": int(info.row), "index": int(info.index)})
		_info("%s 투입, %s 대기로" % [_name(uid), _name(str(occ.unit_id))])
	else:
		var r: int = me.row
		var i: int = me.index
		me.row = occ.row
		me.index = occ.index
		occ.row = r
		occ.index = i
		said.append(str(occ.unit_id))
		_info("%s ↔ %s 자리 교환" % [_name(uid), _name(str(occ.unit_id))])
	selected_unit = ""
	_refresh()
	for s in said:
		_say(s)


func _remove(uid: String) -> void:
	var e := _entry_for(uid)
	if e.is_empty():
		return
	Game.formation.erase(e)
	_hush(uid)
	if selected_unit == uid:
		selected_unit = ""
	_info("%s 대기로" % _name(uid))
	_refresh()


func _entry_for(uid: String) -> Dictionary:
	for f in Game.formation:
		if str(f.unit_id) == uid:
			return f
	return {}


func _entry_at(key: String) -> Dictionary:
	var info := SlotManager.parse_key(key)
	for f in Game.formation:
		if int(f.row) == int(info.row) and int(f.index) == int(info.index):
			return f
	return {}


# ================================================================ 말풍선
## 배치된 대원 uid 가 지금 상태에 맞는 대사 한마디 (맞는 대사가 없으면 조용히)
func _say(uid: String) -> void:
	var e := _entry_for(uid)
	if e.is_empty() or bubble_layer == null:
		return
	var ctx := sortie_context(uid, int(e.row))
	var l := SortieLines.pick(lines, ctx, rng)
	if l.is_empty():
		return
	_hush(uid)
	var key := SlotManager.make_key("ally", int(e.row), int(e.index))
	var s: Control = slot_nodes[key]
	var b := SpeechBubble.new()
	bubble_layer.add_child(b)
	b.setup(SortieLines.format(str(l.text), l, ctx), _font, s.position + Vector2(69, 40), BUBBLE_LIFE, 230.0, 14)
	bubbles[uid] = b


func _hush(uid: String) -> void:
	var b: Variant = bubbles.get(uid)
	if b != null and is_instance_valid(b):
		b.queue_free()
	bubbles.erase(uid)


## 대사 조건 상황 (테스트에서도 씀)
static func sortie_context(uid: String, row: int) -> Dictionary:
	var st := Game.sortie_state(uid)
	var names := {}
	for u in Game.allies:
		names[u.id] = u.display_name
	var deployed := Game.formation.map(func(f): return str(f.unit_id))
	return SortieLines.make_context(uid, str(names.get(uid, uid)), float(st.affinity), float(st.fatigue),
		100.0 * float(st.hp) / maxf(1.0, float(st.max_hp)), st.statuses, row, deployed, names)


# ================================================================ 아래: 정보·버튼
func _build_bottom() -> void:
	var p := _panel(Rect2(468, 520, 796, 184))
	add_child(p)
	count_label = _label("", 18, Color(1, 1, 1), true)
	count_label.position = Vector2(16, 12)
	p.add_child(count_label)
	info_label = _label("", 14, Color(0.8, 0.9, 1.0))
	info_label.position = Vector2(16, 44)
	info_label.size = Vector2(430, 130)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(info_label)
	var col := VBoxContainer.new()
	col.position = Vector2(470, 10)
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	start_btn = _big_button("출정 (전투 시작)", Color(1.0, 0.5, 0.3), Vector2(310, 58), 20)
	start_btn.pressed.connect(func():
		if Game.formation.is_empty():
			return
		Game.restart_count = 0
		Game.start_battle())
	col.add_child(start_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var reset := _big_button("기본 편성", Color(0.5, 0.7, 0.9), Vector2(100, 44), 15)
	reset.pressed.connect(func():
		Game.reset_formation()
		Game.prune_formation()
		for k in bubbles.keys():
			_hush(k)
		_info("기본 편성으로")
		_refresh())
	row.add_child(reset)
	var clear := _big_button("모두 빼기", Color(0.7, 0.6, 0.5), Vector2(100, 44), 15)
	clear.pressed.connect(func():
		Game.formation.clear()
		for k in bubbles.keys():
			_hush(k)
		_info("진형을 비웠습니다")
		_refresh())
	row.add_child(clear)
	var back := _big_button("기지로" if Game.campaign else "메뉴", Color(0.6, 0.6, 0.6), Vector2(94, 44), 15)
	back.pressed.connect(func(): Game.go_menu())
	row.add_child(back)


func _show_info(uid: String) -> void:
	var u := Game.ally_view(Game.find_ally(uid))
	var t := "%s — %s Lv%d · HP %d · AP %d(+%d) · 속도 %d · %s" % [u.display_name, u.role, u.level, u.max_hp, u.max_ap, u.ap_recovery, u.speed,
		"원거리" if u.range_type == "ranged" else "근접"]
	var why := Game.sortie_block_reason(uid)
	if why != "":
		t += "\n출정 불가: " + why
	info_label.text = t


func _info(t: String) -> void:
	info_label.text = t


func _refresh() -> void:
	for k in slot_nodes:
		var s: Control = slot_nodes[k]
		var e := _entry_at(k)
		var tex: TextureRect = s.get_node("Portrait")
		tex.texture = null if e.is_empty() else _portrait(Game.find_ally(str(e.unit_id)))
		s.queue_redraw()
	for k in card_nodes:
		card_nodes[k].queue_redraw()
	var n := Game.formation.size()
	count_label.text = "배치 %d / 6" % n
	start_btn.disabled = n == 0
	start_btn.text = "출정 (전투 시작)" if n > 0 else "배치된 대원이 없습니다"
	if info_label.text == "":
		info_label.text = "대원 카드를 진형 칸으로 끌어다 놓으세요." if n < 6 else "진형이 가득 찼습니다. 대원끼리 끌어서 자리를 바꿀 수 있습니다."


# ================================================================ 작은 위젯
func _portrait(u: UnitData) -> Texture2D:
	return UnitArt.portrait(u.sprite_id, manifest) if u != null else null


func _name(uid: String) -> String:
	var u := Game.find_ally(uid)
	return u.display_name if u != null else uid


func _panel(r: Rect2) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color = Color(1, 1, 1), bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _big_button(text: String, color: Color, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _bold)
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.55)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate()
	h.bg_color = color.darkened(0.25)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	var d := sb.duplicate()
	d.bg_color = Color(0.12, 0.12, 0.13)
	d.border_color = Color(0.3, 0.3, 0.32)
	b.add_theme_stylebox_override("disabled", d)
	return b
