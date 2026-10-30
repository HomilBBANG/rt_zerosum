class_name UiPanel
extends RefCounted
## UI 공용 패널 (assets/ui/panel.png — 원본 art_src/ui/panel.webp): 어두운 판 + 올리브색 테두리 + 팔각 모서리.
## apply(패널) = 그 컨테이너의 바탕을 이 그림으로 (모서리 · 테두리는 그대로, 가운데만 늘림) + 안쪽 여백.
## 그림은 2배 해상도(2560×1440 창에서 1:1)라 반으로 줄여 그림. 기지 창 · 대원 카드 · 기록 · 확대 버튼 · 전투 하단 패널 · 상태 이상 창에 씀.

const TEX_PATH := "res://assets/ui/panel.png"
const CORNER := 32          # 그림의 모서리 · 테두리 칸 (그림 픽셀) — 이만큼은 늘리지 않음

static var _sb: StyleBoxTexture


static func _style() -> StyleBoxTexture:
	if _sb == null:
		_sb = StyleBoxTexture.new()
		_sb.texture = load(TEX_PATH)
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			_sb.set_texture_margin(side, CORNER)
	return _sb


## c(보통 PanelContainer)의 바탕을 공용 패널로. margin = 안쪽 여백 (왼 · 위 · 오른 · 아래, 게임 좌표)
static func apply(c: Control, margin: Vector4 = Vector4(18, 14, 18, 14), alpha: float = 1.0) -> void:
	var em := StyleBoxEmpty.new()
	em.content_margin_left = margin.x
	em.content_margin_top = margin.y
	em.content_margin_right = margin.z
	em.content_margin_bottom = margin.w
	c.add_theme_stylebox_override("panel", em)
	if c.has_meta("ui_panel"):
		c.set_meta("ui_panel_alpha", alpha)
		c.queue_redraw()
		return
	c.set_meta("ui_panel", true)
	c.set_meta("ui_panel_alpha", alpha)
	c.draw.connect(func():
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
		var sb := _style()
		var a: float = c.get_meta("ui_panel_alpha", 1.0)
		if a < 1.0:
			sb = sb.duplicate()
			sb.modulate_color = Color(1, 1, 1, a)
		c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size * 2.0))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	c.queue_redraw()
