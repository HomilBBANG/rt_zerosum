@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "출정 대사" 탭. 출정 대기 화면에서 배치된 대원이 말풍선으로 하는 대사 (data/outgame/sortie_lines.json)

const PANEL := preload("res://addons/rtz_sortie_editor/sortie_editor_panel.gd")
var panel: Control


func _enter_tree() -> void:
	panel = PANEL.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)


func _exit_tree() -> void:
	CharacterSprite2D.clear_cache()   # 그림·발자국 소리 static 캐시 비우기 (에디터를 닫을 때 "resources still in use" 방지)
	if panel != null:
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel != null:
		panel.visible = visible
		if visible and panel.has_method("reload_data"):
			panel.reload_data(true)   # 탭을 열 때마다 대원 목록 다시 읽기 (편집 중인 대사는 유지)


func _get_plugin_name() -> String:
	return "출정 대사"


func _get_plugin_icon() -> Texture2D:
	var th := EditorInterface.get_editor_theme()
	return th.get_icon("RichTextEffect" if th.has_icon("RichTextEffect", "EditorIcons") else "Label", "EditorIcons")
