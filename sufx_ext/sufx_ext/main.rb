module Sufx
  module_function

  def load_files
    base = File.dirname(__FILE__)
    %w[
      core/constants
      core/naming
      core/dynamic_component
      core/tag_manager
      core/body_block
      tools/convert_tool
      tools/scale_tool
      commands/merge
      commands/divide
      commands/door_lines
      commands/door_create
      commands/door_gap
      commands/channel
      ui/panel_controller
    ].each { |rel| require File.join(base, "#{rel}.rb") }
  end

  load_files
end

unless file_loaded?(__FILE__)
  toolbar = UI::Toolbar.new(Sufx::EXTENSION_NAME)

  cmd = UI::Command.new('SUFX Tools') { Sufx::UIPanel.show }
  cmd.tooltip = 'SUFX Tools 패널 열기'
  cmd.status_bar_text = '가구 파라메트릭 모델링 패널을 엽니다.'

  icon_dir = File.join(File.dirname(__FILE__), 'html', 'icons')
  small_icon = File.join(icon_dir, 'sufx_16.png')
  large_icon = File.join(icon_dir, 'sufx_24.png')
  cmd.small_icon = small_icon if File.exist?(small_icon)
  cmd.large_icon = large_icon if File.exist?(large_icon)

  toolbar.add_item(cmd)
  toolbar.show

  extensions_menu = UI.menu('Extensions')
  sufx_menu = extensions_menu.add_submenu(Sufx::EXTENSION_NAME)
  sufx_menu.add_item('SUFX Tools 패널 열기') { Sufx::UIPanel.show }
  sufx_menu.add_item('SUFX Scale (6-핸들)') { Sufx::SufxScaleTool.start! }

  file_loaded(__FILE__)
end
