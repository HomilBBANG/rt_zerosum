class_name LoadingTips
extends RefCounted
## 로딩 멘트 표: data/loading_tips.xlsx 시트 "로딩 멘트" (사용자가 엑셀에서 직접 고침 — 로딩 화면이 뜰 때마다 다시 읽음)
##   열: 멘트 | 사용(O 또는 빈 칸 = 씀, X = 안 씀) | 장면(전체 · 기지 · 전투) | 메모(게임에서 안 씀)
## pick(장면) = 그 장면(또는 전체)에 맞는 멘트 중 하나를 무작위로 (없으면 "")

const PATH := "res://data/loading_tips.xlsx"
const SHEET := "로딩 멘트"
static var _last := ""


static func all(scene: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(PATH):
		return out
	var sheets := XlsxReader.read(PATH)
	var rows: Array = sheets.get(SHEET, sheets.values()[0] if not sheets.is_empty() else [])
	if rows.is_empty():
		return out
	var head: Array = rows[0]
	var col := {}
	for c in head.size():
		col[str(head[c]).strip_edges()] = c
	var ci: int = col.get("멘트", 0)
	for r in range(1, rows.size()):
		var row: Array = rows[r]
		var text := _cell(row, ci)
		if text == "":
			continue
		if _cell(row, col.get("사용", -1)).to_upper() in ["X", "0", "FALSE", "N", "NO"]:
			continue
		var where := _cell(row, col.get("장면", -1))
		if scene != "" and where != "" and where != "전체" and where != scene:
			continue
		out.append(text)
	return out


static func pick(scene: String = "") -> String:
	var list := all(scene)
	if list.is_empty():
		return ""
	if list.size() > 1 and list.has(_last):   # 바로 전 멘트는 다시 안 나오게
		list.remove_at(list.find(_last))
	_last = list[randi() % list.size()]
	return _last


static func _cell(row: Array, c: int) -> String:
	return str(row[c]).strip_edges() if c >= 0 and c < row.size() else ""
