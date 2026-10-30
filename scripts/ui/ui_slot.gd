class_name UiSlot
extends RefCounted
## 정사각형 슬롯 패널 3종 (원본 art_src/ui/square_panels.webp → assets/ui/slot_*.png, 150×150 = 75칸의 2배 해상도):
##   item  = 1번 (팔각 모서리) — 기지 인벤토리 칸에만
##   skill = 2번 (둥근 모서리) — 전투 하단 일반 스킬 칸에만
##   ult   = 3번 (꺾쇠 모서리) — 전투 하단 필살기 칸에만
## 자리 이동 · 무기 칸 등 다른 곳에는 쓰지 않음.

const TEX := {
	"item": "res://assets/ui/slot_item.png",
	"skill": "res://assets/ui/slot_skill.png",
	"ult": "res://assets/ui/slot_ult.png",
}
const RADIUS := {"item": 4, "skill": 9, "ult": 2}   # 강조 테두리 모서리 (게임 좌표)

static var _tex := {}


static func texture(kind: String) -> Texture2D:
	if not _tex.has(kind):
		_tex[kind] = load(TEX.get(kind, TEX.item))
	return _tex[kind]


## 버튼 바탕을 그 패널 그림으로: 기본 스타일은 비우고 draw 신호로 그림 → 아이콘 · 비용 등 자식은 그 위에 그려짐.
## gray = 쓸 수 없음(어둡게), border = 강조 테두리 색 (알파 0 = 없음). 마우스를 올리면 밝게
static func apply(b: BaseButton, kind: String, gray: bool = false, border: Color = Color(0, 0, 0, 0)) -> void:
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	var tex := texture(kind)
	var line: StyleBoxFlat = null
	if border.a > 0.0:
		line = StyleBoxFlat.new()
		line.draw_center = false
		line.border_color = border
		line.set_border_width_all(3)
		line.set_corner_radius_all(int(RADIUS.get(kind, 4)))
	b.draw.connect(func():
		var mod := Color(0.55, 0.55, 0.58) if gray else Color.WHITE
		if b.is_hovered() and not b.disabled:
			mod = Color(1.3, 1.3, 1.25)
		b.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
		b.draw_texture_rect(tex, Rect2(Vector2.ZERO, b.size * 2.0), false, mod)
		b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if line != null:
			b.draw_style_box(line, Rect2(Vector2.ONE, b.size - Vector2(2, 2))))
	b.queue_redraw()
