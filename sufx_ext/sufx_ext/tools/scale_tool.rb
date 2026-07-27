module Sufx
  # §4.8 Scale 툴 커스터마이징 — 옵션 B(커스텀 Scale Tool)를 채택.
  #
  # SUFX 블럭(body/door/base/leg 등)의 바운딩박스 6개 면-중앙 지점에만 그립(핸들)을
  # 그리고, 드래그하면 반대쪽 면을 고정한 채 해당 축 방향으로만 크기를 바꾼다
  # (SketchUp 기본 Scale 툴의 코너/모서리 8+12 핸들을 3축 6핸들로 제한).
  #
  # LIMITATION(중요): 현재 body/door 지오메트리는 단일 솔리드 박스로 구현되어 있어
  # "측판(side panel) 18T 두께 자동 복원" 같은 다중 패널 구조가 아직 존재하지 않는다.
  # 따라서 rebuild_panel_thickness!는 지금은 no-op 스텁이다 — 바디가 실제 패널(18T
  # 측판) 조합으로 고도화되면 이 지점에서 각 패널 face를 재-push/pull해야 한다.
  # 이 부분은 명세서에서도 "가장 난이도 높음, 마지막 배치"로 지정한 항목이므로
  # SketchUp 실기 테스트를 거쳐 반드시 재검증이 필요하다.
  class SufxScaleTool
    HANDLE_PICK_RADIUS_PX = 10
    HANDLES = [
      { axis: :x, sign: 1 }, { axis: :x, sign: -1 },
      { axis: :y, sign: 1 }, { axis: :y, sign: -1 },
      { axis: :z, sign: 1 }, { axis: :z, sign: -1 }
    ].freeze

    def self.start!
      model = Sketchup.active_model
      selection = model.selection
      unless selection.size == 1 && Sufx::Attrs.block_type(selection.first)
        Sketchup.status_text = 'SUFX Scale: SUFX 블럭 1개를 선택하세요.'
        return false
      end

      model.select_tool(new(selection.first))
      true
    end

    def initialize(instance)
      @instance = instance
      @hover = nil
      @dragging = nil
      @drag_bounds = nil
      @preview_min = nil
      @preview_max = nil
      @handles = nil
    end

    def activate
      Sketchup.status_text = '면 중앙 그립을 드래그해 축별로 크기를 조정하세요 (Esc: 취소)'
      update_handles
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(_view)
      update_handles
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onMouseMove(_flags, x, y, view)
      if @dragging
        drag_to(x, y, view)
      else
        @hover = pick_handle(x, y, view)
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      handle = pick_handle(x, y, view)
      return unless handle

      @dragging = handle
      @drag_bounds = @instance.bounds
    end

    def onLButtonUp(_flags, _x, _y, _view)
      return unless @dragging

      commit_scale!
      @dragging = nil
      @drag_bounds = nil
      update_handles
    end

    def draw(view)
      return if @instance.deleted?

      update_handles if @handles.nil?
      @handles.each do |h|
        active = @dragging == h || @hover == h
        view.drawing_color = active ? 'orange' : 'blue'
        pt2d = view.screen_coords(h[:point])
        size = active ? 6 : 4
        square = [
          Geom::Point3d.new(pt2d.x - size, pt2d.y - size, 0),
          Geom::Point3d.new(pt2d.x + size, pt2d.y - size, 0),
          Geom::Point3d.new(pt2d.x + size, pt2d.y + size, 0),
          Geom::Point3d.new(pt2d.x - size, pt2d.y + size, 0)
        ]
        view.draw2d(GL_POLYGON, square)
      end
    end

    private

    def update_handles
      bounds = @instance.bounds
      @handles = HANDLES.map { |h| h.merge(point: face_center(bounds, h[:axis], h[:sign])) }
    end

    def face_center(bounds, axis, sign)
      c = bounds.center
      case axis
      when :x then Geom::Point3d.new(sign.positive? ? bounds.max.x : bounds.min.x, c.y, c.z)
      when :y then Geom::Point3d.new(c.x, sign.positive? ? bounds.max.y : bounds.min.y, c.z)
      else Geom::Point3d.new(c.x, c.y, sign.positive? ? bounds.max.z : bounds.min.z)
      end
    end

    def pick_handle(x, y, view)
      update_handles
      mouse = Geom::Point3d.new(x, y, 0)
      closest = @handles.min_by { |h| view.screen_coords(h[:point]).distance(mouse) }
      return nil unless closest

      view.screen_coords(closest[:point]).distance(mouse) <= HANDLE_PICK_RADIUS_PX ? closest : nil
    end

    def axis_vector(axis)
      case axis
      when :x then Geom::Vector3d.new(1, 0, 0)
      when :y then Geom::Vector3d.new(0, 1, 0)
      else Geom::Vector3d.new(0, 0, 1)
      end
    end

    def drag_to(x, y, view)
      axis = @dragging[:axis]
      sign = @dragging[:sign]
      vec = axis_vector(axis)
      anchor = @dragging[:point]

      ray = view.pickray(x, y)
      _point_on_ray, point_on_axis = Geom.closest_points(ray, [anchor, vec])

      min_pt = @drag_bounds.min.clone
      max_pt = @drag_bounds.max.clone
      min_clamp = Units.mm_to_inch(Constants::MIN_CELL_SIZE)

      case axis
      when :x
        if sign.positive?
          max_pt.x = [point_on_axis.x, min_pt.x + min_clamp].max
        else
          min_pt.x = [point_on_axis.x, max_pt.x - min_clamp].min
        end
      when :y
        if sign.positive?
          max_pt.y = [point_on_axis.y, min_pt.y + min_clamp].max
        else
          min_pt.y = [point_on_axis.y, max_pt.y - min_clamp].min
        end
      else
        if sign.positive?
          max_pt.z = [point_on_axis.z, min_pt.z + min_clamp].max
        else
          min_pt.z = [point_on_axis.z, max_pt.z - min_clamp].min
        end
      end

      @preview_min = min_pt
      @preview_max = max_pt
    end

    def commit_scale!
      return unless @preview_min && @preview_max

      model = Sketchup.active_model
      model.start_operation('SUFX Scale', true)
      begin
        BodyBlock.redefine_box!(@instance, @preview_min, @preview_max)
        rebuild_panel_thickness!(@instance)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("SUFX Scale 실패: #{e.message}")
      end
      @preview_min = nil
      @preview_max = nil
    end

    # NOTE: 현재 바디/도어는 단일 솔리드 박스라 "측판"이 별도로 존재하지 않는다.
    # 다중 패널 구조로 고도화되면 여기서 각 패널 face를 target_thk로 재-push/pull한다.
    def rebuild_panel_thickness!(_component)
      # 의도적 no-op — 클래스 상단 LIMITATION 노트 참고.
    end
  end
end
