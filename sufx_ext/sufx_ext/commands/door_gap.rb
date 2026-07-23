module Sufx
  module Commands
    # §4.6 Door Gap — 선택된 도어에 4방향(top/bottom/left/right/all) 갭 누적 조정, 또는 Reset.
    # 매번 §4.5에서 기록해둔 origin_door_bounds를 기준으로 지오메트리를 재생성하므로
    # 반복 클릭에 따른 부동소수점 오차가 누적되지 않는다.
    module DoorGap
      module_function

      DIRECTIONS = %i[top bottom left right].freeze

      def run!(selection, direction, mm)
        doors = selection.select { |e| Attrs.block_type(e) == 'door' } # 자동 필터링(필수) — 도어 아닌 항목은 무시
        return false if doors.empty? # §4.6: 선택에 도어 없으면 조용히 무시

        model = Sketchup.active_model
        model.start_operation('SUFX Door Gap', true)
        begin
          doors.each do |door|
            if direction == :reset
              %w[gap_top gap_bottom gap_left gap_right].each { |k| Attrs.set(door, k, 0.0) }
            elsif direction == :all
              DIRECTIONS.each { |d| bump_gap(door, d, mm) }
            else
              bump_gap(door, direction, mm)
            end
            rebuild_door_geometry(door)
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("SUFX Door Gap 실패: #{e.message}")
          return false
        end
        true
      end

      def bump_gap(door, side, mm)
        key = "gap_#{side}"
        current = Attrs.get(door, key, 0.0).to_f
        Attrs.set(door, key, current + mm)
      end

      def rebuild_door_geometry(door)
        origin = Attrs.get(door, 'origin_door_bounds')
        return unless origin.is_a?(Array) && origin.size == 6

        front_normal_arr = Attrs.get(door, 'front_normal', [0.0, -1.0, 0.0])
        frame = BodyBlock.axis_frame(Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2]))

        p_a = Geom::Point3d.new(origin[0], origin[1], origin[2])
        p_b = Geom::Point3d.new(origin[3], origin[4], origin[5])
        body_front_val, u_a, v_a = BodyBlock.axis_values(frame, p_a)
        _depth_b, u_b, v_b = BodyBlock.axis_values(frame, p_b)
        u0_base, u1_base = [u_a, u_b].minmax
        v0_base, v1_base = [v_a, v_b].minmax

        door_thk_inch = Units.mm_to_inch(Attrs.get(door, 'door_thk', Constants::DEFAULT_DOOR_THK).to_f)
        body_gap_inch = Units.mm_to_inch(Attrs.get(door, 'body_gap', Constants::DEFAULT_BODY_GAP).to_f)

        gap_left = Units.mm_to_inch(Attrs.get(door, 'gap_left', 0.0).to_f)
        gap_right = Units.mm_to_inch(Attrs.get(door, 'gap_right', 0.0).to_f)
        gap_top = Units.mm_to_inch(Attrs.get(door, 'gap_top', 0.0).to_f)
        gap_bottom = Units.mm_to_inch(Attrs.get(door, 'gap_bottom', 0.0).to_f)

        u0 = u0_base + gap_left
        u1 = u1_base - gap_right
        v0 = v0_base + gap_bottom
        v1 = v1_base - gap_top

        min_clamp = Units.mm_to_inch(Constants::MIN_CELL_SIZE)
        if (u1 - u0) < min_clamp
          mid = (u0 + u1) / 2.0
          u0 = mid - (min_clamp / 2.0)
          u1 = mid + (min_clamp / 2.0)
        end
        if (v1 - v0) < min_clamp
          mid = (v0 + v1) / 2.0
          v0 = mid - (min_clamp / 2.0)
          v1 = mid + (min_clamp / 2.0)
        end

        door_attached_val = body_front_val + (frame[:depth_sign] * body_gap_inch)
        door_outer_val = door_attached_val + (frame[:depth_sign] * door_thk_inch)

        BodyBlock.redefine_box!(door,
                                 BodyBlock.point_on_frame(frame, door_attached_val, u0, v0),
                                 BodyBlock.point_on_frame(frame, door_outer_val, u1, v1))
      end
    end
  end
end
