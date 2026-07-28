# Sayou Alt Manager - Topic 생성/조회/삭제
# Topic은 Tag/Scene을 직접 다루지 않는 순수 데이터 구조체다.
# (Topic 삭제 시 하위 Alt의 SketchUp 리소스 정리는 main.rb에서 AltManager와 조율한다)

module SayouAltManager
  module TopicManager
    module_function

    def create_topic(data, name)
      name = name.to_s.strip
      return nil if name.empty?

      topic = {
        'id' => Store.next_id(data),
        'name' => name,
        'alt_seq' => 0, # 삭제되어도 재사용하지 않는 Alt 이름 시퀀스(A,B,C... 중복 방지)
        'alts' => []
      }
      data['topics'] << topic
      topic
    end

    def find_topic(data, topic_id)
      data['topics'].find { |t| t['id'] == topic_id }
    end

    def delete_topic(data, topic_id)
      data['topics'].reject! { |t| t['id'] == topic_id }
    end
  end
end
