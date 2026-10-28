extends Control
## 타이틀: 게임 시작(새 기지) / 이어하기(저장) / 전투 테스트 메뉴(개발용) / 종료.
## 게임 루프 [임시]: 타이틀 → 기지 → 전투 출전 → 전투 배치 → 전투 → 결과 → 기지.

var _font: Font
var _bold: Font
var _confirm: Control


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	# 원색 조명 색면 두 개 + 경계 띠 (전투 메뉴와 같은 스타일 선언)
	var a := Polygon2D.new()
	a.polygon = PackedVector2Array([Vector2(0, 0), Vector2(700, 0), Vector2(420, 720), Vector2(0, 720)])
	a.color = Color(0.03, 0.18, 0.40)
	add_child(a)
	var b := Polygon2D.new()
	b.polygon = PackedVector2Array([Vector2(700, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(420, 720)])
	b.color = Color(1.0, 0.52, 0.06)
	add_child(b)
	var s := Polygon2D.new()
	s.polygon = PackedVector2Array([Vector2(700, 0), Vector2(744, 0), Vector2(464, 720), Vector2(420, 720)])
	s.color = Color(0.40, 0.82, 1.0)
	add_child(s)
	# 기지 단면 실루엣
	var sil := Polygon2D.new()
	sil.polygon = PackedVector2Array([Vector2(760, 470), Vector2(1220, 470), Vector2(1220, 720), Vector2(760, 720)])
	sil.color = Color(0.10, 0.06, 0.06)
	add_child(sil)
	for i in 3:
		for j in 4:
			var w := ColorRect.new()
			w.color = [Color(1, 0.12, 0.47), Color(0.22, 1, 0.73), Color(0.18, 0.95, 1), Color(0, 0, 0)][(i * 4 + j) % 4] if (i + j) % 3 != 2 else Color(0, 0, 0)
			w.position = Vector2(780 + j * 108, 486 + i * 76)
			w.size = Vector2(96, 62)
			add_child(w)

	var box := VBoxContainer.new()
	box.position = Vector2(90, 110)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(_label("RT ZEROSUM", 64, Color(1, 1, 1)))
	box.add_child(_label("2048-04-07 — 기지 총괄 책임자", 20, Color(0.9, 0.95, 1)))
	var sp := Control.new()
	sp.custom_minimum_size.y = 24
	box.add_child(sp)
	var start := _button("게임 시작", Color(1.0, 0.55, 0.25))
	start.pressed.connect(_on_new)
	box.add_child(start)
	var cont := _button("이어하기", Color(0.35, 0.85, 0.7))
	cont.disabled = not Game.has_save()
	cont.pressed.connect(func():
		if Game.load_campaign():
			Game.go_base())
	box.add_child(cont)
	var test := _button("전투 테스트 메뉴 (개발용)", Color(0.6, 0.6, 0.7))
	test.pressed.connect(func(): Game.go_menu_test())
	box.add_child(test)
	var quit := _button("종료", Color(0.5, 0.5, 0.55))
	quit.pressed.connect(func(): Game.quit_game())
	box.add_child(quit)
	if Game.outgame_data == null:
		start.disabled = true
		cont.disabled = true
		box.add_child(_label("data/outgame.xlsx 를 읽지 못해 기지를 열 수 없습니다", 15, Color(1, 0.5, 0.4)))
	box.add_child(_label("기지 데이터: data/outgame.xlsx · 대원 일정: Godot 에디터 '일정' 탭 · F11 전체 화면", 13, Color(0.85, 0.9, 0.95)))
	if Game.cli.get("scene", "title") == "title":
		Game.maybe_cli_capture()


func _on_new() -> void:
	if not Game.has_save():
		_start_new()
		return
	_confirm = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.97)
	sb.border_color = Color(1, 0.6, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_confirm.add_theme_stylebox_override("panel", sb)
	_confirm.position = Vector2(380, 280)
	add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_confirm.add_child(v)
	v.add_child(_label("저장된 기지가 있습니다. 새로 시작하면 덮어씁니다.", 18, Color(1, 0.95, 0.8)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var yes := _button("새로 시작", Color(1.0, 0.55, 0.25))
	yes.custom_minimum_size = Vector2(200, 48)
	yes.pressed.connect(_start_new)
	h.add_child(yes)
	var no := _button("취소", Color(0.5, 0.5, 0.55))
	no.custom_minimum_size = Vector2(200, 48)
	no.pressed.connect(func(): _confirm.queue_free())
	h.add_child(no)


func _start_new() -> void:
	if Game.start_base_session(true):
		Game.go_base()


func _label(text: String, size: int, color: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _bold if size >= 20 else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(360, 56)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.55)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate()
	h.bg_color = color.darkened(0.2)
	b.add_theme_stylebox_override("hover", h)
	var d := sb.duplicate()
	d.bg_color = Color(0.1, 0.1, 0.12)
	d.border_color = Color(0.3, 0.3, 0.32)
	b.add_theme_stylebox_override("disabled", d)
	return b
