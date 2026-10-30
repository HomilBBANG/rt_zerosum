class_name OutgameHud
extends Control
## 기지 화면 HUD 와 창들. 표시와 명령 전달만 하고 규칙은 BaseSim 에 맡긴다 (03_HANDOFF 2절).
## 위: 날짜·시각·배속 / 달러·미지급·결산 D-day / 버튼(스킬·도감·퀘스트·의뢰·무기고·납품·원장·저장·출전·타이틀)
## 창(모달)이 열려 있으면 시계가 멈춘다 [임시 규칙].

const PANEL_BG := Color(0.05, 0.07, 0.10, 0.92)
const PANEL_LINE := Color(0.32, 0.46, 0.58)
const GOOD := Color(0.45, 1.0, 0.6)
const BAD := Color(1.0, 0.42, 0.35)
const GOLD := Color(1.0, 0.85, 0.35)
const QUEST_COL := Color(0.95, 0.75, 0.4)
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
var sel_panel: PanelContainer
var sel_body: VBoxContainer
var _sel_id := ""
var _sel_t := 0.0
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
	_build_selection()
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
	sim.divine_revealed.connect(func(cid):
		show_toast("✦ %s 의 정체 — %s! 스킬 창 신앙 탭이 '기적' 으로" % [_char_name(cid), sim.divine_god(cid).get("name", "신")], Color(1, 0.9, 0.5)))
	sim.quest_started.connect(func(qid): show_toast("◆ 퀘스트 시작: %s" % sim.quest_def(qid).get("name", qid), QUEST_COL))
	sim.quest_step.connect(func(qid, _i): show_toast("◆ %s — 다음: %s" % [sim.quest_def(qid).get("name", qid), _quest_step_line(qid, int(_i))], QUEST_COL))
	sim.cutscene_queued.connect(func(_id): _pump_cutscenes.call_deferred())
	sim.quest_completed.connect(func(qid): show_toast("◆ 퀘스트 완료: %s" % sim.quest_def(qid).get("name", qid), GOOD))


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
const UI_DIR := "res://assets/ui/outgame/"
var _top_left: Control
var _top_right: Control


## 상단: 왼쪽 = 날짜 바(day_bar 그림) 한 장이 날짜 · 속도 버튼 · 돈(지폐 그림) · 정보 줄 전체를 감쌈, 오른쪽 = 아이콘 버튼 (UI 패키지에서 자른 assets/ui/outgame/icons)
func _build_top() -> void:
	var left := PanelContainer.new()
	var em := StyleBoxEmpty.new()
	em.content_margin_left = 22
	em.content_margin_right = 22
	em.content_margin_top = 9
	em.content_margin_bottom = 9
	left.add_theme_stylebox_override("panel", em)
	left.position = Vector2(10, 8)
	left.mouse_filter = MOUSE_FILTER_IGNORE
	_top_left = left
	_nine_bg(left, load(UI_DIR + "day_bar.png"), 44, 20)   # 양 끝 팔각 모서리는 그대로, 가운데만 늘림
	add_child(left)
	var lv := _vbox(4)
	left.add_child(lv)
	var row := _hbox(8)
	lv.add_child(row)
	date_label = _label("", 22, Color(1, 1, 1))
	row.add_child(date_label)
	row.add_child(_spacer_w(6))
	for sp in [[0, "정지"], [1, "1x"], [4, "4x"], [16, "16x"]]:
		var b := _button(sp[1], Color(0.55, 0.65, 0.42), 14, 44)
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		var v: int = sp[0]
		b.pressed.connect(func(): hub.set_speed(v))
		row.add_child(b)
		speed_buttons.append(b)
	var r2 := _hbox(8)
	lv.add_child(r2)
	var money := TextureRect.new()
	money.texture = load(UI_DIR + "money.png")
	money.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	money.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	money.custom_minimum_size = Vector2(52, 24)
	money.mouse_filter = MOUSE_FILTER_IGNORE
	r2.add_child(money)
	cash_label = _label("", 20, GOLD)
	r2.add_child(cash_label)
	r2.add_child(_label("|", 14, Color(0.4, 0.45, 0.35)))
	info_label = _label("", 14, Color(0.85, 0.92, 1.0))
	r2.add_child(info_label)

	var right := _hbox(4)
	_top_right = right
	right.position = Vector2(0, 6)
	add_child(right)
	var specs := [["스킬", "skill", null, func(): open_skills("")], ["도감", "codex", null, func(): open_codex()], ["퀘스트", "quest", QUEST_COL, func(): open_quests()],
		["의뢰", "contract", null, func(): open_contracts("")], ["무기고", "tools", null, func(): open_armory()], ["납품", "calendar_check", GOLD, func(): open_supply()], ["원장", "ledger", null, func(): open_ledger()],
		["저장", "bookmark", Color(0.6, 0.95, 0.65), func(): hub.save_now()], ["전투 출전", "sword", Color(1.0, 0.55, 0.35), func(): open_sortie()],
		["타이틀", "gear", Color(0.7, 0.7, 0.72), func(): hub.to_title()]]
	for s in specs:
		right.add_child(_icon_button(s[0], s[1], s[2] if s[2] != null else Color(0.88, 0.86, 0.76), s[3]))
	right.position.x = 1280 - 10 - right.get_combined_minimum_size().x
	right.resized.connect(func(): right.position.x = 1280 - 10 - right.size.x)


## 날짜 바가 오른쪽 아이콘 버튼에 닿으면 정보 줄 글자를 줄임 (14 → 12 → 11), 넉넉하면 다시 14
func _fit_top() -> void:
	if _top_left == null or _top_right == null:
		return
	var limit := _top_right.position.x - 8.0 - _top_left.position.x
	for fs in [14, 12, 11]:
		info_label.add_theme_font_size_override("font_size", fs)
		if _top_left.get_combined_minimum_size().x <= limit:
			break
	_top_left.reset_size()


## 그림 배경(9칸 늘리기)을 그 컨트롤 전체에 그림: 양 끝 모서리는 그대로, 가운데만 늘림.
## 그림은 2배 해상도로 만들어 두었으므로 반으로 줄여 그림 (2560×1440 창에서 1:1). 컨테이너의 안쪽 여백과 상관없이 테두리까지 채움
func _nine_bg(c: Control, tex: Texture2D, side: int, cap: int) -> void:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = side
	sb.texture_margin_right = side
	sb.texture_margin_top = cap
	sb.texture_margin_bottom = cap
	c.draw.connect(func():
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
		c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size * 2.0))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))


func _spacer_w(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c


## 아이콘 버튼 + 아래 이름 (마우스를 올리면 밝게 · 살짝 커짐)
func _icon_button(text: String, icon: String, col: Color, cb: Callable) -> Control:
	var box := _vbox(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := TextureButton.new()
	b.texture_normal = load(UI_DIR + "icons/%s.png" % icon)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(42, 42)
	b.size_flags_horizontal = SIZE_SHRINK_CENTER
	b.tooltip_text = text
	b.focus_mode = FOCUS_NONE
	b.pivot_offset = Vector2(21, 21)
	b.mouse_entered.connect(func():
		b.modulate = Color(1.25, 1.25, 1.2)
		b.scale = Vector2(1.06, 1.06))
	b.mouse_exited.connect(func():
		b.modulate = Color.WHITE
		b.scale = Vector2.ONE)
	b.pressed.connect(cb)
	box.add_child(b)
	var l := _label(text, 12, col, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 48
	box.add_child(l)
	return box


func _build_log() -> void:
	log_panel = PanelContainer.new()
	UiPanel.apply(log_panel, Vector4(14, 10, 14, 10), 0.9)   # UI 공용 패널
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
	var hint := _label("대원 클릭: 선택 (한 번 더 = 대화) · 방 클릭: 이동 · 더블클릭: 뛰기 · 도착 후 우클릭: 행동 · Tab: 다음 대원 · Esc: 해제 · 말풍선: 엿듣기 · F1", 12, Color(0.8, 0.88, 0.95), true)
	hint.position = Vector2(500, 696)
	add_child(hint)


## 오른쪽 아래 확대/축소: − 배율 + (휠·핀치·Q/E·+/- 키도 됨, 0 = 기본)
func _build_zoom() -> void:
	var p := PanelContainer.new()
	UiPanel.apply(p, Vector4(12, 8, 12, 8))
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


## 오른쪽: 선택한 대원 카드 (이름·지금 하는 일·체력·피로도·친밀도·조작 안내)
func _build_selection() -> void:
	sel_panel = PanelContainer.new()
	UiPanel.apply(sel_panel, Vector4(18, 14, 18, 14))
	sel_panel.position = Vector2(1280 - 10 - 330, 300)
	sel_panel.custom_minimum_size = Vector2(330, 0)
	sel_panel.visible = false
	add_child(sel_panel)
	sel_body = _vbox(4)
	sel_panel.add_child(sel_body)


func show_selection(npc_id: String) -> void:
	_sel_id = npc_id
	_sel_t = 0.0
	sel_panel.visible = npc_id != ""
	_fill_selection()


func _fill_selection() -> void:
	for c in sel_body.get_children():
		sel_body.remove_child(c)
		c.queue_free()
	if _sel_id == "" or not sim.npcs.has(_sel_id):
		return
	var n: NpcAgent = sim.npcs[_sel_id]
	var row := _hbox(10)
	sel_body.add_child(row)
	row.add_child(_portrait_rect(_sprite_of(_sel_id), 56))
	var col := _vbox(2)
	row.add_child(col)
	col.add_child(_label(n.name, 18, GOLD))
	var what: String = n.state_name() if n.state != NpcAgent.STAYING else OutgameData.ACTIVITIES.get(n.activity, n.activity)
	if n.state == NpcAgent.MOVING:
		what = "%s → %s" % ["뛰는 중" if n.running else "걷는 중", sim.data.facility_name(n.dest)]
	col.add_child(_label("%s · %s" % [sim.data.facility_name(n.facility), what], 14, Color(0.85, 0.9, 1)))
	if n.is_holding():
		col.add_child(_label("지시 대기 중 (다음 일정까지)", 12, Color(0.6, 1.0, 0.7)))
	var card := _status_card(_sel_id)
	sel_body.add_child(card)
	if sim.is_combatant(n):
		var cid := n.character_id
		var pts := sim.skill_points(cid)
		sel_body.add_child(_label("Lv%d · 경험치 %d/%d%s" % [sim.char_level(cid), sim.char_xp(cid), sim.xp_need(cid), "  · 스킬 포인트 %d (우클릭 → 스킬 트리)" % pts if pts > 0 else ""],
			13, Color(0.85, 0.6, 1.0) if pts > 0 else Color(0.8, 0.85, 0.92)))
	var tip := "방 클릭: 걸어서 · 더블클릭: 뛰어서\n도착하면 우클릭: 그 방에서 할 행동 · 대원 다시 클릭: 대화"
	if sim.is_researcher(_sel_id):
		tip = "방 클릭: 걸어서 · 더블클릭: 뛰어서\n%s 클릭: 무기 연구 · 우클릭: 대화·행동" % n.name
	if n.state == NpcAgent.MOVING:
		tip = "가는 중 — 더블클릭하면 뛰어감\n도착하면 우클릭으로 행동 지시"
	sel_body.add_child(_label(tip, 12, Color(0.75, 0.8, 0.9)))
	sel_panel.reset_size()
	var sz := sel_panel.get_combined_minimum_size()
	sel_panel.position = Vector2(1280 - 10 - sz.x, 640 - 12 - sz.y)   # 오른쪽 아래 확대 버튼 위, 화면 안쪽


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
	var mx := sim.char_max_hp(sim.ckey(n))
	if sim.is_combatant(n):   # 전투에 나가지 않는 대원(로한)은 체력 게이지 없음
		v.add_child(_gauge("체력", float(cs.hp), mx, HP_COL, "%d / %d" % [floori(float(cs.hp)), mx]))
	var fat := float(cs.fatigue)
	v.add_child(_gauge("피로도", fat, 100.0, FATIGUE_COL, "%d%s" % [roundi(fat), "  (지침)" if fat >= 80 else ""]))
	var nxt := sim.next_affinity_need(npc_id)
	var aff_txt := "%d  · 다음 대화 %d" % [roundi(float(cs.affinity)), nxt] if nxt >= 0 else "%d  · 대화 모두 해금" % roundi(float(cs.affinity))
	if not sim.pending_affinity_talk(npc_id).is_empty():
		aff_txt += "  ♥ 새 대화"
	v.add_child(_gauge("친밀도", float(cs.affinity), 100.0, AFFINITY_COL, aff_txt))
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
		["다음 달", func(): hub.debug_skip(-30)], ["전리품 +2", func():
			for it in sim.supply().item_order:
				sim.add_loot(it, 2)
			show_toast("모든 전리품 +2")], ["점검 지금", func(): sim.debug_inspect_now()],
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
	cash_label.text = "%d" % sim.ledger.cash   # 지폐 그림이 $ 표시
	_update_battle_bar()
	if _sel_id != "":
		_sel_t -= delta
		if _sel_t <= 0.0:
			_sel_t = 0.3
			_fill_selection()
	zoom_label.text = "%d%%" % hub.zoom_percent()
	var left := sim.minutes_to_settlement()
	var pend := sim.ledger.pending_total()
	var info := "미지급 %s$%d  ·  결산 D-%d (%d일 %d시간)" % ["-" if pend < 0 else "", absi(pend), ceili(left / 1440.0),
		floori(left / 1440.0), floori(fmod(left, 1440.0) / 60.0)]
	if info != info_label.text:
		info_label.text = info
		_fit_top.call_deferred()
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
	_after_modal()


func _after_modal() -> void:
	if _modals.is_empty() and not _queue.is_empty():
		var fn: Callable = _queue.pop_front()
		fn.call_deferred()
	elif _modals.is_empty():
		_pump_cutscenes.call_deferred()


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
	UiPanel.apply(panel, Vector4(22, 18, 22, 18))   # 모든 창 = UI 공용 패널
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
	if str(d.get("cutscene", "")) != "":   # 말 걸기 컷씬 = 평소 대사 대신
		play_cutscene(d.cutscene, 0, func(): sim.end_dialogue(npc_id))
		return
	var req: Dictionary = d.request
	var title := "%s와(과) 대화" % sim.data.npc_name(npc_id) if req.is_empty() else "%s의 요청 !" % sim.data.npc_name(npc_id)
	if req.is_empty() and int(d.get("affinity_need", -1)) >= 0:
		title += "  ♥ 친밀도 %d 대화%s" % [d.affinity_need, " (새로 해금)" if d.get("new_talk", false) else ""]
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
	var got: Dictionary = d.get("gift", {})
	if not got.is_empty():   # 하루 첫 대화 선물 (전리품 → 창고, 납품 · 장군 요구에 씀)
		body.add_child(_label("%s 이(가) %s 을(를) 건넸습니다 → 전리품 창고 (지금 %d개)" % [sim.data.npc_name(npc_id), got.name, sim.loot_count(got.item)], 15, GOLD))
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
		var taste := sim.data.gift_taste(g, npc_id)
		var b := _button("%s ×%d  +%d%s" % [it.name, int(sim.gifts[g]), sim.data.gift_value(g, npc_id), "" if taste == "보통" else " " + taste],
			AFFINITY_COL.darkened(0.2) if taste != "별로" else Color(0.6, 0.6, 0.65), 13)
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
	if str(o.get("cutscene", "")) != "":   # 엿듣기 컷씬 = 엿듣기 창 대신
		play_cutscene(o.cutscene)
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
			body.add_child(_label("%s — 체력 %d/%d%s%s" % [n.name, floori(float(cs.hp)), sim.char_max_hp(sim.ckey(n)), "  상태: " + ", ".join(sts) if not sts.is_empty() else "",
				"  (%s)" % n.state_name() if n.state in [NpcAgent.TREATMENT, NpcAgent.RECOVERING] else ""], 14,
				BAD if not sts.is_empty() else (GOLD if float(cs.hp) < sim.char_max_hp(sim.ckey(n)) else GOOD)))
	elif f.tag == "행정":
		var b := _button("의뢰 게시판 열기", Color(0.45, 0.7, 0.9), 15)
		b.pressed.connect(func(): open_contracts(""))
		body.add_child(b)
	elif f.tag == "연구":
		_research_section(body, win)
	elif f.tag == "훈련":
		body.add_child(_label("훈련: 대원 우클릭 → 훈련 (%d분, 끝나면 훈련 단계 +1 → 전투 최대 HP +%d)" % [sim.data.inum("train_minutes", 120), sim.data.inum("train_hp_bonus", 5)], 14, Color(0.85, 0.9, 1)))


# ---------------------------------------------------------------- 스킬 창 (캐릭터마다 액티브 · 패시브 · 신앙)
const SKILL_MODES := [["active", "액티브 스킬"], ["passive", "패시브 스킬"], ["faith", "신앙 스킬"]]
const SKILL_MODE_HINT := {"active": "전투에서 쓰는 스킬을 강화 · 새 스킬도 배움", "passive": "늘 적용되는 능력치 (체력·속도·AP·방어·위력)",
	"faith": "믿는 신에 따라 배울 수 있는 스킬이 다름 · 신앙도는 퀘스트·대화·이벤트로", "miracle": "정체가 신 — 의지로 기적을 일으킴 (그 캐릭터만의 기적)"}


## cid = "" 이면 첫 대원. 왼쪽: 대원 목록 (위아래 스크롤) / 위: 액티브 · 패시브 · 신앙 탭
## 액티브·패시브: 왼쪽 정보(레벨·경험치·포인트·고른 스킬 설명·배우기) + 오른쪽 스킬 트리(캐릭터마다 모양 다름). mode "tree" = 예전 이름 (액티브)
func open_skills(cid: String = "", pick: String = "", mode: String = "active") -> void:
	var allies: Array = sim.battle.allies if sim.battle != null else []
	if allies.is_empty():
		return
	if cid == "":
		cid = allies[0].id
	if mode == "tree":
		mode = "active"
	var win := _window("스킬", 1240)
	var body: VBoxContainer = win.body
	var main := _hbox(12)
	body.add_child(main)
	# 왼쪽: 대원 목록 — 대원이 늘어나도 위아래로 스크롤
	var side := _vbox(6)
	main.add_child(side)
	side.add_child(_label("대원", 15, Color(1, 0.95, 0.75)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(156, 612)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(sc)
	var list := _vbox(6)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	sc.add_child(list)
	var cur_btn: Button = null
	for u in allies:
		var pts := sim.skill_points(u.id)
		var b := _button("%s%s\nLv%d%s" % [u.display_name, " ✦" if sim.is_divine(u.id) else "", sim.char_level(u.id), "  ●%d" % pts if pts > 0 else ""],
			Color(0.85, 0.6, 1.0) if u.id == cid else Color(0.45, 0.55, 0.7), 14)
		b.icon = UnitArt.portrait(u.sprite_id, manifest)
		b.expand_icon = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(146, 60)
		b.add_theme_constant_override("icon_max_width", 48)
		b.tooltip_text = "%s · %s · Lv%d · 스킬 포인트 %d" % [u.display_name, u.role, sim.char_level(u.id), pts]
		if u.id == cid:
			b.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
			cur_btn = b
		var uid: String = u.id
		b.pressed.connect(func():
			if uid != cid:
				close_top()
				open_skills(uid, "", mode))
		list.add_child(b)
	if cur_btn != null:
		sc.ensure_control_visible.call_deferred(cur_btn)
	# 오른쪽: 탭 + 내용
	var right := _vbox(10)
	main.add_child(right)
	var tabs := _hbox(6)
	right.add_child(tabs)
	var divine := sim.is_divine(cid)   # 정체가 신 → 신앙 탭 = 기적
	for m in SKILL_MODES:
		var mb := _button("✦ 기적" if m[0] == "faith" and divine else m[1], Color(1.0, 0.85, 0.35) if m[0] == mode else Color(0.45, 0.55, 0.7), 15, 120)
		mb.custom_minimum_size.y = 40
		var mm: String = m[0]
		mb.pressed.connect(func():
			if mm != mode:
				close_top()
				open_skills(cid, "", mm))
		tabs.add_child(mb)
	var hint := _label(SKILL_MODE_HINT.get("miracle" if mode == "faith" and divine else mode, ""), 13, Color(0.75, 0.8, 0.9))
	hint.size_flags_vertical = SIZE_SHRINK_CENTER
	tabs.add_child(hint)
	var row := _hbox(12)
	right.add_child(row)
	if mode == "faith":
		if divine:
			_miracle_page(row, cid)
		else:
			_faith_page(row, cid)
		return
	var kname: String = BaseSim.TREE_KIND_NAME.get(mode, "")
	# 왼쪽: 정보
	var info := _vbox(6)
	info.custom_minimum_size = Vector2(280, 560)
	row.add_child(info)
	var unit: UnitData = GameData._find(sim.battle.allies, cid)
	var head := _hbox(10)
	info.add_child(head)
	head.add_child(_portrait_rect(unit.sprite_id, 76))
	var hc := _vbox(2)
	head.add_child(hc)
	hc.add_child(_label(unit.display_name, 22, GOLD))
	hc.add_child(_label("%s · Lv%d%s" % [unit.role, sim.char_level(cid), "  (최대)" if sim.char_level(cid) >= sim.level_max() else ""], 15, Color(0.85, 0.9, 1)))
	var pts := sim.skill_points(cid)
	hc.add_child(_label("스킬 포인트 %d" % pts, 17, Color(0.85, 0.6, 1.0) if pts > 0 else Color(0.7, 0.72, 0.78)))
	info.add_child(_gauge("경험치", float(sim.char_xp(cid)), maxf(1.0, float(sim.xp_need(cid))), Color(0.85, 0.6, 1.0),
		"%d / %d" % [sim.char_xp(cid), sim.xp_need(cid)]))
	info.add_child(_label("레벨 업마다 포인트 1 (액티브·패시브 공용)", 12, Color(0.7, 0.75, 0.85)))
	info.add_child(_label("선을 따라 선행 스킬부터 · '택1' 은 그중 하나만", 12, Color(0.7, 0.75, 0.85)))
	var detail := _vbox(4)
	detail.custom_minimum_size.y = 180
	info.add_child(detail)
	var learn := _button("배우기 (포인트 1)", Color(0.85, 0.6, 1.0), 16, 200)
	info.add_child(learn)
	info.add_child(_label("배운 %s 스킬" % kname, 15, Color(1, 0.95, 0.75)))
	var learned_box := _vbox(2)
	info.add_child(learned_box)
	for nid in sim.learned_skills(cid):
		var n := sim.tree_node(cid, nid)
		if n.get("kind", "") != mode:
			continue
		learned_box.add_child(_label("· %s — %s" % [n.get("name", nid), n.get("desc", "")], 12, SkillTreeView.col_of(n).lightened(0.3)))
	var reset := _button("%s 초기화 (포인트 돌려받기)" % kname, Color(0.6, 0.6, 0.65), 13)
	reset.pressed.connect(func():
		var res := sim.reset_skills(cid, mode)
		show_toast(res.msg, GOOD if res.ok else BAD)
		close_top()
		open_skills(cid, "", mode))
	info.add_child(reset)
	# 오른쪽: 스킬 트리 (캐릭터마다 모양이 다름)
	var tree := SkillTreeView.new()
	tree.custom_minimum_size = Vector2(740, 580)
	row.add_child(tree)
	tree.setup(sim, cid, mode, font, bold)
	var show := func(nid: String):
		for c in detail.get_children():
			detail.remove_child(c)
			c.queue_free()
		var n := sim.tree_node(cid, nid)
		if n.is_empty() or n.kind != mode:
			detail.add_child(_label("트리에서 스킬을 고르세요", 14, Color(0.75, 0.8, 0.9)))
			learn.disabled = true
			return
		var st := sim.skill_state(cid, nid)
		detail.add_child(_label(str(n.name), 19, SkillTreeView.col_of(n).lightened(0.25)))
		detail.add_child(_label("%s · %s · 필요 Lv%d%s%s" % [kname, SkillTreeData.BRANCH_NAME.get(n.branch, ""), int(n.level), " · 처음부터" if bool(n.start) else "",
			" · 택일 '%s'" % n.group if str(n.group) != "" else ""], 13, Color(0.8, 0.84, 0.9)))
		var reqs: Array = (n.req as Array).map(func(q): return str(sim.tree_node(cid, str(q)).get("name", q)))
		if not reqs.is_empty() and not bool(n.start):
			detail.add_child(_label("선행: %s%s" % [", ".join(PackedStringArray(reqs)), " (모두)" if bool(n.req_all) and reqs.size() > 1 else (" (하나라도)" if reqs.size() > 1 else "")], 13, Color(0.75, 0.8, 0.9)))
		var d := _label(str(n.desc), 15)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 270
		detail.add_child(d)
		if st == "no_level":
			detail.add_child(_label("경험 부족 — Lv%d 이 되어야 배울 수 있습니다" % int(n.level), 15, SkillTreeView.RED))
		elif st != "ready" and st != "learned":
			detail.add_child(_label(str(BaseSim.SKILL_STATE_MSG.get(st, st)), 14, BAD))
		learn.disabled = st != "ready"
		learn.text = "배웠음" if st == "learned" else "배우기 (포인트 1)"
	tree.node_selected.connect(show)
	learn.pressed.connect(func():
		var res := sim.learn_skill(cid, tree.selected)
		show_toast(res.msg, GOOD if res.ok else BAD)
		close_top()
		open_skills(cid, tree.selected, mode))
	if pick != "":
		tree.selected = pick
	show.call(tree.selected)


## 신앙 탭: 믿는 신 · 신앙도 · 그 신의 신앙 스킬 (신앙도가 모자라면 회색 + 붉은 "신앙 부족"), 아래에 다른 신들의 스킬 (참고)
func _faith_page(row: HBoxContainer, cid: String) -> void:
	var unit: UnitData = GameData._find(sim.battle.allies, cid)
	var gi := sim.god_info(cid)
	var gcol: Color = gi.get("color", Color(0.75, 0.78, 0.85))
	var info := _vbox(6)
	info.custom_minimum_size = Vector2(280, 560)
	row.add_child(info)
	var head := _hbox(10)
	info.add_child(head)
	head.add_child(_portrait_rect(unit.sprite_id, 76))
	var hc := _vbox(2)
	head.add_child(hc)
	hc.add_child(_label(unit.display_name, 22, GOLD))
	hc.add_child(_label("%s · Lv%d" % [unit.role, sim.char_level(cid)], 15, Color(0.85, 0.9, 1)))
	if gi.is_empty():   # 무신앙: 신앙도가 쌓이지 않고 신앙 스킬도 없음
		hc.add_child(_label("믿음이 없습니다.", 17, Color(0.8, 0.82, 0.88)))
		info.add_child(_label("믿는 신이 없어 신앙도가 쌓이지 않고 배울 신앙 스킬도 없습니다.", 13, Color(0.75, 0.78, 0.85)))
	else:
		hc.add_child(_label("신앙도 %d" % sim.faith(cid), 17, gcol))
		info.add_child(_gauge("신앙도", float(sim.faith(cid)), float(sim.faith_max()), gcol, "%d / %d" % [sim.faith(cid), sim.faith_max()]))
		info.add_child(_label("신앙도는 퀘스트 · 대화 · 이벤트로 오름", 12, Color(0.7, 0.75, 0.85)))
		info.add_child(_label("신앙 스킬은 포인트 없이 배움 (임시 데이터)", 12, Color(0.7, 0.75, 0.85)))
	var learned := sim.faith_skill_list(cid).filter(func(fs): return sim.has_faith_skill(cid, fs.id))
	info.add_child(_label("배운 신앙 스킬", 15, Color(1, 0.95, 0.75)))
	if learned.is_empty():
		info.add_child(_label("(없음)", 12, Color(0.6, 0.64, 0.7)))
	for fs in learned:
		info.add_child(_label("· %s — %s" % [fs.name, fs.desc], 12, gcol.lightened(0.3)))
	# 오른쪽: 신 카드 + 신앙 스킬
	var right := _vbox(10)
	right.custom_minimum_size = Vector2(740, 560)
	row.add_child(right)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(gcol.darkened(0.8), 0.95), gcol, 10))
	right.add_child(card)
	var cv := _vbox(4)
	card.add_child(cv)
	if gi.is_empty():
		cv.add_child(_label("믿음이 없습니다.", 24, Color(0.85, 0.87, 0.92)))
		cv.add_child(_label("믿는 신이 없어 신앙 스킬이 비어 있습니다. 신앙도도 쌓이지 않습니다.", 14, Color(0.75, 0.78, 0.85)))
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(740, 200)
		empty.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.1, 0.12, 0.6), Color(0.3, 0.31, 0.35), 10))
		var el := _label("신앙 스킬 없음", 18, Color(0.5, 0.52, 0.58))
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_child(el)
		right.add_child(empty)
		return
	var gh := _hbox(12)
	cv.add_child(gh)
	var gid: String = sim.god_of(cid)
	var icon := GodIcon.make(gi, 64, "%s — 눌러서 세계관 도감" % gi.name)
	icon.pressed.connect(func(): open_codex("gods", gid))
	gh.add_child(icon)
	var gt := _vbox(2)
	gh.add_child(gt)
	gt.add_child(_label(str(gi.name), 24, gcol.lightened(0.2)))
	gt.add_child(_label(str(gi.desc), 14, Color(0.88, 0.9, 0.95)))
	gt.add_child(_label("아이콘을 누르면 세계관 도감", 12, Color(0.65, 0.7, 0.8)))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	right.add_child(grid)
	for fs in sim.faith_skill_list(cid):
		grid.add_child(_faith_card(cid, fs, gcol))
	# 다른 신들 (참고): 무엇을 믿느냐에 따라 스킬이 다름
	right.add_child(_label("다른 신의 신앙 스킬 (이 캐릭터는 배울 수 없음)", 14, Color(0.75, 0.78, 0.85)))
	for g in sim.battle.god_order:
		if g == sim.god_of(cid):
			continue
		var og: Dictionary = sim.battle.gods[g]
		var names := (sim.battle.faith_skills.get(g, []) as Array).map(func(x): return "%s(%d)" % [x.name, int(x.need)])
		var orow := _hbox(8)
		right.add_child(orow)
		var oi := GodIcon.make(og, 28, "%s — 눌러서 세계관 도감" % og.name)
		var gg: String = g
		oi.pressed.connect(func(): open_codex("gods", gg))
		orow.add_child(oi)
		var ol := _label("%s — %s" % [og.name, " · ".join(names)], 12, Color(og.color).darkened(0.15))
		ol.size_flags_vertical = SIZE_SHRINK_CENTER
		orow.add_child(ol)


## 신앙 스킬 카드 (miracle = true 면 기적 카드: 필요 의지 · '의지 부족')
func _faith_card(cid: String, fs: Dictionary, gcol: Color, miracle: bool = false) -> Control:
	var st := sim.miracle_state(cid, fs.id) if miracle else sim.faith_state(cid, fs.id)
	var word := "의지" if miracle else "신앙"
	var c := Control.new()
	c.custom_minimum_size = Vector2(176, 200)
	c.draw.connect(func():
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		var ncol := Color(1, 1, 1)
		match st:
			"learned":
				sb.bg_color = gcol.darkened(0.45)
				sb.border_color = gcol.lightened(0.3)
			"ready":
				sb.bg_color = Color(0.1, 0.12, 0.16)
				sb.border_color = gcol
				sb.set_border_width_all(3)
			_:
				sb.bg_color = Color(0.17, 0.17, 0.18)
				sb.border_color = Color(0.28, 0.28, 0.3)
				ncol = Color(0.45, 0.46, 0.5)
		var r := Rect2(Vector2.ZERO, c.size)
		c.draw_style_box(sb, r)
		c.draw_string(bold, Vector2(0, 30), str(fs.name), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 18, ncol)
		c.draw_string(font, Vector2(0, 54), "%s %d" % [word, int(fs.need)], HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 13, gcol if st != "no_faith" else ncol)
		c.draw_multiline_string(font, Vector2(10, 136), str(fs.desc), HORIZONTAL_ALIGNMENT_CENTER, c.size.x - 20, 14, -1, ncol.darkened(0.05))
		var sub: String = {"learned": "습득", "ready": "배우기 가능", "no_faith": ""}.get(st, "")
		c.draw_string(font, Vector2(0, c.size.y - 14), sub, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 13, gcol.lightened(0.4))
		if st == "no_faith":
			c.draw_rect(r.grow(-2), Color(0.1, 0.1, 0.1, 0.35))
			var t := "%s 부족" % word
			var ts := bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			var p := r.get_center() + Vector2(-ts.x * 0.5, ts.y * 0.35)
			c.draw_string_outline(bold, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, 0.8))
			c.draw_string(bold, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, SkillTreeView.RED))
	if st == "ready":
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.tooltip_text = "클릭: 배우기"
		c.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				var res := sim.learn_miracle(cid, fs.id) if miracle else sim.learn_faith_skill(cid, fs.id)
				show_toast(res.msg, GOOD if res.ok else BAD)
				close_top()
				open_skills(cid, "", "faith"))
	return c


## 기적 탭 (정체가 신인 캐릭터): 정체인 신 · 의지 · 그 캐릭터만의 기적. 전에 배운 신앙 스킬 효과는 그대로
func _miracle_page(row: HBoxContainer, cid: String) -> void:
	var unit: UnitData = GameData._find(sim.battle.allies, cid)
	var gi := sim.divine_god(cid)
	var gcol: Color = gi.get("color", Color(1, 0.9, 0.5))
	var info := _vbox(6)
	info.custom_minimum_size = Vector2(280, 560)
	row.add_child(info)
	var head := _hbox(10)
	info.add_child(head)
	head.add_child(_portrait_rect(unit.sprite_id, 76))
	var hc := _vbox(2)
	head.add_child(hc)
	hc.add_child(_label(unit.display_name + " ✦", 22, GOLD))
	hc.add_child(_label("%s · Lv%d" % [unit.role, sim.char_level(cid)], 15, Color(0.85, 0.9, 1)))
	hc.add_child(_label("의지 %d" % sim.will(cid), 17, gcol))
	info.add_child(_gauge("의지", float(sim.will(cid)), float(sim.will_max()), gcol, "%d / %d" % [sim.will(cid), sim.will_max()]))
	info.add_child(_label("출전할 때마다 의지 +%d · 기적은 신앙이 아니라 의지로 배움" % sim.data.inum("will_battle", 5), 12, Color(0.7, 0.75, 0.85)))
	info.add_child(_label("기적은 포인트 없이 배움 (임시 데이터)", 12, Color(0.7, 0.75, 0.85)))
	info.add_child(_label("배운 기적", 15, Color(1, 0.95, 0.75)))
	var learned := sim.miracle_list(cid).filter(func(m): return sim.miracle_state(cid, m.id) == "learned")
	if learned.is_empty():
		info.add_child(_label("(없음)", 12, Color(0.6, 0.64, 0.7)))
	for m in learned:
		info.add_child(_label("· %s — %s" % [m.name, m.desc], 12, gcol.lightened(0.3)))
	var old_fs := sim.faith_skill_list(cid).filter(func(fs): return sim.has_faith_skill(cid, fs.id))
	if not old_fs.is_empty():
		info.add_child(_label("전에 배운 신앙 스킬 (효과 유지)", 13, Color(0.75, 0.78, 0.85)))
		for fs in old_fs:
			info.add_child(_label("· %s — %s" % [fs.name, fs.desc], 12, Color(0.7, 0.74, 0.82)))
	var right := _vbox(10)
	right.custom_minimum_size = Vector2(740, 560)
	row.add_child(right)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(gcol.darkened(0.8), 0.95), gcol, 10))
	right.add_child(card)
	var gh := _hbox(12)
	card.add_child(gh)
	var gid := str(sim.divine_info(cid).get("god", ""))
	var icon := GodIcon.make(gi if not gi.is_empty() else {"name": "?"}, 64, "%s — 눌러서 세계관 도감" % gi.get("name", "?"))
	icon.pressed.connect(func(): open_codex("gods", gid))
	gh.add_child(icon)
	var gt := _vbox(2)
	gh.add_child(gt)
	gt.add_child(_label("정체 — %s" % gi.get("name", "?"), 24, gcol.lightened(0.2)))
	gt.add_child(_label(str(gi.get("desc", "")), 14, Color(0.88, 0.9, 0.95)))
	gt.add_child(_label("이 캐릭터는 신 — 신앙 대신 기적을 일으킵니다", 12, Color(0.65, 0.7, 0.8)))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	right.add_child(grid)
	for m in sim.miracle_list(cid):
		grid.add_child(_faith_card(cid, m, gcol, true))


# ---------------------------------------------------------------- 연구실 (로한): 연구 → 무기고 제작 해금
func open_research() -> void:
	var rid := sim.researcher_id()
	var who := sim.data.npc_name(rid) if rid != "" else "연구원"
	var win := _window("%s의 무기 연구" % who, 760)
	_research_section(win.body, win, true)


func _research_section(body: VBoxContainer, win: Dictionary, with_talk: bool = false) -> void:
	var rid := sim.researcher_id()
	if with_talk and rid != "":
		var row := _hbox(12)
		body.add_child(row)
		row.add_child(_portrait_rect(_sprite_of(rid), 84))
		var col := _vbox(4)
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(col)
		var line := "새 무기 설계요? 맡겨만 주세요." if sim.research.is_empty() else "지금 연구 중이에요. 조금만 기다려요."
		col.add_child(_label(sim.data.npc_name(rid), 17, GOLD))
		col.add_child(_label(line, 16))
		var talk := _button("대화", Color(0.45, 0.7, 0.9), 13, 70)
		talk.size_flags_vertical = SIZE_SHRINK_BEGIN
		talk.pressed.connect(func():
			close_top()
			open_dialogue(rid))
		row.add_child(talk)
	body.add_child(_label("연구를 끝내면 그 무기를 무기고에서 제작할 수 있습니다 · 한 번에 하나 · 비용은 시작할 때\n%s 이(가) 연구실에서 깨어 있을 때만 진행 (밥 먹으러 가거나 자면 멈춤)" % (sim.data.npc_name(rid) if rid != "" else "연구원"), 13, Color(0.75, 0.8, 0.9)))
	if not sim.research.is_empty():
		var q: Dictionary = sim.data.research.get(str(sim.research.id), {})
		var done := int(sim.research.total) - int(sim.research.remaining)
		var why := sim.research_pause_reason()
		body.add_child(_gauge("진행", float(done), maxf(1.0, float(sim.research.total)), Color(0.45, 0.85, 1.0),
			"%s — 남은 %d분%s" % [q.get("name", ""), int(sim.research.remaining), "  (멈춤: %s)" % why if why != "" else ""]))
	var list := _scroll(body, 280)
	for qid in sim.data.research_order:
		var q: Dictionary = sim.data.research[qid]
		var st := sim.research_state(qid)
		var row := _hbox(10)
		list.add_child(row)
		var items := PackedStringArray()
		for rcp in q.unlocks:
			items.append(sim.item_name(str(sim.data.recipes.get(rcp, {}).get("item", rcp))))
		var col := _vbox(2)
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(col)
		var head := "%s  →  %s" % [q.name, ", ".join(items)]
		col.add_child(_label(head, 16, GOOD if st == "done" else (GOLD if st == "active" else (Color(0.55, 0.58, 0.65) if st == "locked" else Color(1, 1, 1)))))
		var sub := "$%d · %d분" % [int(q.cost), int(q.minutes)]
		if q.prereq != "":
			sub += " · 선행: %s" % sim.data.research.get(q.prereq, {}).get("name", q.prereq)
		if str(q.desc) != "":
			sub += " · %s" % q.desc
		col.add_child(_label(sub, 13, Color(0.7, 0.75, 0.85)))
		var b := _button({"done": "완료 ✓", "active": "연구 중", "locked": "잠김", "ready": "연구 시작"}[st], Color(0.45, 0.85, 1.0), 14, 100)
		b.disabled = st != "ready" or not sim.research.is_empty() or sim.ledger.cash < int(q.cost)
		b.pressed.connect(func():
			var res := sim.start_research(qid)
			show_toast(res.msg, GOOD if res.ok else BAD)
			close_top()
			open_research())
		row.add_child(b)


## 무기고: 대원별 장착 (주무기/보조1/보조2)
func _armory_section(body: VBoxContainer) -> void:
	body.add_child(_label("장착 (전투에 반영)", 16, Color(1, 0.95, 0.75)))
	for id in sim.data.npc_order:
		var n: NpcAgent = sim.npcs[id]
		if not sim.is_combatant(n):
			continue   # 연구원 등 전투에 나가지 않는 대원
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
	body.add_child(_label("친밀도 선물 — 대원을 클릭한 대화창에서 '선물하기'. 대원마다 좋아하는 선물과 오르는 친밀도가 다름", 14, AFFINITY_COL))
	for g in sim.data.px_order:
		var it: Dictionary = sim.data.px_items[g]
		var row := _hbox(10)
		body.add_child(row)
		var col := _vbox(0)
		col.custom_minimum_size.x = 470
		row.add_child(col)
		col.add_child(_label("%s — $%d · 기본 친밀도 +%d · 보유 %d" % [it.name, it.price, it.base, int(sim.gifts.get(g, 0))], 15))
		var fans := sim.data.npc_order.filter(func(nid): return sim.data.gift_value(g, nid) > int(it.base))
		fans.sort_custom(func(a, b): return sim.data.gift_value(g, a) > sim.data.gift_value(g, b))
		var fan_txt := ", ".join(fans.map(func(nid): return "%s +%d" % [sim.data.npc_name(nid), sim.data.gift_value(g, nid)]))
		col.add_child(_label("  ♥ " + (fan_txt if fan_txt != "" else "좋아하는 대원 없음"), 13, AFFINITY_COL.darkened(0.1)))
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
		var open := sim.recipe_unlocked(rid)
		var need: String = "" if open else str(sim.data.research.get(sim.recipe_research(rid), {}).get("name", ""))
		g.add_child(_label("%s → %s (%d분)%s" % [r.name, sim.item_name(r.item), r.minutes, "" if open else "  — 연구 필요: " + need], 14,
			Color(1, 1, 1) if open else Color(0.55, 0.58, 0.65)))
		var b := _button("제작" if open else "잠김", Color(0.45, 0.7, 0.9), 13, 70)
		b.disabled = not w.is_empty() or not open
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
## 우클릭 메뉴: 그 대원이 지금 있는 방에서 할 행동 (도착해 있을 때) + 어디서나 할 지시
func open_context(npc_id: String, at: Vector2) -> void:
	var n: NpcAgent = sim.npcs[npc_id]
	var pm := PopupMenu.new()
	pm.add_theme_font_override("font", font)
	pm.add_theme_font_size_override("font_size", 15)
	pm.add_separator(n.name)
	pm.add_item("대화", 0)
	if sim.is_researcher(npc_id):
		pm.add_item("무기 연구", 7)
	if sim.is_combatant(n):
		pm.add_item("정보·장비", 4)
		pm.add_item("스킬 트리 (Lv%d%s)" % [sim.char_level(n.character_id), " · 포인트 %d" % sim.skill_points(n.character_id) if sim.skill_points(n.character_id) > 0 else ""], 8)
	pm.set_item_disabled(pm.get_item_index(0), n.state == NpcAgent.UNAVAILABLE)
	var room_ids := {}
	if n.state == NpcAgent.MOVING:
		pm.add_separator("%s 로 가는 중 — 도착하면 행동" % sim.data.facility_name(n.dest))
	elif n.state != NpcAgent.UNAVAILABLE:
		pm.add_separator("%s 에서" % sim.data.facility_name(n.facility))
		var acts := sim.room_actions(npc_id)
		if acts.is_empty():
			pm.add_item("(이 방에서 할 수 있는 일 없음)", 99)
			pm.set_item_disabled(pm.get_item_index(99), true)
		for i in acts.size():
			var act: Dictionary = acts[i]
			var id := 100 + i
			room_ids[id] = act.id
			pm.add_item(act.label if act.enabled or str(act.why) == "" else "%s — %s" % [act.label, act.why], id)
			pm.set_item_disabled(pm.get_item_index(id), not act.enabled)
	pm.add_separator("어디서나")
	pm.add_item("업무·의뢰 지시", 2)
	if sim.is_combatant(n):
		pm.add_item("훈련실로 (훈련)", 3)
	pm.add_item("의무실로 (치료·휴식)", 5)
	if not n.command.is_empty() and n.state != NpcAgent.UNAVAILABLE:
		pm.add_item("지시 그만두기 → 일정대로", 6)
	# 메뉴 아이콘 (UI 패키지): 대화 · 연구 · 정보 · 스킬 · 의뢰
	pm.add_theme_constant_override("icon_max_width", 22)
	for pair in [[0, "mail"], [7, "search"], [4, "book"], [8, "skill"], [2, "contract"]]:
		var ix := pm.get_item_index(pair[0])
		if ix >= 0:
			pm.set_item_icon(ix, load(UI_DIR + "icons/%s.png" % pair[1]))
	pm.set_item_disabled(pm.get_item_index(2), not n.is_free())
	if sim.is_combatant(n):
		pm.set_item_disabled(pm.get_item_index(3), not n.is_free() or sim.training_facility() == "")
	var cs := sim.cstate(n)
	pm.set_item_disabled(pm.get_item_index(5), not n.is_free() or sim.infirmary_facility() == "" or ((cs.statuses as Array).is_empty() and float(cs.hp) >= sim.char_max_hp(sim.ckey(n))))
	add_child(pm)
	pm.id_pressed.connect(func(id): _on_context(id, npc_id, room_ids.get(id, "")))
	pm.popup_hide.connect(pm.queue_free)
	pm.position = Vector2i(at)
	pm.popup()


func _on_context(id: int, npc_id: String, room_act: String = "") -> void:
	var r := {}
	match room_act:
		"sleep", "rest", "eat":
			r = sim.issue_activity(npc_id, room_act)
		"train":
			r = sim.issue_train(npc_id)
		"medical":
			r = sim.issue_medical(npc_id)
		"jobs":
			open_contracts(npc_id)
		"facility":
			open_facility(sim.npcs[npc_id].facility)
		"research":
			open_research()
	if not r.is_empty():
		show_toast(r.msg, GOOD if r.ok else BAD)
		_sel_t = 0.0
		return
	if room_act != "":
		return
	match id:
		0:
			open_dialogue(npc_id)
		2:
			open_contracts(npc_id)
		3:
			var r3 := sim.issue_train(npc_id)
			show_toast(r3.msg, GOOD if r3.ok else BAD)
		4:
			open_character(npc_id)
		5:
			var r5 := sim.issue_medical(npc_id)
			show_toast(r5.msg, GOOD if r5.ok else BAD)
		6:
			var r6 := sim.cancel_command(npc_id)
			show_toast(r6.msg, GOOD if r6.ok else BAD)
		7:
			open_research()
		8:
			open_skills(sim.npcs[npc_id].character_id)


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


# ---------------------------------------------------------------- 컷씬 (data/cutscenes.json — 에디터 '컷씬' 탭, 재생 화면은 CutscenePlayer)
## 창이 열려 있으면 닫힌 뒤에. 재생 중엔 모달로 쳐서 시간이 멈춤. on_end = 다 본 뒤 (말 걸기 컷씬이면 대화 끝내기)
func play_cutscene(id: String, from: int = 0, on_end: Callable = Callable()) -> void:
	if sim.cutscene_def(id).is_empty():
		if on_end.is_valid():
			on_end.call()
		return
	if modal_open():
		enqueue(func(): play_cutscene(id, from, on_end))
		return
	var p := CutscenePlayer.new()
	p.defs = CutsceneData.by_id(sim.cutscene_defs())
	p.npcs = sim.data.npcs
	add_child(p)
	_modals.append(p)
	p.set_meta("on_close", func(): p.skip_all())   # close_top · close_all 로 닫혀도 남은 행동은 적용
	p.cutscene_started.connect(func(cid): sim.mark_cutscene_seen(cid))
	p.action_requested.connect(func(st):
		var r := sim.apply_cutscene_action(st)
		if str(st.do) != "affinity":
			show_toast(str(r.msg), GOOD if r.ok else BAD))
	p.finished.connect(func(_last):
		_modals.erase(p)
		p.queue_free()
		if on_end.is_valid():
			on_end.call()
		_after_modal())
	p.play(id, from)


## 대기열의 컷씬 (창이 없을 때 하나씩)
func _pump_cutscenes() -> void:
	if modal_open():
		return
	var id := sim.next_cutscene()
	if id != "":
		play_cutscene(id)


func playing_cutscene() -> bool:
	return _modals.any(func(m): return m is CutscenePlayer)


# ---------------------------------------------------------------- 퀘스트 (data/quests.json — 에디터 '퀘스트' 탭, 진행은 BaseSim)
## 단계 i 의 표시 글 (desc 가 있으면 그것, 없으면 자동 설명)
func _quest_step_line(qid: String, i: int) -> String:
	var q := sim.quest_def(qid)
	if q.is_empty() or i >= (q.steps as Array).size():
		return ""
	var st: Dictionary = q.steps[i]
	return str(st.desc) if str(st.desc) != "" else QuestData.step_text(st, QuestData.target_names(sim.data, sim.battle, sim.quest_defs()))


## 퀘스트 기록: 진행 중 → 완료 (시작 안 한 퀘스트는 안 보임). pick = 펼쳐 둘 퀘스트 id
func open_quests(pick: String = "") -> void:
	var win := _window("퀘스트", 820)
	var body: VBoxContainer = win.body
	var names := QuestData.target_names(sim.data, sim.battle, sim.quest_defs())
	var active := sim.quest_defs().filter(func(q): return sim.quest_status(q.id) == "active")
	var done := sim.quest_defs().filter(func(q): return sim.quest_status(q.id) == "done")
	body.add_child(_label("진행 중 %d · 완료 %d — 단계는 앞에서부터 하나씩, 마지막 단계를 끝내면 보상 (현금은 주간 결산 때 지급)" % [active.size(), done.size()], 13, Color(0.75, 0.8, 0.9)))
	var list := _scroll(body, 540)
	if active.is_empty() and done.is_empty():
		list.add_child(_label("아직 받은 퀘스트가 없습니다", 16, Color(0.75, 0.8, 0.9)))
	for q in active + done:
		list.add_child(_quest_card(q, names, pick == "" or pick == q.id))


func _quest_card(q: Dictionary, names: Dictionary, open: bool) -> Control:
	var fin := sim.quest_status(q.id) == "done"
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.1, 0.13, 0.96) if not fin else Color(0.07, 0.09, 0.08, 0.9),
		QUEST_COL.darkened(0.25) if not fin else Color(0.3, 0.5, 0.36), 8))
	var row := _hbox(12)
	pc.add_child(row)
	var giver: Dictionary = sim.data.npcs.get(str(q.giver), {})
	if not giver.is_empty():
		row.add_child(_portrait_rect(str(giver.sprite), 64))
	var col := _vbox(4)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(col)
	var head := _hbox(8)
	col.add_child(head)
	head.add_child(_label(("✓ " if fin else "◆ ") + str(q.name), 18, GOOD if fin else QUEST_COL))
	var pr := sim.quest_progress(q.id)
	head.add_child(_label("완료 (%d일차)" % int(sim.quests[q.id].finished) if fin else "%d / %d 단계" % [int(pr.step) + 1, int(pr.total)], 13, Color(0.75, 0.8, 0.9)))
	if not giver.is_empty():
		head.add_child(_label("의뢰인 " + str(giver.name), 13, Color(0.7, 0.85, 1.0)))
	if str(q.desc) != "" and (open or not fin):
		var d := _label(str(q.desc), 13, Color(0.85, 0.88, 0.95))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 640
		col.add_child(d)
	if open or not fin:
		var steps: Array = q.steps
		for i in steps.size():
			var st: Dictionary = steps[i]
			var txt := str(st.desc) if str(st.desc) != "" else QuestData.step_text(st, names)
			var cur := not fin and i == int(pr.step)
			var mark := "✓" if fin or i < int(pr.step) else ("▶" if cur else "·")
			var extra := ""
			if cur and int(pr.need) > 1:
				extra = "  (%d / %d)" % [int(pr.have), int(pr.need)]
			var c := GOOD.darkened(0.15) if fin or i < int(pr.step) else (Color(1, 0.95, 0.75) if cur else Color(0.55, 0.58, 0.65))
			var l := _label("  %s %d. %s%s" % [mark, i + 1, txt if i <= int(pr.step) or fin else "???", extra], 14, c)
			col.add_child(l)
		var rw: Dictionary = q.rewards
		var got := PackedStringArray()
		if int(rw.cash) > 0:
			got.append("$%d" % int(rw.cash))
		if int(rw.affinity) != 0 and not giver.is_empty():
			got.append("%s 친밀도 %+d" % [giver.name, int(rw.affinity)])
		var fc := sim.quest_faith_char(q)
		if int(rw.get("faith", 0)) != 0 and fc != "":
			got.append("%s 신앙도 %+d%s" % [_char_name(fc), int(rw.faith), " (믿음이 없어 안 쌓임)" if sim.faithless(fc) else ""])
		for cid in _quest_divine(q.id):
			got.append("??? (%s의 비밀)" % _char_name(cid) if not sim.is_divine(cid) else "✦ %s의 정체" % _char_name(cid))
		if not got.is_empty():
			col.add_child(_label("보상: " + " · ".join(got), 13, GOLD))
	return pc


## 이 퀘스트를 끝내면 정체가 드러나는 신 해금 캐릭터
func _quest_divine(qid: String) -> Array:
	var out := []
	if sim.battle != null:
		for cid in sim.battle.divine:
			var c: Dictionary = sim.battle.divine[cid].condition
			if str(c.type) == "quest" and str(c.get("target", "")) == "quest:" + qid:
				out.append(cid)
	return out


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
		col.add_child(_label("전투: %s Lv%d · HP %d (훈련 %d단계) · 속도 %d" % [u.role, sim.char_level(u.id), sim.char_max_hp(u.id), lv, u.speed], 15, GOLD))
		var gi := sim.god_info(u.id)
		if not gi.is_empty():
			var grow := _hbox(8)
			col.add_child(grow)
			var gic := GodIcon.make(gi, 30, "%s — 눌러서 세계관 도감" % gi.name)
			var ug: String = sim.god_of(u.id)
			gic.pressed.connect(func(): open_codex("gods", ug))
			grow.add_child(gic)
			var gl := _label("믿는 신: %s · 신앙도 %d" % [gi.name, sim.faith(u.id)], 14, Color(gi.color).lightened(0.2))
			gl.size_flags_vertical = SIZE_SHRINK_CENTER
			grow.add_child(gl)
		var sk := _button("스킬 트리  (포인트 %d)" % sim.skill_points(u.id), Color(0.85, 0.6, 1.0), 14)
		sk.pressed.connect(func():
			close_top()
			open_skills(u.id))
		col.add_child(sk)
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


# ---------------------------------------------------------------- 세계관 도감 (data/codex.json · 탭: 등장인물 · 몬스터 · 상태이상 · 종교(신) · 도시 배경)
const CODEX_COL := {"characters": Color(0.55, 0.8, 1.0), "monsters": Color(1.0, 0.5, 0.4), "statuses": Color(0.85, 0.6, 1.0), "gods": Color(1.0, 0.85, 0.45), "cities": Color(0.5, 0.95, 0.7)}


## tab = CodexData.TABS id, pick = 항목 id ("" = 첫 항목). 신 아이콘을 누르면 open_codex("gods", 신 id)
func open_codex(tab: String = "characters", pick: String = "") -> void:
	var codex := CodexData.read()
	var list := CodexData.entries(codex, tab, sim.battle, sim.data.npcs)
	var cur: Dictionary = {}
	for e in list:
		if e.id == pick:
			cur = e
	if cur.is_empty() and not list.is_empty():
		cur = list[0]
	var win := _window("세계관 도감", 1140)
	var body: VBoxContainer = win.body
	var tabs := _hbox(6)
	body.add_child(tabs)
	for t in CodexData.TABS:
		var tb := _button(t[1], CODEX_COL[t[0]] if t[0] == tab else Color(0.45, 0.55, 0.7), 15, 130)
		tb.custom_minimum_size.y = 40
		var tt: String = t[0]
		tb.pressed.connect(func():
			if tt != tab:
				close_top()
				open_codex(tt))
		tabs.add_child(tb)
	var main := _hbox(12)
	body.add_child(main)
	# 왼쪽: 항목 목록 (위아래 스크롤)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(260, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(sc)
	var lv := _vbox(4)
	lv.size_flags_horizontal = SIZE_EXPAND_FILL
	sc.add_child(lv)
	var cur_btn: Button = null
	for e in list:
		var sel: bool = e.id == cur.get("id", "")
		var b := _button(str(e.title), CODEX_COL[tab] if sel else Color(0.4, 0.48, 0.62), 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(244, 46)
		if str(e.get("sprite", "")) != "":
			b.icon = UnitArt.portrait(e.sprite, manifest)
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 38)
		if str(e.get("color", "")).begins_with("#"):
			b.add_theme_color_override("font_color", Color.html(e.color).lightened(0.25))
		if sel:
			cur_btn = b
		var eid: String = e.id
		b.pressed.connect(func():
			close_top()
			open_codex(tab, eid))
		lv.add_child(b)
	if cur_btn != null:
		sc.ensure_control_visible.call_deferred(cur_btn)
	# 오른쪽: 내용
	var rs := ScrollContainer.new()
	rs.custom_minimum_size = Vector2(840, 560)
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(rs)
	var det := _vbox(10)
	det.size_flags_horizontal = SIZE_EXPAND_FILL
	rs.add_child(det)
	if cur.is_empty():
		det.add_child(_label("항목이 없습니다 (data/codex.json)", 16, Color(0.75, 0.8, 0.9)))
		return
	_codex_detail(det, tab, cur)


func _codex_badge(text: String, col: Color, size: float) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(size, size)
	pc.add_theme_stylebox_override("panel", _panel_style(Color(col.darkened(0.6), 0.95), col, 12))
	var l := _label(text, int(size * 0.42), col.lightened(0.3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


func _codex_detail(det: VBoxContainer, tab: String, e: Dictionary) -> void:
	var gd: GameData = sim.battle
	var head := _hbox(16)
	det.add_child(head)
	var col: Color = Color.html(e.color) if str(e.get("color", "")).begins_with("#") else CODEX_COL[tab]
	match tab:
		"characters", "monsters":
			head.add_child(_portrait_rect(str(e.get("sprite", "")), 120))
		"gods":
			head.add_child(GodIcon.make(gd.gods.get(e.id, {"name": e.title}), 120, str(e.title)))
		"statuses":
			head.add_child(_codex_badge(str(StatusCatalog.get_def(e.id).get("short", str(e.title).substr(0, 1))), col, 110))
		_:
			head.add_child(_codex_badge(str(e.title).substr(0, 1), col, 110))
	var hv := _vbox(4)
	hv.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(hv)
	hv.add_child(_label(str(e.title), 28, col.lightened(0.2) if tab in ["gods", "statuses", "cities"] else GOLD))
	if str(e.subtitle) != "":
		hv.add_child(_label(str(e.subtitle), 16, Color(0.8, 0.85, 0.95)))
	var bl := _label(str(e.body), 16, Color(0.92, 0.94, 0.98))
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size.x = 800
	det.add_child(bl)
	det.add_child(HSeparator.new())
	match tab:
		"characters":
			var u: UnitData = GameData._find(gd.allies, e.id) if gd != null else null
			if u != null:
				det.add_child(_label("기록", 17, Color(1, 0.95, 0.75)))
				det.add_child(_label("%s · Lv%d · 키 %dcm · HP %d · 속도 %d · AP %d · 방어 %d · %s" % [u.role, sim.char_level(u.id), roundi(u.height_cm), sim.char_max_hp(u.id), u.speed, u.max_ap, u.defense,
					"원거리" if u.range_type == "ranged" else "근접"], 15, Color(0.85, 0.9, 1)))
				if sim.is_divine(u.id):   # 정체가 드러난 신 (잠겨 있으면 안 보임)
					var dg := sim.divine_god(u.id)
					var dr := _hbox(10)
					det.add_child(dr)
					dr.add_child(_label("정체", 15, Color(1, 0.9, 0.5)))
					var dic := GodIcon.make(dg, 36, "%s — 종교(신) 탭" % dg.get("name", ""))
					var dgid := str(sim.divine_info(u.id).god)
					dic.pressed.connect(func():
						close_top()
						open_codex("gods", dgid))
					dr.add_child(dic)
					var dl := _label("%s (신) · 의지 %d" % [dg.get("name", "?"), sim.will(u.id)], 15, Color(dg.get("color", GOLD)).lightened(0.2))
					dl.size_flags_vertical = SIZE_SHRINK_CENTER
					dr.add_child(dl)
				var gi := sim.god_info(u.id)
				var gr := _hbox(10)
				det.add_child(gr)
				gr.add_child(_label("믿는 신", 15, Color(0.8, 0.84, 0.92)))
				if gi.is_empty():
					gr.add_child(_label("무신앙", 15, Color(0.7, 0.72, 0.78)))
				else:
					var ic := GodIcon.make(gi, 36, "%s — 종교(신) 탭" % gi.name)
					var g: String = sim.god_of(u.id)
					ic.pressed.connect(func():
						close_top()
						open_codex("gods", g))
					gr.add_child(ic)
					var gl := _label("%s · 신앙도 %d" % [gi.name, sim.faith(u.id)], 15, Color(gi.color).lightened(0.2))
					gl.size_flags_vertical = SIZE_SHRINK_CENTER
					gr.add_child(gl)
			elif sim.data.npcs.has(e.id):
				det.add_child(_label(str(sim.data.npcs[e.id].get("desc", "")), 15, Color(0.85, 0.9, 1)))
		"monsters":
			var m: UnitData = gd.monsters.get(e.id) if gd != null else null
			if m != null:
				det.add_child(_label("기록", 17, Color(1, 0.95, 0.75)))
				det.add_child(_label("Lv%d · HP %d · 속도 %d · AP %d · 방어 %d · 차지 %d칸" % [m.level, m.max_hp, m.speed, m.max_ap, m.defense, m.row_span], 15, Color(0.85, 0.9, 1)))
				var names := m.skill_ids.map(func(sid): return gd.actions[sid].display_name if gd.actions.has(sid) else sid)
				det.add_child(_label("쓰는 기술: " + " · ".join(names), 15, Color(0.85, 0.9, 1)))
		"statuses":
			var sd := StatusCatalog.get_def(e.id)
			var eff := StatusCatalog.effect_of(e.id)
			det.add_child(_label("효과: %s (%s)" % [StatusCatalog.EFFECTS.get(eff, {}).get("name", eff), "긍정" if sd.get("positive", false) else "부정"], 17, Color(1, 0.95, 0.75)))
			var rl := _label(str(sd.get("desc", "")).replace("{t}", "n").replace("{v}", "v"), 15, Color(0.85, 0.9, 1))
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size.x = 800
			det.add_child(rl)
			if gd != null:
				var users := PackedStringArray()
				for sid in gd.actions:
					if (gd.actions[sid] as ActionData).status_ids().has(e.id):
						users.append(gd.actions[sid].display_name)
				det.add_child(_label("이 상태를 거는 기술: " + (" · ".join(users) if not users.is_empty() else "없음"), 15, Color(0.85, 0.9, 1)))
		"gods":
			if gd != null and gd.gods.has(e.id):
				det.add_child(_label(str(gd.gods[e.id].desc), 15, Color(0.85, 0.9, 1)))
				det.add_child(_label("믿는 대원", 17, Color(1, 0.95, 0.75)))
				var br := _hbox(8)
				det.add_child(br)
				var any := false
				for u in gd.allies:
					if sim.god_of(u.id) != e.id:
						continue
					any = true
					var b := _button("%s  신앙 %d" % [u.display_name, sim.faith(u.id)], Color(0.45, 0.6, 0.8), 14)
					b.icon = UnitArt.portrait(u.sprite_id, manifest)
					b.expand_icon = true
					b.add_theme_constant_override("icon_max_width", 34)
					var uid: String = u.id
					b.pressed.connect(func():
						close_top()
						open_codex("characters", uid))
					br.add_child(b)
				if not any:
					br.add_child(_label("없음", 15, Color(0.7, 0.72, 0.78)))
				det.add_child(_label("신앙 스킬", 17, Color(1, 0.95, 0.75)))
				for fs in gd.faith_skills.get(e.id, []):
					det.add_child(_label("신앙 %d · %s — %s" % [int(fs.need), fs.name, fs.desc], 15, col.lightened(0.3)))


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
	body.add_child(_label("잔액 $%d · 미지급 $%d (다음 결산 때) · 장군 충성심 %d" % [sim.ledger.cash, sim.ledger.pending_total(), sim.loyalty], 18, GOLD))
	var list := _scroll(body, 380)
	for p in sim.ledger.pending:
		list.add_child(_label("[미지급] %s  %s$%d" % [p.label, "+" if int(p.amount) >= 0 else "-", absi(int(p.amount))], 14, Color(0.7, 0.85, 1) if int(p.amount) >= 0 else BAD))
	var es: Array = sim.ledger.entries.duplicate()
	es.reverse()
	for e in es.slice(0, 60):
		list.add_child(_label("%s  %s  %s$%d" % [e.date, e.label, "+" if int(e.amount) >= 0 else "-", absi(int(e.amount))], 14, GOOD if int(e.amount) >= 0 else BAD))


# ---------------------------------------------------------------- 결산 · 납품 · 장군 점검
func open_statement(st: Dictionary) -> void:
	var win := _window("%d주차 결산" % (int(st.week) + 1), 560)
	var body: VBoxContainer = win.body
	body.add_child(_label(str(st.date), 14, Color(0.75, 0.8, 0.9)))
	if st.has("rate"):
		var dl: Dictionary = st.get("delivery", {})
		var parts := PackedStringArray()
		for it in dl.get("req", {}):
			parts.append("%s %d/%d" % [sim.item_label(it), mini(int(dl.done.get(it, 0)), int(dl.req[it])), int(dl.req[it])])
		body.add_child(_label("납품 %d%%  —  %s" % [roundi(float(st.rate) * 100.0), " · ".join(parts) if not parts.is_empty() else "목록 없음"], 14, Color(0.85, 0.9, 1)))
	for it in st.items:
		var amt := int(it.amount)
		body.add_child(_label("%s   %s$%d" % [it.label, "+" if amt >= 0 else "-", absi(amt)], 16, (GOLD if amt >= 0 else BAD) if it.source == "general" else Color(1, 1, 1)))
	body.add_child(_label("합계 %s$%d  →  잔액 $%d" % ["+" if int(st.total) >= 0 else "-", absi(int(st.total)), st.cash], 21, GOOD if int(st.total) >= 0 else BAD))


## 충성심 막대 (0~100)
func _loyalty_bar(w: float = 260.0) -> Control:
	var row := _hbox(8)
	row.add_child(_label("장군 충성심", 15, Color(0.9, 0.9, 0.8)))
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = sim.loyalty
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(w, 14)
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.85, 0.7, 0.3) if sim.loyalty >= 30 else BAD
	fg.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.13, 0.12)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	row.add_child(_label("%d / 100" % sim.loyalty, 15, GOLD))
	return row


## 장군 점검: 장군이 아이템을 요구 → 준다 / 안 준다 / 나중에 (결산 전까지 '납품' 창에서 대답)
func open_inspection(rec: Dictionary) -> void:
	var win := _window("장군 점검 (%s)" % rec.month, 560)
	var body: VBoxContainer = win.body
	body.add_child(_label(str(rec.get("date", "")), 14, Color(0.75, 0.8, 0.9)))
	var item := str(rec.get("item", ""))
	if item == "":
		body.add_child(_label("장군이 기지를 한 바퀴 둘러보고 돌아갔습니다.", 17))
		body.add_child(_loyalty_bar())
		return
	var row := _hbox(12)
	body.add_child(row)
	var badge := TextureRect.new()
	badge.texture = load(UI_DIR + "icons/sword.png")
	badge.custom_minimum_size = Vector2(64, 64)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(badge)
	var col := _vbox(4)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label("장군", 17, GOLD))
	var line := str(rec.get("line", ""))
	var t := _label("\"%s\"" % (line if line != "" else "%s %d개를 내놓게." % [sim.item_label(item), int(rec.count)]), 17)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 440
	col.add_child(t)
	var have := sim.loot_count(item)
	body.add_child(_label("요구: %s ×%d   ·   창고에 %d개" % [sim.item_label(item), int(rec.count), have], 16, GOOD if have >= int(rec.count) else BAD))
	body.add_child(_loyalty_bar())
	if str(rec.get("answer", "")) != "":
		body.add_child(_label("이미 대답했습니다: %s" % ("줬음" if rec.answer == "give" else "거절"), 15, Color(0.75, 0.8, 0.9)))
		return
	var sp := sim.supply()
	var btns := _hbox(8)
	btns.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(btns)
	var give := _button("준다  (결산 +$%d · 충성심 %+d)" % [sp.inum("general_bonus", 40), sp.inum("loyalty_give", 5)], Color(0.45, 0.9, 0.55), 15)
	give.disabled = have < int(rec.count)
	if give.disabled:
		give.tooltip_text = "창고에 %d개가 있어야 합니다 — 전투 승리 · 대원에게서 얻음" % int(rec.count)
	var refuse := _button("안 준다  (결산 -$%d · 충성심 %d)" % [sp.inum("general_penalty", 40), sp.inum("loyalty_refuse", -10)], Color(1.0, 0.45, 0.4), 15)
	var later := _button("나중에", Color(0.6, 0.6, 0.65), 15)
	later.tooltip_text = "이번 주 결산 전까지 '납품' 창에서 대답 — 그때까지 대답이 없으면 거절"
	for b in [give, refuse, later]:
		btns.add_child(b)
	give.pressed.connect(func():
		var r := sim.answer_demand(true)
		show_toast(r.msg, GOOD if r.ok else BAD)
		if r.ok:
			close_top())
	refuse.pressed.connect(func():
		var r := sim.answer_demand(false)
		show_toast(r.msg, BAD if r.ok else BAD)
		close_top())
	later.pressed.connect(close_top)


## 납품 창: 이번 주 납품 목록(창고에서 내기) · 예상 주급 · 장군 충성심과 대답 기다리는 요구 · 전리품 창고
func open_supply() -> void:
	var win := _window("납품 · 장군", 700)
	_fill_supply(win.body)


func _fill_supply(body: VBoxContainer) -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var left := sim.minutes_to_settlement()
	var d := sim.delivery()
	body.add_child(_label("%d주차 납품 목록  ·  결산 D-%d (%d일 %d시간)  ·  스토리 진행률 %d%%" % [sim.week_now() + 1, ceili(left / 1440.0), floori(left / 1440.0),
		floori(fmod(left, 1440.0) / 60.0), roundi(sim.story_progress())], 15, Color(0.85, 0.9, 1)))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for h in ["물품", "필요", "냄", "창고", "", ""]:
		grid.add_child(_label(h, 13, Color(0.7, 0.75, 0.8)))
	for it in d.req:
		var need := int(d.req[it])
		var done := int(d.done.get(it, 0))
		var have := sim.loot_count(it)
		grid.add_child(_label(sim.item_label(it), 16, GOOD if done >= need else Color(1, 1, 1)))
		grid.add_child(_label(str(need), 16))
		grid.add_child(_label(str(done), 16, GOOD if done >= need else GOLD))
		grid.add_child(_label(str(have), 16, Color(0.8, 0.85, 0.9)))
		var one := _button("1개 내기", Color(0.55, 0.65, 0.42), 13)
		var all := _button("모두 내기", Color(0.55, 0.65, 0.42), 13)
		one.disabled = done >= need or have <= 0
		all.disabled = one.disabled
		var item: String = it
		one.pressed.connect(func():
			var r := sim.deliver(item, 1)
			show_toast(r.msg, GOOD if r.ok else BAD)
			_fill_supply(body))
		all.pressed.connect(func():
			var r := sim.deliver(item, 999)
			show_toast(r.msg, GOOD if r.ok else BAD)
			_fill_supply(body))
		grid.add_child(one)
		grid.add_child(all)
	if d.req.is_empty():
		body.add_child(_label("이번 주 납품 목록 없음 (data/supply.xlsx 납품)", 14, Color(0.7, 0.75, 0.8)))
	var base := sim.supply().inum("base_pay", 150)
	body.add_child(_label("납품 %d%%  →  이번 주 주급 $%d  (기본 $%d × 납품 비율)" % [roundi(sim.delivery_rate() * 100.0), sim.expected_pay(), base], 19, GOLD))
	body.add_child(HSeparator.new())
	body.add_child(_loyalty_bar())
	var dm := sim.pending_demand()
	if not dm.is_empty():
		var have2 := sim.loot_count(str(dm.item))
		body.add_child(_label("장군 요구 (대답 기다림): %s ×%d  ·  창고 %d개  —  결산 전까지 대답 없으면 거절" % [sim.item_label(str(dm.item)), int(dm.count), have2], 15, GOLD))
		var row := _hbox(8)
		body.add_child(row)
		var give := _button("준다", Color(0.45, 0.9, 0.55), 14, 90)
		give.disabled = have2 < int(dm.count)
		var refuse := _button("안 준다", Color(1.0, 0.45, 0.4), 14, 90)
		give.pressed.connect(func():
			var r := sim.answer_demand(true)
			show_toast(r.msg, GOOD if r.ok else BAD)
			_fill_supply(body))
		refuse.pressed.connect(func():
			var r := sim.answer_demand(false)
			show_toast(r.msg, BAD)
			_fill_supply(body))
		row.add_child(give)
		row.add_child(refuse)
	else:
		var ins := sim.inspection_this_month()
		var st: String = "아직 (날짜 모름)" if not ins.get("done", false) else {"give": "요구에 응함", "refuse": "요구 거절", "none": "요구 없음"}.get(str(ins.get("answer", "")), "")
		body.add_child(_label("이번 달 장군 점검: %s" % st, 14, Color(0.8, 0.85, 0.9)))
	body.add_child(HSeparator.new())
	body.add_child(_label("전리품 창고 (전투 승리 · 대원에게서 얻음)", 15, Color(0.9, 0.9, 0.8)))
	var parts := PackedStringArray()
	for it in sim.supply().item_order:
		if sim.loot_count(it) > 0:
			parts.append("%s ×%d" % [sim.item_label(it), sim.loot_count(it)])
	for it in sim.loot:
		if not sim.supply().items.has(it):
			parts.append("%s ×%d" % [it, sim.loot_count(it)])
	var l := _label(" · ".join(parts) if not parts.is_empty() else "비어 있음", 14, Color(0.85, 0.85, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 660
	body.add_child(l)


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
