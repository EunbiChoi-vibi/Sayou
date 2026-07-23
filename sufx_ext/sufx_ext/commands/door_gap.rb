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

        base_min = Geom::Point3d.new(origin[0], origin[1], origin[2])
        base_max = Geom::Point3d.new(origin[3], origin[4], origin[5])

        door_thk_inch = Units.mm_to_inch(Attrs.get(door, 'door_thk', Constants::DEFAULT_DOOR_THK).to_f)
        body_gap_inch = Units.mm_to_inch(Attrs.get(door, 'body_gap', Constants::DEFAULT_BODY_GAP).to_f)

        gap_left = Units.mm_to_inch(Attrs.get(door, 'gap_left', 0.0).to_f)
        gap_right = Units.mm_to_inch(Attrs.get(door, 'gap_right', 0.0).to_f)
        gap_top = Units.mm_to_inch(Attrs.get(door, 'gap_top', 0.0).to_f)
        gap_bottom = Units.mm_to_inch(Attrs.get(door, 'gap_bottom', 0.0).to_f)

        x0 = base_min.x + gap_left
        x1 = base_max.x - gap_right
        z0 = base_min.z + gap_bottom
        z1 = base_max.z - gap_top

        min_clamp = Units.mm_to_inch(Constants::MIN_CELL_SIZE)
        if (x1 - x0) < min_clamp
          mid = (x0 + x1) / 2.0
          x0 = mid - (min_clamp / 2.0)
          x1 = mid + (min_clamp / 2.0)
        end
        if (z1 - z0) < min_clamp
          mid = (z0 + z1) / 2.0
          z0 = mid - (min_clamp / 2.0)
          z1 = mid + (min_clamp / 2.0)
        end

        front_y = base_min.y # origin_door_bounds 저장 시 min.y == max.y (부착 시점의 바디 정면 기준)
        door_max_y = front_y - body_gap_inch
        door_min_y = door_max_y - door_thk_inch

        BodyBlock.redefine_box!(door,
                                 Geom::Point3d.new(x0, door_min_y, z0),
                                 Geom::Point3d.new(x1, door_max_y, z1))
      end
    end
  end
end
