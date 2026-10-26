# 아웃게임 프로토타입 — Godot 4.7 개발 전달서 v0.2

> 모든 엔진 구조·클래스명·테스트 수치·입력 편의 기능은 **구현용 제안**이다. 플레이어가 확정한 기능은 `01_OUTGAME_GDD_v0_1.md`를 기준으로 한다. 이미 제작된 전투 프로토타입은 손상하지 말고 독립 아웃게임 씬으로 추가한다.

## 1. 구현 목표

2048-04-07에서 시작하는 기지 단면 화면에서 (1) WASD 이동, (2) 검은 잠금 방 달러 해금, (3) NPC 주간 스케줄 이동, (4) 직접 대화/엿듣기/요청, (5) 일일 오염·청소 명령, (6) 주간 결산 및 월간 점검, (7) 훈련·제작·강화 더미 메뉴, (8) 저장/로드가 실제로 동작하게 한다.

## 2. 씬과 서비스 분할 [제안]

```text
res://
  scenes/outgame/base_hub.tscn
  scenes/outgame/facility_room.tscn
  scenes/outgame/npc_agent.tscn
  scenes/outgame/ui/outgame_hud.tscn
  scenes/outgame/ui/facility_unlock_popup.tscn
  scenes/outgame/ui/npc_context_menu.tscn
  scenes/outgame/ui/dialogue_popup.tscn
  scenes/outgame/ui/weekly_statement.tscn
  scenes/outgame/ui/inspection_report.tscn
  scenes/editor/npc_weekly_schedule_editor.tscn
  scripts/outgame/world_clock.gd
  scripts/outgame/base_map_controller.gd
  scripts/outgame/camera_controller.gd
  scripts/outgame/facility_registry.gd
  scripts/outgame/npc_agent_controller.gd
  scripts/outgame/npc_schedule_resolver.gd
  scripts/outgame/room_route_service.gd
  scripts/outgame/interaction_router.gd
  scripts/outgame/dialogue_event_service.gd
  scripts/outgame/cleaning_service.gd
  scripts/outgame/task_assignment_service.gd
  scripts/outgame/economy_ledger.gd
  scripts/outgame/weekly_settlement_service.gd
  scripts/outgame/monthly_inspection_service.gd
  scripts/outgame/outgame_save_service.gd
  data/outgame/facilities/*.tres
  data/outgame/npcs/*.tres
  data/outgame/schedules/*.tres
  data/outgame/dialogues/*.tres
  data/outgame/jobs/*.tres
  data/outgame/events/*.tres
```

- UI는 표시와 명령 발송만 담당하고, 시간/경제/청소/위생/경로 처리 로직을 UI 버튼 내부에 넣지 않는다.
- 전투 프로토타입의 `character_id`/`weapon_id`와 매핑하는 별도 어댑터를 둘 수 있으나 **실제 전투 씬 구조를 수정하지 않는다**.

## 3. 필수 상태 데이터 [제안]

```text
WorldState:
  absolute_date, minute_of_day, elapsed_game_minutes,
  current_week_index, current_month_key, rng_seed

BaseState:
  cash_usd, room_unlock_states, room_cleanliness,
  dirt_objects, assigned_jobs, training_jobs,
  crafting_jobs, inspection_history, economy_ledger

NpcState:
  npc_id, position, current_facility_id, current_action,
  active_command, weekly_schedule_id, dialogue_flags,
  request_flags, current_path, busy_until

EconomyState:
  ledger_entries, settled_week_ids, pending_inspection_bonuses,
  completed_job_ids, claimed_contract_ids
```

**고유 ID와 저장 보장:** 방 ID, 인물 ID, 의뢰 ID, 월별 점검 ID, 주별 결산 ID를 고정하고 저장/로드 후 재생성에 따른 중복 지불을 방지한다.

## 4. 이벤트 버스 [제안]

`hour_changed`, `day_changed`, `week_finished`, `month_changed`, `room_unlocked`, `npc_state_changed`, `dialogue_requested`, `cleanliness_changed`, `job_completed`, `inspection_completed`, `statement_ready`.

- 시계만 날짜 경과를 결정한다. UI나 NPC가 각자 `day_changed`를 발생시키지 않는다.
- 이벤트 처리 순서는 **하루 전환 → 일정 갱신 → 일일 오염** 등으로 일관되게 정해 로그가 동일하게 재현되게 한다.
- 점검은 월별 한 번, 주간 결산은 주 ID별 한 번만 적용한다.

## 5. 공간/경로 구현

- **카메라**: `Camera2D`, WASD용 입력 액션, 맵 바운드 제한.
- **기지**: 씬에 미리 배치된 3개 층 단면과 방 직사각형 영역. **해금은 이미 있는 방의 표시/접근을 전환**하는 동작이다.
- **NPC**: 2D 이동 경로를 시설 단위 연결 그래프 + 내부 경유점으로 설계. 길이 열려 있는지 검사하고, 방 잠금 해제 후 그래프 연결 갱신.
- 경로 알고리즘은 소규모 프로토타입에서 AStar2D 또는 선형 그래프/웨이포인트로 시작 가능. 실제 실내 충돌 수준에 따라 수정.
- 캐릭터가 클릭 대상 근처에 있으면 대화 시작, 말풍선은 캐릭터 화면 위치 기준으로 부착.

## 5.1 승인된 추가 기능의 구현 연결

**시설 해금 → 생활 변화:** `room_unlocked(room_id)` 발생 시 해당 시설 해금 조건을 가진 NPC의 주간 일정 분기를 재평가한다. 출입 가능 경로도 갱신한다. 실제 NPC별 활동 변화는 에디터 데이터로 결정한다. [구현 방식 임시]

**엿듣기 → 스토리 발견:** 대원 간 `conversation_event_id`를 스토리 대사/이벤트 데이터와 연결한다. 말풍선 클릭으로 해당 대화가 재생되어 스토리 관련 내용을 읽을 수 있도록 한다. 단서 수집 UI 또는 후속 이벤트 자동 개방은 승인되지 않았으므로 구현 의무가 아니다. [구현 방식 임시]

## 6. 하루/주/월 이벤트 계산

### 날짜 전환
- 누적 분이 1440을 넘을 때마다 정확히 하루 증가.
- 일일 오염 생성: 열린 구역 중 오염 이벤트 대상 위치를 난수 시드 기반으로 선택.
- NPC 일정 날짜/요일을 다시 조회.

### 주간 결산
- **임시 주기**: 시작 시점부터 7일 경과할 때 `week_index` 증가.
- 행정 지원금은 그 주에 한 번만 지급.
- 의뢰·대원 작업 완료 수익은 완료 시 원장에 기록하거나 정산 때 반영하도록 데이터형을 통일(중복 지급 금지). 초기 버전에서는 **작업 완료 시 미지급 수익으로 누적 → 결산 시 현금 반영**을 임시 권장.
- 해당 주 월간 점검의 추가 달러를 동일 결산 항목에 포함.

### 월간 장군 점검
- 월 시작 시 또는 게임 시작 로드 시, 아직 점검하지 않은 월이면 그 달의 **남은 유효 날짜 중 하나**를 난수로 선정.
- 시계가 점검 시점에 도달하면 청결 상태를 채점하고 `month_key`의 점검 완료 플래그 기록.
- 보너스는 `week_id`로 귀속. 동일 월에 다음 검사를 다시 뽑지 않음.

> 점검 날짜 무작위, 게임 시간 스케일, 달러 금액과 점수 공식 등은 모두 밸런싱 전용 설정으로 분리.

## 7. 프로토타입 테스트 데이터 [전부 더미]

```yaml
clock:
  game_minutes_per_real_second: 1
  start_datetime: '2048-04-07 08:00'
  week_length_days: 7
base:
  floor_count: 3
  initial_open_floors: [ground_1, basement_1]
  cash_usd: 150
  locked_room_costs_usd: [50, 90]
economy:
  weekly_subsidy_usd: 100
  dummy_contract_reward_usd: 40
hygiene:
  initial_cleanliness: 90
  daily_dirt_events: [1, 2]
  cleaning_action_seconds_game: 20
inspection:
  demo_bonus_usd: [0, 30, 60]
npcs:
  count: 4
```

- 게임 시작 시간 08:00은 UI 테스트를 위한 임시 선택. **사용자가 확정한 것은 날짜(2048-04-07), 24시간 하루 체계**뿐이다.
- 값은 프로토타입 가독성/빠른 기능 검증을 위한 것이며 세계관·최종 경제 밸런스 확정이 아니다.

## 8. 기능별 개발 순서

| 단계 | 구현 산출물 | 성공 기준 |
|---|---|---|
| P0 | 기지 단면/검은 잠금 방/WASD/달러 해금 | 장소 자유 관찰, 달러 감소, 잠금 해제 지속 |
| P1 | 시계/7일 시간표 에디터/NPC 이동 | NPC가 날짜·시간에 맞춰 이동, 잠긴 방 회피 |
| P2 | 직접 대화/엿듣기/`!` 요청 | 입력별 다른 UI와 이벤트 상태 반영 |
| P3 | 일일 오염/캐릭터 청소/위임 | 지정 캐릭터 또는 위임 대상 이동 후 오염 제거 |
| P4 | 임무/업무/주간 지원금·결산 | 중복 지급 없음, 금액 내역 확인 |
| P5 | 월간 장군 점검 | 월별 1회, 평가 점수, 해당 주 보너스 |
| P6 | 훈련/제작/강화 더미/저장·로드 | 인물·무기 데이터 변경 및 재시작 후 유지 |
| P7 | 미국 카툰풍/극명 원색 실내 라이트 적용 | 가독성/성능을 유지하면서 그래픽 목표 시연 |

## 9. 개발 AI를 위한 필수 금지 사항

- 사용자가 지시하지 않은 **자유 건설·랜덤 룸 배치**를 추가하지 않는다.
- 카메라에 주인공 캐릭터를 스폰하지 않는다.
- 점검을 주간 확률 이벤트로 바꾸지 않는다. **월 1회 랜덤 일자**가 확정이다.
- 잠금 해금을 재료/시간제로 바꾸지 않는다. **달러**가 확정이다.
- 외부 의뢰·시설/부대 캐릭터·직업 이름·훈련 비용·무기 레시피를 확정하지 않는다.
- 기존 전투 명령·AP 시스템을 바꾸지 않는다.
- UI 클릭·저장·이벤트 발생으로 같은 재정 처리가 여러 번 적용되지 않게 한다.
- 셰이더 적용을 위해 NPC 또는 UI 식별성까지 훼손하지 않는다.

## 10. 검증 자동화 권장

- 날짜 테스트: 2048-04-07 23:59 → 2048-04-08 00:00; 월말·연말 이동.
- 달러 테스트: 해금 비용 부족/정확/초과, 중복 클릭 방지.
- NPC 테스트: 매일 다른 목적지, 잠금 공간, 대화 중 일정 변경, 청소 지시/위임.
- 대화 테스트: 일반 클릭·NPC끼리 말풍선·요청 수락 동시 발생 충돌 방지.
- 주간 테스트: 7/14/21일 경과마다 정산 1회; 시간 건너뛰기 후에도 중복 없음.
- 월간 테스트: 달 중간 저장 후 재시작해도 점검 1회; 점검 보너스 해당 주에만 지급.
- 저장 테스트: 날짜·돈·해금·스케줄·NPC 상태·위생·점검/원장 복원.
