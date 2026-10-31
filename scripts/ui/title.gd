extends Control
## 타이틀: 이어하기(저장) / 새 게임(새 기지) / 설정(전체 화면 · 전투 테스트 메뉴 — 개발용) / 종료.
## 게임 루프 [임시]: 타이틀 → 기지 → 전투 출전 → 전투 배치 → 전투 → 결과 → 기지.

var _font: Font
var _bold: Font
var _confirm: Control


## 타이틀 v2 (사용자 제공 그림 art_src/ui/title/ → assets/ui/title/, 레퍼런스 art_src/ui/title/ref_title.webp):
## 배경 한 장 + 위 로고 + 아래 띠(9칸 늘리기) 위에 버튼 4개(이어하기 · 새 게임 · 설정 · 종료 — 글자 · 아이콘이 그려진 그림).
const T := "res://assets/ui/title/"
const BAR_RECT := Rect2(0, 595, 1280, 108)          # 아래 띠 (레퍼런스 화면 위치)
const BTN_Y := 619.0
const BTN_H := 62.0
const BTN_SLOTS := [Vector2(84, 358), Vector2(371, 635), Vector2(647, 911), Vector2(922, 1198)]   # 버튼 칸 가로 범위


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var bg := TextureRect.new()
	bg.texture = load(T + "bg_title.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	# 로고 "ZEROSUM" (사용자 제공, 원본 art_src/ui/title/logo_zerosum.webp): 위 가운데 (레퍼런스처럼 살짝 오른쪽)
	var logo := TextureRect.new()
	logo.texture = load(T + "logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(620, 144)
	logo.position = Vector2(654 - 310, 52)
	logo.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(logo)
	# 아래 띠
	var bar := Control.new()
	bar.position = BAR_RECT.position
	bar.size = BAR_RECT.size
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.draw.connect(func():
		var k := BAR_RECT.size.y / 212.0
		UiNine.draw(bar, T + "title_bar.png", Vector4(300, 100, 300, 100), Rect2(Vector2.ZERO, bar.size), k))
	add_child(bar)
	var has_data := Game.outgame_data != null
	var cont := _art_button("btn_continue.png", 0, "이어하기")
	cont.disabled = not (has_data and Game.has_save())
	cont.pressed.connect(_on_continue)
	var start := _art_button("btn_new.png", 1, "새 게임")
	start.disabled = not has_data
	start.pressed.connect(_on_new)
	var settings := _art_button("btn_settings.png", 2, "설정")
	settings.pressed.connect(_open_settings)
	var quit := _art_button("btn_quit.png", 3, "종료")
	quit.pressed.connect(func(): Game.quit_game())
	if not has_data:
		var err := _label("data/outgame.xlsx 를 읽지 못해 기지를 열 수 없습니다", 15, Color(1, 0.5, 0.4))
		err.position = Vector2(84, BAR_RECT.position.y - 30)
		add_child(err)
	if Game.cli.get("scene", "title") == "title":
		match str(Game.cli.get("title_ui", "")):
			"settings": _open_settings()
			"slots_load": _slot_window("load")
			"slots_new": _slot_window("new")
		Game.maybe_cli_capture()


## 그림 버튼 (글자 · 아이콘이 그려진 그림): 칸 i 가운데에 높이 맞춤. 마우스 올림 = 밝게 + 살짝 커짐, 누름 = 어둡게, 못 누름 = 흐리게
func _art_button(file: String, i: int, tip: String) -> TextureButton:
	var tex: Texture2D = load(T + file)
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var slot: Vector2 = BTN_SLOTS[i]
	var w := minf(slot.y - slot.x, BTN_H * tex.get_width() / float(tex.get_height()))
	b.size = Vector2(w, BTN_H)
	b.position = Vector2((slot.x + slot.y) * 0.5 - w * 0.5, BTN_Y)
	b.pivot_offset = b.size * 0.5
	b.tooltip_text = tip
	b.focus_mode = FOCUS_NONE
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var look := func():
		if b.disabled:
			b.modulate = Color(0.5, 0.5, 0.5, 0.85)
			b.scale = Vector2.ONE
		elif b.is_pressed():
			b.modulate = Color(0.85, 0.85, 0.8)
		elif b.is_hovered():
			b.modulate = Color(1.25, 1.18, 0.95)   # 레퍼런스의 선택된 버튼처럼 금빛으로 밝게
			b.scale = Vector2(1.03, 1.03)
		else:
			b.modulate = Color.WHITE
			b.scale = Vector2.ONE
	for sig in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
		b.connect(sig, look)
	add_child(b)
	look.call_deferred()
	return b


## 설정 = 공용 설정 창 (음량 · 창 크기 · 전체 화면) + 전투 테스트 메뉴(개발용)
func _open_settings() -> void:
	SettingsPanel.open(self, true)


## 이어하기: 저장 칸이 하나면 바로 그 칸, 여럿이면 저장 칸 창(불러오기)
func _on_continue() -> void:
	var n := 0
	for k in range(1, Game.SAVE_SLOTS + 1):
		if Game.has_slot(k):
			n += 1
	if n <= 1:
		if Game.load_campaign():
			Game.go_base()
		return
	_slot_window("load")


## 새 게임: 저장 칸 창에서 시작할 칸 고르기 (차 있는 칸 = 덮어쓰기 확인)
func _on_new() -> void:
	_slot_window("new")


## 저장 칸 창 (칸 3개: 게임 날짜 · 잔액 · 실제 저장 시각). mode = "load"(불러오기) | "new"(여기에 새로 시작)
func _slot_window(mode: String) -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = PanelContainer.new()
	UiPanel.apply(_confirm, Vector4(26, 20, 26, 22))
	add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_confirm.add_child(v)
	var t := _label("불러오기 — 저장 칸" if mode == "load" else "새 게임 — 시작할 저장 칸", 20, Color(1, 0.92, 0.75))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var latest := Game.latest_slot()
	for k in range(1, Game.SAVE_SLOTS + 1):
		var info := Game.slot_info(k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var desc := "칸 %d — 비어 있음" % k
		if info.exists:
			desc = "칸 %d — %s%s\n저장: %s%s" % [k, info.label if str(info.label) != "" else "(예전 저장)", "  ·  $%d" % int(info.cash) if int(info.cash) >= 0 else "",
				str(info.saved_at), "   (최근)" if k == latest else ""]
		var l := _label(desc, 15, Color(0.92, 0.92, 0.88) if info.exists else Color(0.6, 0.62, 0.6))
		l.custom_minimum_size = Vector2(380, 44)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 42)
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 16)
		var slot := k
		if mode == "load":
			b.text = "불러오기"
			b.disabled = not info.exists
			UiButton.apply(b, "accept")
			b.pressed.connect(func():
				if Game.load_campaign(slot):
					Game.go_base())
		else:
			b.text = "덮어쓰고 시작" if info.exists else "여기에 시작"
			UiButton.apply(b, "decline" if info.exists else "accept")
			b.pressed.connect(func():
				if info.exists:
					_confirm_overwrite(slot)
				else:
					_start_new(slot))
		row.add_child(b)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 40)
	UiButton.apply(close, "choice", "choice_on")
	close.pressed.connect(func(): _confirm.queue_free())
	v.add_child(close)
	_confirm.reset_size()
	_confirm.position = Vector2(640, 330) - _confirm.get_combined_minimum_size() * 0.5


func _confirm_overwrite(slot: int) -> void:
	_confirm.queue_free()
	_confirm = PanelContainer.new()
	UiPanel.apply(_confirm, Vector4(26, 20, 26, 22))
	add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_confirm.add_child(v)
	v.add_child(_label("칸 %d 에 저장된 기지가 있습니다. 새로 시작하면 덮어씁니다." % slot, 18, Color(1, 0.95, 0.8)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var yes := Button.new()
	yes.text = "덮어쓰고 시작"
	yes.custom_minimum_size = Vector2(200, 44)
	UiButton.apply(yes, "accept")
	yes.pressed.connect(func(): _start_new(slot))
	h.add_child(yes)
	var no := Button.new()
	no.text = "취소"
	no.custom_minimum_size = Vector2(200, 44)
	UiButton.apply(no, "decline")
	no.pressed.connect(func(): _slot_window("new"))
	h.add_child(no)
	_confirm.reset_size()
	_confirm.position = Vector2(640, 330) - _confirm.get_combined_minimum_size() * 0.5


func _start_new(slot: int = 1) -> void:
	Game.save_slot = slot
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
