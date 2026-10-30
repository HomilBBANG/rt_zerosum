class_name SupplyData
extends RefCounted
## 보급 · 납품 · 장군 데이터 (data/supply.xlsx, tools/gen_supply_xlsx.py 로 처음 만듦 — 이후엔 엑셀이 원본).
## 아이템(전리품) · 전투 보상 · 대원 선물 · 장군 요구 · 주마다 납품 목록 · 설정(기본 주급 · 장군 추가금/차감 · 충성심).

const PATH := "res://data/supply.xlsx"

var settings: Dictionary = {}
var items: Dictionary = {}          # id → {id, name, desc}
var item_order: Array[String] = []
var battle_loot: Array = []         # [{stage("*" = 모두), item, min, max, chance}]
var crew_gifts: Array = []          # [{npc, item, chance, affinity}]
var demands: Array = []             # [{item, count, weight, line}]
var deliveries: Array = []          # [{progress, list: {item: 개수}}] 진행률 순
var warnings: PackedStringArray = []


static func load_from(path: String = PATH) -> SupplyData:
	var d := SupplyData.new()
	if not FileAccess.file_exists(path):
		d.warnings.append("supply.xlsx 없음 — 납품 · 전리품 없이")
		return d
	var sheets := XlsxReader.read(path)
	if sheets.is_empty():
		d.warnings.append("supply.xlsx 를 읽지 못함")
		return d
	d._parse(sheets)
	return d


## 머리 줄 이름 → 값 사전 (빈 줄은 뺌)
static func _rows(sheet: Array) -> Array:
	var out := []
	if sheet.is_empty():
		return out
	var head: Array = sheet[0]
	for r in range(1, sheet.size()):
		var row: Array = sheet[r]
		var e := {}
		var any := false
		for c in head.size():
			var v: String = str(row[c]).strip_edges() if c < row.size() else ""
			e[str(head[c]).strip_edges()] = v
			if v != "":
				any = true
		if any:
			out.append(e)
	return out


static func _int(e: Dictionary, k: String, def: int = 0) -> int:
	var v := str(e.get(k, ""))
	return roundi(v.to_float()) if v.is_valid_float() else def


## "scrap:4, gunpowder:2" → {scrap: 4, gunpowder: 2}
static func parse_list(s: String) -> Dictionary:
	var out := {}
	for part in s.replace("，", ",").split(",", false):
		var kv := part.strip_edges().split(":")
		var id := kv[0].strip_edges()
		if id == "":
			continue
		out[id] = int(out.get(id, 0)) + (maxi(1, int(kv[1].strip_edges())) if kv.size() > 1 else 1)
	return out


func _parse(sheets: Dictionary) -> void:
	for e in _rows(sheets.get("설정", [])):
		if e.get("id", "") != "":
			settings[e.id] = e.get("값", "")
	for e in _rows(sheets.get("아이템", [])):
		var id := str(e.get("id", ""))
		if id == "":
			continue
		items[id] = {"id": id, "name": e.get("이름", id) if e.get("이름", "") != "" else id, "desc": e.get("설명", "")}
		item_order.append(id)
	for e in _rows(sheets.get("전투 보상", [])):
		var r := {"stage": e.get("스테이지", "*") if e.get("스테이지", "") != "" else "*", "item": e.get("아이템", ""),
			"min": maxi(0, _int(e, "최소", 1)), "max": 0, "chance": clampi(_int(e, "확률%", 100), 0, 100)}
		r.max = maxi(r.min, _int(e, "최대", r.min))
		_check_item(r.item, "전투 보상")
		battle_loot.append(r)
	for e in _rows(sheets.get("대원 선물", [])):
		var r2 := {"npc": e.get("대원", ""), "item": e.get("아이템", ""), "chance": clampi(_int(e, "확률%", 0), 0, 100), "affinity": _int(e, "최소친밀도", 0)}
		_check_item(r2.item, "대원 선물")
		crew_gifts.append(r2)
	for e in _rows(sheets.get("장군 요구", [])):
		var r3 := {"item": e.get("아이템", ""), "count": maxi(1, _int(e, "개수", 1)), "weight": maxi(0, _int(e, "가중치", 1)), "line": e.get("장군 대사", "")}
		_check_item(r3.item, "장군 요구")
		demands.append(r3)
	for e in _rows(sheets.get("납품", [])):
		var lst := parse_list(str(e.get("납품 목록", "")))
		if lst.is_empty():
			continue
		for it in lst:
			_check_item(it, "납품")
		deliveries.append({"progress": float(_int(e, "진행률%", 0)), "list": lst})
	deliveries.sort_custom(func(a, b): return a.progress < b.progress)


func _check_item(id: String, where: String) -> void:
	if id != "" and not items.has(id):
		warnings.append("supply.xlsx %s: 없는 아이템 '%s'" % [where, id])


func num(key: String, def: float) -> float:
	var v := str(settings.get(key, ""))
	return v.to_float() if v.is_valid_float() else def


func inum(key: String, def: int) -> int:
	return roundi(num(key, float(def)))


func item_name(id: String) -> String:
	return str(items.get(id, {}).get("name", id))


## 그 진행률(%)에 맞는 납품 목록: 진행률 이하 중 가장 높은 단계의 줄들을 주마다 번갈아. 없으면 {}
func delivery_for(progress: float, week: int) -> Dictionary:
	var best := -1.0
	for d in deliveries:
		if float(d.progress) <= progress + 0.001:
			best = maxf(best, float(d.progress))
	if best < 0.0:
		return {}
	var rows := deliveries.filter(func(d): return is_equal_approx(float(d.progress), best))
	return (rows[posmod(week, rows.size())].list as Dictionary).duplicate()
