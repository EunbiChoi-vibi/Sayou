module Sufx
  # SUFX / DOOR 태그(레이어) 트리를 idempotent하게 생성하고 엔티티에 할당한다.
  #
  #   SUFX
  #   ├── SUFX_BODY
  #   ├── SUFX_VALANCE
  #   └── DOOR
  #       ├── SUFX_DOOR
  #       ├── SUFX_DOORLINE
  #       └── SUFX_HIDDEN
  #
  # 폴더 계층은 SketchUp 2020+(Sketchup::Layers#add_folder)에서만 지원되므로,
  # 구버전에서는 폴더 없이 평평한 태그만 생성한다(기능 저하는 있어도 오류는 없게).
  module TagManager
    module_function

    def tags_collection(model)
      model.respond_to?(:tags) ? model.tags : model.layers
    end

    def find_folder(model, name)
      tags = tags_collection(model)
      return nil unless tags.respond_to?(:folders)

      tags.folders.find { |f| f.name == name }
    rescue StandardError
      nil
    end

    def ensure_folder(model, name)
      tags = tags_collection(model)
      return nil unless tags.respond_to?(:add_folder)

      find_folder(model, name) || tags.add_folder(name)
    rescue StandardError
      nil
    end

    def ensure_tag(model, name, folder_name: nil)
      tags = tags_collection(model)
      tag = tags[name]
      tag ||= tags.add(name)

      if folder_name
        folder = ensure_folder(model, folder_name)
        begin
          folder.add_layer(tag) if folder && tag.respond_to?(:folder) && tag.folder != folder
        rescue StandardError
          nil
        end
      end

      tag
    end

    def ensure_tree(model)
      ensure_folder(model, Constants::TAG_ROOT)
      ensure_tag(model, Constants::TAG_BODY, folder_name: Constants::TAG_ROOT)
      ensure_tag(model, Constants::TAG_VALANCE, folder_name: Constants::TAG_ROOT)

      door_folder = ensure_folder(model, Constants::TAG_DOOR_FOLDER)
      root_folder = find_folder(model, Constants::TAG_ROOT)
      if door_folder && root_folder
        begin
          root_folder.add_folder(door_folder) if door_folder.respond_to?(:parent) && door_folder.parent != root_folder
        rescue StandardError
          nil
        end
      end

      ensure_tag(model, Constants::TAG_DOOR, folder_name: Constants::TAG_DOOR_FOLDER)
      ensure_tag(model, Constants::TAG_DOORLINE, folder_name: Constants::TAG_DOOR_FOLDER)
      ensure_tag(model, Constants::TAG_HIDDEN, folder_name: Constants::TAG_DOOR_FOLDER)
    end

    # entity에 태그를 할당한다. path는 "SUFX_BODY" 또는 "DOOR/SUFX_DOOR" 형태(마지막 세그먼트만 사용).
    def assign(model, entity, path)
      ensure_tree(model)
      tag_name = path.to_s.split('/').last
      tag = tags_collection(model)[tag_name] || ensure_tag(model, tag_name)
      entity.layer = tag
    end
  end
end
