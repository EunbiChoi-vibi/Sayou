module Sufx
  module Commands
    # §4.7 Channel(챗넬) — 하부장 바디 전용, 0(없음)/1(상챗넬)/2(상+중챗넬).
    # 본체 내부를 가로지르는 얇은 가로 레일(서랍 레일 느낌) 부재로 구현한다.
    #   CH1(상챗넬): 상판 바로 아래에 레일 1개
    #   CH2(상+중챗넬): CH1 레일 + 본체 세로 중앙에 레일 1개 추가
    # 각 레일은 폭 전체를 채우되, 깊이는 뒤쪽에서 CHANNEL_RAIL_DEPTH만큼만(서랍 레일처럼 좁게).
    # 정밀 boolean 절삭이 아니라 실제 지오메트리(솔리드 레일)를 삽입하는 방식이며,
    # SUFX_CHANNEL 태그로 표시해 구분한다.
    # create_drawer(commands/door_create.rb의 :drawer 타입)는 channel_mode를 조회해
    # CHANNEL_CLEARANCE만큼 서랍 상단 높이를 축소한다 — 서랍 연동 요구사항(§4.7) 충족.
    module Channel
      module_function

      GROOVE_COLOR = Sketchup::Color.new(255, 140, 0).freeze # 확정 지오메트리가 아님을 표시하는 주황색

      def run!(mode)
        model = Sketchup.active_model
        bodies = model.selection.to_a.select { |e| Attrs.block_type(e) == 'body' }
        if bodies.empty?
          msg = '바디블럭을 1개 이상 선택하세요.'
          Sketchup.status_text = "SUFX Channel: #{msg}"
          return [false, msg]
        end

        model.start_operation('SUFX Channel', true)
        begin
          bodies.each { |body| set_channel(model, body, mode) }
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("SUFX Channel 실패: #{e.message}")
          return [false, e.message]
        end
        [true, nil]
      end

      def set_channel(model, body, mode)
        Attrs.set(body, 'channel_mode', mode)
        rebuild_channel_geometry(model, body, mode)
      end

      # 방향: front_normal(§core/body_block.rb#axis_frame)을 기준으로 배치한다 — Convert에서
      # 어떤 면을 선택해 만든 바디든 동일하게 동작한다.
      def rebuild_channel_geometry(model, body, mode)
        body.make_unique if body.respond_to?(:make_unique)
        definition = body.definition
        definition.entities.grep(Sketchup::Group).each do |g|
          g.erase! if Attrs.get(g, 'channel_groove')
        end
        return if mode.to_i.zero?

        front_normal_arr = Attrs.get(body, 'front_normal', [0.0, -1.0, 0.0])
        frame = BodyBlock.axis_frame(Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2]))

        bounds = body.bounds
        u_min, u_max = BodyBlock.axis_range(bounds, frame[:u_sym])
        v_min, v_max = BodyBlock.axis_range(bounds, frame[:v_sym])
        depth_min, depth_max = BodyBlock.axis_range(bounds, frame[:depth_axis])

        panel_thk = Units.mm_to_inch(Attrs.get(body, 'panel_thk', Constants::DEFAULT_PANEL_THK).to_f)
        rail_thk = Units.mm_to_inch(Constants::CHANNEL_RAIL_THK)
        rail_depth = Units.mm_to_inch(Constants::CHANNEL_RAIL_DEPTH)

        back_val = frame[:depth_sign].positive? ? depth_min : depth_max
        rail_front_val = back_val + (frame[:depth_sign] * rail_depth) # 뒤에서 앞으로 rail_depth만큼만

        # CH1: 상판 바로 아래
        top_hi = v_max - panel_thk
        top_lo = top_hi - rail_thk
        add_rail(model, definition.entities, frame, back_val, rail_front_val, u_min, u_max, top_lo, top_hi)

        # CH2: CH1 + 본체 세로 중앙에 레일 하나 더
        return unless mode.to_i >= 2

        mid = (v_min + v_max) / 2.0
        add_rail(model, definition.entities, frame, back_val, rail_front_val, u_min, u_max,
                 mid - (rail_thk / 2.0), mid + (rail_thk / 2.0))
      end

      def add_rail(model, entities, frame, depth_a, depth_b, u_a, u_b, v_a, v_b)
        p0 = BodyBlock.point_on_frame(frame, depth_a, u_a, v_a)
        p1 = BodyBlock.point_on_frame(frame, depth_b, u_b, v_b)
        rail = BodyBlock.create_box(entities, p0, p1)
        Attrs.set(rail, 'channel_groove', true)
        rail.material = GROOVE_COLOR
        TagManager.assign(model, rail, Constants::TAG_CHANNEL)
        rail
      end
    end
  end
end
