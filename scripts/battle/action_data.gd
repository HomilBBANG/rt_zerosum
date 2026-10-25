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
## "damage" | "heal" | "ap_grant" | "move" | "weapon_swap"
@export var effect: String = "damage"
@export var power: int = 0
@export var description: String = ""
