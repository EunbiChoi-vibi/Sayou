module Sufx
  module Constants
    DEFAULT_DOOR_THK      = 18.0  # mm
    DEFAULT_BODY_GAP      = 4.0   # mm
    DEFAULT_DOOR_GAP      = 0.0   # mm, 도어 생성 시 4방향 기본 갭(Reset 시에도 이 값으로 돌아감)
    DEFAULT_DOOR_GAP_STEP = 1.0   # mm, All 스테퍼 1클릭당 증가량
    MIN_CELL_SIZE         = 10.0  # mm, 하한 clamp
    DEFAULT_PANEL_THK      = 18.0 # mm, 바디블럭 측판/상판/하판 두께
    DEFAULT_BACK_PANEL_THK = 10.0 # mm, 바디블럭 뒷판 두께

    # mm, 임의 추정값(placeholder) — 실측 후 조정 필요
    CHANNEL_CLEARANCE = { 0 => 0.0, 1 => 20.0, 2 => 40.0 }.freeze

    SCALE_HANDLE_AXES = [:x, :y, :z].freeze

    ADJACENCY_TOLERANCE_MM = 0.1

    TAG_ROOT        = 'SUFX'.freeze
    TAG_BODY         = 'SUFX_BODY'.freeze
    TAG_DOOR_FOLDER  = 'DOOR'.freeze
    TAG_DOOR         = 'SUFX_DOOR'.freeze
    TAG_DOORLINE     = 'SUFX_DOORLINE'.freeze
    TAG_HIDDEN       = 'SUFX_HIDDEN'.freeze
    TAG_VALANCE      = 'SUFX_VALANCE'.freeze
    TAG_CHANNEL      = 'SUFX_CHANNEL'.freeze

    NAME_BODY    = 'SUFX_BODY'.freeze
    NAME_DOOR    = 'SUFX_DOOR'.freeze
    NAME_BASE    = 'SUFX_BASE'.freeze
    NAME_LEG     = 'SUFX_LEG'.freeze
    NAME_VALANCE = 'SUFX_VALANCE'.freeze

    ATTR_DICT      = 'SUFX'.freeze
    META_DICT      = 'SUFX_META'.freeze
  end
end
