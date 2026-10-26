extends Control
## 메인 메뉴: 2D/3D 모드, 조명 프리셋, 선공 설정, 시드 선택 후 편성 또는 바로 전투.

var _font: Font
var preset_opt: OptionButton
var ambush_opt: OptionButton
var seed_edit: LineEdit


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	# 배경: 두 색 공간 분할 (스타일 선언)
	var left := Polygon2D.new()
	left.polygon = PackedVector2Array([Vector2(0, 0), Vector2(760, 0), Vector2(520, 720), Vector2(0, 720)])
	left.color = Color(0.05, 0.16, 0.18)
	add_child(left)
	var right := Polygon2D.new()
	right.polygon = PackedVector2Array([Vector2(760, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(520, 720)])
	right.color = Color(1.0, 0.12, 0.47)
	add_child(right)
	var strip := Polygon2D.new()
	strip.polygon = PackedVector2Array([Vector2(760, 0), Vector2(800, 0), Vector2(560, 720), Vector2(520, 720)])
	strip.color = Color(0.22, 1.0, 0.73)
	add_child(strip)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	box.position = Vector2(90, 80)
	box.custom_minimum_size = Vector2(520, 480)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(_label("RT ZEROSUM", 54, Color(1, 1, 1)))
	box.add_child(_label("전투 플레이어블 프로토타입 v1.0 — 횡스크롤 턴제 6인 AP 전투", 17, Color(0.85, 0.95, 0.95)))
	var sp := Control.new()
	sp.custom_minimum_size.y = 10
	box.add_child(sp)

	# 스테이지 (엑셀 스테이지 시트 + 스테이지 에디터 배치)
	if Game.data != null and not Game.data.stage_order.is_empty():
		var st_row := HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 10)
		box.add_child(st_row)
		st_row.add_child(_label("스테이지", 16))
		var st_opt := OptionButton.new()
		st_opt.add_theme_font_override("font", _font)
		for id in Game.data.stage_order:
			st_opt.add_item("%s  (%s)" % [Game.data.stages[id].name, id])
			if id == Game.stage_id:
				st_opt.select(st_opt.item_count - 1)
		st_opt.item_selected.connect(func(i):
			Game.set_stage(Game.data.stage_order[i])
			preset_opt.select(LightingPresets.ORDER.find(Game.preset))
			ambush_opt.select(["none", "ally", "enemy"].find(Game.ambush))
			seed_edit.text = str(Game.seed_value))
		st_row.add_child(st_opt)

	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 10)
	box.add_child(opt_row)
	opt_row.add_child(_label("조명 프리셋", 16))
	preset_opt = OptionButton.new()
	preset_opt.add_theme_font_override("font", _font)
	for id in LightingPresets.ORDER:
		preset_opt.add_item(LightingPresets.get_preset(id).name)
	preset_opt.select(LightingPresets.ORDER.find(Game.preset))
	preset_opt.item_selected.connect(func(i): Game.preset = LightingPresets.ORDER[i])
	opt_row.add_child(preset_opt)

	var amb_row := HBoxContainer.new()
	amb_row.add_theme_constant_override("separation", 10)
	box.add_child(amb_row)
	amb_row.add_child(_label("선공 (디버그)", 16))
	ambush_opt = OptionButton.new()
	ambush_opt.add_theme_font_override("font", _font)
	ambush_opt.add_item("일반 전투 — 동전")
	ambush_opt.add_item("아군 기습")
	ambush_opt.add_item("적 매복")
	ambush_opt.select(["none", "ally", "enemy"].find(Game.ambush))
	ambush_opt.item_selected.connect(func(i): Game.ambush = ["none", "ally", "enemy"][i])
	amb_row.add_child(ambush_opt)
	amb_row.add_child(_label("시드", 16))
	seed_edit = LineEdit.new()
	seed_edit.text = str(Game.seed_value)
	seed_edit.custom_minimum_size.x = 100
	seed_edit.add_theme_font_override("font", _font)
	seed_edit.text_changed.connect(func(t): if t.is_valid_int(): Game.seed_value = int(t))
	amb_row.add_child(seed_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	box.add_child(btn_row)
	var f := _big_button("편성 화면으로", Color(0.3, 0.8, 0.7))
	f.pressed.connect(func(): Game.go_formation())
	btn_row.add_child(f)
	var s := _big_button("바로 전투 시작", Color(1.0, 0.5, 0.3))
	s.pressed.connect(func(): Game.restart_count = 0; Game.start_battle())
	btn_row.add_child(s)
	var bb := _big_button("리그 벤치", Color(0.9, 0.8, 0.3))
	bb.pressed.connect(func(): get_tree().change_scene_to_file(Game.SCENE_BENCH))
	btn_row.add_child(bb)
	box.add_child(_label("밸런스: data/balance.xlsx (저장하면 즉시 반영) · AI·스테이지 에디터: Godot 에디터 상단 탭 · 전투 중: 1~4 조명 프리셋 전환 · F1 디버그 패널 · R 재시작 · Space 턴 종료", 13, Color(0.8, 0.9, 0.9)))
	if Game.cli.get("scene", "menu") == "menu":
		Game.maybe_cli_capture()


func _label(text: String, size: int, color: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load("res://assets/fonts/Pretendard-Bold.ttf") if size >= 20 else _font)   # 큰 글자는 Bold
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(220, 54)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.5)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate()
	h.bg_color = color.darkened(0.2)
	b.add_theme_stylebox_override("hover", h)
	return b
