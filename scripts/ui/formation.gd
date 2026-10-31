extends Control
## 출정 대기 (편성) 화면.
## 왼쪽: 출정 가능한 대원 목록 (체력·피로·친밀도·상태 이상, 외부 의뢰 중이면 출정 불가로 흐리게)
## 오른쪽 위: 진형 — 후방 2 · 중간 2 · 전방 2 (오른쪽이 적 방향, 전장과 같은 방향)
## 조작: 목록에서 대원을 끌어다 진형 칸에 놓기 / 진형끼리 끌면 이동·자리 교환 / 진형에서 목록으로 끌거나 우클릭하면 빼기.
##       (클릭으로도 가능: 대원 클릭 → 칸 클릭)
## 배치된 대원은 지금 상태에 맞는 짧은 대사를 초상화 위 말풍선으로 말한다 (data/outgame/sortie_lines.json, Godot 에디터 '출정 대사' 탭).

const ROW_COLS := [2, 1, 0]   # 화면 왼쪽부터 후방(2) · 중간(1) · 전방(0)
const COL_NAMES := ["후방", "중간", "전방"]
const SLOT_SIZE := Vector2(252, 150)
const FORM_ORIGIN := Vector2(470, 171)
const FORM_GAP := Vector2(12, 10)
const CARD_SIZE := Vector2(412, 86)
## 출정 대기 v2 (레퍼런스 art_src/ui/sortie/ref_sortie.webp, 조각 assets/ui/sortie/)
const SO := "res://assets/ui/sortie/"
const CREAM := Color(0.95, 0.93, 0.86)
const M_CARD := Vector4(212, 30, 30, 30)   # 카드 그림: 왼쪽 초상화 칸까지는 늘리지 않음
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
var roster_panel: Control
var bubble_layer: Control
var _dragging := false
var _tex := {}   # 그리기에 쓰는 그림 (draw 안에서 load 만 하면 그리기가 끝나기 전에 풀려 흰색으로 나옴 → 붙잡아 둠)


func _t(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	lines = SortieLines.read()
	rng.seed = Game.seed_value if Game.cli.has("shot") else int(Time.get_ticks_usec())
	Game.prune_formation()
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.06)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var bgi := TextureRect.new()   # 어둡게 깐 기지 그림 (레퍼런스의 흐린 배경)
	bgi.texture = load("res://assets/ui/result/lose/bg_defeat.png")
	bgi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgi.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bgi.modulate = Color(0.32, 0.36, 0.36)
	bgi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgi)
	var stage_name := str(Game.data.stages.get(Game.stage_id, {}).get("name", Game.stage_id)) if Game.data != null else ""
	_build_header(stage_name)
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


## 위 줄: 왼쪽 로고 판 · 가운데 제목 판(제목 + 조작 안내) · 오른쪽 작전 판(OPERATION · 스테이지 + 안내 버튼) · 맨 아래 작은 글자
func _build_header(stage_name: String) -> void:
	var logo_p := _art_panel(Rect2(6, 8, 352, 70), SO + "panel_plain.png", Vector4(40, 40, 40, 40), 0.42)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/title/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(66, 17)
	logo.size = Vector2(190, 36)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_p.add_child(logo)
	logo_p.draw.connect(func():   # 왼쪽 갈매기 표시
		var c := Vector2(40, 35)
		for i in 2:
			var x := c.x - 10 + i * 10.0
			logo_p.draw_colored_polygon(PackedVector2Array([Vector2(x - 8, c.y - 12), Vector2(x, c.y - 12), Vector2(x + 8, c.y), Vector2(x, c.y + 12), Vector2(x - 8, c.y + 12), Vector2(x, c.y)]), Color(0.72, 0.68, 0.5)))
	var tp := _art_panel(Rect2(362, 8, 574, 70), SO + "header_left.png", Vector4(160, 50, 120, 50), 0.56)
	var title := _label("출정 대기" + (" — " + stage_name if stage_name != "" else ""), 24, C_ACCENT, true)
	title.position = Vector2(30, 10)
	tp.add_child(title)
	var hint := _label("대원을 끌어다 진형에 놓으세요 · 진형끼리 끌면 자리 교환 · 목록으로 끌거나 우클릭하면 빼기", 12, Color(0.78, 0.82, 0.8))
	hint.position = Vector2(30, 42)
	tp.add_child(hint)
	var op := _art_panel(Rect2(940, 10, 334, 66), SO + "header_right.png", Vector4(120, 40, 160, 40), 0.56)
	var op_no := (Game.data.stages.keys().find(Game.stage_id) + 1) if Game.data != null else 1
	var opl := _label("OPERATION %02d" % maxi(1, op_no), 12, Color(0.72, 0.7, 0.6))
	opl.position = Vector2(100, 18)
	opl.size = Vector2(150, 16)
	opl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	op.add_child(opl)
	var stl := _label(stage_name, 12, Color(0.85, 0.82, 0.7))
	stl.position = Vector2(100, 36)
	stl.size = Vector2(150, 16)
	stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	op.add_child(stl)
	var help := TextureButton.new()   # 안내 = 아래 정보 칸에 조작법
	help.texture_normal = load(SO + "btn_log.png")
	help.ignore_texture_size = true
	help.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	help.position = Vector2(268, 6)
	help.size = Vector2(54, 54)
	help.tooltip_text = "조작 안내"
	help.focus_mode = Control.FOCUS_NONE
	help.pressed.connect(func(): _info("대원 카드를 진형 칸으로 끌어다 놓기 · 진형끼리 끌면 자리 교환 · 목록으로 끌거나 우클릭하면 빼기 · 카드를 눌러 고른 뒤 칸을 눌러도 배치"))
	op.add_child(help)
	for spec in [[Vector2(52, 703), "ZEROSUM   TACTICAL  OPERATIONS"], [Vector2(1010, 703), "SIX TO MOVE.  NOTHING TO WASTE."]]:
		var f := _label(spec[1], 11, Color(0.45, 0.48, 0.44), true)
		f.position = spec[0]
		add_child(f)


## 그림 판 (9칸 늘리기): rect 에 Control 을 만들어 그 판을 그림
func _art_panel(r: Rect2, path: String, m: Vector4, k: float) -> Control:
	var c := Control.new()
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): UiNine.draw(c, path, m, Rect2(Vector2.ZERO, c.size), k))
	add_child(c)
	return c


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
	roster_panel = _art_panel(Rect2(8, 84, 450, 612), SO + "panel_a.png", Vector4(160, 60, 160, 60), 0.5)
	roster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	roster_panel.set_drag_forwarding(Callable(), _can_drop_roster, _drop_roster)
	var avail := Game.allies.filter(func(u): return Game.sortie_block_reason(u.id) == "").size()
	var head := _label("출정 가능 대원 %d / %d" % [avail, Game.allies.size()], 19, CREAM, true)
	head.position = Vector2(26, 14)
	roster_panel.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(19, 50)
	scroll.size = Vector2(416, 552)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	roster_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
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
		tex.position = Vector2(17, 10)
		tex.size = Vector2(70, 68)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tex)
		box.add_child(card)
		card_nodes[uid] = card


func _draw_card(card: Control, uid: String) -> void:
	var u := Game.ally_view(Game.find_ally(uid))
	var blocked := Game.sortie_block_reason(uid)
	var placed := not _entry_for(uid).is_empty()
	# 카드 그림 (고른 대원 = 금빛 왼쪽 테두리 카드, 그 밖 = 보통 카드 · 진형에 있으면 조금 밝게)
	var k := card.size.y / 197.0
	var mod := Color(1.12, 1.12, 1.08) if placed else Color.WHITE
	if blocked != "":
		mod = Color(0.6, 0.6, 0.62)
	UiNine.draw(card, SO + ("card_gold.png" if uid == selected_unit else "card.png"), M_CARD, Rect2(Vector2.ZERO, card.size), k, mod)
	var nc := CREAM if blocked == "" else Color(0.55, 0.55, 0.58)
	var tx := 104.0
	card.draw_string(_bold, Vector2(tx, 25), u.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, nc)
	var nw := _bold.get_string_size(u.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	card.draw_string(_font, Vector2(tx + 8 + nw, 25), "%s · Lv%d" % [u.role, u.level], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.76, 0.7))
	var st := Game.sortie_state(uid)
	if st.known:
		_bar(card, Vector2(tx, 36), "체력", float(st.hp) / maxf(1.0, float(st.max_hp)), "%d/%d" % [floori(float(st.hp)), int(st.max_hp)], "bar_red.png")
		_bar(card, Vector2(tx, 52), "피로", float(st.fatigue) / 100.0, "%d" % roundi(float(st.fatigue)), "bar_orange.png")
		_bar(card, Vector2(tx, 68), "친밀", float(st.affinity) / 100.0, "%d" % roundi(float(st.affinity)), "bar_pink.png")
	else:
		card.draw_string(_font, Vector2(tx, 54), "HP %d · AP %d(+%d) · 속도 %d" % [u.max_hp, u.max_ap, u.ap_recovery, u.speed], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.82, 0.84, 0.8))
		card.draw_string(_font, Vector2(tx, 74), "(기지 상태 없음 — 전투 테스트)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.58, 0.6, 0.56))
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
	var tw := _bold.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var tr := Rect2(card.size.x - 22 - tw - 18, 8, tw + 18, 24)   # 자리 꼬리표 (작은 판)
	UiNine.draw(card, SO + "tag_plate.png", Vector4(30, 30, 30, 30), tr, 0.3)
	card.draw_string(_bold, tr.position + Vector2(9, 17), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
	var x := card.size.x - 22.0
	for sid in st.statuses:
		var def := StatusCatalog.get_def(str(sid))
		var nm := str(def.get("name", sid))
		var w := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12
		x -= w
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color(0.25, 0.5, 0.3) if def.get("positive", false) else Color(0.55, 0.16, 0.16)
		chip.set_corner_radius_all(4)
		card.draw_style_box(chip, Rect2(x, 38, w, 18))
		card.draw_string(_font, Vector2(x + 6, 52), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))
		x -= 4
	if blocked != "":
		card.draw_rect(Rect2(Vector2(6, 6), card.size - Vector2(12, 12)), Color(0, 0, 0, 0.3))


## 막대 한 줄: 이름 · 막대(그림 홈 + 색 막대 그림) · 값
func _bar(c: Control, at: Vector2, label: String, t: float, value: String, fill: String, w: float = 170.0, show_value: bool = true) -> void:
	c.draw_string(_font, at + Vector2(0, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.74))
	var r := Rect2(at + Vector2(32, 1), Vector2(w, 12))
	UiNine.draw(c, SO + "bar_track.png", Vector4(18, 18, 18, 18), r, 0.25)
	var fw := (r.size.x - 4) * clampf(t, 0.0, 1.0)
	if fw > 1.0:
		c.draw_texture_rect(_t(SO + fill), Rect2(r.position + Vector2(2, 2), Vector2(fw, r.size.y - 4)), false)
	if show_value:
		c.draw_string(_font, at + Vector2(40 + w, 11), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CREAM)


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
	_art_panel(Rect2(FORM_ORIGIN.x - 10, FORM_ORIGIN.y - 10, SLOT_SIZE.x * 3 + FORM_GAP.x * 2 + 20, SLOT_SIZE.y * 2 + FORM_GAP.y + 20), SO + "panel_b.png", Vector4(160, 60, 160, 60), 0.4)
	# 열 머리 (갈매기 판): 후방 지원·회복 · 중간 화력·교전 · 전방 돌파·근접 + ▶ 적 방향 ≫
	var subs := ["지원 · 회복", "화력 · 교전", "돌파 · 근접"]
	for c in 3:
		var hx := FORM_ORIGIN.x - 10 + c * (SLOT_SIZE.x + FORM_GAP.x)
		var hw := SLOT_SIZE.x + (20.0 if c == 2 else 10.0)
		var hp := _art_panel(Rect2(hx, 96, hw, 64), SO + "lane_header.png", Vector4(40, 40, 110, 40), 0.55)
		var cx := hw * (0.32 if c == 2 else 0.45)
		var t := _label(COL_NAMES[c], 19, CREAM, true)
		t.position = Vector2(cx - 60, 9)
		t.size = Vector2(120, 24)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp.add_child(t)
		var st := _label(subs[c], 12, Color(0.75, 0.74, 0.66))
		st.position = Vector2(cx - 60, 33)
		st.size = Vector2(120, 18)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp.add_child(st)
		if c == 2:
			var ar := TextureRect.new()
			ar.texture = load(SO + "arrow.png")
			ar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ar.position = Vector2(hw * 0.6, 20)
			ar.size = Vector2(14, 20)
			ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hp.add_child(ar)
			var el := _label("적 방향", 15, Color(1.0, 0.55, 0.35), true)
			el.position = Vector2(hw * 0.6 + 18, 19)
			hp.add_child(el)
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
			tex.position = Vector2(14, 22)
			tex.size = Vector2(96, 112)
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
	var cap := "%s %d" % [COL_NAMES[_col_of(int(info.row))], int(info.index) + 1]
	var k := 0.5
	var target := _dragging or selected_unit != ""
	if e.is_empty():
		UiNine.draw(s, SO + "card.png", M_CARD, Rect2(Vector2.ZERO, s.size), k, Color(0.7, 0.72, 0.7, 0.85))
		s.draw_string(_font, Vector2(120, 30), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.62))
		var msg := "여기에 놓기" if target else "비어 있음"
		s.draw_string(_bold, Vector2(112, s.size.y * 0.58), msg, HORIZONTAL_ALIGNMENT_CENTER, s.size.x - 120, 15, Color(0.85, 0.75, 0.4) if target else Color(0.6, 0.62, 0.58))
		if target:
			_corners(s)
		return
	var uid := str(e.unit_id)
	var u := Game.ally_view(Game.find_ally(uid))
	UiNine.draw(s, SO + ("card_gold.png" if uid == selected_unit else "card.png"), M_CARD, Rect2(Vector2.ZERO, s.size), k)
	var tx := 120.0
	s.draw_string(_bold, Vector2(tx, 36), u.display_name, HORIZONTAL_ALIGNMENT_LEFT, s.size.x - tx - 10, 19, CREAM)
	s.draw_string(_font, Vector2(tx, 56), "%s · Lv%d" % [u.role, u.level], HORIZONTAL_ALIGNMENT_LEFT, s.size.x - tx - 10, 12, Color(0.75, 0.76, 0.7))
	var st := Game.sortie_state(uid)
	if st.known:
		_bar(s, Vector2(tx, 70), "체력", float(st.hp) / maxf(1.0, float(st.max_hp)), "%d/%d" % [floori(float(st.hp)), int(st.max_hp)], "bar_red.png", 48)
		_bar(s, Vector2(tx, 88), "피로", float(st.fatigue) / 100.0, "%d" % roundi(float(st.fatigue)), "bar_orange.png", 48)
		_bar(s, Vector2(tx, 106), "친밀", float(st.affinity) / 100.0, "%d" % roundi(float(st.affinity)), "bar_pink.png", 48)
	var y := 136.0
	for sid in st.statuses:
		var def := StatusCatalog.get_def(str(sid))
		s.draw_string(_font, Vector2(tx, y), "● " + str(def.get("name", sid)), HORIZONTAL_ALIGNMENT_LEFT, s.size.x - tx - 10, 12,
			Color(0.5, 1.0, 0.6) if def.get("positive", false) else Color(1.0, 0.45, 0.4))
		y += 13
	if uid == selected_unit:
		_corners(s)


## 금색 모서리 표시 (고른 칸 · 놓을 수 있는 칸)
func _corners(c: Control) -> void:
	var sz := 18.0
	var r := Rect2(Vector2(-2, -2), c.size + Vector2(4, 4))
	c.draw_texture_rect(_t(SO + "corner_tl.png"), Rect2(r.position, Vector2(sz, sz)), false)
	c.draw_texture_rect(_t(SO + "corner_tr.png"), Rect2(Vector2(r.end.x - sz, r.position.y), Vector2(sz, sz)), false)
	c.draw_texture_rect(_t(SO + "corner_bl.png"), Rect2(Vector2(r.position.x, r.end.y - sz), Vector2(sz, sz)), false)
	c.draw_texture_rect(_t(SO + "corner_br.png"), Rect2(r.end - Vector2(sz, sz), Vector2(sz, sz)), false)


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
	b.setup(SortieLines.format(str(l.text), l, ctx), _font, s.position + Vector2(62, 26), BUBBLE_LIFE, 230.0, 14)
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
	# 왼쪽: 안내 판 (속이 빈 틀 + 어두운 바탕), 오른쪽: 버튼 판
	var mp := Rect2(460, 512, 440, 184)
	var under := ColorRect.new()
	under.color = Color(0.06, 0.08, 0.08, 0.92)
	under.position = mp.position + Vector2(8, 8)
	under.size = mp.size - Vector2(16, 16)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)
	var p := _art_panel(mp, SO + "frame_hollow.png", Vector4(160, 60, 160, 60), 0.4)
	count_label = _label("", 24, CREAM, true)
	count_label.position = Vector2(24, 18)
	p.add_child(count_label)
	info_label = _label("", 14, Color(0.85, 0.86, 0.8))
	info_label.position = Vector2(24, 58)
	info_label.size = Vector2(392, 110)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(info_label)
	var bp := _art_panel(Rect2(904, 512, 362, 184), SO + "panel_plain.png", Vector4(40, 40, 40, 40), 0.42)
	var col := VBoxContainer.new()
	col.position = Vector2(14, 14)
	col.add_theme_constant_override("separation", 10)
	bp.add_child(col)
	start_btn = _art_button("출정 (전투 시작)  ▶", "btn_orange.png", Vector2(334, 78), 22)
	start_btn.pressed.connect(func():
		if Game.formation.is_empty():
			return
		Game.restart_count = 0
		Game.start_battle())
	col.add_child(start_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var reset := _art_button("기본 편성", "btn_blue.png", Vector2(108, 64), 16)
	reset.pressed.connect(func():
		Game.reset_formation()
		Game.prune_formation()
		for k in bubbles.keys():
			_hush(k)
		_info("기본 편성으로")
		_refresh())
	row.add_child(reset)
	var clear := _art_button("모두 빼기", "btn_brown.png", Vector2(108, 64), 16)
	clear.pressed.connect(func():
		Game.formation.clear()
		for k in bubbles.keys():
			_hush(k)
		_info("진형을 비웠습니다")
		_refresh())
	row.add_child(clear)
	var back := _art_button("기지로" if Game.campaign else "메뉴", "btn_gray.png", Vector2(102, 64), 16)
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
	start_btn.text = "출정 (전투 시작)  ▶" if n > 0 else "배치된 대원이 없습니다"
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


## 그림 버튼 (주황 = 출정 · 파랑 = 기본 편성 · 갈색 = 모두 빼기 · 회색 = 기지로): 마우스 올림 = 밝게, 누름 = 어둡게, 못 누름 = 흐리게
func _art_button(text: String, file: String, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _bold)
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.58))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.04))
	b.add_theme_constant_override("outline_size", 4)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiNine.behind(b, SO + file, Vector4(60, 50, 60, 50), 0.4, func() -> Color:
		match b.get_draw_mode():
			BaseButton.DRAW_HOVER: return Color(1.18, 1.15, 1.1)
			BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED: return Color(0.82, 0.82, 0.8)
			BaseButton.DRAW_DISABLED: return Color(0.55, 0.55, 0.55)
		return Color.WHITE)
	return b


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
