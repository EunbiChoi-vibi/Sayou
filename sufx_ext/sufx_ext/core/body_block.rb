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

    # center를 밑면 중심으로, axis_vector 방향으로 height만큼 밀어올린 원기둥을
    # target_entities 안에 새 그룹으로 생성한다(Leg 다리용).
    def create_cylinder(target_entities, center, radius, height, axis_vector)
      group = target_entities.add_group
      entities = group.entities
      circle_edges = entities.add_circle(center, axis_vector, radius, 24)
      face = entities.add_face(circle_edges)
      face.reverse! if face.normal.dot(axis_vector) < 0
      face.pushpull(height)
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
    # 통짜 솔리드가 아니라, 선택한 면 쪽만 열려있는 5면 캐비닛 쉘(상/하/좌/우판 + 얇은 뒷판)로 만든다
    # — 실제 원본 툴의 "칸막이 박스" 형태를 재현한다.
    #
    # setback_mm: 문이 나중에 들어갈 자리만큼(기본 door_thk+body_gap) 앞부분을 아예 비워두고
    # 그만큼 안쪽에서부터 쉘을 만든다. 이렇게 해두면 Door 생성 시 바디를 추가로 깎지 않아도
    # 도어-바디 최종 간격이 정확히 body_gap이 된다(§도어 생성 참고).
    def build_cell_body(model, source_group, face, row, col, cell_w, cell_h,
                         panel_thk_mm: nil, back_thk_mm: nil, setback_mm: nil)
      depth_full = depth_along_normal(source_group.bounds, face.normal)
      panel_thk = Units.mm_to_inch(panel_thk_mm || Constants::DEFAULT_PANEL_THK)
      back_thk = Units.mm_to_inch(back_thk_mm || Constants::DEFAULT_BACK_PANEL_THK)
      setback = Units.mm_to_inch(setback_mm || (Constants::DEFAULT_DOOR_THK + Constants::DEFAULT_BODY_GAP))
      setback = 0 if setback >= depth_full # 마스가 셋백보다 얕으면 셋백을 포기(안전장치)

      base_corner = face.origin.offset(face.u_axis, col * cell_w).offset(face.v_axis, row * cell_h)
      corner = base_corner.offset(face.normal.reverse, setback)
      depth = depth_full - setback

      # 패널 두께를 감당하기엔 셀/깊이가 너무 작으면 통짜 솔리드로 대체(안전장치).
      if (panel_thk * 2) >= [cell_w, cell_h].min || back_thk >= depth
        opposite_corner = corner
                           .offset(face.u_axis, cell_w)
                           .offset(face.v_axis, cell_h)
                           .offset(face.normal.reverse, depth)
        return create_box(model.active_entities, corner, opposite_corner)
      end

      build_shell(model.active_entities, corner, face.u_axis, face.v_axis, face.normal.reverse,
                  cell_w, cell_h, depth, panel_thk, back_thk)
    end

    # corner를 기준점으로 u(폭)/v(높이)/n(깊이, 앞->뒤) 세 축 방향의 open-front 쉘 박스를 만든다.
    # n=0(앞, corner가 놓인 면)에는 패널을 만들지 않아 그 방향이 뚫려 있다.
    #
    # 실제 가구 짜임 순서를 그대로 따라 서로 겹치지 않게(면이 깨지지 않게) 만든다:
    #   1) 측판(좌/우, panel_thk) — 세로/깊이 전체를 관통하는 기준 부재
    #   2) 뒷판(back_thk) — 세로는 측판과 동일한 풀 하이트, 가로는 측판 두께만큼 제외,
    #      맨 뒤(n 방향 끝)에 얇게 낀다
    #   3) 상/하판(panel_thk) — 가로는 측판 두께, 깊이는 뒷판 두께를 제외한 범위(뒷판 앞쪽)까지
    # 이렇게 하면 5개 패널의 부피가 서로 겹치지 않아(경계면만 맞닿아) 겹친 면/여분의 선이 남지 않는다.
    #
    # 각 패널은 create_box로 "자기만의 서브그룹" 안에 따로 만든다 — 5개를 전부 같은
    # entities에 직접 채우면(구버전 방식) 서로 맞닿는 경계에서 SketchUp이 지오메트리를
    # 자동 병합/분할하다가 특정 면(특히 하판)이 사라지는 문제가 있었다. 서브그룹으로
    # 격리하면 패널끼리 절대 서로의 지오메트리에 영향을 주지 않는다.
    def build_shell(target_entities, corner, u, v, n, cell_w, cell_h, depth, panel_thk, back_thk)
      group = target_entities.add_group
      entities = group.entities
      depth_front = depth - back_thk # 상/하판이 차지하는 깊이(뒷판 두께만큼 제외)

      # 1) 측판 — 세로/깊이 전체 관통
      create_box(entities, corner,
                 corner.offset(u, panel_thk).offset(v, cell_h).offset(n, depth)) # 좌측판
      create_box(entities, corner.offset(u, cell_w - panel_thk),
                 corner.offset(u, cell_w).offset(v, cell_h).offset(n, depth)) # 우측판

      # 2) 뒷판 — 세로는 측판과 동일(풀 하이트), 가로는 측판 두께 제외, 맨 뒤에 얇게
      create_box(entities,
                 corner.offset(u, panel_thk).offset(n, depth - back_thk),
                 corner.offset(u, cell_w - panel_thk).offset(v, cell_h).offset(n, depth)) # 뒷판

      # 3) 상/하판 — 가로는 측판 두께 제외, 깊이는 뒷판 두께만큼 제외(뒷판과 안 겹치게)
      create_box(entities, corner.offset(u, panel_thk),
                 corner.offset(u, cell_w - panel_thk).offset(v, panel_thk).offset(n, depth_front)) # 하판
      create_box(entities, corner.offset(u, panel_thk).offset(v, cell_h - panel_thk),
                 corner.offset(u, cell_w - panel_thk).offset(v, cell_h).offset(n, depth_front)) # 상판

      group
    end

    # 이미 알고 있는 월드 바운딩박스(min_pt~max_pt)로부터 open-front 쉘을 만든다.
    # Merge처럼 "기존 바디들을 합친 새 바운딩박스"로 바디를 다시 만들어야 할 때 쓴다
    # — build_cell_body처럼 Convert의 CandidateFace가 없어도 front_normal_vec만으로 동작한다.
    def build_shell_from_bounds(target_entities, min_pt, max_pt, front_normal_vec, panel_thk_inch, back_thk_inch)
      frame = axis_frame(front_normal_vec)
      depth_a, u_a, v_a = axis_values(frame, min_pt)
      depth_b, u_b, v_b = axis_values(frame, max_pt)
      depth_lo, depth_hi = [depth_a, depth_b].minmax
      u_lo, u_hi = [u_a, u_b].minmax
      v_lo, v_hi = [v_a, v_b].minmax

      depth = depth_hi - depth_lo
      cell_w = u_hi - u_lo
      cell_h = v_hi - v_lo

      if (panel_thk_inch * 2) >= [cell_w, cell_h].min || back_thk_inch >= depth
        return create_box(target_entities, min_pt, max_pt)
      end

      front_depth_val = frame[:depth_sign].positive? ? depth_hi : depth_lo
      corner = point_on_frame(frame, front_depth_val, u_lo, v_lo)
      n = front_normal_vec.reverse

      build_shell(target_entities, corner, frame[:u_axis], frame[:v_axis], n, cell_w, cell_h, depth,
                  panel_thk_inch, back_thk_inch)
    end

    # entity를 바디블럭 컴포넌트로 확정하고 이름/속성/태그를 세팅한다 (§4.1a).
    def make_body_block(entity, origin_mass_dims: nil, front_normal: nil, door_thk_mm: nil, body_gap_mm: nil)
      model = Sketchup.active_model
      comp = entity.is_a?(Sketchup::ComponentInstance) ? entity : entity.to_component
      comp.definition.name = Naming.next_name(Constants::NAME_BODY)

      dims = origin_mass_dims || bounds_dims_mm(comp.bounds)
      Attrs.set_all(comp,
        'block_type' => 'body',
        'door_thk' => door_thk_mm || Constants::DEFAULT_DOOR_THK,
        'body_gap' => body_gap_mm || Constants::DEFAULT_BODY_GAP,
        'panel_thk' => Constants::DEFAULT_PANEL_THK,
        'back_panel_thk' => Constants::DEFAULT_BACK_PANEL_THK,
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

    def dominant_axis(vec)
      ax, ay, az = vec.x.abs, vec.y.abs, vec.z.abs
      return :x if ax >= ay && ax >= az
      return :y if ay >= az

      :z
    end

    # front_normal_vec(바디의 "열린 면" 바깥쪽 방향, 월드축 정렬 단위벡터)로부터
    # 도어/갭 계산에 필요한 로컬 좌표계를 만든다.
    # - depth_axis/depth_sign: 문이 붙는 방향의 축과 부호(+1: 그 축의 max쪽이 바깥, -1: min쪽이 바깥)
    # - u_axis/u_sym: 좌우(가로) 방향, v_axis/v_sym: 상하(세로) 방향 — 가능하면 Z를 세로로 둔다.
    # Convert에서 어떤 면(Tab으로 전환한 면)을 선택했든 도어가 그 면을 바라보고 붙도록
    # 하기 위한 공용 헬퍼 — door_create.rb/door_gap.rb에서 공유해서 쓴다.
    def axis_frame(front_normal_vec)
      depth_axis = dominant_axis(front_normal_vec)
      depth_sign = front_normal_vec.send(depth_axis) >= 0 ? 1 : -1

      remaining = %i[x y z] - [depth_axis]
      v_sym = remaining.include?(:z) ? :z : remaining.first
      u_sym = (remaining - [v_sym]).first

      unit = { x: Geom::Vector3d.new(1, 0, 0), y: Geom::Vector3d.new(0, 1, 0), z: Geom::Vector3d.new(0, 0, 1) }
      {
        depth_axis: depth_axis,
        depth_sign: depth_sign,
        u_sym: u_sym,
        v_sym: v_sym,
        u_axis: unit[u_sym],
        v_axis: unit[v_sym]
      }
    end

    # depth_axis/u_sym/v_sym(axis_frame에서 얻은 것)에 각각 값을 배정해 Point3d를 만든다.
    def point_on_frame(frame, depth_val, u_val, v_val)
      coords = { frame[:depth_axis] => depth_val, frame[:u_sym] => u_val, frame[:v_sym] => v_val }
      Geom::Point3d.new(coords[:x], coords[:y], coords[:z])
    end

    # point_on_frame의 역연산 — 월드좌표 Point3d에서 [depth_val, u_val, v_val]을 뽑아낸다.
    def axis_values(frame, point)
      coords = { x: point.x, y: point.y, z: point.z }
      [coords[frame[:depth_axis]], coords[frame[:u_sym]], coords[frame[:v_sym]]]
    end
  end
end
