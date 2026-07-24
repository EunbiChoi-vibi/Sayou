require 'json'

module Sufx
  # Convert 버튼의 인터랙티브 격자 변환 툴 (§4.1).
  # 방향키로 행/열 조정, Tab으로 기준면 전환, Enter로 확정, Esc로 취소.
  #
  # §4.2 Base/Leg 통합: B/L 키로 토글(둘 중 하나만 켤 수 있음), +/-로 5mm씩 높이 조정
  # (최소 5mm, 기본값 Base 60mm/Leg 100mm). 켜져 있으면 3D 뷰에 파란 틴트로 바닥에서부터
  # 그 높이만큼의 영역을 미리 보여주고, Enter로 확정할 때 바디 그리드가 그 영역을 뺀
  # 나머지 높이로만 나뉘며 Base(전체 풋프린트 지지대) 또는 Leg(D40 원기둥 4개 + 10T
  # 전면 가림막)가 함께 생성된다.
  class SufxConvertTool
    class << self
      # 패널의 Base/Leg 버튼이 "지금 활성화된 Convert 툴 인스턴스"에 클릭을 전달할 수
      # 있도록, 현재 활성 인스턴스를 클래스 레벨에서 추적한다(activate/deactivate에서 설정).
      attr_accessor :active_instance
    end

    KEY_TAB = 9
    KEY_RETURN = 13
    KEY_B = 'B'.ord
    KEY_L = 'L'.ord
    KEY_PLUS = '+'.ord
    KEY_EQUALS = '='.ord
    KEY_MINUS = '-'.ord

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
      # Base(좌대)/Leg(다리) — 둘 중 하나만 켤 수 있고(:none/:base/:leg), 각자 마지막으로
      # 조정한 높이를 기억해둔다(B/L로 전환해도 그 타입의 값은 유지).
      @support_type = :none
      @support_height_mm = {
        base: Constants::DEFAULT_BASE_HEIGHT_MM,
        leg: Constants::DEFAULT_LEG_HEIGHT_MM
      }
    end

    def activate
      self.class.active_instance = self
      Sketchup.status_text = status_text
      Sketchup.active_model.active_view.invalidate
      push_dimensions_to_panel
      push_tool_state_to_panel
    end

    def deactivate(view)
      self.class.active_instance = nil if self.class.active_instance == self
      view.invalidate
      push_dimensions_to_panel(clear: true)
      push_tool_state_to_panel
    end

    def resume(_view)
      Sketchup.status_text = status_text
      push_dimensions_to_panel
      push_tool_state_to_panel
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
      when KEY_B
        toggle_support(:base)
      when KEY_L
        toggle_support(:leg)
      when KEY_PLUS, KEY_EQUALS
        adjust_support_height(Constants::SUPPORT_HEIGHT_STEP_MM)
      when KEY_MINUS
        adjust_support_height(-Constants::SUPPORT_HEIGHT_STEP_MM)
      when KEY_RETURN
        commit_grid!
        return false
      end
      Sketchup.status_text = status_text
      push_dimensions_to_panel
      push_tool_state_to_panel
      view.invalidate
      true
    end

    # 패널의 Base/Leg 버튼 클릭(마우스)에서 호출 — B/L 키와 동일하게 토글하고 화면을 갱신한다.
    def toggle_support_from_panel(type)
      toggle_support(type)
      Sketchup.status_text = status_text
      push_dimensions_to_panel
      push_tool_state_to_panel
      Sketchup.active_model.active_view.invalidate
    end

    # Base/Leg는 둘 중 하나만 켤 수 있다 — 같은 타입을 다시 누르면 끄고,
    # 다른 타입을 누르면 그쪽으로 바로 전환된다(암묵적으로 이전 타입은 꺼짐).
    def toggle_support(type)
      @support_type = @support_type == type ? :none : type
    end

    def adjust_support_height(delta_mm)
      return if @support_type == :none

      current = @support_height_mm[@support_type]
      @support_height_mm[@support_type] = [current + delta_mm, Constants::SUPPORT_MIN_HEIGHT_MM].max
    end

    def current_support_height_mm
      @support_height_mm[@support_type] || 0.0
    end

    TINT_COLOR = Sketchup::Color.new(70, 200, 120, 70).freeze
    SUPPORT_TINT_COLOR = Sketchup::Color.new(40, 110, 230, 130).freeze
    GRID_LINE_COLOR = Sketchup::Color.new(0, 190, 210).freeze
    LABEL_H_COLOR = Sketchup::Color.new(219, 39, 119).freeze # 열(가로 폭) 라벨 · 마젠타
    LABEL_V_COLOR = Sketchup::Color.new(22, 163, 74).freeze  # 행(세로 높이) 라벨 · 그린

    def draw(view)
      return if @group.deleted?

      draw_hud(view)
      return if @cols <= 0 || @rows <= 0

      # 초록 틴트/파란 Base·Leg 틴트는 원본 면 전체 기준, 격자선/치수는 실제로
      # 바디가 만들어질 축소된 면(grid_face) 기준 — 둘이 달라야 Base/Leg가 켜졌을 때
      # "바닥 쪽 파란 구간은 바디에서 제외되고 그 위만 격자로 나뉜다"가 눈으로 보인다.
      full_face = current_face
      body_face = grid_face
      cell_w = body_face.width / @cols
      cell_h = body_face.height / @rows

      draw_face_tint(view, full_face)
      draw_support_tint(view, full_face)
      draw_grid_lines(view, body_face, cell_w, cell_h)
      draw_dimension_labels(view, body_face, cell_w, cell_h)
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

    # Base/Leg가 켜져 있으면 면 바닥(v=0)부터 설정한 높이만큼 파란 틴트를 덧그린다 —
    # 실제 Convert 시 바디가 바닥 기준으로 그만큼 줄어들 영역을 미리 보여준다.
    def draw_support_tint(view, face)
      return if @support_type == :none

      h = [Units.mm_to_inch(current_support_height_mm), face.height].min
      p0 = face.origin.offset(lift_vector(face, TINT_OFFSET_MM))
      p1 = p0.offset(face.u_axis, face.width)
      p2 = p1.offset(face.v_axis, h)
      p3 = p0.offset(face.v_axis, h)

      view.drawing_color = SUPPORT_TINT_COLOR
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

    # 상단 바깥쪽에 열(칸) 폭 치수(마젠타 핏 라벨 + 경계점 마커),
    # 우측 바깥쪽에 행 높이 치수(그린 핏 라벨 + 경계점 마커)를 그린다.
    # 배경/텍스트 모두 screen-space 2D(draw2d/draw_text 고정좌표)로 그려서
    # 3D 깊이버퍼 영향을 받지 않게 한다 — 이전에 3D 월드좌표로 배경을 그렸을 때
    # 배경이 텍스트를 가리거나 흐리게 보이던 문제(z-fighting 계열)를 원천적으로 피한다.
    def draw_dimension_labels(view, face, cell_w, cell_h)
      origin = face.origin.offset(lift_vector(face, GRID_OFFSET_MM))

      (0..@cols).each do |c|
        point = origin.offset(face.u_axis, c * cell_w).offset(face.v_axis, face.height)
        draw_marker(view, point, LABEL_H_COLOR)
      end
      (0...@cols).each do |c|
        point = origin.offset(face.u_axis, (c + 0.5) * cell_w).offset(face.v_axis, face.height)
        draw_pill_label(view, point, format('%.0f', Units.inch_to_mm(cell_w)), LABEL_H_COLOR, dy: -20)
      end

      (0..@rows).each do |r|
        point = origin.offset(face.v_axis, r * cell_h).offset(face.u_axis, face.width)
        draw_marker(view, point, LABEL_V_COLOR)
      end
      (0...@rows).each do |r|
        point = origin.offset(face.v_axis, (r + 0.5) * cell_h).offset(face.u_axis, face.width)
        draw_pill_label(view, point, format('%.0f', Units.inch_to_mm(cell_h)), LABEL_V_COLOR, dx: 26)
      end
    end

    MARKER_HALF_PX = 5

    # 경계점(칸 나누는 선이 상/우 테두리와 만나는 점)에 작은 정사각 마커를 찍는다.
    def draw_marker(view, point3d, color)
      screen = view.screen_coords(point3d)
      return if screen.nil? || screen.z < 0 # 카메라 뒤쪽(투영 실패)이면 스킵

      x, y = screen.x, screen.y
      h = MARKER_HALF_PX
      quad = [[x - h, y - h, 0], [x + h, y - h, 0], [x + h, y + h, 0], [x - h, y + h, 0]]
      view.drawing_color = color
      view.draw2d(GL_QUADS, quad)
    rescue StandardError => e
      warn "[SUFX] draw_marker 실패: #{e.message}"
    end

    # point3d를 화면 좌표로 투영한 뒤, 그 위치에서 (dx,dy) 픽셀만큼 띄워서
    # 색상 배경 핏(pill) + 흰색 텍스트를 screen-space 2D로 그린다.
    def draw_pill_label(view, point3d, text, color, dx: 0, dy: 0)
      screen = view.screen_coords(point3d)
      return if screen.nil? || screen.z < 0

      x = screen.x + dx
      y = screen.y + dy
      pad_x, pad_y = 8, 5
      text_w = [text.length * 8, 16].max
      text_h = 14

      quad = [
        [x - (text_w / 2) - pad_x, y - (text_h / 2) - pad_y, 0],
        [x + (text_w / 2) + pad_x, y - (text_h / 2) - pad_y, 0],
        [x + (text_w / 2) + pad_x, y + (text_h / 2) + pad_y, 0],
        [x - (text_w / 2) - pad_x, y + (text_h / 2) + pad_y, 0]
      ]
      view.drawing_color = color
      view.draw2d(GL_QUADS, quad)
      view.draw_text([x - (text_w / 2), y - (text_h / 2)], text, color: 'white', bold: true)
    rescue StandardError => e
      warn "[SUFX] draw_pill_label 실패: #{e.message}"
    end

    # face.normal 방향으로 mm만큼 띄운 벡터를 만든다(z-fighting 방지용 공용 헬퍼).
    def lift_vector(face, mm)
      v = face.normal.clone
      v.length = Units.mm_to_inch(mm)
      v
    end

    def status_text
      base = '방향키: 행/열 조정 · Tab: 기준면 전환 · B/L: Base/Leg 토글 · +/-: 높이 5mm · Enter: 확정 · Esc: 취소'
      return base if @support_type == :none

      label = @support_type == :base ? 'Base' : 'Leg'
      "#{base} · #{label} #{current_support_height_mm.to_i}mm"
    end

    # 화면 고정 위치(스크린 좌표)에 항상 보이는 안내 문구를 그린다.
    def draw_hud(view)
      view.drawing_color = 'red'
      view.draw_text([12, 12], "SUFX Convert · #{@rows} x #{@cols}칸 · #{status_text}")
    rescue StandardError
      nil
    end

    # 현재 셀 치수를 SUFX Tools 패널의 HTML 텍스트로도 밀어넣는다(3D 뷰 라벨과 별개의 보조 표시).
    def push_dimensions_to_panel(clear: false)
      dialog = Sufx::UIPanel.dialog
      return unless dialog && dialog.visible?

      if clear
        dialog.execute_script('updateConvertDims(null)')
        return
      end

      return if @cols <= 0 || @rows <= 0

      face = grid_face
      cell_w_mm = Units.inch_to_mm(face.width / @cols)
      cell_h_mm = Units.inch_to_mm(face.height / @rows)
      text = format('%d행 x %d열 · 셀 %.0f x %.0fmm', @rows, @cols, cell_w_mm, cell_h_mm)
      unless @support_type == :none
        label = @support_type == :base ? 'Base' : 'Leg'
        text += format(' · %s %.0fmm', label, current_support_height_mm)
      end
      dialog.execute_script("updateConvertDims(#{text.to_json})")
    rescue StandardError => e
      warn "[SUFX] push_dimensions_to_panel 실패: #{e.message}"
    end

    # 패널의 Base/Leg 버튼 활성/비활성 및 강조 상태를 갱신한다 — Convert 툴이 active일
    # 때만 버튼을 누를 수 있게 하고, 켜진 타입(base/leg)을 버튼에 강조 표시한다.
    def push_tool_state_to_panel
      dialog = Sufx::UIPanel.dialog
      return unless dialog && dialog.visible?

      active = self.class.active_instance == self
      dialog.execute_script("updateConvertToolState(#{active}, #{@support_type.to_s.to_json})")
    rescue StandardError => e
      warn "[SUFX] push_tool_state_to_panel 실패: #{e.message}"
    end

    def current_face
      @candidate_faces[@base_face_index]
    end

    # Base/Leg가 켜져 있으면 면 바닥(v=0)에서 설정한 높이만큼 잘라낸(=그 구간은 바디가
    # 아니라 Base/Leg 몫으로 남겨둔) 축소된 면을 반환한다. 바디 그리드는 이 면을 기준으로
    # 나뉘어서, 결과적으로 바디 전체 높이가 바닥 기준으로 그만큼 줄어든다.
    def grid_face
      return current_face if @support_type == :none

      face = current_face
      h = Units.mm_to_inch(current_support_height_mm)
      return face if h >= face.height

      BodyBlock::CandidateFace.new(face.normal, face.origin.offset(face.v_axis, h),
                                    face.u_axis, face.v_axis, face.width, face.height - h)
    end

    def commit_grid!
      face = grid_face
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

        support_height_inch = Units.mm_to_inch(current_support_height_mm)
        case @support_type
        when :base
          build_base_support(model, current_face, support_height_inch)
        when :leg
          build_leg_support(model, current_face, support_height_inch)
          build_leg_valance(model, current_face, support_height_inch)
        end

        @group.erase! unless @group.deleted?
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("SUFX Convert 실패: #{e.message}")
      end

      model.select_tool(nil)
    end

    # Base: 원본 매스의 바닥 v구간(0~height) 전체 풋프린트(폭 전체 x 원본 깊이 전체)를
    # 그대로 지지대로 쓴다. 전면(face.origin 평면)이 도어의 최종 전면 끝선과 정확히
    # 일치한다 — Door는 Convert의 셋백(door_thk+body_gap)만큼 안쪽에서 시작해 그만큼
    # 다시 앞으로 나와 결국 이 원본 면 위치에서 끝나기 때문(door_create.rb 참고).
    def build_base_support(model, face, height_inch)
      depth_full = BodyBlock.depth_along_normal(@group.bounds, face.normal)
      p0 = face.origin
      p1 = p0.offset(face.u_axis, face.width)
                    .offset(face.v_axis, height_inch)
                    .offset(face.normal.reverse, depth_full)

      group = BodyBlock.create_box(model.active_entities, p0, p1)
      comp = group.to_component
      comp.definition.name = Naming.next_name(Constants::NAME_BASE)
      Attrs.set_all(comp,
                    'block_type' => 'base',
                    'group_id' => BodyBlock.new_guid,
                    'front_normal' => [face.normal.x, face.normal.y, face.normal.z])
      TagManager.assign(model, comp, Constants::TAG_BODY)
      comp
    end

    # Leg: 풋프린트(폭 x 깊이) 4개 모서리에서 각각 LEG_INSET_MM만큼 안쪽을 중심으로
    # D40 원기둥을 세운다.
    def build_leg_support(model, face, height_inch)
      inset = Units.mm_to_inch(Constants::LEG_INSET_MM)
      radius = Units.mm_to_inch(Constants::LEG_DIAMETER_MM) / 2.0
      depth_full = BodyBlock.depth_along_normal(@group.bounds, face.normal)

      u_positions = [inset, face.width - inset]
      d_positions = [inset, depth_full - inset]

      u_positions.product(d_positions).map do |u, d|
        center = face.origin.offset(face.u_axis, u).offset(face.normal.reverse, d)
        group = BodyBlock.create_cylinder(model.active_entities, center, radius, height_inch, face.v_axis)
        comp = group.to_component
        comp.definition.name = Naming.next_name(Constants::NAME_LEG)
        Attrs.set_all(comp,
                      'block_type' => 'leg',
                      'group_id' => BodyBlock.new_guid,
                      'front_normal' => [face.normal.x, face.normal.y, face.normal.z])
        TagManager.assign(model, comp, Constants::TAG_BODY)
        comp
      end
    end

    # Leg 전용 전면 가림막(10T) — Base와 동일하게 도어 전면 끝선(face.origin 평면)에
    # 맞춰 붙인다.
    def build_leg_valance(model, face, height_inch)
      thk = Units.mm_to_inch(Constants::LEG_VALANCE_THK_MM)
      p0 = face.origin
      p1 = p0.offset(face.u_axis, face.width)
                    .offset(face.v_axis, height_inch)
                    .offset(face.normal.reverse, thk)

      group = BodyBlock.create_box(model.active_entities, p0, p1)
      comp = group.to_component
      comp.definition.name = Naming.next_name(Constants::NAME_VALANCE)
      Attrs.set_all(comp,
                    'block_type' => 'valance',
                    'group_id' => BodyBlock.new_guid,
                    'front_normal' => [face.normal.x, face.normal.y, face.normal.z])
      TagManager.assign(model, comp, Constants::TAG_VALANCE)
      comp
    end
  end
end
