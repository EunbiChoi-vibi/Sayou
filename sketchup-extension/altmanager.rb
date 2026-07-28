# Sayou Alt Manager
# SketchUp Ruby Extension - loader / entry point
#
# 설치 방법: 이 파일(altmanager.rb)과 옆의 altmanager/ 폴더를 통째로
# SketchUp Plugins 폴더에 복사하면 Extensions(Plugins) 메뉴에 등록됩니다.

require 'sketchup.rb'
require 'extensions.rb'

module SayouAltManager
  PLUGIN_ROOT = File.dirname(__FILE__)
  MAIN_FILE = File.join(PLUGIN_ROOT, 'altmanager', 'main.rb')

  unless file_loaded?(__FILE__)
    extension = SketchupExtension.new('Sayou Alt Manager', MAIN_FILE)
    extension.description =
      '인테리어 디자인 대안(Alt)을 Tag/Scene으로 자동 생성·전환·정리하는 도구'
    extension.version   = '1.0.0'
    extension.creator   = 'Sayou'
    extension.copyright = "#{Time.now.year} Sayou"

    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
