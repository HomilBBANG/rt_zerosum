@tool
class_name XlsxReader
extends RefCounted
## .xlsx(엑셀 통합 문서)를 외부 도구 없이 읽는다: xlsx = zip + XML.
## read(path) → { 시트이름: [[셀 문자열, ...], ...] } (행·열 순서 그대로, 빈 셀은 "")


static func read(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		push_warning("xlsx 열기 실패: %s" % path)
		return {}
	var files := zr.get_files()
	var shared: PackedStringArray = []
	if files.has("xl/sharedStrings.xml"):
		shared = _shared_strings(zr.read_file("xl/sharedStrings.xml"))
	var rels := _rels(zr.read_file("xl/_rels/workbook.xml.rels"))
	var out := {}
	for sh in _sheets(zr.read_file("xl/workbook.xml")):
		var target: String = rels.get(sh.rid, "")
		if target == "":
			continue
		target = target.trim_prefix("/")
		if not target.begins_with("xl/"):
			target = "xl/" + target
		if files.has(target):
			out[sh.name] = _sheet_rows(zr.read_file(target), shared)
	zr.close()
	return out


static func _parser(bytes: PackedByteArray) -> XMLParser:
	var p := XMLParser.new()
	p.open_buffer(bytes)
	return p


static func _sheets(bytes: PackedByteArray) -> Array:
	var out := []
	var p := _parser(bytes)
	while p.read() == OK:
		if p.get_node_type() == XMLParser.NODE_ELEMENT and p.get_node_name() == "sheet":
			out.append({"name": p.get_named_attribute_value_safe("name"), "rid": p.get_named_attribute_value_safe("r:id")})
	return out


static func _rels(bytes: PackedByteArray) -> Dictionary:
	var out := {}
	var p := _parser(bytes)
	while p.read() == OK:
		if p.get_node_type() == XMLParser.NODE_ELEMENT and p.get_node_name() == "Relationship":
			out[p.get_named_attribute_value_safe("Id")] = p.get_named_attribute_value_safe("Target")
	return out


## 공유 문자열: <si> 하나 = 문자열 하나 (<t> 또는 서식 run <r><t> 를 이어 붙임, 윗주 <rPh> 는 건너뜀)
static func _shared_strings(bytes: PackedByteArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var p := _parser(bytes)
	var cur := ""
	var in_t := false
	var in_rph := false
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := p.get_node_name()
				if n == "si":
					cur = ""
				elif n == "rPh":
					in_rph = not p.is_empty()
				elif n == "t" and not p.is_empty():
					in_t = true
			XMLParser.NODE_TEXT:
				if in_t and not in_rph:
					cur += p.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var n := p.get_node_name()
				if n == "t":
					in_t = false
				elif n == "rPh":
					in_rph = false
				elif n == "si":
					out.append(cur)
	return out


static func _col_index(ref: String) -> int:
	var n := 0
	for ch in ref:
		var c := ch.unicode_at(0)
		if c >= 65 and c <= 90:
			n = n * 26 + (c - 64)
		elif c >= 97 and c <= 122:
			n = n * 26 + (c - 96)
		else:
			break
	return n - 1


static func _sheet_rows(bytes: PackedByteArray, shared: PackedStringArray) -> Array:
	var rows := {}      # 행 번호 → {열: 값}
	var max_row := 0
	var p := _parser(bytes)
	var row := 0
	var col := 0
	var ctype := ""
	var val := ""
	var in_v := false
	var in_t := false
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := p.get_node_name()
				if n == "row":
					row = int(p.get_named_attribute_value_safe("r"))
				elif n == "c":
					var ref := p.get_named_attribute_value_safe("r")
					col = _col_index(ref) if ref != "" else col + 1
					ctype = p.get_named_attribute_value_safe("t")
					val = ""
					if p.is_empty():
						continue
				elif n == "v" and not p.is_empty():
					in_v = true
				elif n == "t" and not p.is_empty():
					in_t = true
			XMLParser.NODE_TEXT:
				if in_v or in_t:
					val += p.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var n := p.get_node_name()
				if n == "v":
					in_v = false
				elif n == "t":
					in_t = false
				elif n == "c":
					var s := val
					if ctype == "s" and val.is_valid_int():
						s = shared[int(val)] if int(val) < shared.size() else ""
					elif ctype == "b":
						s = "TRUE" if val == "1" else "FALSE"
					elif ctype == "" or ctype == "n":
						s = _num_text(val)
					if not rows.has(row):
						rows[row] = {}
					rows[row][col] = s.strip_edges()
					max_row = maxi(max_row, row)
	var out := []
	for r in range(1, max_row + 1):
		var cells: Dictionary = rows.get(r, {})
		var arr: Array[String] = []
		var mc := -1
		for c in cells:
			mc = maxi(mc, c)
		for c in range(mc + 1):
			arr.append(str(cells.get(c, "")))
		out.append(arr)
	return out


## 숫자 셀: 176.80000000000001 같은 부동소수 표기를 짧게
static func _num_text(v: String) -> String:
	if v == "" or not v.is_valid_float():
		return v
	var f := float(v)
	if is_equal_approx(f, roundf(f)) and absf(f) < 1e12:
		return str(int(roundf(f)))
	return str(snappedf(f, 0.0001))
