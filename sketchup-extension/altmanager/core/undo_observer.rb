# Sayou Alt Manager - Undo/Redo 감지
#
# 사용자가 SketchUp 기본 Undo(Ctrl+Z)로 Tag/Scene 변경을 되돌리면, 패널에
# 남아있는 화면은 이전 상태를 계속 보여줘 실제 모델과 어긋나 보일 수 있다.
# ModelObserver로 Undo/Redo 트랜잭션을 감지해 패널을 다시 그리게 한다.
# (AttributeDictionary 저장도 main.rb의 run_op가 Tag/Scene 변경과 같은
# 트랜잭션에 묶어 저장하므로, Undo 한 번으로 실제 모델과 패널 데이터가
# 함께 되돌아간다 - 이 관찰자는 그 결과를 화면에 반영하는 역할만 한다.)

module SayouAltManager
  class UndoObserver < Sketchup::ModelObserver
    def onTransactionUndo(_model)
      SayouAltManager.push_state
    end

    def onTransactionRedo(_model)
      SayouAltManager.push_state
    end
  end
end
