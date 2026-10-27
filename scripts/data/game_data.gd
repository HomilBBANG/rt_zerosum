@tool
class_name GameData
extends RefCounted
## 밸런스 데이터 (data/balance.xlsx) → UnitData / ActionData / 아이템 / 스테이지.
## 시트: 캐릭터(아군) · 몬스터 · 아이템 · 스킬 · 스킬트리 · 스테이지. 열 이름은 1행 머리글로 찾는다(열 순서 자유).
## 게임 실행 중 파일이 바뀌면 apply_from() 으로 기존 객체를 제자리 갱신 → 진행 중인 전투에도 즉시 반영.

const BALANCE_PATH := "res://data/balance.xlsx"
const STAGE_DIR := "res://data/stages"
## 에디터 스테이지 탭의 "테스트 플레이" 요청 (게임이 시작할 때 읽고 지움, git 무시)
const EDITOR_PLAY_PATH := "res://data/.editor_play.json"
const ROW_NAMES := ["전방", "중앙", "후방"]

var allies: Array[UnitData] = []
var monsters: Dictionary = {}       # id → UnitData (원본, 스테이지 배율 적용 전)
var items: Dictionary = {}          # id → {id, name, kind, range_type, power_bonus, sprite, desc}
var actions: Dictionary = {}        # id → ActionData
var stages: Dictionary = {}         # id → {id, name, preset, ambush, hp_mult, dmg_mult, seed, desc}
var stage_order: Array[String] = []
## 스킬 트리: 캐릭터 id → [{id, char, dir(center|n|e|s|w), tier 0~3, name, level, effect, value, desc}] (십자형 — 중앙 + 동서남북 갈래)
var skill_tree: Dictionary = {}
const TREE_DIRS := {"중앙": "center", "북": "n", "동": "e", "남": "s", "서": "w"}
var warnings: PackedStringArray = []
var _stage_copies: Array = []       # [{copy: UnitData, base: id, stage: id}] 스테이지 배율 적용본


static func load_from(path: String = BALANCE_PATH) -> GameData:
	var sheets := XlsxReader.read(path)
	if sheets.is_empty():
		return null
	var g := GameData.new()
	g._parse(sheets)
	return g


# ---------------------------------------------------------------- 파싱
static func _table(sheet: Array) -> Array:
	var out := []
	if sheet.is_empty():
		return out
	var head: Array = sheet[0]
	for r in range(1, sheet.size()):
		var row: Array = sheet[r]
		var d := {}
		var any := false
		for c in head.size():
			var key := str(head[c]).strip_edges()
			var v: String = str(row[c]) if c < row.size() else ""
			d[key] = v
			if v != "":
				any = true
		if any and str(d.get("id", "")) != "":
			out.append(d)
	return out


static func _f(d: Dictionary, key: String, def: float = 0.0) -> float:
	var v := str(d.get(key, ""))
	return float(v) if v.is_valid_float() else def


static func _i(d: Dictionary, key: String, def: int = 0) -> int:
	var v := str(d.get(key, ""))
	return int(roundf(float(v))) if v.is_valid_float() else def


static func _list(d: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	for s in str(d.get(key, "")).replace("，", ",").split(","):
		var t := s.strip_edges()
		if t != "":
			out.append(t)
	return out


static func _range(v: String) -> String:
	return "ranged" if v.strip_edges() in ["원거리", "ranged"] else "melee"


func _parse(sheets: Dictionary) -> void:
	for d in _table(sheets.get("아이템", [])):
		items[d.id] = {"id": d.id, "name": d.get("이름", d.id), "kind": d.get("종류", "무기"),
			"range_type": _range(d.get("사거리", "")), "power_bonus": _i(d, "위력보너스"),
			"sprite": d.get("스프라이트", ""), "desc": d.get("설명", "")}
	for d in _table(sheets.get("스킬", [])):
		var a := ActionData.new()
		a.id = d.id
		a.display_name = d.get("이름", d.id)
		a.kind = d.get("종류", "attack")
		a.ap_cost = _i(d, "AP비용", 1)
		a.target_rule = d.get("대상", "weapon")
		a.effect = d.get("효과", "damage")
		a.power = _i(d, "위력")
		a.description = d.get("설명", "")
		actions[a.id] = a
	for d in _table(sheets.get("캐릭터", [])):
		allies.append(_unit(d, "ally"))
	for d in _table(sheets.get("스킬트리", [])):
		var cid := str(d.get("캐릭터", ""))
		var dir: String = TREE_DIRS.get(str(d.get("방향", "")).strip_edges(), "")
		if cid == "" or dir == "":
			warnings.append("스킬트리 %s: 캐릭터·방향(중앙/북/동/남/서) 확인" % d.id)
			continue
		if not skill_tree.has(cid):
			skill_tree[cid] = []
		skill_tree[cid].append({"id": d.id, "char": cid, "dir": dir, "tier": 0 if dir == "center" else clampi(_i(d, "단계", 1), 1, 9),
			"name": d.get("이름", d.id), "level": _i(d, "필요레벨", 1), "effect": str(d.get("효과", "")).strip_edges(),
			"value": _i(d, "값"), "desc": d.get("설명", "")})
	for d in _table(sheets.get("몬스터", [])):
		monsters[d.id] = _unit(d, "enemy")
	for d in _table(sheets.get("스테이지", [])):
		var amb := "none"
		match str(d.get("선공", "")).strip_edges():
			"기습": amb = "ally"
			"매복": amb = "enemy"
		stages[d.id] = {"id": d.id, "name": d.get("이름", d.id), "preset": d.get("조명", "g1") if d.get("조명", "") != "" else "g1",
			"ambush": amb, "hp_mult": _f(d, "적HP배율", 1.0), "dmg_mult": _f(d, "적공격배율", 1.0),
			"seed": _i(d, "시드", 12345), "desc": d.get("설명", "")}
		stage_order.append(d.id)
	for cid in skill_tree:
		if _find(allies, cid) == null:
			warnings.append("스킬트리: 캐릭터 시트에 없는 '%s'" % cid)
		for n in skill_tree[cid]:
			var ef: String = n.effect
			if ef.begins_with("skill:") or ef.begins_with("skill_power:"):
				var sid := ef.split(":")[1]
				if not actions.has(sid):
					warnings.append("스킬트리 %s: 스킬 시트에 없는 '%s'" % [n.id, sid])
			elif not ef in ["hp", "speed", "ap", "ap_rec", "defense", "power", "heal"]:
				warnings.append("스킬트리 %s: 모르는 효과 '%s'" % [n.id, ef])


func _unit(d: Dictionary, team: String) -> UnitData:
	var u := UnitData.new()
	u.id = d.id
	u.display_name = d.get("이름", d.id)
	u.team = team
	u.role = d.get("병과", d.get("분류", ""))
	u.level = _i(d, "레벨", 1)
	u.speed = _i(d, "속도", 5)
	u.range_type = _range(d.get("사거리", ""))
	u.max_hp = _i(d, "HP", 30)
	u.max_ap = _i(d, "AP", 6)
	u.ap_recovery = _i(d, "AP회복", 2)
	u.defense = _i(d, "방어")
	u.skill_ids = _list(d, "스킬")
	var ws: Array[Dictionary] = []
	for wid in _list(d, "무기"):
		if items.has(wid):
			var it: Dictionary = items[wid]
			ws.append({"id": wid, "name": it.name, "range_type": it.range_type, "power_bonus": it.power_bonus, "sprite": it.sprite})
		else:
			warnings.append("%s: 아이템 시트에 없는 무기 '%s'" % [u.id, wid])
	u.weapons = ws
	u.sprite_id = d.get("스프라이트", u.id)
	u.height_cm = _f(d, "키(cm)", 175.0)
	var row_name := str(d.get("열", "")).strip_edges()
	u.default_row = ROW_NAMES.find(row_name) if row_name in ROW_NAMES else clampi(_i(d, "열"), 0, 2)
	u.default_index = clampi(_i(d, "줄", 1) - 1, 0, 1)
	u.row_span = clampi(_i(d, "차지칸", 1), 1, 3)
	u.ai_id = d.get("AI", "default") if d.get("AI", "") != "" else "default"
	var pal := {"sprite_id": u.sprite_id, "height_cm": u.height_cm}
	if str(d.get("눈색", "")) != "":
		pal["eye_paint"] = d.get("눈색")
	if str(d.get("원화방향", "")).strip_edges() == "왼쪽":
		pal["art_faces_left"] = true
	u.palette = pal
	for sid in u.skill_ids:
		if not actions.has(sid):
			warnings.append("%s: 스킬 시트에 없는 스킬 '%s'" % [u.id, sid])
	return u


# ---------------------------------------------------------------- 스테이지
static func stage_path(stage_id: String) -> String:
	return "%s/%s.json" % [STAGE_DIR, stage_id]


## 스테이지 배치 파일 {enemies: [{monster, row, index}]} (스테이지 에디터가 저장)
static func load_placement(stage_id: String) -> Array:
	var f := FileAccess.open(stage_path(stage_id), FileAccess.READ)
	if f == null:
		return []
	var j: Variant = JSON.parse_string(f.get_as_text())
	if j is Dictionary and j.get("enemies") is Array:
		return j.enemies
	return []


## 스테이지의 적 UnitData (몬스터 원본 복제 + 스테이지 배율, 배치 열/줄)
func build_stage_enemies(stage_id: String) -> Array[UnitData]:
	var out: Array[UnitData] = []
	_stage_copies = _stage_copies.filter(func(e): return e.stage != stage_id)
	var n := 0
	for e in load_placement(stage_id):
		var base: UnitData = monsters.get(str(e.get("monster", "")), null)
		if base == null:
			warnings.append("%s: 몬스터 시트에 없는 '%s'" % [stage_id, e.get("monster", "")])
			continue
		n += 1
		var copy := UnitData.new()
		_derive(copy, base, stage_id, n)
		copy.default_row = int(e.get("row", 0))
		copy.default_index = int(e.get("index", 0))
		_stage_copies.append({"copy": copy, "base": base.id, "stage": stage_id, "n": n})
		out.append(copy)
	return out


func _derive(copy: UnitData, base: UnitData, stage_id: String, n: int) -> void:
	var row := copy.default_row
	var idx := copy.default_index
	_copy_props(copy, base)
	copy.default_row = row
	copy.default_index = idx
	copy.id = "e_%s_%d" % [base.id, n]
	var st: Dictionary = stages.get(stage_id, {})
	copy.max_hp = maxi(1, int(roundf(base.max_hp * float(st.get("hp_mult", 1.0)))))
	copy.damage_mult = float(st.get("dmg_mult", 1.0))


static func _copy_props(dst: Object, src: Object) -> void:
	for p in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = src.get(p.name)
			dst.set(p.name, v.duplicate(true) if (v is Array or v is Dictionary) else v)


# ---------------------------------------------------------------- 즉시 반영
## 새로 읽은 데이터로 기존 객체를 제자리 갱신 (같은 id). 진행 중인 전투의 UnitRuntime 이 같은 UnitData 를 보므로 바로 반영된다.
func apply_from(newer: GameData) -> void:
	for nu in newer.allies:
		var cur := _find(allies, nu.id)
		if cur != null:
			_copy_props(cur, nu)
		else:
			allies.append(nu)
	for id in newer.monsters:
		if monsters.has(id):
			_copy_props(monsters[id], newer.monsters[id])
		else:
			monsters[id] = newer.monsters[id]
	for id in newer.actions:
		if actions.has(id):
			_copy_props(actions[id], newer.actions[id])
		else:
			actions[id] = newer.actions[id]
	items = newer.items
	skill_tree = newer.skill_tree
	stages = newer.stages
	stage_order = newer.stage_order
	warnings = newer.warnings
	for e in _stage_copies:
		if monsters.has(e.base):
			_derive(e.copy, monsters[e.base], e.stage, e.n)


static func _find(list: Array[UnitData], id: String) -> UnitData:
	for u in list:
		if u.id == id:
			return u
	return null
