module Sufx
  module Commands
    # §4.7 Channel(챗넬) — 하부장 바디 전용, 0(없음)/1(상챗넬)/2(상+중챗넬).
    # 정밀 boolean 절삭 대신, 홈 위치를 나타내는 보조 지오메트리를 바디 정의 내부에 만들고
    # SUFX_HIDDEN 태그(§3.3)로 표시한다 — 실제 절삭 형상은 실측 후 고도화 대상.
    # create_drawer(commands/door_create.rb의 :drawer 타입)는 channel_mode를 조회해
    # CHANNEL_CLEARANCE만큼 서랍 상단 높이를 축소한다 — 서랍 연동 요구사항(§4.7) 충족.
    module Channel
      module_function

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

      def rebuild_channel_geometry(model, body, mode)
        body.make_unique if body.respond_to?(:make_unique)
        definition = body.definition
        definition.entities.grep(Sketchup::Group).each do |g|
          g.erase! if Attrs.get(g, 'channel_groove')
        end
        return if mode.to_i.zero?

        clearance = Units.mm_to_inch(Constants::CHANNEL_CLEARANCE[mode] || 0)
        return if clearance <= 0

        bounds = body.bounds
        groove_depth = Units.mm_to_inch(10.0) # 홈 깊이 placeholder(실측 필요)
        min_pt = Geom::Point3d.new(bounds.min.x, bounds.max.y - groove_depth, bounds.max.z - clearance)
        max_pt = Geom::Point3d.new(bounds.max.x, bounds.max.y, bounds.max.z)

        groove = BodyBlock.create_box(definition.entities, min_pt, max_pt)
        Attrs.set(groove, 'channel_groove', true)
        groove.hidden = true
        TagManager.assign(model, groove, Constants::TAG_HIDDEN)
      end
    end
  end
end
