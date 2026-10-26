class_name OutgameHud
extends Control
## 기지 화면 HUD 와 창들. 표시와 명령 전달만 하고 규칙은 BaseSim 에 맡긴다 (03_HANDOFF 2절).
## 위: 날짜·시각·배속 / 달러·미지급·결산까지 / 위생·점검 / 버튼(의뢰·무기고·원장·저장·출전·타이틀)
## 창(모달)이 열려 있으면 시계가 멈춘다 [임시 규칙].

const PANEL_BG := Color(0.05, 0.07, 0.10, 0.92)
const PANEL_LINE := Color(0.32, 0.46, 0.58)
const GOOD := Color(0.45, 1.0, 0.6)
const BAD := Color(1.0, 0.42, 0.35)
const GOLD := Color(1.0, 0.85, 0.35)
const HP_COL := Color(0.95, 0.25, 0.25)
const FATIGUE_COL := Color(0.62, 0.55, 1.0)
const AFFINITY_COL := Color(1.0, 0.93, 0.6)   # 친밀도 = 파스텔 노랑

var hub: Node            # BaseHub
var sim: BaseSim
var font: Font
var bold: Font
var manifest: Dictionary = {}

var date_label: Label
var cash_label: Label
var info_label: Label
var speed_buttons: Array[Button] = []
var toast: Label
var banner: Label
var log_panel: PanelContainer
var log_label: RichTextLabel
var debug_panel: PanelContainer
var debug_label: Label
var zoom_label: Label
var battle_bar: PanelContainer
var battle_label: Label
var battle_skip: Button
var _modals: Array[Control] = []
var _queue: Array[Callable] = []
var _toast_t := 0.0


func setup(p_hub: Node, p_sim: BaseSim) -> void:
	hub = p_hub
	sim = p_sim
	font = load("res://assets/fonts/Pretendard-Medium.ttf")
	bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	if f != null:
		manifest = JSON.parse_string(f.get_as_text())
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top()
	_build_log()
	_build_zoom()
	_build_debug()
	_build_battle_bar()
	toast = _label("", 20, GOLD, true)
	toast.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	toast.position = Vector2(340, 92)
	toast.size = Vector2(600, 30)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	add_child(toast)
	banner = _label("", 19, Color(1, 0.95, 0.5), true)
	banner.position = Vector2(240, 124)
	banner.size = Vector2(800, 30)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	add_child(banner)


# ================================================================ 공통 위젯
func _label(text: String, size: int, col: Color = Color(1, 1, 1), outline: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", bold if size >= 20 else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _panel_style(bg: Color = PANEL_BG, line: Color = PANEL_LINE, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _button(text: String, col: Color = Color(0.45, 0.7, 0.9), size: int = 15, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	var sb := _panel_style(col.darkened(0.62), col, 6)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate()
	h.bg_color = col.darkened(0.3)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	var dis := sb.duplicate()
	dis.bg_color = Color(0.12, 0.12, 0.14)
	dis.border_color = Color(0.3, 0.3, 0.32)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.52))
	b.focus_mode = FOCUS_NONE
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	return b


func _hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


# ================================================================ 위쪽 바
func _build_top() -> void:
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _panel_style())
	left.position = Vector2(10, 8)
	add_child(left)
	var lv := _vbox(2)
	left.add_child(lv)
	var row := _hbox(10)
	lv.add_child(row)
	date_label = _label("", 22, Color(1, 1, 1))
	row.add_child(date_label)
	for sp in [[0, "정지"], [1, "1x"], [4, "4x"], [16, "16x"]]:
		var b := _button(sp[1], Color(0.45, 0.7, 0.9), 14, 44)
		var v: int = sp[0]
		b.pressed.connect(func(): hub.set_speed(v))
		row.add_child(b)
		speed_buttons.append(b)
	var row2 := _hbox(16)
	lv.add_child(row2)
	cash_label = _label("", 20, GOLD)
	row2.add_child(cash_label)
	info_label = _label("", 14, Color(0.85, 0.92, 1.0))
	row2.add_child(info_label)

	var right := _hbox(6)
	right.position = Vector2(0, 10)
	right.set_anchors_preset(PRESET_TOP_RIGHT)
	add_child(right)
	var specs := [["의뢰", Color(0.45, 0.7, 0.9), func(): open_contracts("")], ["무기고", Color(0.45, 0.7, 0.9), func(): open_armory()],
		["원장", Color(0.45, 0.7, 0.9), func(): open_ledger()], ["저장", Color(0.45, 0.9, 0.6), func(): hub.save_now()],
		["전투 출전", Color(1.0, 0.5, 0.3), func(): open_sortie()], ["타이틀", Color(0.6, 0.6, 0.65), func(): hub.to_title()]]
	for s in specs:
		var b := _button(s[0], s[1], 16 if s[0] == "전투 출전" else 14)
		b.pressed.connect(s[2])
		right.add_child(b)
	right.position.x = 1280 - 10 - right.get_combined_minimum_size().x
	right.resized.connect(func(): right.position.x = 1280 - 10 - right.size.x)


func _build_log() -> void:
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.05, 0.08, 0.78), Color(0.25, 0.32, 0.4)))
	log_panel.position = Vector2(10, 628)
	log_panel.custom_minimum_size = Vector2(470, 84)
	log_panel.mouse_filter = MOUSE_FILTER_PASS
	add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.add_theme_font_override("normal_font", font)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_label.scroll_following = true
	log_label.mouse_filter = MOUSE_FILTER_PASS
	log_panel.add_child(log_label)
	var hint := _label("좌클릭 대원: 대화 · 우클릭: 지시 · 말풍선: 엿듣기 · 검은 방: 해금 · WASD 이동 · 휠/핀치/Q·E 확대 · F1", 12, Color(0.8, 0.88, 0.95), true)
	hint.position = Vector2(500, 696)
	add_child(hint)


## 오른쪽 아래 확대/축소: − 배율 + (휠·핀치·Q/E·+/- 키도 됨, 0 = 기본)
func _build_zoom() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.05, 0.08, 0.8), Color(0.25, 0.32, 0.4)))
	add_child(p)
	var h := _hbox(6)
	p.add_child(h)
	var minus := _button("－", Color(0.45, 0.7, 0.9), 18, 40)
	minus.tooltip_text = "축소 (휠 아래 · Q · -)"
	minus.pressed.connect(func(): hub.zoom_step(-1))
	h.add_child(minus)
	zoom_label = _label("100%", 15, Color(0.9, 0.95, 1.0))
	zoom_label.custom_minimum_size.x = 56
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(zoom_label)
	var plus := _button("＋", Color(0.45, 0.7, 0.9), 18, 40)
	plus.tooltip_text = "확대 (휠 위 · E · +)"
	plus.pressed.connect(func(): hub.zoom_step(1))
	h.add_child(plus)
	p.position = Vector2(1280 - 10 - p.get_combined_minimum_size().x, 640)


## 전투 발생 띠 (전투가 끝날 때까지 기지 시계 정지)
func _build_battle_bar() -> void:
	battle_bar = PanelContainer.new()
	battle_bar.add_theme_stylebox_override("panel", _panel_style(Color(0.35, 0.03, 0.05, 0.95), Color(1.0, 0.35, 0.3), 8))
	battle_bar.position = Vector2(330, 112)
	battle_bar.visible = false
	add_child(battle_bar)
	var h := _hbox(12)
	battle_bar.add_child(h)
	battle_label = _label("", 19, Color(1, 0.92, 0.85))
	h.add_child(battle_label)
	var go := _button("전투 배치로", Color(1.0, 0.5, 0.3), 17, 130)
	go.pressed.connect(func(): hub.sortie(str(sim.pending_battle.get("stage", ""))))
	h.add_child(go)
	battle_skip = _button("넘기기", Color(0.6, 0.6, 0.65), 15, 80)
	battle_skip.pressed.connect(func():
		if sim.skip_pending_battle():
			show_toast("전투를 넘겼습니다"))
	h.add_child(battle_skip)


func _update_battle_bar() -> void:
	var p := sim.pending_battle
	battle_bar.visible = not p.is_empty()
	if p.is_empty():
		return
	var st: Dictionary = Game.data.stages.get(str(p.get("stage", "")), {}) if Game.data != null else {}
	battle_label.text = "⚠ 전투 발생 — %s · %s (%s)  기지 시간 정지" % [p.get("name", ""), st.get("name", p.get("stage", "")), str(p.get("label", "")).right(5)]
	battle_skip.visible = p.get("allow_skip", false)
	battle_bar.position.x = (1280.0 - battle_bar.size.x) * 0.5


## 게이지 한 줄: 이름 · 막대 · 값
func _gauge(label: String, value: float, max_v: float, col: Color, text: String = "") -> HBoxContainer:
	var h := _hbox(8)
	var l := _label(label, 14, Color(0.85, 0.9, 1))
	l.custom_minimum_size.x = 54
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max_v
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 14)
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.13, 0.17)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	h.add_child(bar)
	h.add_child(_label(text if text != "" else "%d" % roundi(value), 14, col.lightened(0.2)))
	return h


## 캐릭터 클릭 카드: 체력 · 피로도 · 친밀도(파스텔 노랑, 피로도 아래) · 상태 이상 — 아웃게임에서만
func _status_card(npc_id: String) -> VBoxContainer:
	var n: NpcAgent = sim.npcs[npc_id]
	var cs := sim.cstate(n)
	var v := _vbox(3)
	var mx := sim.char_max_hp(n.character_id)
	v.add_child(_gauge("체력", float(cs.hp), mx, HP_COL, "%d / %d" % [floori(float(cs.hp)), mx]))
	var fat := float(cs.fatigue)
	v.add_child(_gauge("피로도", fat, 100.0, FATIGUE_COL, "%d%s" % [roundi(fat), "  (지침)" if fat >= 80 else ""]))
	v.add_child(_gauge("친밀도", float(cs.affinity), 100.0, AFFINITY_COL))
	var sts: Array = cs.statuses
	if not sts.is_empty():
		var names := PackedStringArray()
		for sid in sts:
			names.append(StatusCatalog.get_def(str(sid)).name)
		v.add_child(_label("상태 이상: %s — 의무실 치료 필요 (우클릭 → 의무실로)" % ", ".join(names), 13, BAD))
	return v


func _build_debug() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.04, 0.10, 0.94), Color(0.8, 0.4, 0.9)))
	debug_panel.position = Vector2(930, 60)
	debug_panel.custom_minimum_size = Vector2(340, 0)
	debug_panel.visible = false
	add_child(debug_panel)
	var v := _vbox(6)
	debug_panel.add_child(v)
	v.add_child(_label("디버그 (F1)", 16, Color(1, 0.8, 1)))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var acts := [["+1시간", func(): hub.debug_skip(60)], ["다음 날", func(): hub.debug_skip(-1)], ["다음 주", func(): hub.debug_skip(-7)],
		["다음 달", func(): hub.debug_skip(-30)], ["오염 추가", func(): hub.debug_dirt()], ["점검 지금", func(): sim.debug_inspect_now()],
		["달러 +100", func(): sim.ledger.cash += 100], ["전투 발생", func(): hub.debug_battle()], ["저장 지우기", func(): hub.debug_delete_save()],
		["닫기", func(): debug_panel.visible = false]]
	for a in acts:
		var b := _button(a[0], Color(0.8, 0.45, 0.9), 13, 100)
		b.pressed.connect(a[1])
		g.add_child(b)
	debug_label = _label("", 12, Color(0.92, 0.88, 0.96))
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.custom_minimum_size.x = 316
	v.add_child(debug_label)


func toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible


# ================================================================ 매 프레임 갱신
func refresh(delta: float) -> void:
	date_label.text = sim.clock.label()
	for i in speed_buttons.size():
		speed_buttons[i].modulate = Color(1, 1, 0.5) if [0, 1, 4, 16][i] == hub.speed else Color(1, 1, 1)
	cash_label.text = "$%d" % sim.ledger.cash
	_update_battle_bar()
	zoom_label.text = "%d%%" % hub.zoom_percent()
	var left := sim.minutes_to_settlement()
	var ins := sim.inspection_this_month()
	var ins_text := "이번 달 장군 점검: %s" % ("완료 (%s, %d점)" % [ins.grade, roundi(float(ins.score))] if ins.get("done", false) else "예정 (날짜 모름)")
	var nb := sim.next_battle()
	var nb_text := "다음 전투 %s" % sim.clock.label(int(nb.minute)).right(14) if not nb.is_empty() else "예정 전투 없음"
	info_label.text = "미지급 $%d · 결산까지 %d일 %d시간 · 식재료 %d끼  |  위생 %d점 · %s  |  %s" % [sim.ledger.pending_total(),
		floori(left / 1440.0), floori(fmod(left, 1440.0) / 60.0), sim.food, roundi(sim.hygiene_score()), ins_text.replace("이번 달 장군 점검", "점검"), nb_text]
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
	if debug_panel.visible:
		var lines := PackedStringArray()
		for id in sim.data.npc_order:
			var n: NpcAgent = sim.npcs[id]
			lines.append("%s: %s @%s → %s (%s)" % [n.name, n.state_name(), sim.data.facility_name(n.facility), sim.data.facility_name(n.dest), n.dest_reason])
		var ii := sim.inspection_this_month()
		if not ii.is_empty():
			lines.append("점검 예정: %s%s" % [sim.clock.label(int(ii.minute)), " (완료)" if ii.done else ""])
		lines.append("작업실: %s" % ("비어 있음" if sim.workshop.is_empty() else "%s 남은 %d분" % [sim.workshop.kind, sim.workshop.remaining]))
		debug_label.text = "\n".join(lines)


func refresh_log() -> void:
	var lines: Array = sim.log_lines.slice(maxi(0, sim.log_lines.size() - 40))
	log_label.text = "\n".join(lines)


func show_toast(text: String, col: Color = GOLD) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", col)
	_toast_t = 3.0
	toast.modulate.a = 1.0


func set_banner(text: String) -> void:
	banner.text = text
	banner.visible = text != ""


# ================================================================ 모달 창
func modal_open() -> bool:
	return not _modals.is_empty()


## 다른 창이 열려 있으면 닫힌 뒤에 띄움 (결산·점검 알림이 겹칠 때)
func enqueue(open_fn: Callable) -> void:
	if modal_open():
		_queue.append(open_fn)
	else:
		open_fn.call()


func close_top() -> void:
	if _modals.is_empty():
		return
	var m: Control = _modals.pop_back()
	if m.has_meta("on_close"):
		(m.get_meta("on_close") as Callable).call()
	m.queue_free()
	if _modals.is_empty() and not _queue.is_empty():
		var fn: Callable = _queue.pop_front()
		fn.call_deferred()


func close_all() -> void:
	while not _modals.is_empty():
		close_top()


## {root, body}. 화면을 어둡게 덮고 가운데 창
func _window(title: String, w: float, on_close: Callable = Callable()) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.mouse_filter = MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(dim)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT: close_top())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.12, 0.98), PANEL_LINE, 10))
	panel.custom_minimum_size = Vector2(w, 0)
	root.add_child(panel)
	var v := _vbox(8)
	panel.add_child(v)
	var head := _hbox(8)
	v.add_child(head)
	var t := _label(title, 21, Color(1, 0.95, 0.75))
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	var x := _button("닫기 (Esc)", Color(0.6, 0.6, 0.65), 13)
	x.pressed.connect(close_top)
	head.add_child(x)
	var body := _vbox(8)
	v.add_child(body)
	if on_close.is_valid():
		root.set_meta("on_close", on_close)
	_modals.append(root)
	panel.resized.connect(func(): panel.position = (Vector2(1280, 720) - panel.size) * 0.5)
	return {"root": root, "body": body, "panel": panel}


func _scroll(body: Control, h: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var v := _vbox(6)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _portrait_rect(sprite: String, size: float = 72.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if sprite != "":
		tr.texture = UnitArt.portrait(sprite, manifest)
	return tr


func _sprite_of(speaker: String) -> String:
	return str(sim.data.npcs.get(speaker, {}).get("sprite", ""))


# ---------------------------------------------------------------- 대화 (직접 대화 / 요청)
func open_dialogue(npc_id: String) -> void:
	var d := sim.begin_dialogue(npc_id)
	if d.is_empty():
		return
	var req: Dictionary = d.request
	var title := "%s와(과) 대화" % sim.data.npc_name(npc_id) if req.is_empty() else "%s의 요청 !" % sim.data.npc_name(npc_id)
	var win := _window(title, 640, func(): sim.end_dialogue(npc_id))
	var body: VBoxContainer = win.body
	var row := _hbox(12)
	body.add_child(row)
	var por := _portrait_rect(_sprite_of(npc_id), 96)
	row.add_child(por)
	var col := _vbox(6)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(col)
	var who := _label("", 17, GOLD)
	col.add_child(who)
	var txt := _label("", 17)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(480, 64)
	col.add_child(txt)
	body.add_child(_status_card(npc_id))
	body.add_child(_gift_row(npc_id))
	var btns := _hbox(8)
	btns.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(btns)
	var lines: Array = d.lines if not (d.lines as Array).is_empty() else [{"speaker": npc_id, "text": "(대사 없음)"}]
	var state := {"i": 0}
	var show_line := func():
		var ln: Dictionary = lines[state.i]
		who.text = sim.data.npc_name(ln.speaker)
		txt.text = ln.text
		por.texture = UnitArt.portrait(_sprite_of(ln.speaker), manifest) if _sprite_of(ln.speaker) != "" else por.texture
	show_line.call()
	var next := _button("다음", Color(0.45, 0.7, 0.9), 15, 90)
	btns.add_child(next)
	var accept := _button("수락", Color(0.4, 0.9, 0.5), 15, 90)
	var later := _button("나중에", Color(0.6, 0.6, 0.65), 15, 90)
	var close := _button("닫기", Color(0.6, 0.6, 0.65), 15, 90)
	for b in [accept, later, close]:
		btns.add_child(b)
		b.visible = false
	var at_end := func():
		next.visible = false
		accept.visible = not req.is_empty()
		later.visible = not req.is_empty()
		close.visible = req.is_empty()
	if lines.size() <= 1:
		at_end.call()
	next.pressed.connect(func():
		state.i += 1
		show_line.call()
		if state.i >= lines.size() - 1:
			at_end.call())
	later.pressed.connect(close_top)
	close.pressed.connect(close_top)
	accept.pressed.connect(func():
		var r := sim.accept_request(req.id)
		show_toast(r.msg, GOOD if r.ok else BAD)
		var ok_lines: Array = r.get("lines", [])
		if not ok_lines.is_empty():
			who.text = sim.data.npc_name(ok_lines[0].speaker)
			txt.text = ok_lines[0].text
		accept.visible = false
		later.visible = false
		close.visible = true)


## 선물하기 (PX 에서 산 것)
func _gift_row(npc_id: String) -> HBoxContainer:
	var h := _hbox(8)
	var owned := sim.data.px_order.filter(func(g): return int(sim.gifts.get(g, 0)) > 0)
	if owned.is_empty():
		h.add_child(_label("선물: 없음 (PX 에서 구매)", 13, Color(0.7, 0.75, 0.85)))
		return h
	h.add_child(_label("선물하기", 14, AFFINITY_COL))
	for g in owned:
		var it: Dictionary = sim.data.px_items[g]
		var b := _button("%s ×%d" % [it.name, int(sim.gifts[g])], AFFINITY_COL.darkened(0.2), 13)
		b.pressed.connect(func():
			var r := sim.give_gift(npc_id, g)
			show_toast(r.msg, AFFINITY_COL if r.ok else BAD)
			close_top()
			open_dialogue(npc_id))
		h.add_child(b)
	return h


# ---------------------------------------------------------------- 엿듣기
func open_overhear(key: String) -> void:
	var o := sim.overhear(key)
	if o.is_empty():
		return
	var win := _window("엿듣기 — " + str(o.title), 680)
	var body: VBoxContainer = win.body
	if str(o.story) != "":
		body.add_child(_label("스토리 관련 대화 (%s)" % o.story, 14, Color(1, 0.6, 0.9)))
	for ln in o.lines:
		var row := _hbox(10)
		body.add_child(row)
		row.add_child(_portrait_rect(_sprite_of(ln.speaker), 52))
		var col := _vbox(2)
		row.add_child(col)
		col.add_child(_label(sim.data.npc_name(ln.speaker), 15, GOLD))
		var t := _label(ln.text, 16)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 560
		col.add_child(t)


# ---------------------------------------------------------------- 해금
func open_unlock(fid: String) -> void:
	var f: Dictionary = sim.data.facilities[fid]
	var win := _window("잠긴 시설 — %s" % sim.data.facility_name(fid), 460)
	var body: VBoxContainer = win.body
	body.add_child(_label("%s · 기능: %s" % [sim.data.floor_name(f.floor), f.tag], 15, Color(0.85, 0.9, 1)))
	if str(f.desc) != "":
		body.add_child(_label(f.desc, 14, Color(0.75, 0.8, 0.9)))
	body.add_child(_label("해금 비용  $%d" % f.cost, 24, GOLD))
	var short: int = int(f.cost) - sim.ledger.cash
	body.add_child(_label("보유 $%d" % sim.ledger.cash + ("  —  $%d 부족" % short if short > 0 else ""), 16, BAD if short > 0 else GOOD))
	var btns := _hbox(8)
	btns.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(btns)
	var ok := _button("해금", Color(1.0, 0.75, 0.3), 17, 120)
	ok.disabled = short > 0
	ok.pressed.connect(func():
		ok.disabled = true   # 중복 클릭 방지
		var r := sim.try_unlock(fid)
		show_toast(r.msg, GOOD if r.ok else BAD)
		close_top())
	btns.add_child(ok)


# ---------------------------------------------------------------- 시설 정보 (작업실: 제작·강화)
func open_facility(fid: String) -> void:
	var f: Dictionary = sim.data.facilities[fid]
	var win := _window(sim.data.facility_name(fid), 620)
	var body: VBoxContainer = win.body
	var here := PackedStringArray()
	for n in sim.npcs.values():
		if n.facility == fid and n.state != NpcAgent.UNAVAILABLE:
			here.append(n.name)
	body.add_child(_label("%s · 기능: %s · 머무는 대원: %s" % [sim.data.floor_name(f.floor), f.tag, ", ".join(here) if not here.is_empty() else "없음"], 15, Color(0.85, 0.9, 1)))
	if f.cleanable:
		var cl := float(sim.cleanliness.get(fid, 100.0))
		var who := sim.cleaner_of(fid)
		body.add_child(_label("청결 %d / 100 · 오염 %d곳%s" % [roundi(cl), sim.dirt_in(fid).size(), " · %s 청소하러 가는 중" % sim.data.npc_name(who) if who != "" else ""],
			15, GOOD if cl >= 80 else (GOLD if cl >= 50 else BAD)))
		body.add_child(_label("청소: 대원 우클릭 → 청소 → 이 방 클릭", 13, Color(0.7, 0.75, 0.85)))
	if f.tag in ["작업", "무기고"]:
		_armory_section(body)
		_workshop_section(body)
	elif f.tag == "식당":
		body.add_child(_label("식재료 %d끼 남음 — 식당에서 먹으면 한 끼에 1 소모 (없으면 굶어서 피로 +%d)" % [sim.food, sim.data.inum("hungry_fatigue", 6)], 15, GOLD))
		var b := _button("식재료 공급  $%d → +%d끼" % [sim.data.inum("food_pack_price", 20), sim.data.inum("food_pack_amount", 12)], Color(0.45, 0.9, 0.6), 16)
		b.pressed.connect(func():
			var r := sim.buy_food()
			show_toast(r.msg, GOOD if r.ok else BAD)
			close_top()
			open_facility(fid))
		body.add_child(b)
	elif f.tag == "상점":
		_px_section(body, fid)
	elif f.tag == "의무":
		body.add_child(_label("상태 이상은 여기서 치료해야 사라지고, 체력은 여기 침대에서 쉬어야만 회복됩니다.", 14, Color(0.85, 0.9, 1)))
		body.add_child(_label("대원 우클릭 → 의무실로 (치료 %d분 → 의무침대 휴식, 체력이 다 차면 복귀)" % sim.data.inum("treat_minutes", 60), 13, Color(0.7, 0.75, 0.85)))
		for id in sim.data.npc_order:
			var n: NpcAgent = sim.npcs[id]
			var cs := sim.cstate(n)
			var sts := (cs.statuses as Array).map(func(x): return StatusCatalog.get_def(str(x)).name)
			body.add_child(_label("%s — 체력 %d/%d%s%s" % [n.name, floori(float(cs.hp)), sim.char_max_hp(n.character_id), "  상태: " + ", ".join(sts) if not sts.is_empty() else "",
				"  (%s)" % n.state_name() if n.state in [NpcAgent.TREATMENT, NpcAgent.RECOVERING] else ""], 14,
				BAD if not sts.is_empty() else (GOLD if float(cs.hp) < sim.char_max_hp(n.character_id) else GOOD)))
	elif f.tag == "행정":
		var b := _button("의뢰 게시판 열기", Color(0.45, 0.7, 0.9), 15)
		b.pressed.connect(func(): open_contracts(""))
		body.add_child(b)
	elif f.tag == "훈련":
		body.add_child(_label("훈련: 대원 우클릭 → 훈련 (%d분, 끝나면 훈련 단계 +1 → 전투 최대 HP +%d)" % [sim.data.inum("train_minutes", 120), sim.data.inum("train_hp_bonus", 5)], 14, Color(0.85, 0.9, 1)))


## 무기고: 대원별 장착 (주무기/보조1/보조2)
func _armory_section(body: VBoxContainer) -> void:
	body.add_child(_label("장착 (전투에 반영)", 16, Color(1, 0.95, 0.75)))
	for id in sim.data.npc_order:
		var n: NpcAgent = sim.npcs[id]
		var row := _hbox(6)
		body.add_child(row)
		var nl := _label(n.name, 14)
		nl.custom_minimum_size.x = 50
		row.add_child(nl)
		for slot in 3:
			var ob := OptionButton.new()
			ob.add_theme_font_override("font", font)
			ob.add_theme_font_size_override("font_size", 12)
			ob.custom_minimum_size.x = 150
			ob.fit_to_longest_item = false
			var uids: Array[String] = []
			if slot > 0:
				ob.add_item("(비움)")
				uids.append("")
			for it in sim.inventory:
				if it.owner == "" or it.owner == n.character_id:
					ob.add_item("%s+%d" % [sim.item_name(it.item), it.plus])
					uids.append(it.uid)
					if it.owner == n.character_id and int(it.slot) == slot:
						ob.select(ob.item_count - 1)
			var cid := n.character_id
			var wf := sim.workshop_facility()
			ob.item_selected.connect(func(i):
				var res := sim.equip(cid, slot, uids[i])
				show_toast(res.msg, GOOD if res.ok else BAD)
				close_top()
				open_facility(wf))
			row.add_child(ob)


func _px_section(body: VBoxContainer, fid: String) -> void:
	body.add_child(_label("친밀도 선물 — 대원을 클릭한 대화창에서 '선물하기'. 좋아하는 선물은 친밀도 ×%d" % sim.data.inum("liked_gift_mult", 2), 14, AFFINITY_COL))
	for g in sim.data.px_order:
		var it: Dictionary = sim.data.px_items[g]
		var row := _hbox(10)
		body.add_child(row)
		var l := _label("%s — $%d · 친밀도 +%d · 보유 %d" % [it.name, it.price, it.affinity, int(sim.gifts.get(g, 0))], 15)
		l.custom_minimum_size.x = 400
		row.add_child(l)
		var b := _button("구매", Color(0.45, 0.9, 0.6), 14, 70)
		b.disabled = sim.ledger.cash < int(it.price)
		b.pressed.connect(func():
			var r := sim.buy_gift(g)
			show_toast(r.msg, GOOD if r.ok else BAD)
			close_top()
			open_facility(fid))
		row.add_child(b)


func _workshop_section(body: VBoxContainer) -> void:
	var w := sim.workshop
	if w.is_empty():
		body.add_child(_label("작업대: 비어 있음 (강화·제작은 한 번에 하나씩)", 15, GOOD))
	else:
		var what: String = sim.data.recipes.get(str(w.get("recipe", "")), {}).get("name", "") if w.kind == "craft" else "%s 강화" % sim.item_name(str(sim.inv_item(str(w.uid)).get("item", "")))
		body.add_child(_label("작업 중: %s — 남은 %d분" % [what, int(w.remaining)], 15, GOLD))
	body.add_child(_label("제작 (레시피·재료 미정 → 시간만 걸림)", 16, Color(1, 0.95, 0.75)))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	body.add_child(g)
	for rid in sim.data.recipe_order:
		var r: Dictionary = sim.data.recipes[rid]
		g.add_child(_label("%s → %s (%d분)" % [r.name, sim.item_name(r.item), r.minutes], 14))
		var b := _button("제작", Color(0.45, 0.7, 0.9), 13, 70)
		b.disabled = not w.is_empty()
		b.pressed.connect(func():
			var res := sim.start_craft(rid)
			show_toast(res.msg, GOOD if res.ok else BAD)
			close_top())
		g.add_child(b)
	body.add_child(_label("강화 (단계마다 위력 +%d, 최대 +%d, %d분)" % [sim.data.inum("enhance_power_bonus", 1), sim.data.inum("enhance_max", 5), sim.data.inum("enhance_minutes", 60)], 16, Color(1, 0.95, 0.75)))
	var list := _scroll(body, 170)
	for it in sim.inventory:
		var row := _hbox(10)
		list.add_child(row)
		var owner := "보관" if it.owner == "" else _char_name(it.owner)
		var l := _label("%s +%d  (%s)" % [sim.item_name(it.item), it.plus, owner], 14)
		l.custom_minimum_size.x = 380
		row.add_child(l)
		var b := _button("강화", Color(0.9, 0.6, 0.3), 13, 70)
		b.disabled = not w.is_empty() or int(it.plus) >= sim.data.inum("enhance_max", 5)
		var uid: String = it.uid
		b.pressed.connect(func():
			var res := sim.start_enhance(uid)
			show_toast(res.msg, GOOD if res.ok else BAD)
			close_top())
		row.add_child(b)


func _char_name(character_id: String) -> String:
	for id in sim.data.npc_order:
		if sim.data.npcs[id].character_id == character_id:
			return sim.data.npcs[id].name
	return character_id


# ---------------------------------------------------------------- 대원 우클릭 메뉴
func open_context(npc_id: String, at: Vector2) -> void:
	var n: NpcAgent = sim.npcs[npc_id]
	var pm := PopupMenu.new()
	pm.add_theme_font_override("font", font)
	pm.add_theme_font_size_override("font_size", 15)
	pm.add_separator(n.name)
	pm.add_item("대화", 0)
	pm.add_item("청소 지시 → 장소 클릭", 1)
	pm.add_item("업무·의뢰 지시", 2)
	pm.add_item("훈련", 3)
	pm.add_item("정보·장비", 4)
	pm.add_item("의무실로 (치료·휴식)", 5)
	for id in [1, 2]:
		pm.set_item_disabled(pm.get_item_index(id), not n.is_free())
	pm.set_item_disabled(pm.get_item_index(3), not n.is_free() or sim.training_facility() == "")
	pm.set_item_disabled(pm.get_item_index(0), n.state == NpcAgent.UNAVAILABLE)
	var cs := sim.cstate(n)
	pm.set_item_disabled(pm.get_item_index(5), not n.is_free() or sim.infirmary_facility() == "" or ((cs.statuses as Array).is_empty() and float(cs.hp) >= sim.char_max_hp(n.character_id)))
	add_child(pm)
	pm.id_pressed.connect(_on_context.bind(npc_id))
	pm.popup_hide.connect(pm.queue_free)
	pm.position = Vector2i(at)
	pm.popup()


func _on_context(id: int, npc_id: String) -> void:
	match id:
		0:
			open_dialogue(npc_id)
		1:
			hub.begin_clean_pick(npc_id)
		2:
			open_contracts(npc_id)
		3:
			var r := sim.issue_train(npc_id)
			show_toast(r.msg, GOOD if r.ok else BAD)
		4:
			open_character(npc_id)
		5:
			var r := sim.issue_medical(npc_id)
			show_toast(r.msg, GOOD if r.ok else BAD)


# ---------------------------------------------------------------- 의뢰 게시판 (업무 지시·외부 의뢰)
func open_contracts(npc_id: String) -> void:
	var title := "의뢰 게시판" if npc_id == "" else "%s 에게 일 맡기기" % sim.data.npc_name(npc_id)
	var win := _window(title, 760)
	var body: VBoxContainer = win.body
	body.add_child(_label("수익은 완료 즉시 '미지급'으로 쌓였다가 주간 결산 때 지급 · 외부 의뢰는 정문으로 나갔다가 복귀 (성공률·위험 미정 → 고정 완료)", 13, Color(0.75, 0.8, 0.9)))
	var pick := OptionButton.new()
	pick.add_theme_font_override("font", font)
	var ids: Array[String] = []
	for id in sim.data.npc_order:
		var n: NpcAgent = sim.npcs[id]
		pick.add_item("%s (%s)" % [n.name, n.state_name() if not n.is_free() else "가능"])
		pick.set_item_disabled(pick.item_count - 1, not n.is_free())
		ids.append(id)
		if id == npc_id:
			pick.select(pick.item_count - 1)
	if npc_id == "":
		var row := _hbox(8)
		row.add_child(_label("맡길 대원", 15))
		row.add_child(pick)
		body.add_child(row)
		for i in ids.size():
			if sim.npcs[ids[i]].is_free():
				pick.select(i)
				break
	var avail := sim.available_contracts()
	if avail.is_empty():
		body.add_child(_label("지금 맡을 수 있는 의뢰가 없습니다", 15, BAD))
	for cid in avail:
		var j: Dictionary = sim.data.jobs[cid]
		var row := _hbox(10)
		body.add_child(row)
		var l := _label("[%s] %s — $%d · %d분 · %s%s" % ["외부의뢰" if j.kind == "external" else "작업지시", j.name, j.reward, j.minutes,
			sim.data.facility_name(j.place), "" if j.repeat else " · 1회"], 15)
		l.custom_minimum_size.x = 560
		row.add_child(l)
		var b := _button("지시", Color(0.4, 0.9, 0.5), 14, 70)
		b.pressed.connect(func():
			var who: String = npc_id if npc_id != "" else ids[maxi(0, pick.selected)]
			var r := sim.issue_job(who, cid)
			show_toast(r.msg, GOOD if r.ok else BAD)
			if r.ok:
				close_top())
		row.add_child(b)
	var running := sim.jobs.filter(func(jb): return jb.state != "done")
	if not running.is_empty():
		body.add_child(_label("진행 중", 16, Color(1, 0.95, 0.75)))
		for jb in running:
			var n: NpcAgent = sim.npcs.get(jb.npc)
			body.add_child(_label("%s — %s (%s, 남은 %d분)" % [sim.data.jobs.get(jb.contract, {}).get("name", jb.contract), n.name if n else jb.npc,
				"이동 중" if jb.state == "assigned" else "작업 중", int(n.busy) if n else 0], 14, Color(0.85, 0.9, 1)))


# ---------------------------------------------------------------- 대원 정보·장비
func open_character(npc_id: String) -> void:
	var n: NpcAgent = sim.npcs[npc_id]
	var win := _window("%s — 정보·장비" % n.name, 640)
	var body: VBoxContainer = win.body
	var row := _hbox(14)
	body.add_child(row)
	row.add_child(_portrait_rect(n.sprite, 110))
	var col := _vbox(4)
	row.add_child(col)
	var u: UnitData = GameData._find(sim.battle.allies, n.character_id) if sim.battle != null else null
	col.add_child(_label("상태: %s · 위치: %s" % [n.state_name(), sim.data.facility_name(n.facility)], 15))
	col.add_child(_label("지금 일정: %s @ %s (%s)" % [OutgameData.ACTIVITIES.get(n.activity, n.activity), sim.data.facility_name(n.dest), n.dest_reason], 14, Color(0.8, 0.88, 1)))
	col.add_child(_status_card(npc_id))
	var lv := sim.training_level(n.character_id)
	if u != null:
		col.add_child(_label("전투: %s · HP %d (+%d 훈련 %d단계) · 속도 %d" % [u.role, u.max_hp + lv * sim.data.inum("train_hp_bonus", 5), lv * sim.data.inum("train_hp_bonus", 5), lv, u.speed], 15, GOLD))
	body.add_child(_label("장비 (전투에 반영 · 주무기 / 보조1 / 보조2)", 16, Color(1, 0.95, 0.75)))
	for slot in 3:
		var r := _hbox(10)
		body.add_child(r)
		r.add_child(_label(["주무기", "보조 1", "보조 2"][slot], 15))
		var ob := OptionButton.new()
		ob.add_theme_font_override("font", font)
		ob.custom_minimum_size.x = 360
		var uids: Array[String] = []
		if slot > 0:
			ob.add_item("(비움)")
			uids.append("")
		for it in sim.inventory:
			if it.owner == "" or it.owner == n.character_id:
				ob.add_item("%s +%d%s" % [sim.item_name(it.item), it.plus, "" if it.owner == "" else " (장착 중 %d)" % (int(it.slot) + 1)])
				uids.append(it.uid)
				if it.owner == n.character_id and int(it.slot) == slot:
					ob.select(ob.item_count - 1)
		ob.item_selected.connect(func(i):
			var res := sim.equip(n.character_id, slot, uids[i])
			show_toast(res.msg, GOOD if res.ok else BAD)
			close_top()
			open_character(npc_id))
		r.add_child(ob)
	# 오늘 일정 요약
	var wd := sim.clock.weekday()
	var today := PackedStringArray()
	for b in sim.data.schedules.get(npc_id, {}).get("weekly_schedule", []):
		if int(b.weekday) == wd:
			var req: Array = b.get("required_unlocks", [])
			var fb := str(b.get("fallback_facility_id", ""))
			today.append("%s~%s %s @ %s%s%s" % [OutgameData.hm(int(b.start_minute)), OutgameData.hm(int(b.end_minute)), OutgameData.ACTIVITIES.get(b.activity_id, b.activity_id),
				sim.data.facility_name(b.target_facility_id), " (해금 시: %s)" % ", ".join(req.map(func(x): return sim.data.facility_name(x))) if not req.is_empty() else "",
				" (잠기면: %s)" % sim.data.facility_name(fb) if fb != "" else ""])
	body.add_child(_label("오늘(%s) 일정 — 편집은 Godot 에디터 '일정' 탭" % OutgameData.WEEKDAYS[wd], 15, Color(1, 0.95, 0.75)))
	var t := _label("\n".join(today), 13, Color(0.82, 0.88, 0.96))
	body.add_child(t)


# ---------------------------------------------------------------- 무기고 · 원장
func open_armory() -> void:
	var wf := sim.workshop_facility()
	if wf != "":
		open_facility(wf)
		return
	var win := _window("무기고", 560)
	var body: VBoxContainer = win.body
	var list := _scroll(body, 360)
	for it in sim.inventory:
		list.add_child(_label("%s +%d — %s" % [sim.item_name(it.item), it.plus, "보관 중" if it.owner == "" else "%s 장착 (%d)" % [_char_name(it.owner), int(it.slot) + 1]], 15))
	body.add_child(_label("무기고가 잠겨 있습니다", 15, BAD))


func open_ledger() -> void:
	var win := _window("달러 원장", 700)
	var body: VBoxContainer = win.body
	body.add_child(_label("잔액 $%d · 미지급 $%d (다음 결산 때 지급)" % [sim.ledger.cash, sim.ledger.pending_total()], 18, GOLD))
	var list := _scroll(body, 380)
	for p in sim.ledger.pending:
		list.add_child(_label("[미지급] %s  +$%d" % [p.label, p.amount], 14, Color(0.7, 0.85, 1)))
	var es: Array = sim.ledger.entries.duplicate()
	es.reverse()
	for e in es.slice(0, 60):
		list.add_child(_label("%s  %s  %s$%d" % [e.date, e.label, "+" if int(e.amount) >= 0 else "-", absi(int(e.amount))], 14, GOOD if int(e.amount) >= 0 else BAD))


# ---------------------------------------------------------------- 결산 · 점검 알림
func open_statement(st: Dictionary) -> void:
	var win := _window("%d주차 결산" % (int(st.week) + 1), 520)
	var body: VBoxContainer = win.body
	body.add_child(_label(str(st.date), 14, Color(0.75, 0.8, 0.9)))
	for it in st.items:
		body.add_child(_label("%s   +$%d" % [it.label, it.amount], 16, GOLD if it.source == "inspection" else Color(1, 1, 1)))
	body.add_child(_label("합계 +$%d  →  잔액 $%d" % [st.total, st.cash], 21, GOOD))


func open_inspection(rec: Dictionary) -> void:
	var win := _window("장군 점검 (%s)" % rec.month, 480)
	var body: VBoxContainer = win.body
	body.add_child(_label(str(rec.date), 14, Color(0.75, 0.8, 0.9)))
	body.add_child(_label("환경 미화 %d점 → 장군 만족도: %s" % [roundi(float(rec.score)), rec.grade], 20, GOLD))
	body.add_child(_label("이번 주 결산 보너스 $%d" % int(rec.bonus), 17, GOOD if int(rec.bonus) > 0 else BAD))


# ---------------------------------------------------------------- 출전
func open_sortie() -> void:
	var win := _window("전투 출전", 520)
	var body: VBoxContainer = win.body
	if Game.data == null or Game.data.stage_order.is_empty():
		body.add_child(_label("스테이지가 없습니다 (밸런스 엑셀 스테이지 시트)", 15, BAD))
		return
	body.add_child(_label("스테이지를 고르면 전투 배치(편성) 화면으로 갑니다. 기지 시간은 전투 동안 멈춥니다 [임시].", 14, Color(0.8, 0.88, 1)))
	var ob := OptionButton.new()
	ob.add_theme_font_override("font", font)
	for id in Game.data.stage_order:
		ob.add_item("%s (%s)" % [Game.data.stages[id].name, id])
		if id == Game.stage_id:
			ob.select(ob.item_count - 1)
	body.add_child(ob)
	var away := PackedStringArray()
	for n in sim.npcs.values():
		if n.state == NpcAgent.UNAVAILABLE:
			away.append(n.name)
	if not away.is_empty():
		body.add_child(_label("외부 의뢰 중: %s (출전 연계 규칙 미정 — 이번 프로토타입은 편성 가능)" % ", ".join(away), 13, GOLD))
	var go := _button("전투 배치로", Color(1.0, 0.5, 0.3), 18, 180)
	go.pressed.connect(func(): hub.sortie(Game.data.stage_order[maxi(0, ob.selected)]))
	body.add_child(go)
