module Sufx
  # inch(SketchUp 내부 단위) <-> mm 변환.
  module Units
    module_function

    def inch_to_mm(value)
      value.to_f * 25.4
    end

    def mm_to_inch(value)
      value.to_f / 25.4
    end
  end

  # 바디블럭(및 파생 솔리드) 생성/조회에 필요한 지오메트리 유틸리티.
  # 정밀한 boolean 연산 대신, 사각 솔리드(box) push/pull 조합으로 지오메트리를
  # 구성한다 (가구 바디블럭은 대부분 직육면체이므로 이 근사로 충분하다).
  module BodyBlock
    CandidateFace = Struct.new(:normal, :origin, :u_axis, :v_axis, :width, :height)

    module_function

    # entity(그룹/컴포넌트)의 바운딩박스 6면을 Convert 툴의 격자 투영 후보로 반환한다.
    # index 0 = 정면(-Y)을 기본값으로 둔다.
    def collect_outer_faces(entity)
      bounds = entity.bounds
      min = bounds.min
      max = bounds.max
      w = max.x - min.x
      d = max.y - min.y
      h = max.z - min.z

      x_axis = Geom::Vector3d.new(1, 0, 0)
      y_axis = Geom::Vector3d.new(0, 1, 0)
      z_axis = Geom::Vector3d.new(0, 0, 1)

      [
        CandidateFace.new(Geom::Vector3d.new(0, -1, 0), Geom::Point3d.new(min.x, min.y, min.z), x_axis, z_axis, w, h),
        CandidateFace.new(Geom::Vector3d.new(0, 1, 0),  Geom::Point3d.new(max.x, max.y, min.z), x_axis.reverse, z_axis, w, h),
        CandidateFace.new(Geom::Vector3d.new(-1, 0, 0), Geom::Point3d.new(min.x, max.y, min.z), y_axis.reverse, z_axis, d, h),
        CandidateFace.new(Geom::Vector3d.new(1, 0, 0),  Geom::Point3d.new(max.x, min.y, min.z), y_axis, z_axis, d, h),
        CandidateFace.new(Geom::Vector3d.new(0, 0, 1),  Geom::Point3d.new(min.x, min.y, max.z), x_axis, y_axis, w, d),
        CandidateFace.new(Geom::Vector3d.new(0, 0, -1), Geom::Point3d.new(min.x, max.y, min.z), x_axis, y_axis.reverse, w, d)
      ]
    end

    def depth_along_normal(bounds, normal)
      if normal.x.abs > 0.5
        bounds.max.x - bounds.min.x
      elsif normal.y.abs > 0.5
        bounds.max.y - bounds.min.y
      else
        bounds.max.z - bounds.min.z
      end
    end

    # min_pt~max_pt를 대각선으로 하는 사각 솔리드 면을 entities 안에 채운다(내부용).
    def fill_box_faces(entities, min_pt, max_pt)
      x0, y0, z0 = [min_pt.x, max_pt.x].min, [min_pt.y, max_pt.y].min, [min_pt.z, max_pt.z].min
      x1, y1, z1 = [min_pt.x, max_pt.x].max, [min_pt.y, max_pt.y].max, [min_pt.z, max_pt.z].max

      pts = [
        Geom::Point3d.new(x0, y0, z0),
        Geom::Point3d.new(x1, y0, z0),
        Geom::Point3d.new(x1, y1, z0),
        Geom::Point3d.new(x0, y1, z0)
      ]
      face = entities.add_face(pts)
      face.reverse! if face.normal.z < 0
      height = z1 - z0
      face.pushpull(height) if height.abs > 0
      entities
    end

    # min_pt~max_pt를 대각선으로 하는 사각 솔리드를 target_entities 안에 새 그룹으로 생성한다.
    def create_box(target_entities, min_pt, max_pt)
      group = target_entities.add_group
      fill_box_faces(group.entities, min_pt, max_pt)
      group
    end

    # 기존 그룹/컴포넌트 인스턴스의 지오메트리를 새 box 치수로 완전히 재생성한다.
    # (Door Gap, 바디 사후축소, Channel 홈 재생성 등에서 재사용)
    # NOTE: instance.transformation이 항등(identity)이라는 전제 하에 동작한다.
    # 이 코드베이스는 모든 솔리드를 회전/오프셋 없이 월드 좌표로 직접 생성하므로 이 전제가 항상 성립한다.
    def redefine_box!(instance, min_pt, max_pt)
      # ComponentInstance는 정의(definition)를 여러 인스턴스가 공유할 수 있으므로,
      # 지오메트리를 고치기 전 항상 make_unique로 분리해 다른 사본에 영향이 번지지 않게 한다.
      instance.make_unique if instance.respond_to?(:make_unique)
      definition = instance.respond_to?(:definition) ? instance.definition : instance
      entities = definition.entities
      entities.clear!
      fill_box_faces(entities, min_pt, max_pt)
      instance
    end

    # Convert 격자의 셀 (row,col) 하나에 해당하는 바디블럭 지오메트리를 만든다.
    # 통짜 솔리드가 아니라, 선택한 면 쪽만 열려있는 5면 캐비닛 쉘(상/하/좌/우/뒷판)로 만든다
    # — 실제 원본 툴의 "칸막이 박스" 형태를 재현한다.
    def build_cell_body(model, source_group, face, row, col, cell_w, cell_h, panel_thk_mm: nil)
      depth = depth_along_normal(source_group.bounds, face.normal)
      panel_thk = Units.mm_to_inch(panel_thk_mm || Constants::DEFAULT_PANEL_THK)
      corner = face.origin.offset(face.u_axis, col * cell_w).offset(face.v_axis, row * cell_h)

      # 패널 두께를 감당하기엔 셀/깊이가 너무 작으면 통짜 솔리드로 대체(안전장치).
      if (panel_thk * 2) >= [cell_w, cell_h].min || panel_thk >= depth
        opposite_corner = corner
                           .offset(face.u_axis, cell_w)
                           .offset(face.v_axis, cell_h)
                           .offset(face.normal.reverse, depth)
        return create_box(model.active_entities, corner, opposite_corner)
      end

      build_shell(model.active_entities, corner, face.u_axis, face.v_axis, face.normal.reverse,
                  cell_w, cell_h, depth, panel_thk)
    end

    # corner를 기준점으로 u(폭)/v(높이)/n(깊이, 앞->뒤) 세 축 방향의 open-front 쉘 박스를 만든다.
    # n=0(앞, corner가 놓인 면)에는 패널을 만들지 않아 그 방향이 뚫려 있다.
    def build_shell(target_entities, corner, u, v, n, cell_w, cell_h, depth, panel_thk)
      group = target_entities.add_group
      entities = group.entities

      far = corner.offset(u, cell_w).offset(v, cell_h).offset(n, depth)

      fill_box_faces(entities, corner.offset(n, depth - panel_thk), far) # 뒷판
      fill_box_faces(entities, corner, corner.offset(u, cell_w).offset(v, panel_thk).offset(n, depth)) # 하판
      fill_box_faces(entities, corner.offset(v, cell_h - panel_thk), far) # 상판
      fill_box_faces(entities, corner, corner.offset(u, panel_thk).offset(v, cell_h).offset(n, depth)) # 좌측판
      fill_box_faces(entities, corner.offset(u, cell_w - panel_thk), far) # 우측판

      group
    end

    # entity를 바디블럭 컴포넌트로 확정하고 이름/속성/태그를 세팅한다 (§4.1a).
    def make_body_block(entity, origin_mass_dims: nil, front_normal: nil)
      model = Sketchup.active_model
      comp = entity.is_a?(Sketchup::ComponentInstance) ? entity : entity.to_component
      comp.definition.name = Naming.next_name(Constants::NAME_BODY)

      dims = origin_mass_dims || bounds_dims_mm(comp.bounds)
      Attrs.set_all(comp,
        'block_type' => 'body',
        'door_thk' => Constants::DEFAULT_DOOR_THK,
        'body_gap' => Constants::DEFAULT_BODY_GAP,
        'panel_thk' => Constants::DEFAULT_PANEL_THK,
        'gap_top' => 0.0,
        'gap_bottom' => 0.0,
        'gap_left' => 0.0,
        'gap_right' => 0.0,
        'channel_mode' => 0,
        'group_id' => new_guid,
        'origin_mass_dims' => dims,
        'front_normal' => front_normal || [0.0, -1.0, 0.0])
      TagManager.assign(model, comp, Constants::TAG_BODY)
      comp
    end

    def bounds_dims_mm(bounds)
      [Units.inch_to_mm(bounds.width), Units.inch_to_mm(bounds.height), Units.inch_to_mm(bounds.depth)]
    end

    def new_guid
      # SketchUp 번들 Ruby는 대부분 SecureRandom을 포함하지만, 혹시 없을 경우를 대비한 폴백.
      require 'securerandom'
      SecureRandom.uuid
    rescue LoadError
      "sufx-#{Time.now.to_f}-#{rand(1_000_000)}"
    end

    def union_bounds(entities)
      combined = Geom::BoundingBox.new
      entities.each { |e| combined.add(e.bounds) }
      combined
    end

    # 두 바운딩박스가 정확히 한 축에서만 맞닿고(gap ~= 0),
    # 나머지 두 축에서는 겹치는 구간이 있는지(=인접한 면 형태) 판정한다.
    def bbox_touches?(a, b, tol_inch)
      axes = %i[x y z]
      touching_axes = 0
      overlapping = true

      axes.each do |axis|
        a_min, a_max = axis_range(a, axis)
        b_min, b_max = axis_range(b, axis)
        overlap_len = [a_max, b_max].min - [a_min, b_min].max # >0: 겹침, <0: 이격거리

        if overlap_len.abs <= tol_inch
          touching_axes += 1
        elsif overlap_len < -tol_inch
          overlapping = false
        end
      end

      touching_axes == 1 && overlapping
    end

    def axis_range(bounds, axis)
      case axis
      when :x then [bounds.min.x, bounds.max.x]
      when :y then [bounds.min.y, bounds.max.y]
      else [bounds.min.z, bounds.max.z]
      end
    end
  end
end
