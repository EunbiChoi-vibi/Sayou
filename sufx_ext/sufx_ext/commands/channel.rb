module Sufx
  module Commands
    # §4.7 Channel(챗넬) — 하부장 바디 전용, 0(없음)/1(상챗넬)/2(상+중챗넬).
    # 정밀 boolean 절삭 대신, 홈 위치를 나타내는 보조 지오메트리를 바디 정의 내부에 만들고
    # SUFX_CHANNEL 태그(§3.3)로 표시한다 — 실제 절삭 형상은 실측 후 고도화 대상.
    # (이전에는 이 보조 지오메트리를 SUFX_HIDDEN 태그 + hidden=true로 만들어서 아예 안 보였다
    # — "챗넬이 생성되지 않는다"는 문제의 원인. 이제는 눈에 보이도록 만든다.)
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

      # 방향: front_normal(§core/body_block.rb#axis_frame)을 기준으로 "뒤쪽 상단"에
      # 홈을 배치한다 — Convert에서 어떤 면을 선택해 만든 바디든 동일하게 동작한다.
      def rebuild_channel_geometry(model, body, mode)
        body.make_unique if body.respond_to?(:make_unique)
        definition = body.definition
        definition.entities.grep(Sketchup::Group).each do |g|
          g.erase! if Attrs.get(g, 'channel_groove')
        end
        return if mode.to_i.zero?

        clearance = Units.mm_to_inch(Constants::CHANNEL_CLEARANCE[mode] || 0)
        return if clearance <= 0

        front_normal_arr = Attrs.get(body, 'front_normal', [0.0, -1.0, 0.0])
        frame = BodyBlock.axis_frame(Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2]))

        bounds = body.bounds
        u_min, u_max = BodyBlock.axis_range(bounds, frame[:u_sym])
        _v_min, v_max = BodyBlock.axis_range(bounds, frame[:v_sym])
        depth_min, depth_max = BodyBlock.axis_range(bounds, frame[:depth_axis])

        groove_depth = Units.mm_to_inch(10.0) # 홈 깊이 placeholder(실측 필요)
        back_val = frame[:depth_sign].positive? ? depth_min : depth_max
        groove_far_val = back_val + (frame[:depth_sign] * groove_depth)

        p0 = BodyBlock.point_on_frame(frame, back_val, u_min, v_max - clearance)
        p1 = BodyBlock.point_on_frame(frame, groove_far_val, u_max, v_max)

        groove = BodyBlock.create_box(definition.entities, p0, p1)
        Attrs.set(groove, 'channel_groove', true)
        groove.material = GROOVE_COLOR
        TagManager.assign(model, groove, Constants::TAG_CHANNEL)
      end
    end
  end
end
