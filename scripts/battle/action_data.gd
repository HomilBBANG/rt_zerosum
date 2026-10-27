@tool
class_name ActionData
extends Resource
## 행동 정의 (GDD 7절 ActionData). kind/target_rule 로 UI 와 해결 로직을 분리한다.

@export var id: String = ""
@export var display_name: String = ""
## "attack" | "heavy" | "support" | "ultimate" | "move" | "weapon"
@export var kind: String = "attack"
@export var ap_cost: int = 1
## "weapon" (현재 무기 사거리 따름: 근접=전방 우선, 원거리=전열 무관)
## "enemy_any" | "ally_any" | "ally_other" | "self" | "slot" | "none"
@export var target_rule: String = "weapon"
## "damage" | "heal" | "ap_grant" | "status"(상태 이상만) | "move" | "weapon_swap"
@export var effect: String = "damage"
@export var power: int = 0
## 맞은 대상에게 거는 상태 이상 (StatusCatalog id, "" = 없음) · 지속 턴 · 수치(% 또는 고정 피해) · 확률(%)
@export var status_id: String = ""
@export var status_turns: int = 0
@export var status_value: int = 0
@export var status_chance: int = 100
@export var description: String = ""
