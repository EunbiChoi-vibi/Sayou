require 'json'

module Sufx
  # Convert 버튼의 인터랙티브 격자 변환 툴 (§4.1).
  # 방향키로 행/열 조정, Tab으로 기준면 전환, Enter로 확정, Esc로 취소.
  class SufxConvertTool
    KEY_TAB = 9
    KEY_RETURN = 13

    # 선택 유효성(그룹 1개)을 먼저 검사한 뒤 툴을 활성화한다.
    # door_thk_mm/body_gap_mm: 패널에 현재 입력된 DOOR THK/BODY GAP 값.
    # Convert 시점에 이 합(기본 22mm)만큼 미리 셋백해서 쉘을 만들어 두면,
    # 나중에 Door를 붙일 때 바디를 더 깎지 않아도 최종 간격이 body_gap과 정확히 맞는다.
    # 반환값은 다른 커맨드들과 동일하게 [성공여부, 실패사유] 형태.
    def self.start!(door_thk_mm = nil, body_gap_mm = nil)
      model = Sketchup.active_model
      selection = model.selection
      if selection.size.zero?
        msg = '변환할 그룹(Group)을 먼저 선택하세요.'
        Sketchup.status_text = "SUFX Convert: #{msg}"
        return [false, msg]
      end
      unless selection.size == 1 && selection.first.is_a?(Sketchup::Group)
        msg = 'Convert는 그룹(Group) 1개만 선택했을 때 동작합니다. ' \
              '(컴포넌트이거나 여러 개를 선택한 상태입니다)'
        Sketchup.status_text = "SUFX Convert: #{msg}"
        return [false, msg]
      end

      model.select_tool(new(selection.first, door_thk_mm, body_gap_mm))
      [true, nil]
    end

    def initialize(group, door_thk_mm = nil, body_gap_mm = nil)
      @group = group
      @rows = 1
      @cols = 1
      @base_face_index = 0
      @candidate_faces = BodyBlock.collect_outer_faces(@group)
      @door_thk_mm = door_thk_mm || Constants::DEFAULT_DOOR_THK
      @body_gap_mm = body_gap_mm || Constants::DEFAULT_BODY_GAP
    end

    def activate
      Sketchup.status_text = '방향키: 행/열 조정 · Tab: 기준면 전환 · Enter: 확정 · Esc: 취소'
      Sketchup.active_model.active_view.invalidate
      push_dimensions_to_panel
    end

    def deactivate(view)
      view.invalidate
      push_dimensions_to_panel(clear: true)
    end

    def resume(_view)
      Sketchup.status_text = '방향키: 행/열 조정 · Tab: 기준면 전환 · Enter: 확정 · Esc: 취소'
      push_dimensions_to_panel
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onKeyDown(key, _repeat, _flags, view)
      case key
      when VK_LEFT
        @cols = [@cols - 1, 1].max
      when VK_RIGHT
        @cols += 1
      when VK_UP
        @rows += 1
      when VK_DOWN
        @rows = [@rows - 1, 1].max
      when KEY_TAB
        @base_face_index = (@base_face_index + 1) % @candidate_faces.size
      when KEY_RETURN
        commit_grid!
        return false
      end
      push_dimensions_to_panel
      view.invalidate
      true
    end

    TINT_COLOR = Sketchup::Color.new(70, 200, 120, 70).freeze
    GRID_LINE_COLOR = Sketchup::Color.new(0, 190, 210).freeze

    def draw(view)
      return if @group.deleted?

      draw_hud(view)

      face = current_face
      return if @cols <= 0 || @rows <= 0

      cell_w = face.width / @cols
      cell_h = face.height / @rows

      draw_face_tint(view, face)
      draw_grid_lines(view, face, cell_w, cell_h)
    end

    private

    TINT_OFFSET_MM = 2.0
    GRID_OFFSET_MM = 5.0 # 가이드선을 면에서 5mm 띄워서 z-fighting(흐리게/점선처럼 보이는 현상) 방지

    # 선택된 면 전체에 반투명 초록 컬러 틴트를 깐다(원본 툴 참고 UX).
    def draw_face_tint(view, face)
      p0 = face.origin.offset(lift_vector(face, TINT_OFFSET_MM))
      p1 = p0.offset(face.u_axis, face.width)
      p2 = p1.offset(face.v_axis, face.height)
      p3 = p0.offset(face.v_axis, face.height)

      view.drawing_color = TINT_COLOR
      view.draw(GL_POLYGON, [p0, p1, p2, p3])
    end

    def draw_grid_lines(view, face, cell_w, cell_h)
      view.line_width = 2
      view.drawing_color = GRID_LINE_COLOR
      origin = face.origin.offset(lift_vector(face, GRID_OFFSET_MM))

      (0..@cols).each do |c|
        p0 = origin.offset(face.u_axis, c * cell_w)
        p1 = p0.offset(face.v_axis, face.height)
        view.draw(GL_LINES, [p0, p1])
      end
      (0..@rows).each do |r|
        p0 = origin.offset(face.v_axis, r * cell_h)
        p1 = p0.offset(face.u_axis, face.width)
        view.draw(GL_LINES, [p0, p1])
      end
    end

    # face.normal 방향으로 mm만큼 띄운 벡터를 만든다(z-fighting 방지용 공용 헬퍼).
    def lift_vector(face, mm)
      v = face.normal.clone
      v.length = Units.mm_to_inch(mm)
      v
    end

    # 화면 고정 위치(스크린 좌표)에 항상 보이는 안내 문구를 그린다.
    # 카메라 각도/거리와 무관하게 "Convert 모드가 켜졌다"는 것을 즉시 확인할 수 있게 하기 위함.
    # NOTE: view.draw_text는 SketchUp 빌드에 따라 렌더링되지 않는 경우가 있어(치수 라벨이
    # 안 보이던 원인) 여기 문구는 "되면 좋고" 수준으로 남겨둔다. 실제 치수는 항상 동작하는
    # push_dimensions_to_panel(패널 쪽 HTML 텍스트)로 표시한다.
    def draw_hud(view)
      text = "SUFX Convert · #{@rows} x #{@cols}칸 · 방향키:행/열 · Tab:기준면 · Enter:확정 · Esc:취소"
      view.drawing_color = 'red'
      view.draw_text([12, 12], text)
    rescue StandardError
      nil
    end

    # 현재 셀 치수를 SUFX Tools 패널의 HTML 텍스트로 밀어넣는다 — 3D 뷰 안의 draw_text에
    # 의존하지 않는, 항상 동작하는 치수 표시 경로.
    def push_dimensions_to_panel(clear: false)
      dialog = Sufx::UIPanel.dialog
      return unless dialog && dialog.visible?

      if clear
        dialog.execute_script('updateConvertDims(null)')
        return
      end

      return if @cols <= 0 || @rows <= 0

      face = current_face
      cell_w_mm = Units.inch_to_mm(face.width / @cols)
      cell_h_mm = Units.inch_to_mm(face.height / @rows)
      text = format('%d행 x %d열 · 셀 %.0f x %.0fmm', @rows, @cols, cell_w_mm, cell_h_mm)
      dialog.execute_script("updateConvertDims(#{text.to_json})")
    rescue StandardError => e
      warn "[SUFX] push_dimensions_to_panel 실패: #{e.message}"
    end

    def current_face
      @candidate_faces[@base_face_index]
    end

    def commit_grid!
      face = current_face
      cell_w = face.width / @cols
      cell_h = face.height / @rows
      model = Sketchup.active_model

      model.start_operation('SUFX Convert', true)
      begin
        front_normal = [face.normal.x, face.normal.y, face.normal.z]
        setback_mm = @door_thk_mm + @body_gap_mm
        (0...@rows).each do |r|
          (0...@cols).each do |c|
            cell_group = BodyBlock.build_cell_body(model, @group, face, r, c, cell_w, cell_h,
                                                    setback_mm: setback_mm)
            BodyBlock.make_body_block(cell_group, front_normal: front_normal,
                                                   door_thk_mm: @door_thk_mm, body_gap_mm: @body_gap_mm)
          end
        end
        @group.erase! unless @group.deleted?
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("SUFX Convert 실패: #{e.message}")
      end

      model.select_tool(nil)
    end
  end
end
