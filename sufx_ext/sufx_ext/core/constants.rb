module Sufx
  module Constants
    DEFAULT_DOOR_THK      = 18.0  # mm
    DEFAULT_BODY_GAP      = 4.0   # mm
    DEFAULT_DOOR_GAP      = 0.0   # mm, 도어 생성 시 4방향 기본 갭(Reset 시에도 이 값으로 돌아감)
    DEFAULT_DOOR_GAP_STEP = 1.0   # mm, All 스테퍼 1클릭당 증가량
    MIN_CELL_SIZE         = 10.0  # mm, 하한 clamp
    DEFAULT_PANEL_THK      = 18.0 # mm, 바디블럭 측판/상판/하판 두께
    DEFAULT_BACK_PANEL_THK = 10.0 # mm, 바디블럭 뒷판 두께

    # 챗넬(CH1/CH2) — 전면 기준 바디 깊이를 파내고(RECESS) 그 자리에 단턱 브라켓을 채운다.
    CHANNEL_RECESS_MM    = 10.0 # mm, Convert에서 선택한 전면 기준으로 바디 깊이를 줄이는 양
    CHANNEL_BAND_H_MM    = 40.0 # mm, 브라켓이 차지하는 세로 폭(전면에서 볼 때)
    CHANNEL_LIP_H_MM     = 10.0 # mm, 브라켓 하단부 중 추가로 더 튀어나오는 구간의 높이
    CHANNEL_LIP_EXTRA_MM = 4.0  # mm, 하단 구간이 나머지(기본 돌출)보다 더 튀어나오는 두께

    # 서랍 상단이 챗넬 브라켓과 부딪히지 않도록 줄여야 하는 높이 — 브라켓 세로 폭과 동일하게 둔다.
    CHANNEL_CLEARANCE = { 0 => 0.0, 1 => CHANNEL_BAND_H_MM, 2 => CHANNEL_BAND_H_MM }.freeze

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
