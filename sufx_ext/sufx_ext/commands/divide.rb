module Sufx
  module Commands
    # §4.4 Divide — 바디블럭 1개를 N등분한다.
    # axis :h(Div H) = 가로 분할선을 넣어 위/아래로 나눔 (Z축 분할)
    # axis :v(Div V) = 세로 분할선을 넣어 좌/우로 나눔 (X축 분할)
    # NOTE: 원본 툴의 실제 축 매핑은 명세서에 명시되어 있지 않아 추정값이다.
    # SketchUp 내 실동작 확인 후 반대로 뒤집어야 하면 slice_segment의 :h/:v 분기만 교체하면 된다.
    module Divide
      module_function

      def run!(axis, count)
        model = Sketchup.active_model
        selection = model.selection.to_a
        unless selection.size == 1 && Attrs.block_type(selection.first) == 'body'
          Sketchup.status_text = 'SUFX Divide: 바디블럭 1개를 선택하세요.'
          return false
        end
        return false unless count.is_a?(Integer) && count >= 2 # §4.4: 잘못된 입력은 조용히 무시

        body = selection.first
        bounds = body.bounds
        model.start_operation('SUFX Divide', true)
        begin
          count.times do |i|
            sub_min, sub_max = slice_segment(bounds, axis, i, count)
            group = BodyBlock.create_box(model.active_entities, sub_min, sub_max)
            comp = group.to_component
            comp.definition.name = Naming.next_name(Constants::NAME_BODY)
            Attrs.copy(body, comp)
            Attrs.set(comp, 'block_type', 'body')
            TagManager.assign(model, comp, Constants::TAG_BODY)
          end
          body.erase! unless body.deleted?
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("SUFX Divide 실패: #{e.message}")
          return false
        end
        true
      end

      def slice_segment(bounds, axis, index, count)
        min = bounds.min
        max = bounds.max
        if axis == :h
          step = (max.z - min.z) / count.to_f
          sub_min = Geom::Point3d.new(min.x, min.y, min.z + step * index)
          sub_max = Geom::Point3d.new(max.x, max.y, min.z + step * (index + 1))
        else
          step = (max.x - min.x) / count.to_f
          sub_min = Geom::Point3d.new(min.x + step * index, min.y, min.z)
          sub_max = Geom::Point3d.new(min.x + step * (index + 1), max.y, max.z)
        end
        [sub_min, sub_max]
      end
    end
  end
end
