# Sayou Alt Manager - main entry
# Extension이 로드될 때 실행되는 메인 로직: 대화상자, 메뉴, 콜백, 전역 상태 관리

require 'sketchup.rb'
require 'json'

module SayouAltManager
  PLUGIN_DIR = File.dirname(__FILE__)

  Sketchup.require File.join(PLUGIN_DIR, 'data', 'store')
  Sketchup.require File.join(PLUGIN_DIR, 'core', 'topic_manager')
  Sketchup.require File.join(PLUGIN_DIR, 'core', 'alt_manager')
  Sketchup.require File.join(PLUGIN_DIR, 'core', 'scene_sync')

  @dialog = nil

  # ---- 데이터 로드/저장 ----

  def self.load_data
    Store.load(Sketchup.active_model)
  end

  def self.save_data(data)
    Store.save(data, Sketchup.active_model)
  end

  # 현재 데이터를 HtmlDialog(JS)에 그대로 밀어넣어 트리를 다시 그리게 한다.
  def self.push_state(data = load_data)
    return unless @dialog && @dialog.visible?
    json = JSON.generate(data)
    @dialog.execute_script("AltManagerUI.render(#{json});")
  end

  ERROR_MESSAGES = {
    'no_selection'    => '먼저 모델에서 그룹으로 만들 엔티티를 선택하세요.',
    'topic_not_found' => 'Topic을 찾을 수 없습니다. 패널을 새로고침해 주세요.',
    'alt_not_found'   => 'Alt를 찾을 수 없습니다. 패널을 새로고침해 주세요.',
    'no_alt_selected' => '먼저 Alt를 선택하세요.'
  }.freeze

  def self.report_error(code)
    UI.messagebox(ERROR_MESSAGES[code] || "오류가 발생했습니다: #{code}")
  end

  # Topic 삭제는 하위 Alt들의 Tag/Scene/(옵션)엔티티까지 함께 정리해야 하므로
  # TopicManager와 AltManager 양쪽을 조율하는 로직을 여기서 담당한다.
  def self.delete_topic_with_resources(data, topic_id, delete_entities)
    topic = TopicManager.find_topic(data, topic_id)
    return { 'ok' => false, 'error' => 'topic_not_found' } unless topic

    model = Sketchup.active_model
    model.start_operation('Alt Manager - Topic 삭제', true)
    begin
      topic['alts'].each { |alt| AltManager.remove_alt_resources(model, alt, delete_entities) }
      if topic['alts'].any? { |a| a['id'] == data['current_selected_alt'] }
        data['current_selected_alt'] = nil
      end
      TopicManager.delete_topic(data, topic_id)
      model.commit_operation
      { 'ok' => true }
    rescue StandardError => e
      model.abort_operation
      { 'ok' => false, 'error' => e.message }
    end
  end

  # ---- HtmlDialog ----

  def self.create_dialog
    options = {
      dialog_title: 'Alt Manager',
      preferences_key: 'com.sayou.altmanager',
      scrollable: true,
      resizable: true,
      width: 320,
      height: 520,
      min_width: 260,
      min_height: 360,
      style: UI::HtmlDialog::STYLE_DIALOG
    }
    dialog = UI::HtmlDialog.new(options)
    dialog.set_file(File.join(PLUGIN_DIR, 'ui', 'dialog.html'))
    setup_callbacks(dialog)
    dialog
  end

  def self.setup_callbacks(dialog)
    dialog.add_action_callback('ready') do |_ctx|
      push_state
    end

    dialog.add_action_callback('create_topic') do |_ctx, name|
      data = load_data
      topic = TopicManager.create_topic(data, name)
      if topic
        save_data(data)
        push_state(data)
      end
    end

    dialog.add_action_callback('register_alt') do |_ctx, topic_id|
      data = load_data
      result = AltManager.register_alt(data, topic_id.to_i)
      if result['ok']
        save_data(data)
        push_state(data)
      else
        report_error(result['error'])
      end
    end

    dialog.add_action_callback('select_alt') do |_ctx, alt_id|
      data = load_data
      result = AltManager.select_alt(data, alt_id.to_i)
      if result['ok']
        save_data(data)
        push_state(data)
      else
        report_error(result['error'])
      end
    end

    # Alt 개별 삭제: "그룹(엔티티)도 함께 삭제하시겠습니까?" 예/아니오
    # 예 -> Tag/Scene/엔티티 모두 삭제, 아니오 -> Tag/Scene만 삭제(엔티티는 유지)
    dialog.add_action_callback('delete_alt') do |_ctx, alt_id|
      data = load_data
      _topic, alt = AltManager.find_alt(data, alt_id.to_i)
      next report_error('alt_not_found') unless alt

      answer = UI.messagebox(
        "'#{alt['name']}' Alt를 삭제합니다.\n그룹(엔티티)도 함께 삭제하시겠습니까?",
        MB_YESNO
      )
      delete_entities = (answer == 6) # IDYES

      result = AltManager.delete_alt(data, alt_id.to_i, delete_entities)
      if result['ok']
        save_data(data)
        push_state(data)
      else
        report_error(result['error'])
      end
    end

    # Topic 삭제: "하위 Alt를 모두 삭제하시겠습니까?" -> 예일 때만
    # 엔티티 포함 여부를 한 번 더 확인(하위 Alt가 있는 경우에만)
    dialog.add_action_callback('delete_topic') do |_ctx, topic_id|
      data = load_data
      topic = TopicManager.find_topic(data, topic_id.to_i)
      next report_error('topic_not_found') unless topic

      confirm = UI.messagebox(
        "'#{topic['name']}' Topic의 하위 Alt를 모두 삭제하시겠습니까?",
        MB_YESNO
      )
      next if confirm != 6 # IDYES가 아니면 취소

      delete_entities = false
      if topic['alts'].any?
        answer = UI.messagebox('그룹(엔티티)도 함께 삭제하시겠습니까?', MB_YESNO)
        delete_entities = (answer == 6)
      end

      result = delete_topic_with_resources(data, topic_id.to_i, delete_entities)
      if result['ok']
        save_data(data)
        push_state(data)
      else
        report_error(result['error'])
      end
    end

    # Finalize: 현재 선택된 Alt만 남기고 같은 Topic의 나머지 Alt(Tag/Scene/엔티티)를 정리
    dialog.add_action_callback('finalize') do |_ctx, _payload|
      data = load_data
      alt_id = data['current_selected_alt']
      next report_error('no_alt_selected') unless alt_id

      _topic, alt = AltManager.find_alt(data, alt_id)
      next report_error('alt_not_found') unless alt

      confirm = UI.messagebox(
        "'#{alt['name']}' Alt만 남기고 나머지를 삭제하시겠습니까?",
        MB_YESNO
      )
      next if confirm != 6

      result = AltManager.finalize(data, alt_id, true)
      if result['ok']
        save_data(data)
        push_state(data)
      else
        report_error(result['error'])
      end
    end

    # Sync Camera: 현재 카메라 값을 등록된 모든 Alt Scene에 일괄 반영
    dialog.add_action_callback('sync_camera') do |_ctx, _payload|
      confirm = UI.messagebox('현재 카메라 기준으로 전체 동기화하시겠습니까?', MB_YESNO)
      next if confirm != 6

      data = load_data
      result = SceneSync.sync_camera(data)
      report_error(result['error']) unless result['ok']
    end
  end

  def self.toggle_dialog
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      return
    end
    @dialog = create_dialog
    @dialog.show
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Alt Manager') { toggle_dialog }
    file_loaded(__FILE__)
  end
end
