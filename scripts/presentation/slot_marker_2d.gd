class_name SlotMarker2D
extends Node2D
## 이동(빈 슬롯) / 교환(점유 슬롯) 마커

signal clicked(key: String)

var kind: String = "move"
var key: String = ""
var _t: float = 0.0
var _hover := false


func _ready() -> void:
	z_index = 8
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(110, 40)
	shape.shape = rs
	area.add_child(shape)
	area.input_event.connect(func(_v, ev, _i):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(key)
			get_viewport().set_input_as_handled())
	area.mouse_entered.connect(func(): _hover = true; queue_redraw())
	area.mouse_exited.connect(func(): _hover = false; queue_redraw())
	add_child(area)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var col := Color(0.4, 0.9, 1.0) if kind == "move" else Color(1.0, 0.8, 0.3)
	if _hover:
		col = col.lightened(0.3)
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(Vector2(cos(a) * (54 + pulse * 4), sin(a) * (17 + pulse * 1.5)))
	draw_colored_polygon(pts, Color(col, 0.22 + 0.1 * pulse))
	pts.append(pts[0])
	draw_polyline(pts, col, 3.0, true)
	if kind == "move":
		# 이동 화살표 (아래쪽을 가리킴)
		draw_polyline(PackedVector2Array([Vector2(0, -34), Vector2(0, -10)]), col, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-9, -14), Vector2(9, -14), Vector2(0, -2)]), col)
	else:
		# 교환 아이콘: 양방향 화살표
		draw_polyline(PackedVector2Array([Vector2(-16, -24), Vector2(16, -24)]), col, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(16, -30), Vector2(16, -18), Vector2(26, -24)]), col)
		draw_polyline(PackedVector2Array([Vector2(16, -10), Vector2(-16, -10)]), col, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-16, -16), Vector2(-16, -4), Vector2(-26, -10)]), col)
