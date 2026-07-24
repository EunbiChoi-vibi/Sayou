module Sufx
  module Commands
    # §4.7 Channel(챗넬) — 하부장 바디 전용, 0(없음)/1(상챗넬)/2(상+중챗넬).
    #
    # 챗넬을 켜면 바디 자체의 깊이가 Convert 때 탭으로 선택한 전면 기준으로
    # CHANNEL_RECESS_MM만큼 줄어든다(측/뒷/상하판을 그만큼 뒤로 물려서 쉘 전체를 재생성).
    # 그렇게 파낸 자리에 챗넬 브라켓 매스를 채운다 — 브라켓은 가로로 폭 전체를 가로지르는
    # 세로 CHANNEL_BAND_H_MM 높이의 면이며, 새로 생긴 면에서 원래 전면 위치까지
    # (=CHANNEL_RECESS_MM 두께로) 매스가 튀어나온다. 그 중 아래쪽 CHANNEL_LIP_H_MM 구간만
    # 원래 전면보다 CHANNEL_LIP_EXTRA_MM만큼 더 튀어나와 단턱(계단) 형태를 만든다.
    #   CH1(상챗넬): 브라켓 1개, 상판 바로 아래
    #   CH2(상+중챗넬): CH1 브라켓 + 본체 세로 중앙에 브라켓 1개 추가
    #
    # 정밀 boolean 절삭이 아니라 실제 지오메트리(박스 조합)를 매번 처음부터 재구성하는
    # 방식이다. 최초 1회 캡처해둔 channel_orig_bounds(파내기 전의 전체 바디 바운드)를
    # 기준으로 매 호출마다 바디 내부 전체(쉘 + 브라켓)를 다시 만들어야, CH1<->CH2<->없음을
    # 오갈 때 깊이가 중첩 축소되지 않고 항상 같은 기준에서 재계산된다.
    # create_drawer(commands/door_create.rb의 :drawer 타입)는 channel_mode를 조회해
    # CHANNEL_CLEARANCE만큼 서랍 상단 높이를 축소한다 — 서랍 연동 요구사항(§4.7) 충족.
    module Channel
      module_function

      GROOVE_COLOR = Sketchup::Color.new(255, 140, 0).freeze

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

        min_pt, max_pt = origin_bounds(body)

        front_normal_arr = Attrs.get(body, 'front_normal', [0.0, -1.0, 0.0])
        front_normal = Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2])
        frame = BodyBlock.axis_frame(front_normal)

        panel_thk = Units.mm_to_inch(Attrs.get(body, 'panel_thk', Constants::DEFAULT_PANEL_THK).to_f)
        back_thk = Units.mm_to_inch(Attrs.get(body, 'back_panel_thk', Constants::DEFAULT_BACK_PANEL_THK).to_f)

        depth_a, u_a, v_a = BodyBlock.axis_values(frame, min_pt)
        depth_b, u_b, v_b = BodyBlock.axis_values(frame, max_pt)
        u_min, u_max = [u_a, u_b].minmax
        v_min, v_max = [v_a, v_b].minmax
        depth_min, depth_max = [depth_a, depth_b].minmax
        front_val = frame[:depth_sign].positive? ? depth_max : depth_min
        back_val  = frame[:depth_sign].positive? ? depth_min : depth_max

        definition.entities.clear!

        if mode.to_i.zero?
          BodyBlock.build_shell_from_bounds(definition.entities, min_pt, max_pt, front_normal, panel_thk, back_thk)
          return
        end

        recess = Units.mm_to_inch(Constants::CHANNEL_RECESS_MM)
        shrunk_front_val = front_val - (frame[:depth_sign] * recess)

        shrunk_min = BodyBlock.point_on_frame(frame, shrunk_front_val, u_min, v_min)
        shrunk_max = BodyBlock.point_on_frame(frame, back_val, u_max, v_max)
        BodyBlock.build_shell_from_bounds(definition.entities, shrunk_min, shrunk_max, front_normal, panel_thk, back_thk)

        band_h = Units.mm_to_inch(Constants::CHANNEL_BAND_H_MM)

        # CH1: 상판 바로 아래
        top_hi = v_max - panel_thk
        top_lo = top_hi - band_h
        add_bracket(model, definition.entities, frame, shrunk_front_val, front_val, u_min, u_max, top_lo, top_hi)

        # CH2: CH1 + 본체 세로 중앙에 브라켓 하나 더
        return unless mode.to_i >= 2

        mid = (v_min + v_max) / 2.0
        add_bracket(model, definition.entities, frame, shrunk_front_val, front_val, u_min, u_max,
                    mid - (band_h / 2.0), mid + (band_h / 2.0))
      end

      # 파내기 전(=풀 뎁스)의 바디 바운드를 최초 1회 캡처해 저장해두고 계속 재사용한다.
      # 이미 저장되어 있으면 현재(파여 있을 수도 있는) body.bounds 대신 그 값을 쓴다.
      def origin_bounds(body)
        stored = Attrs.get(body, 'channel_orig_bounds', nil)
        if stored.nil?
          b = body.bounds
          stored = [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z]
          Attrs.set(body, 'channel_orig_bounds', stored)
        end
        [Geom::Point3d.new(stored[0], stored[1], stored[2]), Geom::Point3d.new(stored[3], stored[4], stored[5])]
      end

      # shrunk_front_val(파낸 새 전면)~front_val(원래 전면) 구간을 기본 두께로 채우고,
      # 그 중 아래쪽 CHANNEL_LIP_H_MM 구간만 원래 전면보다 CHANNEL_LIP_EXTRA_MM만큼 더
      # 튀어나오게(단턱) 한다.
      def add_bracket(model, entities, frame, shrunk_front_val, front_val, u_a, u_b, v_lo, v_hi)
        base = BodyBlock.create_box(entities,
                                     BodyBlock.point_on_frame(frame, shrunk_front_val, u_a, v_lo),
                                     BodyBlock.point_on_frame(frame, front_val, u_b, v_hi))
        tag_groove(model, base)

        lip_h = Units.mm_to_inch(Constants::CHANNEL_LIP_H_MM)
        lip_extra = Units.mm_to_inch(Constants::CHANNEL_LIP_EXTRA_MM)
        lip_v_hi = [v_lo + lip_h, v_hi].min
        lip_front_val = front_val + (frame[:depth_sign] * lip_extra)

        lip = BodyBlock.create_box(entities,
                                    BodyBlock.point_on_frame(frame, shrunk_front_val, u_a, v_lo),
                                    BodyBlock.point_on_frame(frame, lip_front_val, u_b, lip_v_hi))
        tag_groove(model, lip)
      end

      def tag_groove(model, group)
        Attrs.set(group, 'channel_groove', true)
        group.material = GROOVE_COLOR
        TagManager.assign(model, group, Constants::TAG_CHANNEL)
      end
    end
  end
end
