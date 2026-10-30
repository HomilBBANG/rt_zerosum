@tool
class_name XlsxWriter
extends RefCounted
## .xlsx(엑셀 통합 문서)를 외부 도구 없이 쓴다: xlsx = zip + XML (ZIPPacker).
## write(path, sheets) — sheets = [{name: 시트 이름, rows: [[셀, …], …], widths: [열 너비, …] (선택), header: true (선택, 첫 줄 굵게 · 고정 · 필터),
##   ref_cols: [열 번호, …] (선택, 참고용 열 — 머리 줄 연한 바탕 · 글자 회색)}]
## 셀: int · float = 숫자, bool = TRUE/FALSE, 그 밖 = 글자 (줄바꿈 \n 그대로). 읽기는 XlsxReader.


static func write(path: String, sheets: Array) -> int:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var zp := ZIPPacker.new()
	var err := zp.open(path)
	if err != OK:
		return err
	var names: Array[String] = []
	for i in sheets.size():
		names.append(_sheet_name(str(sheets[i].get("name", "Sheet%d" % (i + 1))), names))
	_put(zp, "[Content_Types].xml", _content_types(sheets.size()))
	_put(zp, "_rels/.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
	var wb := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
	var rels := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
	for i in sheets.size():
		wb += '<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % [_esc(names[i]), i + 1, i + 1]
		rels += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % [i + 1, i + 1]
	rels += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>' % (sheets.size() + 1)
	wb += "</sheets></workbook>"
	_put(zp, "xl/workbook.xml", wb)
	_put(zp, "xl/_rels/workbook.xml.rels", rels)
	_put(zp, "xl/styles.xml", _styles())
	for i in sheets.size():
		_put(zp, "xl/worksheets/sheet%d.xml" % (i + 1), _sheet_xml(sheets[i]))
	return zp.close()


static func _put(zp: ZIPPacker, name: String, text: String) -> void:
	zp.start_file(name)
	zp.write_file(text.to_utf8_buffer())
	zp.close_file()


## 시트 이름: 31자 · []:*?/\ 빼고 · 겹치면 번호
static func _sheet_name(n: String, used: Array[String]) -> String:
	for ch in ["[", "]", ":", "*", "?", "/", "\\"]:
		n = n.replace(ch, " ")
	n = n.strip_edges().substr(0, 31)
	if n == "":
		n = "Sheet"
	var base := n
	var k := 2
	while used.has(n):
		n = base.substr(0, 28) + " %d" % k
		k += 1
	return n


static func _content_types(n: int) -> String:
	var t := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
	for i in n:
		t += '<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % (i + 1)
	return t + "</Types>"


## 스타일 0 = 기본(위 정렬 · 줄바꿈), 1 = 머리 줄(굵게 · 회색 바탕 · 아래 테두리), 2 = 참고 열 머리 줄(연한 바탕 · 회색 굵게), 3 = 참고 열 칸(회색 글자)
static func _styles() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
		+ '<fonts count="4"><font><sz val="11"/><name val="맑은 고딕"/></font><font><b/><sz val="11"/><name val="맑은 고딕"/></font>' \
		+ '<font><sz val="11"/><color rgb="FF7A808C"/><name val="맑은 고딕"/></font><font><b/><sz val="11"/><color rgb="FF7A808C"/><name val="맑은 고딕"/></font></fonts>' \
		+ '<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' \
		+ '<fill><patternFill patternType="solid"><fgColor rgb="FFD9DEE7"/><bgColor indexed="64"/></patternFill></fill>' \
		+ '<fill><patternFill patternType="solid"><fgColor rgb="FFF1F2F5"/><bgColor indexed="64"/></patternFill></fill></fills>' \
		+ '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF8A93A6"/></bottom><diagonal/></border></borders>' \
		+ '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' \
		+ '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>' \
		+ '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>' \
		+ '<xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>' \
		+ '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>' \
		+ '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'


static func _sheet_xml(sh: Dictionary) -> String:
	var rows: Array = sh.get("rows", [])
	var header := bool(sh.get("header", true)) and not rows.is_empty()
	var ncol := 0
	for r in rows:
		ncol = maxi(ncol, (r as Array).size())
	var widths: Array = sh.get("widths", [])
	var ref_cols: Array = sh.get("ref_cols", [])
	var x := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
	if header:
		x += '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>'
	if ncol > 0:
		x += "<cols>"
		for c in ncol:
			var w: float = float(widths[c]) if c < widths.size() else _auto_width(rows, c)
			x += '<col min="%d" max="%d" width="%.1f" customWidth="1"/>' % [c + 1, c + 1, w]
		x += "</cols>"
	x += "<sheetData>"
	for ri in rows.size():
		var r: Array = rows[ri]
		x += '<row r="%d">' % (ri + 1)
		for ci in r.size():
			var ref := col_name(ci) + str(ri + 1)
			var is_ref := ref_cols.has(ci)
			var st := (' s="2"' if is_ref else ' s="1"') if header and ri == 0 else (' s="3"' if is_ref else "")
			var v: Variant = r[ci]
			if v == null or (v is String and v == ""):
				if st != "":
					x += '<c r="%s"%s/>' % [ref, st]
				continue
			if v is bool:
				x += '<c r="%s"%s t="b"><v>%d</v></c>' % [ref, st, 1 if v else 0]
			elif v is int or v is float:
				x += '<c r="%s"%s><v>%s</v></c>' % [ref, st, str(v)]
			else:
				x += '<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % [ref, st, _esc(str(v))]
		x += "</row>"
	x += "</sheetData>"
	if header and ncol > 0 and rows.size() > 1:
		x += '<autoFilter ref="A1:%s%d"/>' % [col_name(ncol - 1), rows.size()]
	return x + "</worksheet>"


## 열 너비 자동: 가장 긴 줄 글자 수 (한글은 2칸), 6~60
static func _auto_width(rows: Array, c: int) -> float:
	var w := 6.0
	for r in rows:
		if c < (r as Array).size() and r[c] != null:
			for line in str(r[c]).split("\n"):
				var n := 0.0
				for ch in line:
					n += 1.9 if ch.unicode_at(0) > 0x2E80 else 1.05
				w = maxf(w, n + 2.0)
	return minf(w, 60.0)


## 0 → A, 25 → Z, 26 → AA
static func col_name(i: int) -> String:
	var s := ""
	var n := i + 1
	while n > 0:
		var m := (n - 1) % 26
		s = String.chr(65 + m) + s
		n = (n - 1) / 26
	return s


static func _esc(s: String) -> String:
	var out := s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
	# XML 1.0 에 못 쓰는 제어 문자 빼기 (탭 · 줄바꿈 빼고)
	var clean := ""
	for ch in out:
		var u := ch.unicode_at(0)
		if u >= 32 or u == 9 or u == 10 or u == 13:
			clean += ch
	return clean
