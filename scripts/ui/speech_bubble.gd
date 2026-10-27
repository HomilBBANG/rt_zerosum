@tool
class_name SpeechBubble
extends Control
## 말풍선: 흰 둥근 사각형 + 아래쪽 꼬리. 꼬리 끝(tip, 부모 좌표)에 맞춰 그 위에 뜨고, life 초 뒤 사라진다.
## 화면 밖으로 나가지 않게 가로 위치만 밀고, 꼬리는 tip 을 계속 가리킨다. life < 0 이면 사라지지 않음 (에디터 미리보기).

const PAD := Vector2(12, 8)
const TAIL := 11.0
const FILL := Color(1, 1, 1, 0.97)
const LINE := Color(0.12, 0.13, 0.16)
const TEXT := Color(0.1, 0.1, 0.12)

var _tail_x := 0.0
var _box := Vector2.ZERO


## text: 대사, tip: 꼬리 끝(부모 좌표), bounds: 말풍선이 들어가야 할 가로 범위 (x0, x1)
func setup(text: String, font: Font, tip: Vector2, life: float = 4.5, max_w: float = 220.0, font_size: int = 14,
		bounds: Vector2 = Vector2(4, 1276)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := max_w - PAD.x * 2.0
	var one_line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var w := minf(one_line.x, inner)
	var ts := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w + 1.0, font_size)
	_box = Vector2(ceilf(w) + PAD.x * 2.0, ceilf(ts.y) + PAD.y * 2.0)
	size = _box + Vector2(0, TAIL)
	var x := clampf(tip.x - _box.x * 0.5, bounds.x, maxf(bounds.x, bounds.y - _box.x))
	position = Vector2(x, tip.y - size.y)
	_tail_x = clampf(tip.x - x, 14.0, _box.x - 14.0)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT)
	l.position = PAD
	l.size = Vector2(_box.x - PAD.x * 2.0, _box.y - PAD.y * 2.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	# 톡 튀어나왔다가 잠시 뒤 흐려지며 사라짐
	pivot_offset = Vector2(_tail_x, size.y)
	scale = Vector2(0.7, 0.7)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate:a", 1.0, 0.12)
	if life >= 0.0:
		tw.tween_interval(maxf(0.1, life))
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		tw.tween_callback(queue_free)
	queue_redraw()


func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FILL
	sb.border_color = LINE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	draw_style_box(sb, Rect2(Vector2.ZERO, _box))
	var a := Vector2(_tail_x - 8.0, _box.y - 2.0)
	var b := Vector2(_tail_x + 8.0, _box.y - 2.0)
	var t := Vector2(_tail_x, _box.y + TAIL)
	draw_colored_polygon(PackedVector2Array([a, b, t]), FILL)
	draw_line(a + Vector2(0, 1), t, LINE, 2.0, true)
	draw_line(b + Vector2(0, 1), t, LINE, 2.0, true)
