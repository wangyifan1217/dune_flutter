/// C4 NOVA：AI 助手会话 ensure、历史、SSE 流式与 tool_call UI（注入 WebView）。
abstract final class NovaChatInjection {
  static const js = r'''
window.DunesNovaChat = (function () {
  var convId = 0;
  var sending = false;
  var novaPeerRead = 0;
  var bgStreaming = false;
  var novaServerGenerating = false;
  var novaGenAfterMsgId = 0;
  var novaGenStatus = '正在生成…';
  var novaGenPollTimer = null;
  var scrollObserved = false;
  var novaHistoryAll = [];
  var novaHistoryHasMore = false;
  var novaHistoryOldestAt = '';
  var novaHistoryLoading = false;
  var novaMsgHasMore = false;
  var novaMsgOldestId = 0;
  var novaMsgHasNewer = false;
  var novaMsgNewestId = 0;
  var novaMsgLoadingOlder = false;
  var novaMsgLoadingNewer = false;
  var novaSuppressAutoScroll = false;
  var NOVA_GEN_STORAGE_TTL_MS = 15 * 60 * 1000;
  function novaGenStorageKey() {
    return 'dunes_nova_generating_' + String(convId || 0);
  }
  function persistNovaGenerating() {
    if (!convId) return;
    try {
      sessionStorage.setItem(novaGenStorageKey(), JSON.stringify({
        at: Date.now(),
        status: novaGenStatus || '正在生成…',
        after: novaGenAfterMsgId || 0
      }));
    } catch (e) {}
  }
  function clearPersistedNovaGenerating() {
    try { sessionStorage.removeItem(novaGenStorageKey()); } catch (e) {}
  }
  function loadPersistedNovaGenerating() {
    try {
      var raw = sessionStorage.getItem(novaGenStorageKey());
      if (!raw) return false;
      var o = JSON.parse(raw);
      if (!o || Date.now() - Number(o.at || 0) > NOVA_GEN_STORAGE_TTL_MS) {
        clearPersistedNovaGenerating();
        return false;
      }
      novaServerGenerating = true;
      novaGenStatus = o.status || '正在生成…';
      novaGenAfterMsgId = Number(o.after || 0);
      return true;
    } catch (e) {
      return false;
    }
  }
  function isUserOutboundMessage(m) {
    if (!m) return false;
    var uid = m.sender && m.sender.userId != null ? Number(m.sender.userId) : Number(m.senderUserId || 0);
    if (uid <= 0) return false;
    var kind = String(m.kind || '').toUpperCase();
    return kind === 'TEXT' || kind === 'IMAGE' || kind === 'FILE' || kind === 'AUDIO';
  }
  function inferAwaitingNovaReply(items) {
    if (!items || !items.length) return false;
    return isUserOutboundMessage(items[items.length - 1]);
  }
  var NOVA_WELCOME = '你好，我是你的 NOVA 助手。可以帮你查审批、找合同、对账单、读文档；展开上方推荐问题或直接问我。';
  var NOVA_INPUT_PLACEHOLDER = '问NOVA';
  var NOVA_INPUT_BUSY_PLACEHOLDER = 'NOVA 正在生成中，请稍候…';

  function isNovaInputLocked() {
    return !!(sending || novaServerGenerating || bgStreaming);
  }
  function syncNovaInputLock() {
    var screen = c4Screen();
    if (!screen) return;
    var locked = isNovaInputLocked();
    var input = document.getElementById('c4-input');
    var sendBtn = document.getElementById('c4-send');
    var voiceBtn = screen.querySelector('.msg-input-bar .voice-btn');
    var attachBtn = screen.querySelector('.msg-input-bar .emoji-btn');
    var qaBar = document.getElementById('c4-quick-actions');
    var inputBar = screen.querySelector('.msg-input-bar');
    screen.classList.toggle('nova-input-locked', locked);
    if (inputBar) inputBar.classList.toggle('nova-input-locked', locked);
    if (input) {
      input.readOnly = locked;
      input.placeholder = locked ? NOVA_INPUT_BUSY_PLACEHOLDER : NOVA_INPUT_PLACEHOLDER;
      input.setAttribute('aria-disabled', locked ? 'true' : 'false');
    }
    [sendBtn, voiceBtn, attachBtn].forEach(function (el) {
      if (!el) return;
      el.style.pointerEvents = locked ? 'none' : '';
      el.style.opacity = locked ? '0.45' : '';
      el.setAttribute('aria-disabled', locked ? 'true' : 'false');
    });
    if (qaBar) {
      qaBar.style.pointerEvents = locked ? 'none' : '';
      qaBar.style.opacity = locked ? '0.55' : '';
    }
    var hint = document.getElementById('c4-input-busy-hint');
    if (!hint && inputBar && inputBar.parentNode) {
      hint = document.createElement('div');
      hint.id = 'c4-input-busy-hint';
      hint.className = 'nova-input-busy-hint';
      inputBar.parentNode.insertBefore(hint, inputBar);
    }
    if (hint) {
      hint.textContent = locked ? String(novaGenStatus || 'NOVA 正在生成中，请稍候…') : '';
      hint.style.display = locked ? 'block' : 'none';
    }
  }
  function showNovaInputBusyHint() {
    syncNovaInputLock();
    var hint = document.getElementById('c4-input-busy-hint');
    if (hint) {
      hint.classList.add('nova-input-busy-flash');
      setTimeout(function () { if (hint) hint.classList.remove('nova-input-busy-flash'); }, 700);
    }
  }

  function activeIsC4() {
    return document.querySelector('.screen.active')?.dataset?.screen === 'C4';
  }
  function readC4Input() {
    var input = document.getElementById('c4-input');
    return input ? String(input.value || '').trim() : '';
  }
  function clearC4Input() {
    var input = document.getElementById('c4-input');
    if (input) input.value = '';
  }
  function submitC4Input() {
    if (!activeIsC4()) return;
    if (isNovaInputLocked()) { showNovaInputBusyHint(); return; }
    var t = readC4Input();
    if (!t) return;
    clearC4Input();
    sendMessage(t);
  }

  function apiBase() {
    return localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
  }
  function authHeaders(extra) {
    var h = Object.assign({}, extra || {});
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    if (token) h.Authorization = 'Bearer ' + token;
    return h;
  }
  function esc(s) {
    return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function novaAvHtml(avClass) {
    if (window.dunesNovaAvatarHtml) return window.dunesNovaAvatarHtml(avClass || 'msg-av-sm ai-bot');
    return '<div class="' + (avClass || 'msg-av-sm ai-bot') + '"><i class="ti ti-sparkles"></i></div>';
  }
  function novaIcHtml() {
    if (window.dunesNovaIconHtml) return window.dunesNovaIconHtml();
    return '<i class="ti ti-sparkles"></i>';
  }
  function selfName() {
    return localStorage.getItem('dunes_display_name') || '我';
  }
  function selfInitial() {
    var n = selfName();
    return n ? n.charAt(0) : '我';
  }
  function msgTimeLabel(at) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  }
  function msgCreatedAt(m) {
    return m && (m.createdAt || m.created_at) || '';
  }
  function cnWeekday(d) {
    return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][d.getDay()];
  }
  function dayKey(d) {
    return d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate();
  }
  function dayDividerLabel(at, prevAt) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    var prev = prevAt ? new Date(prevAt) : null;
    if (prev && !isNaN(prev.getTime()) && dayKey(d) === dayKey(prev)) return '';
    var now = new Date();
    var weekday = cnWeekday(d);
    if (dayKey(d) === dayKey(now)) return '今天 · ' + weekday;
    var yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (dayKey(d) === dayKey(yesterday)) return '昨天 · ' + weekday;
    var dayBefore = new Date(now);
    dayBefore.setDate(dayBefore.getDate() - 2);
    if (dayKey(d) === dayKey(dayBefore)) return '前天 · ' + weekday;
    var y = d.getFullYear();
    var m = d.getMonth() + 1;
    var day = d.getDate();
    if (y === now.getFullYear()) return m + '月' + day + '日 · ' + weekday;
    return y + '年' + m + '月' + day + '日 · ' + weekday;
  }
  function createDateDivider(label) {
    var div = document.createElement('div');
    div.className = 'msg-date-divider';
    div.textContent = label;
    return div;
  }
  function lastNovaMessageCreatedAt(box) {
    if (!box) return null;
    var i = box.children.length;
    while (i--) {
      var el = box.children[i];
      if (!el || el.classList.contains('msg-date-divider')) continue;
      if (el.id === 'dunes-nova-load-more-msgs') continue;
      var at = el.getAttribute('data-created-at');
      if (at) return at;
    }
    return null;
  }
  function ensureNovaLeadingDateDivider(box) {
    if (!box) return;
    var firstMsg = box.querySelector('[data-message-id]');
    if (!firstMsg) return;
    var at = firstMsg.getAttribute('data-created-at') || '';
    if (!at) return;
    var prev = firstMsg.previousElementSibling;
    if (prev && prev.classList.contains('msg-date-divider')) return;
    if (prev && prev.id === 'dunes-nova-load-more-msgs') {
      var prev2 = prev.previousElementSibling;
      if (prev2 && prev2.classList.contains('msg-date-divider')) return;
    }
    var label = dayDividerLabel(at, null);
    if (!label) return;
    box.insertBefore(createDateDivider(label), firstMsg);
  }
  function normalizeNovaMsg(m) {
    if (!m) return m;
    if (m.createdAt == null && m.created_at != null) m.createdAt = m.created_at;
    var p = m.payload;
    if (typeof p === 'string' && p) {
      try { m.payload = JSON.parse(p); } catch (e) { m.payload = null; }
    }
    return m;
  }
  function novaAttachmentObjectKey(payload) {
    payload = payload || {};
    var key = String(payload.objectKey || '').trim();
    if (key) return key;
    var url = String(payload.url || '').trim();
    if (url && !isPublicMediaUrl(url)) return url;
    return '';
  }
  async function resolveNovaAttachmentUrl(el) {
    var objectKey = el.getAttribute('data-object-key') || '';
    var url = el.getAttribute('data-url') || '';
    if (isPublicMediaUrl(url)) return url;
    if (isPublicMediaUrl(objectKey)) return objectKey;
    if (!objectKey) return url;
    try {
      var pr = await apiJson('/storage/presigned-get?bucket=im-attachments&objectKey=' + encodeURIComponent(objectKey));
      if (pr.success && pr.data && pr.data.url) {
        url = pr.data.url;
        el.setAttribute('data-url', url);
        return url;
      }
    } catch (e) {}
    return url;
  }
  function bindNovaImageLoadScroll(root) {
    if (!root) return;
    root.querySelectorAll('img.dunes-img-thumb, img[data-object-key]').forEach(function (img) {
      if (img.dataset.novaScrollWired) return;
      img.dataset.novaScrollWired = '1';
      img.addEventListener('load', function () {
        if (!novaSuppressAutoScroll && activeIsC4()) scrollC4();
      });
    });
  }
  async function hydrateNovaMediaUrls(root) {
    if (!root) return;
    var nodes = root.querySelectorAll('[data-object-key]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var key = el.getAttribute('data-object-key') || '';
      var direct = el.getAttribute('data-url') || '';
      if (isPublicMediaUrl(direct) || isPublicMediaUrl(key)) {
        var pub = isPublicMediaUrl(direct) ? direct : key;
        el.dataset.hydrated = '1';
        if (el.tagName === 'IMG') {
          el.src = pub;
          el.setAttribute('data-full-url', pub);
        }
        continue;
      }
      if (!key || el.dataset.hydrated === '1') continue;
      try {
        var url = await resolveNovaAttachmentUrl(el);
        if (!url) continue;
        el.dataset.hydrated = '1';
        if (el.tagName === 'IMG') {
          el.src = url;
          el.setAttribute('data-full-url', url);
        }
      } catch (e) {}
    }
    bindNovaImageLoadScroll(root);
  }
  async function presignedAccessUrl(objectKey) {
    if (!objectKey || isPublicMediaUrl(objectKey)) return objectKey || '';
    try {
      var pr = await apiJson('/storage/presigned-get?bucket=im-attachments&objectKey=' + encodeURIComponent(objectKey));
      if (pr.success && pr.data && pr.data.url) return pr.data.url;
    } catch (e) {}
    return '';
  }
  function apiJson(path, opts) {
    opts = opts || {};
    var headers = authHeaders(opts.headers || {});
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(apiBase() + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) { return r.json(); });
  }
  function rowsEl() {
    return document.getElementById('c4-api-rows');
  }
  function streamWrap() {
    return document.getElementById('c4-msg-stream');
  }
  function c4Screen() {
    return document.querySelector('.screen[data-screen="C4"]');
  }
  function setHasChat(on) {
    var s = c4Screen();
    if (s) s.classList.toggle('nova-has-chat', !!on);
  }
  function scrollC4() {
    if (novaSuppressAutoScroll || isNovaHistoryLocated()) return;
    var stream = streamWrap();
    if (!stream) return;
    function doScroll() {
      stream.scrollTop = stream.scrollHeight;
      var box = rowsEl();
      if (box && box.lastElementChild) {
        try {
          box.lastElementChild.scrollIntoView({ block: 'end', behavior: 'auto' });
        } catch (e) {
          box.lastElementChild.scrollIntoView(false);
        }
      }
    }
    requestAnimationFrame(function () {
      doScroll();
      requestAnimationFrame(doScroll);
    });
  }
  function observeNovaRowsScroll() {
    if (scrollObserved) return;
    var box = rowsEl();
    if (!box || typeof MutationObserver === 'undefined') return;
    scrollObserved = true;
    var mo = new MutationObserver(function () {
      if (novaSuppressAutoScroll || isNovaHistoryLocated()) return;
      scrollC4();
    });
    mo.observe(box, { childList: true, subtree: true, characterData: true });
  }
  function readStatusHtml(msgId) {
    var id = Number(msgId || 0);
    var lr = Number(novaPeerRead || 0);
    if (!id) return '';
    if (lr >= id) return '<div class="msg-read-status read">已读</div>';
    return '<div class="msg-read-status unread">未读</div>';
  }
  function applyNovaPeerRead(v) {
    var n = Number(v || 0);
    if (n > novaPeerRead) novaPeerRead = n;
    refreshNovaReadStatuses();
  }
  function refreshNovaReadStatuses() {
    var box = rowsEl();
    if (!box) return;
    box.querySelectorAll('.msg-row.sent[data-message-id]').forEach(function (row) {
      var old = row.querySelector('.msg-read-status');
      var html = readStatusHtml(row.dataset.messageId);
      if (!html) return;
      if (old) old.outerHTML = html;
      else {
        var content = row.querySelector('.msg-content');
        if (content) content.insertAdjacentHTML('beforeend', html);
      }
    });
  }
  function markNovaConversationRead() {
    if (!convId) return Promise.resolve();
    return apiJson('/conversations/' + convId + '/read', { method: 'POST' }).then(function (j) {
      if (window.DunesInbox && window.DunesInbox.patchConvUnread) {
        window.DunesInbox.patchConvUnread(convId, 0);
      }
      return j;
    }).catch(function () {});
  }
  function bumpNovaUnreadBackground() {
    if (!convId) return;
    if (window.DunesInbox && window.DunesInbox.patchConvUnread) {
      window.DunesInbox.patchConvUnread(convId, 1);
    }
    apiJson('/conversations').then(function (j) {
      if (!j.success || !window.DunesInbox || !window.DunesInbox.patchConvUnread) return;
      var c = (j.data || []).find(function (x) { return String(x.id) === String(convId); });
      if (c) window.DunesInbox.patchConvUnread(convId, c.unreadCount || 1);
    }).catch(function () {});
  }
  function clearNovaLiveRows() {
    var box = rowsEl();
    if (!box) return;
    box.querySelectorAll('.dunes-nova-live').forEach(function (row) {
      if (row.parentNode) row.parentNode.removeChild(row);
    });
  }
  function finishStreamUi(ui, attempt, text) {
    if (ui._novaNotReady && attempt < 2) {
      if (ui.row && ui.row.parentNode) ui.row.parentNode.removeChild(ui.row);
      sending = false;
      bgStreaming = false;
      return new Promise(function (resolve) {
        setTimeout(function () { resolve(sendMessage(text, attempt + 1)); }, 3000);
      });
    }
    finalizeNovaThinkingPanel(ui);
    if (ui.row) ui.row.classList.remove('dunes-nova-live');
    sending = false;
    bgStreaming = false;
    if (!novaServerGenerating) syncNovaInputLock();
    if (novaServerGenerating && activeIsC4()) {
      maybeShowServerGenerating({ force: true });
    }
    if (activeIsC4()) {
      scrollC4();
      return markNovaConversationRead();
    }
    clearNovaLiveRows();
    bumpNovaUnreadBackground();
    return Promise.resolve();
  }
  function isPublicMediaUrl(v) {
    return /^https?:\/\//i.test(String(v || '').trim());
  }
  function storageDownloadEndpoint(objectKey, bucket, fileName) {
    var base = apiBase();
    var q = 'bucket=' + encodeURIComponent(bucket || 'im-attachments') + '&objectKey=' + encodeURIComponent(objectKey);
    if (fileName) q += '&fileName=' + encodeURIComponent(fileName);
    return base + '/storage/download?' + q;
  }
  async function uploadViaPresigned(file) {
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var authH = token ? { Authorization: 'Bearer ' + token } : {};
    var form = new FormData();
    form.append('file', file, file.name || ('upload-' + Date.now()));
    form.append('bucket', 'im-attachments');
    if (convId) form.append('conversationId', String(convId));
    var proxy = await fetch(apiBase() + '/storage/upload', { method: 'POST', headers: authH, body: form }).then(function (r) { return r.json(); });
    if (proxy && proxy.success && proxy.data) {
      var key = proxy.data.objectKey || proxy.data.url || '';
      var url = proxy.data.url || key;
      if (url || key) return { url: url, objectKey: key || url };
    }
    throw new Error((proxy && proxy.message) || '上传失败');
  }
  function appendUserAttachmentBubble(kind, label, payload, msgId) {
    var box = rowsEl();
    if (!box) return null;
    var fake = {
      id: msgId || 0,
      kind: kind,
      bodyText: label,
      createdAt: new Date().toISOString(),
      sender: { userId: Number(localStorage.getItem('dunes_user_id') || '1'), displayName: selfName() },
      payload: payload || {}
    };
    var wrap = document.createElement('div');
    wrap.innerHTML = renderHistoryMessage(fake);
    var row = wrap.firstElementChild;
    if (!row) return null;
    row.classList.add('dunes-nova-live');
    if (msgId) {
      row.dataset.messageId = String(msgId);
      row.dataset.msgId = String(msgId);
    }
    box.appendChild(row);
    setHasChat(true);
    hydrateNovaMediaUrls(row);
    wireC4VoicePlay();
    scrollC4();
    return row;
  }
  function sendNovaAttachment(kind, label, payload, opts) {
    opts = opts || {};
    if (isNovaInputLocked()) {
      showNovaInputBusyHint();
      return Promise.resolve();
    }
    if (!convId) {
      return ensureSession().then(function () { return sendNovaAttachment(kind, label, payload, opts); });
    }
    payload = payload || {};
    var objectKey = novaAttachmentObjectKey(payload);
    if (!opts.skipBubble) appendUserAttachmentBubble(kind, label, payload);
    return presignedAccessUrl(objectKey).then(function (accessUrl) {
      if (accessUrl) payload.accessUrl = accessUrl;
      return sendMessage('', 0, { kind: kind, bodyText: label, payload: payload });
    });
  }
  function wireC4VoicePlay() {
    var box = rowsEl();
    if (!box || box.dataset.voiceWired) return;
    box.dataset.voiceWired = '1';
    box.addEventListener('click', async function (e) {
      var b = e.target.closest('.dunes-voice-bubble');
      if (!b) return;
      e.preventDefault();
      e.stopPropagation();
      var url = b.getAttribute('data-url') || '';
      var key = b.getAttribute('data-object-key') || '';
      if (!isPublicMediaUrl(url) && key) {
        try {
          var pr = await apiJson('/storage/presigned-get?bucket=im-attachments&objectKey=' + encodeURIComponent(key));
          if (pr.success && pr.data && pr.data.url) url = pr.data.url;
        } catch (err) {}
      }
      if (!url) { alert('无法播放该语音'); return; }
      if (!window.__dunesVoiceAudio) {
        window.__dunesVoiceAudio = new Audio();
        window.__dunesVoiceAudio.addEventListener('ended', function () {
          if (window.__dunesVoicePlaying) window.__dunesVoicePlaying.classList.remove('playing');
          window.__dunesVoicePlaying = null;
        });
      }
      if (window.__dunesVoicePlaying === b && !window.__dunesVoiceAudio.paused) {
        window.__dunesVoiceAudio.pause();
        b.classList.remove('playing');
        window.__dunesVoicePlaying = null;
        return;
      }
      window.__dunesVoiceAudio.src = url;
      window.__dunesVoicePlaying = b;
      b.classList.add('playing');
      try { await window.__dunesVoiceAudio.play(); } catch (err) { b.classList.remove('playing'); alert('播放失败'); }
    });
  }
  function ensureNovaHiddenInput(id, accept, capture) {
    var screen = c4Screen();
    if (!screen) return null;
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('input');
      el.type = 'file';
      el.id = id;
      el.accept = accept || 'image/*';
      el.style.cssText = 'position:fixed;left:-9999px;opacity:0;width:1px;height:1px';
      if (capture) el.setAttribute('capture', capture);
      screen.appendChild(el);
    }
    return el;
  }
  function wireC4MediaToolbar() {
    var screen = c4Screen();
    if (!screen || screen.dataset.novaMediaWired) return;
    screen.dataset.novaMediaWired = '1';
    var camInput = ensureNovaHiddenInput('c4-camera-slot', 'image/*', 'environment');
    var albumInput = ensureNovaHiddenInput('c4-album-slot', 'image/*', '');
    function handleNovaImageFile(f, labelPrefix) {
      if (!f) return;
      uploadViaPresigned(f).then(function (up) {
        var fileKey = up.objectKey || up.url;
        var fileUrl = up.url || fileKey;
        return sendNovaAttachment('IMAGE', labelPrefix + f.name, { url: fileUrl, objectKey: fileKey, previewUrl: fileUrl, mimeType: f.type || 'image/*', fileName: f.name });
      }).catch(function (err) { alert('上传失败：' + (err.message || err)); });
    }
    if (camInput && !camInput.dataset.wired) {
      camInput.dataset.wired = '1';
      camInput.addEventListener('change', function () {
        var f = camInput.files && camInput.files[0];
        camInput.value = '';
        if (!f) return;
        ensureSession().then(function () { handleNovaImageFile(f, '[拍照] '); });
      });
    }
    if (albumInput && !albumInput.dataset.wired) {
      albumInput.dataset.wired = '1';
      albumInput.addEventListener('change', function () {
        var f = albumInput.files && albumInput.files[0];
        albumInput.value = '';
        if (!f) return;
        ensureSession().then(function () { handleNovaImageFile(f, '[图片] '); });
      });
    }
    var fileInput = document.getElementById('c4-upload-slot');
    if (!fileInput) {
      fileInput = document.createElement('input');
      fileInput.type = 'file';
      fileInput.id = 'c4-upload-slot';
      fileInput.accept = '*/*';
      fileInput.style.cssText = 'position:fixed;left:-9999px;opacity:0;width:1px;height:1px';
      screen.appendChild(fileInput);
    }
    var attachBtn = screen.querySelector('.msg-input-bar .emoji-btn');
    if (attachBtn && !attachBtn.dataset.wired) {
      attachBtn.dataset.wired = '1';
      attachBtn.title = '发送文件';
      attachBtn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (isNovaInputLocked()) { showNovaInputBusyHint(); return; }
        ensureSession().then(function () { fileInput.click(); });
      });
    }
    if (!fileInput.dataset.wired) {
      fileInput.dataset.wired = '1';
      fileInput.addEventListener('change', function () {
        var f = fileInput.files && fileInput.files[0];
        fileInput.value = '';
        if (!f) return;
        uploadViaPresigned(f).then(function (up) {
          var fileKey = up.objectKey || up.url;
          var fileUrl = up.url || fileKey;
          var isImg = (f.type || '').indexOf('image/') === 0;
          if (isImg) {
            return sendNovaAttachment('IMAGE', '[图片] ' + f.name, { url: fileUrl, objectKey: fileKey, previewUrl: fileUrl, mimeType: f.type || 'image/*', fileName: f.name });
          }
          return sendNovaAttachment('FILE', f.name, { url: fileUrl, objectKey: fileKey, mimeType: f.type || 'application/octet-stream', fileName: f.name, size: f.size || 0 });
        }).catch(function (err) { alert('上传失败：' + (err.message || err)); });
      });
    }
    async function resampleAudioBuffer(audioBuffer, targetRate) {
      targetRate = targetRate || 16000;
      if (!audioBuffer || audioBuffer.sampleRate === targetRate) return audioBuffer;
      var Ctx = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      if (!Ctx) return audioBuffer;
      var frames = Math.max(1, Math.ceil(audioBuffer.duration * targetRate));
      var offline = new Ctx(1, frames, targetRate);
      var src = offline.createBufferSource();
      src.buffer = audioBuffer;
      src.connect(offline.destination);
      src.start(0);
      return offline.startRendering();
    }
    function audioBufferToWavBlob(audioBuffer) {
      var channels = audioBuffer.numberOfChannels;
      var sampleRate = audioBuffer.sampleRate;
      var samples = audioBuffer.getChannelData(0);
      if (channels > 1) {
        var mixed = new Float32Array(samples.length);
        for (var c = 0; c < channels; c++) {
          var ch = audioBuffer.getChannelData(c);
          for (var i = 0; i < samples.length; i++) mixed[i] = (mixed[i] || 0) + ch[i] / channels;
        }
        samples = mixed;
      }
      var bytesPerSample = 2;
      var blockAlign = bytesPerSample;
      var dataLen = samples.length * bytesPerSample;
      var buffer = new ArrayBuffer(44 + dataLen);
      var view = new DataView(buffer);
      function writeStr(off, str) { for (var j = 0; j < str.length; j++) view.setUint8(off + j, str.charCodeAt(j)); }
      writeStr(0, 'RIFF');
      view.setUint32(4, 36 + dataLen, true);
      writeStr(8, 'WAVE');
      writeStr(12, 'fmt ');
      view.setUint32(16, 16, true);
      view.setUint16(20, 1, true);
      view.setUint16(22, 1, true);
      view.setUint32(24, sampleRate, true);
      view.setUint32(28, sampleRate * blockAlign, true);
      view.setUint16(32, blockAlign, true);
      view.setUint16(34, 16, true);
      writeStr(36, 'data');
      view.setUint32(40, dataLen, true);
      var offset = 44;
      for (var k = 0; k < samples.length; k++, offset += 2) {
        var s = Math.max(-1, Math.min(1, samples[k]));
        view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
      }
      return new Blob([buffer], { type: 'audio/wav' });
    }
    async function novaVoiceUploadBlob(blob, recMime) {
      var mime = String(recMime || blob.type || '');
      if (/wav|mpeg|mp3/i.test(mime)) {
        var ext0 = /wav/i.test(mime) ? 'wav' : 'mp3';
        return { blob: blob, mimeType: mime, fileName: 'voice-' + Date.now() + '.' + ext0 };
      }
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) throw new Error('当前环境无法转换语音格式');
      var ctx = new Ctx();
      try {
        var raw = await blob.arrayBuffer();
        var audioBuffer = await ctx.decodeAudioData(raw.slice(0));
        audioBuffer = await resampleAudioBuffer(audioBuffer, 16000);
        var wavBlob = audioBufferToWavBlob(audioBuffer);
        return { blob: wavBlob, mimeType: 'audio/wav', fileName: 'voice-' + Date.now() + '.wav' };
      } finally {
        try { ctx.close(); } catch (_) {}
      }
    }
    if (typeof window.__dunesWireHoldToTalkVoice === 'function') {
      window.__dunesWireHoldToTalkVoice({
        screen: screen,
        prefix: 'c4',
        textInput: document.getElementById('c4-input'),
        canRecord: function () { return !isNovaInputLocked(); },
        onBlocked: showNovaInputBusyHint,
        beforeRecord: ensureSession,
        onVoiceBlob: async function (blob, recMime, sec) {
          var localUrl = URL.createObjectURL(blob);
          appendUserAttachmentBubble('AUDIO', '[语音] ' + sec + 's', { url: localUrl, durationSec: sec, pending: true });
          scrollC4();
          var prepared = await novaVoiceUploadBlob(blob, recMime);
          var uploadBlob = prepared.blob;
          var uploadMime = prepared.mimeType;
          var fileName = prepared.fileName;
          var voiceFile;
          try { voiceFile = new File([uploadBlob], fileName, { type: uploadMime }); } catch (_) { voiceFile = uploadBlob; voiceFile.name = fileName; }
          var up = await uploadViaPresigned(voiceFile);
          var fileKey = up.objectKey || up.url;
          var fileUrl = up.url || fileKey;
          await sendNovaAttachment('AUDIO', '[语音] ' + sec + 's', { url: fileUrl, objectKey: fileKey, mimeType: uploadMime, durationSec: sec, fileName: fileName, size: uploadBlob.size }, { skipBubble: true });
        }
      });
    }
    wireC4VoicePlay();
  }
  function mdLite(text) {
    var s = esc(text || '');
    s = s.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
    s = s.replace(/\n/g, '<br>');
    return s;
  }
  function normalizeNovaBodyText(text) {
    return String(text || '').replace(/<br\s*\/?>/gi, '\n').trim();
  }
  function sanitizeNovaBody(text) {
    var s = normalizeNovaBodyText(text);
    s = s.replace(/^助手\s*[·•]\s*/u, '');
    s = s.replace(/^助手\s+/u, '');
    return s.trim();
  }
  var HERMES_THINK_LINE_RE = /^💭\s*\*\*思考中\*\*/;
  var HERMES_TOOL_LINE_RE = /^🔧\s*\*\*调用工具\*\*/;
  var HERMES_DONE_LINE_RE = /^✓\s*\S+\s*完成/;
  var NOVA_REASONING_HEAD_RE = /^推理过程\s*[:：]/;
  var NOVA_REASONING_SEP_RE = /^-{3,}\s*$/;
  /** Hermes 豆包式进度（见 New API §7.2.1，在 delta.content 内） */
  function stripHermesProgressLines(text) {
    return stripNovaReasoningBlock(String(text || '')
      .replace(/💭\s*\*\*思考中\*\*[^\n]*/g, '')
      .replace(/🔧\s*\*\*调用工具\*\*[^\n]*/g, '')
      .replace(/✓\s*\S+\s*完成/g, '')
      .trim());
  }
  function trimNovaReasoningHeader(text) {
    return String(text || '')
      .replace(/^\*{0,2}推理过程\*{0,2}\s*[:：]\s*/, '')
      .replace(/^推理过程\s*[:：]\s*/, '')
      .trim();
  }
  function splitNovaReasoningReply(raw, final) {
    raw = String(raw || '');
    if (!raw || raw.indexOf('推理过程') < 0) {
      return { thinking: '', reply: raw };
    }
    var lines = raw.split('\n');
    var sepIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (NOVA_REASONING_SEP_RE.test(String(lines[i] || '').trim())) {
        sepIdx = i;
        break;
      }
    }
    if (sepIdx >= 0) {
      var thinkLines = lines.slice(0, sepIdx);
      var replyLines = lines.slice(sepIdx + 1);
      return {
        thinking: trimNovaReasoningHeader(thinkLines.join('\n').trim()),
        reply: replyLines.join('\n').trim()
      };
    }
    if (final || NOVA_REASONING_HEAD_RE.test(raw.trim()) || /^推理过程/.test(raw.trim())) {
      return { thinking: trimNovaReasoningHeader(raw.trim()), reply: '' };
    }
    return { thinking: '', reply: raw };
  }
  function stripNovaReasoningBlock(text) {
    text = String(text || '');
    if (text.indexOf('推理过程') < 0) return text;
    var split = splitNovaReasoningReply(text, true);
    if (split.reply) return split.reply;
    var m = text.match(/推理过程\s*[:：][\s\S]*?\n-{3,}\s*\n?([\s\S]+)/);
    if (m && m[1]) return m[1].trim();
    return text;
  }
  function stripHermesThinkingHeader(text) {
    return String(text || '')
      .replace(/^💭\s*\*\*思考中\*\*\s*/, '')
      .replace(/^[….…]+\s*/, '')
      .trim();
  }
  function hermesProgressStatus(text) {
    var t = String(text || '');
    var tools = t.match(/🔧\s*\*\*调用工具\*\*\s*([^\n…]+)/g);
    if (tools && tools.length) {
      var last = tools[tools.length - 1].replace(/🔧\s*\*\*调用工具\*\*\s*/, '').trim();
      return { text: '调用工具 ' + last + '…' };
    }
    var done = t.match(/✓\s*(\S+)\s*完成/g);
    if (done && done.length) return { text: done[done.length - 1] };
    if (/💭\s*\*\*思考中\*\*/.test(t)) return { text: '思考中…' };
    return null;
  }
  function splitNovaStreamText(raw, final) {
    raw = String(raw || '');
    if (!raw) return { thinking: '', reply: '' };
    var buf = raw;
    var pending = '';
    if (!final) {
      var idx = raw.lastIndexOf('\n');
      if (idx >= 0 && idx < raw.length - 1) {
        pending = raw.slice(idx + 1);
        buf = raw.slice(0, idx + 1);
      } else if (idx < 0 && /^[💭🔧✓]/.test(raw) && raw.length < 28) {
        return { thinking: '', reply: '', pending: raw };
      }
    }
    var lines = buf.split('\n');
    if (pending) lines.push(pending);
    var thinking = [];
    var reply = [];
    var mode = 'reply';
    lines.forEach(function (line) {
      var trimmed = line.trim();
      if (!trimmed) return;
      if (HERMES_THINK_LINE_RE.test(trimmed)) {
        mode = 'thinking';
        var body = stripHermesThinkingHeader(trimmed);
        if (body) thinking.push(body);
        return;
      }
      if (HERMES_TOOL_LINE_RE.test(trimmed) || HERMES_DONE_LINE_RE.test(trimmed)) {
        mode = 'tool';
        return;
      }
      if (mode === 'thinking') {
        thinking.push(line);
        return;
      }
      if (mode === 'tool') {
        mode = 'reply';
      }
      reply.push(line);
      mode = 'reply';
    });
    return { thinking: thinking.join('\n').trim(), reply: reply.join('\n').trim() };
  }
  function novaStreamReplyText(ui, final) {
    var raw = ui.text || '';
    var nova = splitNovaReasoningReply(raw, !!final);
    var parts = splitNovaStreamText(nova.reply || '', !!final);
    var thinking = [nova.thinking, parts.thinking].filter(function (x) { return x && x.trim(); }).join('\n\n').trim();
    if (thinking) ui.thinkStream = thinking;
    return stripHermesProgressLines(sanitizeNovaBody(parts.reply || ''));
  }
  function novaFinalReplyText(ui) {
    return novaStreamReplyText(ui, true);
  }
  function setNovaThinkStatus(ui, text) {
    if (!ui || !ui.thinkStatus) return;
    ui.thinkStatus.textContent = text || '思考中…';
  }
  function renderNovaToolSteps(ui) {
    if (!ui || !ui.toolStepsWrap) return;
    var keys = Object.keys(ui.tools || {});
    if (!keys.length) {
      ui.toolStepsWrap.innerHTML = '';
      return;
    }
    ui.toolStepsWrap.innerHTML = keys.map(function (k) {
      var t = ui.tools[k];
      var done = t.status === 'done';
      return '<div class="nova-tool-step' + (done ? ' done' : ' pending') + '">'
        + '<i class="ti ti-' + (done ? 'check' : 'loader ti-spin') + '"></i>'
        + '<span>' + esc(toolLabel(t.name, t.request)) + '</span></div>';
    }).join('');
  }
  function showNovaThinkPanel(ui, statusText) {
    if (!ui || !ui.thinkPanel) return;
    ui.thinkPanel.style.display = 'block';
    ui.thinkPanel.classList.remove('collapsed');
    if (statusText) setNovaThinkStatus(ui, statusText);
  }
  function renderNovaThinkBody(ui) {
    if (!ui || !ui.thinkBody) return;
    var body = String(ui.thinkStream || '').trim();
    if (!body) {
      ui.thinkBody.innerHTML = '';
      return;
    }
    showNovaThinkPanel(ui, '深度思考中…');
    ui.thinkBody.innerHTML = mdLite(body);
  }
  function wireNovaThinkToggle(ui) {
    if (!ui || !ui.thinkToggle || ui.thinkToggle.dataset.wired) return;
    ui.thinkToggle.dataset.wired = '1';
    ui.thinkToggle.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (!ui.thinkPanel) return;
      ui.thinkPanel.classList.toggle('collapsed');
    });
  }
  function syncNovaStreamThinking(ui) {
    if (!ui || !ui.thinkPanel) return;
    var st = hermesProgressStatus(ui.text);
    var reply = novaStreamReplyText(ui, false);
    var hasThink = !!(ui.thinkStream && ui.thinkStream.trim());
    var hasTools = Object.keys(ui.tools || {}).length > 0;
    if (hasThink) renderNovaThinkBody(ui);
    if (hasTools) renderNovaToolSteps(ui);
    if (hasThink || hasTools) showNovaThinkPanel(ui, hasThink ? '深度思考中…' : (st ? st.text : '处理中…'));
    if (reply.length > 0) {
      stopNovaStreamWaitHint(ui);
      if (hasThink || hasTools) {
        setNovaThinkStatus(ui, '已完成思考');
        ui.thinkPanel.classList.add('collapsed');
      }
      return;
    }
    if (st || ui._novaStreaming) {
      showNovaThinkPanel(ui, st ? st.text : (ui._waitHint || '正在生成…'));
      return;
    }
    if (!hasThink && !hasTools) ui.thinkPanel.style.display = 'none';
  }
  function startNovaStreamWaitHint(ui) {
    if (!ui || ui._waitTimer) return;
    ui._streamStart = Date.now();
    ui._waitHint = '正在生成…';
    ui._waitTimer = setInterval(function () {
      if (!ui._novaStreaming) {
        clearInterval(ui._waitTimer);
        ui._waitTimer = null;
        return;
      }
      var hasThink = !!(ui.thinkStream && ui.thinkStream.trim());
      var hasTools = Object.keys(ui.tools || {}).length > 0;
      var reply = novaStreamReplyText(ui, false);
      if (hasThink || hasTools || reply.length > 0) {
        clearInterval(ui._waitTimer);
        ui._waitTimer = null;
        return;
      }
      var sec = Math.max(1, Math.floor((Date.now() - (ui._streamStart || Date.now())) / 1000));
      ui._waitHint = '正在生成…（已等待 ' + sec + ' 秒，复杂问题可能需要 30–60 秒）';
      setNovaThinkStatus(ui, ui._waitHint);
    }, 1000);
  }
  function stopNovaStreamWaitHint(ui) {
    if (!ui || !ui._waitTimer) return;
    clearInterval(ui._waitTimer);
    ui._waitTimer = null;
  }
  function paintNovaStreamText(ui, final) {
    if (!ui || !ui.textEl) return;
    var reply = novaStreamReplyText(ui, !!final);
    renderNovaThinkBody(ui);
    if (reply) {
      if (novaBodyNeedsRichRender(reply)) ui.textEl.innerHTML = renderNovaBodyHtml(reply);
      else ui.textEl.innerHTML = mdLite(reply);
      stopNovaStreamWaitHint(ui);
    } else if (final) {
      ui.textEl.innerHTML = '';
    }
    syncNovaStreamThinking(ui);
    scrollC4();
  }
  function finalizeNovaThinkingPanel(ui) {
    if (!ui || !ui.thinkPanel) return;
    stopNovaStreamWaitHint(ui);
    paintNovaStreamText(ui, true);
    var finalReply = novaFinalReplyText(ui);
    if (finalReply) {
      ui.thinkPanel.style.display = 'none';
    } else {
      var hasThink = !!(ui.thinkStream && ui.thinkStream.trim());
      var hasTools = Object.keys(ui.tools || {}).length > 0;
      if (hasThink || hasTools) {
        if (hasThink) renderNovaThinkBody(ui);
        if (hasTools) renderNovaToolSteps(ui);
        showNovaThinkPanel(ui, '已完成思考');
        ui.thinkPanel.classList.add('collapsed');
      } else {
        ui.thinkPanel.style.display = 'none';
      }
    }
    ui._novaStreaming = false;
  }
  function extractUrlFromMarkdownLink(link) {
    var m = String(link || '').match(/\((https?:[^)\s]+)\)/);
    return m ? m[1] : '';
  }
  function extractNameFromMarkdownLink(link) {
    var m = String(link || '').match(/^\[([^\]]+)\]/);
    return m ? m[1] : '';
  }
  function fileExt(name) {
    var n = String(name || '');
    var path = n.split('?')[0];
    var i = path.lastIndexOf('.');
    return i >= 0 ? path.slice(i + 1).toLowerCase() : '';
  }
  function isImageExt(ext) {
    return /^(jpe?g|png|gif|webp|svg|bmp)$/i.test(String(ext || ''));
  }
  function isImageFile(file) {
    if (!file || !file.url) return false;
    return isImageExt(file.ext) || isImageExt(fileExt(file.url));
  }
  function fileIconClass(ext) {
    if (ext === 'html' || ext === 'htm') return 'ti-file-type-html';
    if (ext === 'pdf') return 'ti-file-type-pdf';
    if (ext === 'doc' || ext === 'docx') return 'ti-file-type-doc';
    if (ext === 'xls' || ext === 'xlsx') return 'ti-file-type-xls';
    if (ext === 'zip' || ext === 'rar' || ext === '7z') return 'ti-file-zip';
    if (ext === 'md' || ext === 'txt') return 'ti-file-text';
    if (isImageExt(ext)) return 'ti-photo';
    return 'ti-file';
  }
  function tryParseHermesFileJson(text) {
    var raw = normalizeNovaBodyText(text);
    if (!raw) return null;
    function fromObj(o) {
      if (!o || typeof o !== 'object') return null;
      var url = String(o.download_url || o.downloadUrl || '').trim();
      if (!url) url = extractUrlFromMarkdownLink(o.chat_link || o.chatLink || '');
      var name = String(o.display_filename || o.displayFilename || '').trim();
      if (!name) name = extractNameFromMarkdownLink(o.chat_link || o.chatLink || '');
      if (!url && !name) return null;
      if (!name && url) {
        try { name = decodeURIComponent(url.split('/').pop().split('?')[0]); } catch (e) { name = '文件'; }
      }
      return { url: url, name: name || '文件', ext: fileExt(name) };
    }
    try {
      var direct = fromObj(JSON.parse(raw));
      if (direct && direct.url) return direct;
    } catch (e1) {}
    var block = raw.match(/\{[\s\S]*"(?:download_url|chat_link|display_filename)"[\s\S]*\}/);
    if (block) {
      try {
        var inner = fromObj(JSON.parse(block[0]));
        if (inner && inner.url) return inner;
      } catch (e2) {}
    }
    return null;
  }
  function tryParseMarkdownFileLink(text) {
    var raw = normalizeNovaBodyText(text);
    var m = raw.match(/^\[([^\]]+)\]\((https?:[^)\s]+)\)\s*$/);
    if (!m) return null;
    return { url: m[2], name: m[1], ext: fileExt(m[1]) || fileExt(m[2]) };
  }
  function novaBodyNeedsRichRender(text) {
    var raw = sanitizeNovaBody(text || '');
    if (!raw) return false;
    if (tryParseHermesFileJson(raw) || tryParseMarkdownFileLink(raw)) return true;
    if (/\{[\s\S]*"(?:download_url|chat_link|display_filename)"/.test(raw)) return true;
    if (/\[[^\]]+\]\(https?:/i.test(raw)) return true;
    if (/\(https?:\/\/[^)\s]+\.(?:jpe?g|png|gif|webp)/i.test(raw)) return true;
    return false;
  }
  function renderNovaImageCard(file) {
    if (!file || !file.url) return '';
    var name = file.name || '图片';
    return ''
      + '<div class="dunes-nova-image-card tappable" role="button" tabindex="0"'
      + ' data-url="' + esc(file.url) + '" data-filename="' + esc(name) + '">'
      + '<img class="dunes-img-thumb dunes-nova-img-preview" src="' + esc(file.url) + '"'
      + ' data-full-url="' + esc(file.url) + '" alt="' + esc(name) + '" loading="lazy">'
      + '<div class="dni-foot"><span class="dni-name">' + esc(name) + '</span>'
      + '<span class="dni-hint">点击查看大图</span></div></div>';
  }
  function renderNovaFileCard(file) {
    if (!file || !file.url) return '';
    var ext = file.ext || fileExt(file.name);
    var icon = fileIconClass(ext);
    return ''
      + '<div class="dunes-nova-file-card tappable" role="button" tabindex="0"'
      + ' data-url="' + esc(file.url) + '" data-filename="' + esc(file.name) + '">'
      + '<div class="dnf-icon"><i class="ti ' + icon + '"></i></div>'
      + '<div class="dnf-bd"><div class="dnf-name">' + esc(file.name) + '</div>'
      + '<div class="dnf-meta">点击打开文件</div></div>'
      + '<div class="dnf-go"><i class="ti ti-chevron-right"></i></div></div>';
  }
  function renderNovaDeliverableCard(file) {
    if (isImageFile(file)) return renderNovaImageCard(file);
    return renderNovaFileCard(file);
  }
  function renderNovaBodyHtml(body) {
    var split = splitNovaReasoningReply(body, true);
    var raw = stripHermesProgressLines(sanitizeNovaBody(split.reply || body));
    raw = String(raw || '').replace(/\]\s*\n+\s*\(/g, '](');
    if (!raw) return '';
    var file = tryParseHermesFileJson(raw) || tryParseMarkdownFileLink(raw);
    var rest = '';
    if (!file) {
      var block = raw.match(/\{[\s\S]*"(?:download_url|chat_link|display_filename)"[\s\S]*\}/);
      if (block) {
        file = tryParseHermesFileJson(block[0]);
        rest = raw.replace(block[0], '').trim();
      }
    }
    if (file && file.url) {
      if (!file.ext) file.ext = fileExt(file.name) || fileExt(file.url);
      var card = renderNovaDeliverableCard(file);
      if (!rest) return card;
      return renderNovaBodyHtml(rest) + card;
    }
    var linkRe = /\[([^\]]+)\]\((https?:[^)\s]+)\)/gi;
    var html = '';
    var last = 0;
    var m;
    var hit = false;
    while ((m = linkRe.exec(raw)) !== null) {
      hit = true;
      if (m.index > last) html += mdLite(raw.slice(last, m.index));
      var item = { url: m[2], name: m[1], ext: fileExt(m[1]) || fileExt(m[2]) };
      html += renderNovaDeliverableCard(item);
      last = linkRe.lastIndex;
    }
    if (hit) {
      if (last < raw.length) html += mdLite(raw.slice(last));
      return html;
    }
    var bareRe = /\((https?:\/\/[^)\s]+\.(?:jpe?g|png|gif|webp|svg)(?:\?[^)\s]*)?)\)/gi;
    last = 0;
    hit = false;
    html = '';
    while ((m = bareRe.exec(raw)) !== null) {
      hit = true;
      if (m.index > last) html += mdLite(raw.slice(last, m.index));
      var u = m[1];
      var nm = '';
      try { nm = decodeURIComponent(u.split('/').pop().split('?')[0]); } catch (e2) { nm = '图片'; }
      html += renderNovaImageCard({ url: u, name: nm, ext: fileExt(u) });
      last = bareRe.lastIndex;
    }
    if (hit) {
      if (last < raw.length) html += mdLite(raw.slice(last));
      return html;
    }
    return mdLite(raw);
  }
  function openNovaImageUrl(url) {
    if (!url) return;
    if (typeof window.__dunesOpenImageViewer === 'function') {
      window.__dunesOpenImageViewer(url);
      return;
    }
    window.open(url, '_blank', 'noopener');
  }
  function toolLabel(name, req) {
    if (name === 'get_inbox') return 'GET /workbench/inbox';
    if (name === 'get_payments_no_invoice') return 'GET /payments?noInvoice=true';
    if (name === 'search_business') {
      var q = (req && req.q) ? String(req.q) : '';
      return 'search(' + q + ')';
    }
    if (name === 'search_kb') return 'search_kb';
    return String(name || 'tool');
  }
  function toolClass(name) {
    if (name === 'search_business' || name === 'search_kb') return ' blue';
    if (name === 'get_payments_no_invoice') return ' amber';
    return '';
  }
  function renderToolChip(name, req, status) {
    var done = status === 'done';
    return '<span class="ai-tool-call nova-tool-chip' + toolClass(name) + (done ? '' : ' pending') + '" data-tool="' + esc(name) + '">'
      + '<i class="ti ti-' + (name.indexOf('search') >= 0 ? 'search' : 'tool') + '"></i>'
      + esc(toolLabel(name, req))
      + (done ? '<i class="ti ti-check check"></i>' : '<i class="ti ti-loader ti-spin"></i>')
      + '</span>';
  }
  function renderToolsHtml(tools) {
    if (!tools || !tools.length) return '';
    var html = '<div style="margin-bottom:6px;display:flex;flex-wrap:wrap;gap:2px">';
    tools.forEach(function (t) {
      html += renderToolChip(t.name, t.request, t.status || 'done');
    });
    html += '</div>';
    return html;
  }
  function renderCitationsHtml(citations) {
    if (!citations || !citations.length) return '';
    return citations.map(function (c) {
      return '<span class="ai-citation" title="' + esc(c.title || '') + '">' + esc(c.ref || '') + '</span>';
    }).join(' ');
  }
  function parsePayload(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try { return JSON.parse(raw); } catch (e) { return {}; }
  }
  function renderHistoryMessage(m) {
    var kind = String(m.kind || '').toUpperCase();
    var sender = m.sender || {};
    var uid = sender.userId != null ? Number(sender.userId) : null;
    var isUser = uid != null && uid > 0;
    var isAi = kind === 'AI_ASSISTANT' || kind === 'AI_TOOL_CALL' || (!isUser && (sender.displayName === 'NOVA' || uid === 0));
    var payload = parsePayload(m.payload);
    var tools = payload.tools || [];
    var citations = payload.citations || [];
    var body = m.bodyText || m.content || '';
    var at = msgCreatedAt(m);
    var time = msgTimeLabel(at);
    var createdAttr = ' data-created-at="' + esc(at) + '"';
    if (isUser && kind === 'IMAGE' && payload && (payload.url || payload.objectKey)) {
      var mediaKey = novaAttachmentObjectKey(payload);
      var mediaUrl = payload.url || mediaKey || '';
      var src = isPublicMediaUrl(mediaUrl) ? esc(mediaUrl) : '';
      return ''
        + '<div class="msg-row sent" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + '<div class="msg-av-sm person-e">' + esc(selfInitial()) + '</div>'
        + '<div class="msg-content"><div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent"><img src="' + src + '" class="dunes-img-thumb" data-url="' + esc(mediaUrl) + '" data-object-key="' + esc(mediaKey) + '" data-bucket="im-attachments" data-full-url="' + esc(mediaUrl) + '" style="max-width:170px;border-radius:10px;display:block;cursor:pointer"></div>'
        + readStatusHtml(m.id) + '</div></div>';
    }
    if (isUser && kind === 'AUDIO') {
      var sec = Math.max(1, Number((payload && payload.durationSec) || String(body).replace(/\D/g, '') || 1));
      var audioKey = novaAttachmentObjectKey(payload);
      var audioUrl = payload && (payload.url || audioKey) || '';
      return ''
        + '<div class="msg-row sent" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + '<div class="msg-av-sm person-e">' + esc(selfInitial()) + '</div>'
        + '<div class="msg-content"><div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent dunes-voice-bubble" data-url="' + esc(audioUrl) + '" data-object-key="' + esc(audioKey) + '" data-bucket="im-attachments">'
        + '<span class="voice-sec">' + sec + '\'</span><span class="voice-wave"><i class="ti ti-volume"></i></span></div>'
        + readStatusHtml(m.id) + '</div></div>';
    }
    if (isUser && kind === 'FILE' && payload && (payload.url || payload.objectKey)) {
      var fileKey = novaAttachmentObjectKey(payload);
      var fileUrl = payload.url || fileKey || '';
      var href = isPublicMediaUrl(fileUrl) ? esc(fileUrl) : storageDownloadEndpoint(fileKey || fileUrl, 'im-attachments', payload.fileName || body);
      return ''
        + '<div class="msg-row sent" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + '<div class="msg-av-sm person-e">' + esc(selfInitial()) + '</div>'
        + '<div class="msg-content"><div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent"><i class="ti ti-paperclip"></i> <a class="dunes-attach-link dunes-nova-file-link" href="' + href + '" data-url="' + esc(fileUrl) + '" data-object-key="' + esc(fileKey) + '" data-bucket="im-attachments" data-file-name="' + esc(payload.fileName || body) + '" target="_blank" rel="noopener">' + esc(body) + '</a></div>'
        + readStatusHtml(m.id) + '</div></div>';
    }
    if (isUser && kind === 'TEXT') {
      return ''
        + '<div class="msg-row sent" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + '<div class="msg-av-sm person-e">' + esc(selfInitial()) + '</div>'
        + '<div class="msg-content">'
        + '<div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent">' + esc(body) + '</div>'
        + readStatusHtml(m.id)
        + '</div></div>';
    }
    if (isAi || kind.indexOf('AI') >= 0) {
      return ''
        + '<div class="msg-row recv" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + novaAvHtml('msg-av-sm ai-bot')
        + '<div class="msg-content">'
        + '<div class="msg-meta"><span class="nm">NOVA</span>'
        + '<span class="badge-ai">AI</span>'
        + (time ? '<span>' + esc(time) + '</span>' : '')
        + '</div>'
        + '<div class="msg-bubble ai-recv">'
        + renderNovaBodyHtml(body)
        + (citations.length ? ' ' + renderCitationsHtml(citations) : '')
        + '</div></div></div>';
    }
    return '';
  }
  function clearApiRows() {
    var box = rowsEl();
    if (box) box.innerHTML = '';
  }
  function showWelcome() {
    var box = rowsEl();
    if (!box) return;
    box.innerHTML = ''
      + '<div class="msg-row recv dunes-nova-welcome">'
      + novaAvHtml('msg-av-sm ai-bot')
      + '<div class="msg-content">'
      + '<div class="msg-meta"><span class="nm">NOVA</span>'
      + '<span class="badge-ai">AI</span></div>'
      + '<div class="msg-bubble ai-recv">' + esc(NOVA_WELCOME) + '</div>'
      + '</div></div>';
    setHasChat(false);
  }
  function applyNovaPeerFromPayload(j, items) {
    if (j.data && j.data.peerLastReadMessageId != null) {
      novaPeerRead = Number(j.data.peerLastReadMessageId) || 0;
      return;
    }
    var maxAi = 0;
    (items || []).forEach(function (m) {
      var k = String(m.kind || '').toUpperCase();
      if (k === 'AI_ASSISTANT' || k === 'AI_TOOL_CALL') {
        var id = Number(m.id || 0);
        if (id > maxAi) maxAi = id;
      }
    });
    if (maxAi > novaPeerRead) novaPeerRead = maxAi;
  }
  function hasAiReplyAfter(items, afterMsgId) {
    if (!afterMsgId) return false;
    var seen = false;
    for (var i = 0; i < (items || []).length; i++) {
      var m = items[i];
      var id = Number(m.id || 0);
      if (id === afterMsgId) seen = true;
      else if (seen) {
        var k = String(m.kind || '').toUpperCase();
        if (k === 'AI_ASSISTANT' || k === 'AI_TOOL_CALL') return true;
      }
    }
    return false;
  }
  function syncInboxNovaGenerating(previewText) {
    if (!convId || !window.DunesInbox || !window.DunesInbox.patchNovaGeneratingPreview) return;
    if (novaServerGenerating) {
      window.DunesInbox.patchNovaGeneratingPreview(convId, true, novaGenStatus);
      return;
    }
    window.DunesInbox.patchNovaGeneratingPreview(convId, false, '', previewText != null ? previewText : undefined);
  }
  function applyNovaGeneratingState(j, items) {
    var d = (j && j.success !== false && j.data) ? j.data : {};
    novaServerGenerating = !!d.assistantGenerating;
    novaGenAfterMsgId = Number(d.assistantGeneratingAfterMessageId || 0);
    novaGenStatus = String(d.assistantGeneratingStatus || '正在生成…');
    if (novaServerGenerating && hasAiReplyAfter(items, novaGenAfterMsgId)) {
      novaServerGenerating = false;
      clearPersistedNovaGenerating();
      syncInboxNovaGenerating(lastNovaPreviewFromItems(items));
      return;
    }
    if (!novaServerGenerating && loadPersistedNovaGenerating()) {
      if (hasAiReplyAfter(items, novaGenAfterMsgId)) {
        novaServerGenerating = false;
        clearPersistedNovaGenerating();
        syncInboxNovaGenerating(lastNovaPreviewFromItems(items));
        return;
      }
    }
    if (!novaServerGenerating && inferAwaitingNovaReply(items)) {
      loadPersistedNovaGenerating();
    }
    if (novaServerGenerating) persistNovaGenerating();
    else clearPersistedNovaGenerating();
    syncInboxNovaGenerating(novaServerGenerating ? null : lastNovaPreviewFromItems(items));
    syncNovaInputLock();
  }
  function lastNovaPreviewFromItems(items) {
    if (!items || !items.length) return '';
    for (var i = items.length - 1; i >= 0; i--) {
      var m = items[i];
      if (!m) continue;
      var kind = String(m.kind || '').toUpperCase();
      if (kind.indexOf('AI') >= 0 || (m.sender && (!m.sender.userId || m.sender.displayName === 'NOVA'))) {
        return stripHermesProgressLines(sanitizeNovaBody(String(m.bodyText || '')));
      }
    }
    return '';
  }
  function refreshNovaGeneratingStatus() {
    if (!convId) return Promise.resolve();
    return apiJson('/ai/assistant/status?conversationId=' + convId).then(function (j) {
      var d = (j && j.success !== false && j.data) ? j.data : {};
      if (d.assistantGenerating) {
        novaServerGenerating = true;
        novaGenAfterMsgId = Number(d.assistantGeneratingAfterMessageId || 0);
        novaGenStatus = String(d.assistantGeneratingStatus || '正在生成…');
        persistNovaGenerating();
        syncInboxNovaGenerating();
        syncNovaInputLock();
      }
    }).catch(function () {});
  }
  function removeNovaServerPendingRow() {
    var box = rowsEl();
    if (!box) return;
    box.querySelectorAll('.dunes-nova-server-pending').forEach(function (row) {
      if (row.parentNode) row.parentNode.removeChild(row);
    });
  }
  function stopNovaGeneratingPoll() {
    if (novaGenPollTimer) {
      clearInterval(novaGenPollTimer);
      novaGenPollTimer = null;
    }
  }
  function maybeShowServerGenerating(opts) {
    opts = opts || {};
    if (!novaServerGenerating) return;
    syncInboxNovaGenerating();
    if (!opts.force && (sending || bgStreaming)) return;
    var box = rowsEl();
    if (!box) return;
    if (box.querySelector('.dunes-nova-server-pending')) {
      var existing = box.querySelector('.dunes-nova-server-pending .nova-think-status');
      if (existing) existing.textContent = novaGenStatus || '正在生成…';
      startNovaGeneratingPoll();
      return;
    }
    var ui = createAiStreamRow();
    ui.row.classList.add('dunes-nova-server-pending', 'dunes-nova-live');
    showNovaThinkPanel(ui, novaGenStatus || '正在生成…');
    scrollC4();
    startNovaGeneratingPoll();
    syncNovaInputLock();
  }
  function startNovaGeneratingPoll() {
    if (novaGenPollTimer || !convId) return;
    novaGenPollTimer = setInterval(function () {
      if (!convId) {
        stopNovaGeneratingPoll();
        return;
      }
      Promise.all([
        fetchNovaMessages('/conversations/' + convId + '/messages?size=80'),
        apiJson('/ai/assistant/status?conversationId=' + convId).catch(function () { return {}; })
      ]).then(function (all) {
        var r = all[0];
        var sj = all[1];
        if (sj && sj.data && sj.data.assistantGenerating) {
          novaGenStatus = String(sj.data.assistantGeneratingStatus || novaGenStatus || '正在生成…');
        }
        applyNovaPeerFromPayload(r.j, r.items);
        applyNovaGeneratingState(r.j, r.items);
        if (!novaServerGenerating) {
          stopNovaGeneratingPoll();
          removeNovaServerPendingRow();
          clearPersistedNovaGenerating();
          syncInboxNovaGenerating(lastNovaPreviewFromItems(r.items));
          syncNovaInputLock();
          paintNovaMessages(r.items);
          refreshNovaReadStatuses();
          scrollC4();
          return;
        }
        syncInboxNovaGenerating();
        if (!activeIsC4()) return;
        var pending = document.querySelector('.dunes-nova-server-pending');
        if (pending) {
          var tt = pending.querySelector('.nova-think-status');
          if (tt) tt.textContent = novaGenStatus || '正在生成…';
        } else {
          maybeShowServerGenerating({ force: true });
        }
      }).catch(function () {});
    }, 2500);
  }
  function afterNovaHistoryLoaded(r, opts) {
    opts = opts || {};
    applyNovaPeerFromPayload(r.j, r.items);
    paintNovaMessages(r.items, opts);
    applyNovaGeneratingState(r.j, r.items);
    maybeShowServerGenerating({ force: true });
  }
  function ensureNovaLoadMoreHint(box) {
    if (!box) return;
    var old = document.getElementById('dunes-nova-load-more-msgs');
    if (old) old.remove();
    if (!novaMsgHasMore) return;
    var bar = document.createElement('div');
    bar.id = 'dunes-nova-load-more-msgs';
    bar.className = 'msg-system';
    bar.innerHTML = '<span class="pill tappable" style="cursor:pointer"><i class="ti ti-arrow-up"></i> 点击加载更早消息</span>';
    bar.querySelector('.pill').addEventListener('click', function () { loadOlderNovaMessages(); });
    box.insertBefore(bar, box.firstChild);
  }
  function isNovaHistoryLocated() {
    return !!(window.__dunesLocateFromHistory || window.__dunesMsgAnchorId || novaMsgHasNewer);
  }
  function clearNovaLocateState() {
    window.__dunesLocateFromHistory = false;
    window.__dunesFocusMessageId = null;
    window.__dunesMsgAnchorId = null;
    novaMsgHasNewer = false;
    var jumpBar = document.getElementById('dunes-jump-latest');
    if (jumpBar) jumpBar.remove();
    var newer = document.getElementById('dunes-nova-load-newer-msgs');
    if (newer) newer.remove();
    clearNovaTurnHighlight();
  }
  function applyNovaPagination(d, items) {
    d = d || {};
    items = items || [];
    novaMsgHasMore = !!d.hasMore;
    novaMsgOldestId = items.length ? Number(items[0].id) : 0;
    novaMsgHasNewer = !!d.hasNewer;
    novaMsgNewestId = items.length ? Number(items[items.length - 1].id) : 0;
  }
  function ensureNovaJumpToLatestBar() {
    if (!window.__dunesMsgAnchorId && !novaMsgHasNewer) return;
    var stream = streamWrap();
    if (!stream) return;
    var old = document.getElementById('dunes-jump-latest');
    if (old) return;
    var bar = document.createElement('div');
    bar.id = 'dunes-jump-latest';
    bar.className = 'dunes-jump-latest';
    bar.innerHTML = '<button type="button" class="tappable">回到最新消息</button>';
    bar.querySelector('button').addEventListener('click', function () {
      jumpToLatestNovaMessages();
    });
    stream.appendChild(bar);
  }
  function jumpToLatestNovaMessages() {
    clearNovaLocateState();
    return loadHistory();
  }
  function ensureNovaLoadNewerHint(box) {
    if (!box) return;
    var old = document.getElementById('dunes-nova-load-newer-msgs');
    if (old) old.remove();
    if (!novaMsgHasNewer) return;
    var bar = document.createElement('div');
    bar.id = 'dunes-nova-load-newer-msgs';
    bar.className = 'msg-system';
    bar.innerHTML = '<span class="pill tappable" style="cursor:pointer"><i class="ti ti-arrow-down"></i> 点击加载后续消息</span>';
    bar.querySelector('.pill').addEventListener('click', function () { loadNewerNovaMessages(); });
    box.appendChild(bar);
  }
  function loadNewerNovaMessages() {
    if (novaMsgLoadingNewer || !novaMsgHasNewer || !convId) return Promise.resolve();
    var after = novaMsgNewestId;
    if (!after) return Promise.resolve();
    var box = rowsEl();
    var stream = streamWrap();
    if (!box) return Promise.resolve();
    novaMsgLoadingNewer = true;
    novaSuppressAutoScroll = true;
    var nearBottom = false;
    if (stream) nearBottom = (stream.scrollHeight - stream.scrollTop - stream.clientHeight) < 120;
    return fetchNovaMessages('/conversations/' + convId + '/messages?size=20&after=' + after).then(function (r) {
      var items = r.items || [];
      var d = (r.j && r.j.data) ? r.j.data : {};
      if (!items.length) {
        novaMsgHasNewer = false;
        ensureNovaLoadNewerHint(box);
        return;
      }
      paintNovaMessages(items, { append: true, scroll: false });
      novaMsgNewestId = Number(items[items.length - 1].id);
      novaMsgHasNewer = !!d.hasMore;
      ensureNovaLoadNewerHint(box);
      if (!novaMsgHasNewer) {
        window.__dunesMsgAnchorId = null;
        var jb = document.getElementById('dunes-jump-latest');
        if (jb) jb.remove();
      } else {
        ensureNovaJumpToLatestBar();
      }
      if (stream && nearBottom) {
        novaSuppressAutoScroll = false;
        scrollC4();
      }
    }).catch(function (e) {
      console.warn('loadNewerNovaMessages', e);
    }).then(function () {
      novaMsgLoadingNewer = false;
      novaSuppressAutoScroll = false;
    });
  }
  function isNovaDuplicateVoiceTranscript(items, idx) {
    if (idx <= 0) return false;
    var cur = items[idx];
    var prev = items[idx - 1];
    if (String(cur.kind || '').toUpperCase() !== 'TEXT') return false;
    if (String(prev.kind || '').toUpperCase() !== 'AUDIO') return false;
    var txt = String(cur.bodyText || cur.content || '').trim();
    if (!txt) return false;
    var prevPayload = parsePayload(prev.payload);
    if (String(prevPayload.transcript || '').trim() === txt) return true;
    return String(prev.bodyText || '').trim() === txt;
  }
  function paintNovaMessages(items, opts) {
    opts = opts || {};
    var box = rowsEl();
    if (!box) return;
    if (!items.length) {
      if (!opts.keepIfHasRows) showWelcome();
      return;
    }
    items = items.slice().sort(function (a, b) { return Number(a.id) - Number(b.id); });
    items.forEach(function (m) { normalizeNovaMsg(m); });
    items = items.filter(function (m, i, arr) { return !isNovaDuplicateVoiceTranscript(arr, i); });
    var prepend = !!opts.prepend;
    var firstExisting = prepend ? box.querySelector('[data-message-id]') : null;
    var prevAt = prepend ? null : (opts.append ? lastNovaMessageCreatedAt(box) : null);
    var lastPrependedAt = null;
    var frag = document.createDocumentFragment();
    items.forEach(function (m) {
      if ((prepend || opts.append) && m.id && box.querySelector('[data-message-id="' + m.id + '"]')) return;
      var at = msgCreatedAt(m);
      var divLabel = dayDividerLabel(at, prevAt);
      if (divLabel) frag.appendChild(createDateDivider(divLabel));
      var wrap = document.createElement('div');
      wrap.innerHTML = renderHistoryMessage(m);
      while (wrap.firstChild) frag.appendChild(wrap.firstChild);
      prevAt = at;
      if (prepend) lastPrependedAt = at;
    });
    if (prepend) box.insertBefore(frag, box.firstChild);
    else if (opts.append) box.appendChild(frag);
    else {
      box.innerHTML = '';
      box.appendChild(frag);
    }
    if (prepend && firstExisting && lastPrependedAt) {
      var firstExistingAt = firstExisting.getAttribute('data-created-at') || '';
      var boundaryLabel = dayDividerLabel(firstExistingAt, lastPrependedAt);
      if (boundaryLabel) {
        var existingDivider = firstExisting.previousElementSibling;
        if (!existingDivider || !existingDivider.classList.contains('msg-date-divider')) {
          box.insertBefore(createDateDivider(boundaryLabel), firstExisting);
        }
      }
    }
    ensureNovaLeadingDateDivider(box);
    ensureNovaLoadMoreHint(box);
    if (!prepend) ensureNovaLoadNewerHint(box);
    setHasChat(true);
    refreshNovaReadStatuses();
    hydrateNovaMediaUrls(box);
    wireC4VoicePlay();
    if (opts.scroll !== false) scrollC4();
  }
  function loadOlderNovaMessages() {
    if (novaMsgLoadingOlder || !novaMsgHasMore || !convId) return Promise.resolve();
    var before = novaMsgOldestId;
    if (!before) return Promise.resolve();
    var box = rowsEl();
    var stream = streamWrap();
    if (!box) return Promise.resolve();
    novaMsgLoadingOlder = true;
    novaSuppressAutoScroll = true;
    var prevHeight = stream ? stream.scrollHeight : 0;
    return fetchNovaMessages('/conversations/' + convId + '/messages?size=20&before=' + before).then(function (r) {
      var items = r.items || [];
      var d = (r.j && r.j.data) ? r.j.data : {};
      novaMsgHasMore = !!d.hasMore;
      if (!items.length) {
        novaMsgHasMore = false;
        ensureNovaLoadMoreHint(box);
        return;
      }
      novaMsgOldestId = items[0].id;
      paintNovaMessages(items, { prepend: true, scroll: false });
      if (stream) stream.scrollTop = stream.scrollHeight - prevHeight;
    }).catch(function (e) {
      console.warn('loadOlderNovaMessages', e);
    }).then(function () {
      novaMsgLoadingOlder = false;
      novaSuppressAutoScroll = false;
    });
  }
  function wireNovaStreamHistory() {
    var stream = streamWrap();
    if (!stream || stream.dataset.novaHistoryWired) return;
    stream.dataset.novaHistoryWired = '1';
    stream.addEventListener('scroll', function () {
      if (stream.scrollTop < 72) loadOlderNovaMessages();
    });
  }
  function clearNovaTurnHighlight() {
    var box = rowsEl();
    if (!box) return;
    box.querySelectorAll('.dunes-nova-turn-focus').forEach(function (el) {
      el.classList.remove('dunes-nova-turn-focus');
    });
  }
  function highlightNovaTurn(userMsgId) {
    clearNovaTurnHighlight();
    var box = rowsEl();
    if (!box || !userMsgId) return;
    var userRow = box.querySelector('[data-message-id="' + userMsgId + '"]')
      || box.querySelector('.msg-row.sent[data-msg-id="' + userMsgId + '"]');
    if (!userRow || !userRow.classList.contains('sent')) return;
    userRow.classList.add('dunes-nova-turn-focus');
    var next = userRow.nextElementSibling;
    while (next) {
      if (next.classList && next.classList.contains('msg-date-divider')) {
        next = next.nextElementSibling;
        continue;
      }
      if (next.classList && next.classList.contains('msg-row') && next.classList.contains('recv')) {
        next.classList.add('dunes-nova-turn-focus');
        break;
      }
      if (next.classList && next.classList.contains('msg-row') && next.classList.contains('sent')) break;
      next = next.nextElementSibling;
    }
  }
  function focusNovaMessage(msgId, opts) {
    if (!msgId) return;
    opts = opts || {};
    var block = opts.block || 'center';
    var tries = 0;
    function tryScroll() {
      tries++;
      var row = document.querySelector('#c4-api-rows .msg-row.sent[data-message-id="' + msgId + '"]')
        || document.querySelector('#c4-api-rows [data-message-id="' + msgId + '"]')
        || document.querySelector('#c4-api-rows .msg-row[data-msg-id="' + msgId + '"]');
      if (!row) {
        if (tries < 12) setTimeout(tryScroll, 80);
        return;
      }
      row.scrollIntoView({ block: block, behavior: tries < 2 ? 'auto' : 'smooth' });
      row.classList.add('dunes-msg-focus');
      if (opts.highlightTurn) highlightNovaTurn(msgId);
      setTimeout(function () { row.classList.remove('dunes-msg-focus'); }, 2600);
    }
    setTimeout(tryScroll, 50);
  }
  function finalizeStreamRow(ui, aiMsgId, fallbackText) {
    if (!ui || !ui.row || !ui.row.parentNode) return;
    var body = novaFinalReplyText(ui);
    if (!body) body = stripHermesProgressLines(sanitizeNovaBody(ui.text || ''));
    if (!body && fallbackText) body = String(fallbackText).trim();
    if (!body) return;
    var fake = {
      id: aiMsgId || 0,
      kind: 'AI_ASSISTANT',
      bodyText: body,
      sender: { displayName: 'NOVA', userId: 0 },
      payload: { citations: (ui.citations || []) }
    };
    var wrap = document.createElement('div');
    wrap.innerHTML = renderHistoryMessage(fake);
    var newRow = wrap.firstElementChild;
    if (!newRow) return;
    newRow.classList.remove('dunes-nova-live');
    if (aiMsgId) {
      newRow.dataset.messageId = String(aiMsgId);
      newRow.dataset.msgId = String(aiMsgId);
    }
    ui.row.parentNode.replaceChild(newRow, ui.row);
    ui.row = newRow;
  }
  function fetchNovaMessages(query) {
    if (!convId) return Promise.resolve({ items: [], j: {} });
    return apiJson(query).then(function (j) {
      var items = (j.data && j.data.items) || j.items || [];
      if (!items.length && j.data && j.data.messages) items = j.data.messages;
      items = items.slice().sort(function (a, b) { return Number(a.id) - Number(b.id); });
      return { items: items, j: j };
    });
  }
  function loadHistory() {
    if (!convId) return Promise.resolve();
    clearNovaLocateState();
    return fetchNovaMessages('/conversations/' + convId + '/messages?size=20').then(function (r) {
      var items = r.items;
      var box = rowsEl();
      if (!box) return;
      var d = (r.j && r.j.data) ? r.j.data : {};
      applyNovaPagination(d, items);
      stopNovaGeneratingPoll();
      removeNovaServerPendingRow();
      if (!items.length) {
        applyNovaGeneratingState(r.j, items);
        showWelcome();
        maybeShowServerGenerating({ force: true });
        return;
      }
      afterNovaHistoryLoaded(r);
      wireNovaStreamHistory();
    }).catch(function (e) {
      console.warn('C4 history', e);
      showWelcome();
    });
  }
  function loadHistoryAround(centerId) {
    if (!convId || !centerId) return loadHistory();
    novaSuppressAutoScroll = true;
    return fetchNovaMessages('/conversations/' + convId + '/messages?size=40&around=' + centerId).then(function (r) {
      var items = r.items;
      if (!items.length) return loadHistory();
      var d = (r.j && r.j.data) ? r.j.data : {};
      applyNovaPagination(d, items);
      stopNovaGeneratingPoll();
      removeNovaServerPendingRow();
      afterNovaHistoryLoaded(r, { scroll: false });
      window.__dunesMsgAnchorId = Number(centerId);
      window.__dunesLocateFromHistory = false;
      window.__dunesFocusMessageId = null;
      focusNovaMessage(centerId, { block: 'center', highlightTurn: true });
      ensureNovaJumpToLatestBar();
    }).catch(function (e) {
      console.warn('C4 history around', e);
      return loadHistory();
    }).then(function () {
      novaSuppressAutoScroll = false;
    });
  }
  function startNewConversation() {
    if (isNovaInputLocked()) { showNovaInputBusyHint(); return Promise.resolve(); }
    stopNovaGeneratingPoll();
    novaServerGenerating = false;
    sending = false;
    bgStreaming = false;
    clearPersistedNovaGenerating();
    syncInboxNovaGenerating();
    return apiJson('/ai/assistant/sessions/new', { method: 'POST', body: '{}' }).then(function (j) {
      var d = j.data || j;
      convId = Number(d.conversationId || d.id || 0);
      if (convId) {
        window.pendingConvId = convId;
        try { pendingConvId = convId; } catch (e2) {}
      }
      novaPeerRead = 0;
      clearApiRows();
      showWelcome();
      setHasChat(false);
      syncNovaInputLock();
      scrollC4();
      return convId;
    });
  }
  function isNovaSlashNew(text) {
    var t = String(text || '').trim().toLowerCase();
    return t === '/new' || t === '/新对话' || t === '新对话';
  }
  function openNovaSearch() {
    function goSearch() {
      window.__dunesC12NovaMode = true;
      window.__dunesHistoryReturnScreen = 'C4';
      window.__dunesActiveConvKind = 'AI_ASSISTANT';
      window.pendingConvId = convId;
      try { pendingConvId = convId; } catch (e) {}
      if (typeof go === 'function') go('C12');
      else if (typeof setScreen === 'function') setScreen('C12', false);
    }
    if (convId) return Promise.resolve(goSearch());
    return ensureSession().then(goSearch);
  }
  function formatNovaHistoryTime(at) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    var now = new Date();
    var hm = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
    if (dayKey(d) === dayKey(now)) return hm;
    var yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (dayKey(d) === dayKey(yesterday)) return '昨天 ' + hm;
    if (d.getFullYear() === now.getFullYear()) return (d.getMonth() + 1) + '/' + d.getDate() + ' ' + hm;
    return d.getFullYear() + '/' + (d.getMonth() + 1) + '/' + d.getDate();
  }
  function renderNovaHistoryList(rows, append) {
    var box = document.getElementById('c11-api-rows');
    if (!box) return;
    if (!rows.length && !append) {
      box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>暂无历史对话</span></div>';
      return;
    }
    if (!append) box.innerHTML = '';
    var prevAt = append ? (box.dataset.lastHistAt || '') : null;
    rows.forEach(function (r) {
      var at = r.lastMessageAt || '';
      var divLabel = dayDividerLabel(at, prevAt);
      if (divLabel) {
        var secEl = document.createElement('div');
        secEl.className = 'msg-date-divider';
        secEl.textContent = divLabel;
        box.appendChild(secEl);
      }
      var conv = Number(r.conversationId || 0);
      var mid = Number(r.messageId || r.id || 0);
      var preview = stripHermesProgressLines(sanitizeNovaBody(String(r.lastMessagePreview || '')));
      if (preview.indexOf('你好，我是你的') === 0) preview = '';
      var card = document.createElement('div');
      card.className = 'noti-card tappable';
      card.dataset.title = String(r.title || '');
      card.dataset.preview = preview;
      card.innerHTML = '<div class="nc-ic nova-hist-ic">' + novaIcHtml() + '</div>'
        + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(r.title || '新对话') + '</div>'
        + '<div class="nc-time">' + esc(formatNovaHistoryTime(r.lastMessageAt)) + '</div></div>'
        + '<div class="nc-desc">' + esc(preview || '（暂无消息预览）') + '</div></div>';
      card.addEventListener('click', function () {
        convId = conv;
        window.pendingConvId = convId;
        try { pendingConvId = convId; } catch (e) {}
        window.__dunesFocusMessageId = mid;
        window.__dunesMsgAnchorId = mid;
        window.__dunesLocateFromHistory = !!mid;
        if (typeof go === 'function') go('C4');
        else if (typeof setScreen === 'function') setScreen('C4', false);
      });
      box.appendChild(card);
      prevAt = at;
    });
    if (prevAt) box.dataset.lastHistAt = prevAt;
    var moreBtn = document.getElementById('c11-load-more');
    if (novaHistoryHasMore) {
      if (!moreBtn) {
        moreBtn = document.createElement('div');
        moreBtn.id = 'c11-load-more';
        moreBtn.className = 'api-strip tappable';
        moreBtn.innerHTML = '<i class="ti ti-arrow-down"></i><span>加载更多历史</span>';
        moreBtn.addEventListener('click', function () { loadNovaHistoryList(true); });
        box.appendChild(moreBtn);
      }
    } else if (moreBtn) moreBtn.remove();
  }
  function filterNovaHistory(q) {
    q = String(q || '').trim().toLowerCase();
    if (!q) {
      renderNovaHistoryList(novaHistoryAll);
      return;
    }
    var hits = novaHistoryAll.filter(function (r) {
      var t = String(r.title || '').toLowerCase();
      var p = String(r.lastMessagePreview || '').toLowerCase();
      return t.indexOf(q) >= 0 || p.indexOf(q) >= 0;
    });
    renderNovaHistoryList(hits);
  }
  var c11HeaderWired = false;
  function wireC11Header() {
    if (c11HeaderWired) return;
    c11HeaderWired = true;
    var screen = document.querySelector('.screen[data-screen="C11"]');
    if (!screen) return;
    var name = screen.querySelector('.ds-name');
    if (name) name.textContent = 'NOVA对话历史';
    var crumb = screen.querySelector('.ds-crumb');
    if (crumb) crumb.style.display = 'none';
    var searchBtn = document.getElementById('c11-header-search');
    var searchBar = document.getElementById('c11-search-bar');
    var input = document.getElementById('c11-search-input');
    var clr = document.getElementById('c11-search-clear');
    if (searchBtn && searchBar) {
      searchBtn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var on = searchBar.classList.toggle('dunes-c11-search-on');
        searchBar.style.display = on ? 'flex' : 'none';
        if (on && input) input.focus();
        if (!on && input) { input.value = ''; filterNovaHistory(''); }
      });
    }
    if (input && !input.dataset.dunesWired) {
      input.dataset.dunesWired = '1';
      input.addEventListener('input', function () { filterNovaHistory(input.value); });
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') filterNovaHistory(input.value); });
    }
    if (clr && input) {
      clr.addEventListener('click', function () {
        input.value = '';
        filterNovaHistory('');
        input.focus();
      });
    }
  }
  function loadNovaHistoryList(append) {
    var box = document.getElementById('c11-api-rows');
    if (!box) return Promise.resolve();
    if (novaHistoryLoading) return Promise.resolve();
    wireC11Header();
    if (!append) {
      novaHistoryOldestAt = '';
      box.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>加载对话历史…</span></div>';
    }
    novaHistoryLoading = true;
    var q = '/ai/history?view=turns&size=20';
    if (append && novaHistoryOldestAt) q += '&before=' + encodeURIComponent(novaHistoryOldestAt);
    return apiJson(q).then(function (j) {
      var d = j.data || j;
      var rows = d.items || [];
      novaHistoryHasMore = !!d.hasMore;
      if (rows.length) novaHistoryOldestAt = rows[rows.length - 1].lastMessageAt || novaHistoryOldestAt;
      if (append) novaHistoryAll = novaHistoryAll.concat(rows);
      else novaHistoryAll = rows;
      var input = document.getElementById('c11-search-input');
      var sq = input ? input.value.trim() : '';
      if (sq) filterNovaHistory(sq);
      else renderNovaHistoryList(rows, !!append);
    }).catch(function (e) {
      if (!append) box.innerHTML = '<div class="api-strip"><span>加载失败：' + esc(e.message || e) + '</span></div>';
    }).then(function () {
      novaHistoryLoading = false;
    });
  }
  var c4HeaderWired = false;
  function wireC4Header() {
    if (c4HeaderWired) return;
    c4HeaderWired = true;
    var stack = document.getElementById('stack');
    if (!stack) return;
    stack.addEventListener('click', function (e) {
      if (!activeIsC4()) return;
      if (e.target.closest('#c4-btn-new')) {
        e.preventDefault();
        e.stopPropagation();
        startNewConversation();
        return;
      }
      if (e.target.closest('#c4-btn-search')) {
        e.preventDefault();
        e.stopPropagation();
        openNovaSearch();
      }
    }, true);
  }
  function ensureSession() {
    var pending = Number(window.pendingConvId || 0);
    var body = pending > 0 ? JSON.stringify({ conversationId: pending }) : undefined;
    return apiJson('/ai/assistant/sessions/ensure', { method: 'POST', body: body }).then(function (j) {
      var d = j.data || j;
      convId = Number(d.conversationId || d.id || 0);
      if (convId) {
        window.pendingConvId = convId;
        try { pendingConvId = convId; } catch (e2) {}
      }
      return convId;
    });
  }
  function appendUserBubble(text, msgId) {
    var box = rowsEl();
    if (!box) return;
    var row = document.createElement('div');
    row.className = 'msg-row sent dunes-nova-live';
    if (msgId) row.dataset.messageId = String(msgId);
    row.innerHTML = ''
      + '<div class="msg-av-sm person-e">' + esc(selfInitial()) + '</div>'
      + '<div class="msg-content">'
      + '<div class="msg-meta"><span class="nm">' + esc(selfName()) + '</span></div>'
      + '<div class="msg-bubble sent">' + esc(text) + '</div>'
      + readStatusHtml(msgId || 0)
      + '</div>';
    box.appendChild(row);
    setHasChat(true);
    scrollC4();
  }
  function createAiStreamRow() {
    var box = rowsEl();
    var row = document.createElement('div');
    row.className = 'msg-row recv dunes-nova-live';
    row.innerHTML = ''
      + novaAvHtml('msg-av-sm ai-bot')
      + '<div class="msg-content">'
      + '<div class="msg-meta"><span class="nm">NOVA</span>'
      + '<span class="badge-ai">AI</span></div>'
      + '<div class="msg-bubble ai-recv">'
      + '<div class="nova-think-panel" style="display:none">'
      + '<div class="nova-think-toggle" role="button" tabindex="0">'
      + '<i class="ti ti-sparkles nova-think-ic"></i>'
      + '<span class="nova-think-label">深度思考</span>'
      + '<span class="nova-think-status">思考中…</span>'
      + '<i class="ti ti-chevron-down nova-think-chev"></i></div>'
      + '<div class="nova-think-body-wrap">'
      + '<div class="nova-think-body"></div>'
      + '<div class="nova-tool-steps"></div></div></div>'
      + '<div class="nova-text"></div>'
      + '<div class="nova-citations"></div>'
      + '</div></div>';
    box.appendChild(row);
    scrollC4();
    var ui = {
      row: row,
      thinkPanel: row.querySelector('.nova-think-panel'),
      thinkToggle: row.querySelector('.nova-think-toggle'),
      thinkStatus: row.querySelector('.nova-think-status'),
      thinkBody: row.querySelector('.nova-think-body'),
      toolStepsWrap: row.querySelector('.nova-tool-steps'),
      textEl: row.querySelector('.nova-text'),
      citeEl: row.querySelector('.nova-citations'),
      tools: {},
      text: '',
      thinkStream: '',
      citations: [],
      _novaStreaming: true
    };
    wireNovaThinkToggle(ui);
    return ui;
  }
  function parseSSEPayload(raw, eventName) {
    try {
      var j = JSON.parse(raw);
      if (j.event && j.data) return { type: j.event, data: j.data };
      if (j.type) return { type: j.type, data: j };
      return { type: eventName || j.event || 'message', data: j.data || j };
    } catch (e) {
      return null;
    }
  }
  function applyStreamEvent(ui, type, data) {
    data = data || {};
    if (type === 'thinking') {
      showNovaThinkPanel(ui, data.text || '思考中…');
      return;
    }
    if (type === 'thinking_delta') {
      var thinkChunk = data.text || data.content || '';
      if (!thinkChunk) return;
      var piece = data.body || stripHermesThinkingHeader(thinkChunk);
      if (piece) ui.thinkStream = (ui.thinkStream || '') + piece;
      renderNovaThinkBody(ui);
      stopNovaStreamWaitHint(ui);
      syncNovaStreamThinking(ui);
      scrollC4();
      return;
    }
    if (type === 'tool_progress') {
      var tool = data.tool || data.name || '';
      var msg = data.message || data.text || '';
      if (msg) showNovaThinkPanel(ui, msg);
      else if (tool) {
        var phase = String(data.phase || data.status || '').trim();
        showNovaThinkPanel(ui, phase ? (phase + ' · ' + tool) : ('调用工具 ' + tool + '…'));
      } else showNovaThinkPanel(ui, '正在生成…');
      return;
    }
    if (type === 'tool_call') {
      var name = data.tool || data.name || 'tool';
      ui.tools[name] = { name: name, request: data.request || {}, status: 'running' };
      showNovaThinkPanel(ui, '调用工具 ' + toolLabel(name, data.request) + '…');
      renderNovaToolSteps(ui);
      scrollC4();
      return;
    }
    if (type === 'tool_result') {
      var tname = data.tool || data.name || 'tool';
      if (!ui.tools[tname]) ui.tools[tname] = { name: tname, request: {}, status: 'running' };
      ui.tools[tname].status = 'done';
      ui.tools[tname].result = data.result;
      renderNovaToolSteps(ui);
      setNovaThinkStatus(ui, toolLabel(tname, ui.tools[tname].request) + ' 完成');
      scrollC4();
      return;
    }
    if (type === 'delta') {
      var chunk = data.text || data.content || '';
      if (!chunk) return;
      ui.text += chunk;
      paintNovaStreamText(ui, false);
      return;
    }
    if (type === 'citation') {
      var ref = data.ref || (data.ref && data.ref.ref);
      var span = document.createElement('span');
      span.className = 'ai-citation';
      span.textContent = ref || '?';
      span.title = data.title || '';
      ui.citeEl.appendChild(span);
      ui.citeEl.appendChild(document.createTextNode(' '));
      return;
    }
    if (type === 'error') {
      novaServerGenerating = false;
      sending = false;
      bgStreaming = false;
      clearPersistedNovaGenerating();
      syncNovaInputLock();
      ui.thinkPanel.style.display = 'none';
      var msg = data.message || data.data && data.data.message || '助手出错';
      if (data.code === 'vision_not_configured' || String(msg).indexOf('glm-4v 未开通') >= 0) {
        msg = '图片识别未开通：请在 New API 后台为当前令牌开通 glm-4v 模型';
      } else if (data.code === 'vision_upstream_error' || data.code === 'vision_failed') {
        msg = '图片识别暂时不可用，请稍后重试';
      } else       if (data.code === 'asr_failed' && (String(msg).indexOf('未得到有效转写') >= 0 || String(msg).indexOf('dialogue') >= 0)) {
        msg = '语音识别未得到有效转写，请改用文字发送或稍后重试';
      } else if (data.code === 'asr_not_configured' || String(msg).indexOf('语音识别未开通') >= 0 || String(msg).indexOf('glm-asr') >= 0) {
        msg = '语音识别未开通：请在 New API 后台为当前令牌开通 glm-asr-2512 模型';
      } else if (data.code === 'asr_upstream_error' || (data.code === 'asr_failed' && String(msg).indexOf('网络错误') >= 0)) {
        msg = '语音识别上游暂时不可用，请稍后重试';
      } else if (data.code && String(data.code).indexOf('asr_') === 0) {
        ui.thinkPanel.style.display = 'none';
        ui.text = msg;
        paintNovaStreamText(ui, false);
        scrollC4();
        return;
      } else if (data.code === 'quota_exceeded' || String(msg).indexOf('额度') >= 0) {
        msg = '额度已用尽，请联系管理员';
      } else if (data.code === 'hermes_timeout' || /timeout|deadline exceeded/i.test(String(msg))) {
        msg = 'NOVA 响应超时，模型处理较慢，请稍后重试';
      } else if (/hermes HTTP 500|do_request_failed|new_api_error/i.test(String(msg))) {
        msg = 'NOVA 模型服务暂时不可用，请稍后重试或联系管理员';
      }
      ui._novaError = msg;
      ui.textEl.innerHTML = '<span style="color:var(--coral)">' + esc(msg) + '</span>';
      if (data.code === 'nova_not_ready') ui._novaNotReady = true;
      scrollC4();
      return;
    }
    if (type === 'voice_transcript') {
      showNovaThinkPanel(ui, '正在生成…');
      return;
    }
    if (type === 'image_description') {
      showNovaThinkPanel(ui, '正在生成…');
      return;
    }
    if (type === 'user_message') {
      var mid = Number(data.messageId || (data.message && data.message.id) || 0);
      var msg = data.message || null;
      var live = document.querySelectorAll('#c4-api-rows .msg-row.sent.dunes-nova-live');
      var last = live.length ? live[live.length - 1] : null;
      if (last && mid) {
        last.dataset.messageId = String(mid);
        last.dataset.msgId = String(mid);
        last.classList.remove('dunes-nova-live');
        if (msg && msg.createdAt) last.setAttribute('data-created-at', msg.createdAt);
      } else if (msg && mid) {
        normalizeNovaMsg(msg);
        appendUserAttachmentBubble(String(msg.kind || 'TEXT').toUpperCase(), msg.bodyText || '', parsePayload(msg.payload), mid);
      }
      refreshNovaReadStatuses();
      scrollC4();
      return;
    }
    if (type === 'done') {
      novaServerGenerating = false;
      clearPersistedNovaGenerating();
      syncNovaInputLock();
      stopNovaGeneratingPoll();
      removeNovaServerPendingRow();
      var serverText = String(data.text || data.bodyText || '').trim();
      if (serverText && !novaFinalReplyText(ui)) ui.text = serverText;
      finalizeNovaThinkingPanel(ui);
      var finalReply = novaFinalReplyText(ui) || serverText;
      if (ui.textEl) {
        if (ui._novaError) {
          ui.textEl.innerHTML = '<span style="color:var(--coral)">' + esc(ui._novaError) + '</span>';
        } else if (finalReply) {
          if (novaBodyNeedsRichRender(finalReply)) ui.textEl.innerHTML = renderNovaBodyHtml(finalReply);
          else ui.textEl.innerHTML = mdLite(finalReply);
        } else ui.textEl.innerHTML = '';
      }
      if (data.messageId) finalizeStreamRow(ui, Number(data.messageId), serverText);
      if (data.peerLastReadMessageId != null) applyNovaPeerRead(data.peerLastReadMessageId);
      else if (data.messageId) applyNovaPeerRead(data.messageId);
      if (activeIsC4()) {
        markNovaConversationRead();
        scrollC4();
      }
    }
  }
  function sendMessage(text, attempt, opts) {
    opts = opts || {};
    text = String(text || '').trim();
    attempt = attempt || 0;
    if (isNovaHistoryLocated()) {
      clearNovaLocateState();
      return jumpToLatestNovaMessages().then(function () {
        return sendMessage(text, attempt, opts);
      });
    }
    if (!opts.kind && isNovaSlashNew(text)) return startNewConversation();
    var hasMedia = !!(opts.kind && opts.payload);
    if ((!text && !hasMedia) || sending || novaServerGenerating) {
      if (novaServerGenerating || sending || bgStreaming) showNovaInputBusyHint();
      else if (novaServerGenerating) maybeShowServerGenerating();
      return Promise.resolve();
    }
    sending = true;
    bgStreaming = true;
    novaServerGenerating = true;
    persistNovaGenerating();
    syncInboxNovaGenerating();
    syncNovaInputLock();
    if (attempt === 0 && text && !opts.skipUserBubble) appendUserBubble(text);
    var ui = createAiStreamRow();
    showNovaThinkPanel(ui, '正在生成…');
    startNovaStreamWaitHint(ui);
    var headers = authHeaders({ 'Content-Type': 'application/json', Accept: 'text/event-stream' });
    var body = { content: text };
    if (convId) body.conversationId = convId;
    if (opts.kind) {
      body.kind = opts.kind;
      body.bodyText = opts.bodyText || '';
      body.payload = opts.payload || {};
      if (String(opts.kind).toUpperCase() === 'AUDIO') {
        showNovaThinkPanel(ui, '正在听懂语音…');
      } else if (String(opts.kind).toUpperCase() === 'IMAGE') {
        showNovaThinkPanel(ui, '正在识别图片…');
      }
    }
    return fetch(apiBase() + '/ai/assistant/messages', {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(body)
    }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      if (!r.body || !r.body.getReader) {
        return r.text().then(function (t) {
          t.split('\n').forEach(function (line) {
            if (!line.startsWith('data:')) return;
            var ev = parseSSEPayload(line.slice(5).trim(), '');
            if (ev) applyStreamEvent(ui, ev.type, ev.data);
          });
        });
      }
      var reader = r.body.getReader();
      var dec = new TextDecoder();
      var buf = '';
      var curEvent = 'message';
      var paintQueued = false;
      function queueStreamPaint() {
        if (paintQueued) return;
        paintQueued = true;
        requestAnimationFrame(function () {
          paintQueued = false;
          if (!ui.text) return;
          paintNovaStreamText(ui, false);
        });
      }
      function processSseLines(lines) {
        lines.forEach(function (line) {
          if (line.indexOf('event:') === 0) {
            curEvent = line.slice(6).trim();
            return;
          }
          if (line.indexOf('data:') !== 0) return;
          var ev = parseSSEPayload(line.slice(5).trim(), curEvent);
          if (!ev) return;
          if (ev.type === 'thinking_delta') {
            applyStreamEvent(ui, 'thinking_delta', ev.data);
            return;
          }
          if (ev.type === 'delta') {
            var chunk = (ev.data && (ev.data.text || ev.data.content)) || '';
            if (!chunk) return;
            if (HERMES_THINK_LINE_RE.test(chunk.trim())) {
              applyStreamEvent(ui, 'thinking_delta', { text: chunk });
              return;
            }
            ui.text += chunk;
            queueStreamPaint();
            return;
          }
          if (ev.type === 'tool_progress') {
            applyStreamEvent(ui, 'tool_progress', ev.data);
            return;
          }
          applyStreamEvent(ui, ev.type, ev.data);
        });
      }
      function pump() {
        return reader.read().then(function (chunk) {
          if (chunk.value) {
            buf += dec.decode(chunk.value, { stream: true });
            var parts = buf.split('\n');
            buf = parts.pop() || '';
            processSseLines(parts);
          }
          if (chunk.done) {
            if (buf.trim()) processSseLines(buf.split('\n'));
            finalizeNovaThinkingPanel(ui);
            var endReply = novaFinalReplyText(ui);
            if (ui.textEl && endReply) {
              if (novaBodyNeedsRichRender(endReply)) ui.textEl.innerHTML = renderNovaBodyHtml(endReply);
              else ui.textEl.innerHTML = mdLite(endReply);
            }
            scrollC4();
            return;
          }
          return pump();
        });
      }
      return pump();
    }).catch(function (e) {
      var msg = String((e && e.message) || e || '');
      var disconnected = /abort|cancel|network|failed to fetch|load failed/i.test(msg);
      if (!disconnected) {
        novaServerGenerating = false;
        clearPersistedNovaGenerating();
        syncNovaInputLock();
      } else {
        persistNovaGenerating();
        syncNovaInputLock();
      }
      stopNovaGeneratingPoll();
      ui.thinkPanel.style.display = 'none';
      if (!disconnected) {
        ui.textEl.innerHTML = '<span style="color:var(--coral)">（' + esc(msg) + '）</span>';
      } else if (activeIsC4()) {
        maybeShowServerGenerating({ force: true });
      }
    }).then(function () {
      return finishStreamUi(ui, attempt, text);
    });
  }
  var QA_PROMPTS = {
    '查代办': '我还有几个待办？',
    '查合同': '查湖北中石油的合同',
    '流程': 'PROPOSAL_3STEP 啥意思？'
  };
  function wireStackOnce() {
    var stack = document.getElementById('stack');
    if (!stack || stack.dataset.novaStackWired) return;
    stack.dataset.novaStackWired = '1';
    stack.addEventListener('click', function (e) {
      if (!activeIsC4()) return;
      var imgCard = e.target.closest('.dunes-nova-image-card');
      if (imgCard) {
        e.preventDefault();
        e.stopPropagation();
        openNovaImageUrl(imgCard.getAttribute('data-url') || '');
        return;
      }
      var fileCard = e.target.closest('.dunes-nova-file-card');
      if (fileCard) {
        e.preventDefault();
        e.stopPropagation();
        var url = fileCard.getAttribute('data-url') || '';
        if (url) window.open(url, '_blank', 'noopener');
        return;
      }
      if (e.target.closest('#c4-send')) {
        e.preventDefault();
        e.stopPropagation();
        submitC4Input();
        return;
      }
      if (isNovaInputLocked() && e.target.closest('#c4-quick-actions .qa-cell, #c4-send, .msg-input-bar .voice-btn, .msg-input-bar .emoji-btn, #c4-input')) {
        e.preventDefault();
        e.stopPropagation();
        showNovaInputBusyHint();
        return;
      }
      var card = e.target.closest('[data-c4-prompt]');
      if (card && !card.dataset.go) {
        var p = card.dataset.c4Prompt;
        if (!p) return;
        e.preventDefault();
        e.stopPropagation();
        sendMessage(p);
        return;
      }
      var cell = e.target.closest('#c4-quick-actions .qa-cell');
      if (cell && !cell.dataset.go) {
        var label = (cell.querySelector('.qa-t') || {}).textContent || '';
        label = label.trim();
        if (label === '拍照' || cell.getAttribute('data-qa') === 'camera') {
          e.preventDefault();
          e.stopPropagation();
          ensureSession().then(function () {
            var cam = document.getElementById('c4-camera-slot');
            if (cam) cam.click();
          });
          return;
        }
        if (label === '图片' || cell.getAttribute('data-qa') === 'album') {
          e.preventDefault();
          e.stopPropagation();
          ensureSession().then(function () {
            var alb = document.getElementById('c4-album-slot');
            if (alb) alb.click();
          });
          return;
        }
        if (label === '新对话' || cell.getAttribute('data-qa') === 'new-chat') {
          e.preventDefault();
          e.stopPropagation();
          startNewConversation();
          return;
        }
        var prompt = QA_PROMPTS[label];
        if (!prompt) return;
        e.preventDefault();
        e.stopPropagation();
        sendMessage(prompt);
      }
      var imgThumb = e.target.closest('.dunes-img-thumb');
      if (imgThumb) {
        e.preventDefault();
        e.stopPropagation();
        openNovaImageUrl(imgThumb.getAttribute('data-full-url') || imgThumb.getAttribute('data-url') || imgThumb.src || '');
      }
    }, true);
    stack.addEventListener('keydown', function (e) {
      if (!activeIsC4()) return;
      var input = e.target;
      if (!input || input.id !== 'c4-input') return;
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        e.stopPropagation();
        if (isNovaInputLocked()) { showNovaInputBusyHint(); return; }
        submitC4Input();
      }
    }, true);
  }
  function onLeave() {
    if (bgStreaming || novaServerGenerating) {
      persistNovaGenerating();
      syncInboxNovaGenerating();
    }
    stopNovaGeneratingPoll();
    if (bgStreaming) {
      clearNovaLiveRows();
      bgStreaming = false;
      sending = false;
    }
  }
  function onScreen(id) {
    if (id === 'C11') {
      wireC11Header();
      loadNovaHistoryList();
      return;
    }
    if (id !== 'C4') return;
    if (typeof window.__dunesWireNovaC4 === 'function') window.__dunesWireNovaC4();
    wireStackOnce();
    wireC4Header();
    wireC4MediaToolbar();
    observeNovaRowsScroll();
    wireNovaStreamHistory();
    if (!bgStreaming) sending = false;
    var pending = Number(window.pendingConvId || 0);
    if (pending > 0) convId = pending;
    var focusId = Number(window.__dunesFocusMessageId || window.__dunesMsgAnchorId || 0);
    var locating = focusId > 0 && !!window.__dunesLocateFromHistory;
    ensureSession().then(function () {
      return refreshNovaGeneratingStatus();
    }).then(function () {
      if (bgStreaming) {
        maybeShowServerGenerating({ force: true });
        startNovaGeneratingPoll();
        return markNovaConversationRead();
      }
      if (locating) {
        return loadHistoryAround(focusId);
      }
      return loadHistory();
    }).then(function () {
      return markNovaConversationRead();
    }).then(function () {
      syncNovaInputLock();
      if (!isNovaHistoryLocated()) scrollC4();
    });
  }
  wireStackOnce();
  wireC4Header();
  window.sendAssistantStream = function (text) { return sendMessage(text); };
  return {
    onScreen: onScreen,
    onLeave: onLeave,
    sendMessage: sendMessage,
    ensureSession: ensureSession,
    loadHistory: loadHistory,
    loadHistoryAround: loadHistoryAround,
    startNewConversation: startNewConversation,
    openNovaSearch: openNovaSearch,
    loadNovaHistoryList: loadNovaHistoryList
  };
})();
''';
}
