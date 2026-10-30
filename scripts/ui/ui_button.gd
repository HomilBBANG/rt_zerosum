class_name UiButton
extends RefCounted
## 의뢰 수락 / 거절 버튼 그림 (원본 art_src/ui/buttons_accept_decline.webp → assets/ui/btn_accept.png 초록 · btn_decline.png 회색).
## 대원 요청(의뢰) 대화의 수락 · 나중에, 의뢰 게시판의 지시에만 씀 — 대화 선택지 등 다른 버튼에는 안 씀.
## 그림은 2배 해상도(높이 72 = 버튼 36칸)라 반으로 줄여 그림. 양 끝 팔각 모서리는 그대로, 가운데만 늘림.

const TEX := {"accept": "res://assets/ui/btn_accept.png", "decline": "res://assets/ui/btn_decline.png"}
const SIDE := 26     # 좌우 모서리 칸 (그림 픽셀)
const CAP_TOP := 24
const CAP_BOTTOM := 28   # 아래 그림자 포함

static var _sb := {}


static func _style(kind: String) -> StyleBoxTexture:
	if not _sb.has(kind):
		var sb := StyleBoxTexture.new()
		sb.texture = load(TEX.get(kind, TEX.accept))
		sb.texture_margin_left = SIDE
		sb.texture_margin_right = SIDE
		sb.texture_margin_top = CAP_TOP
		sb.texture_margin_bottom = CAP_BOTTOM
		_sb[kind] = sb
	return _sb[kind]


## b(Button)의 바탕을 그 그림으로. 글자는 그림 위 (그림은 버튼 뒤에 그리는 자식).
## 마우스 올림 = 밝게, 누름 = 어둡게, 못 누름 = 흐리게
static func apply(b: Button, kind: String) -> void:
	var em := StyleBoxEmpty.new()
	em.content_margin_left = 16
	em.content_margin_right = 16
	em.content_margin_top = 5
	em.content_margin_bottom = 8   # 아래 그림자만큼 글자를 위로
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, em)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color(0.97, 0.97, 0.93))
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.75, 0.7))
	b.add_theme_color_override("font_outline_color", Color(0.06, 0.07, 0.06))
	b.add_theme_constant_override("outline_size", 4)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 36.0)
	var bg := Control.new()
	bg.show_behind_parent = true
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(bg)
	var sb := _style(kind)
	bg.draw.connect(func():
		var mod := Color.WHITE
		match b.get_draw_mode():
			BaseButton.DRAW_HOVER:
				mod = Color(1.22, 1.22, 1.18)
			BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED:
				mod = Color(0.78, 0.78, 0.78)
			BaseButton.DRAW_DISABLED:
				mod = Color(0.6, 0.6, 0.6, 0.6)
		var s: StyleBoxTexture = sb
		if mod != Color.WHITE:
			s = sb.duplicate()
			s.modulate_color = mod
		bg.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
		bg.draw_style_box(s, Rect2(Vector2.ZERO, bg.size * 2.0))
		bg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	for sig in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
		b.connect(sig, bg.queue_redraw)
