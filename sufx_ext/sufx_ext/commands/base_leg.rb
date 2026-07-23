module Sufx
  module Commands
    # §4.2 Base(좌대)/Leg(다리) — 선택한 바디블럭들 아래에 지지대를 만든다.
    module BaseLeg
      module_function

      def run!(type, height_mm)
        model = Sketchup.active_model
        bodies = model.selection.to_a.select { |e| Attrs.block_type(e) == 'body' }
        if bodies.empty?
          msg = '바디블럭을 1개 이상 선택하세요.'
          Sketchup.status_text = "SUFX #{type}: #{msg}"
          return [false, msg]
        end
        unless height_mm.is_a?(Numeric) && height_mm > 0
          return [false, '높이값이 올바르지 않습니다.']
        end

        height_inch = Units.mm_to_inch(height_mm)
        model.start_operation(type == :leg ? 'SUFX Leg' : 'SUFX Base', true)
        begin
          bodies.each { |body| add_support(model, body, type, height_inch) }
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("SUFX #{type} 생성 실패: #{e.message}")
          return [false, e.message]
        end
        [true, nil]
      end

      def add_support(model, body, type, height_inch)
        bounds = body.bounds
        min_pt = Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.min.z - height_inch)
        max_pt = Geom::Point3d.new(bounds.max.x, bounds.max.y, bounds.min.z)

        group = BodyBlock.create_box(model.active_entities, min_pt, max_pt)
        comp = group.to_component
        prefix = type == :leg ? Constants::NAME_LEG : Constants::NAME_BASE
        comp.definition.name = Naming.next_name(prefix)
        Attrs.set_all(comp,
                       'block_type' => type.to_s,
                       'parent_body_id' => (Attrs.get(body, 'group_id') || body.guid).to_s)
        TagManager.assign(model, comp, Constants::TAG_BODY)

        create_valance(model, body, height_inch) if type == :leg
        comp
      end

      # 다리(Leg) 사용 시 가림판(Valance)을 자동 생성한다.
      # 별도 SUFX_VALANCE 태그를 사용해 사용자가 태그 트레이에서 껐다 켰다 할 수 있게 하고,
      # 기본은 보이는(visible) 상태로 둔다.
      def create_valance(model, body, height_inch)
        bounds = body.bounds
        valance_thk = Units.mm_to_inch(18.0) # 가림판 두께 placeholder(18T), 실측 후 조정
        min_pt = Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.min.z - height_inch)
        max_pt = Geom::Point3d.new(bounds.max.x, bounds.min.y + valance_thk, bounds.min.z)

        group = BodyBlock.create_box(model.active_entities, min_pt, max_pt)
        comp = group.to_component
        comp.definition.name = Naming.next_name(Constants::NAME_VALANCE)
        Attrs.set_all(comp,
                       'block_type' => 'valance',
                       'parent_body_id' => (Attrs.get(body, 'group_id') || body.guid).to_s)
        TagManager.assign(model, comp, Constants::TAG_VALANCE)
        comp
      end
    end
  end
end
