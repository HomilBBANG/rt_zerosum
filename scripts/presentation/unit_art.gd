class_name UnitArt
extends RefCounted
## 유닛 아트 조회 헬퍼: 평면 스프라이트(assets/sprites/<id>.png) 또는 Skeleton2D 리그(assets/sprites/rig_<id>/rig.json)


static func rig_dir(sprite_id: String) -> String:
	return "res://assets/sprites/rig_%s" % sprite_id


static func has_rig(sprite_id: String) -> bool:
	return ResourceLoader.exists(rig_dir(sprite_id).path_join("rig.json")) or FileAccess.file_exists(rig_dir(sprite_id).path_join("rig.json"))


static func portrait(sprite_id: String, manifest: Dictionary) -> Texture2D:
	if has_rig(sprite_id):
		var tex: Texture2D = load(rig_dir(sprite_id).path_join("head.png"))
		var at := AtlasTexture.new()
		at.atlas = tex
		var s := tex.get_size()
		var side := minf(s.x, s.y)
		at.region = Rect2((s.x - side) * 0.5, 0, side, side)
		return at
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/%s.png" % sprite_id)
	var hr: Array = manifest.get("units", {}).get(sprite_id, {}).get("head_rect", [64, 36, 128, 128])
	at.region = Rect2(hr[0], hr[1], hr[2], hr[3])
	return at
