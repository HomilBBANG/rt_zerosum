class_name SettingsPanel
extends PanelContainer
## 설정 창 (타이틀 '설정' · 기지 F10): 배경음악 · 효과음 음량, 창 크기, 전체 화면 (+ 타이틀에서는 전투 테스트 메뉴 — 개발용).
## 바꾸면 바로 적용 + user://settings.cfg 에 저장 (Settings).

var _font: Font
var _bold: Font


static func open(parent: Node, dev_menu: bool = false) -> SettingsPanel:
	for c in parent.get_children():
		if c is SettingsPanel:   # 이미 열려 있으면 닫기 (토글)
			c.queue_free()
			return null
	var p := SettingsPanel.new()
	parent.add_child(p)
	p._build(dev_menu)
	return p


func _build(dev_menu: bool) -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	Settings.load_all()
	UiPanel.apply(self, Vector4(28, 20, 28, 22))
	mouse_filter = MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var t := _label("설정", 22, Color(1, 0.92, 0.75), _bold)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_slider_row("배경음악", Settings.bgm, func(x):
		Settings.bgm = x
		Settings.apply_audio()
		Settings.save_all()))
	v.add_child(_slider_row("효과음", Settings.sfx, func(x):
		Settings.sfx = x
		Settings.apply_audio()
		Settings.save_all()))
	# 창 크기
	var wr := _row("창 크기")
	var ob := OptionButton.new()
	ob.add_theme_font_override("font", _font)
	ob.add_theme_font_size_override("font_size", 15)
	ob.custom_minimum_size.x = 210
	ob.focus_mode = FOCUS_NONE
	var win := get_window()
	var cur: Vector2i = Settings.win_size if Settings.win_size.x >= 640 else win.size   # 고른 크기 (없으면 지금 창에 가장 가까운 것)
	var best := 0
	for i in Settings.WINDOW_SIZES.size():
		var s: Vector2i = Settings.WINDOW_SIZES[i]
		ob.add_item("%d × %d" % [s.x, s.y])
		if absi(s.x - cur.x) < absi(Settings.WINDOW_SIZES[best].x - cur.x):
			best = i
	ob.select(best)
	ob.item_selected.connect(func(i):
		Game.set_window_size(Settings.WINDOW_SIZES[i]))
	wr.add_child(ob)
	v.add_child(wr)
	# 전체 화면
	var fr := _row("전체 화면")
	var cb := CheckButton.new()
	cb.button_pressed = win.mode == Window.MODE_FULLSCREEN
	cb.focus_mode = FOCUS_NONE
	cb.text = "F11"
	cb.add_theme_font_override("font", _font)
	cb.add_theme_font_size_override("font_size", 14)
	cb.toggled.connect(func(on): Game.set_fullscreen(on))
	fr.add_child(cb)
	v.add_child(fr)
	if dev_menu:
		var test := _choice("전투 테스트 메뉴 (개발용)")
		test.pressed.connect(func(): Game.go_menu_test())
		v.add_child(test)
	var close := _choice("닫기")
	close.pressed.connect(queue_free)
	v.add_child(close)
	reset_size()
	position = Vector2(640, 360) - get_combined_minimum_size() * 0.5


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


func _row(name: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _label(name, 16, Color(0.92, 0.91, 0.86), _font)
	l.custom_minimum_size.x = 90
	h.add_child(l)
	return h


func _slider_row(name: String, value: float, on_change: Callable) -> HBoxContainer:
	var h := _row(name)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = roundf(value * 100.0)
	s.custom_minimum_size = Vector2(210, 24)
	s.focus_mode = FOCUS_NONE
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	var pct := _label("%d%%" % int(s.value), 15, Color(1, 0.92, 0.75), _bold)
	pct.custom_minimum_size.x = 48
	s.value_changed.connect(func(x):
		pct.text = "%d%%" % int(x)
		on_change.call(x / 100.0))
	h.add_child(s)
	h.add_child(pct)
	return h


func _label(text: String, size: int, col: Color, f: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _choice(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(340, 42)
	b.focus_mode = FOCUS_NONE
	UiButton.apply(b, "choice", "choice_on")
	return b
