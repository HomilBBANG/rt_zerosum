class_name BattleHUD
extends CanvasLayer
## 전투 HUD (GDD 5절). 상단 라운드/선공/타임라인, 유닛 위 HP·AP, 하단 명령 패널, 툴팁, 디버그/로그.
## 모든 UI 는 조명 셰이더와 무관한 CanvasLayer 에 두어 가독성을 유지한다.

var controller: BattleController
var view: BattleViewBase
var preset: Dictionary
var manifest: Dictionary

var top_bar: PanelContainer
var round_label: Label
var timeline: HBoxContainer
var hover_label: Label   # 행동 순서 초상화에 마우스를 올리면 이름 표시
var floating_root: Control
var popup_root: Control
var bottom: PanelContainer
var portrait: TextureRect
var name_label: Label
var stat_label: Label
var slots_row: HBoxContainer        # 하단 슬롯 줄
var equip_popup: Button             # 무기 칸 클릭 시 뜨는 장착 버튼
var equip_index: int = -1
var _last_busy := false
var slot_tip: PanelContainer        # 슬롯 설명 말풍선 (호버)
var slot_tip_label: Label
var hint_label: Label
var cancel_btn: Button
var end_btn: Button
var log_box: RichTextLabel
var log_panel: PanelContainer
var log_btn: Button
var debug_panel: PanelContainer
var debug_label: Label
var toast: PanelContainer
var toast_label: Label
var preset_label: Label
var result_banner: Label

var pending_action: String = ""     # 대상 지정 대기 중인 행동 id
var pending_move: bool = false
var floating: Dictionary = {}       # instance_id -> {root, name, hp, ap}
var _toast_t: float = 0.0
var _font: Font
var _font_bold: Font


func _ready() -> void:
	layer = 10
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_font_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	_build_ui()


func setup(p_controller: BattleController, p_view: BattleViewBase, p_preset: Dictionary) -> void:
	controller = p_controller
	view = p_view
	preset = p_preset
	controller.battle_started.connect(_on_battle_started)
	controller.round_started.connect(_on_round_started)
	controller.actor_started.connect(_on_actor_started)
	controller.awaiting_command.connect(_on_awaiting_command)
	controller.actor_ended.connect(_on_actor_ended)
	controller.ap_changed.connect(func(_u): _refresh_floating(); _refresh_panel(); _refresh_timeline())
	controller.action_resolved.connect(_on_action_resolved)
	controller.unit_died.connect(func(_u): _refresh_floating(); _refresh_timeline())
	controller.battle_ended.connect(_on_battle_ended)
	controller.log_message.connect(_on_log)
	controller.command_rejected.connect(func(reason): show_toast(reason))
	controller.weapon_changed.connect(func(_u): _refresh_panel())
	controller.unit_moved.connect(func(_u, _f, _t): _refresh_panel())
	controller.units_swapped.connect(func(_a, _b): _refresh_panel())
	view.unit_clicked.connect(_on_unit_clicked)
	view.slot_clicked.connect(_on_slot_clicked)
	apply_preset(preset)


func apply_preset(p: Dictionary) -> void:
	preset = p
	preset_label.text = "%s  (%s)   [1~4 프리셋 · F1 디버그 · R 재시작]" % [p.name, p.ref]


# ---------------------------------------------------------------- UI 구성
func _panel_style(alpha: float = 0.82, border: Color = Color(1, 1, 1, 0.12)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, alpha)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb


func _label(text: String, size: int = 16, color: Color = Color(0.95, 0.95, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load("res://assets/fonts/Pretendard-Bold.ttf") if size >= 20 else _font)   # 큰 글자는 Bold
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _build_ui() -> void:
	# 상단 바: 배경 없이 라운드 + 행동 순서 초상화 (동전 결과·"행동 순서" 글자는 표시하지 않음)
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16
	top_bar.offset_right = -16
	top_bar.offset_top = 8
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 18)
	top_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(top_h)
	round_label = _label("라운드 1", 22, Color(1, 0.92, 0.5))
	round_label.add_theme_font_override("font", _font_bold)
	top_h.add_child(round_label)
	# 행동 순서: 화면 상단 중앙 (내용 폭이 바뀌어도 가운데 유지)
	timeline = HBoxContainer.new()
	timeline.add_theme_constant_override("separation", 6)
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.anchor_left = 0.5
	timeline.anchor_right = 0.5
	timeline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	timeline.offset_top = 8
	add_child(timeline)
	hover_label = _label("", 14)
	hover_label.visible = false
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	preset_label = _label("", 13, Color(0.75, 0.8, 0.85))
	preset_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	preset_label.position = Vector2(16, 70)
	add_child(preset_label)
	add_child(hover_label)

	# 유닛 위 HP/AP
	floating_root = Control.new()
	floating_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floating_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floating_root)
	popup_root = Control.new()
	popup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_root)

	# 하단 명령 패널: 초상화 | 이름 + [무기 3칸 · 자리 이동 · 기본 스킬 3칸 · 필살기] | 취소·턴 종료
	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel_style(0.88))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_top = -138
	bottom.offset_bottom = -8
	add_child(bottom)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	bottom.add_child(hb)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(104, 104)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var pf := PanelContainer.new()
	pf.add_theme_stylebox_override("panel", _panel_style(0.6, Color(1, 1, 1, 0.3)))
	pf.add_child(portrait)
	hb.add_child(pf)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	hb.add_child(col)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 14)
	col.add_child(head_row)
	name_label = _label("-", 20, Color(1, 1, 1))
	head_row.add_child(name_label)
	stat_label = _label("", 13, Color(0.8, 0.85, 0.9))
	stat_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head_row.add_child(stat_label)
	var slots_line := HBoxContainer.new()
	slots_line.add_theme_constant_override("separation", 16)
	col.add_child(slots_line)
	slots_row = HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 8)
	slots_line.add_child(slots_row)
	# 안내 문구: 슬롯 오른쪽 (캐릭터를 가리지 않게 패널 안)
	hint_label = _label("", 13, Color(1, 0.95, 0.7))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slots_line.add_child(hint_label)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 150
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	cancel_btn = _button("취소 (우클릭)", Color(0.5, 0.5, 0.55))
	cancel_btn.pressed.connect(cancel_pending)
	right.add_child(cancel_btn)
	end_btn = _button("턴 종료", Color(0.9, 0.45, 0.3))
	end_btn.pressed.connect(func(): cancel_pending(); controller.player_end_turn())
	right.add_child(end_btn)
	# 무기 장착 팝업 (불투명 검은 버튼) + 슬롯 설명 말풍선
	equip_popup = _button("장착하기  AP -1", Color(0.85, 0.85, 0.85))
	var ep: StyleBoxFlat = equip_popup.get_theme_stylebox("normal").duplicate()
	ep.bg_color = Color(0.02, 0.02, 0.03, 1.0)
	ep.border_color = Color(1, 1, 1, 0.5)
	equip_popup.add_theme_stylebox_override("normal", ep)
	var ep_dis: StyleBoxFlat = ep.duplicate()
	ep_dis.border_color = Color(1, 0.85, 0.3, 0.6)
	equip_popup.add_theme_stylebox_override("disabled", ep_dis)
	equip_popup.add_theme_color_override("font_disabled_color", Color(1, 0.85, 0.3))
	equip_popup.custom_minimum_size = Vector2(124, 32)
	equip_popup.visible = false
	equip_popup.pressed.connect(_on_equip_pressed)
	add_child(equip_popup)
	slot_tip = PanelContainer.new()
	slot_tip.add_theme_stylebox_override("panel", _panel_style(0.95, Color(1, 1, 1, 0.3)))
	slot_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_tip.visible = false
	slot_tip_label = _label("", 14)
	slot_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_tip_label.custom_minimum_size.x = 250
	slot_tip.add_child(slot_tip_label)
	add_child(slot_tip)

	# 로그 (2단): 1단 = 우측 상단 아이콘만, 2단 = 아이콘 아래 기록 창. 아이콘 클릭(또는 L)으로 전환
	log_btn = Button.new()
	log_btn.icon = load("res://assets/textures/ui_log.png")
	log_btn.expand_icon = true
	log_btn.toggle_mode = true
	log_btn.focus_mode = Control.FOCUS_NONE
	var lb_style := _panel_style(0.55)
	lb_style.set_content_margin_all(6)
	log_btn.add_theme_stylebox_override("normal", lb_style)
	var lb_hover := _panel_style(0.75, Color(1, 1, 1, 0.35))
	lb_hover.set_content_margin_all(6)
	log_btn.add_theme_stylebox_override("hover", lb_hover)
	log_btn.add_theme_stylebox_override("pressed", lb_hover)
	log_btn.add_theme_stylebox_override("hover_pressed", lb_hover)
	log_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	log_btn.offset_left = -52
	log_btn.offset_right = -16
	log_btn.offset_top = 10
	log_btn.offset_bottom = 46
	log_btn.toggled.connect(func(on): log_panel.visible = on)
	add_child(log_btn)
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _panel_style(0.6))
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_left = -404
	log_panel.offset_right = -16
	log_panel.offset_top = 52
	log_panel.offset_bottom = 144
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.visible = false
	add_child(log_panel)
	if Game.cli.get("log", "0") == "1":   # 스크린샷용: 2단(기록 창)으로 시작
		log_btn.set_pressed_no_signal(true)
		log_panel.visible = true
	log_box = RichTextLabel.new()
	log_box.scroll_following = true
	log_box.add_theme_font_override("normal_font", _font)
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(log_box)

	debug_panel = PanelContainer.new()
	debug_panel.add_theme_stylebox_override("panel", _panel_style(0.85, Color(1, 0.8, 0.2, 0.5)))
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	debug_panel.position = Vector2(12, 84)
	debug_panel.custom_minimum_size = Vector2(330, 0)
	debug_panel.visible = false
	add_child(debug_panel)
	debug_label = _label("", 12, Color(1, 0.95, 0.8))
	debug_panel.add_child(debug_label)

	toast = PanelContainer.new()
	toast.add_theme_stylebox_override("panel", _panel_style(0.92, Color(1, 0.4, 0.3, 0.8)))
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	toast_label = _label("", 14, Color(1, 0.9, 0.85))
	toast.add_child(toast_label)

	result_banner = _label("", 54, Color(1, 0.95, 0.6))
	result_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_banner.visible = false
	add_child(result_banner)


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(150, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.45)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate()
	hov.bg_color = color.darkened(0.2)
	b.add_theme_stylebox_override("hover", hov)
	var prs := sb.duplicate()
	prs.bg_color = color
	b.add_theme_stylebox_override("pressed", prs)
	var dis := sb.duplicate()
	dis.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	dis.border_color = Color(0.3, 0.3, 0.35)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	return b


# ---------------------------------------------------------------- 컨트롤러 이벤트
func _on_battle_started() -> void:
	for id in floating:
		floating[id].root.queue_free()
		floating[id].hp.queue_free()
	floating.clear()
	for u in controller.slots.all_units():
		var root := VBoxContainer.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_theme_constant_override("separation", 1)
		var nm := _label(u.display_name(), 13, Color(1, 1, 1) if u.team == "ally" else Color(1, 0.75, 0.75))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(nm)
		# 체력 바 (3D 비교 모드용, 2D 뷰는 발밑에 직접 그림). 위치는 _process 에서 매 프레임 갱신
		var hp := ProgressBar.new()
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp.show_percentage = false
		hp.max_value = u.data.max_hp
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.8)
		bg.set_corner_radius_all(3)
		bg.set_border_width_all(1)
		bg.border_color = Color(0, 0, 0, 0.9)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.95, 0.16, 0.14)   # 체력은 아군·적 모두 붉은색
		fill.set_corner_radius_all(2)
		hp.add_theme_stylebox_override("background", bg)
		hp.add_theme_stylebox_override("fill", fill)
		floating_root.add_child(hp)
		hp.visible = not view.draws_back_bars()   # 2D 뷰는 월드 안에서 캐릭터 아래 층에 직접 그림
		var ap := _label("", 12, Color(0.55, 0.9, 1.0))
		ap.visible = false   # AP 는 발밑 파란 칸으로 표시
		ap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(ap)
		floating_root.add_child(root)
		floating[u.instance_id] = {"root": root, "name": nm, "hp": hp, "ap": ap, "unit": u}
	_refresh_floating()
	result_banner.visible = false


func _on_round_started(round_no: int, _queue: Array) -> void:
	round_label.text = "라운드 %d" % round_no
	_refresh_timeline()


func _on_actor_started(unit: UnitRuntime, _recovered: int) -> void:
	view.clear_highlights()
	view.set_highlight(unit, "current")
	_refresh_timeline()
	_refresh_panel()
	if unit.team == "enemy":
		hint_label.text = "적 %s 행동 중..." % unit.display_name()


func _on_awaiting_command(_unit: UnitRuntime) -> void:
	pending_action = ""
	pending_move = false
	_refresh_panel()
	hint_label.text = "행동을 선택하세요. AP 가 남으면 여러 번 행동할 수 있습니다."


func _on_actor_ended(_unit: UnitRuntime, _reason: String) -> void:
	cancel_pending()
	_refresh_panel()


func _on_action_resolved(event: Dictionary) -> void:
	for r in event.results:
		var color := Color(1, 0.3, 0.25)
		var text := "-%d" % r.amount
		if r.kind == "heal":
			color = Color(0.4, 1, 0.5)
			text = "+%d" % r.amount
		elif r.kind == "ap":
			color = Color(0.5, 0.9, 1)
			text = "AP +%d" % r.amount
		if r.get("killed", false):
			text += "  전투 불능"
		_spawn_popup(r.target, text, color)
	_refresh_floating()


func _on_battle_ended(winner: String) -> void:
	cancel_pending()
	result_banner.text = "승리!" if winner == "ally" else "패배..."
	result_banner.visible = true
	hint_label.text = "전투 종료"
	_refresh_panel()


func _on_log(text: String) -> void:
	log_box.append_text(text + "\n")


# ---------------------------------------------------------------- 명령 흐름
func begin_action(action_id: String) -> void:
	if not controller.is_player_turn():
		return
	var opt_reason := ""
	for o in controller.get_command_options():
		if o.id == action_id and not o.enabled:
			opt_reason = o.reason
	if opt_reason != "":
		show_toast(opt_reason)
		return
	pending_move = false
	view.clear_slot_markers()
	pending_action = action_id
	var a := controller.get_action(action_id)
	var targets := controller.get_valid_targets(action_id)
	view.clear_highlights()
	view.set_highlight(controller.current, "current")
	for u in controller.slots.living_units():
		if u in targets:
			view.set_highlight(u, "target_ally" if u.team == controller.current.team else "target_ok")
		elif u != controller.current:
			view.set_highlight(u, "target_bad")
	hint_label.text = "%s (AP %d): 대상을 클릭하세요. 강조되지 않은 대상은 선택할 수 없습니다." % [a.display_name, a.ap_cost]
	_refresh_panel()


func begin_move() -> void:
	if not controller.is_player_turn():
		return
	pending_action = ""
	pending_move = true
	view.clear_highlights()
	view.set_highlight(controller.current, "current")
	view.show_slot_markers(controller.get_move_options())
	hint_label.text = "위치 변경 (AP 1): 빈 슬롯 = 이동, 아군 슬롯 = 자리 교환. 우클릭으로 취소."
	_refresh_panel()


func cancel_pending() -> void:
	_hide_equip()
	pending_action = ""
	pending_move = false
	view.clear_slot_markers()
	view.clear_highlights()
	if controller and controller.current and controller.current.alive:
		view.set_highlight(controller.current, "current")
	if controller and controller.is_player_turn():
		hint_label.text = "행동을 선택하세요."
	_refresh_panel()


func _on_unit_clicked(unit: UnitRuntime) -> void:
	if view.busy or not controller.is_player_turn():
		return
	if pending_action == "":
		# 대상 지정 중이 아니면 유닛 정보 툴팁
		show_toast("%s  Lv%d  속도 %d  HP %d/%d  AP %d/%d  %s" % [unit.display_name(), unit.data.level, unit.data.speed, unit.hp, unit.data.max_hp, unit.ap, unit.data.max_ap, _row_text(unit)])
		return
	var reason := controller.get_target_block_reason(pending_action, unit)
	if reason != "":
		show_toast(reason)
		return
	var aid := pending_action
	pending_action = ""
	view.clear_highlights()
	view.set_highlight(controller.current, "current")
	controller.player_execute(aid, unit)
	_refresh_panel()


func _on_slot_clicked(key: String) -> void:
	if view.busy or not pending_move:
		return
	pending_move = false
	view.clear_slot_markers()
	controller.player_move(key)
	_refresh_panel()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if pending_action != "" or pending_move or equip_popup.visible:
			cancel_pending()
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and controller and controller.is_player_turn():
		cancel_pending()
		controller.player_end_turn()


# ---------------------------------------------------------------- 갱신
const SLOT := 56.0
const SLOT_GAP := 18.0


func _refresh_panel() -> void:
	for c in slots_row.get_children():
		c.queue_free()
	slot_tip.visible = false
	var u := controller.current
	if u == null:
		return
	name_label.text = "%s  ·  %s  Lv%d" % [u.display_name(), u.data.role, u.data.level]
	stat_label.text = "HP %d/%d   AP %d/%d (+%d/턴)   속도 %d   %s %d" % [u.hp, u.data.max_hp, u.ap, u.data.max_ap, u.data.ap_recovery, u.data.speed, _row_text(u), u.index + 1]
	portrait.texture = UnitArt.portrait(u.data.sprite_id, manifest)
	portrait.flip_h = (u.team == "enemy") != bool(u.data.palette.get("art_faces_left", false))
	var is_player := controller.is_player_turn() and not view.busy
	var opts := {}
	for o in controller.get_command_options():
		opts[o.id] = o
	# 무기 3칸: 주무기 · 보조무기1 · 보조무기2
	var wcost := int(opts.get("weapon", {}).get("cost", 1))
	for i in 3:
		if i < u.data.weapons.size():
			var w: Dictionary = u.data.weapons[i]
			var equipped := i == u.weapon_index
			var tip := "%s  ·  %s  ·  위력 %+d%s\n%s" % [w.name, "원거리" if w.range_type == "ranged" else "근접", int(w.power_bonus), "  (장착 중)" if equipped else "", ["주무기", "보조무기 1", "보조무기 2"][i]]
			var wi: int = i
			_add_slot(_weapon_icon(str(w.id)), w.name, -1, is_player, "equipped" if equipped else "", tip, func(btn: Control): _open_equip_popup(btn, wi, wcost), false, true)
		else:
			_add_slot(null, ["주무기", "보조무기 1", "보조무기 2"][i], -1, false, "", "", Callable())
	_add_gap()
	# 자리 이동
	var mv: Dictionary = opts.get("move", {})
	if not mv.is_empty():
		var mv_tip := "%s  ·  AP %d\n이동·교체할 수 있는 자리 아래에 파란 표시가 생깁니다. 빈 자리 = 이동, 아군 = 자리 교체.%s" % [mv.name, mv.cost, "" if mv.enabled else "\n(%s)" % mv.reason]
		_add_slot(load("res://assets/textures/ui_move.png"), "자리 이동", mv.cost, is_player and mv.enabled, "selected" if pending_move else "", mv_tip, func(_b): _hide_equip(); begin_move())
	_add_gap()
	# 기본 스킬 3칸 + 필살기
	var skills: Array = []
	var ult: Dictionary = {}
	for sid in u.data.skill_ids:
		var o: Dictionary = opts.get(sid, {})
		if o.is_empty():
			continue
		if o.kind == "ultimate":
			ult = o
		elif skills.size() < 3:
			skills.append(o)
	for i in 3:
		if i < skills.size():
			_add_skill_slot(skills[i], is_player)
		else:
			_add_slot(null, "", -1, false, "", "", Callable())
	_add_gap()
	if not ult.is_empty():
		_add_skill_slot(ult, is_player)
	else:
		_add_slot(null, "필살기", -1, false, "", "", Callable())
	end_btn.disabled = not is_player
	cancel_btn.disabled = not (pending_action != "" or pending_move or equip_popup.visible)


func _add_skill_slot(o: Dictionary, is_player: bool) -> void:
	var tip := "%s  ·  AP %d\n%s%s" % [o.name, o.cost, o.desc, "" if o.enabled else "\n(%s)" % o.reason]
	var id: String = o.id
	var icon_id := id if ResourceLoader.exists("res://assets/textures/ui_%s.png" % id) else ("ultimate" if o.kind == "ultimate" else "basic_attack")
	_add_slot(load("res://assets/textures/ui_%s.png" % icon_id), o.name, o.cost, is_player and o.enabled, "selected" if pending_action == id else "", tip, func(_b): _hide_equip(); begin_action(id), o.kind == "ultimate")


func _add_gap() -> void:
	var g := Control.new()
	g.custom_minimum_size.x = SLOT_GAP - 8.0
	slots_row.add_child(g)


## 정사각 슬롯 + 아래 이름. mark: "" | "equipped"(노란 테두리) | "selected"(선택 중). on_press(btn) 은 클릭 시 호출.
func _add_slot(icon: Texture2D, caption: String, cost: int, enabled: bool, mark: String, tip: String, on_press: Callable, is_ult: bool = false, is_weapon: bool = false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size.x = SLOT + 8.0
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(SLOT, SLOT)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.08, 0.28, 0.95) if is_ult else Color(0.1, 0.11, 0.14, 0.95)
	if is_weapon:
		sb.bg_color = Color(0.5, 0.52, 0.56, 0.95)   # 무기 원화는 어두운 색이라 밝은 바탕
	sb.border_color = Color(1, 1, 1, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	if mark == "equipped":
		sb.border_color = Color(1.0, 0.82, 0.25)
		sb.set_border_width_all(3)
	elif mark == "selected":
		sb.border_color = Color(0.45, 0.85, 1.0)
		sb.set_border_width_all(3)
	btn.add_theme_stylebox_override("normal", sb)
	var hov: StyleBoxFlat = sb.duplicate()
	hov.bg_color = sb.bg_color.lightened(0.12)
	if mark == "":
		hov.border_color = Color(1, 1, 1, 0.6)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("disabled", sb)
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 7
		tr.offset_top = 7
		tr.offset_right = -7
		tr.offset_bottom = -7
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tr)
	if cost >= 0:
		var cl := _label(str(cost), 12, Color(0.55, 0.8, 1.0))
		cl.position = Vector2(SLOT - 13, 0)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cl)
	var active := enabled and on_press.is_valid()
	btn.disabled = not active
	if icon == null or not active:
		btn.modulate = Color(1, 1, 1, 0.45) if icon != null else Color(1, 1, 1, 0.3)
	if mark == "equipped":
		btn.modulate = Color(1, 1, 1, 1)   # 장착 중 표시는 항상 선명하게
		btn.disabled = not on_press.is_valid()
	if on_press.is_valid():
		btn.pressed.connect(func(): on_press.call(btn))
	if tip != "":
		btn.mouse_entered.connect(_show_slot_tip.bind(btn, tip))
		btn.mouse_exited.connect(func(): slot_tip.visible = false)
	box.add_child(btn)
	var cap := _label(caption, 12, Color(0.9, 0.9, 0.92))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size.x = SLOT + 8.0
	cap.clip_text = true
	box.add_child(cap)
	slots_row.add_child(box)


func _weapon_icon(wid: String) -> Texture2D:
	var path := "res://assets/sprites/w_%s.png" % wid
	return load(path) if ResourceLoader.exists(path) else load("res://assets/textures/ui_basic_attack.png")


## 슬롯 설명 말풍선: 슬롯 바로 위
func _show_slot_tip(btn: Control, text: String) -> void:
	slot_tip_label.text = text
	slot_tip.reset_size()
	var r := btn.get_global_rect()
	var x := clampf(r.position.x + r.size.x * 0.5 - slot_tip.size.x * 0.5, 8.0, 1280.0 - slot_tip.size.x - 8.0)
	slot_tip.position = Vector2(x, r.position.y - slot_tip.size.y - (44.0 if equip_popup.visible else 8.0))
	slot_tip.visible = true


## 무기 칸 클릭: 그 칸 위에 불투명한 검은 버튼. 장착 중이면 "장착 중" 비활성
func _open_equip_popup(btn: Control, index: int, cost: int) -> void:
	if not controller.is_player_turn() or view.busy:
		return
	if pending_action != "" or pending_move:
		cancel_pending()
	var u := controller.current
	equip_index = index
	if index == u.weapon_index:
		equip_popup.text = "장착 중"
		equip_popup.disabled = true
	else:
		equip_popup.text = "장착하기  AP -%d" % cost
		equip_popup.disabled = not APComponent.can_pay(u, cost)
		if equip_popup.disabled:
			equip_popup.text = "AP 부족"
	equip_popup.reset_size()
	var r := btn.get_global_rect()
	equip_popup.position = Vector2(r.position.x + r.size.x * 0.5 - equip_popup.size.x * 0.5, r.position.y - equip_popup.size.y - 6.0)
	equip_popup.visible = true
	slot_tip.visible = false
	cancel_btn.disabled = false


func _on_equip_pressed() -> void:
	var i := equip_index
	_hide_equip()
	controller.player_equip_weapon(i)
	_refresh_panel()


func _hide_equip() -> void:
	equip_popup.visible = false
	equip_index = -1


func _kind_color(kind: String) -> Color:
	match kind:
		"attack": return Color(0.95, 0.55, 0.3)
		"heavy": return Color(1.0, 0.4, 0.35)
		"support": return Color(0.4, 0.85, 0.6)
		"ultimate": return Color(0.9, 0.5, 1.0)
		"move": return Color(0.4, 0.75, 1.0)
		"weapon": return Color(0.8, 0.8, 0.5)
	return Color(0.6, 0.6, 0.6)


func _refresh_floating() -> void:
	for id in floating:
		var e: Dictionary = floating[id]
		var u: UnitRuntime = e.unit
		e.hp.value = u.hp
		e.ap.text = "AP %d/%d" % [u.ap, u.data.max_ap]
		e.root.modulate = Color(1, 1, 1, 1) if u.alive else Color(1, 1, 1, 0.35)
		e.hp.modulate = e.root.modulate


## 행동 순서: 초상화를 순서대로. 차례인 유닛은 30% 크게, 끝난 유닛은 어둡게, 쓰러진 유닛은 회색.
const TL_SIZE := 40.0
const TL_CUR_SCALE := 1.3


func _refresh_timeline() -> void:
	for c in timeline.get_children():
		c.queue_free()
	hover_label.visible = false
	for i in controller.queue.size():
		var u: UnitRuntime = controller.queue[i]
		var is_cur := (u == controller.current and i == controller.queue_pos - 1)
		var done := i < controller.queue_pos - 1 or (i == controller.queue_pos - 1 and not is_cur)
		# 컨테이너는 자식 scale 을 1 로 되돌리므로, 고정 크기 칸 안에 초상화를 직접 놓고 키운다
		var cell := Control.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side := TL_SIZE * (TL_CUR_SCALE if is_cur else 1.0)
		cell.custom_minimum_size = Vector2(side, TL_SIZE * TL_CUR_SCALE)
		var frame := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.1, 0.85)
		sb.border_color = Color(1.0, 0.82, 0.3) if is_cur else (Color(0.35, 0.95, 0.6) if u.team == "ally" else Color(1.0, 0.35, 0.3))
		sb.set_border_width_all(3 if is_cur else 2)
		sb.set_corner_radius_all(6)
		frame.add_theme_stylebox_override("panel", sb)
		frame.size = Vector2(TL_SIZE, TL_SIZE)
		frame.position = Vector2((side - TL_SIZE) * 0.5, 0.0)
		frame.pivot_offset = Vector2(TL_SIZE * 0.5, 0.0)
		frame.scale = Vector2.ONE * (TL_CUR_SCALE if is_cur else 1.0)
		frame.clip_contents = true
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		var tr := TextureRect.new()
		tr.texture = UnitArt.portrait(u.data.sprite_id, manifest)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.flip_h = (u.team == "enemy") != bool(u.data.palette.get("art_faces_left", false))
		tr.position = Vector2(2, 2)
		tr.size = Vector2(TL_SIZE - 4, TL_SIZE - 4)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
		if not u.alive:
			frame.modulate = Color(0.45, 0.45, 0.48, 0.8)
		elif done:
			frame.modulate = Color(0.6, 0.6, 0.62, 1.0)
		frame.mouse_entered.connect(_show_timeline_name.bind(frame, u))
		frame.mouse_exited.connect(func(): hover_label.visible = false)
		cell.add_child(frame)
		timeline.add_child(cell)


## 초상화 아래에 이름 표시 (마우스 호버)
func _show_timeline_name(frame: Control, u: UnitRuntime) -> void:
	hover_label.text = u.display_name() + ("" if u.alive else " (전투 불능)")
	hover_label.add_theme_color_override("font_color", Color(1, 1, 1) if u.team == "ally" else Color(1, 0.75, 0.72))
	hover_label.reset_size()
	var r := frame.get_global_rect()
	hover_label.position = Vector2(r.get_center().x - hover_label.size.x * 0.5, r.end.y + 4.0)
	hover_label.visible = true


func _spawn_popup(target: UnitRuntime, text: String, color: Color) -> void:
	var l := _label(text, 24, color)
	l.position = view.get_unit_screen_pos(target) + Vector2(-30, -30)
	popup_root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 50, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func show_toast(text: String) -> void:
	toast_label.text = text
	toast.visible = true
	toast.reset_size()
	var mp := get_viewport().get_mouse_position()
	toast.position = Vector2(clampf(mp.x + 14, 8, 1280 - toast.size.x - 8), clampf(mp.y - 44, 8, 720 - 60))
	_toast_t = 2.2


func toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible


func _process(delta: float) -> void:
	if controller == null:
		return
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			toast.visible = false
	for id in floating:
		var e: Dictionary = floating[id]
		var pos: Vector2 = view.get_unit_screen_pos(e.unit) - Vector2(e.root.size.x * 0.5, 40)
		# 키 큰 괴물(4m)은 머리 위 표시가 상단 HUD·펼친 전투 기록에 가리지 않게 그 아래로 내림
		var min_y := 152.0 if log_panel.visible and pos.x + e.root.size.x > 1280.0 - 404.0 else 104.0
		pos.y = maxf(pos.y, min_y)
		e.root.position = pos
		var r: Rect2 = view.get_unit_back_bar_rect(e.unit)
		e.hp.position = r.position
		e.hp.size = r.size
	if debug_panel.visible:
		var d := controller.debug_snapshot()
		var lines := PackedStringArray()
		lines.append("라운드 %d  상태 %s  시드 %d  매복 %s  선공 %s" % [d.round, d.state, d.seed, d.ambush, d.first_team])
		lines.append("현재: %s" % d.current)
		lines.append("큐: " + ", ".join(d.queue))
		for u in controller.slots.all_units():
			lines.append("%s %s spd%d lv%d hp%d/%d ap%d/%d %s" % ["A" if u.team == "ally" else "E", u.display_name(), u.data.speed, u.data.level, u.hp, u.data.max_hp, u.ap, u.data.max_ap, u.slot_key() if u.alive else "dead"])
		debug_label.text = "\n".join(lines)
	# 연출 중에는 슬롯 잠금 반영 (연출 시작·끝에 한 번씩 다시 그림)
	var busy_now := controller.is_player_turn() and view.busy
	if busy_now != _last_busy:
		_last_busy = busy_now
		if busy_now:
			_hide_equip()
		_refresh_panel()


## 위치 표시: 두 칸 큰 몸집은 "전방·중앙"
func _row_text(u: UnitRuntime) -> String:
	var names: PackedStringArray = []
	for r in range(u.row, u.row + u.data.row_span):
		names.append(SlotManager.ROW_NAMES[r])
	return "·".join(names)


## 로그 1단(아이콘만) ↔ 2단(기록 창) 전환
func toggle_log() -> void:
	log_btn.button_pressed = not log_btn.button_pressed


## 자동 검증용: 하단 슬롯 i 번째(간격 칸 제외) 버튼
func debug_slot_button(i: int) -> Button:
	var n := 0
	for c in slots_row.get_children():
		if c is VBoxContainer and not c.is_queued_for_deletion():
			if n == i:
				return c.get_child(0)
			n += 1
	return null
