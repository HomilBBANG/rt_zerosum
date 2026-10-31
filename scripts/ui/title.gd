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
	cont.pressed.connect(func():
		if Game.load_campaign():
			Game.go_base())
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
		if str(Game.cli.get("title_ui", "")) == "settings":
			_open_settings()
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


func _on_new() -> void:
	if not Game.has_save():
		_start_new()
		return
	_confirm = PanelContainer.new()
	UiPanel.apply(_confirm, Vector4(26, 20, 26, 22))
	_confirm.position = Vector2(370, 290)
	add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_confirm.add_child(v)
	v.add_child(_label("저장된 기지가 있습니다. 새로 시작하면 덮어씁니다.", 18, Color(1, 0.95, 0.8)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var yes := Button.new()
	yes.text = "새로 시작"
	yes.custom_minimum_size = Vector2(200, 44)
	UiButton.apply(yes, "accept")
	yes.pressed.connect(_start_new)
	h.add_child(yes)
	var no := Button.new()
	no.text = "취소"
	no.custom_minimum_size = Vector2(200, 44)
	UiButton.apply(no, "decline")
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
