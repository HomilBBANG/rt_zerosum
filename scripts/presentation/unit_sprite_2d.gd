class_name UnitSprite2D
extends Node2D
## 2D 유닛: 원화 스프라이트 + 구역 마스크 셰이더 + 무기 레이어 + 클릭 영역 + 하이라이트.

signal clicked(unit: UnitRuntime)

const SHADER := preload("res://shaders/cel_zoned_lighting.gdshader")
const BASE_SCALE := 0.5

var unit: UnitRuntime
var manifest: Dictionary
var body: Sprite2D
var weapon: Sprite2D
var flip: Node2D
var area: Area2D
var mat: ShaderMaterial
var wmat: ShaderMaterial
var highlight_kind: String = "none"
var light_from_right: bool = true
var _bob_t: float = 0.0
var _flash: float = 0.0
var _dead_alpha: float = 1.0
var ui_accent: Color = Color(1, 0.9, 0.4)


func build(p_unit: UnitRuntime, p_manifest: Dictionary) -> void:
	unit = p_unit
	manifest = p_manifest
	var meta: Dictionary = manifest.units.get(unit.data.sprite_id, {})
	flip = Node2D.new()
	flip.name = "Flip"
	add_child(flip)
	if unit.team == "enemy":
		flip.scale.x = -1.0
	flip.scale *= BASE_SCALE
	body = Sprite2D.new()
	body.name = "Body"
	body.centered = false
	body.texture = load("res://assets/sprites/%s.png" % unit.data.sprite_id)
	var ground: float = float(meta.get("ground", 492))
	body.offset = Vector2(-128.0, -ground)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	body.material = mat
	flip.add_child(body)
	weapon = Sprite2D.new()
	weapon.name = "Weapon"
	weapon.centered = false
	wmat = ShaderMaterial.new()
	wmat.shader = SHADER
	weapon.material = wmat
	weapon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var hand: Array = meta.get("hand", [172, 298])
	weapon.position = Vector2(float(hand[0]) - 128.0, float(hand[1]) - ground)
	flip.add_child(weapon)
	refresh_weapon()
	# 클릭 영역
	area = Area2D.new()
	area.input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var h: float = float(meta.get("height", 460)) * BASE_SCALE
	rect.size = Vector2(120.0 * BASE_SCALE * 1.6, h)
	shape.shape = rect
	shape.position = Vector2(0, -h * 0.5)
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	add_child(area)
	_update_light_masks()
	z_index = 10


func refresh_weapon() -> void:
	var w := unit.current_weapon()
	var wid: String = w.get("id", "")
	var path := "res://assets/sprites/w_%s.png" % wid
	if wid == "" or not ResourceLoader.exists(path):
		weapon.visible = false
		return
	weapon.visible = true
	weapon.texture = load(path)
	var wm: Dictionary = manifest.weapons.get(wid, {"pivot": [0, 0]})
	weapon.offset = Vector2(-float(wm.pivot[0]), -float(wm.pivot[1]))
	_update_light_masks()


func set_light_direction(from_right: bool) -> void:
	light_from_right = from_right
	_update_light_masks()


func _update_light_masks() -> void:
	# 텍스처 공간에서의 빛 방향: 적은 좌우 반전되므로 뒤집는다.
	var tex_from_right := light_from_right
	if unit.team == "enemy":
		tex_from_right = not tex_from_right
	var suffix := "_mask_r" if tex_from_right else "_mask_l"
	mat.set_shader_parameter("zone_mask", load("res://assets/sprites/%s%s.png" % [unit.data.sprite_id, suffix]))
	if weapon.visible:
		var wid: String = unit.current_weapon().get("id", "")
		wmat.set_shader_parameter("zone_mask", load("res://assets/sprites/w_%s%s.png" % [wid, suffix]))


## 프리셋 적용. zone: "key" | "accent" | "ambient" — 유닛이 서 있는 빛 영역
func apply_lighting(p: Dictionary, zone: String) -> void:
	ui_accent = p.get("ui_accent", ui_accent)
	# 캐릭터는 의상 고유색 식별을 위해 그림자 색을 배경보다 약간 밝게 (§3.1 '피부·의상 식별 유지')
	var char_shadow := Color(minf(1.0, p.shadow.r * 1.9), minf(1.0, p.shadow.g * 1.9), minf(1.0, p.shadow.b * 1.9))
	for m in [mat, wmat]:
		m.set_shader_parameter("shadow_tint", char_shadow)
		m.set_shader_parameter("ambient_tint", p.ambient)
		match zone:
			"accent":
				# 보조광(창문) 영역: 키=보조광색, 림=주조명색
				m.set_shader_parameter("key_color", p.accent)
				m.set_shader_parameter("accent_color", p.key)
				m.set_shader_parameter("key_mix", p.char_accent_mix)
				m.set_shader_parameter("accent_mix", p.char_key_mix)
			"ambient":
				# 두 빛 사이: 고유색이 가장 잘 보이는 구역. 약한 주변광 키, 선명한 주조명 림
				m.set_shader_parameter("key_color", p.ambient.lightened(0.45))
				m.set_shader_parameter("accent_color", p.key)
				m.set_shader_parameter("key_mix", 0.22)
				m.set_shader_parameter("accent_mix", p.char_key_mix)
			_:
				m.set_shader_parameter("key_color", p.key)
				m.set_shader_parameter("accent_color", p.accent)
				m.set_shader_parameter("key_mix", p.char_key_mix)
				m.set_shader_parameter("accent_mix", p.char_accent_mix)


func set_highlight(kind: String) -> void:
	highlight_kind = kind
	queue_redraw()


func _draw() -> void:
	# 바닥 접지 그림자 + 하이라이트 링 (UI 요소: 조명과 무관한 색)
	var r := Vector2(44, 13)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2.ONE)
	draw_ellipse_poly(Vector2.ZERO, r, Color(0, 0, 0, 0.35), true)
	match highlight_kind:
		"current":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), ui_accent, false, 4.0)
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(ui_accent, 0.25), true)
		"target_ok":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(1.0, 0.25, 0.2), false, 4.0)
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(1.0, 0.25, 0.2, 0.22), true)
		"target_ally":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(0.3, 1.0, 0.5), false, 4.0)
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(0.3, 1.0, 0.5, 0.22), true)
		"target_bad":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(0.5, 0.5, 0.5, 0.6), false, 2.0)
		"hover":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(1, 1, 1, 0.7), false, 2.0)


func draw_ellipse_poly(center: Vector2, radii: Vector2, color: Color, filled: bool, width: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, width, true)


func _process(delta: float) -> void:
	if not unit.alive:
		return
	_bob_t += delta * (2.2 if highlight_kind == "current" else 1.4)
	var amp := 2.5 if highlight_kind == "current" else 1.5
	flip.position.y = sin(_bob_t + float(unit.instance_id)) * amp
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		for m in [mat, wmat]:
			m.set_shader_parameter("flash_color", Color(1, 1, 1, _flash))


func head_screen_offset() -> Vector2:
	var meta: Dictionary = manifest.units.get(unit.data.sprite_id, {})
	var h: float = float(meta.get("height", 460)) * BASE_SCALE
	return Vector2(0, -h - 6)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(unit)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 연출
func play_attack(toward_right: bool, ranged: bool) -> Tween:
	var tw := create_tween()
	var dir := 1.0 if toward_right else -1.0
	if ranged:
		tw.tween_property(flip, "position:x", -10.0 * dir, 0.08).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(flip, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_BACK)
	else:
		tw.tween_property(flip, "position:x", 48.0 * dir, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(flip, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tw


func play_hit() -> void:
	_flash = 1.0
	var tw := create_tween()
	tw.tween_property(flip, "rotation", -0.12 if unit.team == "ally" else 0.12, 0.06)
	tw.tween_property(flip, "rotation", 0.0, 0.16)


func play_heal() -> void:
	var tw := create_tween()
	tw.tween_property(flip, "scale", flip.scale * 1.06, 0.12)
	tw.tween_property(flip, "scale", flip.scale, 0.18)


func play_death() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flip, "rotation", (-1.35 if unit.team == "ally" else 1.35), 0.45).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(flip, "modulate", Color(0.45, 0.45, 0.5, 0.55), 0.6)
	z_index = 5
	set_highlight("none")
