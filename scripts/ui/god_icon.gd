class_name GodIcon
extends Control
## 신 아이콘: 상징색 원 + 테두리 고리 + 글자(FaithData.symbol_of). 누르면 pressed (도감 열기 등).

signal pressed

var color := Color(0.85, 0.8, 0.6)
var symbol := "?"
var _hover := false
var _font: Font


static func make(god: Dictionary, size: float, tip: String = "") -> GodIcon:
	var ic := GodIcon.new()
	ic.color = god.get("color", Color(0.85, 0.8, 0.6)) if god.get("color") is Color else FaithData.color_of(god)
	ic.symbol = str(god.get("symbol", "")) if str(god.get("symbol", "")) != "" else FaithData.symbol_of(god)
	ic.custom_minimum_size = Vector2(size, size)
	ic.tooltip_text = tip
	return ic


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_font = load("res://assets/fonts/Pretendard-Bold.ttf")
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var col := color.lightened(0.15) if _hover else color
	draw_circle(c, r, Color(0.05, 0.06, 0.09, 0.95))
	draw_circle(c, r * 0.86, col.darkened(0.55))
	draw_arc(c, r * 0.93, 0, TAU, 48, col, maxf(1.5, r * 0.1), true)
	draw_arc(c, r * 0.72, 0, TAU, 48, Color(col, 0.55), maxf(1.0, r * 0.04), true)
	for i in 8:   # 둘레 작은 점 (문장 느낌)
		var a := TAU * i / 8.0 - PI / 2
		draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.8, maxf(1.0, r * 0.045), Color(col, 0.8))
	if _font != null:
		var fs := int(r * 0.95)
		draw_string(_font, Vector2(0, c.y + fs * 0.36), symbol, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col.lightened(0.35))
