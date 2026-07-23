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

  document.querySelectorAll('.gap-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      callRuby('onDoorGapClick', btn.dataset.dir, num('input-gap-step', 1));
    });
  });
  document.getElementById('gap-all').addEventListener('click', function () {
    callRuby('onDoorGapClick', 'all', num('input-gap-step', 1));
  });

  document.querySelectorAll('.channel-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      callRuby('onChannelClick', parseInt(btn.dataset.mode, 10));
    });
  });

  // Ruby -> JS 상태 갱신 (§5.3). Ruby 쪽에서 dialog.execute_script로 직접 호출한다.
  window.updateDoorGapPanel = function (hasDoor) {
    var el = document.getElementById('door-gap-status');
    el.textContent = hasDoor ? '' : 'No door selected';
    el.style.display = hasDoor ? 'none' : 'block';
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
