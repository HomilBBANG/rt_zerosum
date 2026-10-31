class_name UiNine
extends RefCounted
## 9칸 늘리기 그림 그리기 공용 (모서리 · 테두리는 그대로, 가운데만 늘림).
## 그림은 사용자 제공 원본 크기(대개 2배 해상도)라 k 배로 줄여 그림 — 테두리 굵기 = 그림 테두리 × k.
## 전투 UI v2 (원본 art_src/ui/battle_ui_package.webp → assets/ui/battle/v2/) 에서 씀.

static var _sb := {}   # "경로|여백|색" → StyleBoxTexture


static func style(path: String, m: Vector4, mod: Color = Color.WHITE) -> StyleBoxTexture:
	var key := "%s|%s|%s" % [path, m, mod.to_html()]
	if not _sb.has(key):
		var sb := StyleBoxTexture.new()
		sb.texture = load(path)
		sb.texture_margin_left = m.x
		sb.texture_margin_top = m.y
		sb.texture_margin_right = m.z
		sb.texture_margin_bottom = m.w
		sb.modulate_color = mod
		_sb[key] = sb
	return _sb[key]


## ci 위 rect(게임 좌표)에 그림 path 를 9칸 늘리기로. m = 그림 여백(왼 · 위 · 오른 · 아래, 그림 픽셀), k = 그림 배율
static func draw(ci: CanvasItem, path: String, m: Vector4, rect: Rect2, k: float, mod: Color = Color.WHITE) -> void:
	ci.draw_set_transform(rect.position, 0.0, Vector2(k, k))
	ci.draw_style_box(style(path, m, mod), Rect2(Vector2.ZERO, rect.size / k))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## c 뒤에 그림을 까는 자식 (버튼처럼 스스로 글자 · 아이콘을 그리는 컨트롤용). mod_fn() → 지금 색 (마우스 올림 · 누름 등)
static func behind(c: Control, path: String, m: Vector4, k: float, mod_fn: Callable = Callable(), grow: float = 0.0) -> Control:
	var bg := Control.new()
	bg.show_behind_parent = true
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	bg.draw.connect(func():
		var mod: Color = mod_fn.call() if mod_fn.is_valid() else Color.WHITE
		draw(bg, path, m, Rect2(Vector2.ZERO, bg.size).grow(grow), k, mod))
	if c is BaseButton:
		for sig in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
			c.connect(sig, bg.queue_redraw)
		c.connect("toggled", bg.queue_redraw.unbind(1))
	return bg
