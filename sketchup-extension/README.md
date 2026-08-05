# Sayou Alt Manager (SketchUp Ruby Extension)

인테리어 디자인 대안(Alt)을 **Tag(레이어) + Scene** 자동화로 관리하는 SketchUp
익스텐션입니다. 기획안(`대안(Alt) 관리 자동화 도구` v2)의 Phase 1(MVP) +
Phase 2 기능에 더해, Phase 3 중 아래 4가지를 추가로 구현했습니다.

- Alt 썸네일 미리보기
- Undo/Redo 시 패널 자동 새로고침
- Alt 이름 인라인(더블클릭) 편집
- Topic 이름 내보내기/불러오기(JSON)

## 설치

1. 이 폴더(`sketchup-extension/`) 안의 `altmanager.rb`와 `altmanager/` 폴더를
   SketchUp Plugins 폴더에 복사합니다.
   - Windows: `%APPDATA%\SketchUp\SketchUp <버전>\SketchUp\Plugins`
   - macOS: `~/Library/Application Support/SketchUp <버전>/SketchUp/Plugins`
2. SketchUp을 재시작하면 **Extensions(Plugins) 메뉴 > Alt Manager**가 나타납니다.

`.rbz`로 패키징해서 Extension Manager로 설치하고 싶다면:

```bash
cd sketchup-extension
./build.sh   # dist/sayou_altmanager.rbz 생성
```

## 사용법

1. **Topic 생성**: 상단 입력창에 이름(예: "거실 욕실")을 입력하고 Create.
2. **Alt 등록**: 모델에서 대안이 될 그룹(또는 컴포넌트/엔티티들)을 선택한 뒤,
   해당 Topic 행의 `+` 버튼 클릭 → Tag/Scene이 자동 생성되고 A, B, C… 순서로
   버튼이 추가됩니다.
3. **Alt 전환**: A/B/C 버튼을 클릭하면 해당 Tag만 보이도록 전환되고, 그 Alt의
   Scene으로 즉시 이동합니다. 선택된 버튼은 하이라이트됩니다.
4. **Delete**: Alt 버튼을 선택한 상태(또는 Topic 이름을 클릭해 선택한 상태,
   혹은 Topic 행 우클릭)에서 하단 Delete 클릭 → 확인 팝업 후 삭제.
5. **Sync Camera**: 현재 SketchUp 화면의 카메라 값을 등록된 모든 Alt Scene에
   일괄 반영합니다.
6. **Finalize**: 현재 선택된 Alt만 남기고, 같은 Topic의 나머지 Alt(Tag/Scene/
   엔티티)를 정리합니다.
7. **썸네일**: Alt를 등록하거나 전환할 때마다 그 시점의 화면을 작게 캡처해
   버튼 위에 미리보기로 보여줍니다.
8. **이름 바꾸기**: Alt 카드 아래 이름 텍스트를 더블클릭하면 바로 수정할 수
   있습니다(A/B/C 같은 원래 이름은 내부적으로 유지되고, 화면 표시용 이름만
   바뀝니다).
9. **Import / Export**: 상단 작은 버튼으로 이 파일의 Topic 이름 목록을 JSON
   으로 내보내거나, 다른 파일에서 내보낸 JSON을 불러와 같은 이름의 Topic을
   빠르게 세팅할 수 있습니다.

모든 삭제/Finalize/Sync Camera 동작은 `UI.messagebox`(예/아니오) 확인을
거칩니다. Topic/Alt 구조는 모델 파일(AttributeDictionary)에 저장되므로 파일을
닫았다가 다시 열어도 유지되고, SketchUp Undo/Redo와도 함께 되돌아갑니다.

## 폴더 구조

```
sketchup-extension/
├─ altmanager.rb            # 로더(진입점, extension 등록)
├─ altmanager/
│  ├─ main.rb                # 대화상자, 메뉴, JS<->Ruby 콜백, 전역 상태
│  ├─ ui/
│  │  ├─ dialog.html
│  │  ├─ style.css
│  │  └─ script.js
│  ├─ core/
│  │  ├─ topic_manager.rb    # Topic 생성/조회/삭제
│  │  ├─ alt_manager.rb      # Alt 생성/전환/이름변경/삭제/Finalize/썸네일
│  │  ├─ scene_sync.rb       # Sync Camera
│  │  ├─ import_export.rb    # Topic 이름 내보내기/불러오기
│  │  └─ undo_observer.rb    # Undo/Redo 감지 -> 패널 새로고침
│  └─ data/
│     └─ store.rb            # AttributeDictionary 읽기/쓰기
└─ build.sh                  # .rbz 패키징 스크립트
```

## 구현하며 정리한 세부 규칙 (기획안에 명시되지 않아 판단한 부분)

- **Alt와 엔티티의 연결고리**: 별도 ID 매핑 없이 "그룹의 Tag"로만 연결합니다.
  엔티티 삭제가 필요할 때는 `model.layers.remove_layer(tag, true)` 한 번으로
  해당 Tag가 걸린 모든 엔티티(중첩 그룹 포함)를 SketchUp이 정리합니다. 저장
  후 다시 열어도 끊어지지 않는 가장 안정적인 방식이라 이렇게 결정했습니다.
- **Alt 전환 범위**: "다른 Alt Tag는 숨김" 처리는 **같은 Topic 안에서만**
  적용됩니다. 다른 Topic의 현재 선택 Alt는 그대로 유지되어, 예를 들어
  "거실 욕실" Alt B를 보면서 동시에 "현관" Alt A도 계속 보이는 식의
  다중 Topic 동시 확인이 가능합니다.
- **Topic 삭제 트리거**: 기획안에 "Topic 우클릭 또는 Delete(Topic 선택 상태)"
  두 가지가 언급되어 있어 둘 다 구현했습니다. Topic 이름을 좌클릭하면
  "선택" 상태가 되고 이 상태에서 하단 Delete를 누르면 Topic이 삭제되며,
  Topic 행을 우클릭하면 선택 없이 바로 삭제 확인 팝업이 뜹니다.
- **Alt 이름 자릿수**: A~Z를 다 쓰면 A1, B1… 형식으로 넘어가도록 처리했습니다
  (기획안에는 언급 없음, 26개 이상 Alt가 생기는 예외 상황 대비).
- **저장/트랜잭션 통합**: 모든 데이터 변경 콜백은 `main.rb`의 `run_op`
  헬퍼를 거쳐 "SketchUp 쪽 변경 + AttributeDictionary 저장"을 하나의
  `start_operation`/`commit_operation`으로 묶습니다. 그래야 Undo 한 번으로
  Tag/Scene 변경과 패널 데이터가 항상 같이 되돌아갑니다(아래 Undo 항목 참고).
- **썸네일 저장 방식**: Tag 위치에 파일 경로 대신 base64 데이터 URI
  (`data:image/png;base64,...`)를 패널 데이터에 실어 보냅니다. HtmlDialog가
  `file://` 절대경로 접근을 제한하는 환경(특히 macOS)이 있어, 캡처한 PNG를
  임시 폴더(`Sketchup.temp_dir`)에 썼다가 바로 인코딩하고 원본은 지웁니다.
  Alt가 많아지면 AttributeDictionary/JSON 크기가 커지는 트레이드오프가
  있지만, 안정성을 우선했습니다.
- **Alt 이름 변경 범위**: 더블클릭으로 바꾸는 이름은 화면 표시용
  (`display_name`)만 바꾸고, 실제 SketchUp Tag/Scene 이름(`tag`/`scene`
  필드)은 건드리지 않습니다. Tag/Scene 이름까지 바꾸려면 SketchUp 쪽 rename
  API 호출과 데이터 참조 업데이트를 함께 해야 해서 실패 시 참조가 깨질
  위험이 있어, 더 안전한 쪽을 택했습니다.
- **Import/Export 범위**: Tag/Scene/Group은 SketchUp 파일마다 고유한
  객체라 파일 간에 그대로 옮길 수 없습니다. 그래서 "Topic 이름 목록"만
  내보내고 불러오도록 스코프를 좁혔습니다 — 다른 파일에서 같은 Topic들을
  빠르게 만든 뒤, Alt는 각 파일에서 실제 그룹을 선택해 `+`로 새로 등록하는
  흐름입니다. (Alt까지 통째로 옮기는 건 애초에 대상 파일에 원본 지오메트리가
  없어 불가능한 요구라 스코프에서 뺐습니다.)
- **Undo 옵저버 범위**: `ModelObserver`는 패널을 열 때의 활성 모델에만
  붙습니다. SketchUp에서 여러 파일(문서 창)을 동시에 열어두고 그 사이를
  전환하는 경우까지는 대응하지 않습니다 — 필요하시면 `AppObserver`로
  확장해서 모델 전환 시 관찰자를 재연결하도록 다음 버전에서 보완할 수
  있습니다.

## 알려진 제한 사항 / 다음 단계 제안

- 이 환경에는 SketchUp이 설치되어 있지 않아 **실제 SketchUp에서의 동작
  테스트는 하지 못했습니다.** 설치 후 Week 3~4 로드맵의 완료 기준(트리
  렌더링, Tag/Scene 자동 생성, 파일 재실행 후 복원 등)과 이번에 추가한
  썸네일/Undo/이름변경/Import-Export를 직접 확인해봐 주세요. 특히 아래
  API들은 설치된 SketchUp 버전에 따라 동작이 달라질 수 있는 지점입니다.
  콘솔 오류 메시지를 알려주시면 바로 수정하겠습니다.
  - `Sketchup::Layers#remove_layer` (`core/alt_manager.rb`)
  - `Sketchup::View#write_image` 옵션 키(`core/alt_manager.rb`의
    `capture_thumbnail`)
  - `UI::HtmlDialog#set_on_closed` (`main.rb`)
- 남은 Phase 3 항목(드래그 정렬)은 아직 구현하지 않았습니다.
