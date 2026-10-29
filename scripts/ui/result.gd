extends Control
## 결과 화면: 승패, 라운드, 로그 요약, 재시작(같은 설정) / 편성 / 메뉴. 연속 3회 재시작 가능 검증용 카운터 표시.

var _font: Font


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	var r := Game.last_result
	var win: bool = r.get("winner", "enemy") == "ally"
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.16, 0.18) if win else Color(0.2, 0.03, 0.08)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var wedge := Polygon2D.new()
	wedge.polygon = PackedVector2Array([Vector2(900, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(640, 720)])
	wedge.color = Color(1.0, 0.12, 0.47) if win else Color(0.22, 1.0, 0.73)
	add_child(wedge)
	if not win:
		_show_pose_art(r, "annoying")
	var box := VBoxContainer.new()
	box.position = Vector2(80, 80)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	box.add_child(_label("승리" if win else "패배", 72, Color(1, 0.95, 0.6)))
	box.add_child(_label("라운드 %d 에 종료 · 재시작 횟수 %d" % [r.get("rounds", 0), Game.restart_count], 18))
	var log_h := 330
	if Game.campaign and Game.base != null and not Game.base.growth.is_empty():   # 출전 대원 경험치·레벨 업
		var g := PackedStringArray()
		for e in Game.base.growth:
			g.append("%s +%d 경험치%s" % [e.name, int(e.xp), "  ▲ Lv%d (스킬 포인트 +%d)" % [int(e.level), int(e.ups)] if int(e.ups) > 0 else ""])
		box.add_child(_label("  ·  ".join(g), 16, Color(0.9, 0.75, 1.0)))
		log_h = 290
	var log_box := RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(760, log_h)
	log_box.add_theme_font_override("normal_font", _font)
	log_box.add_theme_font_size_override("normal_font_size", 13)
	var lines: PackedStringArray = r.get("log", PackedStringArray())
	var start := maxi(0, lines.size() - 40)
	for i in range(start, lines.size()):
		log_box.append_text(lines[i] + "\n")
	box.add_child(log_box)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	box.add_child(btns)
	var again := _big_button("다시 전투 (같은 설정)", Color(1.0, 0.5, 0.3))
	again.pressed.connect(func(): Game.restart_count += 1; Game.start_battle())
	btns.add_child(again)
	var form := _big_button("전투 배치" if Game.campaign else "편성", Color(0.3, 0.8, 0.7))
	form.pressed.connect(func(): Game.go_formation())
	btns.add_child(form)
	var menu := _big_button("기지로 복귀" if Game.campaign else "메뉴", Color(0.6, 0.6, 0.6))
	menu.pressed.connect(func(): Game.go_menu())
	btns.add_child(menu)
	Game.maybe_cli_capture()


## 패배: 출전 대원 중 그 포즈 그림(annoying = 언짢음)이 있는 대원을 오른쪽에 (SkillPoseData)
func _show_pose_art(r: Dictionary, pose: String) -> void:
	var paths: Array[String] = []
	for a in r.get("allies", []):
		var u := Game.find_ally(str(a.get("id", "")))
		var p := CharacterSprite2D.pose_path(u.sprite_id, pose) if u != null else ""
		if p != "":
			paths.append(p)
	var h := 600.0
	var x := 1250.0
	for i in mini(paths.size(), 3):
		var tex := CharacterSprite2D._tex(paths[i])
		if tex == null:
			continue
		var k := h / float(tex.get_height()) * (1.0 if i == 0 else 0.86)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(tex.get_width(), tex.get_height()) * k
		x -= tr.size.x * (1.0 if i == 0 else 0.7)
		tr.position = Vector2(x, 720.0 - tr.size.y - 10.0)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i > 0:
			tr.modulate = Color(0.75, 0.75, 0.8)
			tr.show_behind_parent = false
		add_child(tr)
		if i > 0:
			move_child(tr, 2)   # 뒤 대원은 앞 대원 뒤로 (배경·쐐기 다음)


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
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(170, 50)
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
