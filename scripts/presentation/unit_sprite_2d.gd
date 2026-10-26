class_name UnitSprite2D
extends Node2D
## 2D 유닛: 캐릭터 프레임 애니메이션(CharacterSprite2D, assets/characters/<id>) 또는 옛 평면 스프라이트
## + 구역 마스크 셰이더 + 무기 레이어 + 클릭 영역 + 하이라이트.
## 공격·피격·회복·쓰러짐 애니메이션 프레임이 없으면 간단한 이동·흔들림 트윈으로 대신한다.

signal clicked(unit: UnitRuntime)

const SHADER := preload("res://shaders/cel_character.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline_group.gdshader")
const BASE_SCALE := 0.5


var unit: UnitRuntime
var manifest: Dictionary
var body: Sprite2D
var weapon: Sprite2D
var flip: Node2D
var group: CanvasGroup
var area: Area2D
var mat: ShaderMaterial
var wmat: ShaderMaterial
var highlight_kind: String = "none"
var light_from_right: bool = true
var _bob_t: float = 0.0
var _flash: float = 0.0
var _dead_alpha: float = 1.0
var ui_accent: Color = Color(1, 0.9, 0.4)
var chr: CharacterSprite2D = null
var chr_height: float = 232.0


## 좌우 반전 여부: 적은 왼쪽(아군)을 보게 뒤집는다. 원화가 이미 왼쪽을 보면(art_faces_left, 예: 구울) 반대로.
func is_mirrored() -> bool:
	return (unit.team == "enemy") != bool(unit.data.palette.get("art_faces_left", false))


func build(p_unit: UnitRuntime, p_manifest: Dictionary) -> void:
	unit = p_unit
	manifest = p_manifest
	var meta: Dictionary = manifest.units.get(unit.data.sprite_id, {})
	# 파츠·무기를 하나의 CanvasGroup 으로 그려 합쳐진 실루엣에 외곽선을 준다
	group = CanvasGroup.new()
	group.name = "Group"
	group.fit_margin = 8.0
	group.clear_margin = 8.0
	var om := ShaderMaterial.new()
	om.shader = OUTLINE_SHADER
	if Game.cli.get("outline", "1") != "0":
		group.material = om
	flip = Node2D.new()
	flip.name = "Flip"
	if Game.cli.get("nogroup", "0") == "1":
		add_child(flip)
	else:
		add_child(group)
		group.add_child(flip)
	if is_mirrored():
		flip.scale.x = -1.0
	flip.scale *= BASE_SCALE
	if CharacterSprite2D.exists(unit.data.sprite_id):
		_build_character()
		return
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

## 캐릭터 프레임 애니메이션 경로: 셰이더 하나, 무기는 손 위치(character.json hand)에
func _build_character() -> void:
	chr = CharacterSprite2D.new()
	chr.name = "Character"
	flip.add_child(chr)
	chr.scale = Vector2.ONE / BASE_SCALE
	chr.build(unit.data.sprite_id, unit.data.height_cm)
	chr_height = -chr.head_top_local().y + 6.0
	mat = chr.mat
	weapon = Sprite2D.new()
	weapon.name = "Weapon"
	weapon.centered = false
	wmat = ShaderMaterial.new()
	wmat.shader = SHADER
	weapon.material = wmat
	weapon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	weapon.scale = Vector2.ONE * 0.5   # 무기 원화는 캐릭터 키 460px 기준 → 화면 키 230px
	chr.attach_weapon(weapon)
	refresh_weapon()
	area = Area2D.new()
	area.input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(110.0, chr_height)
	shape.shape = rect
	shape.position = Vector2(0, -chr_height * 0.5)
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	add_child(area)
	_update_light_masks()
	z_index = 10


func _all_mats() -> Array:
	return [mat, wmat]


func refresh_weapon() -> void:
	var w := unit.current_weapon()
	var wid: String = str(w.get("sprite", w.get("id", "")))   # 아이템 시트 "스프라이트" (없으면 id)
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
	# 텍스처 공간에서의 빛 방향: 좌우 반전된 유닛은 뒤집는다.
	var tex_from_right := light_from_right
	if is_mirrored():
		tex_from_right = not tex_from_right
	var suffix := "_mask_r" if tex_from_right else "_mask_l"
	var opposite := "_mask_l" if tex_from_right else "_mask_r"
	if chr != null:
		chr.set_light_direction(tex_from_right)   # 적은 좌우 반전 → 반전된 방향의 마스크
	else:
		mat.set_shader_parameter("zone_mask", load("res://assets/sprites/%s%s.png" % [unit.data.sprite_id, suffix]))
		mat.set_shader_parameter("near_rim_mask", load("res://assets/sprites/%s%s.png" % [unit.data.sprite_id, opposite]))
	if weapon.visible:
		var wid: String = str(unit.current_weapon().get("sprite", unit.current_weapon().get("id", "")))
		wmat.set_shader_parameter("zone_mask", load("res://assets/sprites/w_%s%s.png" % [wid, suffix]))
		wmat.set_shader_parameter("near_rim_mask", load("res://assets/sprites/w_%s%s.png" % [wid, opposite]))


## 프리셋 적용. zone: "key" | "accent" | "ambient" — 유닛이 서 있는 빛 영역
func apply_lighting(p: Dictionary, zone: String) -> void:
	ui_accent = p.get("ui_accent", ui_accent)
	for m in _all_mats():
		m.set_shader_parameter("shadow_tint", p.shadow)
		m.set_shader_parameter("ambient_tint", p.ambient)
		match zone:
			"accent":
				# 보조광(창문) 영역: 주조명 = 보조광색, 림 = 주조명색
				m.set_shader_parameter("key_color", p.accent)
				m.set_shader_parameter("accent_color", p.key)
				m.set_shader_parameter("key_mix", 0.62)
			"ambient":
				# 두 빛 사이: 고유색이 가장 잘 보이는 구역. 약한 주변광, 선명한 주조명 림
				m.set_shader_parameter("key_color", p.ambient.lightened(0.5))
				m.set_shader_parameter("accent_color", p.key)
				m.set_shader_parameter("key_mix", 0.3)
			_:
				m.set_shader_parameter("key_color", p.key)
				m.set_shader_parameter("accent_color", p.accent)
				m.set_shader_parameter("key_mix", 0.62)
		m.set_shader_parameter("accent_mix", 0.85)
		m.set_shader_parameter("shadow_depth", 0.78)
		m.set_shader_parameter("shadow_hue", 0.40)
		m.set_shader_parameter("use_near_rim", false)
		m.set_shader_parameter("use_rim", Game.rim_enabled)
		m.set_shader_parameter("debug_view", int(Game.cli.get("charview", "0")))
		_apply_eye_paint(m)


## 3D 배경 모드: 캐릭터 위치에 실제로 닿는 빛으로 명암을 정한다.
## - 닿는 빛이 있으면: 빛 쪽 얼굴·몸을 그 광원색으로 밝힘(키), 반대편은 셀 그림자.
##   빛이 뒤(벽의 창·문)에서 오면 빛 쪽 가장자리에 같은 색 림을 더함(역광이 몸을 감싸는 느낌).
##   반대편 가장자리 림은 그쪽에서 실제로 오는 두 번째 빛이 있을 때만.
## - 닿는 빛이 없으면: 주변광만, 림 없음
func apply_light_probe(p: Dictionary, key: Dictionary, rim: Dictionary) -> void:
	ui_accent = p.get("ui_accent", ui_accent)
	var from_right := true
	var ambient: Color = p.ambient
	for m in _all_mats():
		m.set_shader_parameter("shadow_tint", p.shadow)
		m.set_shader_parameter("ambient_tint", ambient)
		var far_rim := false
		var near_rim := false
		if key.is_empty():
			m.set_shader_parameter("key_color", ambient.lightened(0.5))
			m.set_shader_parameter("key_mix", 0.25)
			m.set_shader_parameter("shadow_depth", 0.86)
			m.set_shader_parameter("shadow_hue", 0.30)
		else:
			var k := clampf(float(key.intensity) / 3.0, 0.0, 1.0)
			from_right = key.from_right
			m.set_shader_parameter("key_color", key.color)
			m.set_shader_parameter("key_mix", lerpf(0.45, 0.70, k))
			m.set_shader_parameter("shadow_depth", 0.80)
			m.set_shader_parameter("shadow_hue", 0.35)
			if key.get("behind", false) and Game.rim_enabled:
				near_rim = true
				m.set_shader_parameter("near_rim_color", key.color)
				m.set_shader_parameter("near_rim_mix", lerpf(0.7, 0.92, k))
			if not rim.is_empty() and Game.rim_enabled:
				far_rim = true
				m.set_shader_parameter("accent_color", rim.color)
				m.set_shader_parameter("accent_mix", clampf(0.45 + float(rim.intensity) / 4.0, 0.45, 0.85))
		m.set_shader_parameter("use_rim", far_rim)
		m.set_shader_parameter("use_near_rim", near_rim)
		m.set_shader_parameter("debug_view", int(Game.cli.get("charview", "0")))
		_apply_eye_paint(m)
	set_light_direction(from_right)


## 로스터 eye_paint 가 있으면 눈동자를 그 색으로 진하게 칠하고, 없으면 원화 눈 색 그대로 둔다.
func _apply_eye_paint(m: ShaderMaterial) -> void:
	var pal: Dictionary = unit.data.palette
	m.set_shader_parameter("paint_eyes", pal.has("eye_paint"))
	m.set_shader_parameter("eye_color", Color(pal.get("eye_paint", pal.get("eyes", "#4f9cff"))))


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
	if chr == null:
		flip.position.y = sin(_bob_t + float(unit.instance_id)) * amp
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		for m in _all_mats():
			m.set_shader_parameter("flash_color", Color(1, 1, 1, _flash))


func head_screen_offset() -> Vector2:
	if chr != null:
		return Vector2(0, -chr_height - 6)
	var meta: Dictionary = manifest.units.get(unit.data.sprite_id, {})
	var h: float = float(meta.get("height", 460)) * BASE_SCALE
	return Vector2(0, -h - 6)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(unit)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 연출
func play_attack(toward_right: bool, ranged: bool) -> Tween:
	if chr != null and chr.has_anim("attack"):
		chr.play("attack")
		var d := CharacterSprite2D.anim_data(chr.cid, "attack")
		var at := create_tween()
		at.tween_interval(0.55 * (d.frames as Array).size() / maxf(1.0, float(d.fps)))   # 프레임 중간쯤 피해 판정
		return at
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
	if chr != null and chr.has_anim("hit"):
		chr.play("hit")
		return
	var tw := create_tween()
	tw.tween_property(flip, "rotation", -0.12 if unit.team == "ally" else 0.12, 0.06)
	tw.tween_property(flip, "rotation", 0.0, 0.16)


func play_heal() -> void:
	if chr != null and chr.has_anim("heal"):
		chr.play("heal")
		return
	var tw := create_tween()
	tw.tween_property(flip, "scale", flip.scale * 1.06, 0.12)
	tw.tween_property(flip, "scale", flip.scale, 0.18)


func play_death() -> void:
	if chr != null and chr.has_anim("death"):
		chr.play("death")
		var tw2 := create_tween()
		tw2.tween_property(flip, "modulate", Color(0.55, 0.55, 0.6, 1.0), 0.8)   # 어둡게만, 투명하게 하지 않음
		z_index = 5
		set_highlight("none")
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flip, "rotation", (-1.35 if unit.team == "ally" else 1.35), 0.45).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(flip, "modulate", Color(0.55, 0.55, 0.6, 1.0), 0.6)
	z_index = 5
	set_highlight("none")
