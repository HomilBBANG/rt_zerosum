@tool
class_name StoryGraph
extends RefCounted
## 스토리 흐름 그래프 (Godot 에디터 '스토리' 탭): 퀘스트 · 컷씬 · 신 정체 해금 · 미션(의뢰·전투·연구) · 계기(새 게임 · n일차 · 말 걸기 …)를 노드로,
## "무엇이 무엇을 시작·이어 주는지"를 선으로. 데이터는 읽기만 (고치는 건 퀘스트 · 컷씬 · 기적 탭).
## 노드 = {id, kind(start|quest|cutscene|divine|mission), ref(원본 id), title, sub[줄], col, row, pos, size}
## 선 = {from, to, label}  (from 이 먼저 일어나고 → to)
## 선 규칙:
##   퀘스트 시작 조건: 처음부터/직접/n일차/의뢰인 조건 → 계기 노드, 미션 완료 → 그 미션(퀘스트·컷씬·의뢰·전투·연구) 노드에서
##   퀘스트 단계(퀘스트·컷씬·의뢰·전투·연구) → 그 노드에서 "n단계" / 퀘스트 → 컷씬 (계기 퀘스트 시작·단계·완료)
##   컷씬 → 다음 컷씬 · 선택지 컷씬 · 행동(퀘스트 시작 · 정체 해금) / 계기(새 게임 · n일차 · 말 걸기 · 엿듣기 · 전투 승리 · 정체 드러날 때) → 컷씬
##   신 정체 해금 조건 → 해금 노드

const KIND_NAME := {"start": "계기", "quest": "퀘스트", "cutscene": "컷씬", "divine": "신 정체 해금", "mission": "미션"}
const W := 210.0            # 노드 너비
const GAP_X := 140.0        # 열 사이 (선 위 글이 들어갈 자리)
const GAP_Y := 26.0         # 같은 열 노드 사이
const LINE_H := 17.0
const HEAD_H := 30.0

var nodes: Dictionary = {}   # id → 노드
var order: Array[String] = []   # 만든 순서
var edges: Array = []
var errors := PackedStringArray()
var notes := PackedStringArray()


## quests = QuestData.read(), cutscenes = CutsceneData.read(), divine = FaithData.read().divine,
## names = QuestData.target_names (kind:id → 이름), npc_names = npc id → 이름, char_names = 전투 캐릭터 id → 이름
func build(quests: Array, cutscenes: Array, divine: Dictionary, names: Dictionary = {}, npc_names: Dictionary = {}, char_names: Dictionary = {}) -> void:
	nodes.clear()
	order.clear()
	edges.clear()
	errors.clear()
	notes.clear()
	var qids := {}
	for q in quests:
		qids[str(q.id)] = q
	var cids := {}
	for c in cutscenes:
		cids[str(c.id)] = c
	# ---- 노드
	for q in quests:
		var sub: Array[String] = []
		for i in (q.steps as Array).size():
			sub.append("%d. %s" % [i + 1, QuestData.step_text(q.steps[i], names)])
		var rw: Dictionary = q.get("rewards", {})
		var rs := PackedStringArray()
		if int(rw.get("cash", 0)) > 0:
			rs.append("현금 %d" % int(rw.cash))
		if int(rw.get("affinity", 0)) != 0:
			rs.append("친밀도 %+d" % int(rw.affinity))
		if int(rw.get("faith", 0)) != 0:
			rs.append("신앙도 %+d" % int(rw.faith))
		if not rs.is_empty():
			sub.append("보상: " + " · ".join(rs))
		_add("q:" + str(q.id), "quest", str(q.id), str(q.name), sub)
	for c in cutscenes:
		var sub: Array[String] = []
		var n_say := 0
		var n_cg := 0
		var acts := PackedStringArray()
		for st in c.steps:
			match str(st.type):
				"say", "narration":
					n_say += 1
				"cg":
					n_cg += 1
				"action":
					if str(st.do) in ["affinity", "faith", "cash"]:
						acts.append("%s %s %+d" % [CutsceneData.ACTIONS.get(st.do, st.do).split(" ")[0], npc_names.get(st.target, st.target) if st.do != "cash" else "", int(st.value)])
		sub.append("%s · 대사 %d · CG %d%s" % [CutsceneData.KINDS.get(c.kind, c.kind), n_say, n_cg, " · 한 번만" if bool(c.get("once", true)) else ""])
		for a in acts:
			sub.append(a)
		_add("c:" + str(c.id), "cutscene", str(c.id), str(c.name), sub)
	for cid in divine:
		var dv: Dictionary = divine[cid]
		_add("d:" + str(cid), "divine", str(cid), "정체 해금: %s" % char_names.get(cid, cid), ["신: %s · 시작 의지 %d" % [str(dv.get("god", "")), int(dv.get("will", 0))]])
	# ---- 선
	for q in quests:
		var qn := "q:" + str(q.id)
		var sc: Dictionary = q.start
		match str(sc.type):
			"always":
				_edge(_start("always", "처음부터"), qn, "시작")
			"manual":
				_edge(_start("manual", "직접 (스크립트)"), qn, "start_quest")
			"day":
				_edge(_start("day:%d" % int(sc.value), "%d일차" % int(sc.value)), qn, "시작")
			"quest":
				var t := str(sc.get("target", ""))
				if t == "":
					errors.append("퀘스트 %s: 시작 조건 '미션 완료' 인데 미션이 없음" % q.name)
				else:
					_edge(_mission_node(t, qids, cids, names), qn, "완료 후 시작")
			_:
				_edge(_start("stat:" + str(q.id), UnlockCond.describe(sc, names) + " (의뢰인 %s)" % npc_names.get(q.giver, q.giver)), qn, "시작")
		for i in (q.steps as Array).size():
			var st: Dictionary = q.steps[i]
			var k := str(st.kind)
			var t := str(st.target)
			if k in ["quest", "cutscene", "contract", "research"] or (k == "stage" and t != ""):
				_edge(_mission_node(k + ":" + t, qids, cids, names), qn, "%d단계" % (i + 1))
	for c in cutscenes:
		var cn := "c:" + str(c.id)
		var tr: Dictionary = c.trigger
		var tt := str(tr.get("target", ""))
		match str(tr.type):
			"new_game":
				_edge(_start("new_game", "새 게임"), cn, "오프닝")
			"day":
				_edge(_start("day:%d" % int(tr.value), "%d일차" % int(tr.value)), cn, "아침")
			"talk":
				_edge(_start("talk:" + tt, "말 걸기: %s" % npc_names.get(tt, tt)), cn, "")
			"overhear":
				_edge(_start("overhear", "대원끼리 대화 엿듣기"), cn, "")
			"battle_win":
				_edge(_start("battle_win", "전투 승리"), cn, "")
			"quest_start":
				_link_quest(tt, cn, "시작 때", qids, c)
			"quest_step":
				_link_quest(tt, cn, "%d단계 시작 때" % int(tr.value), qids, c)
			"quest_done":
				_link_quest(tt, cn, "완료 때", qids, c)
			"divine":
				if tt != "" and divine.has(tt):
					_edge("d:" + tt, cn, "정체 드러날 때")
				elif tt != "":
					errors.append("컷씬 %s: 계기 '신의 정체' — 신 해금 캐릭터가 아닌 '%s'" % [c.name, tt])
				else:
					_edge(_start("divine_any", "누군가의 정체가 드러날 때"), cn, "")
		if str(c.next) != "":
			if cids.has(c.next):
				_edge(cn, "c:" + str(c.next), "다음")
			else:
				errors.append("컷씬 %s: 다음 컷씬 '%s' 없음" % [c.name, c.next])
		for st in c.steps:
			match str(st.type):
				"choice":
					for op in st.options:
						var nx := str(op.next)
						if nx == "":
							continue
						if cids.has(nx):
							_edge(cn, "c:" + nx, "선택: " + str(op.text))
						else:
							errors.append("컷씬 %s: 선택지 '%s' → 없는 컷씬 '%s'" % [c.name, op.text, nx])
				"action":
					if str(st.do) == "start_quest":
						if qids.has(st.target):
							_edge(cn, "q:" + str(st.target), "퀘스트 시작")
						else:
							errors.append("컷씬 %s: 행동 '퀘스트 시작' → 없는 퀘스트 '%s'" % [c.name, st.target])
					elif str(st.do) == "unlock_divine":
						if divine.has(st.target):
							_edge(cn, "d:" + str(st.target), "정체 해금")
						else:
							errors.append("컷씬 %s: 행동 '신 정체 해금' → 신 해금 캐릭터가 아닌 '%s'" % [c.name, st.target])
	for cid in divine:
		var dv: Dictionary = divine[cid]
		var dn := "d:" + str(cid)
		if bool(dv.get("unlocked", false)):
			_edge(_start("always", "처음부터"), dn, "해금")
			continue
		var cond: Dictionary = dv.get("condition", {})
		match str(cond.get("type", "manual")):
			"always":
				_edge(_start("always", "처음부터"), dn, "해금")
			"manual":
				pass   # 컷씬 행동 '정체 해금' 이 선을 그음 (없으면 아래 검사)
			"day":
				_edge(_start("day:%d" % int(cond.value), "%d일차" % int(cond.value)), dn, "해금")
			"quest":
				var t := str(cond.get("target", ""))
				if t != "":
					_edge(_mission_node(t, qids, cids, names), dn, "완료 후 해금")
			_:
				_edge(_start("stat:d:" + str(cid), UnlockCond.describe(cond, names)), dn, "해금")
	# ---- 검사
	for q in quests:
		if str(q.start.type) == "manual" and not _has_in("q:" + str(q.id), "퀘스트 시작"):
			notes.append("퀘스트 '%s': 직접 시작인데 어느 컷씬도 시작하지 않음 (스크립트에서 BaseSim.start_quest 를 불러야 함)" % q.name)
	for c in cutscenes:
		if str(c.trigger.type) == "none" and _in_edges("c:" + str(c.id)).is_empty():
			notes.append("컷씬 '%s': 계기 없음인데 어느 컷씬에서도 이어지지 않음 → 재생될 일이 없음" % c.name)
	for cid in divine:
		var dv: Dictionary = divine[cid]
		if not bool(dv.get("unlocked", false)) and str(dv.get("condition", {}).get("type", "")) == "manual" and _in_edges("d:" + str(cid)).is_empty():
			notes.append("신 정체 해금 '%s': 직접 해금인데 어느 컷씬도 해금하지 않음" % char_names.get(cid, cid))
	_layout()


func _add(id: String, kind: String, ref: String, title: String, sub: Array[String]) -> Dictionary:
	if nodes.has(id):
		return nodes[id]
	var n := {"id": id, "kind": kind, "ref": ref, "title": title, "sub": sub, "col": 0, "row": 0, "pos": Vector2.ZERO,
		"size": Vector2(W, HEAD_H + LINE_H * sub.size() + 10.0)}
	nodes[id] = n
	order.append(id)
	return n


func _start(key: String, title: String) -> String:
	var id := "s:" + key
	if not nodes.has(id):
		_add(id, "start", key, title, [])
	return id


## 미션 대상 "kind:id" → 그 노드 (퀘스트·컷씬이면 그 노드, 의뢰·전투·연구면 미션 노드)
func _mission_node(target: String, qids: Dictionary, cids: Dictionary, names: Dictionary) -> String:
	var kind := target.split(":")[0]
	var id := target.substr(kind.length() + 1)
	match kind:
		"quest":
			if qids.has(id):
				return "q:" + id
			errors.append("없는 퀘스트 '%s' 를 가리킴" % id)
			return _add("m:" + target, "mission", id, "없는 퀘스트: " + id, [] as Array[String]).id
		"cutscene":
			if cids.has(id):
				return "c:" + id
			errors.append("없는 컷씬 '%s' 를 가리킴" % id)
			return _add("m:" + target, "mission", id, "없는 컷씬: " + id, [] as Array[String]).id
	var nm: String = names.get(target, id)
	if kind == "stage" and id == "":
		nm = "아무 전투"
	return _add("m:" + target, "mission", id, "%s: %s" % [UnlockCond.MISSION_KINDS.get(kind, kind), nm], [] as Array[String]).id


func _link_quest(qid: String, cn: String, label: String, qids: Dictionary, c: Dictionary) -> void:
	if qids.has(qid):
		_edge("q:" + qid, cn, label)
	else:
		errors.append("컷씬 %s: 계기 퀘스트 '%s' 없음" % [c.name, qid])


func _edge(from: String, to: String, label: String) -> void:
	for e in edges:
		if e.from == from and e.to == to and e.label == label:
			return
	edges.append({"from": from, "to": to, "label": label})


func _in_edges(id: String) -> Array:
	return edges.filter(func(e): return e.to == id)


func out_edges(id: String) -> Array:
	return edges.filter(func(e): return e.from == id)


func in_edges(id: String) -> Array:
	return _in_edges(id)


func _has_in(id: String, label: String) -> bool:
	return edges.any(func(e): return e.to == id and e.label == label)


## 열 = 뿌리(계기)에서 가장 긴 경로 길이 (되돌아가는 선은 끊고 셈), 행 = 같은 열 안에서 만든 순서. 자리는 열마다 위에서부터 쌓음
func _layout() -> void:
	var depth := {}
	for id in order:
		depth[id] = 0
	var roots: Array[String] = []
	for id in order:
		if _in_edges(id).is_empty():
			roots.append(id)
	# 뿌리에서 깊이 우선 — 긴 경로가 이김 (순환은 방문 중인 노드로 돌아올 때 끊음)
	_cycle_hits = 0
	var visiting := {}
	for r in roots:
		_visit(r, 0, depth, visiting)
	if _cycle_hits > 0:
		notes.append("되돌아가는 흐름(순환)이 %d곳 — 선이 왼쪽으로 돌아감" % _cycle_hits)
	# 뿌리가 없는 섬(전부 순환)은 깊이 0 에 둠
	var cols := {}
	for id in order:
		var c := int(depth[id])
		nodes[id].col = c
		cols.get_or_add(c, []).append(id)
	var ks: Array = cols.keys()
	ks.sort()
	# 같은 열 안 순서: 앞 열에서 이어 주는 노드들의 평균 행에 가깝게 (선이 덜 엇갈리게), 같으면 만든 순서
	var row_of := {}
	for c in ks:
		var ids: Array = cols[c]
		var keyed := []
		for i in ids.size():
			var id: String = ids[i]
			var acc := 0.0
			var cnt := 0
			for e in _in_edges(id):
				if row_of.has(e.from):
					acc += float(row_of[e.from])
					cnt += 1
			keyed.append([acc / cnt if cnt > 0 else float(i), i, id])
		keyed.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		ids = keyed.map(func(k): return k[2])
		cols[c] = ids
		for i in ids.size():
			row_of[ids[i]] = i
	var x := 30.0
	for c in ks:
		var y := 30.0
		var row := 0
		for id in cols[c]:
			var n: Dictionary = nodes[id]
			n.row = row
			n.pos = Vector2(x, y)
			y += float(n.size.y) + GAP_Y
			row += 1
		x += W + GAP_X


var _cycle_hits := 0


func _visit(id: String, d: int, depth: Dictionary, visiting: Dictionary) -> void:
	if visiting.get(id, false):
		_cycle_hits += 1
		return
	if int(depth[id]) >= d and d > 0:
		return
	depth[id] = maxi(int(depth[id]), d)
	visiting[id] = true
	for e in out_edges(id):
		_visit(str(e.to), d + 1, depth, visiting)
	visiting.erase(id)


func bounds() -> Rect2:
	var r := Rect2(0, 0, 0, 0)
	var first := true
	for id in order:
		var n: Dictionary = nodes[id]
		var rr := Rect2(n.pos, n.size)
		r = rr if first else r.merge(rr)
		first = false
	return r
