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
        v0 = v_min + Units.mm_to_inch(gaps[:bottom])
        v1 = v_max - Units.mm_to_inch(gaps[:top])

        if door_type == :drawer
          clearance = Units.mm_to_inch(Constants::CHANNEL_CLEARANCE[channel_mode] || 0)
          v1 = v_max - clearance # §4.7: 챗넬 홈 높이만큼 서랍 상단 축소
        end

        depth_min, depth_max = BodyBlock.axis_range(combined, frame[:depth_axis])
        body_front_val = frame[:depth_sign].positive? ? depth_max : depth_min
        # §4.7: 챗넬이 있으면 combined(=바디 실측 바운드)의 전면이 이미 챗넬 브라켓
        # 돌출분(단턱 포함)만큼 앞으로 나와 있으므로, body_gap을 더 얹으면 그만큼 간격이
        # 더 벌어진다. 챗넬이 있을 때는 그 돌출면에 바로(0mm) 붙인다.
        effective_gap_inch = channel_mode.to_i.zero? ? body_gap_inch : 0.0
        door_attached_val = body_front_val + (frame[:depth_sign] * effective_gap_inch)
        door_outer_val = door_attached_val + (frame[:depth_sign] * door_thk_inch)

        leaf_specs(door_type, u0, u1, v0, v1).map do |lu0, lv0, lu1, lv1|
          p0 = BodyBlock.point_on_frame(frame, door_attached_val, lu0, lv0)
          p1 = BodyBlock.point_on_frame(frame, door_outer_val, lu1, lv1)
          group = BodyBlock.create_box(model.active_entities, p0, p1)
          comp = group.to_component
          comp.definition.name = Naming.next_name(Constants::NAME_DOOR)

          origin_p0 = BodyBlock.point_on_frame(frame, body_front_val, lu0, lv0)
          origin_p1 = BodyBlock.point_on_frame(frame, body_front_val, lu1, lv1)

          Attrs.set_all(comp,
                         'block_type' => 'door',
                         'door_type' => door_type.to_s,
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
