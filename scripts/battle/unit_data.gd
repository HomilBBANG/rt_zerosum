class_name UnitData
extends Resource
## Static definition of a unit (GDD 7절 UnitData). 수치는 모두 프로토타입 임시값.

@export var id: String = ""
@export var display_name: String = ""
@export var team: String = "ally"          # "ally" | "enemy"
@export var level: int = 1
@export var speed: int = 5
@export var range_type: String = "melee"   # 병과 기본 사거리: "melee" | "ranged" (동률 정렬용)
@export var max_hp: int = 30
@export var max_ap: int = 6
@export var ap_recovery: int = 2
@export var defense: int = 0
@export var skill_ids: Array[String] = []
## 무기: {id, name, range_type, power_bonus}
@export var weapons: Array[Dictionary] = []
@export var sprite_id: String = ""
@export var role: String = ""              # 표시용 병과명
## 기본 배치 (row 0=전방,1=중앙,2=후방 / index 0,1)
@export var default_row: int = 0
@export var default_index: int = 0
## 3D/2D 색상 식별용 팔레트 {skin, hair, jacket, pants, accent, eyes}
@export var palette: Dictionary = {}
