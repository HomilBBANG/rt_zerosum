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
var status_flow: VBoxContainer      # 현재 유닛 상태 이상 (한 줄씩)
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
	# 레이아웃: scenes/battle_hud.tscn 에 저장된 노드를 쓴다 (Godot 에디터에서 위치 편집 가능). 없으면 코드로 생성
	if find_child("Bottom", true, false) == null:
		_create_layout()
	_bind_layout()


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
	controller.status_ticked.connect(_on_status_ticked)
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


## 레이아웃 노드 생성. scenes/battle_hud.tscn 에 노드가 이미 있으면(에디터에서 편집한 레이아웃) 호출하지 않는다.
## tools/export_hud_scene.gd 가 이 함수로 만든 노드를 그대로 battle_hud.tscn 에 저장한다.
func _create_layout() -> void:
	if _font == null:
		_font = load("res://assets/fonts/Pretendard-Medium.ttf")
		_font_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	# 상단 바: 배경 없이 라운드 + 행동 순서 초상화 (동전 결과·"행동 순서" 글자는 표시하지 않음)
	top_bar = PanelContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16
	top_bar.offset_right = -16
	top_bar.offset_top = 8
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)
	var top_h := HBoxContainer.new()
	top_h.name = "TopRow"
	top_h.add_theme_constant_override("separation", 18)
	top_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(top_h)
	round_label = _label("라운드 1", 22, Color(1, 0.92, 0.5))
	round_label.name = "RoundLabel"
	round_label.add_theme_font_override("font", _font_bold)
	top_h.add_child(round_label)
	# 행동 순서: 화면 상단 중앙 (내용 폭이 바뀌어도 가운데 유지)
	timeline = HBoxContainer.new()
	timeline.name = "Timeline"
	timeline.add_theme_constant_override("separation", 6)
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.anchor_left = 0.5
	timeline.anchor_right = 0.5
	timeline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	timeline.offset_top = 8
	timeline.alignment = BoxContainer.ALIGNMENT_CENTER
	timeline.custom_minimum_size = Vector2(380, 52)   # 에디터에서 보이는 자리 (초상화는 실행 중에 채움)
	add_child(timeline)
	hover_label = _label("", 14)
	hover_label.name = "HoverName"
	hover_label.visible = false
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	preset_label = _label("", 13, Color(0.75, 0.8, 0.85))
	preset_label.name = "PresetLabel"
	preset_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	preset_label.position = Vector2(16, 70)
	add_child(preset_label)
	add_child(hover_label)

	# 유닛 위 HP/AP
	floating_root = Control.new()
	floating_root.name = "Floating"
	floating_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	floating_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floating_root)
	popup_root = Control.new()
	popup_root.name = "Popups"
	popup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_root)

	# 하단 명령 패널: 초상화 | 이름 + [무기 3칸 · 자리 이동 · 기본 스킬 3칸 · 필살기] | 상태 이상 | 턴 종료
	bottom = PanelContainer.new()
	bottom.name = "Bottom"
	bottom.add_theme_stylebox_override("panel", _panel_style(0.88))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_top = -138
	bottom.offset_bottom = -8
	add_child(bottom)
	var hb := HBoxContainer.new()
	hb.name = "BottomRow"
	hb.add_theme_constant_override("separation", 14)
	bottom.add_child(hb)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(104, 104)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var pf := PanelContainer.new()
	pf.name = "PortraitFrame"
	pf.add_theme_stylebox_override("panel", _panel_style(0.6, Color(1, 1, 1, 0.3)))
	pf.add_child(portrait)
	hb.add_child(pf)
	# 이름·수치·안내: 초상화 오른쪽 좁은 칸 (슬롯 줄은 화면 가운데에 따로)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.custom_minimum_size.x = 168
	info.add_theme_constant_override("separation", 2)
	hb.add_child(info)
	name_label = _label("-", 17, Color(1, 1, 1))
	name_label.name = "NameLabel"
	name_label.clip_text = true
	name_label.custom_minimum_size.x = 168
	info.add_child(name_label)
	stat_label = _label("", 12, Color(0.8, 0.85, 0.9))
	stat_label.name = "StatLabel"
	stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_label.custom_minimum_size.x = 168
	info.add_child(stat_label)
	hint_label = _label("", 12, Color(1, 0.95, 0.7))   # 안내 문구는 표시하지 않음 (사용자 요청)
	hint_label.name = "HintLabel"
	hint_label.visible = false
	info.add_child(hint_label)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.name = "Spacer"
	hb.add_child(fill)
	# 턴 종료: 맨 오른쪽, 모서리 둥근 정사각형 (취소는 같은 버튼을 다시 누르거나 우클릭)
	end_btn = _button("턴\n종료", Color(0.9, 0.45, 0.3))
	end_btn.name = "EndTurn"
	end_btn.custom_minimum_size = Vector2(84, 84)
	end_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	end_btn.add_theme_font_override("font", _font_bold)
	end_btn.add_theme_font_size_override("font_size", 17)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sbx: StyleBoxFlat = end_btn.get_theme_stylebox(st).duplicate()
		sbx.set_corner_radius_all(14)
		end_btn.add_theme_stylebox_override(st, sbx)
	var end_wrap := MarginContainer.new()
	end_wrap.name = "EndTurnWrap"
	end_wrap.add_theme_constant_override("margin_right", 3)   # 왼쪽으로 3px
	end_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	end_wrap.add_child(end_btn)
	hb.add_child(end_wrap)
	# 상태 이상: 슬롯 줄과 턴 종료 사이 빈 칸 (긍정 녹색 / 부정 붉은색, 호버 시 설명)
	var st_box := PanelContainer.new()
	st_box.name = "StatusWindow"
	var st_style := StyleBoxFlat.new()
	st_style.bg_color = Color(0.04, 0.06, 0.12, 0.9)
	st_style.border_color = Color(0.36, 0.45, 0.62, 1.0)   # 불투명 파란 외곽선 창 (채도 낮춤)
	st_style.set_border_width_all(2)
	st_style.set_corner_radius_all(6)
	st_style.set_content_margin_all(6)
	st_box.add_theme_stylebox_override("panel", st_style)
	st_box.anchor_left = 1.0
	st_box.anchor_right = 1.0
	st_box.anchor_top = 1.0
	st_box.anchor_bottom = 1.0
	st_box.offset_left = -322
	st_box.offset_right = -126
	st_box.offset_top = -130
	st_box.offset_bottom = -16
	st_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(st_box)
	var st_scroll := ScrollContainer.new()
	st_scroll.name = "StatusScroll"
	st_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	st_box.add_child(st_scroll)
	status_flow = VBoxContainer.new()   # 상태 이상 한 줄씩
	status_flow.name = "StatusList"
	status_flow.add_theme_constant_override("separation", 4)
	status_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_scroll.add_child(status_flow)
	# 슬롯 줄: 화면 가로 가운데, 하단 패널 안 (무기 칸은 패널 천장까지 세로로 길게)
	slots_row = HBoxContainer.new()
	slots_row.name = "SlotsRow"
	slots_row.add_theme_constant_override("separation", 6)
	slots_row.anchor_left = 0.5
	slots_row.anchor_right = 0.5
	slots_row.anchor_top = 1.0
	slots_row.anchor_bottom = 1.0
	slots_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# 하단 패널(-138..-8) 기준. 이름 글자의 아래 여백(글자 박스 안 빈 줄)만큼 4px 내려, 보이는 아이콘+글자가 위/아래 대칭
	slots_row.offset_top = -134
	slots_row.offset_bottom = -4
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.custom_minimum_size = Vector2(620, 0)   # 에디터에서 보이는 자리 (슬롯은 실행 중에 채움)
	add_child(slots_row)
	# 무기 장착 팝업 (불투명 검은 버튼) + 슬롯 설명 말풍선
	equip_popup = _button("장착하기  AP -1", Color(0.85, 0.85, 0.85))
	equip_popup.name = "EquipPopup"
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
	add_child(equip_popup)
	slot_tip = PanelContainer.new()
	slot_tip.name = "SlotTip"
	slot_tip.add_theme_stylebox_override("panel", _panel_style(0.95, Color(1, 1, 1, 0.3)))
	slot_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_tip.visible = false
	slot_tip_label = _label("", 14)
	slot_tip_label.name = "SlotTipLabel"
	slot_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_tip_label.custom_minimum_size.x = 250
	slot_tip.add_child(slot_tip_label)
	add_child(slot_tip)

	# 로그 (2단): 1단 = 우측 상단 아이콘만, 2단 = 아이콘 아래 기록 창. 아이콘 클릭(또는 L)으로 전환
	log_btn = Button.new()
	log_btn.name = "LogButton"
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
	add_child(log_btn)
	log_panel = PanelContainer.new()
	log_panel.name = "LogPanel"
	log_panel.add_theme_stylebox_override("panel", _panel_style(0.6))
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_left = -404
	log_panel.offset_right = -16
	log_panel.offset_top = 52
	log_panel.offset_bottom = 144
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.visible = false
	add_child(log_panel)
	log_box = RichTextLabel.new()
	log_box.name = "LogText"
	log_box.scroll_following = true
	log_box.add_theme_font_override("normal_font", _font)
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(log_box)

	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.add_theme_stylebox_override("panel", _panel_style(0.85, Color(1, 0.8, 0.2, 0.5)))
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	debug_panel.position = Vector2(12, 84)
	debug_panel.custom_minimum_size = Vector2(330, 0)
	debug_panel.visible = false
	add_child(debug_panel)
	debug_label = _label("", 12, Color(1, 0.95, 0.8))
	debug_label.name = "DebugLabel"
	debug_panel.add_child(debug_label)

	toast = PanelContainer.new()
	toast.name = "Toast"
	toast.add_theme_stylebox_override("panel", _panel_style(0.92, Color(1, 0.4, 0.3, 0.8)))
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	toast_label = _label("", 14, Color(1, 0.9, 0.85))
	toast_label.name = "ToastLabel"
	toast.add_child(toast_label)

	result_banner = _label("", 54, Color(1, 0.95, 0.6))
	result_banner.name = "ResultBanner"
	result_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_banner.visible = false
	add_child(result_banner)


## 씬(또는 코드로 만든) 레이아웃 노드를 이름으로 찾아 변수·신호에 연결
func _bind_layout() -> void:
	top_bar = _n("TopBar")
	round_label = _n("RoundLabel")
	timeline = _n("Timeline")
	hover_label = _n("HoverName")
	preset_label = _n("PresetLabel")
	floating_root = _n("Floating")
	popup_root = _n("Popups")
	bottom = _n("Bottom")
	portrait = _n("Portrait")
	name_label = _n("NameLabel")
	stat_label = _n("StatLabel")
	hint_label = _n("HintLabel")
	end_btn = _n("EndTurn")
	status_flow = _n("StatusList")
	slots_row = _n("SlotsRow")
	equip_popup = _n("EquipPopup")
	slot_tip = _n("SlotTip")
	slot_tip_label = _n("SlotTipLabel")
	log_btn = _n("LogButton")
	log_panel = _n("LogPanel")
	log_box = _n("LogText")
	debug_panel = _n("DebugPanel")
	debug_label = _n("DebugLabel")
	toast = _n("Toast")
	toast_label = _n("ToastLabel")
	result_banner = _n("ResultBanner")
	end_btn.pressed.connect(func(): cancel_pending(); controller.player_end_turn())
	equip_popup.pressed.connect(_on_equip_pressed)
	log_btn.toggled.connect(func(on): log_panel.visible = on)
	if Game.cli.get("log", "0") == "1":   # 스크린샷용: 2단(기록 창)으로 시작
		log_btn.set_pressed_no_signal(true)
		log_panel.visible = true


func _n(node_name: String) -> Node:
	var n := find_child(node_name, true, false)
	assert(n != null, "HUD 레이아웃에 %s 노드가 없습니다 (scenes/battle_hud.tscn)" % node_name)
	return n


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
		nm.visible = false   # 캐릭터 위 이름 표시 안 함 (이름은 행동 순서 초상화 호버로)
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
	_status_popups(event.results, event.get("applied", []))
	_refresh_floating()
	_refresh_panel()


## 차례 시작 상태 이상 (출혈·화상 피해, 재생 회복, 동상 폭발, 기절)
func _on_status_ticked(event: Dictionary) -> void:
	var u: UnitRuntime = event.unit
	if event.results.is_empty() and u.has_effect("stun"):
		var stun_id: String = u.statuses_with("stun")[0]
		_spawn_popup(u, "%s — 행동 불가" % StatusCatalog.get_def(stun_id).name, StatusCatalog.color_of(stun_id))
	_status_popups(event.results, [])
	_refresh_floating()
	_refresh_panel()
	_refresh_timeline()


## 피해·회복 숫자 + 상태 이상 이름 (같은 대상은 조금씩 늦게·아래로)
func _status_popups(results: Array, applied: Array) -> void:
	var n := {}
	for r in results:
		var k: int = n.get(r.target, 0)
		n[r.target] = k + 1
		var color := Color(1, 0.3, 0.25)
		var text := "-%d" % r.amount
		if r.get("status", "") != "":
			color = StatusCatalog.color_of(r.status)
			text = "%s %s%d" % [StatusCatalog.get_def(r.status).name, "+" if r.kind == "heal" else "-", r.amount]
		elif r.kind == "heal":
			color = Color(0.4, 1, 0.5)
			text = "+%d" % r.amount
		elif r.kind == "ap":
			color = Color(0.5, 0.9, 1)
			text = "AP +%d" % r.amount
		if int(r.get("absorbed", 0)) > 0:   # 보호막이 막은 만큼
			text = ("%s  (막음 %d)" % [text, r.absorbed]) if int(r.amount) > 0 else "막음 %d" % r.absorbed
			if int(r.amount) == 0:
				color = StatusCatalog.EFFECTS.shield.color
		if r.get("killed", false):
			text += "  전투 불능"
		_spawn_popup(r.target, text, color, k)
	for a in applied:
		var k2: int = n.get(a.target, 0)
		n[a.target] = k2 + 1
		_spawn_popup(a.target, "%s!" % StatusCatalog.get_def(a.status).name, StatusCatalog.color_of(a.status), k2)


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
	hint_label.text = "%s (AP %d): 대상을 클릭하세요. AP 는 실행할 때 소모. 다시 누르거나 우클릭하면 취소." % [a.display_name, a.ap_cost]
	_refresh_panel()


func begin_move() -> void:
	if not controller.is_player_turn():
		return
	pending_action = ""
	pending_move = true
	view.clear_highlights()
	view.set_highlight(controller.current, "current")
	view.show_slot_markers(controller.get_move_options())
	hint_label.text = "자리 이동 (AP 1): 파란 표시 = 이동·교체 가능. 다시 누르거나 우클릭하면 취소."
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
		var sts := PackedStringArray()
		for sid in unit.statuses:
			sts.append("%s %d턴" % [StatusCatalog.get_def(sid).name, unit.status_turns(sid)] if StatusCatalog.get_def(sid).get("battle", false) else StatusCatalog.get_def(sid).name)
		show_toast("%s  Lv%d  속도 %d  HP %d/%d  AP %d/%d  %s%s" % [unit.display_name(), unit.data.level, unit.speed_now(), unit.hp, unit.data.max_hp, unit.ap, unit.data.max_ap, _row_text(unit),
			"  상태: " + ", ".join(sts) if not sts.is_empty() else ""])
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
const SLOT := 75.0          # 스킬·이동·필살기 칸 (58 → 30% 키움)
const SLOT_GAP := 18.0
const WEAPON_W := 44.0      # 무기 칸: 세로로 긴 칸 (패널 천장까지)
const WEAPON_H := 110.0     # 무기 칸: 이름 포함 높이가 패널 안쪽을 거의 채움
const WEAPON_SEP := 2       # 무기 사이 간격
const CAP_H := 16.0


func _refresh_panel() -> void:
	for c in slots_row.get_children():
		c.queue_free()
	slot_tip.visible = false
	var u := controller.current
	if u == null:
		return
	name_label.text = "%s · %s  Lv%d" % [u.display_name(), u.data.role, u.data.level]
	stat_label.text = "HP %d/%d   AP %d/%d (+%d/턴)\n속도 %d   %s %d" % [u.hp, u.data.max_hp, u.ap, u.data.max_ap, u.data.ap_recovery, u.data.speed, _row_text(u), u.index + 1]
	portrait.texture = UnitArt.portrait(u.data.sprite_id, manifest)
	portrait.flip_h = (u.team == "enemy") != bool(u.data.palette.get("art_faces_left", false))
	var is_player := controller.is_player_turn() and not view.busy
	var opts := {}
	for o in controller.get_command_options():
		opts[o.id] = o
	# 무기 3칸: 주무기 · 보조무기1 · 보조무기2 (세로로 긴 칸, 간격 좁게)
	var wbox := HBoxContainer.new()
	wbox.add_theme_constant_override("separation", WEAPON_SEP)
	slots_row.add_child(wbox)
	var wcost := int(opts.get("weapon", {}).get("cost", 1))
	for i in 3:
		var slot_name: String = ["주무기", "보조무기 1", "보조무기 2"][i]
		if i < u.data.weapons.size():
			var w: Dictionary = u.data.weapons[i]
			var equipped := i == u.weapon_index
			var tip := "%s  ·  %s  ·  위력 %+d%s\n%s" % [w.name, "원거리" if w.range_type == "ranged" else "근접", int(w.power_bonus), "  (장착 중)" if equipped else "", slot_name]
			var wi: int = i
			_add_slot(wbox, {"icon": _weapon_icon_vertical(str(w.get("sprite", w.id))), "caption": w.name, "enabled": is_player,
				"mark": "equipped" if equipped else "", "tip": tip, "weapon": true,
				"press": func(btn: Control):
					if equip_popup.visible and equip_index == wi:
						cancel_pending()   # 같은 무기를 다시 누르면 취소
					else:
						_open_equip_popup(btn, wi, wcost)})
		else:
			_add_slot(wbox, {"caption": slot_name, "weapon": true})
	_add_gap()
	# 자리 이동
	var mv: Dictionary = opts.get("move", {})
	if not mv.is_empty():
		var mv_tip := "%s  ·  AP %d\n이동·교체할 수 있는 자리 아래에 파란 표시가 생깁니다. 빈 자리 = 이동, 아군 = 자리 교체.%s" % [mv.name, mv.cost, "" if mv.enabled else "\n(%s)" % mv.reason]
		_add_slot(slots_row, {"icon": load("res://assets/textures/ui_move.png"), "caption": "자리 이동", "cost": mv.cost,
			"enabled": is_player and mv.enabled, "mark": "move_on" if pending_move else "", "tip": mv_tip,
			"press": func(_b):
				if pending_move:
					cancel_pending()   # 다시 누르면 취소
				else:
					_hide_equip()
					begin_move()})
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
			_add_slot(slots_row, {})
	_add_gap()
	if not ult.is_empty():
		_add_skill_slot(ult, is_player)
	else:
		_add_slot(slots_row, {"caption": "필살기", "ult": true})
	end_btn.disabled = not is_player
	_refresh_statuses(u)


## 현재 유닛의 상태 이상: 한 줄씩 (긍정 녹색 / 부정 붉은색). 호버 시 그 줄을 50% 밝게(페이드) + 설명
func _refresh_statuses(u: UnitRuntime) -> void:
	for c in status_flow.get_children():
		c.queue_free()
	if u.statuses.is_empty():
		status_flow.add_child(_label("상태 이상 없음", 12, Color(0.55, 0.58, 0.62)))
		return
	for sid in u.statuses:
		var d := StatusCatalog.get_def(sid)
		var good: bool = d.get("positive", false)
		var info: Dictionary = u.status_info.get(sid, {})
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.42, 0.22, 0.95) if good else Color(0.5, 0.12, 0.12, 0.95)
		sb.border_color = Color(0.45, 1.0, 0.6) if good else Color(1.0, 0.45, 0.4)
		sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		row.add_theme_stylebox_override("panel", sb)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var title: String = d.get("name", sid)
		if d.get("battle", false):
			var eff := StatusCatalog.effect_of(sid)
			if eff == "shield":
				title += "  %d · %d턴" % [int(info.get("value", 0)), int(info.get("turns", 0))]   # 남은 보호막
			else:
				title += "  %d턴" % int(info.get("turns", 0)) if eff != "frost" else "  %d턴 뒤" % int(info.get("turns", 0))
		row.add_child(_label(title, 13, Color(1, 1, 1)))
		var tip := "%s  ·  %s\n%s" % [d.get("name", sid), "긍정" if good else "부정", StatusCatalog.describe(sid, info)]
		row.mouse_entered.connect(func():
			_fade(row, Color(1.5, 1.5, 1.5))
			_show_slot_tip(row, tip))
		row.mouse_exited.connect(func():
			_fade(row, Color(1, 1, 1))
			slot_tip.visible = false)
		status_flow.add_child(row)


func _fade(c: CanvasItem, to: Color) -> void:
	var tw := c.create_tween()
	tw.tween_property(c, "modulate", to, 0.15)


func _add_skill_slot(o: Dictionary, is_player: bool) -> void:
	var tip := "%s  ·  AP %d\n%s%s" % [o.name, o.cost, o.desc, "" if o.enabled else "\n(%s)" % o.reason]
	var id: String = o.id
	var icon_id := id if ResourceLoader.exists("res://assets/textures/ui_%s.png" % id) else ("ultimate" if o.kind == "ultimate" else "basic_attack")
	_add_slot(slots_row, {"icon": load("res://assets/textures/ui_%s.png" % icon_id), "caption": o.name, "cost": o.cost,
		"enabled": is_player and o.enabled, "mark": "selected" if pending_action == id else "", "tip": tip,
		"ult": o.kind == "ultimate", "press": func(_b):
			if pending_action == id:
				cancel_pending()   # 다시 누르면 취소
			else:
				_hide_equip()
				begin_action(id)})


func _add_gap() -> void:
	var g := Control.new()
	g.custom_minimum_size.x = SLOT_GAP - 8.0
	slots_row.add_child(g)


## 슬롯 하나: 버튼 + 아래 이름. d 키:
##   icon, caption, cost(-1 = 표시 없음), enabled, tip, press(Callable(btn)),
##   mark: "" | "equipped"(노란 테두리) | "selected"(선택 중 테두리) | "move_on"(자리 이동 선택: 파란 바탕 + 화살표 흔들림)
##   weapon(세로로 긴 무기 칸), ult(필살기 바탕)
## 사용할 수 없으면 회색 처리, 비용은 붉은 "-AP" (사용 가능하면 파란 "-AP")
func _add_slot(parent: Container, d: Dictionary) -> void:
	var icon: Texture2D = d.get("icon", null)
	var cost: int = d.get("cost", -1)
	var mark: String = d.get("mark", "")
	var tip: String = d.get("tip", "")
	var on_press: Callable = d.get("press", Callable())
	var is_weapon: bool = d.get("weapon", false)
	var is_ult: bool = d.get("ult", false)
	var active: bool = d.get("enabled", false) and on_press.is_valid()
	var usable := active or mark == "equipped"
	var bsize := Vector2(WEAPON_W, WEAPON_H) if is_weapon else Vector2(SLOT, SLOT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size.x = bsize.x + (1.0 if is_weapon else 4.0)   # 무기 칸 가로 간격 좁게
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 아이콘+이름 덩어리를 패널 세로 가운데
	var btn := Button.new()
	btn.custom_minimum_size = bsize
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	if is_ult:
		sb.bg_color = Color(0.2, 0.08, 0.28, 0.95)
	else:
		sb.bg_color = Color(0.1, 0.11, 0.14, 0.95)
	sb.border_color = Color(1, 1, 1, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	if mark == "equipped":
		sb.border_color = Color(1.0, 0.82, 0.25)
		sb.set_border_width_all(3)
	elif mark == "selected":
		sb.border_color = Color(0.45, 0.85, 1.0)
		sb.set_border_width_all(3)
	elif mark == "move_on":
		sb.bg_color = Color(0.18, 0.45, 0.95)
		sb.border_color = Color(0.6, 0.85, 1.0)
		sb.set_border_width_all(3)
	if not usable:
		sb.bg_color = Color(0.24, 0.24, 0.26, 0.9)   # 회색 처리
		sb.border_color = Color(1, 1, 1, 0.1)
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
		var m := 4.0 if is_weapon else 7.0
		tr.offset_left = m
		tr.offset_top = m
		tr.offset_right = -m
		tr.offset_bottom = -m
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not usable:
			tr.modulate = Color(0.55, 0.55, 0.58, 0.8)
		btn.add_child(tr)
		if mark == "move_on":
			# 가운데 화살표가 좌우로 살짝 왔다갔다
			var set_dx := func(v: float): tr.offset_left = m + v; tr.offset_right = -m + v
			var tw := tr.create_tween().set_loops()
			tw.tween_method(set_dx, -3.0, 3.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_method(set_dx, 3.0, -3.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif d.is_empty() or not d.has("icon"):
		btn.modulate = Color(1, 1, 1, 0.35)   # 빈 칸
	if cost >= 0:
		var cl := _label("-%d" % cost, 12, Color(0.6, 0.85, 1.0) if usable else Color(1.0, 0.3, 0.28))
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cl)
		cl.position = Vector2(bsize.x - 18.0, -1.0)
	btn.disabled = not active
	if mark == "equipped":
		btn.disabled = not on_press.is_valid()
	if on_press.is_valid():
		btn.pressed.connect(func(): on_press.call(btn))
	if tip != "":
		btn.mouse_entered.connect(_show_slot_tip.bind(btn, tip))
		btn.mouse_exited.connect(func(): slot_tip.visible = false)
	var cap := _label(d.get("caption", ""), 11 if is_weapon else 12, Color(0.9, 0.9, 0.92) if usable else Color(0.55, 0.55, 0.58))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.clip_text = true
	cap.custom_minimum_size = Vector2(0, CAP_H)
	# 버튼 + 이름을 한 덩어리로 패널 세로 가운데 (위/아래 대칭)
	box.add_child(btn)
	box.add_child(cap)
	parent.add_child(box)


var _wicon_cache: Dictionary = {}


## 세로 무기 칸용: 가로로 그린 무기 원화를 90° 돌린 텍스처 (총구가 위)
func _weapon_icon_vertical(wid: String) -> Texture2D:
	if _wicon_cache.has(wid):
		return _wicon_cache[wid]
	var tex := _weapon_icon(wid)
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.rotate_90(COUNTERCLOCKWISE)
	img.adjust_bcs(2.8, 1.1, 1.0)   # 무기 원화가 어두워 어두운 칸 바탕에서 보이게 밝게 보정
	var out := ImageTexture.create_from_image(img)
	_wicon_cache[wid] = out
	return out


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


## nth = 같은 대상의 몇 번째 숫자인지 (늦게·아래로 띄워 겹치지 않게)
func _spawn_popup(target: UnitRuntime, text: String, color: Color, nth: int = 0) -> void:
	var l := _label(text, 24 if nth == 0 else 20, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.position = view.get_unit_screen_pos(target) + Vector2(-30, -30 + 26 * nth)
	popup_root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	var d := 0.35 * nth
	if nth > 0:
		l.modulate.a = 0.0
		tw.tween_property(l, "modulate:a", 1.0, 0.1).set_delay(d)
	tw.tween_property(l, "position:y", l.position.y - 50, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(d)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3 + d + 0.3)
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
	var boxes: Array = []
	for c in slots_row.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is HBoxContainer:
			for w in c.get_children():
				boxes.append(w)
		elif c is VBoxContainer:
			boxes.append(c)
	return boxes[i].get_child(0) if i < boxes.size() else null
