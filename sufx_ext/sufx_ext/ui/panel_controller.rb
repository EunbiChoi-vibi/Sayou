require 'json'

module Sufx
  # HtmlDialog 패널 생성/콜백 등록 (§5장).
  module UIPanel
    module_function

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return @dialog
      end

      @dialog = create_dialog
      register_callbacks(@dialog)
      attach_selection_observer
      @dialog.show
      @dialog
    end

    def dialog
      @dialog
    end

    def create_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title: Sufx::EXTENSION_NAME,
        preferences_key: 'com.sayou.sufx_ext.panel',
        scrollable: true,
        resizable: true,
        width: 300,
        height: 680,
        min_width: 260,
        min_height: 480,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_file(File.join(Sufx::PATH_ROOT, 'sufx_ext', 'ui', 'panel.html'))
      dialog
    end

    def register_callbacks(dialog)
      dialog.add_action_callback('onConvertClick') do |_ctx|
        thk = @door_thk || Constants::DEFAULT_DOOR_THK
        gap = @body_gap || Constants::DEFAULT_BODY_GAP
        ok, msg = SufxConvertTool.start!(thk, gap)
        notify_result(dialog, ok, msg)
      end

      dialog.add_action_callback('onMergeClick') do |_ctx|
        ok, msg = Commands::Merge.run!
        notify_result(dialog, ok, msg)
      end

      dialog.add_action_callback('onDivideClick') do |_ctx, axis, count|
        # §4.4: 잘못된 입력은 조용히 무시 (에러 다이얼로그 없음)
        Commands::Divide.run!(axis.to_sym, count.to_i)
      end

      dialog.add_action_callback('onDoorClick') do |_ctx, type|
        thk = @door_thk || Constants::DEFAULT_DOOR_THK
        gap = @body_gap || Constants::DEFAULT_BODY_GAP
        ok, msg = Commands::DoorCreate.run!(type.to_sym, thk, gap)
        notify_result(dialog, ok, msg)
      end

      dialog.add_action_callback('onDoorThkChanged') { |_ctx, v| @door_thk = v.to_f }
      dialog.add_action_callback('onBodyGapChanged') { |_ctx, v| @body_gap = v.to_f }

      dialog.add_action_callback('onDoorGapClick') do |_ctx, dir, mm|
        selection = Sketchup.active_model.selection.to_a
        Commands::DoorGap.run!(selection, dir.to_sym, mm.to_f)
        push_current_selection_state
      end

      # 방향별 입력창(절대값 mm)에서 호출 — 누적(bump)이 아니라 지정한 값으로 그 방향 갭을 직접 설정.
      dialog.add_action_callback('onDoorGapSetClick') do |_ctx, dir, mm|
        selection = Sketchup.active_model.selection.to_a
        Commands::DoorGap.set!(selection, dir.to_sym, mm.to_f)
        push_current_selection_state
      end

      dialog.add_action_callback('onChannelClick') do |_ctx, mode|
        ok, msg = Commands::Channel.run!(mode.to_i)
        notify_result(dialog, ok, msg)
      end
    end

    def notify_result(dialog, ok, msg)
      return if ok

      dialog.execute_script("updateStatus(#{(msg || '').to_s.to_json})")
    end

    def attach_selection_observer
      model = Sketchup.active_model
      @observer ||= SufxSelectionObserver.new(self)
      model.selection.add_observer(@observer)
    rescue StandardError => e
      warn "[SUFX] selection observer attach failed: #{e.message}"
    end

    # SufxSelectionObserver에서 호출 — 선택 변경 시 패널 상태를 갱신한다 (§5.3).
    # door/body는 Sketchup::ComponentInstance 또는 nil.
    def push_selection_state(door, body)
      return unless @dialog && @dialog.visible?

      door_payload =
        if door
          {
            name: door.definition.name,
            top: Attrs.get(door, 'gap_top', Constants::DEFAULT_DOOR_GAP).to_f,
            bottom: Attrs.get(door, 'gap_bottom', Constants::DEFAULT_DOOR_GAP).to_f,
            left: Attrs.get(door, 'gap_left', Constants::DEFAULT_DOOR_GAP).to_f,
            right: Attrs.get(door, 'gap_right', Constants::DEFAULT_DOOR_GAP).to_f
          }
        end
      @dialog.execute_script("updateDoorGapPanel(#{door_payload.to_json})")
      @dialog.execute_script("updateChannelPanel(#{(body ? body.definition.name : nil).to_json})")
    end

    # Door Gap 버튼/입력 조작 직후, 방금 그 값이 실제로 반영됐는지 패널 입력창에도 바로 반영한다.
    def push_current_selection_state
      selection = Sketchup.active_model.selection.to_a
      door = selection.find { |e| Attrs.block_type(e) == 'door' }
      body = selection.find { |e| Attrs.block_type(e) == 'body' }
      push_selection_state(door, body)
    end
  end

  # 선택 변경 감지 → 패널의 "No door/body selected" 텍스트를 갱신한다.
  class SufxSelectionObserver < Sketchup::SelectionObserver
    def initialize(panel_module)
      super()
      @panel = panel_module
    end

    def onSelectionBulkChange(selection)
      notify(selection)
    end

    def onSelectionCleared(_selection)
      notify([])
    end

    private

    def notify(selection)
      door = selection.find { |e| Sufx::Attrs.block_type(e) == 'door' }
      body = selection.find { |e| Sufx::Attrs.block_type(e) == 'body' }
      @panel.push_selection_state(door, body)
    end
  end
end
