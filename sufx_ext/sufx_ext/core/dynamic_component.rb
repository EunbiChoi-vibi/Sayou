module Sufx
  # "SUFX" attribute dictionary 읽기/쓰기 헬퍼 + Dynamic Component 속성 셋업.
  # SketchUp 표준 Dynamic Component 속성(dc_*)과 분리해서 "SUFX" 딕셔너리를 사용한다.
  module Attrs
    module_function

    # entity(Group/ComponentInstance)에서 SUFX 속성값을 읽는다.
    def get(entity, key, default = nil)
      dict = entity.attribute_dictionary(Constants::ATTR_DICT)
      return default unless dict
      value = dict[key.to_s]
      value.nil? ? default : value
    end

    def set(entity, key, value)
      entity.set_attribute(Constants::ATTR_DICT, key.to_s, value)
    end

    def set_all(entity, hash)
      hash.each { |k, v| set(entity, k, v) }
    end

    def block_type(entity)
      get(entity, 'block_type')
    end

    def block_type?(entity, type)
      block_type(entity).to_s == type.to_s
    end

    # from -> to 로 SUFX 딕셔너리 전체를 복사한다 (Divide 시 origin_mass_dims 등 상속용).
    def copy(from, to)
      dict = from.attribute_dictionary(Constants::ATTR_DICT)
      return unless dict
      dict.each_pair { |k, v| to.set_attribute(Constants::ATTR_DICT, k, v) }
    end
  end

  # Dynamic Component(dc_*) 표준 속성 셋업 헬퍼.
  # 옵션 A(스케일 6핸들을 DC formula로 제한)를 쓸 경우를 위해 최소한의 골격만 제공한다.
  # 현재 구현은 tools/scale_tool.rb의 커스텀 Scale 툴(옵션 B)을 우선 사용하고,
  # 이 모듈은 향후 DC 기반 전환을 위한 확장 지점으로 남겨둔다.
  module DynamicComponent
    module_function

    def setup(instance, length_x:, length_y:, length_z:)
      definition = instance.definition
      instance.set_attribute('dynamic_attributes', '_definitionname', definition.name)
      instance.set_attribute('dynamic_attributes', 'lenx', length_x)
      instance.set_attribute('dynamic_attributes', 'leny', length_y)
      instance.set_attribute('dynamic_attributes', 'lenz', length_z)
      definition.set_attribute('dynamic_attributes', '_dynamic_component_init', true)
    rescue StandardError => e
      # DC 속성 셋업은 부가 기능이므로 실패해도 본 지오메트리 생성 흐름은 막지 않는다.
      warn "[SUFX] DynamicComponent.setup failed: #{e.message}"
    end
  end
end
