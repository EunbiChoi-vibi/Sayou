module Sufx
  module Commands
    # §4.3 Merge — 동일 타입 + 완전 인접 블럭들을 하나의 새 블럭으로 합친다.
    module Merge
      module_function

      def validate(selection)
        return [false, '2개 이상 선택해야 합니다.'] if selection.size < 2

        types = selection.map { |e| Attrs.block_type(e) }
        return [false, '동일한 종류끼리만 병합할 수 있습니다.'] if types.uniq.size != 1
        return [false, '선택한 항목이 서로 인접(맞닿음)하지 않습니다.'] unless all_adjacent?(selection)

        [true, nil]
      end

      def all_adjacent?(entities)
        tol = Units.mm_to_inch(Constants::ADJACENCY_TOLERANCE_MM)
        entities.combination(2).all? { |a, b| BodyBlock.bbox_touches?(a.bounds, b.bounds, tol) }
      end

      def run!
        model = Sketchup.active_model
        selection = model.selection.to_a
        ok, message = validate(selection)
        unless ok
          Sketchup.status_text = "SUFX Merge: #{message}"
          return [false, message]
        end

        block_type = Attrs.block_type(selection.first)
        model.start_operation('SUFX Merge', true)
        begin
          combined = BodyBlock.union_bounds(selection)
          group = build_merged_group(model, selection.first, block_type, combined)
          comp = group.to_component
          comp.definition.name = Naming.next_name(prefix_for(block_type))
          Attrs.copy(selection.first, comp)
          Attrs.set(comp, 'block_type', block_type)
          Attrs.set(comp, 'group_id', BodyBlock.new_guid)
          TagManager.assign(model, comp, tag_for(block_type))
          # 도어를 병합한 경우, 복사돼 온 origin_door_bounds/gap_*는 병합 전 낱장 기준이라
          # 병합된 새 지오메트리와 어긋난다. Door Gap이 계속 정확히 동작하도록 재계산한다.
          resync_door_reference!(comp) if block_type == 'door'

          selection.each { |e| e.erase! unless e.deleted? }
          model.commit_operation
          model.selection.clear
          model.selection.add(comp)
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("SUFX Merge 실패: #{e.message}")
          return [false, e.message]
        end
        [true, nil]
      end

      # 바디(body)를 병합할 때는 통짜 솔리드가 아니라 쉘 구조(측/상/하/뒷판)를 유지한 채
      # 합쳐진 바운딩박스로 다시 만든다. 도어/베이스/다리 등은 기존처럼 통짜 박스로 합친다.
      def build_merged_group(model, reference, block_type, combined)
        return BodyBlock.create_box(model.active_entities, combined.min, combined.max) unless block_type == 'body'

        front_normal_arr = Attrs.get(reference, 'front_normal', [0.0, -1.0, 0.0])
        front_normal = Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2])
        panel_thk = Units.mm_to_inch(Attrs.get(reference, 'panel_thk', Constants::DEFAULT_PANEL_THK).to_f)
        back_thk = Units.mm_to_inch(Attrs.get(reference, 'back_panel_thk', Constants::DEFAULT_BACK_PANEL_THK).to_f)

        BodyBlock.build_shell_from_bounds(model.active_entities, combined.min, combined.max,
                                           front_normal, panel_thk, back_thk)
      end

      def prefix_for(block_type)
        case block_type
        when 'door' then Constants::NAME_DOOR
        when 'base' then Constants::NAME_BASE
        when 'leg' then Constants::NAME_LEG
        else Constants::NAME_BODY
        end
      end

      def tag_for(block_type)
        block_type == 'door' ? "#{Constants::TAG_DOOR_FOLDER}/#{Constants::TAG_DOOR}" : Constants::TAG_BODY
      end

      def resync_door_reference!(door)
        front_normal_arr = Attrs.get(door, 'front_normal', [0.0, -1.0, 0.0])
        frame = BodyBlock.axis_frame(Geom::Vector3d.new(front_normal_arr[0], front_normal_arr[1], front_normal_arr[2]))
        body_gap_inch = Units.mm_to_inch(Attrs.get(door, 'body_gap', Constants::DEFAULT_BODY_GAP).to_f)

        bounds = door.bounds
        depth_min, depth_max = BodyBlock.axis_range(bounds, frame[:depth_axis])
        # 부착측(door_attached_val) 기준으로 바디 정면 값을 역산한다.
        door_attached_val = frame[:depth_sign].positive? ? depth_min : depth_max
        body_front_val = door_attached_val - (frame[:depth_sign] * body_gap_inch)

        u_min, u_max = BodyBlock.axis_range(bounds, frame[:u_sym])
        v_min, v_max = BodyBlock.axis_range(bounds, frame[:v_sym])
        p0 = BodyBlock.point_on_frame(frame, body_front_val, u_min, v_min)
        p1 = BodyBlock.point_on_frame(frame, body_front_val, u_max, v_max)

        Attrs.set(door, 'origin_door_bounds', [p0.x, p0.y, p0.z, p1.x, p1.y, p1.z])
        %w[gap_top gap_bottom gap_left gap_right].each { |k| Attrs.set(door, k, 0.0) }
      end
    end
  end
end
