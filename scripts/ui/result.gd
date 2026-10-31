extends Control
## 전투 결과 화면 v2 (레퍼런스 art_src/ui/result/ref_victory.webp, 조각 assets/ui/result/):
## 배경 · 가운데 큰 판(머리 탭 "전투 승리 / 패배") · 대원 줄(초상화 · 이름 · Lv · +EXP 막대 · 전투 끝에 남은 부정적 상태 이상 꼬리표 · 체력)
## · 획득 전리품 칸 · [상세 기록] [계속] · 왼쪽 MVP(준 피해가 가장 큰 대원 — 전신 그림 + 배지), 오른쪽 최저 성과(가장 적은 대원).
## 상세 기록 = 전투 로그 + 다시 전투 · 전투 배치 (예전 결과 화면 버튼).

const R := "res://assets/ui/result/"
const GOLD := Color(1.0, 0.82, 0.25)
const CREAM := Color(0.95, 0.93, 0.86)
const DIM := Color(0.7, 0.72, 0.68)
const RED := Color(0.95, 0.3, 0.28)
const PANEL_K := 0.9   # 큰 판 그림 배율 — 머리 탭 안쪽(그림 53px)이 제목 글자(40)보다 크게

var _font: Font
var _bold: Font
var _manifest := {}
var _detail: Control


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var mf := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	if mf != null:
		_manifest = JSON.parse_string(mf.get_as_text())
	var r := Game.last_result
	var win: bool = r.get("winner", "enemy") == "ally"
	var allies: Array = r.get("allies", [])
	# 배경
	var bg := TextureRect.new()
	bg.texture = load(R + "bg_result.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	# MVP · 최저 성과 (준 피해 비율 · 처치 — 아군 둘 이상일 때 최저 성과)
	var total := 0
	for a in allies:
		total += int(a.get("dmg", 0))
	var ranked := allies.duplicate()
	ranked.sort_custom(func(x, y): return int(x.get("dmg", 0)) * 100 + int(x.get("kills", 0)) > int(y.get("dmg", 0)) * 100 + int(y.get("kills", 0)))
	var mvp: Dictionary = ranked[0] if not ranked.is_empty() else {}
	var worst: Dictionary = ranked[-1] if ranked.size() >= 2 else {}
	if not mvp.is_empty():
		_side_art(str(mvp.id), "", Rect2(0, 60, 330, 660))
	if not worst.is_empty():
		_side_art(str(worst.id), "annoying", Rect2(990, 90, 290, 630))
	# 가운데 판
	var panel := Control.new()
	panel.position = Vector2(287, 6)
	panel.size = Vector2(708, 634)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.draw.connect(func():
		UiNine.draw(panel, R + "panel_main.png", Vector4(140, 96, 140, 44), Rect2(Vector2.ZERO, panel.size), PANEL_K)
		_title(panel, "전투 승리" if win else "전투 패배", win))
	add_child(panel)
	_rows(panel, allies)
	_loot(panel)
	# MVP · 최저 성과 배지
	if not mvp.is_empty():
		_badge("badge_mvp.png", Rect2(18, 432, 250, 156), 0.578, 0.844, mvp, total, GOLD)
	if not worst.is_empty():
		_badge("badge_worst.png", Rect2(1068, 462, 196, 125), 0.595, 0.849, worst, total, Color(0.9, 0.9, 0.88))
	# 버튼
	var detail := _plate_button("상세 기록", R + "plate_row.png", Vector4(36, 36, 36, 36), 0.5, Rect2(348, 648, 278, 56), CREAM)
	detail.pressed.connect(_open_detail)
	var cont := _plate_button("기지로 복귀" if Game.campaign else "계속", R + "bar_gold.png", Vector4(24, 24, 24, 24), 0.9, Rect2(650, 648, 280, 56), Color(0.12, 0.1, 0.05))
	cont.pressed.connect(func(): Game.go_menu())
	if str(Game.cli.get("result_ui", "")) == "detail":   # 확인용: 상세 기록 바로 열기
		_open_detail()
	Game.maybe_cli_capture()


## 머리 탭 제목 + 양옆 줄무늬
func _title(c: Control, text: String, win: bool) -> void:
	var col := GOLD if win else Color(0.95, 0.45, 0.4)
	var fs := 40
	var w := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cx := c.size.x * 0.5
	var y := (16.0 + 69.0) * 0.5 * PANEL_K   # 머리 탭 안쪽 가운데 (그림 16~69px)
	c.draw_string_outline(_bold, Vector2(cx - w * 0.5, y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.05, 0.05, 0.03))
	c.draw_string(_bold, Vector2(cx - w * 0.5, y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	for side in [-1, 1]:
		for i in 3:
			var x0: float = cx + side * (w * 0.5 + 18 + i * 9.0)
			var yy := y - 9 + i * 7.0
			var p := PackedVector2Array([Vector2(x0, yy), Vector2(x0 + side * 30, yy), Vector2(x0 + side * 26, yy + 4), Vector2(x0 - side * 4, yy + 4)])
			c.draw_colored_polygon(p, col)


## 대원 줄: 초상화 · 이름 · Lv | +EXP · 막대 · 경험치 | 전투 끝에 남은 부정적 상태 이상 꼬리표 · 체력
func _rows(panel: Control, allies: Array) -> void:
	var n := maxi(1, allies.size())
	var top := 92.0
	var area := 374.0
	var gap := 6.0
	var h := minf(92.0, (area - gap * (n - 1)) / n)
	for i in allies.size():
		var a: Dictionary = allies[i]
		var row := Control.new()
		row.position = Vector2(30, top + i * (h + gap))
		row.size = Vector2(648, h)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var info := _ally_info(a)
		row.draw.connect(_draw_row.bind(row, info))


## 줄에 쓸 값 모음
func _ally_info(a: Dictionary) -> Dictionary:
	var id := str(a.get("id", ""))
	var u := Game.find_ally(id)
	var name: String = (u.display_name if u.display_name != "" else u.name) if u != null else id
	var lv: int = u.level if u != null else 1
	var xp := -1
	var need := 0
	var gain := 0
	var ups := 0
	if Game.campaign and Game.base != null:
		for g in Game.base.growth:
			if str(g.id) == id:
				gain = int(g.xp)
				lv = int(g.level)
				ups = int(g.ups)
				name = str(g.name)
		xp = Game.base.char_xp(id)
		need = Game.base.xp_need(id)
	var max_hp := int(a.get("max_hp", u.max_hp if u != null else 1))
	var hp := int(a.get("hp", max_hp))
	var alive: bool = a.get("alive", true)
	# 전투가 끝났을 때 남아 있던 부정적 상태 이상 전부 (같은 것이 여러 번이면 한 번만) + 쓰러짐
	var bad: Array = []
	if not alive:
		bad.append("쓰러짐")
	for sid in a.get("statuses", []):
		var d := StatusCatalog.get_def(str(sid))
		var nm := str(d.get("name", sid))
		if not d.get("positive", false) and not bad.has(nm):
			bad.append(nm)
	var hp_line := "체력 %d/%d" % [hp, max_hp] if alive else "체력 0/%d" % max_hp
	var portrait: Texture2D = UnitArt.portrait(u.sprite_id, _manifest) if u != null else null
	return {"name": name, "lv": lv, "ups": ups, "xp": xp, "need": need, "gain": gain, "bad": bad, "hp_line": hp_line, "portrait": portrait}


func _draw_row(row: Control, d: Dictionary) -> void:
	var h := row.size.y
	UiNine.draw(row, R + "plate_row.png", Vector4(30, 30, 30, 30), Rect2(Vector2.ZERO, row.size), 0.5)
	# 초상화 + 테두리
	var ps := h - 12.0
	var pr := Rect2(8, 6, ps, ps)
	if d.portrait != null:
		row.draw_texture_rect(d.portrait, pr.grow(-4), false)
	UiNine.draw(row, R + "frame_portrait.png", Vector4(44, 44, 44, 44), pr, 0.3)
	# 이름 · Lv
	var fs := 19 if h >= 80 else 16
	row.draw_string(_bold, Vector2(ps + 22, h * 0.42), str(d.name), HORIZONTAL_ALIGNMENT_LEFT, 110, fs, CREAM)
	row.draw_string(_bold, Vector2(ps + 22, h * 0.42 + fs + 6), "Lv.%d" % int(d.lv), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)
	if int(d.ups) > 0:   # 이번 전투로 레벨 업
		var lw := _bold.get_string_size("Lv.%d" % int(d.lv), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		row.draw_string(_bold, Vector2(ps + 26 + lw, h * 0.42 + fs + 5), "▲UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)
	# 구분선
	for lx in [222.0, 452.0]:
		row.draw_line(Vector2(lx, 10), Vector2(lx, h - 10), Color(0.35, 0.38, 0.3, 0.8), 1.5)
	# 경험치
	var ex := 236.0
	if int(d.xp) >= 0:
		row.draw_string(_bold, Vector2(ex, h * 0.34), "+%d" % int(d.gain), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
		var gw := _bold.get_string_size("+%d" % int(d.gain), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		row.draw_string(_bold, Vector2(ex + gw + 5, h * 0.34), "EXP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
		var br := Rect2(ex, h * 0.42, 202, 14)
		UiNine.draw(row, R + "bar_track.png", Vector4(22, 22, 22, 22), br.grow(2), 0.32)
		var k := clampf(float(d.xp) / maxf(1.0, float(d.need)), 0.0, 1.0)
		if k > 0.0:
			UiNine.draw(row, R + "bar_gold.png", Vector4(16, 16, 16, 16), Rect2(br.position + Vector2(2, 2), Vector2(maxf(12.0, (br.size.x - 4) * k), br.size.y - 4)), 0.32)
		row.draw_string(_font, Vector2(ex, h * 0.42 + 32), "%d / %d" % [int(d.xp), int(d.need)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	else:
		row.draw_string(_font, Vector2(ex, h * 0.55), "경험치 없음 (전투 테스트)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	# 상태 이상: 전투가 끝났을 때 남은 부정적 상태 이상을 꼬리표로 (없으면 "이상 없음") + 체력
	var bad: Array = d.bad
	var x := 468.0
	var y := 10.0
	var tf := 13
	if bad.is_empty():
		_chip(row, Rect2(x, y, _bold.get_string_size("이상 없음", HORIZONTAL_ALIGNMENT_LEFT, -1, tf).x + 18, 22), "이상 없음", Color(0.75, 0.78, 0.72), CREAM, tf)
	else:
		for nm in bad:
			var w := _bold.get_string_size(str(nm), HORIZONTAL_ALIGNMENT_LEFT, -1, tf).x + 18
			if x + w > 640.0 and x > 468.0:   # 줄 바꿈
				x = 468.0
				y += 26.0
			if y + 22 > h - 18:   # 줄 높이를 넘으면 "외 N"
				break
			_chip(row, Rect2(x, y, w, 22), str(nm), RED, RED, tf)
			x += w + 5
	row.draw_string(_font, Vector2(468, h - 9), str(d.hp_line), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)


## 상태 꼬리표 (어두운 바탕 + 색 테두리)
func _chip(c: Control, r: Rect2, text: String, border: Color, col: Color, fs: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.9)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	c.draw_style_box(sb, r)
	c.draw_string(_bold, r.position + Vector2(9, 16), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, fs, col)


## 획득 전리품: 왼쪽 글자 + 칸(판 · 이름 · ×개수)
func _loot(panel: Control) -> void:
	var items: Array = Game.base.last_loot if Game.campaign and Game.base != null else []
	var box := Control.new()
	box.position = Vector2(30, 474)
	box.size = Vector2(648, 120)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(box)
	box.draw.connect(func():
		UiNine.draw(box, R + "plate_row.png", Vector4(30, 30, 30, 30), Rect2(Vector2.ZERO, box.size), 0.5)
		box.draw_string(_bold, Vector2(22, 68), "획득 전리품", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)
		if items.is_empty():
			box.draw_string(_font, Vector2(170, 68), "없음", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM)
			return
		var sw := 106.0
		for i in mini(items.size(), 4):
			var e: Dictionary = items[i]
			var r := Rect2(160 + i * (sw + 8), 10, sw, 100)
			UiNine.draw(box, R + "plate_slot.png", Vector4(40, 40, 40, 40), r, 0.36)
			var nm := str(e.name)
			var nw := _bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			box.draw_string(_bold, Vector2(r.get_center().x - minf(nw, sw - 14) * 0.5, r.position.y + 50), nm, HORIZONTAL_ALIGNMENT_LEFT, sw - 14, 15, CREAM)
			var cnt := "×%d" % int(e.count)
			var cw := _bold.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			box.draw_string(_bold, Vector2(r.end.x - cw - 12, r.end.y - 14), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1)))


## MVP · 최저 성과 배지: 그림(글자 박힘) + 아래 칸에 이름 · "피해량 N% · 처치 N"
func _badge(file: String, rect: Rect2, name_y: float, stat_y: float, a: Dictionary, total: int, name_col: Color) -> void:
	var tr := TextureRect.new()
	tr.texture = load(R + file)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = rect.position
	tr.size = rect.size
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(tr)
	var u := Game.find_ally(str(a.get("id", "")))
	var nm: String = (u.display_name if u.display_name != "" else u.name) if u != null else str(a.get("id", ""))
	if Game.campaign and Game.base != null:
		for g in Game.base.growth:
			if str(g.id) == str(a.get("id", "")):
				nm = str(g.name)
	var pct := roundi(100.0 * float(a.get("dmg", 0)) / maxf(1.0, total))
	var l1 := _label(nm, 24, name_col, _bold)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.position = Vector2(rect.position.x, rect.position.y + rect.size.y * name_y - 16)
	l1.size = Vector2(rect.size.x, 32)
	add_child(l1)
	var l2 := _label("피해량 %d%% · 처치 %d" % [pct, int(a.get("kills", 0))], 13, CREAM, _bold)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.position = Vector2(rect.position.x, rect.position.y + rect.size.y * stat_y - 10)
	l2.size = Vector2(rect.size.x, 20)
	add_child(l2)


## 옆 전신 그림 (MVP = 기본 그림, 최저 성과 = 언짢은 포즈 — 없으면 기본 그림을 어둡게)
func _side_art(id: String, pose: String, area: Rect2) -> void:
	var u := Game.find_ally(id)
	if u == null:
		return
	var path := CharacterSprite2D.pose_path(u.sprite_id, pose) if pose != "" else ""
	var dim := false
	if path == "":
		path = CharacterSprite2D.dir_of(u.sprite_id).path_join("base.png")
		dim = pose != ""
	var tex := CharacterSprite2D._tex(path)
	if tex == null:
		return
	# 키에 맞춰 같은 배율: 그림 전체 높이(768px 중 몸 759px) = 키, 175cm → 610px (좁은 칸이라도 줄이지 않음 — 옆으로 조금 넘쳐도 됨)
	var k := (610.0 * u.height_cm / 175.0) / float(tex.get_height())
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = Vector2(tex.get_width(), tex.get_height()) * k
	t.position = Vector2(area.get_center().x - t.size.x * 0.5, area.end.y - t.size.y)
	t.mouse_filter = MOUSE_FILTER_IGNORE
	if dim:
		t.modulate = Color(0.7, 0.7, 0.75)
	add_child(t)


func _plate_button(text: String, tex_path: String, m: Vector4, k: float, rect: Rect2, col: Color) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = FOCUS_NONE
	b.text = text
	b.add_theme_font_override("font", _bold)
	b.add_theme_font_size_override("font_size", 22)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, col)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	UiNine.behind(b, tex_path, m, k, func() -> Color:
		match b.get_draw_mode():
			BaseButton.DRAW_HOVER: return Color(1.18, 1.15, 1.08)
			BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED: return Color(0.82, 0.82, 0.8)
		return Color.WHITE)
	add_child(b)
	return b


## 상세 기록: 전투 로그 + 다시 전투 · 전투 배치 · 닫기
func _open_detail() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
		return
	var r := Game.last_result
	var p := PanelContainer.new()
	UiPanel.apply(p, Vector4(24, 18, 24, 20))
	p.position = Vector2(240, 70)
	p.custom_minimum_size = Vector2(800, 560)
	add_child(p)
	_detail = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("상세 기록 — 라운드 %d 에 종료 · 재시작 %d회" % [int(r.get("rounds", 0)), Game.restart_count], 20, GOLD, _bold))
	var log_box := RichTextLabel.new()
	log_box.custom_minimum_size = Vector2(752, 430)
	log_box.add_theme_font_override("normal_font", _font)
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.scroll_following = true
	for line in r.get("log", PackedStringArray()):
		log_box.append_text(str(line) + "\n")
	v.add_child(log_box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	for spec in [["다시 전투", func(): Game.restart_count += 1; Game.start_battle()], ["전투 배치" if Game.campaign else "편성", func(): Game.go_formation()],
			["닫기", func(): p.queue_free()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(240, 42)
		UiButton.apply(b, "choice", "choice_on")
		b.pressed.connect(spec[1])
		h.add_child(b)


func _label(text: String, size: int, color: Color, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f if f != null else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l
