@tool
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
## 명중 보너스 (%p, 쓰는 스킬 명중에 더함) · 회피 (%, 맞는 쪽 명중률에서 뺌) — 캐릭터·몬스터 시트 '명중' · '회피' 열 (스킬 트리 효과 accuracy · evasion 으로도 +)
@export var accuracy: int = 0
@export var evasion: int = 0
@export var skill_ids: Array[String] = []
## 무기: {id, name, range_type, power_bonus}
@export var weapons: Array[Dictionary] = []
@export var sprite_id: String = ""
@export var role: String = ""              # 표시용 병과명
@export var height_cm: float = 175.0       # 키: 화면 크기에 반영 (230px = 175cm)
## 차지하는 열 수: 1 = 한 칸, 2 = default_row 부터 뒤로 두 칸 (예: 전방+중앙). 큰 몸집 괴물용, 이동·교환 불가.
@export var row_span: int = 1
## 적 AI 그래프 id (data/ai/<id>.json, AI 에디터) — 몬스터 시트 "AI" 열
@export var ai_id: String = "default"
## 스킬 트리 보너스 (기지에서 배운 것, 전투용 복제본에만): 모든 공격 위력 + / 회복량 + / 스킬별 위력 {스킬 id: +}
@export var power_bonus: int = 0
@export var heal_bonus: int = 0
@export var skill_power: Dictionary = {}
## 주는 피해 배율 (스테이지 적공격배율)
@export var damage_mult: float = 1.0
## 기본 배치 (row 0=전방,1=중앙,2=후방 / index 0,1)
@export var default_row: int = 0
@export var default_index: int = 0
## 3D/2D 색상 식별용 팔레트 {skin, hair, jacket, pants, accent, eyes}
@export var palette: Dictionary = {}
