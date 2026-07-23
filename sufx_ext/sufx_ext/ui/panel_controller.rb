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
      dialog.add_action_callback('onConvertClick') { |_ctx| SufxConvertTool.start! }

      dialog.add_action_callback('onBaseLegClick') do |_ctx, type, height_mm|
        ok, msg = Commands::BaseLeg.run!(type.to_sym, height_mm.to_f)
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
    def push_selection_state(door_selected, body_name)
      return unless @dialog && @dialog.visible?

      @dialog.execute_script("updateDoorGapPanel(#{door_selected ? 'true' : 'false'})")
      @dialog.execute_script("updateChannelPanel(#{(body_name ? body_name : nil).to_json})")
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
      @panel.push_selection_state(!door.nil?, body ? body.definition.name : nil)
    end
  end
end
