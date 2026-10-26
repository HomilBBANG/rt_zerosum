@tool
class_name OutgameData
extends RefCounted
## 아웃게임(기지) 데이터: data/outgame.xlsx + data/outgame/schedules/<대원 id>.json.
## 시트: 설정 · 층 · 시설 · 대원 · 의뢰 · 대사 · 대화이벤트 · 요청 · 제작 · 오브젝트 · PX. 모든 값은 프로토타입 임시값/더미.
## 전투 발생 규칙: data/outgame/battle_rules.json (Godot 에디터 '전투 발생' 탭).
## 기지 단면 좌표(시설 사각형·바닥선)도 여기서 계산한다 — 게임 화면과 Godot 에디터 '일정' 탭이 같이 쓴다.

const PATH := "res://data/outgame.xlsx"
const SCHED_DIR := "res://data/outgame/schedules"
const RULES_PATH := "res://data/outgame/battle_rules.json"
const OBJECT_KINDS := ["침대", "소파", "의자", "의무침대"]
const CELL_W := 240.0      # 시설 한 칸 폭 (px)
const FLOOR_H := 220.0     # 층 높이 (px)
const FLOOR_SLAB := 22.0   # 바닥 두께 — 대원 발은 방 아래쪽에서 이만큼 위
const ACTIVITIES := {"sleep": "수면", "rest": "휴식", "eat": "식사", "work": "업무", "train": "훈련", "chat": "잡담", "idle": "대기"}
## 대원끼리 대화가 생길 수 있는 활동 (자거나 일하는 중에는 안 함)
const CHAT_ACTIVITIES := ["rest", "eat", "chat", "idle"]
const WEEKDAYS := ["월", "화", "수", "목", "금", "토", "일"]

var settings: Dictionary = {}       # id → 문자열 값
var floors: Array = []              # [{id, name, order}] 순서대로
var facilities: Dictionary = {}     # id → {id, name, floor, order, col, width, cost, initial_open, tag, cleanable, light, desc}
var facility_order: Array[String] = []
var npcs: Dictionary = {}           # id → {id, name, character_id, sprite, height_cm, start, talk, desc}
var npc_order: Array[String] = []
var jobs: Dictionary = {}           # id → {id, name, kind(task|external), reward, minutes, place, repeat, initial, desc}
var job_order: Array[String] = []
var dialogues: Dictionary = {}      # id → [{speaker, text}]
var conversations: Array = []       # [{id, a, b, place, dialogue, story, max, priority, start_day}]
var requests: Dictionary = {}       # id → {id, npc, start_day, dialogue, accept_dialogue, effect, desc}
var request_order: Array[String] = []
var recipes: Dictionary = {}        # id → {id, name, item, minutes, desc}
var recipe_order: Array[String] = []
var objects: Dictionary = {}        # id → {id, facility, kind, x(방 폭 비율), height(m), fatigue_rate, hp_rate, desc}
var object_order: Array[String] = []
var px_items: Dictionary = {}       # id → {id, name, price, affinity, liked: [npc id], desc}
var px_order: Array[String] = []
var battle_rules: Array = []        # [{id, name, enabled, mode, interval_minutes, anchor, weekdays, start_day, times, date, stages, allow_skip, note}]
var schedules: Dictionary = {}      # npc id → {npc_id, preferred_facility_ids, weekly_schedule, delegation_rules}
var warnings: PackedStringArray = []


static func load_from(path: String = PATH) -> OutgameData:
	var sheets := XlsxReader.read(path)
	if sheets.is_empty():
		return null
	var d := OutgameData.new()
	d._parse(sheets)
	d.load_schedules()
	d.battle_rules = read_battle_rules()
	d._validate()
	return d


# ---------------------------------------------------------------- 파싱
static func _ox(v: Variant) -> bool:
	return str(v).strip_edges().to_upper() in ["O", "Y", "YES", "TRUE", "1", "예"]


func _parse(sheets: Dictionary) -> void:
	for r in GameData._table(sheets.get("설정", [])):
		settings[r.id] = str(r.get("값", "")).strip_edges()
	for r in GameData._table(sheets.get("층", [])):
		floors.append({"id": r.id, "name": r.get("이름", r.id), "order": GameData._i(r, "순서", floors.size())})
	floors.sort_custom(func(a, b): return a.order < b.order)
	for r in GameData._table(sheets.get("시설", [])):
		var fl := str(r.get("층", ""))
		var f := {"id": r.id, "name": r.get("이름", r.id), "floor": fl, "order": floor_order(fl),
			"col": GameData._i(r, "칸"), "width": maxi(1, GameData._i(r, "폭", 1)), "cost": GameData._i(r, "해금비용"),
			"initial_open": _ox(r.get("초기해금", "X")), "tag": str(r.get("기능", "")).strip_edges(),
			"cleanable": _ox(r.get("청소", "X")), "light": r.get("조명", "g1") if r.get("조명", "") != "" else "g1",
			"desc": r.get("설명", "")}
		facilities[r.id] = f
		facility_order.append(r.id)
	for r in GameData._table(sheets.get("대원", [])):
		npcs[r.id] = {"id": r.id, "name": r.get("이름", r.id), "character_id": r.get("전투캐릭터", ""),
			"sprite": r.get("스프라이트", ""), "height_cm": GameData._f(r, "키(cm)", 175.0),
			"start": r.get("시작장소", ""), "talk": r.get("대사", ""), "desc": r.get("설명", "")}
		npc_order.append(r.id)
	for r in GameData._table(sheets.get("의뢰", [])):
		jobs[r.id] = {"id": r.id, "name": r.get("이름", r.id), "kind": "external" if str(r.get("종류", "")).strip_edges() == "외부의뢰" else "task",
			"reward": GameData._i(r, "보상"), "minutes": maxi(1, GameData._i(r, "소요(분)", 60)), "place": r.get("장소", ""),
			"repeat": _ox(r.get("반복", "O")), "initial": _ox(r.get("처음부터", "O")), "desc": r.get("설명", "")}
		job_order.append(r.id)
	var lines: Dictionary = {}
	for r in GameData._table(sheets.get("대사", [])):
		if not lines.has(r.id):
			lines[r.id] = []
		lines[r.id].append({"order": GameData._f(r, "순서", lines[r.id].size()), "speaker": str(r.get("화자", "")), "text": str(r.get("내용", ""))})
	for id in lines:
		var arr: Array = lines[id]
		arr.sort_custom(func(a, b): return a.order < b.order)
		dialogues[id] = arr.map(func(e): return {"speaker": e.speaker, "text": e.text})
	for r in GameData._table(sheets.get("대화이벤트", [])):
		conversations.append({"id": r.id, "a": r.get("대원1", ""), "b": r.get("대원2", ""), "place": r.get("장소", ""),
			"dialogue": r.get("대사", ""), "story": r.get("스토리", ""), "max": GameData._i(r, "최대횟수", 1),
			"priority": GameData._i(r, "우선순위"), "start_day": r.get("시작일", "")})
	conversations.sort_custom(func(a, b): return a.priority > b.priority)
	for r in GameData._table(sheets.get("요청", [])):
		requests[r.id] = {"id": r.id, "npc": r.get("대원", ""), "start_day": r.get("시작일", ""), "dialogue": r.get("대사", ""),
			"accept_dialogue": r.get("수락대사", ""), "effect": str(r.get("수락효과", "")).strip_edges(), "desc": r.get("설명", "")}
		request_order.append(r.id)
	for r in GameData._table(sheets.get("오브젝트", [])):
		objects[r.id] = {"id": r.id, "facility": r.get("시설", ""), "kind": str(r.get("종류", "의자")).strip_edges(),
			"x": clampf(GameData._f(r, "위치", 0.5), 0.0, 1.0), "height": GameData._f(r, "높이", 0.5),
			"fatigue_rate": GameData._f(r, "피로회복", 0.0), "hp_rate": GameData._f(r, "체력회복", 0.0), "desc": r.get("설명", "")}
		object_order.append(r.id)
	for r in GameData._table(sheets.get("PX", [])):
		px_items[r.id] = {"id": r.id, "name": r.get("이름", r.id), "price": GameData._i(r, "가격"), "affinity": GameData._i(r, "친밀도"),
			"liked": GameData._list(r, "좋아하는 대원"), "desc": r.get("설명", "")}
		px_order.append(r.id)
	for r in GameData._table(sheets.get("제작", [])):
		recipes[r.id] = {"id": r.id, "name": r.get("이름", r.id), "item": r.get("결과무기", ""),
			"minutes": maxi(1, GameData._i(r, "소요(분)", 60)), "desc": r.get("설명", "")}
		recipe_order.append(r.id)


func _validate() -> void:
	for id in facility_order:
		if floor_order(facilities[id].floor) < 0:
			warnings.append("시설 %s: 층 시트에 없는 층 '%s'" % [id, facilities[id].floor])
	for id in npc_order:
		if not facilities.has(npcs[id].start):
			warnings.append("대원 %s: 시설 시트에 없는 시작장소 '%s'" % [id, npcs[id].start])
		if not dialogues.has(npcs[id].talk):
			warnings.append("대원 %s: 대사 시트에 없는 대사 '%s'" % [id, npcs[id].talk])
	for id in job_order:
		if not facilities.has(jobs[id].place):
			warnings.append("의뢰 %s: 시설 시트에 없는 장소 '%s'" % [id, jobs[id].place])
	for c in conversations:
		for k in ["a", "b"]:
			if not npcs.has(c[k]):
				warnings.append("대화이벤트 %s: 대원 시트에 없는 '%s'" % [c.id, c[k]])
		if not dialogues.has(c.dialogue):
			warnings.append("대화이벤트 %s: 대사 시트에 없는 '%s'" % [c.id, c.dialogue])
	for id in object_order:
		if not facilities.has(objects[id].facility):
			warnings.append("오브젝트 %s: 시설 시트에 없는 '%s'" % [id, objects[id].facility])
	for r in battle_rules:
		for st in r.get("stages", []):
			if str(st) == "":
				warnings.append("전투 발생 %s: 빈 스테이지" % r.get("id", ""))
	for id in request_order:
		var q: Dictionary = requests[id]
		if not npcs.has(q.npc):
			warnings.append("요청 %s: 대원 시트에 없는 '%s'" % [id, q.npc])
		if q.effect.begins_with("의뢰:") and not jobs.has(q.effect.substr(3).strip_edges()):
			warnings.append("요청 %s: 의뢰 시트에 없는 '%s'" % [id, q.effect.substr(3)])


# ---------------------------------------------------------------- 설정값
func num(key: String, def: float) -> float:
	var v := str(settings.get(key, ""))
	return float(v) if v.is_valid_float() else def


func inum(key: String, def: int) -> int:
	return int(roundf(num(key, def)))


func text(key: String, def: String) -> String:
	var v := str(settings.get(key, ""))
	return v if v != "" else def


## "HH:MM" → 분
static func parse_hm(s: String, def: int = 0) -> int:
	var p := s.strip_edges().split(":")
	if p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int():
		return clampi(int(p[0]) * 60 + int(p[1]), 0, 1439)
	return def


static func hm(minute: int) -> String:
	return "%02d:%02d" % [floori(minute / 60.0), minute % 60]


# ---------------------------------------------------------------- 단면 좌표
func floor_order(floor_id: String) -> int:
	for f in floors:
		if f.id == floor_id:
			return f.order
	return -1


func floor_name(floor_id: String) -> String:
	for f in floors:
		if f.id == floor_id:
			return f.name
	return floor_id


func facility_rect(fid: String) -> Rect2:
	var f: Dictionary = facilities.get(fid, {})
	if f.is_empty():
		return Rect2()
	return Rect2(f.col * CELL_W, f.order * FLOOR_H, f.width * CELL_W, FLOOR_H)


## 그 시설 안에서 대원 발이 닿는 높이
func floor_line(fid: String) -> float:
	var r := facility_rect(fid)
	return r.end.y - FLOOR_SLAB


func facility_center_x(fid: String) -> float:
	var r := facility_rect(fid)
	return r.position.x + r.size.x * 0.5


func base_rect() -> Rect2:
	var out := Rect2()
	var first := true
	for id in facility_order:
		var r := facility_rect(id)
		out = r if first else out.merge(r)
		first = false
	return out


## 월드 좌표가 속한 시설 (없으면 "")
func facility_at(p: Vector2) -> String:
	for id in facility_order:
		if facility_rect(id).has_point(p):
			return id
	return ""


func facilities_with_tag(tag: String) -> Array[String]:
	var out: Array[String] = []
	for id in facility_order:
		if facilities[id].tag == tag:
			out.append(id)
	return out


func objects_in(fid: String) -> Array[String]:
	var out: Array[String] = []
	for id in object_order:
		if objects[id].facility == fid:
			out.append(id)
	return out


## 오브젝트의 시뮬레이션 x (px)
func object_x(oid: String) -> float:
	var o: Dictionary = objects.get(oid, {})
	var r := facility_rect(str(o.get("facility", "")))
	return r.position.x + 30.0 + float(o.get("x", 0.5)) * (r.size.x - 60.0)


func npc_name(id: String) -> String:
	return str(npcs.get(id, {}).get("name", id))


func facility_name(id: String) -> String:
	var f: Dictionary = facilities.get(id, {})
	if f.is_empty():
		return id
	return "%s %s" % [floor_name(f.floor), f.name] if f.tag == "계단" else str(f.name)


# ---------------------------------------------------------------- 주간 일정 파일
static func schedule_path(npc_id: String) -> String:
	return "%s/%s.json" % [SCHED_DIR, npc_id]


func load_schedules() -> void:
	schedules.clear()
	for id in npc_order:
		schedules[id] = read_schedule(id)


static func read_schedule(npc_id: String) -> Dictionary:
	var out := {"npc_id": npc_id, "preferred_facility_ids": [], "weekly_schedule": [], "delegation_rules": {"can_delegate_cleaning": false}}
	var f := FileAccess.open(schedule_path(npc_id), FileAccess.READ)
	if f == null:
		return out
	var j: Variant = JSON.parse_string(f.get_as_text())
	if j is Dictionary:
		for k in j:
			out[k] = j[k]
	for b in out.weekly_schedule:   # JSON 숫자는 float → 정수로
		for k in ["weekday", "start_minute", "end_minute"]:
			b[k] = int(b.get(k, 0))
	return out


static func write_schedule(npc_id: String, sched: Dictionary) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCHED_DIR))
	var f := FileAccess.open(schedule_path(npc_id), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(sched, "\t"))
	return OK


# ---------------------------------------------------------------- 전투 발생 규칙 파일
static func read_battle_rules() -> Array:
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return []
	var j: Variant = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary and j.get("rules") is Array):
		return []
	var out := []
	for r in j.rules:
		if not r is Dictionary:
			continue
		var d := {"id": str(r.get("id", "rule_%d" % out.size())), "name": str(r.get("name", "")), "enabled": bool(r.get("enabled", true)),
			"mode": str(r.get("mode", "interval")), "interval_minutes": maxi(10, int(r.get("interval_minutes", 360))),
			"anchor": str(r.get("anchor", "00:00")), "weekdays": (r.get("weekdays", [0, 1, 2, 3, 4, 5, 6]) as Array).map(func(x): return int(x)),
			"start_day": str(r.get("start_day", "")), "times": (r.get("times", []) as Array).map(func(x): return str(x)),
			"date": str(r.get("date", "")), "stages": (r.get("stages", []) as Array).map(func(x): return str(x)),
			"allow_skip": bool(r.get("allow_skip", false)), "note": str(r.get("note", ""))}
		out.append(d)
	return out


static func write_battle_rules(rules: Array) -> int:
	var f := FileAccess.open(RULES_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"rules": rules}, "\t"))
	return OK


## 일정·전투 규칙 파일들의 가장 최근 수정 시각 (실행 중 에디터 저장 감지용)
func schedules_mtime() -> int:
	var t := FileAccess.get_modified_time(RULES_PATH)
	for id in npc_order:
		t = maxi(t, FileAccess.get_modified_time(schedule_path(id)))
	return t
