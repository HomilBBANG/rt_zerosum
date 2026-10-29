@tool
class_name StoryEdit
extends RefCounted
## 스토리 흐름 탭의 편집: 그래프의 "선"을 원본 데이터(퀘스트 · 컷씬 · 신 해금)로 옮겨 적음.
## 선 긋기 = link_options(두 노드) 로 가능한 뜻 목록 → apply_link / 선 지우기 = unlink(선의 src) / 노드 추가 · 삭제.
## 데이터 묶음 d = {"quests": QuestData.read(), "cutscenes": CutsceneData.read(), "divine": FaithData.read().divine} 를 그 자리에서 고침.
## 선의 src (StoryGraph 가 만듦): qstart(퀘스트 시작 조건) · qstep(퀘스트 단계 i) · ctrig(컷씬 계기) · cnext(다음 컷씬) · cchoice(선택지) · caction(행동) · dcond(해금 조건)


static func quest(d: Dictionary, id: String) -> Dictionary:
	for q in d.quests:
		if str(q.id) == id:
			return q
	return {}


static func cutscene(d: Dictionary, id: String) -> Dictionary:
	for c in d.cutscenes:
		if str(c.id) == id:
			return c
	return {}


## 노드 id "q:x" → ["q", "x"]
static func split(node: String) -> Array:
	return [node.substr(0, 1), node.substr(2)]


## 두 노드를 이을 때 고를 수 있는 뜻 [{id, label}] (빈 배열 = 이을 수 없음). from 이 먼저, to 가 나중
static func link_options(from: String, to: String, d: Dictionary) -> Array:
	var a := split(from)
	var b := split(to)
	var out := []
	match [a[0], b[0]]:
		["s", "q"]:
			var key: String = a[1]
			if key == "always":
				out.append({"id": "q_always", "label": "퀘스트를 처음부터 시작"})
			elif key == "manual":
				out.append({"id": "q_manual", "label": "퀘스트를 직접 시작 (스크립트 start_quest)"})
			elif key.begins_with("day:"):
				out.append({"id": "q_day", "label": "%s부터 퀘스트 시작" % key.substr(4) + "일차"})
		["s", "c"]:
			var key: String = a[1]
			if key == "new_game":
				out.append({"id": "c_new_game", "label": "새 게임 시작 때 재생 (오프닝)"})
			elif key.begins_with("day:"):
				out.append({"id": "c_day", "label": "%s일차 아침에 재생" % key.substr(4)})
			elif key.begins_with("talk:"):
				out.append({"id": "c_talk", "label": "그 대원에게 말 걸 때 재생"})
			elif key == "overhear":
				out.append({"id": "c_overhear", "label": "대원끼리 대화 엿들을 때 재생"})
			elif key == "battle_win":
				out.append({"id": "c_battle_win", "label": "전투 승리 때 재생"})
		["s", "d"]:
			var key: String = a[1]
			if key == "always":
				out.append({"id": "d_always", "label": "처음부터 해금"})
			elif key == "manual":
				out.append({"id": "d_manual", "label": "직접 해금 (컷씬 행동 · 스크립트)"})
			elif key.begins_with("day:"):
				out.append({"id": "d_day", "label": "%s일차부터 해금" % key.substr(4)})
		["q", "q"]:
			out.append({"id": "qq_start", "label": "'%s' 완료 후 '%s' 시작" % [_qn(d, a[1]), _qn(d, b[1])]})
			out.append({"id": "qq_step", "label": "'%s' 단계에 \"'%s' 완료\" 추가" % [_qn(d, b[1]), _qn(d, a[1])]})
		["q", "c"]:
			out.append({"id": "qc_start", "label": "퀘스트 시작 때 컷씬 재생"})
			out.append({"id": "qc_step", "label": "퀘스트 1단계 시작 때 재생 (단계 번호는 컷씬 탭에서)"})
			out.append({"id": "qc_done", "label": "퀘스트 완료 때 컷씬 재생"})
		["q", "d"]:
			out.append({"id": "qd_cond", "label": "퀘스트 완료 후 정체 해금"})
		["c", "c"]:
			var c := cutscene(d, a[1])
			out.append({"id": "cc_next", "label": "컷씬이 끝나면 다음 컷씬으로" + (" (지금 다음: %s 을 바꿈)" % c.next if str(c.get("next", "")) != "" else "")})
			out.append({"id": "cc_choice", "label": "선택지로 잇기 (새 선택지 추가%s)" % (", 선택지 컷이 없으면 만듦")})
		["c", "q"]:
			out.append({"id": "cq_action", "label": "컷씬 끝에 행동: 퀘스트 시작"})
			out.append({"id": "cq_start", "label": "이 컷씬을 본 뒤 퀘스트 시작 (시작 조건)"})
			out.append({"id": "cq_step", "label": "퀘스트 단계에 \"이 컷씬 보기\" 추가"})
		["c", "d"]:
			out.append({"id": "cd_action", "label": "컷씬 끝에 행동: 정체 해금"})
			out.append({"id": "cd_cond", "label": "이 컷씬을 본 뒤 해금 (해금 조건)"})
		["m", "q"]:
			out.append({"id": "mq_start", "label": "이 미션 완료 후 퀘스트 시작"})
			out.append({"id": "mq_step", "label": "퀘스트 단계에 이 미션 추가"})
		["m", "d"]:
			out.append({"id": "md_cond", "label": "이 미션 완료 후 정체 해금"})
	return out


static func _qn(d: Dictionary, id: String) -> String:
	var q := quest(d, id)
	return str(q.get("name", id)) if not q.is_empty() else id


## 고른 뜻으로 데이터를 고침 → "" (성공) 또는 안 되는 이유
static func apply_link(opt: String, from: String, to: String, d: Dictionary) -> String:
	var a := split(from)
	var b := split(to)
	var key: String = a[1]
	match opt:
		"q_always":
			quest(d, b[1]).start = {"type": "always", "value": 0, "target": ""}
		"q_manual":
			quest(d, b[1]).start = {"type": "manual", "value": 0, "target": ""}
		"q_day":
			quest(d, b[1]).start = {"type": "day", "value": int(key.substr(4)), "target": ""}
		"c_new_game":
			cutscene(d, b[1]).trigger = {"type": "new_game", "target": "", "value": 1}
		"c_day":
			cutscene(d, b[1]).trigger = {"type": "day", "target": "", "value": int(key.substr(4))}
		"c_talk":
			cutscene(d, b[1]).trigger = {"type": "talk", "target": key.substr(5), "value": 1}
		"c_overhear":
			cutscene(d, b[1]).trigger = {"type": "overhear", "target": "", "value": 1}
		"c_battle_win":
			cutscene(d, b[1]).trigger = {"type": "battle_win", "target": "", "value": 1}
		"d_always":
			_divine(d, b[1]).unlocked = true
		"d_manual":
			var dv := _divine(d, b[1])
			dv.unlocked = false
			dv.condition = {"type": "manual", "value": 0, "target": ""}
		"d_day":
			var dv := _divine(d, b[1])
			dv.unlocked = false
			dv.condition = {"type": "day", "value": int(key.substr(4)), "target": ""}
		"qq_start":
			quest(d, b[1]).start = {"type": "quest", "value": 0, "target": "quest:" + a[1]}
		"qq_step":
			_add_qstep(quest(d, b[1]), "quest", a[1])
		"qc_start", "qc_step", "qc_done":
			cutscene(d, b[1]).trigger = {"type": {"qc_start": "quest_start", "qc_step": "quest_step", "qc_done": "quest_done"}[opt], "target": a[1], "value": 1}
		"qd_cond":
			var dv := _divine(d, b[1])
			dv.unlocked = false
			dv.condition = {"type": "quest", "value": 0, "target": "quest:" + a[1]}
		"cc_next":
			if a[1] == b[1]:
				return "자기 자신으로는 못 잇습니다"
			cutscene(d, a[1]).next = b[1]
		"cc_choice":
			if a[1] == b[1]:
				return "자기 자신으로는 못 잇습니다"
			var c := cutscene(d, a[1])
			var ch: Dictionary = {}
			for st in c.steps:
				if str(st.type) == "choice":
					ch = st
			if ch.is_empty():
				ch = CutsceneData.new_step("choice")
				ch.options = []
				c.steps.append(ch)
			ch.options.append({"text": "선택지 %d" % (ch.options.size() + 1), "next": b[1]})
		"cq_action":
			var st := CutsceneData.new_step("action")
			st.do = "start_quest"
			st.target = b[1]
			cutscene(d, a[1]).steps.append(st)
		"cq_start":
			quest(d, b[1]).start = {"type": "quest", "value": 0, "target": "cutscene:" + a[1]}
		"cq_step":
			_add_qstep(quest(d, b[1]), "cutscene", a[1])
		"cd_action":
			var st := CutsceneData.new_step("action")
			st.do = "unlock_divine"
			st.target = b[1]
			cutscene(d, a[1]).steps.append(st)
		"cd_cond":
			var dv := _divine(d, b[1])
			dv.unlocked = false
			dv.condition = {"type": "quest", "value": 0, "target": "cutscene:" + a[1]}
		"mq_start":
			quest(d, b[1]).start = {"type": "quest", "value": 0, "target": key}
		"mq_step":
			var kind := key.split(":")[0]
			_add_qstep(quest(d, b[1]), kind, key.substr(kind.length() + 1))
		"md_cond":
			var dv := _divine(d, b[1])
			dv.unlocked = false
			dv.condition = {"type": "quest", "value": 0, "target": key}
		_:
			return "모르는 연결 '%s'" % opt
	return ""


static func _add_qstep(q: Dictionary, kind: String, target: String) -> void:
	var st := QuestData.new_step(kind)
	st.target = target
	q.steps.append(st)


static func _divine(d: Dictionary, cid: String) -> Dictionary:
	if not d.divine.has(cid):
		d.divine[cid] = FaithData.new_divine("")
	return d.divine[cid]


## 선 지우기: 그 선이 적힌 데이터를 되돌림 (시작 조건 → 직접, 계기 → 없음, 다음 → 비움, 선택지 next → 비움, 행동·단계 → 삭제, 해금 조건 → 직접)
static func unlink(src: Dictionary, d: Dictionary) -> String:
	match str(src.get("k", "")):
		"qstart":
			quest(d, src.q).start = {"type": "manual", "value": 0, "target": ""}
		"qstep":
			var q := quest(d, src.q)
			if int(src.i) < (q.steps as Array).size():
				q.steps.remove_at(int(src.i))
		"ctrig":
			cutscene(d, src.c).trigger = {"type": "none", "target": "", "value": 1}
		"cnext":
			cutscene(d, src.c).next = ""
		"cchoice":
			var c := cutscene(d, src.c)
			var st: Dictionary = c.steps[int(src.step)]
			st.options[int(src.opt)].next = ""
		"caction":
			var c := cutscene(d, src.c)
			c.steps.remove_at(int(src.step))
		"dcond":
			var dv := _divine(d, src.d)
			dv.unlocked = false
			dv.condition = {"type": "manual", "value": 0, "target": ""}
		_:
			return "지울 수 없는 선입니다"
	return ""


static func new_id(prefix: String, used: Array) -> String:
	var n := 1
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


static func add_quest(d: Dictionary) -> Dictionary:
	var q := QuestData.new_quest(new_id("q_new_", d.quests.map(func(x): return x.id)))
	q.start = {"type": "manual", "value": 0, "target": ""}
	q.steps = []
	d.quests.append(q)
	return q


static func add_cutscene(d: Dictionary) -> Dictionary:
	var c := CutsceneData.new_cutscene(new_id("cs_new_", d.cutscenes.map(func(x): return x.id)), "event")
	c.trigger = {"type": "none", "target": "", "value": 1}
	d.cutscenes.append(c)
	return c


## 퀘스트 삭제 + 가리키던 곳 정리 (시작 조건 → 직접, 단계 삭제, 컷씬 계기 → 없음, 행동 삭제, 해금 조건 → 직접)
static func remove_quest(d: Dictionary, id: String) -> void:
	d.quests = d.quests.filter(func(q): return str(q.id) != id)
	for q in d.quests:
		if str(q.start.get("target", "")) == "quest:" + id:
			q.start = {"type": "manual", "value": 0, "target": ""}
		q.steps = (q.steps as Array).filter(func(st): return not (str(st.kind) == "quest" and str(st.target) == id))
	for c in d.cutscenes:
		if str(c.trigger.type).begins_with("quest") and str(c.trigger.target) == id:
			c.trigger = {"type": "none", "target": "", "value": 1}
		c.steps = (c.steps as Array).filter(func(st): return not (str(st.type) == "action" and str(st.do) == "start_quest" and str(st.target) == id))
	for cid in d.divine:
		if str(d.divine[cid].condition.get("target", "")) == "quest:" + id:
			d.divine[cid].condition = {"type": "manual", "value": 0, "target": ""}


## 컷씬 삭제 + 가리키던 곳 정리 (다음 → 비움, 선택지 next → 비움, 시작 조건 · 단계 · 해금 조건)
static func remove_cutscene(d: Dictionary, id: String) -> void:
	d.cutscenes = d.cutscenes.filter(func(c): return str(c.id) != id)
	for c in d.cutscenes:
		if str(c.next) == id:
			c.next = ""
		for st in c.steps:
			if str(st.type) == "choice":
				for op in st.options:
					if str(op.next) == id:
						op.next = ""
	for q in d.quests:
		if str(q.start.get("target", "")) == "cutscene:" + id:
			q.start = {"type": "manual", "value": 0, "target": ""}
		q.steps = (q.steps as Array).filter(func(st): return not (str(st.kind) == "cutscene" and str(st.target) == id))
	for cid in d.divine:
		if str(d.divine[cid].condition.get("target", "")) == "cutscene:" + id:
			d.divine[cid].condition = {"type": "manual", "value": 0, "target": ""}
