# Sayou Alt Manager - Alt(Tag+Scene+Group) 생성/전환/삭제/Finalize
#
# Alt 하나 = Tag(레이어) 1개 + Scene(페이지) 1개 + 선택된 그룹(엔티티).
# 그룹과 Alt를 별도 id로 다시 연결하지 않고, "그룹의 layer(Tag)"를 통해서만
# 연결한다 -> 파일을 저장/재실행해도 깨지지 않고, 엔티티 삭제 시에도
# model.layers.remove_layer(tag, true) 한 번으로 해당 Tag가 걸린 모든
# 엔티티(중첩 그룹 포함)를 SketchUp이 알아서 정리해준다.

module SayouAltManager
  module AltManager
    module_function

    # ---- 조회 ----

    def find_alt(data, alt_id)
      data['topics'].each do |topic|
        alt = topic['alts'].find { |a| a['id'] == alt_id }
        return [topic, alt] if alt
      end
      [nil, nil]
    end

    # A, B, ... Z, A1, B1, ... 순서로 Alt 이름을 생성한다.
    def alt_label(seq)
      cycle = seq / 26
      letter = (65 + (seq % 26)).chr
      cycle.zero? ? letter : "#{letter}#{cycle}"
    end

    # ---- 등록 ----

    def register_alt(data, topic_id)
      topic = TopicManager.find_topic(data, topic_id)
      return { 'ok' => false, 'error' => 'topic_not_found' } unless topic

      model = Sketchup.active_model
      selection = model.selection
      return { 'ok' => false, 'error' => 'no_selection' } if selection.empty?

      model.start_operation('Alt Manager - Alt 등록', true)
      begin
        group = group_from_selection(model, selection)

        letter = alt_label(topic['alt_seq'])
        topic['alt_seq'] += 1
        base_name = unique_resource_name(model, "#{topic['name']}_#{letter}")

        tag = find_or_create_tag(model, base_name)
        group.layer = tag

        alt = {
          'id' => Store.next_id(data),
          'name' => letter,
          'tag' => tag.name,
          'scene' => base_name
        }
        topic['alts'] << alt

        apply_topic_visibility(model, topic, alt['id'])
        create_or_update_scene(model, base_name)

        model.commit_operation
        { 'ok' => true, 'alt' => alt }
      rescue StandardError => e
        model.abort_operation
        { 'ok' => false, 'error' => e.message }
      end
    end

    # ---- 전환 ----

    def select_alt(data, alt_id)
      topic, alt = find_alt(data, alt_id)
      return { 'ok' => false, 'error' => 'alt_not_found' } unless alt

      model = Sketchup.active_model
      model.start_operation('Alt Manager - Alt 전환', true)
      begin
        apply_topic_visibility(model, topic, alt_id)

        page = model.pages[alt['scene']]
        model.pages.selected_page = page if page

        data['current_selected_alt'] = alt_id
        model.commit_operation
        { 'ok' => true }
      rescue StandardError => e
        model.abort_operation
        { 'ok' => false, 'error' => e.message }
      end
    end

    # ---- 삭제 ----

    def delete_alt(data, alt_id, delete_entities)
      topic, alt = find_alt(data, alt_id)
      return { 'ok' => false, 'error' => 'alt_not_found' } unless alt

      model = Sketchup.active_model
      model.start_operation('Alt Manager - Alt 삭제', true)
      begin
        remove_alt_resources(model, alt, delete_entities)
        topic['alts'].reject! { |a| a['id'] == alt_id }
        data['current_selected_alt'] = nil if data['current_selected_alt'] == alt_id
        model.commit_operation
        { 'ok' => true }
      rescue StandardError => e
        model.abort_operation
        { 'ok' => false, 'error' => e.message }
      end
    end

    # 선택된 Alt만 남기고 같은 Topic의 나머지 Alt를 정리한다(Tag/Scene/엔티티 모두).
    def finalize(data, keep_alt_id, delete_entities_of_others = true)
      topic, keep_alt = find_alt(data, keep_alt_id)
      return { 'ok' => false, 'error' => 'alt_not_found' } unless keep_alt

      model = Sketchup.active_model
      model.start_operation('Alt Manager - Finalize', true)
      begin
        others = topic['alts'].reject { |a| a['id'] == keep_alt_id }
        others.each { |a| remove_alt_resources(model, a, delete_entities_of_others) }
        topic['alts'] = [keep_alt]
        model.commit_operation
        { 'ok' => true }
      rescue StandardError => e
        model.abort_operation
        { 'ok' => false, 'error' => e.message }
      end
    end

    # Topic 삭제 시 main.rb에서도 재사용하는 리소스 정리 헬퍼.
    def remove_alt_resources(model, alt, delete_entities)
      page = model.pages[alt['scene']]
      model.pages.erase(page) if page

      tag = model.layers[alt['tag']]
      return unless tag

      if tag.respond_to?(:deleted?) # SketchUp 2020+ Tags API 안전 체크
        return if tag.deleted?
      end

      if model.layers.respond_to?(:remove_layer)
        model.layers.remove_layer(tag, delete_entities)
      else
        model.layers.remove(tag, delete_entities)
      end
    end

    # ---- 내부 헬퍼 ----

    def group_from_selection(model, selection)
      if selection.count == 1 &&
         (selection.first.is_a?(Sketchup::Group) || selection.first.is_a?(Sketchup::ComponentInstance))
        selection.first
      else
        model.active_entities.add_group(selection.to_a)
      end
    end

    def find_or_create_tag(model, name)
      model.layers[name] || model.layers.add(name)
    end

    def unique_resource_name(model, base_name)
      return base_name unless model.layers[base_name] || model.pages[base_name]

      i = 2
      candidate = "#{base_name}_#{i}"
      while model.layers[candidate] || model.pages[candidate]
        i += 1
        candidate = "#{base_name}_#{i}"
      end
      candidate
    end

    # 같은 Topic 안에서 active_alt_id에 해당하는 Tag만 보이고
    # 나머지 Alt들의 Tag는 숨긴다. 다른 Topic의 Tag는 건드리지 않는다.
    def apply_topic_visibility(model, topic, active_alt_id)
      topic['alts'].each do |a|
        tag = model.layers[a['tag']]
        next unless tag

        tag.visible = (a['id'] == active_alt_id)
      end
    end

    def create_or_update_scene(model, name)
      page = model.pages[name]
      if page
        page.update
      else
        page = model.pages.add(name)
      end
      page
    end
  end
end
