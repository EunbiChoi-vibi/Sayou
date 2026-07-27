module Sufx
  module Commands
    # §4.5 DOOR 생성 (좌경/우경/반반/서랍).
    #
    # 정합 규칙: 바디는 Convert 시점에 이미 door_thk+body_gap만큼 셋백되어 만들어진다
    # (core/body_block.rb#build_cell_body 참고). 그래서 여기서는 바디를 추가로 깎지
    # 않고, 이미 셋백된 바디 앞면을 기준으로 body_gap만큼 띄워서 도어를 놓기만 하면
    # 도어-바디 최종 간격이 정확히 body_gap이 된다.
    #
    # 방향: Convert에서 Tab으로 어떤 면을 선택했든, 그 바디에 저장된 front_normal
    # 속성(§core/body_block.rb#axis_frame)을 그대로 따라가 그 면을 바라보고 도어가
    # 붙는다 — 더 이상 -Y 고정 가정을 쓰지 않는다.
    module DoorCreate
      module_function

      def run!(door_type, door_thk_mm, body_gap_mm)
        model = Sketchup.active_model
        bodies = model.selection.to_a.select { |e| Attrs.block_type(e) == 'body' }
        if bodies.empty?
          msg = '바디블럭을 1개 이상 선택하세요.'
          Sketchup.status_text = "SUFX Door: #{msg}"
          return [false, msg]
        end

        door_thk_inch = Units.mm_to_inch(door_thk_mm)
        body_gap_inch = Units.mm_to_inch(body_gap_mm)
        combined = BodyBlock.union_bounds(bodies)

        min_span = [combined.width, combined.height, combined.depth].min
        if min_span <= door_thk_inch
          msg = '셀 크기가 도어 두께보다 작아 도어를 생성할 수 없습니다.'
          Sketchup.status_text = "SUFX Door: #{msg}"
          return [false, msg]
        end

        first_body = bodies.first
        channel_mode = Attrs.get(first_body, 'channel_mode', 0).to_i
        gaps = {
          left: Attrs.get(first_body, 'gap_left', 0.0).to_f,
          right: Attrs.get(first_body, 'gap_right', 0.0).to_f,
          top: Attrs.get(first_body, 'gap_top', 0.0).to_f,
          bottom: Attrs.get(first_body, 'gap_bottom', 0.0).to_f
        }

        model.start_operation('SUFX Door', true)
        begin
          door_comps = build_doors(model, combined, door_type, door_thk_mm, door_thk_inch,
                                    body_gap_mm, body_gap_inch, gaps, channel_mode, first_body)

          model.commit_operation
          model.selection.clear
          door_comps.each { |c| model.selection.add(c) }
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("SUFX Door 생성 실패: #{e.message}")
          return [false, e.message]
        end
        [true, nil]
      end

      def build_doors(model, combined, door_type, door_thk_mm, door_thk_inch,
                       body_gap_mm, body_gap_inch, gaps, channel_mode, first_body)
        front_normal_arr = Attrs.get(first_body, 'front_normal', [0.0, -1.0, 0.0])
        frame = BodyBlock.axis_frame(Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2]))

        u_min, u_max = BodyBlock.axis_range(combined, frame[:u_sym])
        v_min, v_max = BodyBlock.axis_range(combined, frame[:v_sym])
        u0 = u_min + Units.mm_to_inch(gaps[:left])
        u1 = u_max - Units.mm_to_inch(gaps[:right])

        v_segments = door_v_segments(door_type, channel_mode, v_min, v_max, gaps)

        body_front_val = door_body_front_val(first_body, combined, frame, channel_mode)
        # §4.7: 챗넬이 있으면 combined(=바디 실측 바운드)에는 챗넬 브라켓 돌출분(단턱 포함)이
        # 섞여 있어 그대로 쓰면 도어가 그만큼 더 앞으로 튀어나온다. 챗넬이 있을 때는 파내기
        # 전 원래 전면(channel_orig_bounds)을 기준으로 삼고, body_gap 없이 바로(0mm) 붙인다.
        effective_gap_inch = channel_mode.to_i.zero? ? body_gap_inch : 0.0
        door_attached_val = body_front_val + (frame[:depth_sign] * effective_gap_inch)
        door_outer_val = door_attached_val + (frame[:depth_sign] * door_thk_inch)

        specs = v_segments.flat_map { |sv0, sv1| leaf_specs(door_type, u0, u1, sv0, sv1) }

        specs.each_with_index.map do |(lu0, lv0, lu1, lv1), leaf_idx|
          p0 = BodyBlock.point_on_frame(frame, door_attached_val, lu0, lv0)
          p1 = BodyBlock.point_on_frame(frame, door_outer_val, lu1, lv1)
          group = BodyBlock.create_box(model.active_entities, p0, p1)
          comp = group.to_component
          comp.definition.name = Naming.next_name(Constants::NAME_DOOR)

          origin_p0 = BodyBlock.point_on_frame(frame, body_front_val, lu0, lv0)
          origin_p1 = BodyBlock.point_on_frame(frame, body_front_val, lu1, lv1)
          leaf_side = door_type == :double ? (leaf_idx.zero? ? 'left' : 'right') : ''

          Attrs.set_all(comp,
                         'block_type' => 'door',
                         'door_type' => door_type.to_s,
                         'door_leaf_side' => leaf_side,
                         'door_thk' => door_thk_mm,
                         'body_gap' => body_gap_mm,
                         'gap_top' => Constants::DEFAULT_DOOR_GAP,
                         'gap_bottom' => Constants::DEFAULT_DOOR_GAP,
                         'gap_left' => Constants::DEFAULT_DOOR_GAP,
                         'gap_right' => Constants::DEFAULT_DOOR_GAP,
                         'front_normal' => front_normal_arr,
                         'parent_body_id' => (Attrs.get(first_body, 'group_id') || first_body.guid).to_s,
                         'origin_door_bounds' => [origin_p0.x, origin_p0.y, origin_p0.z,
                                                   origin_p1.x, origin_p1.y, origin_p1.z])
          TagManager.assign(model, comp, "#{Constants::TAG_DOOR_FOLDER}/#{Constants::TAG_DOOR}")
          # origin_door_bounds는 "갭 0" 기준 전체 개구부다. gap_*를 기본값(2mm)으로 채웠으니
          # 그 갭이 실제 지오메트리에도 바로 반영되도록 DoorGap의 재생성 로직을 그대로 재사용한다.
          DoorGap.rebuild_door_geometry(comp)
          comp
        end
      end

      # 챗넬이 없으면 [v0,v1] 구간 하나. 챗넬이 있으면 밴드(Channel.band_ranges)의
      # 윗쪽 끝선에서 CHANNEL_DOOR_CLEARANCE_MM만큼 띄운다(모든 도어 타입 공통).
      # 서랍이고 밴드가 2개(상+중챗넬)면, 밴드로 나뉜 구간마다 서랍을 하나씩 만들도록
      # [v0,v1] 구간을 2개로 쪼갠다(각 구간도 자기 위 밴드의 윗쪽 끝선 기준).
      def door_v_segments(door_type, channel_mode, v_min, v_max, gaps)
        v0 = v_min + Units.mm_to_inch(gaps[:bottom])
        v1 = v_max - Units.mm_to_inch(gaps[:top])

        bands = channel_mode.to_i.positive? ? Channel.band_ranges(v_min, v_max, channel_mode).sort_by(&:first) : []
        return [[v0, v1]] if bands.empty?

        clearance = Units.mm_to_inch(Constants::CHANNEL_DOOR_CLEARANCE_MM)

        unless door_type == :drawer && bands.size >= 2
          topmost_hi = bands.max_by { |lo, _hi| lo }.last
          return [[v0, topmost_hi - clearance]]
        end

        segments = []
        cursor = v0
        bands.each do |_lo, hi|
          segments << [cursor, hi - clearance]
          cursor = hi
        end
        segments
      end

      # 챗넬이 없으면 combined(바디 실측 바운드)의 전면을 그대로 쓴다. 챗넬이 있으면
      # combined에는 챗넬 브라켓의 돌출분이 섞여 있어 쓸 수 없으므로, 파내기 전 원래
      # 전면(channel_orig_bounds, §commands/channel.rb#origin_bounds)을 기준으로 삼는다.
      def door_body_front_val(first_body, combined, frame, channel_mode)
        if channel_mode.to_i.positive?
          orig = Attrs.get(first_body, 'channel_orig_bounds', nil)
          if orig.is_a?(Array) && orig.size == 6
            d_a, = BodyBlock.axis_values(frame, Geom::Point3d.new(orig[0], orig[1], orig[2]))
            d_b, = BodyBlock.axis_values(frame, Geom::Point3d.new(orig[3], orig[4], orig[5]))
            return frame[:depth_sign].positive? ? [d_a, d_b].max : [d_a, d_b].min
          end
        end

        depth_min, depth_max = BodyBlock.axis_range(combined, frame[:depth_axis])
        frame[:depth_sign].positive? ? depth_max : depth_min
      end

      # door_type: :left/:right(단문), :double(반반, 2짝), :drawer(서랍) — 모두 박스 1~2개로 근사.
      # left/right는 지오메트리는 동일하고 힌지 방향만 속성(door_type)에 기록해 구분한다.
      def leaf_specs(door_type, u0, u1, v0, v1)
        if door_type == :double
          mid_u = (u0 + u1) / 2.0
          [[u0, v0, mid_u, v1], [mid_u, v0, u1, v1]]
        else
          [[u0, v0, u1, v1]]
        end
      end
    end
  end
end
