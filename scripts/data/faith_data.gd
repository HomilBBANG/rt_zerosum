@tool
class_name FaithData
extends RefCounted
## 신앙 데이터 (data/faith.json, Godot 에디터 '스킬 트리' 탭의 '신앙' 에서 편집).
## 신 = {id, name, color(#RRGGBB), symbol(아이콘 글자, 비우면 이름 끝 단어 첫 글자), icon(아이콘 그림 res:// PNG — assets/gods/, 있으면 글자 대신), desc} / 신앙 스킬 = {id, god, name, need(필요 신앙도 0~100), effect, value, desc}
## 효과 형식은 스킬 트리 노드와 같음 (SkillTreeData.EFFECTS).
## 믿는 신 = believers {캐릭터 id → {god(신 id, "" = 무신앙), faith(시작 신앙도)}} — 같은 에디터 화면에서 고침.
## (예전에는 밸런스 엑셀 캐릭터 시트 '신'·'신앙' 열 — believers 가 없는 옛 파일이면 그 열을 씀)
## 세계관 설명(도감)은 data/codex.json 의 gods.
## 신 해금 캐릭터 = divine {캐릭터 id → {god(정체인 신 id), unlocked(처음부터 해금), condition(UnlockCond), will(해금될 때 시작 의지)}}:
##   해금되면 그 캐릭터의 신앙 탭이 '기적' 으로 — 신앙도가 아니라 **의지** 로 배움, 그 캐릭터만의 기적 = miracles [{id, char, name, need(필요 의지), effect, value, desc}]

const PATH := "res://data/faith.json"
const FAITH_MAX := 100


static func new_god(id: String) -> Dictionary:
	return {"id": id, "name": "새 신", "color": "#d8c890", "symbol": "", "icon": "", "desc": ""}


const ICON_DIR := "res://assets/gods"


## 신 아이콘 그림 (없으면 null → 글자 아이콘). 원본 PNG 를 바로 읽음 (임포트 전에 넣어도 보임)
static func icon_texture(g: Dictionary) -> Texture2D:
	var p := str(g.get("icon", ""))
	if p == "":
		return null
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return load(p) if ResourceLoader.exists(p) else null


## assets/gods 의 PNG 목록 (res:// 경로)
static func icon_files() -> Array:
	var out := []
	var d := DirAccess.open(ICON_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() in ["png", "webp", "jpg"]:
			out.append(ICON_DIR.path_join(f))
	out.sort()
	return out


## 신 아이콘 글자: symbol, 없으면 이름 끝 단어 첫 글자 ("태양신 솔루스" → "솔")
static func symbol_of(g: Dictionary) -> String:
	var sy := str(g.get("symbol", "")).strip_edges()
	if sy != "":
		return sy.substr(0, 1)
	var words := str(g.get("name", "?")).split(" ", false)
	return words[words.size() - 1].substr(0, 1) if not words.is_empty() else "?"


static func new_divine(god: String) -> Dictionary:
	return {"god": god, "unlocked": false, "condition": {"type": "manual", "value": 0, "target": ""}, "will": 0}


static func new_miracle(id: String, cid: String, need: int) -> Dictionary:
	return {"id": id, "char": cid, "name": "새 기적", "need": need, "effect": "power", "value": 1, "desc": ""}


static func new_skill(id: String, god: String, need: int) -> Dictionary:
	return {"id": id, "god": god, "name": "새 신앙 스킬", "need": need, "effect": "hp", "value": 1, "desc": ""}


static func read(path: String = PATH) -> Dictionary:
	var out := {"gods": [], "skills": [], "believers": {}, "has_believers": false, "divine": {}, "miracles": []}
	if not FileAccess.file_exists(path):
		return out
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not j is Dictionary:
		return out
	for g in j.get("gods", []):
		if g is Dictionary:
			out.gods.append({"id": str(g.get("id", "")), "name": str(g.get("name", "")), "color": str(g.get("color", "#d8c890")),
				"symbol": str(g.get("symbol", "")), "icon": str(g.get("icon", "")), "desc": str(g.get("desc", ""))})
	var b: Variant = j.get("believers", null)
	if b is Dictionary:
		out.has_believers = true
		for cid in b:
			var e: Variant = b[cid]
			if e is Dictionary:
				out.believers[str(cid)] = {"god": str(e.get("god", "")).strip_edges(), "faith": clampi(int(e.get("faith", 0)), 0, FAITH_MAX)}
	var dv: Variant = j.get("divine", {})
	if dv is Dictionary:
		for cid in dv:
			var e2: Variant = dv[cid]
			if e2 is Dictionary:
				out.divine[str(cid)] = {"god": str(e2.get("god", "")), "unlocked": bool(e2.get("unlocked", false)), "condition": UnlockCond.norm(e2.get("condition", {})),
					"will": clampi(int(e2.get("will", 0)), 0, FAITH_MAX)}
	for m in j.get("miracles", []):
		if m is Dictionary:
			out.miracles.append({"id": str(m.get("id", "")), "char": str(m.get("char", "")), "name": str(m.get("name", "")),
				"need": clampi(int(m.get("need", 0)), 0, FAITH_MAX), "effect": str(m.get("effect", "")).strip_edges(),
				"value": int(m.get("value", 0)), "desc": str(m.get("desc", ""))})
	for s in j.get("skills", []):
		if s is Dictionary:
			out.skills.append({"id": str(s.get("id", "")), "god": str(s.get("god", "")), "name": str(s.get("name", "")),
				"need": clampi(int(s.get("need", 0)), 0, FAITH_MAX), "effect": str(s.get("effect", "")).strip_edges(),
				"value": int(s.get("value", 0)), "desc": str(s.get("desc", ""))})
	return out


static func write(d: Dictionary, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var order := (d.gods as Array).map(func(g): return g.id)
	var skills: Array = (d.skills as Array).duplicate()
	skills.sort_custom(func(a, b):
		if a.god != b.god:
			return order.find(a.god) < order.find(b.god)
		return int(a.need) < int(b.need))
	var miracles: Array = (d.get("miracles", []) as Array).duplicate()
	miracles.sort_custom(func(a, b): return a.char < b.char if a.char != b.char else int(a.need) < int(b.need))
	f.store_string(JSON.stringify({"version": 1, "gods": d.gods, "believers": d.get("believers", {}), "divine": d.get("divine", {}),
		"skills": skills, "miracles": miracles}, "\t", false))
	return OK


## 캐릭터 id → 기적 목록 (필요 의지 오름차순)
static func miracles_by_char(d: Dictionary) -> Dictionary:
	var out := {}
	for m in d.get("miracles", []):
		if not out.has(m.char):
			out[m.char] = []
		out[m.char].append(m)
	for c in out:
		(out[c] as Array).sort_custom(func(a, b): return int(a.need) < int(b.need))
	return out


## 신 id → 신앙 스킬 목록 (필요 신앙도 오름차순)
static func by_god(d: Dictionary) -> Dictionary:
	var out := {}
	for s in d.skills:
		if not out.has(s.god):
			out[s.god] = []
		out[s.god].append(s)
	for g in out:
		(out[g] as Array).sort_custom(func(a, b): return int(a.need) < int(b.need))
	return out


static func color_of(g: Dictionary) -> Color:
	var c := str(g.get("color", ""))
	return Color(c) if c.begins_with("#") else Color(0.9, 0.85, 0.6)


## 검사 → {errors, notes}. char_faith = 캐릭터 id → {god, faith} (believers)
static func check(d: Dictionary, char_faith: Dictionary, actions: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var gids := {}
	for g in d.gods:
		if str(g.id) == "":
			errors.append("id 가 빈 신이 있습니다")
		elif gids.has(g.id):
			errors.append("신 id '%s' 가 두 번 있습니다" % g.id)
		gids[g.id] = true
		var ip := str(g.get("icon", ""))
		if ip != "" and not FileAccess.file_exists(ip) and not ResourceLoader.exists(ip):
			errors.append("%s: 아이콘 그림 '%s' 가 없습니다 (글자 아이콘으로 보임)" % [g.name, ip])
	var sids := {}
	for s in d.skills:
		if str(s.id) == "":
			errors.append("%s: id 가 빈 신앙 스킬이 있습니다" % s.god)
		elif sids.has(s.id):
			errors.append("신앙 스킬 id '%s' 가 두 번 있습니다" % s.id)
		sids[s.id] = true
		if not gids.has(s.god):
			errors.append("%s: 없는 신 '%s'" % [s.id, s.god])
		var ef: String = s.effect
		if ef.begins_with("skill:") or ef.begins_with("skill_power:"):
			if not actions.has(ef.split(":")[1]):
				errors.append("%s: 스킬 시트에 없는 스킬 '%s'" % [s.id, ef.split(":")[1]])
		elif not ef in SkillTreeData.EFFECTS:
			errors.append("%s: 모르는 효과 '%s'" % [s.id, ef])
		if ef.begins_with("skill:"):
			notes.append("%s: 새 스킬은 전투 기본 스킬 칸(%d칸)이 차 있으면 안 보입니다" % [s.id, SkillTreeData.SKILL_SLOTS])
	for cid in char_faith:
		var g := str(char_faith[cid].god)
		if g != "" and not gids.has(g):
			errors.append("%s: 믿는 신 '%s' 가 없는 신입니다" % [cid, g])
	for cid in d.get("divine", {}):
		var dv: Dictionary = d.divine[cid]
		if not char_faith.is_empty() and not char_faith.has(cid):
			errors.append("신 해금: 캐릭터 시트에 없는 캐릭터 '%s'" % cid)
		if not gids.has(str(dv.god)):
			errors.append("신 해금 %s: 정체인 신 '%s' 가 없습니다" % [cid, dv.god])
		if str(char_faith.get(cid, {}).get("god", "")) == str(dv.god) and str(dv.god) != "":
			notes.append("신 해금 %s: 자기 자신(%s)을 믿는 상태입니다 — 해금 뒤에는 신앙 대신 기적" % [cid, dv.god])
		if not (d.get("miracles", []) as Array).any(func(m): return m.char == cid):
			notes.append("신 해금 %s: 기적이 없습니다" % cid)
		if str(dv.condition.type) == "quest" and not UnlockCond.MISSION_KINDS.has(str(dv.condition.get("target", "")).split(":")[0]):
			errors.append("신 해금 %s: 미션 완료 조건인데 미션이 없습니다" % cid)
		if str(dv.condition.type) == "manual":
			notes.append("신 해금 %s: 직접 해금 — 이벤트·대사에서 BaseSim.unlock_divine 을 불러야 해금" % cid)
	var mids := {}
	for m in d.get("miracles", []):
		if str(m.id) == "" or mids.has(m.id) or sids.has(m.id):
			errors.append("기적 id '%s' 가 비었거나 겹칩니다 (신앙 스킬 id 와도 달라야 함)" % m.id)
		mids[m.id] = true
		if not (d.get("divine", {}) as Dictionary).has(m.char):
			errors.append("기적 %s: 신 해금 캐릭터가 아닌 '%s'" % [m.id, m.char])
		var mf: String = m.effect
		if mf.begins_with("skill:") or mf.begins_with("skill_power:"):
			if not actions.has(mf.split(":")[1]):
				errors.append("기적 %s: 스킬 시트에 없는 스킬 '%s'" % [m.id, mf.split(":")[1]])
		elif not mf in SkillTreeData.EFFECTS:
			errors.append("기적 %s: 모르는 효과 '%s'" % [m.id, mf])
	for g in d.gods:
		if not (d.skills as Array).any(func(s): return s.god == g.id):
			notes.append("%s: 신앙 스킬이 없습니다" % g.name)
		if not char_faith.values().any(func(cf): return cf.god == g.id):
			notes.append("%s: 믿는 캐릭터가 없습니다" % g.name)
	return {"errors": errors, "notes": notes}
