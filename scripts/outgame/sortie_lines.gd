class_name SortieLines
extends RefCounted
## 출정 대기(편성) 화면 말풍선 대사: data/outgame/sortie_lines.json (Godot 에디터 '출정 대사' 탭).
## 진형에 배치된 대원마다 지금 상태(친밀도·피로도·체력·상태 이상·자리·함께 출정하는 대원)에 맞는 대사 하나를 고른다.
## 고르는 법: 조건이 모두 맞는 대사 중 우선순위가 가장 높은 것 → 같으면 그 대원 전용 대사를 공통 대사보다 먼저 → 그래도 같으면 무작위.
## 대사 안의 {name} = 그 대원 이름, {with} = '함께 출정' 조건의 대원 이름.

const PATH := "res://data/outgame/sortie_lines.json"
## 진형 줄 → 이름 (row 0 = 전방, 1 = 중간, 2 = 후방 — SlotManager 와 같은 순서)
const ROW_KEYS := ["front", "middle", "back"]
const ROW_NAMES := {"": "상관없음", "front": "전방", "middle": "중간", "back": "후방"}
## 상태 조건: "" = 상관없음, "none" = 상태 이상 없음, 그 밖 = 그 상태 이상이 있을 때 (StatusCatalog id)
const STATUS_ANY := ""
const STATUS_NONE := "none"


static func new_line(id: String, char_id: String = "") -> Dictionary:
	return {"id": id, "char": char_id, "text": "", "priority": 0,
		"aff_min": 0, "aff_max": 100, "fat_min": 0, "fat_max": 100, "hp_min": 0, "hp_max": 100,
		"status": STATUS_ANY, "row": "", "with": "", "note": ""}


static func _norm(r: Dictionary, i: int) -> Dictionary:
	var d := new_line(str(r.get("id", "line_%d" % (i + 1))), str(r.get("char", "")))
	d.text = str(r.get("text", ""))
	d.priority = int(r.get("priority", 0))
	for k in ["aff_min", "fat_min", "hp_min"]:
		d[k] = clampi(int(r.get(k, 0)), 0, 100)
	for k in ["aff_max", "fat_max", "hp_max"]:
		d[k] = clampi(int(r.get(k, 100)), 0, 100)
	d.status = str(r.get("status", STATUS_ANY))
	d.row = str(r.get("row", ""))
	d["with"] = str(r.get("with", ""))
	d.note = str(r.get("note", ""))
	return d


static func read(path: String = PATH) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var j: Variant = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary and j.get("lines") is Array):
		return []
	var out := []
	for r in j.lines:
		if r is Dictionary:
			out.append(_norm(r, out.size()))
	return out


static func write(lines: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "lines": lines}, "\t"))
	return OK


## 조건 상황 (게임·에디터 미리보기 공통)
## {char, name, affinity 0~100, fatigue 0~100, hp_pct 0~100, statuses [id…], row "front|middle|back", deployed [캐릭터 id…], names {id: 이름}}
static func make_context(char_id: String, name: String, affinity: float, fatigue: float, hp_pct: float, statuses: Array,
		row: int, deployed: Array, names: Dictionary = {}) -> Dictionary:
	return {"char": char_id, "name": name, "affinity": affinity, "fatigue": fatigue, "hp_pct": hp_pct, "statuses": statuses,
		"row": ROW_KEYS[clampi(row, 0, 2)], "deployed": deployed, "names": names}


static func matches(l: Dictionary, ctx: Dictionary) -> bool:
	if str(l.get("text", "")).strip_edges() == "":
		return false
	var c := str(l.get("char", ""))
	if c != "" and c != str(ctx.get("char", "")):
		return false
	if not _in(float(ctx.get("affinity", 50.0)), l.get("aff_min", 0), l.get("aff_max", 100)):
		return false
	if not _in(float(ctx.get("fatigue", 0.0)), l.get("fat_min", 0), l.get("fat_max", 100)):
		return false
	if not _in(float(ctx.get("hp_pct", 100.0)), l.get("hp_min", 0), l.get("hp_max", 100)):
		return false
	var sts: Array = ctx.get("statuses", [])
	match str(l.get("status", STATUS_ANY)):
		STATUS_ANY:
			pass
		STATUS_NONE:
			if not sts.is_empty():
				return false
		var sid:
			if not sts.has(sid):
				return false
	var row := str(l.get("row", ""))
	if row != "" and row != str(ctx.get("row", "")):
		return false
	var w := str(l.get("with", ""))
	if w != "" and (w == str(ctx.get("char", "")) or not (ctx.get("deployed", []) as Array).has(w)):
		return false
	return true


static func _in(v: float, lo: Variant, hi: Variant) -> bool:
	return v >= float(lo) - 0.001 and v <= float(hi) + 0.001


## 조건이 맞는 대사 전부, 고르는 순서대로 (우선순위 높은 것 → 전용 대사 → 파일 순서)
static func candidates(lines: Array, ctx: Dictionary) -> Array:
	var out := []
	for i in lines.size():
		if matches(lines[i], ctx):
			out.append({"line": lines[i], "order": i})
	out.sort_custom(func(a, b):
		var pa := int(a.line.get("priority", 0))
		var pb := int(b.line.get("priority", 0))
		if pa != pb:
			return pa > pb
		var sa := str(a.line.get("char", "")) != ""
		var sb := str(b.line.get("char", "")) != ""
		if sa != sb:
			return sa
		return int(a.order) < int(b.order))
	return out.map(func(x): return x.line)


## 하나 고르기: 맨 앞 묶음(우선순위·전용 여부가 같은 것들) 중 무작위. 없으면 {}
static func pick(lines: Array, ctx: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var c := candidates(lines, ctx)
	if c.is_empty():
		return {}
	var top: Array = c.filter(func(l): return int(l.get("priority", 0)) == int(c[0].get("priority", 0)) \
		and (str(l.get("char", "")) != "") == (str(c[0].get("char", "")) != ""))
	if rng == null:
		return top[randi() % top.size()]
	return top[rng.randi_range(0, top.size() - 1)]


static func format(text: String, l: Dictionary, ctx: Dictionary) -> String:
	var names: Dictionary = ctx.get("names", {})
	var w := str(l.get("with", ""))
	return text.replace("{name}", str(ctx.get("name", ""))).replace("{with}", str(names.get(w, w)))


## 조건 요약 (에디터 목록·검사용)
static func describe(l: Dictionary, status_names: Dictionary = {}, names: Dictionary = {}) -> String:
	var p := PackedStringArray()
	if int(l.get("aff_min", 0)) > 0 or int(l.get("aff_max", 100)) < 100:
		p.append("친밀도 %d~%d" % [int(l.aff_min), int(l.aff_max)])
	if int(l.get("fat_min", 0)) > 0 or int(l.get("fat_max", 100)) < 100:
		p.append("피로 %d~%d" % [int(l.fat_min), int(l.fat_max)])
	if int(l.get("hp_min", 0)) > 0 or int(l.get("hp_max", 100)) < 100:
		p.append("체력 %d~%d%%" % [int(l.hp_min), int(l.hp_max)])
	match str(l.get("status", "")):
		STATUS_ANY:
			pass
		STATUS_NONE:
			p.append("상태 이상 없음")
		var sid:
			p.append(str(status_names.get(sid, sid)))
	if str(l.get("row", "")) != "":
		p.append(str(ROW_NAMES.get(l.row, l.row)))
	if str(l.get("with", "")) != "":
		p.append("+%s" % names.get(l["with"], l["with"]))
	if int(l.get("priority", 0)) != 0:
		p.append("우선 %d" % int(l.priority))
	return "항상" if p.is_empty() else " · ".join(p)
