@tool
extends RefCounted
## 리깅 탭 도우미: 조명 구역 마스크 (tools/gen_sprites.py build_zone_mask 와 같은 규칙), 시트 조각 나누기, 기본 뼈대, 파츠→뼈 추측.

const Z_SHADOW := 0
const Z_AMBIENT := 85
const Z_UNLIT := 128
const Z_KEY := 170
const Z_ACCENT := 255

## 전신 그림(알파) → 구역 마스크 (L8). 줄마다 실루엣 좌우 끝을 세로로 부드럽게 해서 빛 쪽 / 주변광 / 그림자 + 그림자 쪽 가장자리 림
static func zone_mask(img: Image, from_right: bool, rim: int = 6, smooth: int = 45) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	lo.resize(h)
	hi.resize(h)
	for y in h:
		lo[y] = -1
		hi[y] = -1
		for x in w:
			if img.get_pixel(x, y).a > 0.16:
				if lo[y] < 0:
					lo[y] = x
				hi[y] = x
	var out := Image.create(w, h, false, Image.FORMAT_L8)
	out.fill(Color8(Z_AMBIENT, Z_AMBIENT, Z_AMBIENT))
	for y in h:
		if lo[y] < 0:
			continue
		var s0 := 0.0
		var s1 := 0.0
		var n := 0
		for k in range(maxi(0, y - smooth), mini(h, y + smooth + 1)):
			if lo[k] >= 0:
				s0 += lo[k]
				s1 += hi[k]
				n += 1
		var x0 := s0 / n
		var x1 := s1 / n
		var width := maxf(1.0, x1 - x0)
		var yn := float(y) / h
		var key_t := 0.38 - 0.12 * (yn - 0.5)
		var amb_t := key_t - 0.17
		for x in range(lo[y], hi[y] + 1):
			if img.get_pixel(x, y).a <= 0.16:
				continue
			var t := (x - x0) / width
			if not from_right:
				t = 1.0 - t
			var v := Z_KEY if t >= key_t else (Z_AMBIENT if t >= amb_t else Z_SHADOW)
			var d_edge := (x - lo[y]) if from_right else (hi[y] - x)
			if d_edge < rim:
				v = Z_ACCENT
			out.set_pixel(x, y, Color8(v, v, v))
	return out


## 한 장짜리 시트 → 떨어진 조각들 [{img, pos}] (투명 배경 기준, 반 해상도로 영역을 나눔)
static func split_islands(img: Image, min_area: int = 300) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var hw := (w + 1) / 2
	var hh := (h + 1) / 2
	var lab := PackedInt32Array()
	lab.resize(hw * hh)
	var solid := PackedByteArray()
	solid.resize(hw * hh)
	for y in hh:
		for x in hw:
			var a := 0.0
			for dy in 2:
				for dx in 2:
					var px := mini(w - 1, x * 2 + dx)
					var py := mini(h - 1, y * 2 + dy)
					a = maxf(a, img.get_pixel(px, py).a)
			solid[y * hw + x] = 1 if a > 0.08 else 0
	var comps := []
	var next := 0
	var stack := PackedInt32Array()
	for i in hw * hh:
		if solid[i] == 0 or lab[i] != 0:
			continue
		next += 1
		lab[i] = next
		stack.clear()
		stack.append(i)
		var r := Rect2i(i % hw, i / hw, 1, 1)
		var count := 0
		while not stack.is_empty():
			var j: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var jx := j % hw
			var jy := j / hw
			r = r.expand(Vector2i(jx, jy))
			if jx + 1 < hw and solid[j + 1] == 1 and lab[j + 1] == 0:
				lab[j + 1] = next
				stack.append(j + 1)
			if jx > 0 and solid[j - 1] == 1 and lab[j - 1] == 0:
				lab[j - 1] = next
				stack.append(j - 1)
			if jy + 1 < hh and solid[j + hw] == 1 and lab[j + hw] == 0:
				lab[j + hw] = next
				stack.append(j + hw)
			if jy > 0 and solid[j - hw] == 1 and lab[j - hw] == 0:
				lab[j - hw] = next
				stack.append(j - hw)
		if count * 4 >= min_area:
			comps.append({"id": next, "rect": Rect2i(r.position, r.size + Vector2i.ONE)})
	var out := []
	for c in comps:
		var r: Rect2i = c.rect
		var full := Rect2i(r.position * 2, r.size * 2).intersection(Rect2i(0, 0, w, h))
		var piece := Image.create(full.size.x, full.size.y, false, Image.FORMAT_RGBA8)
		for y in full.size.y:
			for x in full.size.x:
				var sx := full.position.x + x
				var sy := full.position.y + y
				if lab[(sy / 2) * hw + sx / 2] == c.id:
					piece.set_pixel(x, y, img.get_pixel(sx, sy))
		var used := piece.get_used_rect()
		if used.size.x <= 0:
			continue
		out.append({"img": piece.get_region(used), "pos": full.position + used.position})
	out.sort_custom(func(a, b): return a.pos.x < b.pos.x or (a.pos.x == b.pos.x and a.pos.y < b.pos.y))
	return out


## 기본 뼈대 16개 (게임 애니메이션이 쓰는 이름) — 그림 범위 r 안에 사람 비율로
static func template_bones(r: Rect2) -> Array:
	var cx := r.position.x + r.size.x * 0.5
	var t := r.position.y
	var h := r.size.y
	var p := func(dx: float, fy: float) -> Array: return [snappedf(cx + dx * h, 0.1), snappedf(t + fy * h, 0.1)]
	var b := [
		{"name": "hip", "parent": "", "pos": p.call(0.0, 0.47)},
		{"name": "spine", "parent": "hip", "pos": p.call(0.0, 0.39)},
		{"name": "chest", "parent": "spine", "pos": p.call(0.0, 0.30)},
		{"name": "head", "parent": "chest", "pos": p.call(0.0, 0.19)},
	]
	for s in [["l", -1.0], ["r", 1.0]]:
		var k: float = s[1]
		b.append({"name": "shoulder_" + s[0], "parent": "chest", "pos": p.call(0.085 * k, 0.23)})
		b.append({"name": "elbow_" + s[0], "parent": "shoulder_" + s[0], "pos": p.call(0.11 * k, 0.37)})
		b.append({"name": "wrist_" + s[0], "parent": "elbow_" + s[0], "pos": p.call(0.12 * k, 0.49)})
	for s in [["l", -1.0], ["r", 1.0]]:
		var k: float = s[1]
		b.append({"name": "hip_" + s[0], "parent": "hip", "pos": p.call(0.05 * k, 0.50)})
		b.append({"name": "knee_" + s[0], "parent": "hip_" + s[0], "pos": p.call(0.06 * k, 0.71)})
		b.append({"name": "ankle_" + s[0], "parent": "knee_" + s[0], "pos": p.call(0.07 * k, 0.92)})
	return b


## 파츠 이름으로 뼈 추측 (영어·한글), 모르면 파츠 가운데에서 가장 가까운 뼈
static func guess_bone(part_name: String, center: Vector2, bones: Array) -> String:
	var n := part_name.to_lower()
	var side := ""
	if n.ends_with("_l") or n.contains("left") or n.contains("왼"):
		side = "_l"
	elif n.ends_with("_r") or n.contains("right") or n.contains("오른"):
		side = "_r"
	var names := bones.map(func(b): return str(b.name))
	var want := ""
	if _has(n, ["head", "hair", "face", "eye", "iris", "cap", "hat", "머리", "얼굴", "눈", "모자", "포니"]):
		want = "head"
	elif _has(n, ["forearm", "arm_lower", "lower_arm", "아래팔"]):
		want = "elbow" + side
	elif _has(n, ["upper_arm", "arm_upper", "shoulder", "sleeve", "위팔", "어깨"]):
		want = "shoulder" + side
	elif _has(n, ["hand", "손"]):
		want = "wrist" + side
	elif _has(n, ["thigh", "허벅지"]):
		want = "hip" + side
	elif _has(n, ["shin", "calf", "lower_leg", "leg_lower", "정강이", "종아리"]):
		want = "knee" + side
	elif _has(n, ["foot", "boot", "shoe", "발", "부츠", "신발"]):
		want = "ankle" + side
	elif _has(n, ["hips", "pelvis", "waist", "shorts", "골반", "엉덩이", "허리"]):
		want = "hip"
	elif _has(n, ["torso", "chest", "body", "jacket", "shirt", "몸통", "상체", "가슴"]):
		want = "chest"
	if want != "" and names.has(want):
		return want
	var best := ""
	var bd := INF
	for b in bones:
		var d := center.distance_to(Vector2(b.pos[0], b.pos[1]))
		if d < bd:
			bd = d
			best = str(b.name)
	return best


static func _has(n: String, keys: Array) -> bool:
	for k in keys:
		if n.contains(k):
			return true
	return false
