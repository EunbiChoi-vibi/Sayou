// Sayou Alt Manager - 패널 UI 로직
// Ruby(main.rb)가 add_action_callback으로 등록한 이름들을 window.sketchup.*
// 형태로 호출하고, Ruby는 execute_script로 AltManagerUI.render(data)를
// 호출해 이 파일이 트리를 다시 그리도록 한다.

(function () {
  var state = { topics: [], current_selected_alt: null };

  // Topic 접힘/펼침, "지금 클릭한 대상이 Topic인지 Alt인지"는 Ruby 쪽
  // 데이터가 아니라 패널의 화면 상태이므로 JS에서만 관리한다.
  var collapsed = {};
  var selection = null; // { type: 'alt' | 'topic', id: number }

  function byId(id) {
    return document.getElementById(id);
  }

  function render(data) {
    state = data || state;

    // 삭제된 Topic/Alt를 계속 선택 상태로 들고 있지 않도록 정리
    if (selection && selection.type === 'topic' && !findTopic(selection.id)) {
      selection = null;
    }
    if (selection && selection.type === 'alt' && !findAlt(selection.id)) {
      selection = null;
    }

    var list = byId('topic-list');
    list.innerHTML = '';

    if (!state.topics || state.topics.length === 0) {
      var empty = document.createElement('p');
      empty.className = 'am-empty';
      empty.id = 'empty-msg';
      empty.innerHTML = '등록된 Topic이 없습니다.<br />위에서 새 Topic을 만들어보세요.';
      list.appendChild(empty);
      return;
    }

    state.topics.forEach(function (topic) {
      list.appendChild(buildTopicRow(topic));
    });
  }

  function findTopic(topicId) {
    return (state.topics || []).find(function (t) {
      return t.id === topicId;
    });
  }

  function findAlt(altId) {
    var result = null;
    (state.topics || []).forEach(function (t) {
      var alt = t.alts.find(function (a) {
        return a.id === altId;
      });
      if (alt) result = alt;
    });
    return result;
  }

  function buildTopicRow(topic) {
    var wrap = document.createElement('div');
    wrap.className = 'am-topic';

    var row = document.createElement('div');
    row.className = 'am-topic-row';
    if (selection && selection.type === 'topic' && selection.id === topic.id) {
      row.classList.add('selected');
    }

    var isCollapsed = !!collapsed[topic.id];

    var arrow = document.createElement('span');
    arrow.className = 'am-arrow';
    arrow.textContent = isCollapsed ? '▶' : '▼';
    arrow.addEventListener('click', function (e) {
      e.stopPropagation();
      collapsed[topic.id] = !isCollapsed;
      render(state);
    });

    var name = document.createElement('span');
    name.className = 'am-topic-name';
    name.textContent = topic.name;
    name.title = topic.name;
    name.addEventListener('click', function () {
      selection = { type: 'topic', id: topic.id };
      render(state);
    });

    // 기획안 3장: "Topic 우클릭"으로도 삭제할 수 있어야 한다.
    row.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      window.sketchup.delete_topic(String(topic.id));
    });

    row.appendChild(arrow);
    row.appendChild(name);
    wrap.appendChild(row);

    if (!isCollapsed) {
      wrap.appendChild(buildAltsRow(topic));
    }

    return wrap;
  }

  function buildAltsRow(topic) {
    var altsRow = document.createElement('div');
    altsRow.className = 'am-alts-row';

    topic.alts.forEach(function (alt) {
      altsRow.appendChild(buildAltCard(alt));
    });

    var addBtn = document.createElement('button');
    addBtn.className = 'am-add-btn';
    addBtn.textContent = '+';
    addBtn.title = '모델에서 선택한 그룹을 새 Alt로 등록';
    addBtn.addEventListener('click', function () {
      window.sketchup.register_alt(String(topic.id));
    });
    altsRow.appendChild(addBtn);

    return altsRow;
  }

  function buildAltCard(alt) {
    var card = document.createElement('div');
    card.className = 'am-alt-card';
    if (state.current_selected_alt === alt.id) {
      card.classList.add('selected');
    }

    var thumb = document.createElement('div');
    thumb.className = 'am-alt-thumb';
    thumb.title = (alt.display_name || alt.name) + ' 로 전환';
    if (alt.thumbnail) {
      var img = document.createElement('img');
      img.src = alt.thumbnail;
      img.alt = alt.display_name || alt.name;
      thumb.appendChild(img);
    } else {
      thumb.textContent = alt.name;
    }
    thumb.addEventListener('click', function () {
      selection = { type: 'alt', id: alt.id };
      window.sketchup.select_alt(String(alt.id));
    });
    card.appendChild(thumb);

    var label = document.createElement('div');
    label.className = 'am-alt-label';
    label.textContent = alt.display_name || alt.name;
    label.title = '더블클릭해서 이름 바꾸기';
    label.addEventListener('click', function () {
      selection = { type: 'alt', id: alt.id };
      window.sketchup.select_alt(String(alt.id));
    });
    label.addEventListener('dblclick', function (e) {
      e.stopPropagation();
      startRename(card, label, alt);
    });
    card.appendChild(label);

    return card;
  }

  function startRename(card, label, alt) {
    var input = document.createElement('input');
    input.className = 'am-alt-rename-input';
    input.type = 'text';
    input.maxLength = 40;
    input.value = alt.display_name || alt.name;

    var done = false;
    var commit = function () {
      if (done) return;
      done = true;
      var value = input.value.trim();
      if (value && value !== alt.display_name) {
        window.sketchup.rename_alt(String(alt.id), value);
      } else {
        render(state);
      }
    };
    var cancel = function () {
      if (done) return;
      done = true;
      render(state);
    };

    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') input.blur();
      if (e.key === 'Escape') cancel();
    });
    input.addEventListener('blur', commit);
    input.addEventListener('click', function (e) {
      e.stopPropagation();
    });

    card.replaceChild(input, label);
    input.focus();
    input.select();
  }

  function currentAltSelectionId() {
    if (selection && selection.type === 'alt') return selection.id;
    if (state.current_selected_alt) return state.current_selected_alt;
    return null;
  }

  // ---- 상단 Topic 생성 ----

  byId('create-topic-btn').addEventListener('click', createTopic);
  byId('topic-input').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') createTopic();
  });

  function createTopic() {
    var input = byId('topic-input');
    var name = input.value.trim();
    if (!name) return;
    window.sketchup.create_topic(name);
    input.value = '';
  }

  // ---- Export / Import ----

  byId('export-btn').addEventListener('click', function () {
    window.sketchup.export_topics();
  });

  byId('import-btn').addEventListener('click', function () {
    window.sketchup.import_topics();
  });

  // ---- 하단 툴바 ----

  byId('sync-camera-btn').addEventListener('click', function () {
    window.sketchup.sync_camera();
  });

  // Delete는 "지금 선택된 것"을 지운다: Topic을 클릭해 선택한 상태면
  // Topic을, 그게 아니면 현재 활성화된(하이라이트된) Alt를 지운다.
  byId('delete-btn').addEventListener('click', function () {
    if (selection && selection.type === 'topic') {
      window.sketchup.delete_topic(String(selection.id));
      return;
    }
    var altId = currentAltSelectionId();
    if (altId) {
      window.sketchup.delete_alt(String(altId));
      return;
    }
    window.alert('삭제할 Topic 또는 Alt를 먼저 선택하세요.');
  });

  byId('finalize-btn').addEventListener('click', function () {
    if (!state.current_selected_alt) {
      window.alert('Finalize할 Alt를 먼저 선택하세요.');
      return;
    }
    window.sketchup.finalize();
  });

  window.AltManagerUI = { render: render };

  window.addEventListener('load', function () {
    window.sketchup.ready();
  });
})();
