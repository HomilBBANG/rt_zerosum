@tool
class_name CutsceneData
extends RefCounted
## 컷씬 (data/cutscenes.json, Godot 에디터 상단 '컷씬' 탭에서 편집). 재생은 CutscenePlayer, 언제 나오는지는 BaseSim (계기 trigger → 대기열).
## 컷씬 = {id, name, kind(분류), trigger{type, target, value}, once(한 번만), next(끝나면 이어질 컷씬 id), steps[컷]}
## 컷 종류: say 대사(말하는 대원 · 표시 이름 · 왼쪽/오른쪽 서기) / narration 나레이션 / cg 이미지 CG(image "" = 끄기, 글은 아래 상자) /
##   bg 배경(image "" = 기지 화면 어둡게) / choice 선택지(고른 것의 next 컷씬으로 이어짐, "" = 끝) / action 행동(퀘스트 시작 · 신 정체 해금 · 친밀도 · 현금)
## 이어지기: 컷씬 끝 → next, 선택지 → 그 선택지의 next. 이어진 컷씬도 '본 컷씬' 으로 기록 (퀘스트 단계 '컷씬 보기', 미션 'cutscene:id').
## 이미지는 assets/cg/ 의 PNG (1280x720 권장, 원본 PNG 를 바로 읽어서 임포트 전에 넣어도 보임).

const PATH := "res://data/cutscenes.json"
const CG_DIR := "res://assets/cg"
const KINDS := {"opening": "오프닝", "talk": "대화", "event": "이벤트", "quest": "퀘스트", "other": "기타"}
const KIND_ORDER := ["opening", "talk", "event", "quest", "other"]
const TRIGGERS := {"none": "없음 (이어지기·직접 재생만)", "new_game": "새 게임 시작", "quest_start": "퀘스트 시작", "quest_step": "퀘스트 단계 시작",
	"quest_done": "퀘스트 완료", "talk": "지휘관이 대원에게 말 걸기", "overhear": "대원끼리 대화 엿듣기", "day": "n일차 아침", "divine": "신의 정체가 드러날 때", "battle_win": "전투 승리"}
const TRIGGER_ORDER := ["none", "new_game", "quest_start", "quest_step", "quest_done", "talk", "overhear", "day", "divine", "battle_win"]
const STEP_TYPES := {"say": "대사", "narration": "나레이션", "cg": "CG", "bg": "배경", "choice": "선택지", "action": "행동"}
const STEP_ORDER := ["say", "narration", "cg", "bg", "choice", "action"]
const ACTIONS := {"start_quest": "퀘스트 시작", "unlock_divine": "신 정체 해금", "affinity": "대원 친밀도 +/-", "cash": "현금 (주간 결산 때)"}
const ACTION_ORDER := ["start_quest", "unlock_divine", "affinity", "cash"]
const SIDES := {"left": "왼쪽", "right": "오른쪽"}

static var _img_cache: Dictionary = {}


static func new_cutscene(id: String, kind: String = "event") -> Dictionary:
	return {"id": id, "name": "새 컷씬", "kind": kind if KINDS.has(kind) else "event", "trigger": {"type": "new_game" if kind == "opening" else "none", "target": "", "value": 1},
		"once": true, "next": "", "steps": [new_step("narration")]}


static func new_step(t: String) -> Dictionary:
	match t:
		"say":
			return {"type": "say", "speaker": "", "name": "", "side": "left", "text": "…"}
		"cg":
			return {"type": "cg", "image": "", "text": ""}
		"bg":
			return {"type": "bg", "image": ""}
		"choice":
			return {"type": "choice", "text": "어떻게 할까?", "options": [{"text": "선택지 1", "next": ""}, {"text": "선택지 2", "next": ""}]}
		"action":
			return {"type": "action", "do": "start_quest", "target": "", "value": 0}
	return {"type": "narration", "text": "…"}


static func norm_step(st: Dictionary) -> Dictionary:
	var t := str(st.get("type", "narration"))
	if not STEP_TYPES.has(t):
		t = "narration"
	var o := new_step(t)
	match t:
		"say":
			o.speaker = str(st.get("speaker", ""))
			o.name = str(st.get("name", ""))
			o.side = "right" if str(st.get("side", "left")) == "right" else "left"
			o.text = str(st.get("text", ""))
		"narration":
			o.text = str(st.get("text", ""))
		"cg":
			o.image = str(st.get("image", ""))
			o.text = str(st.get("text", ""))
		"bg":
			o.image = str(st.get("image", ""))
		"choice":
			o.text = str(st.get("text", ""))
			var opts := []
			for op in st.get("options", []):
				if op is Dictionary:
					opts.append({"text": str(op.get("text", "")), "next": str(op.get("next", ""))})
			o.options = opts
		"action":
			o.do = str(st.get("do", "start_quest")) if ACTIONS.has(str(st.get("do", ""))) else "start_quest"
			o.target = str(st.get("target", ""))
			o.value = int(st.get("value", 0))
	return o


static func read(path: String = PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary and j.get("cutscenes") is Array):
		return []
	var out := []
	for c in j.cutscenes:
		if not c is Dictionary:
			continue
		var tr: Dictionary = c.get("trigger", {}) if c.get("trigger") is Dictionary else {}
		var tt := str(tr.get("type", "none"))
		var steps := []
		for st in c.get("steps", []):
			if st is Dictionary:
				steps.append(norm_step(st))
		out.append({"id": str(c.get("id", "")), "name": str(c.get("name", "")), "kind": str(c.get("kind", "event")) if KINDS.has(str(c.get("kind", ""))) else "other",
			"trigger": {"type": tt if TRIGGERS.has(tt) else "none", "target": str(tr.get("target", "")), "value": maxi(1, int(tr.get("value", 1)))},
			"once": bool(c.get("once", true)), "next": str(c.get("next", "")), "steps": steps})
	return out


static func write(cuts: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "cutscenes": cuts}, "\t", false))
	return OK


static func by_id(cuts: Array) -> Dictionary:
	var out := {}
	for c in cuts:
		out[c.id] = c
	return out


## 계기 설명 ("퀘스트 '하나의 비밀' 완료", "3일차 아침"). names = "quest:id"/"npc:id"/"conv:id"/"stage:id"/"char:id" → 이름
static func trigger_text(c: Dictionary, names: Dictionary = {}) -> String:
	var t: Dictionary = c.trigger
	var tg := str(t.get("target", ""))
	match str(t.type):
		"none":
			return "이어지기·직접 재생"
		"new_game":
			return "새 게임 시작"
		"quest_start":
			return "퀘스트 '%s' 시작" % names.get("quest:" + tg, tg)
		"quest_step":
			return "퀘스트 '%s' %d단계 시작" % [names.get("quest:" + tg, tg), int(t.value)]
		"quest_done":
			return "퀘스트 '%s' 완료" % names.get("quest:" + tg, tg)
		"talk":
			return "%s 에게 말 걸기" % names.get("npc:" + tg, tg)
		"overhear":
			return "대화 '%s' 엿듣기" % names.get("conv:" + tg, tg)
		"day":
			return "%d일차 아침" % int(t.value)
		"divine":
			return "%s 정체 해금" % names.get("char:" + tg, tg)
		"battle_win":
			return "전투 '%s' 승리" % names.get("stage:" + tg, tg) if tg != "" else "아무 전투 승리"
	return str(t.type)


## 컷 한 줄 요약 (목록·흐름용). npc_names = 대원 id → 이름
static func step_text(st: Dictionary, npc_names: Dictionary = {}) -> String:
	match str(st.type):
		"say":
			var who := str(st.name) if str(st.name) != "" else str(npc_names.get(st.speaker, st.speaker))
			return "%s: %s" % [who if who != "" else "?", st.text]
		"narration":
			return "(나레이션) %s" % st.text
		"cg":
			return "[CG] %s%s" % [str(st.image).get_file() if str(st.image) != "" else "끄기", "  — " + str(st.text) if str(st.text) != "" else ""]
		"bg":
			return "[배경] %s" % (str(st.image).get_file() if str(st.image) != "" else "기지 화면 (어둡게)")
		"choice":
			return "[선택지] %s — %s" % [st.text, " / ".join(PackedStringArray((st.options as Array).map(func(o): return "%s → %s" % [o.text, o.next if str(o.next) != "" else "끝"])))]
		"action":
			return "[행동] %s %s%s" % [ACTIONS.get(st.do, st.do), st.target, " %+d" % int(st.value) if st.do in ["affinity", "cash"] else ""]
	return str(st.type)


## assets/cg 의 PNG 목록 (res:// 경로)
static func images() -> Array:
	var out := []
	var d := DirAccess.open(CG_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() == "png":
			out.append(CG_DIR.path_join(f))
	out.sort()
	return out


## 원본 PNG 를 바로 읽음 (임포트 전에 넣은 그림도). 없으면 null
static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _img_cache.has(path):
		return _img_cache[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		tex = load(path)
	_img_cache[path] = tex
	return tex


static func clear_cache() -> void:
	_img_cache.clear()


## 이 컷씬으로 이어지는 곳 [[컷씬 id, "다음" | "선택지 '…'"]]
static func incoming(cuts: Array, id: String) -> Array:
	var out := []
	for c in cuts:
		if c.next == id and id != "":
			out.append([c.id, "다음"])
		for st in c.steps:
			if st.type == "choice":
				for op in st.options:
					if op.next == id and id != "":
						out.append([c.id, "선택지 '%s'" % op.text])
	return out


## 검사 → {errors, notes}. npcs = OutgameData.npcs, quests = 퀘스트 목록, convs = 대화이벤트 id 목록, divine = 신 해금 캐릭터 id 목록
static func check(cuts: Array, npcs: Dictionary, quests: Array, convs: Array = [], divine: Array = []) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var ids := by_id(cuts)
	var seen := {}
	var qids := quests.map(func(q): return q.id)
	for c in cuts:
		if str(c.id) == "":
			errors.append("id 가 빈 컷씬이 있습니다")
		elif seen.has(c.id):
			errors.append("컷씬 id '%s' 가 두 번 있습니다" % c.id)
		seen[c.id] = true
	var openings := 0
	for c in cuts:
		var where := "%s(%s)" % [c.name, c.id]
		if (c.steps as Array).is_empty():
			errors.append("%s: 컷이 없습니다" % where)
		if str(c.next) != "" and not ids.has(c.next):
			errors.append("%s: 다음 컷씬 '%s' 가 없습니다" % [where, c.next])
		if str(c.next) == c.id:
			errors.append("%s: 다음 컷씬이 자기 자신" % where)
		var t: Dictionary = c.trigger
		var tg := str(t.target)
		match str(t.type):
			"quest_start", "quest_step", "quest_done":
				if not qids.has(tg):
					errors.append("%s: 계기 퀘스트 '%s' 가 없습니다" % [where, tg])
				elif t.type == "quest_step":
					var q: Dictionary = quests[qids.find(tg)]
					if int(t.value) > (q.steps as Array).size():
						errors.append("%s: 퀘스트 '%s' 는 %d단계까지" % [where, q.name, (q.steps as Array).size()])
			"talk":
				if not npcs.has(tg):
					errors.append("%s: 계기 대원 '%s' 가 없습니다" % [where, tg])
			"overhear":
				if not convs.has(tg):
					errors.append("%s: 계기 대화이벤트 '%s' 가 없습니다" % [where, tg])
			"divine":
				if not divine.has(tg):
					errors.append("%s: '%s' 는 신 해금 캐릭터가 아닙니다" % [where, tg])
			"new_game":
				openings += 1
			"none":
				if incoming(cuts, c.id).is_empty():
					notes.append("%s: 계기가 없고 이어지는 컷씬도 없음 — 행동·스크립트에서 BaseSim.queue_cutscene('%s') 로만 재생" % [where, c.id])
		if t.type in ["talk", "overhear"] and not bool(c.once):
			notes.append("%s: 매번 재생 — 그 대원·대화의 평소 대사 대신 계속 나옴" % where)
		for i in (c.steps as Array).size():
			var st: Dictionary = c.steps[i]
			var w := "%s %d번 컷" % [where, i + 1]
			match str(st.type):
				"say":
					if str(st.speaker) != "" and not npcs.has(st.speaker):
						errors.append("%s: 없는 대원 '%s'" % [w, st.speaker])
					if str(st.speaker) == "" and str(st.name) == "":
						errors.append("%s: 말하는 사람이 없습니다 (대원 또는 표시 이름)" % w)
				"cg", "bg":
					if str(st.image) != "" and not FileAccess.file_exists(st.image) and not ResourceLoader.exists(st.image):
						errors.append("%s: 그림 '%s' 가 없습니다" % [w, st.image])
				"choice":
					if (st.options as Array).is_empty():
						errors.append("%s: 선택지가 없습니다" % w)
					for op in st.options:
						if str(op.next) != "" and not ids.has(op.next):
							errors.append("%s: 선택지 '%s' 의 컷씬 '%s' 가 없습니다" % [w, op.text, op.next])
					if i < (c.steps as Array).size() - 1:
						notes.append("%s: 선택지 뒤의 컷은 선택지가 '끝' 일 때만 이어서 나옴" % w)
				"action":
					match str(st.do):
						"start_quest":
							if not qids.has(st.target):
								errors.append("%s: 없는 퀘스트 '%s'" % [w, st.target])
						"unlock_divine":
							if not divine.has(st.target):
								errors.append("%s: '%s' 는 신 해금 캐릭터가 아닙니다" % [w, st.target])
						"affinity":
							if not npcs.has(st.target):
								errors.append("%s: 없는 대원 '%s'" % [w, st.target])
	if openings > 1:
		notes.append("새 게임 시작 컷씬이 %d개 — 목록 순서대로 모두 재생" % openings)
	return {"errors": errors, "notes": notes}
