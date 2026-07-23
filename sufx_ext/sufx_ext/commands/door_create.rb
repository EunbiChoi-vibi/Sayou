module Sufx
  module Commands
    # §4.5 DOOR 생성 (좌경/우경/반반/서랍).
    #
    # 정합 규칙: 바디는 Convert 시점에 이미 door_thk+body_gap만큼 셋백되어 만들어진다
    # (core/body_block.rb#build_cell_body 참고). 그래서 여기서는 바디를 추가로 깎지
    # 않고, 이미 셋백된 바디 앞면(front_y = combined.min.y)을 기준으로 body_gap만큼
    # 띄워서 도어를 놓기만 하면 도어-바디 최종 간격이 정확히 body_gap이 된다.
    # (Convert 이전 구버전 바디처럼 셋백 없이 만들어진 바디가 선택된 경우에도, 그
    # 상태 그대로 도어가 body_gap만큼 띄워져 붙는다 — 추가 축소를 하지 않을 뿐이다.)
    #
    # 방향 가정: 바디블럭의 정면은 -Y 방향(Convert 기본면 index 0과 동일)이라고 가정한다.
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
          build_doorline(model, door_comps)

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
        x0 = combined.min.x + Units.mm_to_inch(gaps[:left])
        x1 = combined.max.x - Units.mm_to_inch(gaps[:right])
        z0 = combined.min.z + Units.mm_to_inch(gaps[:bottom])
        z1 = combined.max.z - Units.mm_to_inch(gaps[:top])
        front_y = combined.min.y

        if door_type == :drawer
          clearance = Units.mm_to_inch(Constants::CHANNEL_CLEARANCE[channel_mode] || 0)
          z1 = combined.max.z - clearance # §4.7: 챗넬 홈 높이만큼 서랍 상단 축소
        end

        door_max_y = front_y - body_gap_inch
        door_min_y = door_max_y - door_thk_inch

        leaf_specs(door_type, x0, x1, z0, z1).map do |lx0, lz0, lx1, lz1|
          group = BodyBlock.create_box(model.active_entities,
                                        Geom::Point3d.new(lx0, door_min_y, lz0),
                                        Geom::Point3d.new(lx1, door_max_y, lz1))
          comp = group.to_component
          comp.definition.name = Naming.next_name(Constants::NAME_DOOR)
          Attrs.set_all(comp,
                         'block_type' => 'door',
                         'door_type' => door_type.to_s,
                         'door_thk' => door_thk_mm,
                         'body_gap' => body_gap_mm,
                         'gap_top' => 0.0,
                         'gap_bottom' => 0.0,
                         'gap_left' => 0.0,
                         'gap_right' => 0.0,
                         'parent_body_id' => (Attrs.get(first_body, 'group_id') || first_body.guid).to_s,
                         'origin_door_bounds' => [lx0, front_y, lz0, lx1, front_y, lz1])
          TagManager.assign(model, comp, "#{Constants::TAG_DOOR_FOLDER}/#{Constants::TAG_DOOR}")
          comp
        end
      end

      # door_type: :left/:right(단문), :double(반반, 2짝), :drawer(서랍) — 모두 박스 1~2개로 근사.
      # left/right는 지오메트리는 동일하고 힌지 방향만 속성(door_type)에 기록해 구분한다.
      def leaf_specs(door_type, x0, x1, z0, z1)
        if door_type == :double
          mid_x = (x0 + x1) / 2.0
          [[x0, z0, mid_x, z1], [mid_x, z0, x1, z1]]
        else
          [[x0, z0, x1, z1]]
        end
      end

      # 도어 윤곽/줄눈선(§3.3 SUFX_DOORLINE) — 도어 바깥쪽(시야 방향) 면에 inset된 사각 엣지 루프.
      def build_doorline(model, door_comps, inset_mm: 2.0)
        inset = Units.mm_to_inch(inset_mm)
        door_comps.each do |door|
          bounds = door.bounds
          y = bounds.min.y # 도어 바깥쪽(밖에서 보이는) 면
          x0 = bounds.min.x + inset
          x1 = bounds.max.x - inset
          z0 = bounds.min.z + inset
          z1 = bounds.max.z - inset
          next if x1 <= x0 || z1 <= z0

          group = model.active_entities.add_group
          pts = [
            Geom::Point3d.new(x0, y, z0),
            Geom::Point3d.new(x1, y, z0),
            Geom::Point3d.new(x1, y, z1),
            Geom::Point3d.new(x0, y, z1)
          ]
          group.entities.add_edges(pts + [pts.first])
          TagManager.assign(model, group, "#{Constants::TAG_DOOR_FOLDER}/#{Constants::TAG_DOORLINE}")
        end
      end
    end
  end
end
