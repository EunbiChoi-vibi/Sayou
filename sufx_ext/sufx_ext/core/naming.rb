module Sufx
  # 모델별 컴포넌트 이름 자동 증가 카운터.
  # attribute_dictionary에 저장하므로 저장/재오픈해도 값이 유지된다.
  module Naming
    module_function

    def next_name(prefix)
      model = Sketchup.active_model
      dict = model.attribute_dictionary(Constants::META_DICT, true)
      key = "#{prefix}_counter"
      n = (dict[key] || 0) + 1
      dict[key] = n
      "#{prefix}##{n}"
    end
  end
end
