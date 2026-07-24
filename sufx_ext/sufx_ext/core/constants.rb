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

    # mm, 챗넬 밴드 바로 아래에서 도어/서랍 상단이 추가로 띄워야 하는 여유(모든 도어 타입 공통).
    CHANNEL_DOOR_CLEARANCE_MM = 15.0

    # Base(좌대)/Leg(다리) — Convert 인터랙티브 툴 안에서 B/L로 토글, +/-로 5mm씩 조정.
    DEFAULT_BASE_HEIGHT_MM = 60.0  # mm, Base 기본 높이
    DEFAULT_LEG_HEIGHT_MM  = 100.0 # mm, Leg 기본 높이
    SUPPORT_HEIGHT_STEP_MM = 5.0   # mm, +/- 1회당 조정량
    SUPPORT_MIN_HEIGHT_MM  = 5.0   # mm, 하한 clamp
    LEG_DIAMETER_MM        = 40.0  # mm, 다리 원기둥 지름(D40)
    LEG_INSET_MM           = 80.0  # mm, 다리 중심이 모서리에서 안쪽으로 들어가는 거리
    LEG_VALANCE_THK_MM     = 10.0  # mm, 다리 전면 가림막 두께(10T)

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
