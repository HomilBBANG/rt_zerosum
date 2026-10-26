class_name RiggedUnit2D
extends Node2D
## Skeleton2D 컷아웃 리그: rig.json(본 트리 + 파츠 + 피벗)로 Bone2D 계층을 만들고
## 파츠 Sprite2D 를 본 아래에 붙인다. 모든 파츠는 cel_zoned_lighting 셰이더 + 구역 마스크를 쓴다.
## 애니메이션(idle/attack/hit/heal/death)은 코드로 만든 Animation 리소스 (본 회전 키).
## 눈동자: rig.json 파츠에 "attach"(붙을 파츠) + "clip_mask"(눈 테두리) 가 있으면 홍채 파츠 — 눈 테두리 안에서 이리저리 봄 (가끔 시선 이동).

const SHADER := preload("res://shaders/cel_character.gdshader")

var rig: Dictionary
var rig_dir: String
var skeleton: Skeleton2D
var bones: Dictionary = {}       # name -> Bone2D
var parts: Array[Sprite2D] = []
var part_names: Array[String] = []
var mats: Array[ShaderMaterial] = []
var anim: AnimationPlayer
var scale_factor: float = 0.156
var weapon_bone: Bone2D
var light_from_right := true
var mirrored := false
var px_k: float = 1.0   # 원본(1475px 키) 기준으로 작성한 이동량을 축소 원화 픽셀로 환산
var irises: Array = []  # [{sprite, rest, origin, clip_origin, range, mat}]
var look := Vector2.ZERO          # 지금 시선 (-1~1)
var look_target := Vector2.ZERO
var look_hold: Vector2 = Vector2(INF, INF)   # 고정 시선 (INF = 자유롭게 둘러봄)
var _look_t := 0.0


## height_cm: 캐릭터 키. rig.json 의 figure_px(정수리~발 픽셀)를 230px = 175cm 기준 화면 키로 맞춘다.
func build(p_rig_dir: String, p_mirrored: bool = false, height_cm: float = 175.0) -> void:
	rig_dir = p_rig_dir
	mirrored = p_mirrored
	var f := FileAccess.open(rig_dir.path_join("rig.json"), FileAccess.READ)
	rig = JSON.parse_string(f.get_as_text())
	scale_factor = float(rig.get("scale", 0.156))
	if rig.has("figure_px"):
		scale_factor = 230.0 * (height_cm / 175.0) / float(rig.figure_px)
	px_k = 0.156 / scale_factor
	var ground: Array = rig.ground
	# 이미지 픽셀 좌표계를 그대로 쓰고 컨테이너에서 축소. 발 접지점이 (0,0).
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	skeleton.position = Vector2(-float(ground[0]), -float(ground[1])) * scale_factor
	skeleton.scale = Vector2(-scale_factor if mirrored else scale_factor, scale_factor)
	if mirrored:
		skeleton.position.x = -skeleton.position.x
	add_child(skeleton)
	# 본 생성 (rest 회전 0, 위치는 부모 기준 이미지 픽셀 차이)
	var pos_of: Dictionary = {}
	for b in rig.bones:
		pos_of[b.name] = Vector2(b.pos[0], b.pos[1])
	for b in rig.bones:
		var bone := Bone2D.new()
		bone.name = b.name
		var parent_name: String = b.parent
		var parent: Node = bones.get(parent_name, skeleton) if parent_name != "" else skeleton
		var ppos: Vector2 = pos_of.get(parent_name, Vector2.ZERO) if parent_name != "" else Vector2.ZERO
		bone.position = pos_of[b.name] - ppos
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(60.0)
		parent.add_child(bone)
		bone.rest = bone.transform
		bones[b.name] = bone
	# 파츠 Sprite2D (z 순서는 본 트리와 무관하게 전역 z_index 로)
	var sorted: Array = rig.parts.filter(func(p): return not p.has("attach"))
	sorted.sort_custom(func(a, b): return a.z < b.z)
	var by_name := {}
	for p in sorted:
		var s := Sprite2D.new()
		s.name = p.name
		s.centered = false
		s.texture = load(rig_dir.path_join(p.tex))
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var bone: Bone2D = bones[p.bone]
		s.position = Vector2(p.origin[0], p.origin[1]) - pos_of[p.bone]
		s.z_index = int(p.z)
		s.z_as_relative = true
		var m := ShaderMaterial.new()
		m.shader = SHADER
		s.material = m
		mats.append(m)
		bone.add_child(s)
		parts.append(s)
		part_names.append(p.name)
		by_name[p.name] = [s, p]
	# 눈동자: 붙을 파츠의 자식 (그 위에 그려짐), 눈 테두리 마스크로 자름
	for p in rig.parts.filter(func(q): return q.has("attach")):
		var host: Array = by_name.get(p.attach, [])
		if host.is_empty():
			continue
		var s := Sprite2D.new()
		s.name = p.name
		s.centered = false
		s.texture = load(rig_dir.path_join(p.tex))
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var rest := Vector2(p.origin[0], p.origin[1]) - Vector2(host[1].origin[0], host[1].origin[1])
		s.position = rest
		var m := ShaderMaterial.new()
		m.shader = SHADER
		s.material = m
		host[0].add_child(s)
		mats.append(m)
		parts.append(s)
		part_names.append(p.name)
		if p.has("clip_mask"):
			var mask: Texture2D = load(rig_dir.path_join(p.clip_mask))
			m.set_shader_parameter("use_clip", true)
			m.set_shader_parameter("clip_mask", mask)
			m.set_shader_parameter("clip_size", mask.get_size())
			var rng: Array = p.get("eye_range", [3, 1])
			irises.append({"sprite": s, "rest": rest, "origin": Vector2(p.origin[0], p.origin[1]),
				"clip_origin": Vector2(p.clip_origin[0], p.clip_origin[1]), "range": Vector2(float(rng[0]), float(rng[1])), "mat": m})
	_apply_look()
	weapon_bone = bones.get(rig.get("weapon_bone", "wrist_r"), null)
	_update_masks()
	_build_animations()
	anim.play("idle")


# ---------------------------------------------------------------- 눈동자
## 시선 고정 (-1~1, 화면 기준 x 오른쪽·y 아래). free_look() 으로 다시 둘러보기
func look_at_dir(dir: Vector2) -> void:
	look_hold = dir.clamp(Vector2(-1, -1), Vector2(1, 1))


func free_look() -> void:
	look_hold = Vector2(INF, INF)


func _process(delta: float) -> void:
	if irises.is_empty():
		return
	if look_hold.x != INF:
		look_target = look_hold
	else:
		_look_t -= delta
		if _look_t <= 0.0:
			# 가끔 시선 이동: 정면 40%, 좌우 위주, 위아래는 조금
			_look_t = randf_range(0.9, 3.2)
			if randf() < 0.4:
				look_target = Vector2.ZERO
			else:
				look_target = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.8))
	var prev := look
	look = look.move_toward(look_target, delta * 9.0)   # 빠르게 휙 (사카드)
	if look != prev:
		_apply_look()


func _apply_look() -> void:
	for e in irises:
		var off := Vector2(look.x * e.range.x, look.y * e.range.y)
		if mirrored:
			off.x = -off.x
		e.sprite.position = e.rest + off
		e.mat.set_shader_parameter("clip_offset", e.origin + off - e.clip_origin)


func set_light_direction(from_right: bool) -> void:
	light_from_right = from_right
	_update_masks()


func _update_masks() -> void:
	var tex_from_right := light_from_right
	if mirrored:
		tex_from_right = not tex_from_right
	var suffix := "_mask_r.png" if tex_from_right else "_mask_l.png"
	var opposite := "_mask_l.png" if tex_from_right else "_mask_r.png"
	for i in parts.size():
		mats[i].set_shader_parameter("zone_mask", load(rig_dir.path_join(part_names[i] + suffix)))
		mats[i].set_shader_parameter("near_rim_mask", load(rig_dir.path_join(part_names[i] + opposite)))


func set_param(key: String, value: Variant) -> void:
	for m in mats:
		m.set_shader_parameter(key, value)


func head_top_local() -> Vector2:
	var hr: Array = rig.get("head_rect", [0, 0, 0, 0])
	var ground: Array = rig.ground
	return Vector2(0.0, (float(hr[1]) - float(ground[1])) * scale_factor - 6.0)


## 손(무기 본)의 로컬 좌표 (유닛 기준) — 무기 스프라이트를 본에 직접 붙이므로 참고용
func attach_weapon(node: Node2D) -> void:
	if weapon_bone == null:
		add_child(node)
		return
	weapon_bone.add_child(node)
	node.position = Vector2(10, 10) * px_k
	node.rotation = deg_to_rad(70.0)


# ---------------------------------------------------------------- 애니메이션
func _bone_path(bname: String) -> NodePath:
	return NodePath(String(skeleton.get_path_to(bones[bname])) + ":rotation")


func _track(a: Animation, bname: String, keys: Array, prop: String = "rotation") -> void:
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath(String(skeleton.get_path_to(bones[bname])) + ":" + prop))
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	for k in keys:
		a.track_insert_key(t, k[0], k[1])


func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	skeleton.add_child(anim)
	anim.root_node = anim.get_path_to(skeleton)
	var lib := AnimationLibrary.new()
	# idle: 호흡 + 머리카락/팔 미세 흔들림
	var idle := Animation.new()
	idle.length = 2.6
	idle.loop_mode = Animation.LOOP_LINEAR
	_track(idle, "spine", [[0.0, 0.0], [1.3, deg_to_rad(1.2)], [2.6, 0.0]])
	_track(idle, "chest", [[0.0, 0.0], [1.3, deg_to_rad(-1.0)], [2.6, 0.0]])
	_track(idle, "head", [[0.0, deg_to_rad(1.0)], [1.3, deg_to_rad(-1.5)], [2.6, deg_to_rad(1.0)]])
	_track(idle, "shoulder_l", [[0.0, deg_to_rad(-1.5)], [1.3, deg_to_rad(1.5)], [2.6, deg_to_rad(-1.5)]])
	_track(idle, "shoulder_r", [[0.0, deg_to_rad(1.5)], [1.3, deg_to_rad(-1.5)], [2.6, deg_to_rad(1.5)]])
	_track(idle, "elbow_l", [[0.0, 0.0], [1.3, deg_to_rad(2.0)], [2.6, 0.0]])
	_track(idle, "elbow_r", [[0.0, 0.0], [1.3, deg_to_rad(-2.0)], [2.6, 0.0]])
	_track(idle, "hip", [[0.0, Vector2(bones.hip.position)], [1.3, bones.hip.position + Vector2(0, 6) * px_k], [2.6, Vector2(bones.hip.position)]], "position")
	lib.add_animation("idle", idle)
	# attack: 오른팔 들어 올려 조준/휘두르기 + 상체 전진
	var atk := Animation.new()
	atk.length = 0.55
	_track(atk, "shoulder_r", [[0.0, 0.0], [0.14, deg_to_rad(-105)], [0.32, deg_to_rad(-95)], [0.55, 0.0]])
	_track(atk, "elbow_r", [[0.0, 0.0], [0.14, deg_to_rad(-20)], [0.32, deg_to_rad(-10)], [0.55, 0.0]])
	_track(atk, "chest", [[0.0, 0.0], [0.14, deg_to_rad(-8)], [0.32, deg_to_rad(-6)], [0.55, 0.0]])
	_track(atk, "spine", [[0.0, 0.0], [0.14, deg_to_rad(-4)], [0.55, 0.0]])
	_track(atk, "head", [[0.0, 0.0], [0.14, deg_to_rad(6)], [0.55, 0.0]])
	_track(atk, "shoulder_l", [[0.0, 0.0], [0.14, deg_to_rad(18)], [0.55, 0.0]])
	lib.add_animation("attack", atk)
	# hit: 뒤로 젖힘
	var hit := Animation.new()
	hit.length = 0.32
	_track(hit, "spine", [[0.0, 0.0], [0.08, deg_to_rad(9)], [0.32, 0.0]])
	_track(hit, "head", [[0.0, 0.0], [0.08, deg_to_rad(12)], [0.32, 0.0]])
	_track(hit, "shoulder_l", [[0.0, 0.0], [0.08, deg_to_rad(-25)], [0.32, 0.0]])
	_track(hit, "shoulder_r", [[0.0, 0.0], [0.08, deg_to_rad(25)], [0.32, 0.0]])
	lib.add_animation("hit", hit)
	# heal: 팔 벌리고 고개 들기
	var heal := Animation.new()
	heal.length = 0.5
	_track(heal, "shoulder_l", [[0.0, 0.0], [0.25, deg_to_rad(35)], [0.5, 0.0]])
	_track(heal, "shoulder_r", [[0.0, 0.0], [0.25, deg_to_rad(-35)], [0.5, 0.0]])
	_track(heal, "head", [[0.0, 0.0], [0.25, deg_to_rad(-6)], [0.5, 0.0]])
	lib.add_animation("heal", heal)
	# death: 무릎 꿇고 쓰러짐
	var die := Animation.new()
	die.length = 0.8
	_track(die, "hip", [[0.0, Vector2(bones.hip.position)], [0.8, bones.hip.position + Vector2(0, 260) * px_k]], "position")
	_track(die, "hip_l", [[0.0, 0.0], [0.8, deg_to_rad(-35)]])
	_track(die, "hip_r", [[0.0, 0.0], [0.8, deg_to_rad(35)]])
	_track(die, "knee_l", [[0.0, 0.0], [0.8, deg_to_rad(70)]])
	_track(die, "knee_r", [[0.0, 0.0], [0.8, deg_to_rad(-70)]])
	_track(die, "spine", [[0.0, 0.0], [0.5, deg_to_rad(-20)], [0.8, deg_to_rad(-35)]])
	_track(die, "head", [[0.0, 0.0], [0.8, deg_to_rad(-40)]])
	_track(die, "shoulder_l", [[0.0, 0.0], [0.8, deg_to_rad(-15)]])
	_track(die, "shoulder_r", [[0.0, 0.0], [0.8, deg_to_rad(15)]])
	lib.add_animation("death", die)
	# walk: 기지(아웃게임) 이동용 — 다리·팔 교차 + 상하 흔들림
	if bones.has("hip_l") and bones.has("hip_r") and bones.has("knee_l") and bones.has("knee_r"):
		var walk := Animation.new()
		walk.length = 0.9
		walk.loop_mode = Animation.LOOP_LINEAR
		_track(walk, "hip_l", [[0.0, deg_to_rad(-20)], [0.45, deg_to_rad(20)], [0.9, deg_to_rad(-20)]])
		_track(walk, "hip_r", [[0.0, deg_to_rad(20)], [0.45, deg_to_rad(-20)], [0.9, deg_to_rad(20)]])
		_track(walk, "knee_l", [[0.0, 0.0], [0.22, deg_to_rad(28)], [0.45, 0.0], [0.9, 0.0]])
		_track(walk, "knee_r", [[0.0, 0.0], [0.45, 0.0], [0.67, deg_to_rad(-28)], [0.9, 0.0]])
		_track(walk, "shoulder_l", [[0.0, deg_to_rad(14)], [0.45, deg_to_rad(-14)], [0.9, deg_to_rad(14)]])
		_track(walk, "shoulder_r", [[0.0, deg_to_rad(-14)], [0.45, deg_to_rad(14)], [0.9, deg_to_rad(-14)]])
		_track(walk, "hip", [[0.0, Vector2(bones.hip.position)], [0.22, bones.hip.position + Vector2(0, -8) * px_k], [0.45, Vector2(bones.hip.position)],
			[0.67, bones.hip.position + Vector2(0, -8) * px_k], [0.9, Vector2(bones.hip.position)]], "position")
		lib.add_animation("walk", walk)
		# sit: 기지 의자·소파에 앉기 (허벅지 앞으로 수평, 정강이 아래로) + 호흡
		var sit := Animation.new()
		sit.length = 2.6
		sit.loop_mode = Animation.LOOP_LINEAR
		for leg in ["l", "r"]:
			_track(sit, "hip_" + leg, [[0.0, deg_to_rad(-82)], [2.6, deg_to_rad(-82)]])
			_track(sit, "knee_" + leg, [[0.0, deg_to_rad(82)], [2.6, deg_to_rad(82)]])
		_track(sit, "chest", [[0.0, 0.0], [1.3, deg_to_rad(-1.2)], [2.6, 0.0]])
		_track(sit, "head", [[0.0, deg_to_rad(1.0)], [1.3, deg_to_rad(-1.0)], [2.6, deg_to_rad(1.0)]])
		lib.add_animation("sit", sit)
	anim.add_animation_library("", lib)


func play(name: String) -> void:
	if anim.has_animation(name):
		anim.stop()
		anim.play(name)
		if name != "idle" and name != "death":
			anim.animation_finished.connect(func(_n): anim.play("idle"), CONNECT_ONE_SHOT)


## 발에서 골반(hip 본)까지 높이 / 전신 높이 (앉을 때 의자 높이에 골반을 맞추는 데 씀)
func hip_ratio() -> float:
	if not bones.has("hip") or not rig.has("figure_px"):
		return 0.5
	return (float(rig.ground[1]) - bones.hip.position.y) / float(rig.figure_px)


func bone_count() -> int:
	return bones.size()


func part_count() -> int:
	return parts.size()
