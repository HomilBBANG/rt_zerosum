@tool
class_name SkillTable
extends RefCounted
## 스킬 표 data/skills.xlsx — 스킬 트리 · 신 · 신앙 스킬 · 믿는 신 · 신 해금 · 기적 · 스킬 상태 이상 · 상태 정의 · 몬스터 스킬 · 스킬 포즈의
## 수치 · 이름 · 설명을 엑셀에서 바로 고치는 표. **표가 원본**: 각 데이터의 read() 가 JSON 을 읽은 뒤 이 표의 값을 덮어 씀
## (SkillTreeData · FaithData · SkillStatusData · StatusCatalog · MonsterSkillData · SkillPoseData).
## - 고칠 수 있는 열 = 머리 줄이 진한 열. "(참고)" 열(회색)은 보기용 — 고쳐도 무시.
## - 줄은 id(열 이름 '… id')로 찾음 → 열 순서를 바꾸거나 열을 더 붙여도 됨. 표에 없는 id 의 줄은 무시 (추가 · 삭제 · 선행 잇기 · 자리 = 에디터).
## - 숫자 칸을 비우면 원래 값 그대로, 글자 칸은 비우면 빈 글자 (효과 칸은 비우면 그대로).
## - 게임 실행 중 저장하면 1초 안에 다시 읽음 (Game._process). 에디터 '스킬 트리' 탭도 바뀐 걸 바로 읽음.
## - 에디터에서 저장하면 이 표도 같이 다시 씀 (엑셀에 열려 있으면 저장 못 함 → 닫고 다시).
## 전투 스킬(AP · 위력 · 대상)은 data/balance.xlsx '스킬' 시트.

const PATH := "res://data/skills.xlsx"
const REF := "(참고) "

static var _cache_mtime := -1
static var _cache: Dictionary = {}


## 표 시트들 {시트 이름: [[셀…]…]} — 파일이 바뀌지 않았으면 기억해 둔 것 (없으면 {})
static func sheets() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var mt := FileAccess.get_modified_time(PATH)
	if mt != _cache_mtime:
		var d := XlsxReader.read(PATH)
		if d.is_empty():
			return _cache   # 저장 중 · 잠김 — 전에 읽은 것
		_cache = d
		_cache_mtime = mt
	return _cache


static func mtime() -> int:
	return FileAccess.get_modified_time(PATH) if FileAccess.file_exists(PATH) else 0


## 테스트용: 파일 대신 이 시트들을 표로 씀 (파일이 바뀌거나 clear_cache 까지)
static func use_sheets(d: Dictionary) -> void:
	_cache = d
	_cache_mtime = mtime()


static func clear_cache() -> void:
	_cache_mtime = -1
	_cache = {}


# ================================================================ 표 → 데이터 (덮어쓰기)
## 시트의 줄을 key 로 찾아 fields {머리 줄: [필드, 종류]} 를 덮어씀. 종류 int · text · code(빈 칸 = 그대로) · color. 바뀐 칸 수
static func _apply(rows: Array, key_head: String, by_key: Dictionary, fields: Dictionary, key2_head: String = "") -> int:
	if rows.size() < 2:
		return 0
	var col := {}
	var head: Array = rows[0]
	for i in head.size():
		col[str(head[i]).strip_edges()] = i
	if not col.has(key_head) or (key2_head != "" and not col.has(key2_head)):
		return 0
	var n := 0
	for r in rows.slice(1):
		var key := _cell(r, col[key_head])
		if key2_head != "":
			key += "|" + _cell(r, col[key2_head])
		if key == "" or not by_key.has(key):
			continue
		var e: Dictionary = by_key[key]
		for h in fields:
			if not col.has(h):
				continue
			var f: String = fields[h][0]
			var kind: String = fields[h][1]
			var raw := _cell(r, col[h])
			var v: Variant
			match kind:
				"int":
					if raw == "" or not raw.is_valid_float():
						continue
					v = roundi(raw.to_float())
				"code":
					if raw == "":
						continue
					v = raw
				_:
					v = raw
			if str(e.get(f, "")) != str(v):
				e[f] = v
				n += 1
	return n


static func _cell(r: Array, i: int) -> String:
	return str(r[i]).strip_edges() if i < r.size() else ""


static func _index(arr: Array, key: String = "id") -> Dictionary:
	var out := {}
	for e in arr:
		out[str(e.get(key, ""))] = e
	return out


static func apply_tree(nodes: Array) -> int:
	return _apply(sheets().get("스킬 트리", []), "노드 id", _index(nodes),
		{"이름": ["name", "text"], "필요 레벨": ["level", "int"], "효과": ["effect", "code"], "값": ["value", "int"], "설명": ["desc", "text"], "택일 그룹": ["group", "text"]})


static func apply_faith(d: Dictionary) -> int:
	var t := sheets()
	if t.is_empty():
		return 0
	var n := 0
	n += _apply(t.get("신", []), "신 id", _index(d.get("gods", [])), {"이름": ["name", "text"], "색": ["color", "code"], "설명": ["desc", "text"]})
	n += _apply(t.get("신앙 스킬", []), "스킬 id", _index(d.get("skills", [])),
		{"이름": ["name", "text"], "필요 신앙도": ["need", "int"], "효과": ["effect", "code"], "값": ["value", "int"], "설명": ["desc", "text"]})
	n += _apply(t.get("기적", []), "기적 id", _index(d.get("miracles", [])),
		{"이름": ["name", "text"], "필요 의지": ["need", "int"], "효과": ["effect", "code"], "값": ["value", "int"], "설명": ["desc", "text"]})
	var bl: Dictionary = d.get("believers", {})
	n += _apply(t.get("믿는 신", []), "대원 id", bl, {"신 id": ["god", "text"], "시작 신앙도": ["faith", "int"]})
	n += _apply(t.get("신 해금", []), "캐릭터 id", d.get("divine", {}), {"시작 의지": ["will", "int"]})
	return n


static func apply_skill_status(entries: Array) -> int:
	var by := {}
	for e in entries:
		by["%s|%s" % [e.skill, e.status]] = e
	return _apply(sheets().get("스킬 상태 이상", []), "스킬 id", by, {"턴": ["turns", "int"], "수치": ["value", "int"], "확률 %": ["chance", "int"]}, "상태 id")


static func apply_statuses(defs: Array) -> int:
	return _apply(sheets().get("상태 정의", []), "상태 id", _index(defs),
		{"이름": ["name", "text"], "머리 위 글자": ["short", "text"], "색": ["color", "code"], "설명": ["desc", "text"]})


static func apply_monster(d: Dictionary) -> int:
	return _apply(sheets().get("몬스터 스킬", []), "스킬 id", _index(d.get("skills", [])),
		{"이름": ["name", "text"], "AP": ["ap", "int"], "위력": ["power", "int"], "명중 %": ["accuracy", "int"], "설명": ["desc", "text"]})


## 스킬 포즈: table = {스킬 id: 포즈} — 표에 줄이 있는 스킬은 그 칸 (빈 칸 = 자동 → 지움)
static func apply_poses(table: Dictionary) -> int:
	var rows: Array = sheets().get("스킬 포즈", [])
	if rows.size() < 2:
		return 0
	var head: Array = rows[0]
	var ki := head.find("스킬 id")
	var pi := head.find("포즈")
	if ki < 0 or pi < 0:
		return 0
	var n := 0
	for r in rows.slice(1):
		var sid := _cell(r, ki)
		if sid == "":
			continue
		var p := _cell(r, pi)
		if p == "(자동)":
			p = ""
		if str(table.get(sid, "")) != p:
			if p == "":
				table.erase(sid)
			else:
				table[sid] = p
			n += 1
	return n


# ================================================================ 데이터 → 표 (에디터 저장 · 처음 만들 때)
## data = {nodes, faith, sstat, sdefs, mdata, spose} (없는 것은 파일에서 — 표를 덮기 전 값)
static func write(data: Dictionary = {}, path: String = PATH) -> int:
	var err := XlsxWriter.write(path, build(data))
	if err == OK and path == PATH:
		clear_cache()
	return err


static func build(data: Dictionary = {}) -> Array:
	var nodes: Array = data.get("nodes", SkillTreeData.read())
	var faith: Dictionary = data.get("faith", FaithData.read())
	var sstat: Array = data.get("sstat", SkillStatusData.read())
	var sdefs: Array = data.get("sdefs", StatusCatalog.read())
	var mdata: Dictionary = data.get("mdata", MonsterSkillData.read())
	var spose: Dictionary = data.get("spose", SkillPoseData.read())
	var gd := GameData.load_from()
	var allies: Array = gd.allies if gd != null else []
	var actions: Dictionary = gd.actions if gd != null else {}
	var monsters: Dictionary = gd.monsters if gd != null else {}
	var od := OutgameData.load_from()
	var names := QuestData.target_names(od, gd, QuestData.read()) if gd != null else {}
	var cname := {}
	for u in allies:
		cname[u.id] = u.display_name
	var gname := {}
	for g in faith.get("gods", []):
		gname[str(g.id)] = str(g.name)
	var sname := {}
	for s in sdefs:
		sname[str(s.id)] = str(s.name)
	var users := _users(allies, nodes, mdata, monsters, cname)
	var mskill := _index(mdata.get("skills", []))
	var out := []

	out.append({"name": "읽어보기", "header": false, "widths": [26, 100], "rows": [
		["스킬 표 (data/skills.xlsx)", "스킬 수치 · 이름 · 설명을 여기서 고치고 저장하면 게임 · 에디터에 바로 들어갑니다."],
		["", ""],
		["고칠 수 있는 열", "머리 줄이 진한 회색인 열. 숫자 칸을 비우면 원래 값 그대로."],
		["(참고) 열", "머리 줄이 연하고 글자가 회색인 열 — 보기용, 고쳐도 무시됩니다."],
		["줄 찾기", "'… id' 열로 찾습니다. id 는 바꾸지 마세요. 열 순서를 바꾸거나 메모 열을 더 붙여도 됩니다."],
		["추가 · 삭제 · 연결", "새 스킬 · 노드 추가, 삭제, 선행 잇기, 트리 모양은 Godot 에디터 '스킬 트리' 탭에서 (표에 새 id 줄을 넣어도 무시)."],
		["실시간 반영", "게임 실행 중에 저장하면 1초 안에 다시 읽습니다. 에디터 '스킬 트리' 탭도 바로 다시 읽습니다."],
		["에디터에서 저장하면", "이 표도 에디터 값으로 다시 써집니다. 엑셀에 열어 둔 채 에디터에서 저장하면 실패하니 닫고 저장하세요. 표에 직접 넣은 서식 · 수식은 그때 사라집니다."],
		["효과 칸", "hp · speed · ap · ap_rec · defense · accuracy · evasion · power · heal · skill_power:<스킬 id> · skill:<스킬 id>"],
		["전투 스킬 (AP · 위력 · 대상)", "data/balance.xlsx '스킬' 시트"],
	]})

	var by_id := _index(nodes)
	var rows := [["노드 id", REF + "캐릭터", REF + "트리", REF + "갈래", REF + "시작", REF + "선행", "이름", "필요 레벨", "효과", "값", "설명", "택일 그룹", REF + "효과 뜻"]]
	for n in SkillTreeData.sorted(nodes):
		var req := PackedStringArray()
		for r in n.get("req", []):
			req.append(str(by_id[str(r)].name) if by_id.has(str(r)) else str(r))
		var joined := ("모두: " if bool(n.get("req_all", false)) and req.size() > 1 else "") + ", ".join(req)
		rows.append([str(n.id), cname.get(n.char, n.char), SkillTreeData.KIND_NAME.get(n.kind, n.kind), SkillTreeData.BRANCH_NAME.get(n.branch, n.branch),
			"시작" if bool(n.get("start", false)) else "", joined, str(n.name), int(n.get("level", 0)), str(n.effect), int(n.get("value", 0)),
			str(n.get("desc", "")), str(n.get("group", "")), SkillTreeData.auto_desc(str(n.effect), int(n.get("value", 0)), actions)])
	out.append({"name": "스킬 트리", "rows": rows, "ref_cols": [1, 2, 3, 4, 5, 12]})

	var believers: Dictionary = faith.get("believers", {})
	rows = [["신 id", "이름", "색", "설명", REF + "믿는 대원"]]
	for g in faith.get("gods", []):
		var who := PackedStringArray()
		for c in believers:
			if str(believers[c].get("god", "")) == str(g.id):
				who.append(str(cname.get(c, c)))
		rows.append([str(g.id), str(g.name), str(g.get("color", "")), str(g.get("desc", "")), ", ".join(who)])
	out.append({"name": "신", "rows": rows, "ref_cols": [4]})

	rows = [["스킬 id", REF + "신", "이름", "필요 신앙도", "효과", "값", "설명", REF + "효과 뜻"]]
	var fsk: Array = (faith.get("skills", []) as Array).duplicate()
	fsk.sort_custom(func(a, b): return [str(a.god), int(a.need)] < [str(b.god), int(b.need)])
	for s in fsk:
		rows.append([str(s.id), gname.get(str(s.god), str(s.god)), str(s.name), int(s.need), str(s.effect), int(s.get("value", 0)), str(s.get("desc", "")),
			SkillTreeData.auto_desc(str(s.effect), int(s.get("value", 0)), actions)])
	out.append({"name": "신앙 스킬", "rows": rows, "ref_cols": [1, 7]})

	rows = [["대원 id", REF + "대원", "신 id", REF + "신 이름", "시작 신앙도"]]
	for c in believers:
		var g := str(believers[c].get("god", ""))
		rows.append([str(c), cname.get(c, c), g, gname.get(g, "(믿음 없음)" if g == "" else g), int(believers[c].get("faith", 0))])
	out.append({"name": "믿는 신", "rows": rows, "ref_cols": [1, 3]})

	rows = [["캐릭터 id", REF + "캐릭터", REF + "정체인 신", REF + "해금", "시작 의지"]]
	var divine: Dictionary = faith.get("divine", {})
	for c in divine:
		var dv: Dictionary = divine[c]
		rows.append([str(c), cname.get(c, c), str(dv.get("god", "")),
			"처음부터" if bool(dv.get("unlocked", false)) else UnlockCond.describe(dv.get("condition", {}), names), int(dv.get("will", 0))])
	out.append({"name": "신 해금", "rows": rows, "ref_cols": [1, 2, 3]})

	rows = [["기적 id", REF + "캐릭터", "이름", "필요 의지", "효과", "값", "설명", REF + "효과 뜻"]]
	var mir: Array = (faith.get("miracles", []) as Array).duplicate()
	mir.sort_custom(func(a, b): return [str(a.char), int(a.need)] < [str(b.char), int(b.need)])
	for m in mir:
		rows.append([str(m.id), cname.get(str(m.char), str(m.char)), str(m.name), int(m.need), str(m.effect), int(m.get("value", 0)), str(m.get("desc", "")),
			SkillTreeData.auto_desc(str(m.effect), int(m.get("value", 0)), actions)])
	out.append({"name": "기적", "rows": rows, "ref_cols": [1, 7]})

	rows = [["스킬 id", "상태 id", REF + "스킬", REF + "쓰는 쪽", REF + "상태", "턴", "수치", "확률 %"]]
	for e in sstat:
		var sid := str(e.skill)
		rows.append([sid, str(e.status), _skill_name(sid, actions, mskill), ", ".join(users.get(sid, [])), sname.get(str(e.status), str(e.status)),
			int(e.get("turns", 0)), int(e.get("value", 0)), int(e.get("chance", 100))])
	out.append({"name": "스킬 상태 이상", "rows": rows, "ref_cols": [2, 3, 4]})

	rows = [["상태 id", REF + "효과(규칙)", "이름", "머리 위 글자", "색", "설명", REF + "수치 뜻", REF + "규칙"]]
	for s in sdefs:
		var ef: Dictionary = StatusCatalog.EFFECTS.get(str(s.effect), {})
		rows.append([str(s.id), "%s (%s)" % [ef.get("name", s.effect), "좋음" if bool(ef.get("positive", false)) else "나쁨"], str(s.name), str(s.get("short", "")),
			str(s.get("color", "")), str(s.get("desc", "")), str(ef.get("hint", "")), str(ef.get("desc", "")).replace("{v}", "N").replace("{t}", "T")])
	out.append({"name": "상태 정의", "rows": rows, "ref_cols": [1, 6, 7]})

	rows = [["스킬 id", REF + "종류", REF + "대상", REF + "효과", "이름", "AP", "위력", "명중 %", "설명", REF + "쓰는 몬스터"]]
	for s in mdata.get("skills", []):
		rows.append([str(s.id), MonsterSkillData.KINDS.get(str(s.kind), str(s.kind)), MonsterSkillData.TARGETS.get(str(s.target), str(s.target)),
			MonsterSkillData.EFFECTS.get(str(s.effect), str(s.effect)), str(s.name), int(s.get("ap", 0)), int(s.get("power", 0)), int(s.get("accuracy", 100)),
			str(s.get("desc", "")), ", ".join(users.get(str(s.id), []))])
	out.append({"name": "몬스터 스킬", "rows": rows, "ref_cols": [1, 2, 3, 9]})

	rows = [["스킬 id", REF + "스킬", REF + "쓰는 쪽", "포즈", REF + "자동이면", REF + "포즈 이름 (shot · slash · point_up · hit · miss · stun · tired · none = 포즈 안 씀 …)"]]
	var sids: Array = actions.keys()
	sids.sort()
	for sid in sids:
		var a: ActionData = actions[sid]
		if a.effect in ["move", "weapon_swap"]:
			continue
		var p := str(spose.get(sid, ""))
		var auto := SkillPoseData.auto_for(a)
		rows.append([str(sid), a.display_name, ", ".join(users.get(str(sid), [])), p if p != "" else "(자동)",
			SkillPoseData.pose_name(auto) if auto != "" else "", "포즈 안 씀" if p == SkillPoseData.NONE else (SkillPoseData.pose_name(p) if p != "" else "")])
	out.append({"name": "스킬 포즈", "rows": rows, "ref_cols": [1, 2, 4, 5]})
	return out


static func _users(allies: Array, nodes: Array, mdata: Dictionary, monsters: Dictionary, cname: Dictionary) -> Dictionary:
	var users := {}
	for u in allies:
		for sid in u.skill_ids:
			_add_user(users, sid, u.display_name)
	for n in nodes:
		if str(n.effect).begins_with("skill:"):
			_add_user(users, str(n.effect).substr(6), "%s (트리)" % cname.get(n.char, n.char))
	var kits: Dictionary = mdata.get("kits", {})
	for mid in kits:
		for sid in kits[mid]:
			_add_user(users, str(sid), monsters[mid].display_name if monsters.has(mid) else str(mid))
	return users


static func _add_user(users: Dictionary, sid: String, who: String) -> void:
	if not users.has(sid):
		users[sid] = []
	if not (users[sid] as Array).has(who):
		users[sid].append(who)


static func _skill_name(sid: String, actions: Dictionary, mskill: Dictionary) -> String:
	if actions.has(sid):
		return (actions[sid] as ActionData).display_name
	return str(mskill[sid].name) if mskill.has(sid) else sid
