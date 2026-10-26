@tool
extends Control
## 일정 에디터 (Godot 에디터 상단 "일정" 탭, addons/rtz_schedule_editor) — 02_NPC_SCHEDULE_EDITOR 명세.
## 대원별 주간 일정(data/outgame/schedules/<대원 id>.json): 요일·시간 블록마다 목적지 시설 + 행동,
## 해금 조건(그 시설이 열리면 이 블록으로 바뀜 = 생활 변화) · 잠겼을 때 대체 장소 · 자주 머무는 장소 · 청소 위임 성향.
## 아래: 기지 단면 미리보기 + 시간 스크러버(씬 실행 없이 그 시각의 목적지·경로), 검사(경로 불가·겹침·잠금·참조 누락).
## 시설·대원 목록은 data/outgame.xlsx (시설·대원 시트).

const DAY_COLORS := [Color(0.35, 0.6, 0.9), Color(0.9, 0.5, 0.3), Color(0.5, 0.85, 0.45), Color(0.85, 0.4, 0.75), Color(0.95, 0.8, 0.3), Color(0.4, 0.85, 0.85), Color(0.75, 0.6, 0.95)]

var data: OutgameData
var npc_list: OptionButton
var status: Label
var day_buttons: Array[Button] = []
var block_box: VBoxContainer
var pref_box: VBoxContainer
var deleg_box: VBoxContainer
var timeline: Control
var map: Control
var check_label: RichTextLabel
var check_summary: Label
var scrub_day: OptionButton
var scrub_slider: HSlider
var scrub_label: Label
var open_mode: OptionButton
var npc_id := ""
var sched: Dictionary = {}
var day := 0
var dirty := false
var _rebuilding := false


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
	# 위: 대원 선택 · 저장 · 테스트 플레이
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "대원 주간 일정"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	npc_list = OptionButton.new()
	npc_list.custom_minimum_size.x = 200
	npc_list.item_selected.connect(func(i): _select_npc(str(npc_list.get_item_metadata(i))))
	top.add_child(npc_list)
	top.add_child(_btn("저장 (Ctrl+S)", _save))
	top.add_child(_btn("되돌리기", func(): _load(npc_id)))
	top.add_child(_btn("기지 테스트 플레이", _play))
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_btn("엑셀 다시 읽기", func(): reload_data(true)))

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# 왼쪽: 자주 머무는 장소 · 청소 위임 · 도움말
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 250
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)
	left.add_child(_head("자주 머무는 장소"))
	left.add_child(_small("일정이 없거나 갈 수 없을 때 (위에서부터)"))
	pref_box = VBoxContainer.new()
	left.add_child(pref_box)
	left.add_child(_head("청소 위임 성향"))
	deleg_box = VBoxContainer.new()
	left.add_child(deleg_box)
	var help := _small("· 블록 = 요일·시간 구간의 목적지 + 행동\n· '해금 조건' 블록은 그 시설이 열리면 같은 시간의 일반 블록 대신 쓰임 (시설 해금 → 생활 변화)\n· 목적지가 잠겼거나 길이 없으면 '잠기면' 장소 → 자주 머무는 장소\n· 대화(잡담)는 쉬기·식사·잡담·대기 중인 두 대원이 같은 방에 있으면 생김 (대화이벤트 시트)\n· 플레이어 지시(청소·업무·훈련)는 일정보다 우선, 끝나면 지금 시각 일정으로 복귀\n· 저장하면 실행 중인 게임에 바로 반영")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(help)
	# 가운데: 주간 시간표 + 요일 블록 목록
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	body.add_child(mid)
	timeline = Control.new()
	timeline.custom_minimum_size = Vector2(0, 7 * 20 + 22)
	timeline.mouse_filter = Control.MOUSE_FILTER_STOP
	timeline.draw.connect(_draw_timeline)
	timeline.gui_input.connect(_timeline_input)
	mid.add_child(timeline)
	var days := HBoxContainer.new()
	days.add_theme_constant_override("separation", 4)
	mid.add_child(days)
	for i in 7:
		var b := _btn(OutgameData.WEEKDAYS[i], func(): _set_day(i))
		b.toggle_mode = true
		b.custom_minimum_size.x = 44
		days.add_child(b)
		day_buttons.append(b)
	days.add_child(_btn("+ 블록", _add_block))
	var cp := MenuButton.new()
	cp.text = "이 요일 복사 →"
	cp.get_popup().add_item("평일 (월~금) 전체", 0)
	cp.get_popup().add_item("주말 (토·일)", 1)
	cp.get_popup().add_item("모든 요일", 2)
	cp.get_popup().id_pressed.connect(_copy_day)
	days.add_child(cp)
	var head := HBoxContainer.new()
	mid.add_child(head)
	for t in [["시작", 62], ["끝", 62], ["목적지", 150], ["행동", 84], ["해금 조건 (선택)", 150], ["잠기면 (선택)", 150]]:
		var l := _small(t[0])
		l.custom_minimum_size.x = t[1]
		head.add_child(l)
	var bs := ScrollContainer.new()
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(bs)
	block_box = VBoxContainer.new()
	block_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block_box.add_theme_constant_override("separation", 3)
	bs.add_child(block_box)

	# 아래: 미리보기 + 검사
	var bottom := HSplitContainer.new()
	bottom.custom_minimum_size.y = 290
	root.add_child(bottom)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(pv)
	var sc := HBoxContainer.new()
	sc.add_theme_constant_override("separation", 8)
	pv.add_child(sc)
	sc.add_child(_head("미리보기"))
	scrub_day = OptionButton.new()
	for i in 7:
		scrub_day.add_item(OutgameData.WEEKDAYS[i])
	scrub_day.item_selected.connect(func(_i): _refresh_preview())
	sc.add_child(scrub_day)
	scrub_slider = HSlider.new()
	scrub_slider.min_value = 0
	scrub_slider.max_value = 1430
	scrub_slider.step = 10
	scrub_slider.value = 600
	scrub_slider.custom_minimum_size.x = 260
	scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_slider.value_changed.connect(func(_v): _refresh_preview())
	sc.add_child(scrub_slider)
	scrub_label = Label.new()
	scrub_label.custom_minimum_size.x = 60
	sc.add_child(scrub_label)
	open_mode = OptionButton.new()
	open_mode.add_item("처음 해금 상태")
	open_mode.add_item("모두 해금 가정")
	open_mode.item_selected.connect(func(_i): _refresh_preview(); _run_checks())
	sc.add_child(open_mode)
	map = Control.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.draw.connect(_draw_map)
	map.resized.connect(map.queue_redraw)
	pv.add_child(map)
	var ck := VBoxContainer.new()
	ck.custom_minimum_size.x = 420
	bottom.add_child(ck)
	ck.add_child(_head("검사"))
	check_summary = Label.new()
	check_summary.add_theme_font_size_override("font_size", 13)
	ck.add_child(check_summary)
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	check_label.add_theme_font_size_override("normal_font_size", 12)
	ck.add_child(check_label)
	reload_data(false)


# ================================================================ 데이터
func reload_data(keep_edit: bool = true) -> void:
	var d := OutgameData.load_from()
	if d == null:
		if status != null:
			status.text = "data/outgame.xlsx 를 읽지 못했습니다"
		return
	data = d
	npc_list.clear()
	for id in data.npc_order:
		npc_list.add_item("%s (%s)" % [data.npc_name(id), id])
		npc_list.set_item_metadata(npc_list.item_count - 1, id)
	if npc_id == "" or not data.npcs.has(npc_id):
		npc_id = data.npc_order[0] if not data.npc_order.is_empty() else ""
	for i in npc_list.item_count:
		if npc_list.get_item_metadata(i) == npc_id:
			npc_list.select(i)
	if keep_edit and dirty and not sched.is_empty():
		_rebuild()
	else:
		_load(npc_id)


func _select_npc(id: String) -> void:
	if dirty:
		_save()
	_load(id)


func _load(id: String) -> void:
	npc_id = id
	if id == "":
		return
	sched = OutgameData.read_schedule(id)
	dirty = false
	_rebuild()
	status.text = "data/outgame/schedules/%s.json" % id


func _open_set() -> Dictionary:
	var out := {}
	for f in data.facility_order:
		if open_mode.selected == 1 or data.facilities[f].initial_open:
			out[f] = true
	return out


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 함)"
	timeline.queue_redraw()
	_refresh_preview()
	_run_checks()


func _blocks_of(wd: int) -> Array:
	var bs: Array = (sched.get("weekly_schedule", []) as Array).filter(func(b): return int(b.weekday) == wd)
	bs.sort_custom(func(a, b): return int(a.start_minute) < int(b.start_minute) or (int(a.start_minute) == int(b.start_minute) and (a.get("required_unlocks", []) as Array).size() > (b.get("required_unlocks", []) as Array).size()))
	return bs


static func _parse_time(s: String) -> int:
	var p := s.strip_edges().split(":")
	if p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int():
		return clampi(int(p[0]) * 60 + int(p[1]), 0, 1440)
	if s.strip_edges().is_valid_int():
		return clampi(int(s) * 60, 0, 1440)
	return -1


# ================================================================ 화면 구성
func _rebuild() -> void:
	_rebuilding = true
	for c in pref_box.get_children():
		c.queue_free()
	for c in deleg_box.get_children():
		c.queue_free()
	var prefs: Array = sched.get("preferred_facility_ids", [])
	for fid in data.facility_order:
		var f: Dictionary = data.facilities[fid]
		if f.tag == "계단":
			continue
		var cb := CheckBox.new()
		cb.text = "%s · %s" % [data.facility_name(fid), data.floor_name(f.floor)]
		cb.button_pressed = fid in prefs
		cb.toggled.connect(func(on):
			var arr: Array = sched.get("preferred_facility_ids", [])
			if on and not fid in arr:
				arr.append(fid)
			elif not on:
				arr.erase(fid)
			sched["preferred_facility_ids"] = arr
			_mark())
		pref_box.add_child(cb)
	var dr: Dictionary = sched.get("delegation_rules", {})
	sched["delegation_rules"] = dr
	var can := CheckBox.new()
	can.text = "청소 지시를 다른 대원에게 넘김"
	can.button_pressed = dr.get("can_delegate_cleaning", false)
	can.toggled.connect(func(on): dr["can_delegate_cleaning"] = on; _mark())
	deleg_box.add_child(can)
	var ch := HBoxContainer.new()
	ch.add_child(_small("확률"))
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 100
	sp.suffix = "%"
	sp.value = float(dr.get("chance", 1.0)) * 100.0
	sp.value_changed.connect(func(v): dr["chance"] = v / 100.0; _mark())
	ch.add_child(sp)
	deleg_box.add_child(ch)
	var selfcb := CheckBox.new()
	selfcb.text = "맡길 사람이 없으면 직접 함"
	selfcb.button_pressed = dr.get("self_if_none", true)
	selfcb.toggled.connect(func(on): dr["self_if_none"] = on; _mark())
	deleg_box.add_child(selfcb)
	deleg_box.add_child(_small("넘길 대상 (비우면 아무나, 가까운 순):"))
	var tos: Array = dr.get("delegate_to", [])
	for id in data.npc_order:
		if id == npc_id:
			continue
		var cb := CheckBox.new()
		cb.text = data.npc_name(id)
		cb.button_pressed = id in tos
		cb.toggled.connect(func(on):
			var arr: Array = dr.get("delegate_to", [])
			if on and not id in arr:
				arr.append(id)
			elif not on:
				arr.erase(id)
			dr["delegate_to"] = arr
			_mark())
		deleg_box.add_child(cb)
	_set_day(day)
	_rebuilding = false
	_run_checks()


func _set_day(d: int) -> void:
	day = d
	for i in day_buttons.size():
		day_buttons[i].set_pressed_no_signal(i == d)
	for c in block_box.get_children():
		c.queue_free()
	for b in _blocks_of(d):
		block_box.add_child(_block_row(b))
	timeline.queue_redraw()
	scrub_day.select(d)
	_refresh_preview()


func _fac_option(current: String, allow_none: bool) -> OptionButton:
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = 150
	ob.fit_to_longest_item = false
	if allow_none:
		ob.add_item("—")
		ob.set_item_metadata(0, "")
	for fid in data.facility_order:
		var f: Dictionary = data.facilities[fid]
		ob.add_item("%s%s" % [data.facility_name(fid), "" if f.initial_open else " (잠금)"])
		ob.set_item_metadata(ob.item_count - 1, fid)
		if fid == current:
			ob.select(ob.item_count - 1)
	if current != "" and not data.facilities.has(current):
		ob.add_item("?? %s" % current)
		ob.set_item_metadata(ob.item_count - 1, current)
		ob.select(ob.item_count - 1)
	return ob


func _block_row(b: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var st := LineEdit.new()
	st.text = OutgameData.hm(int(b.start_minute))
	st.custom_minimum_size.x = 62
	var en := LineEdit.new()
	en.text = OutgameData.hm(int(b.end_minute))
	en.custom_minimum_size.x = 62
	for pair in [[st, "start_minute"], [en, "end_minute"]]:
		var le: LineEdit = pair[0]
		var key: String = pair[1]
		var apply := func(_t = ""):
			var m := _parse_time(le.text)
			if m < 0:
				le.text = OutgameData.hm(int(b[key]))
				return
			if m != int(b[key]):
				b[key] = m
				le.text = OutgameData.hm(m)
				_mark()
		le.text_submitted.connect(apply)
		le.focus_exited.connect(apply)
		row.add_child(le)
	var tgt := _fac_option(str(b.get("target_facility_id", "")), false)
	tgt.item_selected.connect(func(i): b["target_facility_id"] = str(tgt.get_item_metadata(i)); _mark())
	row.add_child(tgt)
	var act := OptionButton.new()
	act.custom_minimum_size.x = 84
	for k in OutgameData.ACTIVITIES:
		act.add_item(OutgameData.ACTIVITIES[k])
		act.set_item_metadata(act.item_count - 1, k)
		if k == str(b.get("activity_id", "")):
			act.select(act.item_count - 1)
	act.item_selected.connect(func(i): b["activity_id"] = str(act.get_item_metadata(i)); _mark())
	row.add_child(act)
	var req: Array = b.get("required_unlocks", [])
	var ru := _fac_option(str(req[0]) if not req.is_empty() else "", true)
	ru.item_selected.connect(func(i):
		var v := str(ru.get_item_metadata(i))
		if v == "":
			b.erase("required_unlocks")
		else:
			b["required_unlocks"] = [v]
		_mark())
	row.add_child(ru)
	var fb := _fac_option(str(b.get("fallback_facility_id", "")), true)
	fb.item_selected.connect(func(i):
		var v := str(fb.get_item_metadata(i))
		if v == "":
			b.erase("fallback_facility_id")
		else:
			b["fallback_facility_id"] = v
		_mark())
	row.add_child(fb)
	row.add_child(_btn("복제", func():
		var c: Dictionary = b.duplicate(true)
		(sched.weekly_schedule as Array).append(c)
		_mark()
		_set_day(day)))
	row.add_child(_btn("삭제", func():
		(sched.weekly_schedule as Array).erase(b)
		_mark()
		_set_day(day)))
	return row


func _add_block() -> void:
	var bs := _blocks_of(day)
	var start := int(bs[-1].end_minute) if not bs.is_empty() else 480
	start = mini(start, 1380)
	var home := str(data.npcs.get(npc_id, {}).get("start", data.facility_order[0]))
	if not sched.has("weekly_schedule"):
		sched["weekly_schedule"] = []
	(sched.weekly_schedule as Array).append({"weekday": day, "start_minute": start, "end_minute": mini(start + 60, 1440), "target_facility_id": home, "activity_id": "idle"})
	_mark()
	_set_day(day)


func _copy_day(id: int) -> void:
	var targets: Array = [[0, 1, 2, 3, 4], [5, 6], [0, 1, 2, 3, 4, 5, 6]][id]
	var src := _blocks_of(day)
	var keep: Array = (sched.weekly_schedule as Array).filter(func(b): return int(b.weekday) == day or not int(b.weekday) in targets)
	for wd in targets:
		if wd == day:
			continue
		for b in src:
			var c: Dictionary = b.duplicate(true)
			c.weekday = wd
			keep.append(c)
	sched.weekly_schedule = keep
	_mark()
	status.text = "%s 일정을 복사했습니다 (저장 안 함)" % OutgameData.WEEKDAYS[day]


# ================================================================ 주간 시간표 (7일 × 24시간)
func _fac_color(fid: String) -> Color:
	var f: Dictionary = data.facilities.get(fid, {})
	if f.is_empty():
		return Color(0.6, 0.1, 0.1)
	var p := LightingPresets.get_preset(f.light)
	var c: Color = (p.key as Color).lerp(p.ambient, 0.35 + 0.2 * (data.facility_order.find(fid) % 3))
	return c


func _draw_timeline() -> void:
	if data == null:
		return
	var w := timeline.size.x - 40.0
	var rh := 20.0
	var font := timeline.get_theme_default_font()
	for h in range(0, 25, 3):
		var x := 36.0 + w * h / 24.0
		timeline.draw_line(Vector2(x, 0), Vector2(x, 7 * rh), Color(1, 1, 1, 0.12))
		timeline.draw_string(font, Vector2(x - 8, 7 * rh + 15), "%d" % h, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.75, 0.85))
	for wd in 7:
		var y := wd * rh
		if wd == day:
			timeline.draw_rect(Rect2(0, y, timeline.size.x, rh), Color(1, 1, 1, 0.07))
		timeline.draw_string(font, Vector2(6, y + 15), OutgameData.WEEKDAYS[wd], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.75) if wd == day else Color(0.8, 0.85, 0.9))
		for b in _blocks_of(wd):
			var x0 := 36.0 + w * int(b.start_minute) / 1440.0
			var x1 := 36.0 + w * int(b.end_minute) / 1440.0
			var cond := not (b.get("required_unlocks", []) as Array).is_empty()
			var r := Rect2(x0, y + (2.0 if not cond else 11.0), maxf(1.0, x1 - x0 - 1), rh - (4.0 if not cond else 13.0))
			timeline.draw_rect(r, _fac_color(str(b.target_facility_id)))
			if not cond and r.size.x > 40:
				timeline.draw_string(font, r.position + Vector2(3, 12), data.facility_name(str(b.target_facility_id)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4, 10, Color(0, 0, 0, 0.85))
	# 미리보기 시각
	var sx := 36.0 + w * scrub_slider.value / 1440.0
	timeline.draw_line(Vector2(sx, 0), Vector2(sx, 7 * rh), Color(1, 1, 0.3), 2.0)


func _timeline_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var wd := clampi(int(e.position.y / 20.0), 0, 6)
		var w := timeline.size.x - 40.0
		if e.position.x > 36:
			scrub_slider.value = clampf((e.position.x - 36.0) / w * 1440.0, 0, 1430)
		_set_day(wd)


# ================================================================ 미리보기 (기지 단면 + 스크러버)
func _dest_of(id: String, s: Dictionary, wd: int, minute: int, open: Dictionary) -> Dictionary:
	var home := str(data.npcs.get(id, {}).get("start", ""))
	var is_open := func(f: String) -> bool: return open.has(f)
	return NpcScheduleResolver.destination(s, wd, minute, is_open,
		func(f: String) -> bool: return open.has(f) and (home == "" or RoomRouteService.reachable(data, home, f, is_open)))


func _refresh_preview() -> void:
	if data == null or scrub_label == null:
		return
	scrub_label.text = OutgameData.hm(int(scrub_slider.value))
	map.queue_redraw()
	timeline.queue_redraw()


func _draw_map() -> void:
	if data == null:
		return
	var br := data.base_rect()
	if br.size.x <= 0:
		return
	var k := minf((map.size.x - 20) / br.size.x, (map.size.y - 30) / br.size.y)
	var off := Vector2(10, 22) - br.position * k
	var font := map.get_theme_default_font()
	var open := _open_set()
	var is_open := func(f: String) -> bool: return open.has(f)
	var wd := scrub_day.selected
	var minute := int(scrub_slider.value)
	var mine := _dest_of(npc_id, sched, wd, minute, open)
	for fid in data.facility_order:
		var r := data.facility_rect(fid)
		var rr := Rect2(off + r.position * k, r.size * k).grow(-1.5)
		var f: Dictionary = data.facilities[fid]
		if open.has(fid):
			var p := LightingPresets.get_preset(f.light)
			map.draw_rect(rr, (p.ambient as Color).darkened(0.35))
		else:
			map.draw_rect(rr, Color(0, 0, 0))
		map.draw_rect(rr, Color(0.05, 0.05, 0.08), false, 1.5)
		map.draw_string(font, rr.position + Vector2(4, 13), data.facility_name(fid) if f.tag != "계단" else "계단", HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 6, 11, Color(1, 1, 1, 0.85) if open.has(fid) else Color(0.5, 0.5, 0.5))
		if fid == mine.facility:
			map.draw_rect(rr.grow(1), Color(1, 0.9, 0.2), false, 3.0)
	# 다른 대원 (작은 점) + 이 대원 (큰 점)
	var slot := {}
	for id in data.npc_order:
		var s: Dictionary = sched if id == npc_id else data.schedules.get(id, {})
		var d := _dest_of(id, s, wd, minute, open)
		if d.facility == "":
			continue
		var r := data.facility_rect(d.facility)
		var n := int(slot.get(d.facility, 0))
		slot[d.facility] = n + 1
		var pos := off + Vector2(r.position.x + 20, data.floor_line(d.facility) - 14) * k + Vector2(n * 22, 0)
		var me := id == npc_id
		map.draw_circle(pos, 10.0, Color(1, 0.9, 0.2) if me else Color(0.85, 0.9, 1))
		map.draw_circle(pos, 10.0, Color(0.05, 0.05, 0.08), false, 1.5)
		var ini := data.npc_name(id).left(1)
		map.draw_string(font, pos + Vector2(-6, 5), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.1))
	# 이 대원의 이전 목적지 → 지금 목적지 경로
	var b: Dictionary = mine.get("block", {})
	if mine.facility != "" and not b.is_empty():
		var pm := int(b.start_minute) - 1
		var pwd := wd
		if pm < 0:
			pm = 1439
			pwd = (wd + 6) % 7
		var prev := _dest_of(npc_id, sched, pwd, pm, open)
		if prev.facility != "" and prev.facility != mine.facility:
			var path := RoomRouteService.find_path(data, prev.facility, mine.facility, is_open)
			if not path.is_empty():
				var pts := PackedVector2Array([off + Vector2(data.facility_center_x(prev.facility), data.floor_line(prev.facility) - 6) * k])
				for p in RoomRouteService.waypoints(data, path, data.facility_center_x(mine.facility)):
					pts.append(off + (p + Vector2(0, -6)) * k)
				map.draw_polyline(pts, Color(1, 0.9, 0.2, 0.8), 2.0)
	var info := "%s %s → %s · %s (%s)" % [OutgameData.WEEKDAYS[wd], OutgameData.hm(minute), data.facility_name(mine.facility) if mine.facility != "" else "갈 곳 없음",
		OutgameData.ACTIVITIES.get(mine.activity, mine.activity), mine.reason]
	map.draw_string(font, Vector2(10, 14), info + "   (노란 원 = 이 대원, 흰 원 = 다른 대원 · 이름 첫 글자)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.6))


# ================================================================ 검사
func _run_checks() -> void:
	if data == null or check_label == null:
		return
	var res := NpcScheduleResolver.validate(sched, data, _open_set())
	var counts := {"경로 불가": 0, "시간 겹침": 0, "잠금 목적지": 0, "참조 누락": 0}
	var lines := PackedStringArray()
	for e in res:
		var t: String = e.text
		if t.contains("경로 없음"):
			counts["경로 불가"] += 1
		elif t.contains("겹침"):
			counts["시간 겹침"] += 1
		elif t.contains("잠김"):
			counts["잠금 목적지"] += 1
		elif t.contains("없는"):
			counts["참조 누락"] += 1
		lines.append("[color=%s]%s[/color]" % ["#ff7766" if e.level == "error" else "#ffd166", t])
	for w in data.warnings:
		counts["참조 누락"] += 1
		lines.append("[color=#ff7766]엑셀: %s[/color]" % w)
	var days_empty := PackedStringArray()
	for wd in 7:
		if _blocks_of(wd).is_empty():
			days_empty.append(OutgameData.WEEKDAYS[wd])
	if not days_empty.is_empty():
		lines.append("[color=#ffd166]일정 없는 요일: %s (자주 머무는 장소에서 대기)[/color]" % ", ".join(days_empty))
	check_summary.text = "  ".join(counts.keys().map(func(k): return "[%s %d]" % [k, counts[k]]))
	check_label.text = "\n".join(lines) if not lines.is_empty() else "[color=#88ff99]문제 없음[/color]"


# ================================================================ 저장 · 테스트
func _save() -> void:
	if npc_id == "":
		return
	sched["npc_id"] = npc_id
	var bs: Array = sched.get("weekly_schedule", [])
	bs.sort_custom(func(a, b): return int(a.weekday) < int(b.weekday) or (int(a.weekday) == int(b.weekday) and int(a.start_minute) < int(b.start_minute)))
	var err := OutgameData.write_schedule(npc_id, sched)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	dirty = err != OK
	status.text = "저장됨: data/outgame/schedules/%s.json" % npc_id if err == OK else "저장 실패 (%d)" % err


## 저장 → 기지 화면 실행 (새 게임, 저장 파일은 건드리지 않음). 카메라는 이 대원 쪽
func _play() -> void:
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"base": true, "npc": npc_id}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn")


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 작은 위젯
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


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	return l
