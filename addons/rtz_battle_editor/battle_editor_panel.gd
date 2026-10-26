@tool
extends Control
## 전투 발생 에디터 (Godot 에디터 상단 "전투 발생" 탭, addons/rtz_battle_editor).
## 기지 시간에 따라 전투가 일어나는 규칙 목록 (data/outgame/battle_rules.json). 규칙 판정은 BattleRules — 게임(BaseSim)과 같은 코드.
## 왼쪽: 규칙 목록 · 오른쪽: 선택한 규칙 편집 · 아래: 게임 시작부터 7일 동안 발생 시각 미리보기 + 검사.
## 전투가 발생하면 기지 시계가 멈추고 "전투 배치로" 막대가 뜬다 (넘기기 허용 규칙만 넘길 수 있음).

const RULE_COLORS := [Color(1.0, 0.45, 0.4), Color(1.0, 0.75, 0.3), Color(0.45, 0.8, 1.0), Color(0.6, 0.9, 0.45), Color(0.85, 0.55, 1.0), Color(0.4, 0.95, 0.85)]
const PREVIEW_DAYS := 7

var rules: Array = []
var sel := -1
var dirty := false
var _rebuilding := false
var stage_ids: Array[String] = []
var clock := WorldClock.new()
var start_minute := 480

var rule_list: ItemList
var status: Label
var form: VBoxContainer
var timeline: Control
var upcoming: RichTextLabel
var check_label: RichTextLabel


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
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "전투 발생 규칙"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	top.add_child(_btn("저장 (Ctrl+S)", _save))
	top.add_child(_btn("되돌리기", func(): _load()))
	top.add_child(_btn("기지 테스트 플레이 (다음 전투 10분 전부터)", _play))
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)

	var body := VSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var upper := HSplitContainer.new()
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(upper)
	# 왼쪽: 규칙 목록
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	upper.add_child(left)
	left.add_child(_head("규칙 (위에서부터 먼저 검사)"))
	rule_list = ItemList.new()
	rule_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rule_list.item_selected.connect(func(i): _select(i))
	left.add_child(rule_list)
	var lb := HBoxContainer.new()
	left.add_child(lb)
	lb.add_child(_btn("추가", _add_rule))
	lb.add_child(_btn("복제", _dup_rule))
	lb.add_child(_btn("삭제", _del_rule))
	lb.add_child(_btn("▲", func(): _move_rule(-1)))
	lb.add_child(_btn("▼", func(): _move_rule(1)))
	left.add_child(_small("같은 분에 여러 규칙이 겹치면 위 규칙 하나만 발생.\n전투가 대기 중이면 다른 규칙은 발생하지 않음."))
	# 오른쪽: 편집 폼
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	upper.add_child(scroll)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)
	# 아래: 미리보기 · 검사
	var lower := HSplitContainer.new()
	lower.custom_minimum_size.y = 250
	body.add_child(lower)
	var tl_box := VBoxContainer.new()
	tl_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(tl_box)
	tl_box.add_child(_head("미리보기: 게임 시작부터 %d일 (새 게임 기준, 전투 처리 시간은 제외)" % PREVIEW_DAYS))
	timeline = Control.new()
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.custom_minimum_size = Vector2(500, 200)
	timeline.draw.connect(_draw_timeline)
	timeline.resized.connect(timeline.queue_redraw)
	tl_box.add_child(timeline)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	lower.add_child(right)
	right.add_child(_head("다음 발생 예정"))
	upcoming = RichTextLabel.new()
	upcoming.bbcode_enabled = true
	upcoming.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(upcoming)
	right.add_child(_head("검사"))
	check_label = RichTextLabel.new()
	check_label.bbcode_enabled = true
	check_label.fit_content = true
	right.add_child(check_label)
	reload_data(false)


# ================================================================ 데이터
func reload_data(keep_edit: bool = true) -> void:
	stage_ids.clear()
	var gd := GameData.load_from()
	if gd != null:
		stage_ids.assign(gd.stage_order)
	var od := OutgameData.load_from()
	if od != null:
		start_minute = OutgameData.parse_hm(od.text("start_time", "08:00"), 480)
		clock.setup(od.text("start_date", "2048-04-07"), start_minute)
	else:
		clock.setup("2048-04-07", start_minute)
	if keep_edit and dirty:
		_rebuild()
	else:
		_load()


func _load() -> void:
	rules = OutgameData.read_battle_rules()
	dirty = false
	sel = clampi(sel, 0, rules.size() - 1) if not rules.is_empty() else -1
	status.text = "%d개 규칙" % rules.size()
	_rebuild()


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 됨)"
	_refresh_list()
	_refresh_preview()


func _new_rule(id: String) -> Dictionary:
	return {"id": id, "name": "새 전투", "enabled": true, "mode": "interval", "interval_minutes": 360, "anchor": "06:00",
		"weekdays": [0, 1, 2, 3, 4, 5, 6], "start_day": "", "times": [], "date": "",
		"stages": [stage_ids[0]] if not stage_ids.is_empty() else [], "allow_skip": false, "note": ""}


func _unique_id(base: String) -> String:
	var ids := rules.map(func(r): return str(r.get("id", "")))
	var i := 1
	while ids.has("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]


func _add_rule() -> void:
	rules.append(_new_rule(_unique_id("battle")))
	sel = rules.size() - 1
	_rebuild()
	_mark()


func _dup_rule() -> void:
	if sel < 0:
		return
	var r: Dictionary = rules[sel].duplicate(true)
	r.id = _unique_id(str(r.id))
	r.name = str(r.name) + " (복제)"
	rules.insert(sel + 1, r)
	sel += 1
	_rebuild()
	_mark()


func _del_rule() -> void:
	if sel < 0:
		return
	rules.remove_at(sel)
	sel = mini(sel, rules.size() - 1)
	_rebuild()
	_mark()


func _move_rule(d: int) -> void:
	var j := sel + d
	if sel < 0 or j < 0 or j >= rules.size():
		return
	var r = rules[sel]
	rules[sel] = rules[j]
	rules[j] = r
	sel = j
	_rebuild()
	_mark()


func _select(i: int) -> void:
	sel = i
	_rebuild_form()
	timeline.queue_redraw()


# ================================================================ 화면 구성
func _rebuild() -> void:
	_refresh_list()
	_rebuild_form()
	_refresh_preview()


func _refresh_list() -> void:
	rule_list.clear()
	for i in rules.size():
		var r: Dictionary = rules[i]
		var on: bool = r.get("enabled", true)
		rule_list.add_item("%s%s\n   %s" % ["" if on else "[꺼짐] ", r.get("name", r.get("id", "")), BattleRules.describe(r)])
		rule_list.set_item_custom_fg_color(i, _rule_color(i) if on else Color(0.55, 0.55, 0.6))
	if sel >= 0 and sel < rules.size():
		rule_list.select(sel)


func _rule_color(i: int) -> Color:
	return RULE_COLORS[i % RULE_COLORS.size()]


func _rebuild_form() -> void:
	_rebuilding = true
	for c in form.get_children():
		form.remove_child(c)
		c.queue_free()
	if sel < 0 or sel >= rules.size():
		form.add_child(_small("규칙이 없습니다. 왼쪽 '추가' 로 만드세요. (규칙이 없으면 전투는 '전투 출정' 버튼으로만)"))
		_rebuilding = false
		return
	var r: Dictionary = rules[sel]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	form.add_child(grid)
	_row(grid, "id", _line(str(r.get("id", "")), func(t): r.id = t.strip_edges()))
	_row(grid, "이름 (기지 알림에 표시)", _line(str(r.get("name", "")), func(t): r.name = t))
	_row(grid, "사용", _check("이 규칙 사용", r.get("enabled", true), func(on): r.enabled = on))
	var mode := OptionButton.new()
	for k in BattleRules.MODES:
		mode.add_item(BattleRules.MODES[k])
		mode.set_item_metadata(mode.item_count - 1, k)
		if k == str(r.get("mode", "interval")):
			mode.select(mode.item_count - 1)
	mode.item_selected.connect(func(i):
		r.mode = str(mode.get_item_metadata(i))
		if r.mode != "interval" and (r.get("times", []) as Array).is_empty():
			r.times = ["12:00"]
		_mark()
		_rebuild_form.call_deferred())
	_row(grid, "방식", mode)
	match str(r.get("mode", "interval")):
		"interval":
			var iv := int(r.get("interval_minutes", 360))
			var hb := HBoxContainer.new()
			var hs := _spin(0, 168, 1, floori(iv / 60.0), "시간")
			var ms := _spin(0, 50, 10, iv % 60, "분")
			var upd := func(_v):
				r.interval_minutes = maxi(10, int(hs.value) * 60 + int(ms.value))
				_mark()
			hs.value_changed.connect(upd)
			ms.value_changed.connect(upd)
			hb.add_child(hs)
			hb.add_child(ms)
			var per := _small("마다 (최소 10분)")
			per.autowrap_mode = TextServer.AUTOWRAP_OFF
			hb.add_child(per)
			_row(grid, "간격", hb)
			_row(grid, "기준 시각 (HH:MM)", _line(str(r.get("anchor", "00:00")), func(t): r.anchor = t.strip_edges(), "예: 06:00 + 6시간 → 00·06·12·18시"))
		"daily":
			_row(grid, "시각들 (쉼표로)", _line(", ".join(r.get("times", [])), func(t): r.times = _split_times(t), "예: 06:00, 18:30"))
		"once":
			_row(grid, "날짜 (YYYY-MM-DD)", _line(str(r.get("date", "")), func(t): r.date = t.strip_edges(), "게임 시작 " + clock.date_str(start_minute)))
			_row(grid, "시각 (HH:MM)", _line(str((r.get("times", ["12:00"]) as Array).front() if not (r.get("times", []) as Array).is_empty() else "12:00"), func(t): r.times = [t.strip_edges()]))
	var wd := HBoxContainer.new()
	var wds: Array = r.get("weekdays", [0, 1, 2, 3, 4, 5, 6])
	for d in 7:
		wd.add_child(_check(OutgameData.WEEKDAYS[d], wds.has(d), func(on):
			var a: Array = r.get("weekdays", [0, 1, 2, 3, 4, 5, 6]).duplicate()
			if on and not a.has(d):
				a.append(d)
			elif not on:
				a.erase(d)
			a.sort()
			r.weekdays = a))
	_row(grid, "요일", wd)
	_row(grid, "시작일 (비우면 처음부터)", _line(str(r.get("start_day", "")), func(t): r.start_day = t.strip_edges(), "YYYY-MM-DD"))
	var st := HFlowContainer.new()
	var cur: Array = r.get("stages", [])
	var all_ids: Array[String] = stage_ids.duplicate()
	for s in cur:
		if not all_ids.has(str(s)):
			all_ids.append(str(s))   # 목록에 없는 스테이지도 보여 줌 (검사에서 경고)
	for s in all_ids:
		st.add_child(_check(s, cur.has(s), func(on):
			var a: Array = (r.get("stages", []) as Array).duplicate()
			if on and not a.has(s):
				a.append(s)
			elif not on:
				a.erase(s)
			r.stages = a))
	_row(grid, "스테이지 (여럿이면 무작위)", st)
	_row(grid, "넘기기", _check("기지 화면에서 '넘기기' 허용 (끄면 반드시 출정)", r.get("allow_skip", false), func(on): r.allow_skip = on))
	_row(grid, "메모", _line(str(r.get("note", "")), func(t): r.note = t))
	form.add_child(_small("※ 전투가 발생하면 기지 시계가 멈추고 '전투 배치로' 막대가 뜬다. 전투에서 잃은 체력·상태 이상은 기지로 그대로 돌아온다."))
	_rebuilding = false


func _split_times(t: String) -> Array:
	var out := []
	for p in t.split(",", false):
		if p.strip_edges() != "":
			out.append(p.strip_edges())
	return out


# ================================================================ 미리보기 · 검사
func _fires(r: Dictionary, from_m: int, to_m: int) -> Array[int]:
	var out: Array[int] = []
	var m := from_m - 1
	while out.size() < 200:
		m = BattleRules.next_fire(r, m, clock, PREVIEW_DAYS + 1)
		if m < 0 or m > to_m:
			break
		out.append(m)
	return out


## 게임과 같은 순서로 실제 발생할 전투 (같은 분이면 위 규칙 하나)
func _merged(from_m: int, to_m: int) -> Array:
	var by_min := {}
	for i in rules.size():
		for m in _fires(rules[i], from_m, to_m):
			if not by_min.has(m):
				by_min[m] = i
	var ms := by_min.keys()
	ms.sort()
	return ms.map(func(m): return [m, by_min[m]])


func _refresh_preview() -> void:
	timeline.queue_redraw()
	var day0 := clock.day_index(start_minute)
	var events := _merged(start_minute + 1, (day0 + PREVIEW_DAYS) * 1440 - 1)
	var lines := PackedStringArray()
	for e in events.slice(0, 14):
		var r: Dictionary = rules[e[1]]
		lines.append("[color=#%s]■[/color] %s  %s" % [_rule_color(e[1]).to_html(false), clock.label(e[0]), r.get("name", r.id)])
	if events.is_empty():
		lines.append("[color=#ffd166]%d일 안에 발생하는 전투 없음[/color]" % PREVIEW_DAYS)
	elif events.size() > 14:
		lines.append("… 외 %d회 (%d일 합계 %d회)" % [events.size() - 14, PREVIEW_DAYS, events.size()])
	upcoming.text = "\n".join(lines)
	_run_checks()


func _draw_timeline() -> void:
	var w := timeline.size.x
	var h := timeline.size.y
	var lx := 110.0
	var rh := (h - 18) / PREVIEW_DAYS
	var font := get_theme_default_font()
	var day0 := clock.day_index(start_minute)
	timeline.draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.09, 0.11))
	for hr in range(0, 25, 3):
		var x := lx + (w - lx - 8) * hr / 24.0
		timeline.draw_line(Vector2(x, 0), Vector2(x, h - 16), Color(1, 1, 1, 0.08 if hr % 6 else 0.18))
		timeline.draw_string(font, Vector2(x - 8, h - 3), "%02d" % hr, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.8))
	for d in PREVIEW_DAYS:
		var y := d * rh
		var dd := clock.date_of_day(day0 + d)
		timeline.draw_string(font, Vector2(6, y + rh * 0.5 + 5), "%02d-%02d (%s)" % [dd.month, dd.day, OutgameData.WEEKDAYS[dd.weekday]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.87, 0.95))
		timeline.draw_line(Vector2(lx, y + rh), Vector2(w - 8, y + rh), Color(1, 1, 1, 0.06))
	# 게임 시작 이전은 어둡게
	var sx := lx + (w - lx - 8) * clock.minute_of_day(start_minute) / 1440.0
	timeline.draw_rect(Rect2(lx, 0, sx - lx, rh), Color(0, 0, 0, 0.45))
	timeline.draw_line(Vector2(sx, 0), Vector2(sx, rh), Color(0.6, 1.0, 0.7), 2.0)
	for e in _merged(start_minute + 1, (day0 + PREVIEW_DAYS) * 1440 - 1):
		var m: int = e[0]
		var d := clock.day_index(m) - day0
		var x := lx + (w - lx - 8) * clock.minute_of_day(m) / 1440.0
		var c := _rule_color(e[1])
		var y := d * rh
		var thick := 4.0 if e[1] == sel else 2.5
		timeline.draw_line(Vector2(x, y + 3), Vector2(x, y + rh - 3), c, thick)
		timeline.draw_string(font, Vector2(x + 3, y + 13), clock.time_str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)


func _run_checks() -> void:
	var lines := PackedStringArray()
	var seen := {}
	var day0 := clock.day_index(start_minute)
	for i in rules.size():
		var r: Dictionary = rules[i]
		var nm := str(r.get("name", r.get("id", "")))
		var id := str(r.get("id", ""))
		if id == "":
			lines.append("[color=#ff6b6b]%s: id 가 비어 있음[/color]" % nm)
		elif seen.has(id):
			lines.append("[color=#ff6b6b]id 중복: %s[/color]" % id)
		seen[id] = true
		var stages: Array = r.get("stages", [])
		if stages.is_empty():
			lines.append("[color=#ff6b6b]%s: 스테이지가 없음[/color]" % nm)
		for s in stages:
			if not stage_ids.is_empty() and not stage_ids.has(str(s)):
				lines.append("[color=#ff6b6b]%s: 없는 스테이지 %s[/color]" % [nm, s])
		var times: Array = [r.get("anchor", "00:00")] if str(r.get("mode", "interval")) == "interval" else r.get("times", [])
		for t in times:
			if not _valid_hm(str(t)):
				lines.append("[color=#ff6b6b]%s: 시각 형식이 틀림 '%s' (HH:MM)[/color]" % [nm, t])
		for k in ["start_day", "date"]:
			var dv := str(r.get(k, ""))
			if dv != "" and not _valid_date(dv):
				lines.append("[color=#ff6b6b]%s: 날짜 형식이 틀림 '%s' (YYYY-MM-DD)[/color]" % [nm, dv])
		if str(r.get("mode", "")) == "once" and str(r.get("date", "")) == "":
			lines.append("[color=#ff6b6b]%s: 한 번 방식인데 날짜가 없음[/color]" % nm)
		if (r.get("weekdays", [0]) as Array).is_empty():
			lines.append("[color=#ffd166]%s: 요일이 하나도 없음 → 발생 안 함[/color]" % nm)
		elif r.get("enabled", true) and _fires(r, start_minute + 1, (day0 + PREVIEW_DAYS) * 1440 - 1).is_empty():
			lines.append("[color=#ffd166]%s: %d일 안에 발생하지 않음[/color]" % [nm, PREVIEW_DAYS])
		if str(r.get("mode", "")) == "interval" and int(r.get("interval_minutes", 360)) < 120:
			lines.append("[color=#ffd166]%s: 간격이 2시간보다 짧음 (기지 활동 시간이 거의 없음)[/color]" % nm)
	check_label.text = "\n".join(lines) if not lines.is_empty() else "[color=#88ff99]문제 없음[/color]"


static func _valid_hm(s: String) -> bool:
	var p := s.strip_edges().split(":")
	return p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int() and int(p[0]) in range(24) and int(p[1]) in range(60)


static func _valid_date(s: String) -> bool:
	var p := s.strip_edges().split("-")
	return p.size() == 3 and p[0].length() == 4 and p[0].is_valid_int() and p[1].is_valid_int() and p[2].is_valid_int() \
		and int(p[1]) in range(1, 13) and int(p[2]) in range(1, 32)


# ================================================================ 저장 · 테스트
func _save() -> void:
	var err := OutgameData.write_battle_rules(rules)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	dirty = err != OK
	status.text = "저장됨: data/outgame/battle_rules.json" if err == OK else "저장 실패 (%d)" % err


## 저장 → 새 기지를 다음 전투 10분 전부터 실행 (저장 파일은 건드리지 않음)
func _play() -> void:
	_save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"base": true, "battle_soon": true}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn")


func _shortcut_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


# ================================================================ 작은 위젯
func _row(grid: GridContainer, label: String, ctl: Control) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)


func _line(t: String, cb: Callable, hint: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = t
	e.placeholder_text = hint
	e.custom_minimum_size.x = 260
	e.text_changed.connect(func(v):
		if not _rebuilding:
			cb.call(v)
			_mark())
	return e


func _check(t: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v):
		if not _rebuilding:
			cb.call(v)
			_mark())
	return c


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


func _small(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	return l


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	return l
