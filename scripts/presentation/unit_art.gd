@tool
class_name UnitArt
extends RefCounted
## 유닛 아트 조회 헬퍼: 캐릭터 프레임 애니메이션(assets/characters/<id>/) 또는 옛 평면 스프라이트(assets/sprites/<id>.png)


static func portrait(sprite_id: String, manifest: Dictionary) -> Texture2D:
	if CharacterSprite2D.exists(sprite_id):
		return CharacterSprite2D.portrait(sprite_id)
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/sprites/%s.png" % sprite_id)
	var hr: Array = manifest.get("units", {}).get(sprite_id, {}).get("head_rect", [64, 36, 128, 128])
	at.region = Rect2(hr[0], hr[1], hr[2], hr[3])
	return at
