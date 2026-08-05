# Sayou Alt Manager - Topic 이름 내보내기/불러오기
#
# Alt(Tag+Scene+Group)는 SketchUp 파일마다 고유한 객체라 파일 간에 그대로
# 옮길 수 없다. 그래서 여기서는 실제로 재사용 가능한 부분, 즉 "Topic 이름
# 목록"만 내보내고 불러온다 - 다른 프로젝트 파일에서 같은 Topic 구성을
# 빠르게 세팅한 뒤, Alt는 각 파일에서 새로 등록(+ 버튼)하는 흐름이다.

module SayouAltManager
  module ImportExport
    module_function

    def topic_names(data)
      data['topics'].map { |t| t['name'] }
    end

    # 이름이 겹치지 않는 Topic만 새로 추가하고, 추가된 개수를 반환한다.
    def import_topics(data, names)
      existing = topic_names(data)
      added = 0
      Array(names).each do |name|
        name = name.to_s.strip
        next if name.empty? || existing.include?(name)

        TopicManager.create_topic(data, name)
        existing << name
        added += 1
      end
      { 'ok' => true, 'added' => added }
    end
  end
end
