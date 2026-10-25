extends Node2D
## 리그 비용 벤치: N명의 유닛(평면 스프라이트 또는 Skeleton2D 리그)을 격자로 띄우고 평균 프레임 시간을 잰다.
## CLI: --scene=bench --count=48 --rig=1 [--bones=1] [--shot=...]  / 화면: 좌상단 측정값, B 키 본 표시

const UNIT_SCRIPT := preload("res://scripts/presentation/unit_sprite_2d.gd")

var count: int = 12
var use_rig: bool = true
var show_bones: bool = false
var units: Array = []
var label: Label
var overlay: Node2D
var frames := 0
var acc_ms := 0.0
var warm := 30
var measure := 180
var done := false
var manifest: Dictionary


func _ready() -> void:
	count = int(Game.cli.get("count", "12"))
	use_rig = Game.cli.get("rig", "1") == "1"
	show_bones = Game.cli.get("bones", "0") == "1"
	var f := FileAccess.open("res://assets/sprites/manifest.json", FileAccess.READ)
	manifest = JSON.parse_string(f.get_as_text())
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.16, 0.18)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var preset := LightingPresets.get_preset(Game.preset)
	var hero := TestRoster.find_unit(TestRoster.build_allies(), "a_raon")
	var flat := TestRoster.find_unit(TestRoster.build_allies(), "a_minu")
	var cols := int(ceil(sqrt(count * 16.0 / 9.0)))
	var rows := int(ceil(float(count) / cols))
	var layer := Node2D.new()
	add_child(layer)
	for i in count:
		var data: UnitData = hero if use_rig else flat
		var rt := UnitRuntime.create(data, i + 1, 0, 0)
		var s: UnitSprite2D = UNIT_SCRIPT.new()
		layer.add_child(s)
		s.build(rt, manifest)
		var cx := 1280.0 * (i % cols + 0.5) / cols
		var cy := 120.0 + 560.0 * ((i / cols) + 1.0) / rows
		s.position = Vector2(cx, cy)
		var sc: float = clampf(2.2 / sqrt(float(count)) * 1.6, 0.25, 1.0)
		s.scale = Vector2.ONE * sc
		s.apply_lighting(preset, "key" if i % 2 == 0 else "accent")
		s.set_light_direction(i % 2 == 0)
		units.append(s)
	overlay = Node2D.new()
	overlay.z_index = 50
	add_child(overlay)
	overlay.draw.connect(_draw_bones)
	label = Label.new()
	label.add_theme_font_override("font", load("res://assets/fonts/NotoSansKR-VF.otf"))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 5)
	label.position = Vector2(16, 12)
	add_child(label)
	_update_label("측정 중...")


func _update_label(extra: String) -> void:
	var first: UnitSprite2D = units[0] if not units.is_empty() else null
	var desc := "평면 스프라이트" if not use_rig else "Skeleton2D 리그 (본 %d, 파츠 %d)" % [first.rig.bone_count(), first.rig.part_count()]
	label.text = "벤치: %s × %d   %s\n[B] 본 표시  [Tab] 평면↔리그  [+/-] 수 변경" % [desc, count, extra]


func _process(delta: float) -> void:
	overlay.queue_redraw()
	if done:
		return
	frames += 1
	if frames <= warm:
		return
	acc_ms += delta * 1000.0
	if frames == warm + measure:
		done = true
		var avg := acc_ms / measure
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var line := "[bench] mode=%s count=%d avg_ms=%.2f fps=%.1f draw_calls=%d objects=%d" % ["rig" if use_rig else "flat", count, avg, 1000.0 / avg, dc, objs]
		print(line)
		_update_label("평균 %.2f ms (%.0f fps) · 드로우콜 %d · 오브젝트 %d" % [avg, 1000.0 / avg, dc, objs])
		if Game.cli.has("shot"):
			Game.maybe_cli_capture(2)
		elif Game.cli.has("bench_quit"):
			get_tree().quit()


func _draw_bones() -> void:
	if not show_bones:
		return
	for s in units:
		if s.rig == null:
			continue
		for name in s.rig.bones:
			var b: Bone2D = s.rig.bones[name]
			var p := overlay.to_local(b.global_position)
			var parent := b.get_parent()
			if parent is Bone2D:
				overlay.draw_line(overlay.to_local(parent.global_position), p, Color(1, 1, 0, 0.9), 2.0)
			overlay.draw_circle(p, 4.0, Color(1, 0.2, 0.8))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				show_bones = not show_bones
			KEY_TAB:
				Game.cli["rig"] = "0" if use_rig else "1"
				get_tree().reload_current_scene()
			KEY_EQUAL, KEY_KP_ADD:
				Game.cli["count"] = str(count * 2)
				get_tree().reload_current_scene()
			KEY_MINUS, KEY_KP_SUBTRACT:
				Game.cli["count"] = str(maxi(1, count / 2))
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				Game.go_menu()
