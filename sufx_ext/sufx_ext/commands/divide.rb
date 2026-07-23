module Sufx
  module Commands
    # §4.4 Divide — 바디블럭 1개를 N등분한다.
    # Div H(axis: :h) = 가로 분할선을 넣어 위/아래로 나눔 (그 바디의 세로/높이축 분할)
    # Div V(axis: :v) = 세로 분할선을 넣어 좌/우로 나눔 (그 바디의 가로/폭축 분할)
    #
    # 어느 월드축이 "폭"이고 "높이"인지는 Convert에서 그 바디를 만들 때 저장해둔
    # front_normal(§core/body_block.rb#axis_frame)로 결정한다 — 월드 X/Z를 고정
    # 가정하면 Convert에서 Tab으로 다른 면을 선택해 만든 바디에서는 엉뚱한 방향으로
    # 잘리기 때문에, 반드시 그 바디 자신의 축을 기준으로 나눠야 한다.
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
        front_normal_arr = Attrs.get(body, 'front_normal', [0.0, -1.0, 0.0])
        frame = BodyBlock.axis_frame(Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2]))
        split_axis = axis == :h ? frame[:v_sym] : frame[:u_sym]

        model.start_operation('SUFX Divide', true)
        begin
          count.times do |i|
            sub_min, sub_max = slice_segment(bounds, split_axis, i, count)
            group = build_divided_group(model, body, sub_min, sub_max)
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

      # Divide로 나뉜 조각도 통짜 솔리드가 아니라 원래 바디의 쉘 구조(측/뒷/상/하판, front_normal)를
      # 그대로 유지한 채 새 바운딩박스로 재생성한다.
      def build_divided_group(model, reference, sub_min, sub_max)
        front_normal_arr = Attrs.get(reference, 'front_normal', [0.0, -1.0, 0.0])
        front_normal = Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2])
        panel_thk = Units.mm_to_inch(Attrs.get(reference, 'panel_thk', Constants::DEFAULT_PANEL_THK).to_f)
        back_thk = Units.mm_to_inch(Attrs.get(reference, 'back_panel_thk', Constants::DEFAULT_BACK_PANEL_THK).to_f)

        BodyBlock.build_shell_from_bounds(model.active_entities, sub_min, sub_max, front_normal, panel_thk, back_thk)
      end

      # split_axis(:x/:y/:z) 방향으로만 균등 분할하고, 나머지 두 축은 원래 바디의 전체
      # 범위를 그대로 유지한다.
      def slice_segment(bounds, split_axis, index, count)
        min = bounds.min
        max = bounds.max
        lo = axis_component(min, split_axis)
        hi = axis_component(max, split_axis)
        step = (hi - lo) / count.to_f

        sub_min = with_axis_component(min, split_axis, lo + (step * index))
        sub_max = with_axis_component(max, split_axis, lo + (step * (index + 1)))
        [sub_min, sub_max]
      end

      def axis_component(point, axis)
        case axis
        when :x then point.x
        when :y then point.y
        else point.z
        end
      end

      def with_axis_component(point, axis, value)
        Geom::Point3d.new(
          axis == :x ? value : point.x,
          axis == :y ? value : point.y,
          axis == :z ? value : point.z
        )
      end
    end
  end
end
