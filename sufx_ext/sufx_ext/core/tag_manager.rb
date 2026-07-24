module Sufx
  # SUFX / DOOR 태그(레이어) 트리를 idempotent하게 생성하고 엔티티에 할당한다.
  #
  #   SUFX
  #   ├── SUFX_BODY
  #   ├── SUFX_VALANCE
  #   ├── SUFX_CHANNEL
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
      # NOTE: 최신 SketchUp에는 Sketchup::Model#tags 라는 "모델 메타데이터(검색 키워드) 문자열"
      # 프로퍼티가 별도로 존재해서, respond_to?(:tags)만으로 분기하면 그 문자열과 충돌한다
      # (String에 .add를 호출하다 크래시). 레이어/태그 컬렉션은 항상 model.layers로 접근한다.
      model.layers
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
      ensure_tag(model, Constants::TAG_CHANNEL, folder_name: Constants::TAG_ROOT)

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
      doorline_tag = ensure_tag(model, Constants::TAG_DOORLINE, folder_name: Constants::TAG_DOOR_FOLDER)
      apply_center_line_style(model, doorline_tag)
      ensure_tag(model, Constants::TAG_HIDDEN, folder_name: Constants::TAG_DOOR_FOLDER)
    end

    # 도어 표시선(SUFX_DOORLINE) 태그를 중간중간 끊어지는 1점쇄선(Center) 스타일로
    # 지정한다. 라인 스타일은 Layer의 상수가 아니라 모델의 Sketchup::LineStyles
    # 컬렉션에 이름으로 등록되어 있다(model.line_styles["이름"] -> Sketchup::LineStyle
    # -> tag.line_style=). SketchUp 2021+에서만 지원되므로, 없는 버전/이름을 못 찾으면
    # 조용히 건너뛴다(선 자체는 실선으로라도 보인다).
    def apply_center_line_style(model, tag)
      return unless tag && tag.respond_to?(:line_style=)
      return unless model.respond_to?(:line_styles)

      styles = model.line_styles
      names = styles.respond_to?(:names) ? styles.names.to_a : []
      match = names.find { |n| n.to_s =~ /center/i } ||
              names.find { |n| n.to_s =~ /dash.?dot/i } ||
              names.find { |n| n.to_s =~ /dash/i }
      return unless match

      style = styles[match]
      tag.line_style = style if style
    rescue StandardError => e
      warn "[SUFX] apply_center_line_style failed: #{e.message}"
    end

    # entity에 태그를 할당한다. path는 "SUFX_BODY" 또는 "DOOR/SUFX_DOOR" 형태(마지막 세그먼트만 사용).
    # 태깅은 부가 기능이므로, 실패하더라도 지오메트리 생성(Convert/Merge/... ) 자체는
    # 막지 않도록 예외를 삼킨다.
    def assign(model, entity, path)
      ensure_tree(model)
      tag_name = path.to_s.split('/').last
      tag = tags_collection(model)[tag_name] || ensure_tag(model, tag_name)
      entity.layer = tag if tag
    rescue StandardError => e
      warn "[SUFX] TagManager.assign failed for #{path}: #{e.message}"
    end
  end
end
