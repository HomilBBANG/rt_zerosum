@tool
class_name CodexData
extends RefCounted
## 세계관 도감 (data/codex.json). 탭 = 등장인물 · 몬스터 · 상태이상 · 종교(신) · 도시 배경.
## 항목 = {id, title, subtitle, body, sprite?(그림 — 등장인물·몬스터), color?(#rrggbb — 도시)}.
## 등장인물·몬스터·상태이상·신은 게임 데이터(엑셀·statuses.json·faith.json)에 있는 것을 자동으로 넣고, 이 파일은 설명(body)·부제·순서만 덧붙임.
## 제목을 비우면 게임 데이터 이름. 도시 배경은 이 파일에만 있음.

const PATH := "res://data/codex.json"
const TABS := [["characters", "등장인물"], ["monsters", "몬스터"], ["statuses", "상태이상"], ["gods", "종교(신)"], ["cities", "도시 배경"]]


static func read(path: String = PATH) -> Dictionary:
	var out := {}
	for t in TABS:
		out[t[0]] = []
	if not FileAccess.file_exists(path):
		return out
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not j is Dictionary:
		return out
	for t in TABS:
		for e in j.get(t[0], []):
			if e is Dictionary and str(e.get("id", "")) != "":
				out[t[0]].append({"id": str(e.id), "title": str(e.get("title", "")), "subtitle": str(e.get("subtitle", "")),
					"body": str(e.get("body", "")), "sprite": str(e.get("sprite", "")), "color": str(e.get("color", ""))})
	return out


static func write(d: Dictionary, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var o := {"version": 1}
	for t in TABS:
		o[t[0]] = d.get(t[0], [])
	f.store_string(JSON.stringify(o, "\t", false))
	return OK


## 그 탭 항목 목록 (도감 순서 → 게임 데이터에만 있는 것은 뒤에, 설명 "기록 없음").
## gd = GameData (아군·몬스터·신), npcs = 기지 대원 데이터 {npc id → {name, sprite, character_id, desc}} (전투에 안 나가는 대원 = 로한 등)
static func entries(codex: Dictionary, tab: String, gd: GameData, npcs: Dictionary = {}) -> Array:
	var auto := []   # [{id, title, subtitle, sprite, color}]
	match tab:
		"characters":
			if gd != null:
				for u in gd.allies:
					auto.append({"id": u.id, "title": u.display_name, "subtitle": u.role, "sprite": u.sprite_id})
			for nid in npcs:
				var n: Dictionary = npcs[nid]
				if str(n.get("character_id", "")) == "":
					auto.append({"id": nid, "title": str(n.get("name", nid)), "subtitle": "", "sprite": str(n.get("sprite", ""))})
		"monsters":
			if gd != null:
				for mid in gd.monsters:
					var m: UnitData = gd.monsters[mid]
					auto.append({"id": mid, "title": m.display_name, "subtitle": m.role, "sprite": m.sprite_id})
		"statuses":
			for sid in StatusCatalog.battle_ids() + StatusCatalog.SYSTEM.keys():
				var sd := StatusCatalog.get_def(sid)
				auto.append({"id": sid, "title": str(sd.name), "subtitle": "긍정" if sd.get("positive", false) else "부정", "color": "#" + StatusCatalog.color_of(sid).to_html(false)})
		"gods":
			if gd != null:
				for g in gd.god_order:
					auto.append({"id": g, "title": str(gd.gods[g].name), "subtitle": "", "color": "#" + (gd.gods[g].color as Color).to_html(false)})
	var by_auto := {}
	for a in auto:
		by_auto[a.id] = a
	var out := []
	var seen := {}
	for e in codex.get(tab, []):
		var a: Dictionary = by_auto.get(e.id, {})
		if tab != "cities" and a.is_empty():
			continue   # 게임에서 지운 것
		out.append(_merge(a, e))
		seen[e.id] = true
	for a in auto:
		if not seen.has(a.id):
			out.append(_merge(a, {"body": "(기록 없음 — data/codex.json 에 설명을 넣으세요)"}))
	return out


static func _merge(a: Dictionary, e: Dictionary) -> Dictionary:
	var m := a.duplicate()
	m["id"] = str(e.get("id", a.get("id", "")))
	for k in ["title", "subtitle", "sprite", "color", "body"]:
		if str(e.get(k, "")) != "":
			m[k] = str(e[k])
		elif not m.has(k):
			m[k] = ""
	return m


## 검사: 같은 탭 id 중복
static func check(codex: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for t in TABS:
		var ids := {}
		for e in codex.get(t[0], []):
			if ids.has(e.id):
				errs.append("%s: id '%s' 가 두 번" % [t[1], e.id])
			ids[e.id] = true
	return errs
