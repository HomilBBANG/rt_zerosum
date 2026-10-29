@tool
class_name SkillExport
extends RefCounted
## 스킬 트리 에디터 내용 → 엑셀 한 파일 (보기 · 공유용, 이 파일을 고쳐도 게임에는 안 들어감 — 고치는 건 Godot 에디터 '스킬 트리' 탭).
## 시트: 읽어보기 · 스킬 트리 · 신 · 신앙 스킬 · 믿는 신 · 신 해금 · 기적 · 스킬 상태 이상 · 상태 정의 · 몬스터 스킬 · 몬스터 기술 묶음 · 스킬 포즈 · 무기별 포즈.
## export(path) = 파일에서 읽어 씀 / export(path, data) = 에디터가 편집 중인 데이터로 씀
##   data = {nodes, faith, sstat, sdefs, mdata, spose, wpose} (없는 것은 파일에서)
## 명령줄: godot --headless --path . -s tools/export_skills_xlsx.gd [출력.xlsx]

const DEFAULT_PATH := "res://exports/skills.xlsx"


static func export(path: String = DEFAULT_PATH, data: Dictionary = {}) -> int:
	return XlsxWriter.write(path, build(data))


static func build(data: Dictionary = {}) -> Array:
	var nodes: Array = data.get("nodes", SkillTreeData.read())
	var faith: Dictionary = data.get("faith", FaithData.read())
	var sstat: Array = data.get("sstat", SkillStatusData.read())
	var sdefs: Array = data.get("sdefs", StatusCatalog.read())
	var mdata: Dictionary = data.get("mdata", MonsterSkillData.read())
	var spose: Dictionary = data.get("spose", SkillPoseData.read())
	var wpose: Dictionary = data.get("wpose", SkillPoseData.read_weapons())
	var gd := GameData.load_from()
	var od := OutgameData.load_from()
	var allies: Array = gd.allies if gd != null else []
	var actions: Dictionary = gd.actions if gd != null else {}
	var monsters: Dictionary = gd.monsters if gd != null else {}
	var cname := {}
	for u in allies:
		cname[u.id] = u.display_name
	var gname := {}
	for g in faith.get("gods", []):
		gname[str(g.id)] = str(g.name)
	var sname := {}
	for s in sdefs:
		sname[str(s.id)] = str(s.name)
	var names := QuestData.target_names(od, gd, QuestData.read()) if gd != null else {}
	var sheets := []

	# ---- 읽어보기
	sheets.append({"name": "읽어보기", "header": false, "widths": [22, 90], "rows": [
		["스킬 트리 에디터 내보내기", Time.get_datetime_string_from_system(false, true)],
		["", ""],
		["이 파일은 보기 · 공유용입니다.", "고쳐도 게임에 들어가지 않습니다 — 고치는 곳은 Godot 에디터 상단 '스킬 트리' 탭 (저장하면 data/*.json)."],
		["다시 뽑기", "스킬 트리 탭 위 '엑셀로 내보내기' 버튼, 또는 godot --headless --path . -s tools/export_skills_xlsx.gd"],
		["", ""],
		["스킬 트리", "대원마다 액티브 · 패시브 트리 노드 (data/skill_tree.json)"],
		["신 · 신앙 스킬 · 믿는 신", "신 목록 · 신마다 신앙도로 배우는 스킬 · 대원별 믿는 신과 시작 신앙도 (data/faith.json)"],
		["신 해금 · 기적", "정체가 신인 캐릭터 · 해금 조건 · 시작 의지 · 그 캐릭터만의 기적 (data/faith.json divine · miracles)"],
		["스킬 상태 이상", "전투 스킬에 달린 상태 이상 — 턴 · 수치 · 확률 (data/skill_status.json)"],
		["상태 정의", "상태 이상 이름 · 머리 위 글자 · 색 · 쓰는 효과(규칙) (data/statuses.json)"],
		["몬스터 스킬 · 기술 묶음", "몬스터 전용 스킬과 몬스터마다 쓰는 스킬 (data/monster_skills.json)"],
		["스킬 포즈 · 무기별 포즈", "스킬을 쓸 때 쓰는 쪽 포즈 그림, 캐릭터 · 무기별 공격 그림 (data/skill_poses.json)"],
		["", ""],
		["전투 스킬 수치(AP · 위력 · 대상)", "엑셀 data/balance.xlsx '스킬' 시트"],
	]})

	# ---- 스킬 트리
	var by_id := {}
	for n in nodes:
		by_id[str(n.id)] = n
	var tree := [["캐릭터", "캐릭터 id", "트리", "노드 id", "이름", "갈래", "시작 노드", "필요 레벨", "선행", "선행 조건", "택일 그룹", "효과", "효과 뜻", "값", "설명", "칸 x", "칸 y"]]
	for n in SkillTreeData.sorted(nodes):
		var req := PackedStringArray()
		for r in n.get("req", []):
			req.append("%s (%s)" % [str(by_id[str(r)].name), r] if by_id.has(str(r)) else str(r))
		tree.append([cname.get(n.char, n.char), str(n.char), SkillTreeData.KIND_NAME.get(n.kind, n.kind), str(n.id), str(n.name),
			SkillTreeData.BRANCH_NAME.get(n.branch, n.branch), "시작" if bool(n.get("start", false)) else "", int(n.get("level", 0)),
			"\n".join(req), ("모두" if bool(n.get("req_all", false)) else "하나라도") if req.size() > 1 else "", str(n.get("group", "")),
			str(n.effect), SkillTreeData.auto_desc(str(n.effect), int(n.get("value", 0)), actions), int(n.get("value", 0)), str(n.get("desc", "")),
			int(n.get("x", 0)), int(n.get("y", 0))])
	sheets.append({"name": "스킬 트리", "rows": tree})

	# ---- 신
	var believers: Dictionary = faith.get("believers", {})
	var gods := [["신 id", "이름", "색", "기호", "아이콘 그림", "설명", "믿는 대원", "신앙 스킬 수"]]
	var bg := FaithData.by_god(faith)
	for g in faith.get("gods", []):
		var who := PackedStringArray()
		for c in believers:
			if str(believers[c].get("god", "")) == str(g.id):
				who.append(str(cname.get(c, c)))
		gods.append([str(g.id), str(g.name), str(g.get("color", "")), str(g.get("symbol", "")), str(g.get("icon", "")), str(g.get("desc", "")),
			", ".join(who), (bg.get(str(g.id), []) as Array).size()])
	sheets.append({"name": "신", "rows": gods})

	# ---- 신앙 스킬
	var fs := [["신", "신 id", "스킬 id", "이름", "필요 신앙도", "효과", "효과 뜻", "값", "설명"]]
	var fsk: Array = (faith.get("skills", []) as Array).duplicate()
	fsk.sort_custom(func(a, b): return [str(a.god), int(a.need)] < [str(b.god), int(b.need)])
	for s in fsk:
		fs.append([gname.get(str(s.god), str(s.god)), str(s.god), str(s.id), str(s.name), int(s.need), str(s.effect),
			SkillTreeData.auto_desc(str(s.effect), int(s.get("value", 0)), actions), int(s.get("value", 0)), str(s.get("desc", ""))])
	sheets.append({"name": "신앙 스킬", "rows": fs})

	# ---- 믿는 신
	var bl := [["대원", "대원 id", "믿는 신", "신 id", "시작 신앙도"]]
	for u in allies:
		var b: Dictionary = believers.get(u.id, {})
		var g := str(b.get("god", ""))
		bl.append([u.display_name, u.id, gname.get(g, g) if g != "" else "(믿음 없음)", g, int(b.get("faith", 0))])
	sheets.append({"name": "믿는 신", "rows": bl})

	# ---- 신 해금
	var dv := [["캐릭터", "캐릭터 id", "정체인 신", "처음부터 해금", "해금 조건", "조건 (원본)", "시작 의지"]]
	var divine: Dictionary = faith.get("divine", {})
	for c in divine:
		var d: Dictionary = divine[c]
		var cond: Dictionary = d.get("condition", {})
		dv.append([cname.get(c, c), str(c), str(d.get("god", "")), "예" if bool(d.get("unlocked", false)) else "",
			"" if bool(d.get("unlocked", false)) else UnlockCond.describe(cond, names), JSON.stringify(cond), int(d.get("will", 0))])
	sheets.append({"name": "신 해금", "rows": dv})

	# ---- 기적
	var mr := [["캐릭터", "캐릭터 id", "기적 id", "이름", "필요 의지", "효과", "효과 뜻", "값", "설명"]]
	var mir: Array = (faith.get("miracles", []) as Array).duplicate()
	mir.sort_custom(func(a, b): return [str(a.char), int(a.need)] < [str(b.char), int(b.need)])
	for m in mir:
		mr.append([cname.get(str(m.char), str(m.char)), str(m.char), str(m.id), str(m.name), int(m.need), str(m.effect),
			SkillTreeData.auto_desc(str(m.effect), int(m.get("value", 0)), actions), int(m.get("value", 0)), str(m.get("desc", ""))])
	sheets.append({"name": "기적", "rows": mr})

	# ---- 누가 쓰는 스킬인지 (대원 기본 스킬 · 스킬 트리 새 스킬 · 몬스터 기술 묶음)
	var users := {}
	for u in allies:
		for sid in u.skill_ids:
			_add_user(users, sid, u.display_name)
	for n in nodes:
		if str(n.effect).begins_with("skill:"):
			_add_user(users, str(n.effect).substr(6), "%s (트리)" % cname.get(n.char, n.char))
	var kits: Dictionary = mdata.get("kits", {})
	for mid in kits:
		var mn: String = monsters[mid].display_name if monsters.has(mid) else str(mid)
		for sid in kits[mid]:
			_add_user(users, str(sid), mn)
	var mskill_name := {}
	for s in mdata.get("skills", []):
		mskill_name[str(s.id)] = str(s.name)

	# ---- 스킬 상태 이상
	var ss := [["스킬 id", "스킬 이름", "쓰는 쪽", "상태 id", "상태 이름", "턴", "수치", "확률 %", "요약"]]
	for e in sstat:
		var sid := str(e.skill)
		ss.append([sid, _skill_name(sid, actions, mskill_name), ", ".join(users.get(sid, [])), str(e.status), sname.get(str(e.status), str(e.status)),
			int(e.get("turns", 0)), int(e.get("value", 0)), int(e.get("chance", 100)), SkillStatusData.summary(e)])
	sheets.append({"name": "스킬 상태 이상", "rows": ss})

	# ---- 상태 정의
	var sd := [["상태 id", "이름", "효과(규칙)", "효과 이름", "좋은/나쁜", "머리 위 글자", "색", "수치 뜻", "규칙 설명", "설명"]]
	for s in sdefs:
		var ef: Dictionary = StatusCatalog.EFFECTS.get(str(s.effect), {})
		sd.append([str(s.id), str(s.name), str(s.effect), str(ef.get("name", "")), ("좋음" if bool(ef.get("positive", false)) else "나쁨") if not ef.is_empty() else "",
			str(s.get("short", "")), str(s.get("color", "")), str(ef.get("hint", "")), str(ef.get("desc", "")).replace("{v}", "N").replace("{t}", "T"), str(s.get("desc", ""))])
	sheets.append({"name": "상태 정의", "rows": sd})

	# ---- 몬스터 스킬
	var ms := [["스킬 id", "이름", "종류", "AP", "대상", "효과", "위력", "명중 %", "쓰는 몬스터", "설명"]]
	for s in mdata.get("skills", []):
		ms.append([str(s.id), str(s.name), MonsterSkillData.KINDS.get(str(s.kind), str(s.kind)), int(s.get("ap", 0)),
			MonsterSkillData.TARGETS.get(str(s.target), str(s.target)), MonsterSkillData.EFFECTS.get(str(s.effect), str(s.effect)),
			int(s.get("power", 0)), int(s.get("accuracy", 100)), ", ".join(users.get(str(s.id), [])), str(s.get("desc", ""))])
	sheets.append({"name": "몬스터 스킬", "rows": ms})
	var mk := [["몬스터", "몬스터 id", "쓰는 스킬 (순서대로)"]]
	for mid in kits:
		var lst := PackedStringArray()
		for sid in kits[mid]:
			lst.append("%s (%s)" % [_skill_name(str(sid), actions, mskill_name), sid])
		mk.append([monsters[mid].display_name if monsters.has(mid) else str(mid), str(mid), "\n".join(lst)])
	sheets.append({"name": "몬스터 기술 묶음", "rows": mk})

	# ---- 스킬 포즈
	var sp := [["스킬 id", "스킬 이름", "쓰는 쪽", "포즈", "포즈 이름", "자동이면"]]
	var sids: Array = actions.keys()
	sids.sort()
	for sid in sids:
		var a: ActionData = actions[sid]
		if a.effect in ["move", "weapon_swap"]:
			continue
		var p := str(spose.get(sid, ""))
		var auto := SkillPoseData.auto_for(a)
		sp.append([str(sid), a.display_name, ", ".join(users.get(str(sid), [])), p if p != "" else "(자동)",
			"포즈 안 씀 (예전 공격 동작)" if p == SkillPoseData.NONE else (SkillPoseData.pose_name(p) if p != "" else ""),
			SkillPoseData.pose_name(auto) if auto != "" else ""])
	sheets.append({"name": "스킬 포즈", "rows": sp})
	var wp := [["캐릭터 스프라이트", "캐릭터", "무기 스프라이트", "공격 포즈", "포즈 이름"]]
	var spr_name := {}
	for u in allies:
		spr_name[u.sprite_id] = u.display_name
	for c in wpose:
		for w in wpose[c]:
			wp.append([str(c), spr_name.get(c, ""), str(w), str(wpose[c][w]), SkillPoseData.pose_name(str(wpose[c][w]))])
	sheets.append({"name": "무기별 포즈", "rows": wp})
	return sheets


static func _add_user(users: Dictionary, sid: String, who: String) -> void:
	if not users.has(sid):
		users[sid] = []
	if not (users[sid] as Array).has(who):
		users[sid].append(who)


static func _skill_name(sid: String, actions: Dictionary, mskill: Dictionary) -> String:
	if actions.has(sid):
		return (actions[sid] as ActionData).display_name
	return str(mskill.get(sid, sid))
