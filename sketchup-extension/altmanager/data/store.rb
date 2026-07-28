# Sayou Alt Manager - 데이터 저장/복원
#
# 모델의 AttributeDictionary에 Topic/Alt 구조를 JSON 문자열로 저장한다.
# 파일을 닫았다가 다시 열어도 패널 트리 구조가 그대로 복원되어야 하기 때문에
# (기획안 4장) 세션이 아니라 모델 자체에 데이터를 귀속시킨다.

require 'json'

module SayouAltManager
  module Store
    DICT_NAME = 'SayouAltManager'
    KEY = 'data'

    module_function

    def default_data
      { 'topics' => [], 'current_selected_alt' => nil, 'next_id' => 1 }
    end

    def load(model)
      return default_data unless model

      dict = model.attribute_dictionary(DICT_NAME)
      raw = dict && dict[KEY]
      return default_data unless raw

      begin
        data = JSON.parse(raw)
        data['topics'] ||= []
        data['next_id'] ||= 1
        data
      rescue JSON::ParserError
        default_data
      end
    end

    def save(data, model)
      return unless model

      dict = model.attribute_dictionary(DICT_NAME, true)
      dict[KEY] = JSON.generate(data)
    end

    # Topic/Alt에 부여할 다음 고유 id. SketchUp entityID 대신 자체 발급 id를
    # 사용해야 저장 후 다시 불러왔을 때도 안정적으로 참조할 수 있다.
    def next_id(data)
      id = data['next_id'] || 1
      data['next_id'] = id + 1
      id
    end
  end
end
