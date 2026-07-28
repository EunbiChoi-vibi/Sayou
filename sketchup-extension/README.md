# Sayou Alt Manager (SketchUp Ruby Extension)

인테리어 디자인 대안(Alt)을 **Tag(레이어) + Scene** 자동화로 관리하는 SketchUp
익스텐션입니다. 기획안(`대안(Alt) 관리 자동화 도구` v2)의 Phase 1(MVP) +
Phase 2 기능을 구현했습니다.

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

모든 삭제/Finalize/Sync Camera 동작은 `UI.messagebox`(예/아니오) 확인을
거칩니다. Topic/Alt 구조는 모델 파일(AttributeDictionary)에 저장되므로 파일을
닫았다가 다시 열어도 유지됩니다.

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
│  │  ├─ alt_manager.rb      # Alt 생성/전환/삭제/Finalize
│  │  └─ scene_sync.rb       # Sync Camera
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

## 알려진 제한 사항 / 다음 단계 제안

- 이 환경에는 SketchUp이 설치되어 있지 않아 **실제 SketchUp에서의 동작
  테스트는 하지 못했습니다.** 설치 후 Week 3~4 로드맵의 완료 기준(트리
  렌더링, Tag/Scene 자동 생성, 파일 재실행 후 복원 등)을 직접 확인해봐
  주세요. 만약 `Sketchup::Layers#remove_layer`처럼 특정 API가 설치된
  SketchUp 버전에서 이름이 다르면 (`core/alt_manager.rb`의
  `remove_alt_resources`) 콘솔 오류 메시지를 알려주시면 바로 수정하겠습니다.
- Phase 3(썸네일 미리보기, 이름 인라인 편집, 드래그 정렬, JSON
  내보내기/불러오기)는 아직 구현하지 않았습니다.
