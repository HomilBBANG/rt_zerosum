@tool
class_name CharacterSprite2D
extends Node2D
## 캐릭터 = 프레임(스프라이트) 애니메이션. 에셋: assets/characters/<id>/ (도구·형식 설명: tools/char_sprites.py, README)
##   character.json · base.png(정지 그림) · base_mask_l/_r.png · base_line.png(선화) · base_eye.png(눈, 원화 색 유지)
##   애니메이션 (셋 중 아무거나, 위에서부터 찾음):
##     ① 스프라이트 시트 한 장: <애니메이션>_<칸 수>.png (한 줄) 또는 <애니메이션>_<열>x<행>.png — 예: walk_8.png, attack_4x2.png
##        (+ 선택 <애니메이션>.json: {"cols", "rows", "count", "skip": [칸 번호…], "order": [칸 번호…], "align_feet": true, "fps", "loop", "ground", "figure_px", "hip_y", "weapon", "durations"})
##     ② 여러 애니메이션을 한 장에: sheet.png + sheet.json {"cols": 8, "rows": 4, "anims": {"idle": {"row": 0, "count": 6, "fps": 8}, …}}
##     ③ 폴더: <애니메이션>/0001.png, 0002.png … (+ 선택 anim.json, 프레임별 _mask_l/_r.png)
##   시트 칸은 모두 같은 크기. 발 위치·키를 안 적으면 첫 칸 그림에서 자동 (그림 맨 아래 가운데 = 발, 높이 = 키).
## 발 접지점이 (0,0). 화면 키 = 230px × (키 cm / 175) — 전투·기지 공통 기준.
## 애니메이션 폴더가 없으면 base.png 한 장으로 대신한다 (has_anim 으로 구분).
## 모든 프레임은 cel_character 셰이더 하나로 그린다. 조명 마스크가 없는 프레임은 마스크 없이(부드러운 단색 조명).

signal anim_finished(anim_name: String)

const SHADER := preload("res://shaders/cel_character.gdshader")
const ROOT := "res://assets/characters"
const ONE_SHOT := ["attack", "hit", "heal"]   # 끝나면 idle 로
const HOLD := ["death"]                       # 마지막 프레임에서 멈춤

static var _cache: Dictionary = {}   # "<id>/<anim>" → {frames, masks_r, masks_l, fps, loop, ground, figure_px, hip_y, weapon}
static var _info_cache: Dictionary = {}
## 칠 방식 강제 (CLI --char_style=neon|classic, --char_gradient=0|1 → Game 이 넣음). 비어 있으면 character.json 그대로
static var style_override: Dictionary = {}

var cid := ""
var info: Dictionary = {}
var height_cm := 175.0
var body: Sprite2D
var mat: ShaderMaterial
var mats: Array[ShaderMaterial] = []
var weapon_holder: Node2D
var current := ""          # 요청한 애니메이션 이름 (프레임이 없으면 base 로 그림)
var _a: Dictionary = {}
var _t := 0.0
var _frame := -1
var _done := false
var _tex_from_right := true
var speed_scale := 1.0     # 재생 속도 배율 (뛰기 시트가 없을 때 걷기를 빠르게 등)


static func dir_of(id: String) -> String:
	return ROOT.path_join(id)


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(dir_of(id).path_join("character.json"))


static func info_of(id: String) -> Dictionary:
	if not _info_cache.has(id):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_of(id).path_join("character.json"))) if exists(id) else null
		_info_cache[id] = d if d is Dictionary else {}
	return _info_cache[id]


## 초상화 (HUD)
static func portrait(id: String) -> Texture2D:
	return _tex(dir_of(id).path_join("portrait.png"))


## 원본 PNG 가 있으면 직접 읽어 밉맵을 만든다 (임포트 전에 넣은 새 프레임도 바로 보이고, 축소해도 선명). 없으면 임포트된 리소스.
static func _tex(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func _mask(path: String) -> Texture2D:
	if FileAccess.file_exists(path) or ResourceLoader.exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)   # 마스크는 밉맵 없이 (구역 값이 섞이면 안 됨)
		return load(path)
	return null


## 그 애니메이션의 프레임 목록 (없으면 frames 가 빈 배열)
static func anim_data(id: String, anim: String) -> Dictionary:
	var key := id + "/" + anim
	if _cache.has(key):
		return _cache[key]
	var inf := info_of(id)
	var d := {"frames": [], "masks_r": [], "masks_l": [], "lines": [], "eyes": [], "fps": float(inf.get("fps", 12)), "loop": not anim in ONE_SHOT and not anim in HOLD,
		"ground": inf.get("ground", [256, 760]), "figure_px": float(inf.get("figure_px", 760)), "hip_y": float(inf.get("hip_y", 400)),
		"weapon": anim in ["", "idle", "attack", "hit", "heal"], "hand": inf.get("hand", null)}
	var dir := dir_of(id)
	var names: Array[String] = []
	if anim == "":
		names = ["base"]
	else:
		dir = dir.path_join(anim)
		if DirAccess.dir_exists_absolute(dir):
			var seen := {}
			for f in DirAccess.get_files_at(dir):
				var fn := f.trim_suffix(".import").trim_suffix(".remap")
				if fn.ends_with(".png") and not fn.contains("_mask_") and not fn.ends_with("_line.png") and not fn.ends_with("_eye.png") and not seen.has(fn):
					seen[fn] = true
					names.append(fn.get_basename())
			names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
			var aj := dir.path_join("anim.json")
			if FileAccess.file_exists(aj):
				var o: Variant = JSON.parse_string(FileAccess.get_file_as_string(aj))
				if o is Dictionary:
					for k in o:
						d[k] = o[k]
					d.fps = float(d.fps)
					d.figure_px = float(d.figure_px)
					d.hip_y = float(d.hip_y)
	if names.is_empty() and anim != "":
		_sheet_frames(id, anim, d)
		if not (d.frames as Array).is_empty():
			_cache[key] = d
			return d
	for nm in names:
		var t := _tex(dir.path_join(nm + ".png"))
		if t == null:
			continue
		d.frames.append(t)
		d.masks_r.append(_mask(dir.path_join(nm + "_mask_r.png")))
		d.masks_l.append(_mask(dir.path_join(nm + "_mask_l.png")))
		d.lines.append(_mask(dir.path_join(nm + "_line.png")))   # 선화 마스크 (있으면 선은 원화 그대로)
		d.eyes.append(_mask(dir.path_join(nm + "_eye.png")))     # 눈 마스크 (있으면 눈은 원화 색 그대로)
	_cache[key] = d
	return d


## 스프라이트 시트에서 프레임 자르기 (① <애니메이션>_N.png / _CxR.png, ② sheet.png + sheet.json)
static func _sheet_frames(id: String, anim: String, d: Dictionary) -> void:
	var cdir := dir_of(id)
	var path := ""
	var cols := 0
	var rows := 1
	var start := 0
	var count := 0
	var opt: Dictionary = {}
	var names := {}
	for f in DirAccess.get_files_at(cdir):
		names[f.trim_suffix(".import").trim_suffix(".remap")] = true
	var aj := cdir.path_join(anim + ".json")
	if FileAccess.file_exists(aj):
		var o: Variant = JSON.parse_string(FileAccess.get_file_as_string(aj))
		if o is Dictionary:
			opt = o
	for fn in names:
		var b := str(fn).get_basename()
		if not str(fn).ends_with(".png") or not b.begins_with(anim + "_") and b != anim:
			continue
		var tail := b.substr(anim.length() + 1) if b != anim else ""
		var parts := tail.to_lower().split("x")
		if tail == "" or (parts.size() <= 2 and parts[0].is_valid_int() and (parts.size() == 1 or parts[1].is_valid_int())):
			path = cdir.path_join(str(fn))
			if tail != "":
				cols = int(parts[0])
				rows = int(parts[1]) if parts.size() == 2 else 1
			break
	if path == "" and names.has("sheet.png") and FileAccess.file_exists(cdir.path_join("sheet.json")):
		var sj: Variant = JSON.parse_string(FileAccess.get_file_as_string(cdir.path_join("sheet.json")))
		if sj is Dictionary and (sj.get("anims", {}) as Dictionary).has(anim):
			var a: Dictionary = sj.anims[anim]
			path = cdir.path_join("sheet.png")
			cols = int(sj.get("cols", 1))
			rows = int(sj.get("rows", 1))
			start = int(a.get("row", 0)) * cols + int(a.get("start", 0))
			count = int(a.get("count", cols))
			for k in a:
				opt[k] = a[k]
	if path == "":
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
	if img == null and ResourceLoader.exists(path):
		img = (load(path) as Texture2D).get_image()
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	cols = int(opt.get("cols", cols))
	rows = int(opt.get("rows", rows))
	if cols <= 0:
		cols = maxi(1, roundi(float(img.get_width()) / img.get_height()))   # 칸 수를 모르면 정사각 칸 한 줄로
	var cw := img.get_width() / cols
	var ch := img.get_height() / maxi(1, rows)
	if count <= 0:
		count = int(opt.get("count", cols * rows - start))
	# 조명 마스크 시트 (tools/char_sprites.py masks 로 만듦, 같은 칸 배치) — 없으면 고른 조명
	var mimg := {}
	for suf in ["_mask_r", "_mask_l", "_line", "_eye"]:
		var mp: String = path.get_basename() + str(suf) + ".png"
		if FileAccess.file_exists(mp):
			var mi := Image.load_from_file(ProjectSettings.globalize_path(mp))
			if mi != null and not mi.is_empty() and mi.get_size() == img.get_size():
				mimg[suf] = mi
	var first_used := Rect2i()
	var lowest := 0
	var skip: Array = (opt.get("skip", []) as Array).map(func(v): return int(v))   # 뺄 칸 번호 (1부터, 그 동작 안에서)
	var cells: Array = []
	for i in range(start, mini(start + count, cols * rows)):
		if not skip.has(i - start + 1):
			cells.append(i)
	if opt.has("order"):   # 재생 순서 (칸 번호, 1부터) — 시트 그림은 그대로 두고 이어지는 순서만 바꿈
		cells = (opt.order as Array).map(func(v): return start + int(v) - 1).filter(func(i): return i >= start and i < cols * rows)
	for i in cells:
		var r := Rect2i((i % cols) * cw, (i / cols) * ch, cw, ch)
		var cell := img.get_region(r)
		var used := cell.get_used_rect()
		if used.size.x <= 0:
			continue   # 빈 칸
		if first_used.size.x <= 0:
			first_used = used
		lowest = maxi(lowest, used.end.y)
		cell.generate_mipmaps()
		d.frames.append(ImageTexture.create_from_image(cell))
		d.get_or_add("feet_y", []).append(used.end.y)
		d.masks_r.append(ImageTexture.create_from_image(mimg["_mask_r"].get_region(r)) if mimg.has("_mask_r") else null)
		d.masks_l.append(ImageTexture.create_from_image(mimg["_mask_l"].get_region(r)) if mimg.has("_mask_l") else null)
		d.lines.append(ImageTexture.create_from_image(mimg["_line"].get_region(r)) if mimg.has("_line") else null)
		d.eyes.append(ImageTexture.create_from_image(mimg["_eye"].get_region(r)) if mimg.has("_eye") else null)
	if (d.frames as Array).is_empty():
		return
	# 발 위치·키: 적혀 있으면 그대로, 아니면 첫 칸 그림에서
	var gx := first_used.position.x + first_used.size.x * 0.5
	d.ground = opt.get("ground", [gx, lowest])
	d.figure_px = float(opt.get("figure_px", lowest - first_used.position.y))
	d.hip_y = float(opt.get("hip_y", float(d.ground[1]) - d.figure_px * 0.48))
	if bool(opt.get("align_feet", false)):   # 칸마다 발바닥을 같은 땅선에 (그림마다 발 높이가 달라 위아래로 튀는 것 방지)
		d.align_feet = true
		d.ground = [d.ground[0], d.feet_y[0]]
	for k in ["fps", "loop", "weapon", "durations"]:
		if opt.has(k):
			d[k] = opt[k]
	d.fps = float(d.fps)


## 에디터·게임에서 프레임을 새로 넣었을 때 다시 읽기
static func clear_cache() -> void:
	_cache.clear()
	_info_cache.clear()


func build(id: String, p_height_cm: float = 175.0) -> void:
	cid = id
	height_cm = p_height_cm
	info = info_of(id)
	body = Sprite2D.new()
	body.name = "Body"
	body.centered = false
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	body.material = mat
	mats = [mat]
	_apply_style()
	add_child(body)
	weapon_holder = Node2D.new()
	weapon_holder.name = "Hand"
	weapon_holder.z_index = 1
	add_child(weapon_holder)
	var hand: Variant = info.get("hand", null)
	if hand is Array and hand.size() >= 2:
		var g: Array = info.get("ground", [0, 0])
		weapon_holder.position = (Vector2(float(hand[0]), float(hand[1])) - Vector2(float(g[0]), float(g[1]))) * base_scale()
		weapon_holder.rotation = deg_to_rad(float(hand[2]) if hand.size() > 2 else 0.0)
	play("idle")


## 원화 픽셀 → 화면 배율 (기본 그림 기준)
func base_scale() -> float:
	return 230.0 * (height_cm / 175.0) / maxf(1.0, float(info.get("figure_px", 760)))


func has_anim(anim: String) -> bool:
	return not (anim_data(cid, anim).frames as Array).is_empty()


## 후보 중 프레임이 있는 첫 애니메이션 (없으면 마지막 후보 = base 로 그림)
func first_anim(cands: Array) -> String:
	for c in cands:
		if has_anim(str(c)):
			return str(c)
	return str(cands.back()) if not cands.is_empty() else "idle"


func play(anim: String, restart: bool = true) -> void:
	if anim == current and not restart and not _done:
		return
	current = anim
	_a = anim_data(cid, anim)
	if (_a.frames as Array).is_empty():
		_a = anim_data(cid, "")
	_t = 0.0
	_frame = -1
	_done = false
	_show(0)


func is_static() -> bool:
	return not has_anim(current)


func _process(delta: float) -> void:
	delta *= speed_scale
	var n := (_a.get("frames", []) as Array).size()
	if _done or n == 0 or (n == 1 and _a.loop):
		return   # 한 장짜리 반복 동작은 넘길 프레임이 없음 (한 장짜리 hit 같은 1회 동작은 시간이 지나면 끝나야 함)
	var i := 0
	var durs: Array = _a.get("durations", [])
	if not durs.is_empty():
		# anim.json "durations": 프레임마다 보여 줄 초 (목록이 짧으면 반복)
		_t += delta
		var total := 0.0
		for k in n:
			total += maxf(0.01, float(durs[k % durs.size()]))
		if _t >= total and not _a.loop:
			i = n
		else:
			var tt := fmod(_t, total)
			var acc := 0.0
			for k in n:
				acc += maxf(0.01, float(durs[k % durs.size()]))
				if tt < acc:
					i = k
					break
	else:
		_t += delta * float(_a.fps)
		i = floori(_t)
	if i >= n:
		if _a.loop:
			i = i % n
		else:
			_done = true
			i = n - 1
			_show(i)
			anim_finished.emit(current)
			if current in ONE_SHOT:
				play("idle")
			return
	_show(i)


func _show(i: int) -> void:
	if i == _frame:
		return
	_frame = i
	var frames: Array = _a.frames
	if frames.is_empty():
		return
	body.texture = frames[i]
	var g: Array = _a.ground
	var s := 230.0 * (height_cm / 175.0) / maxf(1.0, float(_a.figure_px))
	body.scale = Vector2(s, s)
	var gy := float(g[1])
	if _a.get("align_feet", false):
		gy = float(_a.feet_y[i])
	body.position = -Vector2(float(g[0]), gy) * s
	mat.set_shader_parameter("rim_px", 14.0 * float(_a.figure_px) / 760.0)   # 림 두께: 키 760px 그림 기준 14px
	weapon_holder.visible = bool(_a.get("weapon", true))
	_apply_mask()


func _apply_mask() -> void:
	if _frame < 0 or _a.is_empty():
		return
	var mr: Variant = (_a.masks_r as Array)[_frame]
	var ml: Variant = (_a.masks_l as Array)[_frame]
	var has := mr != null and ml != null
	var ln: Variant = (_a.get("lines", []) as Array)[_frame] if _frame < (_a.get("lines", []) as Array).size() else null
	mat.set_shader_parameter("use_line_mask", ln != null)
	if ln != null:
		mat.set_shader_parameter("line_mask", ln)
	var ey: Variant = (_a.get("eyes", []) as Array)[_frame] if _frame < (_a.get("eyes", []) as Array).size() else null
	mat.set_shader_parameter("use_eye_mask", ey != null)
	if ey != null:
		mat.set_shader_parameter("eye_mask", ey)
	mat.set_shader_parameter("use_zone_mask", has)
	if has:
		mat.set_shader_parameter("zone_mask", mr if _tex_from_right else ml)
		mat.set_shader_parameter("near_rim_mask", ml if _tex_from_right else mr)


## character.json "style": 기본 "neon" (면은 조명색으로 쨍하게, 선화는 원화 그대로), "classic" = 예전 셀 칠. "neon_gradient": 0~1 → 몸 위(빛 쪽)→아래로 조명 색상 회전 그라데이션
func _apply_style() -> void:
	var style := str(style_override.get("style", info.get("style", "neon")))
	var grad := float(style_override.get("neon_gradient", info.get("neon_gradient", 0.0)))
	mat.set_shader_parameter("neon", 1.0 if style == "neon" else 0.0)
	mat.set_shader_parameter("neon_gradient", grad if style == "neon" else 0.0)


## tex_from_right: 텍스처 기준 빛이 오른쪽에서 오는가 (좌우 반전된 유닛은 호출하는 쪽에서 뒤집어 넘김)
func set_light_direction(tex_from_right: bool) -> void:
	_tex_from_right = tex_from_right
	mat.set_shader_parameter("grad_dir", Vector2(-0.35 if tex_from_right else 0.35, 1.0))   # 빛 쪽 위에서 반대쪽 아래로
	mat.set_shader_parameter("light_from_right", tex_from_right)
	_apply_mask()


func set_param(key: String, value: Variant) -> void:
	for m in mats:
		m.set_shader_parameter(key, value)


## 정수리 위치 (발 기준, 화면 px)
func head_top_local() -> Vector2:
	var hr: Variant = info.get("head_rect", null)
	var g: Array = info.get("ground", [0, 0])
	var top := float(hr[1]) if hr is Array else float(g[1]) - float(info.get("figure_px", 760))
	return Vector2(0.0, (top - float(g[1])) * base_scale() - 6.0)


## 발에서 골반까지 높이 / 전신 높이 (앉을 때 의자 높이에 골반을 맞추는 데 씀). 앉기 애니메이션이 있으면 그 기준
func hip_ratio(anim: String = "") -> float:
	var d := anim_data(cid, anim) if anim != "" and has_anim(anim) else anim_data(cid, "")
	var g: Array = d.ground
	return clampf((float(g[1]) - float(d.hip_y)) / maxf(1.0, float(d.figure_px)), 0.05, 0.95)


func attach_weapon(node: Node2D) -> void:
	weapon_holder.add_child(node)
