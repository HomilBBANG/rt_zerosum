@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "스테이지" 탭. 스테이지 적 배치 에디터 (data/stages/*.json)

const PANEL := preload("res://addons/rtz_stage_editor/stage_editor_panel.gd")
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
		panel.reload_data()   # 탭을 열 때마다 엑셀(스테이지·몬스터) 다시 읽기


func _get_plugin_name() -> String:
	return "스테이지"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridContainer", "EditorIcons")

