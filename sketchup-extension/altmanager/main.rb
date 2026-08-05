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
  Sketchup.require File.join(PLUGIN_DIR, 'core', 'import_export')
  Sketchup.require File.join(PLUGIN_DIR, 'core', 'undo_observer')

  @dialog = nil
  @undo_observer = nil

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
    'no_alt_selected' => '먼저 Alt를 선택하세요.',
    'invalid_name'    => '이름을 입력하세요.'
  }.freeze

  def self.report_error(code)
    UI.messagebox(ERROR_MESSAGES[code] || "오류가 발생했습니다: #{code}")
  end

  # 모든 데이터 변경 콜백의 공통 골격.
  # - 하나의 SketchUp Operation 안에서 (1) 블록 실행 (2) AttributeDictionary
  #   저장까지 함께 커밋한다 -> Undo/Redo 한 번으로 Tag/Scene 변경과 패널
  #   데이터가 항상 같이 되돌아간다.
  # - 블록은 data(Hash)를 받아 { 'ok' => true/false, 'error' => ... } 형태의
  #   결과 Hash를 반환해야 한다.
  def self.run_op(op_name)
    model = Sketchup.active_model
    data = load_data
    model.start_operation(op_name, true)
    begin
      result = yield(data)
      if result && result['ok']
        save_data(data)
        model.commit_operation
        push_state(data)
      else
        model.abort_operation
        report_error(result && result['error'])
      end
    rescue StandardError => e
      model.abort_operation
      report_error(e.message)
    end
  end

  # Topic 삭제는 하위 Alt들의 Tag/Scene/(옵션)엔티티까지 함께 정리해야 하므로
  # TopicManager와 AltManager 양쪽을 조율하는 로직을 여기서 담당한다.
  def self.delete_topic_with_resources(data, topic_id, delete_entities)
    topic = TopicManager.find_topic(data, topic_id)
    return { 'ok' => false, 'error' => 'topic_not_found' } unless topic

    model = Sketchup.active_model
    topic['alts'].each { |alt| AltManager.remove_alt_resources(model, alt, delete_entities) }
    if topic['alts'].any? { |a| a['id'] == data['current_selected_alt'] }
      data['current_selected_alt'] = nil
    end
    TopicManager.delete_topic(data, topic_id)
    { 'ok' => true }
  end

  # ---- HtmlDialog ----

  def self.create_dialog
    options = {
      dialog_title: 'Alt Manager',
      preferences_key: 'com.sayou.altmanager',
      scrollable: true,
      resizable: true,
      width: 320,
      height: 560,
      min_width: 260,
      min_height: 360,
      style: UI::HtmlDialog::STYLE_DIALOG
    }
    dialog = UI::HtmlDialog.new(options)
    dialog.set_file(File.join(PLUGIN_DIR, 'ui', 'dialog.html'))
    setup_callbacks(dialog)
    dialog.set_on_closed { detach_undo_observer }
    dialog
  end

  def self.setup_callbacks(dialog)
    dialog.add_action_callback('ready') do |_ctx|
      push_state
    end

    dialog.add_action_callback('create_topic') do |_ctx, name|
      run_op('Alt Manager - Topic 생성') do |data|
        topic = TopicManager.create_topic(data, name)
        topic ? { 'ok' => true } : { 'ok' => false, 'error' => 'invalid_name' }
      end
    end

    dialog.add_action_callback('register_alt') do |_ctx, topic_id|
      run_op('Alt Manager - Alt 등록') { |data| AltManager.register_alt(data, topic_id.to_i) }
    end

    dialog.add_action_callback('select_alt') do |_ctx, alt_id|
      run_op('Alt Manager - Alt 전환') { |data| AltManager.select_alt(data, alt_id.to_i) }
    end

    dialog.add_action_callback('rename_alt') do |_ctx, alt_id, new_name|
      run_op('Alt Manager - Alt 이름 변경') { |data| AltManager.rename_alt(data, alt_id.to_i, new_name) }
    end

    # Alt 개별 삭제: "그룹(엔티티)도 함께 삭제하시겠습니까?" 예/아니오
    # 예 -> Tag/Scene/엔티티 모두 삭제, 아니오 -> Tag/Scene만 삭제(엔티티는 유지)
    dialog.add_action_callback('delete_alt') do |_ctx, alt_id|
      peek = load_data
      _topic, alt = AltManager.find_alt(peek, alt_id.to_i)
      next report_error('alt_not_found') unless alt

      answer = UI.messagebox(
        "'#{alt['display_name'] || alt['name']}' Alt를 삭제합니다.\n그룹(엔티티)도 함께 삭제하시겠습니까?",
        MB_YESNO
      )
      delete_entities = (answer == 6) # IDYES

      run_op('Alt Manager - Alt 삭제') { |data| AltManager.delete_alt(data, alt_id.to_i, delete_entities) }
    end

    # Topic 삭제: "하위 Alt를 모두 삭제하시겠습니까?" -> 예일 때만
    # 엔티티 포함 여부를 한 번 더 확인(하위 Alt가 있는 경우에만)
    dialog.add_action_callback('delete_topic') do |_ctx, topic_id|
      peek = load_data
      topic = TopicManager.find_topic(peek, topic_id.to_i)
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

      run_op('Alt Manager - Topic 삭제') { |data| delete_topic_with_resources(data, topic_id.to_i, delete_entities) }
    end

    # Finalize: 현재 선택된 Alt만 남기고 같은 Topic의 나머지 Alt(Tag/Scene/엔티티)를 정리
    dialog.add_action_callback('finalize') do |_ctx, _payload|
      peek = load_data
      alt_id = peek['current_selected_alt']
      next report_error('no_alt_selected') unless alt_id

      _topic, alt = AltManager.find_alt(peek, alt_id)
      next report_error('alt_not_found') unless alt

      confirm = UI.messagebox(
        "'#{alt['display_name'] || alt['name']}' Alt만 남기고 나머지를 삭제하시겠습니까?",
        MB_YESNO
      )
      next if confirm != 6

      run_op('Alt Manager - Finalize') { |data| AltManager.finalize(data, alt_id, true) }
    end

    # Sync Camera: 현재 카메라 값을 등록된 모든 Alt Scene에 일괄 반영
    dialog.add_action_callback('sync_camera') do |_ctx, _payload|
      confirm = UI.messagebox('현재 카메라 기준으로 전체 동기화하시겠습니까?', MB_YESNO)
      next if confirm != 6

      run_op('Alt Manager - Sync Camera') { |data| SceneSync.sync_camera(data) }
    end

    # Topic 이름 내보내기: Tag/Scene/Group은 파일마다 고유해 옮길 수 없으므로
    # 재사용 가능한 "Topic 이름 목록"만 JSON으로 저장한다.
    dialog.add_action_callback('export_topics') do |_ctx, _payload|
      data = load_data
      if data['topics'].empty?
        UI.messagebox('내보낼 Topic이 없습니다.')
        next
      end

      path = UI.savepanel('Alt Manager - Topic 이름 내보내기', Dir.home, 'altmanager_topics.json')
      next unless path

      path += '.json' unless path.end_with?('.json')
      File.write(path, JSON.pretty_generate('topics' => ImportExport.topic_names(data)))
      UI.messagebox("#{data['topics'].length}개 Topic 이름을 내보냈습니다.\n#{path}")
    end

    # Topic 이름 불러오기: 다른 파일에서 내보낸 이름 목록을 이 파일의 Topic으로 추가한다.
    dialog.add_action_callback('import_topics') do |_ctx, _payload|
      path = UI.openpanel('Alt Manager - Topic 이름 불러오기', Dir.home, 'JSON|*.json||')
      next unless path

      begin
        parsed = JSON.parse(File.read(path))
      rescue StandardError
        next UI.messagebox('올바른 JSON 파일이 아닙니다.')
      end

      names = parsed.is_a?(Hash) ? parsed['topics'] : nil
      next UI.messagebox('올바른 Alt Manager 내보내기 파일이 아닙니다.') unless names.is_a?(Array)

      run_op('Alt Manager - Topic 불러오기') do |data|
        result = ImportExport.import_topics(data, names)
        UI.messagebox("#{result['added']}개 Topic을 불러왔습니다.") if result['ok']
        result
      end
    end
  end

  def self.attach_undo_observer
    model = Sketchup.active_model
    return unless model

    detach_undo_observer
    @undo_observer = UndoObserver.new
    model.add_observer(@undo_observer)
  end

  def self.detach_undo_observer
    return unless @undo_observer

    model = Sketchup.active_model
    model.remove_observer(@undo_observer) if model
    @undo_observer = nil
  end

  def self.toggle_dialog
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      return
    end
    @dialog = create_dialog
    @dialog.show
    attach_undo_observer
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Alt Manager') { toggle_dialog }
    file_loaded(__FILE__)
  end
end
