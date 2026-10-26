extends RefCounted
## 코드(BattleHUD._create_layout)로 만든 전투 HUD 레이아웃을 scenes/battle_hud.tscn 에 저장한다.
## 그 뒤로는 Godot 에디터에서 battle_hud.tscn 을 열어 위치·크기를 직접 편집하면 게임에 그대로 반영된다.
## 주의: 다시 실행하면 에디터에서 편집한 레이아웃을 코드 기본값으로 덮어쓴다.
## 사용: godot --headless --path . ++ --export_hud=1   (Game 자동 로드가 필요해 게임 실행 경로로 호출)


static func run() -> int:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	hud.set_script(load("res://scripts/ui/battle_hud.gd"))
	hud.call("_create_layout")
	_own(hud, hud)
	var ps := PackedScene.new()
	var err := ps.pack(hud)
	if err == OK:
		err = ResourceSaver.save(ps, "res://scenes/battle_hud.tscn")
	print("[export_hud] scenes/battle_hud.tscn err=%d" % err)
	hud.free()
	return err


static func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)
