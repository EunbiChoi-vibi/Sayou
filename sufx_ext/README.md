# SUFX Tools (SketchUp Extension) — v0.1.0 초기 구현

`SUFX_Tools_기능명세서_v2_최종.md` 기획서를 기반으로 한 SketchUp Ruby 익스텐션 1차 구현입니다.
가구(붙박이장/상부장/하부장) 바디블럭 → 도어/서랍 → 다리/좌대 → 챗넬까지의
파라메트릭 모델링 흐름을 SketchUp 안에서 지원합니다.

## 설치 방법 (테스트용)

1. `sufx_ext.rb`와 `sufx_ext/` 폴더 전체를 SketchUp Plugins 폴더에 복사합니다.
   - Windows: `%APPDATA%\SketchUp\SketchUp 20xx\SketchUp\Plugins\`
   - macOS: `~/Library/Application Support/SketchUp 20xx/SketchUp/Plugins/`
2. SketchUp을 재시작합니다.
3. `Window > Extension Manager`에서 "SUFX Tools"가 활성화되어 있는지 확인합니다.
4. `Extensions > SUFX Tools > SUFX Tools 패널 열기` 메뉴 또는 툴바 아이콘으로 패널을 엽니다.

최소 지원 버전: SketchUp 2021+ (`UI::HtmlDialog` 안정 지원 기준).

## 사용 흐름

1. 매스(그룹)를 하나 선택하고 **Convert**를 누르면 인터랙티브 격자 툴이 시작됩니다.
   - 방향키: 행/열 개수 조정, Tab: 기준면 전환, Enter: 확정, Esc: 취소.
2. 생성된 `SUFX_BODY#n` 블럭을 선택해 **Merge**(동일 타입+인접 병합) / **Div H, Div V**(N등분)로 다듬습니다.
3. 바디블럭을 선택하고 DOOR 섹션의 좌경/우경/반반/서랍 버튼으로 도어를 답니다.
   (DOOR THK/BODY GAP 값은 패널 상단 입력 필드에서 조정, 이후 생성되는 도어부터 적용됩니다.)
4. 도어를 선택한 상태에서 DOOR GAP 섹션의 방향 버튼으로 4방향 갭을 조정하거나 R로 리셋합니다.
5. 바디블럭을 선택하고 Base/Leg + 높이(mm)로 지지대를 추가합니다(Leg는 가림판 자동 생성).
6. 하부장 바디블럭을 선택하고 CHANNEL 섹션에서 없음/상/상+중을 지정합니다.
7. `Extensions > SUFX Tools > SUFX Scale (6-핸들)`로 SUFX 블럭 1개를 선택한 뒤,
   바운딩박스 6개 면-중앙 그립을 드래그해 축별로만 크기를 조정할 수 있습니다.

## 알려진 한계 / 후속 검증 필요 항목 (중요 — 반드시 실기 테스트 필요)

이 저장소에는 SketchUp 실행 환경이 없어 **SketchUp 안에서 직접 실행/검증하지 못했습니다.**
Ruby 문법 검사(`ruby -c`)만 전체 파일에 대해 통과시켰습니다. 아래 항목은 실제 SketchUp에서
반드시 확인하고 필요하면 수정해야 합니다.

- **지오메트리는 모두 직육면체(box) 근사입니다.** Merge/Divide/Door/Base/Leg/Channel 모두
  boolean 연산 대신 box 재생성 방식으로 구현했습니다. 실제 원본 툴처럼 정교한 형상이
  필요하면 각 커맨드의 지오메트리 생성부를 고도화해야 합니다.
- **바디 정면 방향은 -Y로 가정**했습니다(Convert 기본면 index 0과 동일). 실제 모델링
  관례와 다르면 `core/body_block.rb`의 `collect_outer_faces` 순서 및 `commands/door_create.rb`의
  `front_y = combined.min.y` 부분을 조정해야 합니다.
- **Div H/Div V의 축 매핑은 추정값**입니다(H=Z축 분할/상하, V=X축 분할/좌우).
  명세서에 명시되어 있지 않아 `commands/divide.rb` 상단 주석에 가정을 남겨두었습니다.
- **CHANNEL_CLEARANCE, 가림판 두께(18mm), 챗넬 홈 깊이(10mm), DOOR GAP STEP** 등은
  명세서에서도 "placeholder"로 명시한 값입니다. 실측 후 `core/constants.rb`에서 조정하세요.
- **Scale 툴의 "측판 두께 18T 자동 복원"은 미구현(no-op)** 입니다. 현재 바디/도어가
  단일 솔리드 박스라 "측판"이라는 개념이 아직 없기 때문입니다. 바디를 실제 18T 패널
  조합으로 고도화한 뒤 `tools/scale_tool.rb`의 `rebuild_panel_thickness!`를 구현해야 합니다.
- **툴바/메뉴 아이콘 이미지가 없습니다.** `sufx_ext/html/icons/`에 16x24px 아이콘(PNG)을
  추가하고 `main.rb`의 `small_icon`/`large_icon` 경로와 맞추면 됩니다.
- Merge의 "완전 인접" 판정은 축 하나가 맞닿고 나머지 두 축이 겹치는지로 근사했습니다
  (`core/body_block.rb#bbox_touches?`). 부분 겹침도 인접으로 허용되는 점에 유의하세요.

## 파일 구조

기획서 §2 구조를 그대로 따릅니다.

```
sufx_ext.rb                  # 익스텐션 등록 진입점
sufx_ext/
├── main.rb                  # 툴바/메뉴 등록, 로드 순서 관리
├── tools/
│   ├── convert_tool.rb      # Convert 인터랙티브 그리드 (Sketchup::Tool)
│   └── scale_tool.rb        # 6-핸들 커스텀 Scale 툴
├── commands/
│   ├── merge.rb / divide.rb / door_create.rb / door_gap.rb / base_leg.rb / channel.rb
├── core/
│   ├── body_block.rb        # 박스 지오메트리 유틸 (전 커맨드 공용)
│   ├── dynamic_component.rb # SUFX 속성 헬퍼 + DC 확장 지점
│   ├── tag_manager.rb       # SUFX/DOOR 태그 트리
│   ├── naming.rb            # SUFX_BODY#n 등 자동증가 이름
│   └── constants.rb
└── ui/
    ├── panel.html / panel.css / panel.js
    └── panel_controller.rb  # HtmlDialog 생성 + JS↔Ruby 콜백 + SelectionObserver
```
