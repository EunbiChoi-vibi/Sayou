(function () {
  'use strict';

  function callRuby(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    if (window.sketchup && typeof window.sketchup[name] === 'function') {
      window.sketchup[name].apply(window.sketchup, args);
    }
  }

  function num(id, fallback) {
    var v = parseFloat(document.getElementById(id).value);
    return isNaN(v) ? (fallback || 0) : v;
  }

  function int(id, fallback) {
    var v = parseInt(document.getElementById(id).value, 10);
    return isNaN(v) ? (fallback || 0) : v;
  }

  document.getElementById('btn-convert').addEventListener('click', function () {
    callRuby('onConvertClick');
  });

  document.getElementById('btn-base').addEventListener('click', function () {
    callRuby('onBaseLegClick', 'base', num('input-height', 100));
  });
  document.getElementById('btn-leg').addEventListener('click', function () {
    callRuby('onBaseLegClick', 'leg', num('input-height', 100));
  });

  document.getElementById('btn-merge').addEventListener('click', function () {
    callRuby('onMergeClick');
  });

  document.getElementById('btn-divh').addEventListener('click', function () {
    callRuby('onDivideClick', 'h', int('input-divh-count', 0));
  });
  document.getElementById('btn-divv').addEventListener('click', function () {
    callRuby('onDivideClick', 'v', int('input-divv-count', 0));
  });

  document.querySelectorAll('.door-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      callRuby('onDoorClick', btn.dataset.door);
    });
  });

  document.getElementById('input-door-thk').addEventListener('change', function (e) {
    callRuby('onDoorThkChanged', parseFloat(e.target.value) || 0);
  });
  document.getElementById('input-body-gap').addEventListener('change', function (e) {
    callRuby('onBodyGapChanged', parseFloat(e.target.value) || 0);
  });

  // 방향 아이콘(▲◀▶▼)은 클릭 동작이 없는 순수 표시용이다 — 실제 조정은 옆의 숫자 입력으로 한다.
  ['top', 'bottom', 'left', 'right'].forEach(function (dir) {
    var input = document.getElementById('gap-' + dir + '-input');
    input.addEventListener('change', function () {
      callRuby('onDoorGapSetClick', dir, num('gap-' + dir + '-input', 0));
    });
  });

  document.getElementById('gap-reset').addEventListener('click', function () {
    callRuby('onDoorGapClick', 'reset', 0);
  });

  // R 옆의 스테퍼 — 전체 4방향을 한 번에 1mm씩 조정(All 역할).
  document.querySelectorAll('.gap-all-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      callRuby('onDoorGapClick', 'all', parseFloat(btn.dataset.delta));
    });
  });

  document.querySelectorAll('.channel-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      callRuby('onChannelClick', parseInt(btn.dataset.mode, 10));
    });
  });

  // Ruby -> JS 상태 갱신 (§5.3). Ruby 쪽에서 dialog.execute_script로 직접 호출한다.
  // payload: {name, top, bottom, left, right} 또는 도어 미선택 시 null.
  window.updateDoorGapPanel = function (payload) {
    var statusEl = document.getElementById('door-gap-status');
    var nameEl = document.getElementById('door-gap-name');
    var hasDoor = !!payload;

    statusEl.textContent = hasDoor ? '' : 'No door selected';
    statusEl.style.display = hasDoor ? 'none' : 'block';
    nameEl.textContent = hasDoor ? payload.name : '';

    if (hasDoor) {
      ['top', 'bottom', 'left', 'right'].forEach(function (dir) {
        var input = document.getElementById('gap-' + dir + '-input');
        if (document.activeElement !== input && typeof payload[dir] === 'number') {
          input.value = payload[dir];
        }
      });
    }
  };

  window.updateChannelPanel = function (bodyName) {
    var el = document.getElementById('channel-status');
    if (bodyName) {
      el.textContent = bodyName;
    } else {
      el.textContent = 'No body selected';
    }
    el.style.display = 'block';
  };

  window.updateStatus = function (msg) {
    document.getElementById('status-line').textContent = msg || '';
  };
})();
