module Sufx
  # Convert 버튼의 인터랙티브 격자 변환 툴 (§4.1).
  # 방향키로 행/열 조정, Tab으로 기준면 전환, Enter로 확정, Esc로 취소.
  class SufxConvertTool
    KEY_TAB = 9
    KEY_RETURN = 13

    # 선택 유효성(그룹 1개)을 먼저 검사한 뒤 툴을 활성화한다.
    # 반환값은 다른 커맨드들과 동일하게 [성공여부, 실패사유] 형태.
    def self.start!
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

      model.select_tool(new(selection.first))
      [true, nil]
    end

    def initialize(group)
      @group = group
      @rows = 1
      @cols = 1
      @base_face_index = 0
      @candidate_faces = BodyBlock.collect_outer_faces(@group)
    end

    def activate
      Sketchup.status_text = '방향키: 행/열 조정 · Tab: 기준면 전환 · Enter: 확정 · Esc: 취소'
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(_view)
      Sketchup.status_text = '방향키: 행/열 조정 · Tab: 기준면 전환 · Enter: 확정 · Esc: 취소'
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
      view.invalidate
      true
    end

    TINT_COLOR = Sketchup::Color.new(70, 200, 120, 70).freeze
    GRID_LINE_COLOR = Sketchup::Color.new(0, 190, 210).freeze
    LABEL_H_COLOR = Sketchup::Color.new(225, 35, 130).freeze # 열(가로 폭) 라벨 — 분홍
    LABEL_V_COLOR = Sketchup::Color.new(35, 170, 90).freeze  # 행(세로 높이) 라벨 — 초록

    def draw(view)
      return if @group.deleted?

      draw_hud(view)

      face = current_face
      return if @cols <= 0 || @rows <= 0

      cell_w = face.width / @cols
      cell_h = face.height / @rows

      draw_face_tint(view, face)
      draw_grid_lines(view, face, cell_w, cell_h)
      draw_dimension_labels(view, face, cell_w, cell_h)
    end

    private

    # 선택된 면 전체에 반투명 초록 컬러 틴트를 깐다(원본 툴 참고 UX).
    def draw_face_tint(view, face)
      lift = face.normal.clone
      lift.length = 0.02 # 기존 지오메트리와 겹쳐 그릴 때의 z-fighting 방지용 미세 오프셋
      p0 = face.origin.offset(lift)
      p1 = p0.offset(face.u_axis, face.width)
      p2 = p1.offset(face.v_axis, face.height)
      p3 = p0.offset(face.v_axis, face.height)

      view.drawing_color = TINT_COLOR
      view.draw(GL_POLYGON, [p0, p1, p2, p3])
    end

    def draw_grid_lines(view, face, cell_w, cell_h)
      view.line_width = 2
      view.drawing_color = GRID_LINE_COLOR

      (0..@cols).each do |c|
        p0 = face.origin.offset(face.u_axis, c * cell_w)
        p1 = p0.offset(face.v_axis, face.height)
        view.draw(GL_LINES, [p0, p1])
      end
      (0..@rows).each do |r|
        p0 = face.origin.offset(face.v_axis, r * cell_h)
        p1 = p0.offset(face.u_axis, face.width)
        view.draw(GL_LINES, [p0, p1])
      end
    end

    # 상단 바깥쪽에 열(칸) 폭 라벨(분홍 pill), 우측 바깥쪽에 행 높이 라벨(초록 pill)을 그린다.
    def draw_dimension_labels(view, face, cell_w, cell_h)
      top_offset = face.v_axis.clone
      top_offset.length = [cell_h.to_f * 0.06, 0.3].max
      (0...@cols).each do |c|
        point = face.origin
                    .offset(face.u_axis, (c + 0.5) * cell_w)
                    .offset(face.v_axis, face.height)
                    .offset(top_offset)
        draw_pill_label(view, point, format('%.0f', Units.inch_to_mm(cell_w)), LABEL_H_COLOR)
      end

      right_offset = face.u_axis.clone
      right_offset.length = [cell_w.to_f * 0.06, 0.3].max
      (0...@rows).each do |r|
        point = face.origin
                    .offset(face.v_axis, (r + 0.5) * cell_h)
                    .offset(face.u_axis, face.width)
                    .offset(right_offset)
        draw_pill_label(view, point, format('%.0f', Units.inch_to_mm(cell_h)), LABEL_V_COLOR)
      end
    end

    # point(3D)를 화면에 투영해 그 자리에 배경색 pill + 흰 텍스트를 그린다.
    # 텍스트 폭 측정 API가 없어 글자수 기반으로 배경 크기를 근사한다.
    def draw_pill_label(view, point, text, bg_color)
      screen = view.screen_coords(point)
      return if screen.x.zero? && screen.y.zero?

      char_px = 7
      pad_x = 8
      w = (text.length * char_px) + (pad_x * 2)
      h = 18

      x0 = screen.x - (w / 2.0)
      y0 = screen.y - (h / 2.0)
      rect = [
        Geom::Point3d.new(x0, y0, 0),
        Geom::Point3d.new(x0 + w, y0, 0),
        Geom::Point3d.new(x0 + w, y0 + h, 0),
        Geom::Point3d.new(x0, y0 + h, 0)
      ]
      view.drawing_color = bg_color
      view.draw2d(GL_POLYGON, rect)

      view.draw_text(point, text, color: 'white', size: 11, align: TextAlignCenter)
    rescue StandardError
      nil # 화면 밖 투영 등으로 실패해도 나머지 라벨/그리드 렌더링은 계속되게 한다
    end

    # 화면 고정 위치(스크린 좌표)에 항상 보이는 안내 문구를 그린다.
    # 카메라 각도/거리와 무관하게 "Convert 모드가 켜졌다"는 것을 즉시 확인할 수 있게 하기 위함.
    def draw_hud(view)
      text = "SUFX Convert · #{@rows} x #{@cols}칸 · 방향키:행/열 · Tab:기준면 · Enter:확정 · Esc:취소"
      view.drawing_color = 'red'
      view.draw_text([12, 12], text)
    rescue StandardError
      nil # 일부 SketchUp 버전에서 화면좌표 draw_text 미지원 시 조용히 무시
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
        (0...@rows).each do |r|
          (0...@cols).each do |c|
            cell_group = BodyBlock.build_cell_solid(model, @group, face, r, c, cell_w, cell_h)
            BodyBlock.make_body_block(cell_group)
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
