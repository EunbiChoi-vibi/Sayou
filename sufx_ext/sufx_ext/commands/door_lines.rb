module Sufx
  module Commands
    # 도어 리프 전면에 좌경/우경/반반/서랍 타입을 구분하는 표시선을 그린다.
    # 실제 지오메트리를 깎지는 않는 순수 Edge이며, 숨김 처리하지 않고 항상 보이게
    # 둔다. SUFX_DOORLINE 태그(§core/tag_manager.rb)에 Center 라인 스타일을
    # 지정해두어(중간중간 끊어지는 1점쇄선) 일반 모델 선과 구분되는 표시선으로 보인다.
    #
    # Door Create/Door Gap이 도어 박스를 (재)생성할 때마다 이 메서드도 같이 호출해야
    # 한다 — redefine_box!/fill_box_faces가 entities를 clear!하기 때문에, 표시선도
    # 지오메트리와 함께 매번 다시 그려야 유지된다.
    #
    # 방향 규칙(사용자 확정):
    #   좌경(왼쪽 힌지): 오른쪽위 -> 왼쪽중앙(힌지) -> 오른쪽아래
    #   우경(오른쪽 힌지): 좌경과 좌우 대칭(왼쪽위 -> 오른쪽중앙(힌지) -> 왼쪽아래)
    #   반반(양개): 왼쪽 짝은 좌경 형태, 오른쪽 짝은 우경 형태로 각각 자기 폭 기준으로 그림
    #     (결과적으로 칸 4변의 중점을 잇는 마름모가 된다)
    #   서랍: 오른쪽위 -> 왼쪽아래 대각선 하나
    module DoorLines
      module_function

      def draw!(door, frame, depth_val, u0, u1, v0, v1, door_type, leaf_side)
        entities = door.definition.entities
        mid_u = (u0 + u1) / 2.0
        mid_v = (v0 + v1) / 2.0

        style = door_type.to_s == 'double' ? leaf_side.to_s : door_type.to_s

        path =
          case style
          when 'left'
            [pt(frame, depth_val, u1, v1), pt(frame, depth_val, u0, mid_v), pt(frame, depth_val, u1, v0)]
          when 'right'
            [pt(frame, depth_val, u0, v1), pt(frame, depth_val, u1, mid_v), pt(frame, depth_val, u0, v0)]
          when 'drawer'
            [pt(frame, depth_val, u1, v1), pt(frame, depth_val, u0, v0)]
          else
            []
          end
        return if path.size < 2

        model = Sketchup.active_model
        path.each_cons(2) do |a, b|
          Array(entities.add_line(a, b)).each do |edge|
            next unless edge.is_a?(Sketchup::Edge)

            TagManager.assign(model, edge, "#{Constants::TAG_DOOR_FOLDER}/#{Constants::TAG_DOORLINE}")
          end
        end
      end

      def pt(frame, depth_val, u_val, v_val)
        BodyBlock.point_on_frame(frame, depth_val, u_val, v_val)
      end
    end
  end
end
