require 'sketchup.rb'
require 'extensions.rb'

module Sufx
  EXTENSION_ID      = 'sufx_ext'.freeze
  EXTENSION_NAME    = 'SUFX Tools'.freeze
  EXTENSION_VERSION = '0.1.0'.freeze
  EXTENSION_CREATOR = 'Sayou'.freeze

  PATH_ROOT = File.dirname(__FILE__).freeze

  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new(EXTENSION_NAME, File.join(PATH_ROOT, 'sufx_ext', 'main.rb'))
    ext.description = '가구(붙박이장/상부장/하부장) 파라메트릭 모델링 도구 - SUFX Tools'
    ext.version      = EXTENSION_VERSION
    ext.creator      = EXTENSION_CREATOR
    ext.copyright    = "#{EXTENSION_CREATOR} #{Time.now.year}"
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
