/// C5/C2 聊天：Centrifugo 实时、已读、工具栏、Twemoji 表情（注入 WebView）。
abstract final class ImChatInjection {
  static const js = r'''
window.DunesImChat = (function () {
  var imCentrifuge = null;
  var imConvSub = null;
  var imConvSubs = {};
  var imUserSub = null;
  var imOnlineSub = null;
  var imWsRetry = 0;
  var imLoadGen = 0;
  var imServerChannels = {};
  var peerOnline = false;
  var imPresenceDenied = false;
  var imConnectInflight = false;
  var imReconnectTimer = null;
  window.__dunesOnlineUserIds = window.__dunesOnlineUserIds || {};

  var EMOJI_CHARS = [
    '\u{1F600}','\u{1F603}','\u{1F604}','\u{1F601}','\u{1F606}','\u{1F605}','\u{1F923}','\u{1F602}',
    '\u{1F642}','\u{1F609}','\u{1F60A}','\u{1F970}','\u{1F60D}','\u{1F618}','\u{1F61C}','\u{1F92A}',
    '\u{1F44D}','\u{1F44F}','\u{1F64F}','\u{1F91D}','\u{1F4AA}','\u{2764}\u{FE0F}','\u{1F494}',
    '\u{1F525}','\u{1F389}','\u{1F44C}','\u{2705}','\u{274C}','\u{2753}','\u{1F4A1}','\u{1F680}'
  ];

  function rtUserCh(uid) { return 'dunes_u_' + uid; }
  function rtConvCh(id) { return 'dunes_c_' + id; }
  function isConvChannel(ch) {
    return ch && (ch.indexOf('dunes_c_') === 0 || ch.indexOf('conv:') === 0);
  }
  function devUserId() {
    try {
      var t = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
      if (t) {
        var p = JSON.parse(atob(t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
        if (p.userId != null) {
          var n = Number(p.userId);
          if (!isNaN(n) && n > 0) {
            window.__dunesSelfUserId = n;
            return n;
          }
        }
        if (p.sub) {
          var s = parseInt(String(p.sub), 10);
          if (!isNaN(s) && s > 0) {
            window.__dunesSelfUserId = s;
            return s;
          }
        }
      }
    } catch (e) {}
    var cached = Number(window.__dunesSelfUserId || 0);
    if (cached > 0) return cached;
    var uid = parseInt(localStorage.getItem('dunes_user_id') || '0', 10);
    if (!isNaN(uid) && uid > 0) {
      window.__dunesSelfUserId = uid;
      return uid;
    }
    return 0;
  }
  function currentPendingConvId() {
    var id = Number(window.pendingConvId || 0);
    if (id > 0) return id;
    try {
      id = Number(pendingConvId || 0);
      if (id > 0) return id;
    } catch (e) {}
    return 0;
  }
  function setPendingConvId(id) {
    var n = Number(id || 0);
    var v = n > 0 ? n : null;
    var prev = currentPendingConvId();
    window.pendingConvId = v;
    try { pendingConvId = v; } catch (e) {}
    if (v) {
      if (!window.__dunesLocateFromHistory && !window.__dunesFocusMessageId) {
        clearChatLocateState();
      }
      if (prev && prev !== v) {
        window.__dunesActiveConvId = null;
        window.__dunesChatPeer = null;
        invalidateMsgBoxes();
      }
    }
    return v;
  }
  function markMsgBoxConv(box, convId) {
    if (!box) return;
    box.dataset.dunesLoadedConvId = convId ? String(convId) : '';
  }
  function msgBoxLoadedConvId(box) {
    return Number((box && box.dataset.dunesLoadedConvId) || 0);
  }
  function invalidateMsgBoxes() {
    ['c5-api-rows', 'c2-api-rows'].forEach(function (id) {
      var box = document.getElementById(id);
      if (box) markMsgBoxConv(box, 0);
    });
  }
  function convIdFromChannel(channel) {
    if (!channel) return 0;
    if (channel.indexOf('dunes_c_') === 0) return Number(channel.slice('dunes_c_'.length)) || 0;
    if (channel.indexOf('conv:') === 0) return Number(channel.slice('conv:'.length)) || 0;
    return 0;
  }
  function convIdFromRealtime(data, channel) {
    if (data && data.conversationId != null && data.conversationId !== '') {
      return Number(data.conversationId) || 0;
    }
    return convIdFromChannel(channel);
  }
  function boxMatchesConv(box, convId) {
    var cid = Number(convId || 0);
    return !!(box && cid && msgBoxLoadedConvId(box) === cid);
  }
  function isLatestChatView() {
    return !window.__dunesMsgHasNewer && !window.__dunesMsgAnchorId
      && !window.__dunesLocateFromHistory && !window.__dunesFocusMessageId;
  }
  function appendMessageTail(box, node, msg) {
    if (!box || !node) return;
    var id = Number(msg && msg.id);
    if (id && box.querySelector('[data-message-id="' + id + '"]')) return;
    var createdAt = msgCreatedAt(msg) || node.getAttribute('data-created-at') || '';
    insertDateDividerIfNeeded(box, createdAt, null);
    var newerHint = document.getElementById('dunes-load-newer-msgs');
    if (newerHint && newerHint.parentNode === box) box.insertBefore(node, newerHint);
    else box.appendChild(node);
    if (id > (window.__dunesMsgNewestId || 0)) window.__dunesMsgNewestId = id;
  }
  function currentPendingContactUserId() {
    var id = Number(window.__dunesPendingPeerUserId || window.pendingContactUserId || 0);
    if (id > 0) return id;
    try {
      id = Number(pendingContactUserId || 0);
      if (id > 0) return id;
    } catch (e) {}
    return 0;
  }
  function setPendingPeerUserId(id) {
    var n = Number(id || 0);
    if (n > 0) {
      window.pendingContactUserId = n;
      window.__dunesPendingPeerUserId = n;
      try { pendingContactUserId = n; } catch (e) {}
    }
  }
  function msgSenderId(m) {
    if (!m) return 0;
    if (m.sender && m.sender.userId != null && m.sender.userId !== '') {
      return Number(m.sender.userId);
    }
    if (m.senderUserId != null && m.senderUserId !== '') return Number(m.senderUserId);
    return 0;
  }
  function isSentByMe(m) {
    var me = devUserId();
    var sid = msgSenderId(m);
    return me > 0 && sid > 0 && sid === me;
  }
  function ensureMessageSender(m) {
    if (!m) return m;
    if (!m.sender) m.sender = {};
    if ((m.sender.userId == null || m.sender.userId === '') && m.senderUserId != null) {
      m.sender.userId = m.senderUserId;
    }
    var me = devUserId();
    if (me > 0 && isSentByMe(m)) {
      if (!m.sender.userId) m.sender.userId = me;
      if (!m.sender.displayName) m.sender.displayName = myDisplayName();
    }
    return m;
  }
  function senderDisplayName(m, peer) {
    if (m.sender && m.sender.displayName) return m.sender.displayName;
    var sid = msgSenderId(m);
    if (sid > 0 && sid === devUserId()) return myDisplayName();
    if (peer && sid > 0 && Number(peer.userId) === sid && peer.displayName) return peer.displayName;
    return '系统';
  }
  function myDisplayName() {
    return localStorage.getItem('dunes_display_name') || '我';
  }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
  }
  function apiFetch(path, opts) {
    opts = opts || {};
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET', headers: headers, body: opts.body || undefined
    }).then(function (r) { return r.json(); });
  }
  function defaultWsUrl() {
    var base = localStorage.getItem('dunes_ws_base') || '';
    if (base) return base;
    var api = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    return api.replace(/\/api\/v1\/?$/, '') + '/connection/websocket';
  }
  function personCls(seed) {
    var n = Math.abs(Number(seed) || 0) % 6;
    return 'person-' + ['a', 'b', 'c', 'd', 'e', 'f'][n];
  }
  function deptTitleHtml(dept, title) {
    var parts = [];
    if (dept) parts.push(dept);
    if (title) parts.push(title);
    if (!parts.length) return '';
    return ' <span class="role">' + esc(parts.join(' · ')) + '</span>';
  }
  function readStatusHtml(msgId, peerLastRead) {
    var id = Number(msgId);
    var lr = Number(peerLastRead || 0);
    if (!id) return '';
    if (lr >= id) return '<div class="msg-read-status read">已读</div>';
    return '<div class="msg-read-status unread">未读</div>';
  }
  function msgTimeLabel(at) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  }
  function twemojiCodepoints(ch) {
    var cps = [];
    for (var i = 0; i < ch.length; ) {
      var cp = ch.codePointAt(i);
      i += cp > 0xffff ? 2 : 1;
      if (cp === 0xfe0f) continue;
      cps.push(cp.toString(16));
    }
    return cps.join('-');
  }
  function twemojiImgUrl(ch) {
    var slug = twemojiCodepoints(ch);
    if (!slug) return '';
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/' + slug + '.png';
  }
  function msgCreatedAt(m) {
    if (!m) return '';
    var at = m.createdAt != null ? m.createdAt : m.created_at;
    if (at == null || at === '') return '';
    if (typeof at === 'number') {
      var nd = new Date(at);
      return isNaN(nd.getTime()) ? '' : nd.toISOString();
    }
    return String(at);
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
  function lastMessageCreatedAt(box) {
    if (!box) return null;
    var i = box.children.length;
    while (i--) {
      var el = box.children[i];
      if (!el || el.classList.contains('msg-date-divider')) continue;
      if (el.id === 'dunes-load-newer-msgs' || el.id === 'dunes-load-more-msgs') continue;
      var at = el.getAttribute('data-created-at');
      if (at) return at;
    }
    return null;
  }
  function ensureLeadingDateDivider(box) {
    if (!box) return;
    var firstMsg = box.querySelector('[data-message-id]');
    if (!firstMsg) return;
    var at = firstMsg.getAttribute('data-created-at') || '';
    if (!at) return;
    var prev = firstMsg.previousElementSibling;
    if (prev && prev.classList.contains('msg-date-divider')) return;
    if (prev && prev.id === 'dunes-load-more-msgs') {
      var prev2 = prev.previousElementSibling;
      if (prev2 && prev2.classList.contains('msg-date-divider')) return;
    }
    var label = dayDividerLabel(at, null);
    if (!label) return;
    box.insertBefore(createDateDivider(label), firstMsg);
  }
  function insertDateDividerIfNeeded(box, createdAt, beforeNode) {
    if (!box || !createdAt) return null;
    var prevAt = null;
    if (beforeNode) {
      var sib = beforeNode.previousElementSibling;
      while (sib && sib.classList.contains('msg-date-divider')) sib = sib.previousElementSibling;
      if (sib) prevAt = sib.getAttribute('data-created-at');
    } else {
      prevAt = lastMessageCreatedAt(box);
    }
    var label = dayDividerLabel(createdAt, prevAt);
    if (!label) return null;
    var div = createDateDivider(label);
    if (beforeNode) box.insertBefore(div, beforeNode);
    else {
      var newerHint = document.getElementById('dunes-load-newer-msgs');
      if (newerHint && newerHint.parentNode === box) box.insertBefore(div, newerHint);
      else box.appendChild(div);
    }
    return div;
  }
  function normalizeMsg(m) {
    if (!m) return m;
    if (m.createdAt == null && m.created_at != null) m.createdAt = m.created_at;
    var p = m.payload;
    if (typeof p === 'string' && p) {
      try { m.payload = JSON.parse(p); } catch (e) { m.payload = null; }
    }
    return ensureMessageSender(m);
  }
  function stripLegacyAttachHandlers(screenId) {
    var prefix = screenId === 'C2' ? 'c2' : 'c5';
    var slot = document.getElementById(prefix + '-upload-slot');
    var btn = document.getElementById(prefix + '-attach-btn');
    if (slot && slot.parentNode) {
      var ns = slot.cloneNode(true);
      ns.hidden = true;
      ns.id = prefix + '-upload-slot';
      if (slot.accept) ns.accept = slot.accept;
      if (slot.dataset.bucket) ns.dataset.bucket = slot.dataset.bucket;
      slot.parentNode.replaceChild(ns, slot);
    }
    if (btn && btn.parentNode) {
      var nb = btn.cloneNode(true);
      nb.id = prefix + '-attach-btn';
      nb.className = btn.className;
      nb.innerHTML = btn.innerHTML;
      if (btn.title) nb.title = btn.title;
      btn.parentNode.replaceChild(nb, btn);
    }
  }
  function isPublicMediaUrl(value) {
    return /^https?:\/\//i.test(String(value || '').trim());
  }
  function storageGetEndpoint(objectKey, bucket) {
    if (!objectKey) return '';
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    return base + '/storage/presigned-get?bucket=' + encodeURIComponent(bucket || 'im-attachments') + '&objectKey=' + encodeURIComponent(objectKey);
  }
  function storageDownloadEndpoint(objectKey, bucket, fileName) {
    if (!objectKey) return '';
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    var q = 'bucket=' + encodeURIComponent(bucket || 'im-attachments') + '&objectKey=' + encodeURIComponent(objectKey);
    if (fileName) q += '&fileName=' + encodeURIComponent(fileName);
    return base + '/storage/download?' + q;
  }
  async function resolveAttachmentUrl(el) {
    var objectKey = el.getAttribute('data-object-key') || '';
    var url = el.getAttribute('data-url') || '';
    if (isPublicMediaUrl(url)) return url;
    if (isPublicMediaUrl(objectKey)) return objectKey;
    if (!objectKey) return url;
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var r = await fetch(storageGetEndpoint(objectKey, el.getAttribute('data-bucket') || 'im-attachments'), {
      headers: token ? { Authorization: 'Bearer ' + token } : {}
    });
    var j = await r.json();
    url = j && j.success && j.data && j.data.url ? j.data.url : '';
    if (url) el.setAttribute('data-url', url);
    return url;
  }
  async function hydrateMediaUrls(root) {
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
        } else if (el.classList && el.classList.contains('dunes-attach-link')) {
          el.setAttribute('href', pub);
        }
        continue;
      }
      if (!key || el.dataset.hydrated === '1') continue;
      try {
        var url = await resolveAttachmentUrl(el);
        if (!url) continue;
        el.dataset.hydrated = '1';
        if (el.tagName === 'IMG') {
          el.src = url;
          el.setAttribute('data-full-url', url);
        } else if (el.classList && el.classList.contains('dunes-attach-link')) {
          el.setAttribute('data-url', url);
          el.setAttribute('href', storageDownloadEndpoint(key, el.getAttribute('data-bucket') || 'im-attachments', el.getAttribute('data-file-name') || ''));
        }
      } catch (e) {}
    }
  }
  async function openAttachmentUrl(url, fileName, objectKey, bucket) {
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    if (isPublicMediaUrl(objectKey)) {
      window.open(objectKey, '_blank', 'noopener');
      return;
    }
    if (isPublicMediaUrl(url)) {
      window.open(url, '_blank', 'noopener');
      return;
    }
    if (objectKey) {
      try {
        var dl = storageDownloadEndpoint(objectKey, bucket || 'im-attachments', fileName);
        var resp = await fetch(dl, { headers: token ? { Authorization: 'Bearer ' + token } : {} });
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        var blob = await resp.blob();
        var blobUrl = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = blobUrl;
        a.download = fileName || 'download';
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(function () { URL.revokeObjectURL(blobUrl); }, 2000);
        return;
      } catch (e) {
        console.warn('[DunesImChat] proxy download failed, fallback presigned', e);
      }
    }
    if (!url) return;
    try {
      var r = await fetch(url, { mode: 'cors' });
      if (r.ok) {
        var b = await r.blob();
        var u = URL.createObjectURL(b);
        var link = document.createElement('a');
        link.href = u;
        link.download = fileName || 'download';
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(function () { URL.revokeObjectURL(u); }, 2000);
        return;
      }
    } catch (e2) {}
    var fallback = document.createElement('a');
    fallback.href = url;
    fallback.target = '_blank';
    fallback.rel = 'noopener';
    if (fileName) fallback.download = fileName;
    document.body.appendChild(fallback);
    fallback.click();
    fallback.remove();
  }
  function renderMsg(m, peer, peerLastRead) {
    normalizeMsg(m);
    var me = devUserId();
    var sent = isSentByMe(m);
    var senderId = msgSenderId(m);
    var name = senderDisplayName(m, peer);
    var body = esc(m.bodyText || '');
    var payload = m.payload || null;
    var row = document.createElement('div');
    row.dataset.messageId = m.id || '';
    if (m.recalled) {
      row.className = 'msg-system';
      row.innerHTML = '<span class="pill">该消息已撤回</span>';
      return row;
    }
    if (m.kind === 'SYSTEM' || m.kind === 'SYSTEM_JOIN' || m.kind === 'SYSTEM_LEAVE' || m.kind === 'SYSTEM_REMOVE' || m.kind === 'SYSTEM_FLOW') {
      row.className = 'msg-system';
      row.innerHTML = '<span class="pill">' + body + '</span>';
      return row;
    }
    var myInitial = myDisplayName().slice(0, 1);
    var avInitial = name.slice(0, 1) || '?';
    var peerTag = '';
    if (!sent && m.sender) {
      peerTag = deptTitleHtml(m.sender.departmentName || (peer && peer.departmentName), m.sender.title || m.sender.roleLabel || (peer && (peer.title || peer.roleLabel)));
    }
    var t = msgTimeLabel(m.createdAt);
    if (m.kind === 'IMAGE' && payload && (payload.objectKey || payload.previewUrl || payload.url)) {
      row.className = 'msg-row ' + (sent ? 'sent' : 'recv');
      var mediaUrl = payload.url || payload.previewUrl || payload.objectKey || '';
      var direct = isPublicMediaUrl(mediaUrl);
      var imgKey = direct ? '' : (payload.objectKey || '');
      var src = direct ? esc(mediaUrl) : '';
      var full = esc(mediaUrl);
      var bubble = '<div class="msg-bubble ' + (sent ? 'sent' : 'recv') + '">'
        + '<img src="' + src + '" alt="image" class="dunes-img-thumb" data-full-url="' + full + '"'
        + ' data-object-key="' + esc(imgKey) + '" data-bucket="im-attachments"'
        + ' style="max-width:170px;max-height:170px;border-radius:10px;display:block;cursor:pointer">'
        + '</div>';
      var read = sent ? readStatusHtml(m.id, peerLastRead) : '';
      if (sent) {
        row.innerHTML = '<div class="msg-av-sm ' + personCls(me) + '">' + esc(myInitial) + '</div><div class="msg-content">' + bubble + read + '</div>';
      } else {
        row.innerHTML = '<div class="msg-av-sm ' + personCls(senderId || (peer && peer.userId)) + '">' + esc(avInitial) + '</div><div class="msg-content"><div class="msg-meta"><span class="nm">' + esc(name) + '</span>' + peerTag + '<span>' + esc(t) + '</span></div>' + bubble + '</div>';
      }
      return row;
    }
    if (m.kind === 'AUDIO') {
      row.className = 'msg-row ' + (sent ? 'sent' : 'recv');
      var sec = Math.max(1, Number((payload && payload.durationSec) || String(m.bodyText || '').replace(/\D/g, '') || 1));
      var audioUrl = payload && (payload.url || (isPublicMediaUrl(payload.objectKey) ? payload.objectKey : '')) ? (payload.url || payload.objectKey) : '';
      var audioKey = payload && payload.objectKey && !isPublicMediaUrl(payload.objectKey) ? payload.objectKey : '';
      var voice = '<div class="msg-bubble ' + (sent ? 'sent' : 'recv') + ' dunes-voice-bubble" data-url="' + esc(audioUrl) + '" data-object-key="' + esc(audioKey) + '" data-bucket="im-attachments">'
        + (sent ? '<span class="voice-sec">' + sec + '\'\'</span><span class="voice-wave"><i class="ti ti-volume"></i></span>' : '<span class="voice-wave"><i class="ti ti-volume"></i></span><span class="voice-sec">' + sec + '\'\'</span>')
        + '</div>';
      var read = sent ? readStatusHtml(m.id, peerLastRead) : '';
      if (sent) {
        row.innerHTML = '<div class="msg-av-sm ' + personCls(me) + '">' + esc(myInitial) + '</div><div class="msg-content">' + voice + read + '</div>';
      } else {
        row.innerHTML = '<div class="msg-av-sm ' + personCls(senderId || (peer && peer.userId)) + '">' + esc(avInitial) + '</div><div class="msg-content"><div class="msg-meta"><span class="nm">' + esc(name) + '</span>' + peerTag + '<span>' + esc(t) + '</span></div>' + voice + '</div>';
      }
      return row;
    }
    if (m.kind === 'FILE' && payload && (payload.url || payload.objectKey)) {
      row.className = 'msg-row ' + (sent ? 'sent' : 'recv');
      var icon = 'ti-paperclip';
      var fileName = (payload.fileName || m.bodyText || '附件');
      var fileUrl = payload.url || payload.objectKey || '';
      var objKey = isPublicMediaUrl(fileUrl) ? '' : (payload.objectKey || '');
      var href = isPublicMediaUrl(fileUrl)
        ? esc(fileUrl)
        : (objKey
        ? storageDownloadEndpoint(objKey, 'im-attachments', fileName)
        : esc(payload.url || ''));
      var bubble = '<div class="msg-bubble ' + (sent ? 'sent' : 'recv') + '"><i class="ti ' + icon + '"></i> <a class="dunes-attach-link" href="' + esc(href) + '" data-url="' + esc(payload.url || '') + '" data-object-key="' + esc(payload.objectKey || '') + '" data-bucket="im-attachments" data-file-name="' + esc(fileName) + '" target="_blank" rel="noopener" download>' + body + '</a></div>';
      var read = sent ? readStatusHtml(m.id, peerLastRead) : '';
      if (sent) {
        row.innerHTML = '<div class="msg-av-sm ' + personCls(me) + '">' + esc(myInitial) + '</div><div class="msg-content">' + bubble + read + '</div>';
      } else {
        row.innerHTML = '<div class="msg-av-sm ' + personCls(senderId || (peer && peer.userId)) + '">' + esc(avInitial) + '</div><div class="msg-content"><div class="msg-meta"><span class="nm">' + esc(name) + '</span>' + peerTag + '<span>' + esc(t) + '</span></div>' + bubble + '</div>';
      }
      return row;
    }
    if (sent) {
      row.className = 'msg-row sent';
      var recall = '';
      if (m.createdAt && Date.now() - new Date(m.createdAt).getTime() < 120000) {
        recall = '<button type="button" class="im-recall-btn" data-msg-id="' + m.id + '" style="font-size:10px;color:var(--text-3);background:none;border:none;cursor:pointer;margin-top:2px">撤回</button>';
      }
      var read = readStatusHtml(m.id, peerLastRead);
      var sentName = name || myDisplayName();
      row.innerHTML = '<div class="msg-av-sm ' + personCls(me) + '">' + esc(myInitial) + '</div><div class="msg-content"><div class="msg-meta"><span>' + esc(t) + '</span><span class="nm">' + esc(sentName) + '</span></div><div class="msg-bubble sent">' + body + '</div>' + read + recall + '</div>';
    } else {
      row.className = 'msg-row recv';
      row.innerHTML = '<div class="msg-av-sm ' + personCls(senderId || (peer && peer.userId)) + '">' + esc(avInitial) + '</div><div class="msg-content"><div class="msg-meta"><span class="nm">' + esc(name) + '</span>' + peerTag + '<span>' + esc(t) + '</span></div><div class="msg-bubble recv">' + body + '</div></div>';
    }
    return row;
  }
  function ensureImageViewer() {
    var viewer = document.getElementById('dunes-image-viewer');
    if (viewer) return viewer;
    viewer = document.createElement('div');
    viewer.id = 'dunes-image-viewer';
    viewer.className = 'dunes-image-viewer';
    viewer.innerHTML = '<button type="button" class="dunes-image-close" aria-label="关闭"><i class="ti ti-x"></i></button>'
      + '<div class="dunes-image-stage"><img class="dunes-image-full" alt="preview"></div>';
    document.body.appendChild(viewer);
    var closeBtn = viewer.querySelector('.dunes-image-close');
    var stage = viewer.querySelector('.dunes-image-stage');
    var img = viewer.querySelector('.dunes-image-full');
    var state = {
      scale: 1,
      tx: 0,
      ty: 0,
      startX: 0,
      startY: 0,
      baseTx: 0,
      baseTy: 0,
      pinchStartDist: 0,
      pinchStartScale: 1,
      dragging: false,
      lastTapAt: 0
    };
    function applyTransform() {
      img.style.transform = 'translate(' + state.tx + 'px,' + state.ty + 'px) scale(' + state.scale + ')';
    }
    function resetTransform() {
      state.scale = 1;
      state.tx = 0;
      state.ty = 0;
      applyTransform();
    }
    function closeViewer() {
      viewer.classList.remove('show');
      img.removeAttribute('src');
      resetTransform();
    }
    function openViewer(url) {
      if (!url) return;
      img.src = url;
      viewer.classList.add('show');
      resetTransform();
    }
    viewer.addEventListener('click', function (e) {
      if (e.target === viewer || e.target === stage) closeViewer();
    });
    closeBtn.addEventListener('click', function (e) {
      e.preventDefault();
      closeViewer();
    });
    img.addEventListener('touchstart', function (e) {
      if (e.touches.length === 2) {
        var dx = e.touches[1].clientX - e.touches[0].clientX;
        var dy = e.touches[1].clientY - e.touches[0].clientY;
        state.pinchStartDist = Math.hypot(dx, dy);
        state.pinchStartScale = state.scale;
        state.dragging = false;
      } else if (e.touches.length === 1 && state.scale > 1) {
        state.dragging = true;
        state.startX = e.touches[0].clientX;
        state.startY = e.touches[0].clientY;
        state.baseTx = state.tx;
        state.baseTy = state.ty;
      }
    }, { passive: true });
    img.addEventListener('touchmove', function (e) {
      if (e.touches.length === 2) {
        var dx = e.touches[1].clientX - e.touches[0].clientX;
        var dy = e.touches[1].clientY - e.touches[0].clientY;
        var dist = Math.hypot(dx, dy);
        if (state.pinchStartDist > 0) {
          state.scale = Math.max(1, Math.min(4, state.pinchStartScale * dist / state.pinchStartDist));
          applyTransform();
          e.preventDefault();
        }
      } else if (state.dragging && e.touches.length === 1) {
        var x = e.touches[0].clientX;
        var y = e.touches[0].clientY;
        state.tx = state.baseTx + (x - state.startX);
        state.ty = state.baseTy + (y - state.startY);
        applyTransform();
        e.preventDefault();
      }
    }, { passive: false });
    img.addEventListener('touchend', function () {
      state.dragging = false;
      var now = Date.now();
      if (now - state.lastTapAt < 300) {
        if (state.scale > 1) {
          state.scale = 1;
          state.tx = 0;
          state.ty = 0;
        } else {
          state.scale = 2;
        }
        applyTransform();
      }
      state.lastTapAt = now;
    }, { passive: true });
    img.addEventListener('wheel', function (e) {
      e.preventDefault();
      var delta = e.deltaY > 0 ? -0.15 : 0.15;
      state.scale = Math.max(1, Math.min(4, state.scale + delta));
      applyTransform();
    }, { passive: false });
    window.__dunesOpenImageViewer = openViewer;
    window.__dunesCloseImageViewer = closeViewer;
    return viewer;
  }
  function screenIdFromBox(box) {
    if (!box) return '';
    if (box.id === 'c2-api-rows') return 'C2';
    if (box.id === 'c5-api-rows') return 'C5';
    return '';
  }
  function scrollChatToBottom(screenId, opts) {
    opts = opts || {};
    if (isHistoryLocatedChat() && !opts.force) return;
    var stream = document.querySelector('.screen[data-screen="' + screenId + '"] .msg-stream');
    if (!stream) return;
    var box = msgBoxForScreen(screenId);
    function doScroll() {
      stream.scrollTop = stream.scrollHeight;
      if (box) {
        var last = box.querySelector('[data-message-id]:last-of-type') || box.lastElementChild;
        if (last && last.scrollIntoView) {
          try { last.scrollIntoView({ block: 'end', behavior: 'auto' }); } catch (e) { last.scrollIntoView(false); }
        }
      }
    }
    requestAnimationFrame(function () {
      doScroll();
      requestAnimationFrame(doScroll);
    });
    if (!opts.gentle) {
      [0, 50, 150, 320].forEach(function (ms) { setTimeout(doScroll, ms); });
    }
  }
  function bindChatImageLoadScroll(root, screenId) {
    if (!root || !screenId) return;
    root.querySelectorAll('img.dunes-img-thumb').forEach(function (img) {
      if (img.dataset.scrollWired) return;
      img.dataset.scrollWired = '1';
      img.addEventListener('load', function () {
        if (!isHistoryLocatedChat() && isLatestChatView()) scrollChatToBottom(screenId, { gentle: true });
      });
    });
  }
  function wireImageThumbs(root) {
    if (!root) return;
    ensureImageViewer();
    root.querySelectorAll('.dunes-img-thumb[data-full-url]').forEach(function (img) {
      if (img.dataset.wiredOpen) return;
      img.dataset.wiredOpen = '1';
      img.addEventListener('click', async function () {
        var u = img.getAttribute('data-full-url') || '';
        if (img.getAttribute('data-object-key')) {
          try { u = await resolveAttachmentUrl(img) || u; } catch (e) {}
        }
        if (u && window.__dunesOpenImageViewer) window.__dunesOpenImageViewer(u);
      });
    });
    bindChatImageLoadScroll(root, screenIdFromBox(root));
  }
  function wireAttachmentInteractions(root) {
    if (!root) return;
    root.querySelectorAll('.dunes-attach-link').forEach(function (a) {
      if (a.dataset.wiredAttach) return;
      a.dataset.wiredAttach = '1';
      a.addEventListener('click', async function (e) {
        e.preventDefault();
        e.stopPropagation();
        try {
          var objectKey = a.getAttribute('data-object-key') || '';
          var fileName = a.getAttribute('data-file-name') || '';
          var bucket = a.getAttribute('data-bucket') || 'im-attachments';
          if (objectKey) {
            await openAttachmentUrl('', fileName, objectKey, bucket);
            return;
          }
          var url = await resolveAttachmentUrl(a);
          if (!url) {
            alert('文件地址不可用');
            return;
          }
          await openAttachmentUrl(url, fileName, '', bucket);
        } catch (err) {
          alert('打开文件失败：' + (err.message || err));
        }
      });
    });
    root.querySelectorAll('.dunes-voice-bubble').forEach(function (b) {
      if (b.dataset.wiredVoice) return;
      b.dataset.wiredVoice = '1';
      b.addEventListener('click', async function (e) {
        e.preventDefault();
        e.stopPropagation();
        try {
          var url = await resolveAttachmentUrl(b);
          if (!url) {
            alert('这条语音没有音频文件，请重新发送');
            return;
          }
          if (window.__dunesVoicePlaying && window.__dunesVoicePlaying !== b) {
            window.__dunesVoicePlaying.classList.remove('playing');
          }
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
          await window.__dunesVoiceAudio.play();
        } catch (err) {
          b.classList.remove('playing');
          alert('播放语音失败：' + (err.message || err));
        }
      });
    });
  }
  function refreshReadStatuses() {
    var box = activeMsgBox();
    if (!box) return;
    var lr = window.__dunesPeerLastRead || 0;
    box.querySelectorAll('.msg-row.sent').forEach(function (row) {
      var old = row.querySelector('.msg-read-status');
      if (old) old.remove();
      var content = row.querySelector('.msg-content');
      if (!content) return;
      var html = readStatusHtml(row.dataset.messageId, lr);
      if (html) content.insertAdjacentHTML('beforeend', html);
    });
  }
  function activeChatScreenId() {
    var active = document.querySelector('.screen.active');
    return active && active.dataset.screen;
  }
  function activeMsgBox() {
    var sid = activeChatScreenId();
    if (sid === 'C2') return document.getElementById('c2-api-rows');
    if (sid === 'C5') return document.getElementById('c5-api-rows');
    return null;
  }
  function msgBoxForScreen(screenId) {
    return document.getElementById(screenId === 'C2' ? 'c2-api-rows' : 'c5-api-rows');
  }
  function isServerChannel(ch) {
    return !!(ch && imServerChannels[ch]);
  }
  function maxDomMessageId(box) {
    var maxId = 0;
    if (!box) return 0;
    box.querySelectorAll('[data-message-id]').forEach(function (el) {
      var rid = Number(el.dataset.messageId);
      if (rid && rid > maxId) maxId = rid;
    });
    return maxId;
  }
  function insertMessageInOrder(box, node, msgId) {
    var id = Number(msgId);
    if (!id) {
      box.appendChild(node);
      return;
    }
    if (box.querySelector('[data-message-id="' + id + '"]')) return;
    var maxId = maxDomMessageId(box);
    var newerHint = document.getElementById('dunes-load-newer-msgs');
    if (id > maxId) {
      if (newerHint && newerHint.parentNode === box) box.insertBefore(node, newerHint);
      else box.appendChild(node);
      return;
    }
    var rows = box.querySelectorAll('[data-message-id]');
    for (var i = 0; i < rows.length; i++) {
      var rid = Number(rows[i].dataset.messageId);
      if (rid && rid > id) {
        box.insertBefore(node, rows[i]);
        return;
      }
    }
    if (newerHint && newerHint.parentNode === box) box.insertBefore(node, newerHint);
    else box.appendChild(node);
  }
  function syncMessagesToDom(box, items, peer, screenId) {
    if (!box || !items || !items.length) return;
    var domIds = {};
    box.querySelectorAll('[data-message-id]').forEach(function (el) {
      var rid = Number(el.dataset.messageId);
      if (rid) domIds[rid] = true;
    });
    items.forEach(function (m) {
      normalizeMsg(m);
      if (!m.id || domIds[m.id]) return;
      var node = renderMsg(m, peer, window.__dunesPeerLastRead);
      if (node && node.classList) {
        node.setAttribute('data-msg-id', String(m.id || ''));
        node.setAttribute('data-created-at', msgCreatedAt(m));
      }
      insertMessageInOrder(box, node, m.id);
      domIds[m.id] = true;
      if (m.id > (window.__dunesMsgNewestId || 0)) window.__dunesMsgNewestId = m.id;
    });
    wireImageThumbs(box);
    wireAttachmentInteractions(box);
    hydrateMediaUrls(box);
  }
  function appendRealtimeMessage(msg, screenId, convId) {
    if (!msg || !msg.id) return;
    convId = Number(convId || currentPendingConvId() || 0);
    if (!convId) return;
    msg.conversationId = convId;
    var sid = screenId || activeChatScreenId();
    if (sid !== 'C2' && sid !== 'C5') return;
    var box = msgBoxForScreen(sid);
    if (!boxMatchesConv(box, convId)) return;
    if (box.querySelector('[data-message-id="' + msg.id + '"]')) return;
    if (!box.querySelector('[data-message-id]')) {
      box.innerHTML = '';
      markMsgBoxConv(box, convId);
    }
    var peer = window.__dunesChatPeer;
    normalizeMsg(msg);
    var node = renderMsg(msg, peer, window.__dunesPeerLastRead);
    if (node && node.classList) {
      node.setAttribute('data-msg-id', String(msg.id || ''));
      node.setAttribute('data-created-at', msgCreatedAt(msg));
    }
    if (isLatestChatView()) appendMessageTail(box, node, msg);
    else {
      insertMessageInOrder(box, node, msg.id);
      insertDateDividerIfNeeded(box, msgCreatedAt(msg) || node.getAttribute('data-created-at'), node);
    }
    wireImageThumbs(box);
    wireAttachmentInteractions(box);
    hydrateMediaUrls(box);
    wireRecall(box, screenId);
    if (isLatestChatView()) scrollChatToBottom(sid);
  }
  function rtEventKey(data) {
    if (!data || !data.type) return '';
    if ((data.type === 'message' || data.type === 'system_flow') && data.message && data.message.id) {
      return data.type + ':' + data.message.id;
    }
    if (data.type === 'message_recalled' && data.message && data.message.id) {
      return 'recall:' + data.message.id;
    }
    if (data.type === 'message_updated' && data.message && data.message.id) {
      return 'updated:' + data.message.id;
    }
    if (data.type === 'message_deleted' && data.messageId) {
      return 'deleted:' + data.messageId;
    }
    if (data.type === 'read' && data.conversationId && data.userId) {
      return 'read:' + data.conversationId + ':' + data.userId + ':' + (data.lastReadMessageId || 0);
    }
    if (data.type === 'notification' && data.title) {
      return 'notification:' + data.title + ':' + (data.body || '');
    }
    return '';
  }
  function consumeRtEvent(data) {
    var key = rtEventKey(data);
    if (!key) return true;
    if (!window.__dunesRtSeen) window.__dunesRtSeen = {};
    var now = Date.now();
    if (window.__dunesRtSeen[key] && now - window.__dunesRtSeen[key] < 60000) return false;
    window.__dunesRtSeen[key] = now;
    var keys = Object.keys(window.__dunesRtSeen);
    if (keys.length > 200) {
      keys.forEach(function (k) {
        if (now - window.__dunesRtSeen[k] > 120000) delete window.__dunesRtSeen[k];
      });
    }
    return true;
  }
  function markRtEventSeen(data) {
    var key = rtEventKey(data);
    if (!key) return;
    if (!window.__dunesRtSeen) window.__dunesRtSeen = {};
    window.__dunesRtSeen[key] = Date.now();
  }
  function handleRealtimePayload(data, channel) {
    if (!data || !data.type) return;
    var active = document.querySelector('.screen.active');
    var sid = active && active.dataset.screen;
    var activeConvId = Number(currentPendingConvId() || window.__dunesActiveConvId || 0);
    var eventConvId = convIdFromRealtime(data, channel);
    var inThisChat = eventConvId > 0 && activeConvId > 0 && eventConvId === activeConvId
      && (sid === 'C2' || sid === 'C5');
    if (sid === 'C1' && (data.type === 'message' || data.type === 'system_flow') && isConvChannel(channel)) {
      return;
    }
    if (!consumeRtEvent(data)) return;
    if ((data.type === 'message' || data.type === 'system_flow') && data.message) {
      if (eventConvId) data.message.conversationId = eventConvId;
      if (inThisChat) {
        var box = msgBoxForScreen(sid);
        var mid = data.message.id;
        if (boxMatchesConv(box, eventConvId) && !(mid && box.querySelector('[data-message-id="' + mid + '"]'))) {
          appendRealtimeMessage(data.message, sid, eventConvId);
          afterReadInChat(activeConvId);
          var fromPeer = data.message.sender && Number(data.message.sender.userId) !== devUserId();
          if (fromPeer) refreshPeerReadFromServer(activeConvId);
        } else if (!boxMatchesConv(box, eventConvId)) {
          markRtEventSeen(data);
        } else {
          markRtEventSeen(data);
        }
      } else if (window.DunesInbox) {
        if (typeof window.DunesInbox.applyConvEvent === 'function') {
          window.DunesInbox.applyConvEvent(data);
        } else if (typeof window.DunesInbox.scheduleCommBadgeRefresh === 'function') {
          window.DunesInbox.scheduleCommBadgeRefresh();
        }
      }
    }
    if (data.type === 'conversation_updated') {
      if (window.DunesInbox && typeof window.DunesInbox.applyConvEvent === 'function') {
        window.DunesInbox.applyConvEvent(data);
      } else if (window.DunesInbox && typeof window.DunesInbox.scheduleCommBadgeRefresh === 'function') {
        window.DunesInbox.scheduleCommBadgeRefresh();
      }
    }
    if (data.type === 'message_recalled' && data.message && activeConvId && String(data.conversationId) === String(activeConvId)) {
      if (sid === 'C2' || sid === 'C5') {
        if (!patchRecalledMessage(data.message.id)) loadChat(sid);
      }
    }
    if (data.type === 'message_updated' && data.message && inThisChat) {
      if (sid === 'C2' || sid === 'C5') {
        if (!patchUpdatedMessage(data.message, sid)) loadChat(sid);
      }
    }
    if (data.type === 'message_deleted' && activeConvId && String(data.conversationId) === String(activeConvId)) {
      if (sid === 'C2' || sid === 'C5') {
        var mid = data.messageId || (data.message && data.message.id);
        if (!removeDeletedMessage(mid)) loadChat(sid);
      }
    }
    if (data.type === 'read' && activeConvId && String(data.conversationId) === String(activeConvId)) {
      var uid = Number(data.userId);
      if (uid && uid !== devUserId()) {
        window.__dunesPeerLastRead = Number(data.lastReadMessageId || 0);
        refreshReadStatuses();
      }
      if (inThisChat && window.DunesInbox && window.DunesInbox.patchConvUnread) {
        window.DunesInbox.patchConvUnread(activeConvId, 0);
      }
    }
    if (data.type === 'notification') {
      if (sid === 'Z2' && window.DunesInbox && window.DunesInbox.loadZ2Notifications) {
        window.DunesInbox.loadZ2Notifications();
      } else if (window.DunesInbox && window.DunesInbox.refreshSystemNotifRow) {
        window.DunesInbox.refreshSystemNotifRow();
      } else if (window.DunesApi && window.DunesApi.loadNotifications) {
        window.DunesApi.loadNotifications();
      }
    }
  }
  function presenceUserId(c) {
    if (!c) return '';
    if (c.user != null && c.user !== '') return String(c.user);
    if (c.userId != null && c.userId !== '') return String(c.userId);
    if (c.info) {
      try {
        var info = typeof c.info === 'string' ? JSON.parse(c.info) : c.info;
        if (info && info.userId != null && info.userId !== '') return String(info.userId);
      } catch (e) {}
    }
    if (c.client != null && c.client !== '') return String(c.client);
    return '';
  }
  function isUserOnline(uid) {
    if (!uid) return false;
    if (Number(uid) === devUserId()) return true;
    var map = window.__dunesOnlineUserIds || {};
    return !!map[String(uid)];
  }
  async function markConversationRead(convId) {
    if (!convId) return null;
    try {
      var j = await apiFetch('/conversations/' + convId + '/read', { method: 'POST' });
      if (j.success && j.data && j.data.lastReadMessageId != null) {
        return Number(j.data.lastReadMessageId);
      }
      return j.success ? true : null;
    } catch (e) { return null; }
  }
  async function refreshPeerReadFromServer(convId) {
    if (!convId) return;
    try {
      var j = await apiFetch('/conversations/' + convId);
      if (j.success && j.data && j.data.peerLastReadMessageId != null) {
        window.__dunesPeerLastRead = Number(j.data.peerLastReadMessageId);
        refreshReadStatuses();
      }
    } catch (e) {}
  }
  function maybeAssumePeerReadInActiveChat() {
    var active = document.querySelector('.screen.active');
    var sid = active && active.dataset.screen;
    if (sid !== 'C5' && sid !== 'C2') return;
    if (!window.__dunesChatPeer) return;
    if (!isUserOnline(window.__dunesChatPeer.userId)) return;
    var box = document.getElementById(sid === 'C2' ? 'c2-api-rows' : 'c5-api-rows');
    var maxId = window.__dunesPeerLastRead || 0;
    if (box) {
      box.querySelectorAll('.msg-row.sent[data-message-id]').forEach(function (row) {
        var id = Number(row.dataset.messageId);
        if (id > maxId) maxId = id;
      });
    }
    if (maxId > (window.__dunesPeerLastRead || 0)) {
      window.__dunesPeerLastRead = maxId;
      refreshReadStatuses();
    }
  }
  function callChannelPresence(channel, onOk) {
    if (imPresenceDenied || !imCentrifuge || !channel) return;
    var sub = imConvSubs[channel] || (channel === 'online' ? imOnlineSub : null) || existingSub(channel);
    if (sub && typeof sub.presence === 'function') {
      sub.presence().then(function (res) { if (onOk) onOk(res); }).catch(function (err) {
        if (err && (err.code === 103 || String(err.message || err).indexOf('permission') >= 0)) {
          imPresenceDenied = true;
          console.warn('[DunesImChat] presence denied, skip further polls');
        }
      });
      return;
    }
    if (typeof imCentrifuge.presence !== 'function') return;
    imCentrifuge.presence(channel).then(function (res) { if (onOk) onOk(res); }).catch(function (err) {
      if (err && (err.code === 103 || String(err.message || err).indexOf('permission') >= 0)) {
        imPresenceDenied = true;
        console.warn('[DunesImChat] presence denied, skip further polls');
      }
    });
  }
  function syncConvPresence() {
    var activeConvId = currentPendingConvId();
    if (imPresenceDenied || !window.__dunesChatPeer || !activeConvId || !imCentrifuge) return;
    var convCh = rtConvCh(activeConvId);
    var peerId = String(window.__dunesChatPeer.userId);
    callChannelPresence(convCh, function (res) {
      var clients = res && res.clients ? res.clients : {};
      var peerIn = Object.keys(clients).some(function (k) {
        return presenceUserId(clients[k]) === peerId;
      });
      window.__dunesOnlineUserIds = window.__dunesOnlineUserIds || {};
      if (peerIn) {
        window.__dunesOnlineUserIds[peerId] = true;
        maybeAssumePeerReadInActiveChat();
      } else {
        delete window.__dunesOnlineUserIds[peerId];
      }
      refreshAllPresenceUi();
    });
  }
  function afterReadInChat(convId) {
    if (!convId) return Promise.resolve();
    return markConversationRead(convId).then(function () {
      if (window.DunesInbox && window.DunesInbox.patchConvUnread) {
        window.DunesInbox.patchConvUnread(convId, 0);
      }
      return refreshPeerReadFromServer(convId);
    });
  }
  function teardownConvSubs() {
    Object.keys(imConvSubs).forEach(function (ch) {
      try { imConvSubs[ch].unsubscribe(); imConvSubs[ch].removeAllListeners(); } catch (e) {}
      delete imConvSubs[ch];
    });
    imConvSub = null;
  }
  function teardownImSubs() {
    teardownConvSubs();
    if (imUserSub) { try { imUserSub.unsubscribe(); imUserSub.removeAllListeners(); } catch (e) {} imUserSub = null; }
    if (imOnlineSub) { try { imOnlineSub.unsubscribe(); imOnlineSub.removeAllListeners(); } catch (e) {} imOnlineSub = null; }
  }
  function existingSub(channel) {
    if (!imCentrifuge || !channel) return null;
    try {
      if (typeof imCentrifuge.getSubscription === 'function') {
        return imCentrifuge.getSubscription(channel);
      }
    } catch (e) {}
    if (imUserSub && imUserSub.channel === channel) return imUserSub;
    if (imConvSubs[channel]) return imConvSubs[channel];
    if (imOnlineSub && channel === 'online') return imOnlineSub;
    return null;
  }
  function ensureSub(channel, onPub) {
    if (!imCentrifuge || !channel) return null;
    var sub = existingSub(channel);
    if (!sub) {
      try { sub = imCentrifuge.newSubscription(channel); } catch (e) {
        sub = existingSub(channel);
        if (!sub) throw e;
      }
    }
    if (onPub) {
      try { sub.removeAllListeners('publication'); } catch (e) {}
      sub.on('publication', onPub);
    }
    if (sub.state !== 'subscribed' && sub.state !== 'subscribing') {
      try { sub.subscribe(); } catch (e) {}
    }
    return sub;
  }
  function applyOnlinePresence() {
    if (imPresenceDenied || !imCentrifuge) return;
    callChannelPresence('online', function (res) {
      var map = {};
      var clients = res && res.clients ? res.clients : {};
      Object.keys(clients).forEach(function (k) {
        var uid = presenceUserId(clients[k]);
        if (uid) map[uid] = true;
      });
      map[String(devUserId())] = true;
      window.__dunesOnlineUserIds = map;
      refreshAllPresenceUi();
    });
  }
  function refreshPrivateHeaderOnlineOnly() {
    var peer = window.__dunesChatPeer;
    if (!peer) return;
    var screen = document.querySelector('.screen[data-screen="C5"]');
    if (!screen) return;
    var av = screen.querySelector('.cv-av-mini');
    var sub = screen.querySelector('.cv-sub');
    var on = isUserOnline(peer.userId);
    if (av) {
      var dot = av.querySelector('.av-dot');
      if (dot) dot.classList.toggle('on', !!on);
    }
    if (sub) {
      var parts = [];
      if (peer.departmentName) parts.push(peer.departmentName);
      if (peer.title || peer.roleLabel) parts.push(peer.title || peer.roleLabel);
      parts.push(on ? '在线' : '离线');
      sub.textContent = parts.join(' · ');
    }
  }
  function refreshC9Presence() {
    var uid = Number(window.pendingContactUserId || 0);
    var av = document.getElementById('c9-ph-av');
    if (!av) return;
    var dot = av.querySelector('.av-dot');
    if (!dot) return;
    if (uid && isUserOnline(uid)) dot.classList.add('on');
    else dot.classList.remove('on');
  }
  function refreshAllPresenceUi() {
    if (window.DunesInbox && typeof window.DunesInbox.refreshC1OnlineDots === 'function') {
      window.DunesInbox.refreshC1OnlineDots();
    }
    if (window.DunesContacts && typeof window.DunesContacts.refreshOnlineDots === 'function') {
      window.DunesContacts.refreshOnlineDots();
    }
    refreshPrivateHeaderOnlineOnly();
    refreshC9Presence();
  }
  function ensureOnlineSubscription() {
    if (!imCentrifuge || !centrifugeCtor()) return;
    if (!isServerChannel('online')) {
      if (!imOnlineSub) {
        imOnlineSub = ensureSub('online');
        if (imOnlineSub) {
          try { imOnlineSub.removeAllListeners('subscribed'); } catch (e) {}
          try { imOnlineSub.removeAllListeners('join'); } catch (e) {}
          try { imOnlineSub.removeAllListeners('leave'); } catch (e) {}
          imOnlineSub.on('subscribed', applyOnlinePresence);
          imOnlineSub.on('join', applyOnlinePresence);
          imOnlineSub.on('leave', applyOnlinePresence);
        }
      }
    } else if (imOnlineSub) {
      try { imOnlineSub.unsubscribe(); imOnlineSub.removeAllListeners(); } catch (e) {}
      imOnlineSub = null;
    }
    applyOnlinePresence();
  }
  function updatePresenceFromSub() {
    if (!window.__dunesChatPeer) return;
    peerOnline = isUserOnline(window.__dunesChatPeer.userId);
    applyPrivateHeader(window.__dunesChatPeer, null);
  }
  function subscribeImChannels(channels) {
    if (!imCentrifuge || !centrifugeCtor()) return;
    imPresenceDenied = false;
    imServerChannels = {};
    (channels || []).forEach(function (ch) { if (ch) imServerChannels[ch] = true; });
    ensureOnlineSubscription();
    var uid = devUserId();
    var userCh = rtUserCh(uid);
    var onPubFor = function (knownCh) { return function (ctx) {
      if (isServerChannel(knownCh)) return;
      var ch = knownCh || (ctx && ctx.channel) || (ctx && ctx.channelName) || '';
      handleRealtimePayload(ctx.data, ch);
    }; };
    if (isServerChannel(userCh)) {
      if (imUserSub) {
        try { imUserSub.unsubscribe(); imUserSub.removeAllListeners(); } catch (e) {}
        imUserSub = null;
      }
    } else {
      imUserSub = ensureSub(userCh, onPubFor(userCh));
    }
    var wantConv = {};
    function trackConv(ch) {
      if (!ch || !isConvChannel(ch)) return;
      wantConv[ch] = true;
      if (isServerChannel(ch)) {
        if (imConvSubs[ch]) {
          try { imConvSubs[ch].unsubscribe(); imConvSubs[ch].removeAllListeners(); } catch (e) {}
          delete imConvSubs[ch];
        }
        return;
      }
      imConvSubs[ch] = ensureSub(ch, onPubFor(ch));
    }
    (channels || []).forEach(trackConv);
    var activeConvId = currentPendingConvId();
    if (activeConvId) trackConv(rtConvCh(activeConvId));
    Object.keys(imConvSubs).forEach(function (ch) {
      if (wantConv[ch]) return;
      try { imConvSubs[ch].unsubscribe(); imConvSubs[ch].removeAllListeners(); } catch (e) {}
      delete imConvSubs[ch];
    });
    if (activeConvId) {
      var convCh = rtConvCh(activeConvId);
      imConvSub = imConvSubs[convCh] || null;
    } else {
      imConvSub = null;
    }
    setTimeout(function () { syncConvPresence(); applyOnlinePresence(); }, 400);
  }
  function disconnectLegacyImWs() {
    try {
      if (typeof window.__dunesDisconnectLegacyIm === 'function') window.__dunesDisconnectLegacyIm();
    } catch (e) {}
  }
  function centrifugeCtor() {
    if (typeof globalThis !== 'undefined' && globalThis.Centrifuge) return globalThis.Centrifuge;
    if (typeof Centrifuge !== 'undefined') return Centrifuge;
    return null;
  }
  function onCentrifugePublication(ctx) {
    if (!ctx) return;
    handleRealtimePayload(ctx.data, ctx.channel || ctx.channelName || '');
  }
  function wireCentrifugeClient(cent, channels) {
    if (!cent) return;
    try { cent.removeAllListeners('publication'); } catch (e) {}
    cent.on('publication', onCentrifugePublication);
    cent.on('connected', function () {
      imWsRetry = 0;
      subscribeImChannels(channels);
      window.__dunesOnlineUserIds = window.__dunesOnlineUserIds || {};
      window.__dunesOnlineUserIds[String(devUserId())] = true;
      applyOnlinePresence();
      if (window.__dunesPresenceTimer) clearInterval(window.__dunesPresenceTimer);
      window.__dunesPresenceTimer = setInterval(function () {
        applyOnlinePresence();
        syncConvPresence();
      }, 12000);
    });
    cent.on('disconnected', function () {
      if (imReconnectTimer) {
        try { clearTimeout(imReconnectTimer); } catch (e) {}
        imReconnectTimer = null;
      }
      var delay = Math.min(30000, 1000 * Math.pow(2, imWsRetry));
      imWsRetry++;
      imReconnectTimer = setTimeout(function () {
        imReconnectTimer = null;
        connectImRealtime();
      }, delay);
    });
  }
  function imRealtimeState() {
    return imCentrifuge && imCentrifuge.state ? imCentrifuge.state : '';
  }
  function isImRealtimeUp() {
    var st = imRealtimeState();
    return st === 'connected' || st === 'connecting';
  }
  async function connectImRealtime() {
    var Ctor = centrifugeCtor();
    if (!Ctor) {
      console.warn('[DunesImChat] Centrifuge 未加载，无法连接实时通道');
      return;
    }
    if (isImRealtimeUp()) return;
    if (imConnectInflight) return;
    imConnectInflight = true;
    disconnectLegacyImWs();
    try {
      var j = await apiFetch('/realtime/connection-token');
      if (!j.success || !j.data || !j.data.token) {
        console.warn('[DunesImChat] connection-token 失败', j);
        return;
      }
      if (isImRealtimeUp()) {
        subscribeImChannels(j.data.channels || []);
        return;
      }
      var wsUrl = j.data.wsUrl || defaultWsUrl();
      var channels = j.data.channels || [];
      console.log('[DunesImChat] connecting', wsUrl);
      if (imCentrifuge) {
        teardownImSubs();
        try { imCentrifuge.disconnect(); } catch (e) {}
        imCentrifuge = null;
      }
      imCentrifuge = new Ctor(wsUrl, {
        token: j.data.token,
        data: { userId: devUserId() }
      });
      imPresenceDenied = false;
      wireCentrifugeClient(imCentrifuge, channels);
      imCentrifuge.connect();
    } catch (e) {
      console.warn('DunesImChat.connectImRealtime', e);
    } finally {
      imConnectInflight = false;
    }
  }
  function resubscribeImRealtime() {
    if (!imCentrifuge || imCentrifuge.state !== 'connected') {
      return connectImRealtime();
    }
    return apiFetch('/realtime/connection-token').then(function (j) {
      if (!j.success || !j.data) return connectImRealtime();
      var channels = j.data.channels || [];
      var activeConvId = currentPendingConvId();
      if (activeConvId) {
        var need = rtConvCh(activeConvId);
        if (channels.indexOf(need) < 0) channels.push(need);
      }
      subscribeImChannels(channels);
    }).catch(function () { return connectImRealtime(); });
  }

  function wireRecall(box, screenId) {
    box.querySelectorAll('.im-recall-btn').forEach(function (btn) {
      if (btn.dataset.wired) return;
      btn.dataset.wired = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        var convId = currentPendingConvId();
        apiFetch('/conversations/' + convId + '/messages/' + btn.dataset.msgId + '/recall', { method: 'POST' })
          .then(function () { loadChat(screenId); });
      });
    });
  }
  function resetMsgStream(screenId) {
    var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
    if (!screen) return null;
    var stream = screen.querySelector('.msg-stream');
    var boxId = screenId === 'C2' ? 'c2-api-rows' : 'c5-api-rows';
    if (stream) stream.innerHTML = '<div id="' + boxId + '"></div>';
    var box = document.getElementById(boxId);
    markMsgBoxConv(box, 0);
    return box;
  }
  var _msgLoadingOlder = false;
  var _msgLoadingNewer = false;
  function ensureChatHistoryBtn(screenId) {
    var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
    if (!screen) return;
    var act = screen.querySelector('.cv-act');
    if (!act) return;
    var btnId = screenId === 'C2' ? 'c2-history-btn' : 'c5-history-btn';
    if (document.getElementById(btnId)) return;
    var btn = document.createElement('div');
    btn.id = btnId;
    btn.className = 'ic-btn tappable';
    btn.title = '查找聊天记录';
    btn.dataset.go = 'C12';
    btn.innerHTML = '<i class="ti ti-history"></i>';
    btn.addEventListener('click', function () {
      window.__dunesHistoryReturnScreen = screenId;
      window.__dunesLocateFromHistory = false;
      window.__dunesFocusMessageId = null;
    }, true);
    act.insertBefore(btn, act.firstChild);
  }
  function sortChatItems(items) {
    if (!items || !items.length) return items || [];
    return items.slice().sort(function (a, b) { return Number(a.id) - Number(b.id); });
  }
  function paintMessages(box, items, peer, prepend, append) {
    if (!box || !items || !items.length) return;
    items = sortChatItems(items);
    var firstExisting = null;
    var prevAt = null;
    if (prepend) {
      firstExisting = box.querySelector('[data-message-id]');
    } else if (append) {
      prevAt = lastMessageCreatedAt(box);
    }
    var lastPrependedAt = null;
    var frag = document.createDocumentFragment();
    items.forEach(function (m) {
      if ((prepend || append) && m.id && box.querySelector('[data-message-id="' + m.id + '"]')) return;
      var at = msgCreatedAt(m);
      var divLabel = dayDividerLabel(at, prevAt);
      if (divLabel) frag.appendChild(createDateDivider(divLabel));
      var node = renderMsg(m, peer, window.__dunesPeerLastRead);
      if (node && node.classList) {
        node.setAttribute('data-msg-id', String(m.id || ''));
        node.setAttribute('data-created-at', at);
      }
      frag.appendChild(node);
      prevAt = at;
      lastPrependedAt = at;
    });
    if (prepend) box.insertBefore(frag, box.firstChild);
    else if (append) box.appendChild(frag);
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
    ensureLeadingDateDivider(box);
    wireImageThumbs(box);
    wireAttachmentInteractions(box);
    var sid = screenIdFromBox(box);
    hydrateMediaUrls(box).then(function () {
      if (!prepend && !append && sid && !isHistoryLocatedChat()) scrollChatToBottom(sid);
    });
  }
  function patchRecalledMessage(msgId) {
    if (!msgId) return false;
    var row = document.querySelector('[data-message-id="' + msgId + '"]')
      || document.querySelector('.msg-row[data-msg-id="' + msgId + '"]');
    if (!row) return false;
    row.className = 'msg-system';
    row.innerHTML = '<span class="pill">该消息已撤回</span>';
    return true;
  }
  function patchUpdatedMessage(msg, screenId) {
    if (!msg || !msg.id) return false;
    var row = document.querySelector('[data-message-id="' + msg.id + '"]')
      || document.querySelector('.msg-row[data-msg-id="' + msg.id + '"]');
    if (!row) return false;
    var box = msgBoxForScreen(screenId);
    if (!box) return false;
    row.remove();
    appendRealtimeMessage(msg, screenId, Number(msg.conversationId || window.__dunesActiveConvId || 0));
    return true;
  }
  function removeDeletedMessage(msgId) {
    if (!msgId) return false;
    var row = document.querySelector('[data-message-id="' + msgId + '"]')
      || document.querySelector('.msg-row[data-msg-id="' + msgId + '"]');
    if (!row) return false;
    row.remove();
    return true;
  }
  async function mergeDomNewerMessages(convId, items, gen) {
    if (!items || !items.length) return items || [];
    var apiMax = items[items.length - 1].id || 0;
    var box = activeMsgBox();
    var domMax = apiMax;
    if (box) {
      box.querySelectorAll('.msg-row[data-message-id]').forEach(function (row) {
        var id = Number(row.dataset.messageId);
        if (id > domMax) domMax = id;
      });
    }
    if (domMax <= apiMax) return items;
    try {
      var mj2 = await apiFetch('/conversations/' + convId + '/messages?after=' + apiMax + '&size=30');
      if (gen !== imLoadGen || Number(window.__dunesActiveConvId) !== Number(convId)) return items;
      var extra = mj2.success && mj2.data ? (mj2.data.items || []) : [];
      if (!extra.length) return items;
      var seen = {};
      items.forEach(function (m) { seen[m.id] = true; });
      extra.forEach(function (m) {
        normalizeMsg(m);
        if (!seen[m.id]) {
          items.push(m);
          seen[m.id] = true;
        }
      });
      items.sort(function (a, b) { return Number(a.id) - Number(b.id); });
      window.__dunesMsgNewestId = items[items.length - 1].id;
    } catch (e) {}
    return items;
  }
  function ensureJumpToLatestBar(screenId) {
    if (!window.__dunesMsgAnchorId && !window.__dunesMsgHasNewer) return;
    var stream = document.querySelector('.screen[data-screen="' + screenId + '"] .msg-stream');
    if (!stream) return;
    var old = document.getElementById('dunes-jump-latest');
    if (old) return;
    var bar = document.createElement('div');
    bar.id = 'dunes-jump-latest';
    bar.className = 'dunes-jump-latest';
    bar.innerHTML = '<button type="button" class="tappable">回到最新消息</button>';
    bar.querySelector('button').addEventListener('click', function () {
      jumpToLatestMessages(screenId);
    });
    stream.appendChild(bar);
  }
  function jumpToLatestMessages(screenId) {
    clearChatLocateState();
    return loadChat(screenId);
  }
  function isHistoryLocatedChat() {
    return !!(window.__dunesLocateFromHistory || window.__dunesMsgAnchorId || window.__dunesMsgHasNewer);
  }
  function clearChatLocateState() {
    window.__dunesLocateFromHistory = false;
    window.__dunesFocusMessageId = null;
    window.__dunesMsgAnchorId = null;
    window.__dunesMsgHasNewer = false;
    var jumpBar = document.getElementById('dunes-jump-latest');
    if (jumpBar) jumpBar.remove();
    var newer = document.getElementById('dunes-load-newer-msgs');
    if (newer) newer.remove();
  }
  function reloadLatestChat(screenId) {
    clearChatLocateState();
    var box = resetMsgStream(screenId);
    if (box) {
      box.innerHTML = '<div class="msg-system"><span class="pill"><i class="ti ti-loader"></i> 加载最新消息…</span></div>';
    }
    return loadChat(screenId);
  }
  function focusMessageInChat(msgId) {
    if (!msgId) return;
    var tries = 0;
    function tryScroll() {
      tries++;
      var row = document.querySelector('[data-message-id="' + msgId + '"]')
        || document.querySelector('.msg-row[data-msg-id="' + msgId + '"]');
      if (!row) {
        if (tries < 8) setTimeout(tryScroll, 80);
        return;
      }
      row.scrollIntoView({ block: 'center', behavior: tries < 2 ? 'auto' : 'smooth' });
      row.classList.add('dunes-msg-focus');
      setTimeout(function () { row.classList.remove('dunes-msg-focus'); }, 2600);
    }
    setTimeout(tryScroll, 50);
  }
  function ensureLoadMoreHint(box, screenId) {
    if (!box) return;
    var old = document.getElementById('dunes-load-more-msgs');
    if (old) old.remove();
    if (!window.__dunesMsgHasMore) return;
    var bar = document.createElement('div');
    bar.id = 'dunes-load-more-msgs';
    bar.className = 'msg-system';
    bar.innerHTML = '<span class="pill tappable" style="cursor:pointer"><i class="ti ti-arrow-up"></i> 上滑或点击加载更早消息</span>';
    bar.querySelector('.pill').addEventListener('click', function () { loadOlderMessages(screenId); });
    box.insertBefore(bar, box.firstChild);
  }
  function ensureLoadNewerHint(box, screenId) {
    if (!box) return;
    var old = document.getElementById('dunes-load-newer-msgs');
    if (old) old.remove();
    if (!window.__dunesMsgHasNewer) return;
    var bar = document.createElement('div');
    bar.id = 'dunes-load-newer-msgs';
    bar.className = 'msg-system';
    bar.innerHTML = '<span class="pill tappable" style="cursor:pointer"><i class="ti ti-arrow-down"></i> 点击加载后续消息</span>';
    bar.querySelector('.pill').addEventListener('click', function () { loadNewerMessages(screenId); });
    box.appendChild(bar);
  }
  async function loadOlderMessages(screenId) {
    var convId = currentPendingConvId();
    if (_msgLoadingOlder || !window.__dunesMsgHasMore || !convId) return;
    var before = window.__dunesMsgOldestId;
    if (!before) return;
    var box = document.getElementById(screenId === 'C2' ? 'c2-api-rows' : 'c5-api-rows');
    var stream = box && box.closest('.msg-stream');
    if (!box) return;
    _msgLoadingOlder = true;
    var prevHeight = stream ? stream.scrollHeight : 0;
    try {
      var mj = await apiFetch('/conversations/' + convId + '/messages?size=20&before=' + before);
      if (!mj.success || !mj.data) return;
      var items = mj.data.items || [];
      items.forEach(function (m) { normalizeMsg(m); });
      window.__dunesMsgHasMore = !!mj.data.hasMore;
      if (!items.length) {
        window.__dunesMsgHasMore = false;
        ensureLoadMoreHint(box, screenId);
        return;
      }
      window.__dunesMsgOldestId = items[0].id;
      var peer = window.__dunesChatPeer;
      paintMessages(box, items, peer, true);
      wireRecall(box, screenId);
      ensureLoadMoreHint(box, screenId);
      if (stream) stream.scrollTop = stream.scrollHeight - prevHeight;
    } catch (e) {
      console.warn('loadOlderMessages', e);
    } finally {
      _msgLoadingOlder = false;
    }
  }
  async function loadNewerMessages(screenId) {
    var convId = currentPendingConvId();
    if (_msgLoadingNewer || !window.__dunesMsgHasNewer || !convId) return;
    var after = window.__dunesMsgNewestId;
    if (!after) return;
    var box = document.getElementById(screenId === 'C2' ? 'c2-api-rows' : 'c5-api-rows');
    var stream = box && box.closest('.msg-stream');
    if (!box) return;
    _msgLoadingNewer = true;
    var nearBottom = false;
    if (stream) nearBottom = (stream.scrollHeight - stream.scrollTop - stream.clientHeight) < 120;
    try {
      var mj = await apiFetch('/conversations/' + convId + '/messages?size=20&after=' + after);
      if (!mj.success || !mj.data) return;
      var items = mj.data.items || [];
      items.forEach(function (m) { normalizeMsg(m); });
      if (!items.length) {
        window.__dunesMsgHasNewer = false;
        ensureLoadNewerHint(box, screenId);
        return;
      }
      var peer = window.__dunesChatPeer;
      paintMessages(box, items, peer, false, true);
      window.__dunesMsgNewestId = items[items.length - 1].id;
      window.__dunesMsgHasNewer = !!mj.data.hasMore;
      wireRecall(box, screenId);
      ensureLoadNewerHint(box, screenId);
      if (!window.__dunesMsgHasNewer) {
        window.__dunesMsgAnchorId = null;
        var jb = document.getElementById('dunes-jump-latest');
        if (jb) jb.remove();
      } else {
        ensureJumpToLatestBar(screenId);
      }
      if (stream && nearBottom) scrollChatToBottom(screenId, { gentle: true });
    } catch (e) {
      console.warn('loadNewerMessages', e);
    } finally {
      _msgLoadingNewer = false;
    }
  }
  function wireMsgStreamHistory(screenId) {
    var stream = document.querySelector('.screen[data-screen="' + screenId + '"] .msg-stream');
    if (!stream || stream.dataset.wiredHistory) return;
    stream.dataset.wiredHistory = '1';
    stream.addEventListener('scroll', function () {
      if (stream.scrollTop < 72) loadOlderMessages(screenId);
    });
  }
  function applyPrivateHeader(peer, title) {
    var screen = document.querySelector('.screen[data-screen="C5"]');
    if (!screen || !peer) return;
    window.__dunesChatPeer = peer;
    window.pendingContactUserId = Number(peer.userId);
    var av = screen.querySelector('.cv-av-mini');
    var nm = screen.querySelector('.cv-nm');
    var sub = screen.querySelector('.cv-sub');
    var name = peer.displayName || title || '私聊';
    if (av) {
      var on = isUserOnline(peer.userId);
      av.innerHTML = esc(name.slice(0, 1)) + '<div class="av-dot' + (on ? ' on' : '') + '"></div>';
      av.setAttribute('data-go', 'C9');
      av.className = 'cv-av-mini ' + personCls(peer.userId);
    }
    if (nm) nm.textContent = name;
    if (sub) {
      var parts = [];
      if (peer.departmentName) parts.push(peer.departmentName);
      if (peer.title || peer.roleLabel) parts.push(peer.title || peer.roleLabel);
      var online = isUserOnline(peer.userId);
      parts.push(online ? '在线' : '离线');
      sub.textContent = parts.join(' · ');
    }
    screen.dataset.name = '私聊·' + name;
    var inp = document.getElementById('c5-input');
    if (inp) inp.placeholder = '给' + name + '发消息…';
    ensureChatHistoryBtn('C5');
  }
  function applyGroupHeader(detail) {
    var screen = document.querySelector('.screen[data-screen="C2"]');
    if (!screen) return;
    var nm = screen.querySelector('.cv-nm');
    var sub = screen.querySelector('.cv-sub');
    if (nm) nm.textContent = detail.title || '工作群';
    if (sub && detail.members) {
      sub.textContent = detail.members.length + ' 成员 · ' + detail.members.slice(0, 4).map(function (m) { return m.displayName; }).join(' · ');
    }
    ensureChatHistoryBtn('C2');
  }
  function emojiPanelId(screenId) {
    return 'dunes-emoji-panel-' + (screenId === 'C2' ? 'c2' : 'c5');
  }
  function toggleEmojiPanel(screenId) {
    ensureEmojiPanel(screenId);
    var panel = document.getElementById(emojiPanelId(screenId));
    if (!panel) return;
    ['c2', 'c5'].forEach(function (sid) {
      var other = document.getElementById('dunes-emoji-panel-' + sid);
      if (other && other !== panel) other.style.display = 'none';
    });
    panel.style.display = panel.style.display === 'none' ? 'block' : 'none';
  }
  function ensureEmojiPanel(screenId) {
    var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
    var panelId = emojiPanelId(screenId);
    if (!screen) return null;
    var existing = document.getElementById(panelId);
    if (existing) return existing;
    var panel = document.createElement('div');
    panel.id = panelId;
    panel.className = 'dunes-emoji-panel';
    panel.style.display = 'none';
    var grid = document.createElement('div');
    grid.className = 'dunes-emoji-grid';
    EMOJI_CHARS.forEach(function (ch) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'dunes-emoji-btn';
      var url = twemojiImgUrl(ch);
      if (url) {
        var img = document.createElement('img');
        img.src = url;
        img.alt = ch;
        img.width = 28;
        img.height = 28;
        img.loading = 'lazy';
        btn.appendChild(img);
      } else {
        btn.textContent = ch;
      }
      btn.addEventListener('click', function () {
        var inp = document.getElementById(screenId === 'C2' ? 'c2-input' : 'c5-input');
        if (inp) { inp.value += ch; inp.focus(); }
        panel.style.display = 'none';
      });
      grid.appendChild(btn);
    });
    panel.appendChild(grid);
    var content = screen.querySelector('.content');
    var qa = screen.querySelector('.msg-quick-actions');
    if (content && qa) content.insertBefore(panel, qa);
    return panel;
  }
  function qaTypeFromCell(cell) {
    var t = cell.querySelector('.qa-t');
    var label = t ? t.textContent.trim() : '';
    if (label.indexOf('拍照') >= 0) return 'camera';
    if (label.indexOf('相册') >= 0) return 'album';
    if (label.indexOf('文件') >= 0) return 'file';
    if (label.indexOf('审批') >= 0) return 'approval';
    if (label.indexOf('@') >= 0) return 'at';
    if (label.indexOf('表情') >= 0) return 'emoji';
    return '';
  }
  function styleFilePickerInput(el) {
    if (!el) return el;
    el.removeAttribute('hidden');
    el.style.position = 'fixed';
    el.style.left = '-10000px';
    el.style.top = '0';
    el.style.width = '1px';
    el.style.height = '1px';
    el.style.opacity = '0';
    el.style.pointerEvents = 'none';
    return el;
  }
  function groupMembers() {
    return window.__dunesGroupMembers || [];
  }
  function ensureAtPicker(screenId) {
    var id = 'dunes-at-picker-' + (screenId === 'C2' ? 'c2' : 'c5');
    var existing = document.getElementById(id);
    if (existing) return existing;
    var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
    if (!screen) return null;
    var panel = document.createElement('div');
    panel.id = id;
    panel.className = 'dunes-at-picker';
    panel.style.cssText = 'display:none;position:absolute;left:12px;right:12px;bottom:96px;max-height:160px;overflow-y:auto;background:var(--bg-app);border:1px solid var(--border-soft);border-radius:10px;z-index:90;box-shadow:0 8px 24px rgba(0,0,0,.12)';
    var bar = screen.querySelector('.msg-input-bar');
    if (bar && bar.parentNode) bar.parentNode.insertBefore(panel, bar);
    else screen.appendChild(panel);
    return panel;
  }
  function hideAtPicker(screenId) {
    var panel = document.getElementById('dunes-at-picker-' + (screenId === 'C2' ? 'c2' : 'c5'));
    if (panel) panel.style.display = 'none';
  }
  function renderAtPickerContent(screenId, filter) {
    if (screenId !== 'C2') return;
    var members = groupMembers();
    var panel = ensureAtPicker(screenId);
    if (!panel || !members.length) { hideAtPicker(screenId); return; }
    var q = String(filter || '').trim().toLowerCase();
    var rows = members.filter(function (m) {
      if (!q) return true;
      return String(m.displayName || '').toLowerCase().indexOf(q) >= 0;
    });
    if (!rows.length) { hideAtPicker(screenId); return; }
    panel.innerHTML = '<div style="padding:8px 12px;font-size:11px;color:var(--text-3);border-bottom:1px solid var(--border-soft);display:flex;align-items:center;justify-content:space-between">'
      + '<span>可多选成员，点选后继续输入</span>'
      + '<button type="button" class="dunes-at-done" style="border:none;background:transparent;color:var(--accent);font-weight:700;font-size:12px;cursor:pointer;padding:2px 4px">完成</button></div>'
      + rows.map(function (m) {
        return '<div class="dunes-at-row tappable" data-at-user-id="' + m.userId + '" data-at-name="' + esc(m.displayName || '') + '" style="padding:10px 12px;border-bottom:1px solid var(--border-soft);font-size:13px">@' + esc(m.displayName || '') + '</div>';
      }).join('');
    panel.style.display = 'block';
  }
  function bindAtPickerDismiss() {
    if (window.__dunesAtDismissBound) return;
    window.__dunesAtDismissBound = true;
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') hideAtPicker('C2');
    });
    document.addEventListener('mousedown', function (e) {
      var panel = document.getElementById('dunes-at-picker-c2');
      if (!panel || panel.style.display === 'none') return;
      if (panel.contains(e.target)) return;
      var inp = document.getElementById('c2-input');
      if (inp && (inp === e.target || inp.contains(e.target))) return;
      if (e.target.closest && e.target.closest('[data-qa="at"]')) return;
      hideAtPicker('C2');
    });
  }
  function bindAtPickerOnce(screenId) {
    if (screenId !== 'C2') return;
    var panel = ensureAtPicker(screenId);
    if (!panel || panel.dataset.wired) return;
    panel.dataset.wired = '1';
    panel.addEventListener('mousedown', function (e) { e.preventDefault(); });
    panel.addEventListener('click', function (e) {
      if (e.target.closest('.dunes-at-done')) {
        e.preventDefault();
        hideAtPicker('C2');
        var inp = document.getElementById('c2-input');
        if (inp) inp.focus();
        return;
      }
      var row = e.target.closest('.dunes-at-row');
      if (!row) return;
      e.preventDefault();
      var inp = document.getElementById('c2-input');
      var name = row.getAttribute('data-at-name') || '';
      if (inp) {
        var v = inp.value || '';
        var partial = v.match(/^(.*)@[^@\s]*$/);
        if (partial) inp.value = partial[1] + '@' + name + ' ';
        else inp.value = v + (v && !/\s$/.test(v) ? ' ' : '') + '@' + name + ' ';
        inp.focus();
        renderAtPickerContent('C2', '');
      }
    });
    bindAtPickerDismiss();
  }
  function parseMentionUserIds(text) {
    var members = window.__dunesGroupMembers || [];
    var ids = [];
    var seen = {};
    members.forEach(function (m) {
      var name = m.displayName || '';
      if (!name || text.indexOf('@' + name) < 0) return;
      var uid = Number(m.userId);
      if (uid && !seen[uid]) { seen[uid] = true; ids.push(uid); }
    });
    return ids;
  }
  function openAtMemberPicker(screenId, filter) {
    if (screenId !== 'C2') return;
    if (!groupMembers().length) return;
    bindAtPickerOnce(screenId);
    renderAtPickerContent(screenId, filter);
  }
  function wireGroupAtMention(screenId) {
    if (screenId !== 'C2') return;
    var input = document.getElementById('c2-input');
    if (!input || input.dataset.atWired) return;
    input.dataset.atWired = '1';
    bindAtPickerOnce(screenId);
    input.addEventListener('input', function () {
      var v = input.value || '';
      var m = v.match(/@([^@\s]*)$/);
      if (m) renderAtPickerContent('C2', m[1]);
      else hideAtPicker('C2');
    });
  }
  function pickFileInput(prefix) {
    return styleFilePickerInput(document.getElementById(prefix + '-upload-slot'));
  }
  function showChatToast(screen, msg) {
    if (window.DunesAPI && typeof window.DunesAPI.toast === 'function') {
      window.DunesAPI.toast(msg);
      return;
    }
    var phone = (screen && screen.querySelector('.phone-screen'))
      || document.querySelector('.screen.active .phone-screen');
    if (!phone) return;
    var t = document.createElement('div');
    t.className = 'toast-tmp';
    t.style.cssText = 'position:absolute;left:50%;bottom:88px;transform:translateX(-50%);max-width:88%;background:rgba(20,20,20,.88);color:#fff;padding:10px 14px;border-radius:9px;font-size:11.5px;z-index:80;text-align:center';
    t.textContent = msg;
    phone.appendChild(t);
    setTimeout(function () { t.remove(); }, 2800);
  }
  function wireChatToolbar(screenId) {
    ensureEmojiPanel(screenId);
    var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
    if (!screen) return;
    if (screen.dataset.toolbarWired) return;
    if (!screen.dataset.legacyAttachStripped) {
      stripLegacyAttachHandlers(screenId);
      screen.dataset.legacyAttachStripped = '1';
    }
    screen.dataset.toolbarWired = '1';
    var prefix = screenId === 'C2' ? 'c2' : 'c5';
    function ensureHiddenInput(id, accept, capture) {
      var el = document.getElementById(id);
      if (!el) {
        el = document.createElement('input');
        el.type = 'file';
        el.id = id;
        if (accept) el.accept = accept;
        if (capture) el.capture = capture;
        screen.appendChild(el);
      }
      return styleFilePickerInput(el);
    }
    var camInput = ensureHiddenInput(prefix + '-camera-slot', 'image/*', 'environment');
    var albumInput = ensureHiddenInput(prefix + '-album-slot', 'image/*', '');
    var fileInput = styleFilePickerInput(document.getElementById(prefix + '-upload-slot'))
      || ensureHiddenInput(prefix + '-upload-slot', '*/*', '');
    function ensureConvReady() {
      if (currentPendingConvId()) return true;
      alert('请先进入一个会话再发送');
      return false;
    }
    async function uploadViaPresigned(bucket, file) {
      bucket = bucket || 'im-attachments';
      var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
      var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
      var authHeaders = token ? { Authorization: 'Bearer ' + token } : {};
      var form = new FormData();
      form.append('file', file, file.name || ('upload-' + Date.now()));
      form.append('bucket', bucket);
      var convId = currentPendingConvId();
      if (convId) form.append('conversationId', String(convId));
      var proxy = await fetch(base + '/storage/upload', {
        method: 'POST',
        headers: authHeaders,
        body: form
      }).then(function (r) { return r.json(); });
      if (proxy && proxy.success && proxy.data) {
        var url = proxy.data.url || '';
        var key = proxy.data.objectKey || url;
        if (url || key) return { url: url || key, objectKey: url || key };
      }
      if (bucket === 'im-attachments') {
        throw new Error((proxy && proxy.message) || 'upload failed');
      }
      var contentType = file.type || 'application/octet-stream';
      var headers = Object.assign({ 'Content-Type': 'application/json' }, authHeaders);
      var pr = await fetch(base + '/storage/presigned-put', {
        method: 'POST',
        headers: headers,
        body: JSON.stringify({
          bucket: bucket,
          fileName: file.name || ('upload-' + Date.now()),
          contentType: contentType
        })
      }).then(function (r) { return r.json(); });
      if (!pr.success || !pr.data || !pr.data.url || !pr.data.objectKey) {
        throw new Error((proxy && proxy.message) || (pr && pr.message) || 'presigned failed');
      }
      var put = await fetch(pr.data.url, {
        method: 'PUT',
        body: file
      });
      if (!put.ok) throw new Error('upload failed ' + put.status);
      return { objectKey: pr.data.objectKey, url: '' };
    }
    function sendAttachment(kind, label, payload, opts) {
      opts = opts || {};
      if (!ensureConvReady()) return Promise.resolve();
      var convId = currentPendingConvId();
      var wasHistoryView = isHistoryLocatedChat();
      clearChatLocateState();
      return apiFetch('/conversations/' + convId + '/messages', {
        method: 'POST',
        body: JSON.stringify({ kind: kind, bodyText: label, payload: payload || null })
      }).then(function (j) {
        if (!j.success) throw new Error(j.message || '发送失败');
        if (opts.pendingNode && opts.pendingNode.parentNode) opts.pendingNode.parentNode.removeChild(opts.pendingNode);
        if (wasHistoryView) return jumpToLatestMessages(screenId);
        var msg = j.data && (j.data.message || j.data);
        if (!boxMatchesConv(msgBoxForScreen(screenId), convId)) return loadChat(screenId);
        if (msg && msg.id) {
          markRtEventSeen({ type: 'message', conversationId: convId, message: msg });
          ensureMessageSender(msg);
          appendRealtimeMessage(msg, screenId, convId);
          return afterReadInChat(convId);
        }
        return loadChat(screenId);
      }).catch(function (e) {
        if (opts.pendingNode && opts.pendingNode.parentNode) opts.pendingNode.parentNode.removeChild(opts.pendingNode);
        alert('发送失败：' + (e.message || e));
      });
    }
    camInput.addEventListener('change', function () {
      var f = camInput.files && camInput.files[0];
      if (f) {
        uploadViaPresigned('im-attachments', f).then(function (up) {
          var fileUrl = up.url || up.objectKey;
          sendAttachment('IMAGE', '[拍照] ' + f.name, {
            url: fileUrl,
            previewUrl: fileUrl,
            mimeType: f.type || 'image/*'
          });
        }).catch(function (e) { alert('上传失败：' + (e.message || e)); });
      }
      camInput.value = '';
    });
    albumInput.addEventListener('change', function () {
      var f = albumInput.files && albumInput.files[0];
      if (f) {
        uploadViaPresigned('im-attachments', f).then(function (up) {
          var fileUrl = up.url || up.objectKey;
          sendAttachment('IMAGE', '[相册] ' + f.name, {
            url: fileUrl,
            previewUrl: fileUrl,
            mimeType: f.type || 'image/*'
          });
        }).catch(function (e) { alert('上传失败：' + (e.message || e)); });
      }
      albumInput.value = '';
    });
    fileInput.addEventListener('change', function () {
      var f = fileInput.files && fileInput.files[0];
      if (f) {
        uploadViaPresigned('im-attachments', f).then(function (up) {
          var fileUrl = up.url || up.objectKey;
          sendAttachment('FILE', f.name, {
            url: fileUrl,
            mimeType: f.type || 'application/octet-stream',
            fileName: f.name,
            size: f.size || 0
          });
        }).catch(function (e) { alert('上传失败：' + (e.message || e)); });
      }
      fileInput.value = '';
    });
    function openFilePicker() {
      if (!ensureConvReady()) return;
      var input = pickFileInput(prefix) || fileInput;
      if (!input) return;
      try { input.click(); } catch (e) { console.warn('file picker', e); }
    }
    var qaBar = screen.querySelector('.msg-quick-actions');
    if (qaBar) {
      qaBar.querySelectorAll('.qa-cell').forEach(function (cell) {
        var qa = cell.getAttribute('data-qa') || qaTypeFromCell(cell);
        if (qa === 'approval') cell.removeAttribute('data-go');
        if (screenId === 'C5' && qa === 'at') cell.style.display = 'none';
      });
    }
    if (qaBar && !qaBar.dataset.dunesQaDelegated) {
      qaBar.dataset.dunesQaDelegated = '1';
      qaBar.addEventListener('click', function (e) {
        var cell = e.target.closest('.qa-cell');
        if (!cell) return;
        e.preventDefault();
        e.stopPropagation();
        var qa = cell.getAttribute('data-qa') || qaTypeFromCell(cell);
        if (qa === 'camera') { if (ensureConvReady()) camInput.click(); }
        else if (qa === 'album') { if (ensureConvReady()) albumInput.click(); }
        else if (qa === 'file' || cell.id === prefix + '-attach-btn') openFilePicker();
        else if (qa === 'emoji') toggleEmojiPanel(screenId);
        else if (qa === 'at' && screenId === 'C2') {
          var atInp = document.getElementById('c2-input');
          if (atInp) {
            var cur = atInp.value || '';
            if (!/@([^@\s]*)$/.test(cur)) {
              atInp.value = cur + (cur && !/\s$/.test(cur) ? ' ' : '') + '@';
            }
            atInp.focus();
            openAtMemberPicker('C2', '');
          }
        } else if (qa === 'at' && screenId !== 'C5') {
          var peer = window.__dunesChatPeer;
          var inp = document.getElementById(prefix + '-input');
          if (peer && inp) inp.value += '@' + (peer.displayName || '') + ' ';
        } else if (qa === 'approval') showChatToast(screen, '敬请期待');
      });
    }
    screen.querySelectorAll('.msg-quick-actions .qa-cell').forEach(function (cell) {
      cell.classList.add('tappable');
    });
    var emojiHdr = document.getElementById(screenId === 'C2' ? 'c2-emoji-btn' : 'c5-emoji-btn')
      || screen.querySelector('.msg-input-bar .emoji-btn');
    if (emojiHdr && !emojiHdr.dataset.wired) {
      emojiHdr.dataset.wired = '1';
      emojiHdr.addEventListener('click', function (e) {
        e.preventDefault();
        toggleEmojiPanel(screenId);
      });
    }
    var inputBar = screen.querySelector('.msg-input-bar');
    var voiceBtn = inputBar && inputBar.querySelector('.voice-btn');
    var textInput = document.getElementById(prefix + '-input');
    if (voiceBtn && inputBar && textInput && !voiceBtn.dataset.dunesWired) {
      voiceBtn.dataset.dunesWired = '1';
      voiceBtn.title = '切换语音';
      var holdBtn = document.createElement('div');
      holdBtn.className = 'voice-hold-btn';
      holdBtn.textContent = '按住 说话';
      holdBtn.setAttribute('role', 'button');
      holdBtn.setAttribute('aria-label', '按住说话');
      textInput.insertAdjacentElement('afterend', holdBtn);
      var phoneScreen = screen.querySelector('.phone-screen');
      var overlayId = 'dunes-voice-overlay-' + prefix;
      var overlay = document.getElementById(overlayId);
      if (!overlay && phoneScreen) {
        overlay = document.createElement('div');
        overlay.id = overlayId;
        overlay.className = 'dunes-voice-record-overlay';
        overlay.innerHTML = '<div class="dunes-voice-record-panel">'
          + '<div class="dunes-voice-record-waves"><span></span><span></span><span></span><span></span><span></span></div>'
          + '<div class="dunes-voice-record-tip">松开 发送</div></div>';
        phoneScreen.appendChild(overlay);
      }
      var overlayTip = overlay ? overlay.querySelector('.dunes-voice-record-tip') : null;
      var voiceMode = false;
      var isHolding = false;
      var willCancel = false;
      var abortRecording = false;
      var sendOnStop = true;
      var activeRec = null;
      var activeStream = null;
      var activeChunks = [];
      var startedAt = 0;
      var stopTimer = 0;
      var holdPointerId = null;
      var holdStartY = 0;
      var CANCEL_THRESHOLD = 72;
      function setVoiceMode(on) {
        voiceMode = !!on;
        inputBar.classList.toggle('voice-mode', voiceMode);
        voiceBtn.innerHTML = voiceMode
          ? '<i class="ti ti-keyboard"></i>'
          : '<i class="ti ti-microphone"></i>';
        voiceBtn.title = voiceMode ? '切换键盘' : '切换语音';
        if (voiceMode && textInput) textInput.blur();
      }
      function showVoiceOverlay(cancel) {
        if (!overlay) return;
        overlay.classList.add('show');
        overlay.classList.toggle('cancel', !!cancel);
        if (overlayTip) overlayTip.textContent = cancel ? '松开手指，取消发送' : '松开 发送';
      }
      function hideVoiceOverlay() {
        if (!overlay) return;
        overlay.classList.remove('show', 'cancel');
        if (overlayTip) overlayTip.textContent = '松开 发送';
      }
      function cleanupVoiceStream() {
        if (stopTimer) {
          clearTimeout(stopTimer);
          stopTimer = 0;
        }
        if (activeStream) {
          activeStream.getTracks().forEach(function (t) { try { t.stop(); } catch (_) {} });
        }
        activeStream = null;
      }
      function resetVoiceState() {
        cleanupVoiceStream();
        activeRec = null;
        activeChunks = [];
        isHolding = false;
        willCancel = false;
        abortRecording = false;
        sendOnStop = true;
        holdPointerId = null;
        holdBtn.classList.remove('active');
        hideVoiceOverlay();
      }
      async function uploadVoiceBlob(blob, recMime, sec) {
        var localUrl = URL.createObjectURL(blob);
        var pendingMsg = {
          id: 'pending-voice-' + Date.now(),
          kind: 'AUDIO',
          bodyText: '[语音] ' + sec + 's',
          createdAt: new Date().toISOString(),
          sender: { userId: devUserId(), displayName: myDisplayName() },
          payload: { url: localUrl, durationSec: sec, pending: true }
        };
        var box = msgBoxForScreen(screenId);
        var pendingNode = null;
        if (box && boxMatchesConv(box, currentPendingConvId())) {
          pendingNode = renderMsg(pendingMsg, window.__dunesChatPeer, window.__dunesPeerLastRead);
          if (pendingNode) {
            pendingNode.classList.add('dunes-voice-pending');
            appendMessageTail(box, pendingNode, pendingMsg);
            wireAttachmentInteractions(box);
            scrollChatToBottom(screenId);
          }
        }
        var ext = recMime.indexOf('mp4') >= 0 ? 'm4a' : 'webm';
        var fileName = 'voice-' + Date.now() + '.' + ext;
        var voiceFile;
        try {
          voiceFile = new File([blob], fileName, { type: recMime });
        } catch (_) {
          voiceFile = blob;
          voiceFile.name = fileName;
        }
        try {
          var up = await uploadViaPresigned('im-attachments', voiceFile);
          var fileUrl = up.url || up.objectKey;
          await sendAttachment('AUDIO', '[语音] ' + sec + 's', {
            url: fileUrl,
            mimeType: recMime,
            durationSec: sec,
            fileName: fileName,
            size: blob.size
          }, { skipPendingRemove: false, pendingNode: pendingNode });
        } catch (err) {
          if (pendingNode && pendingNode.parentNode) pendingNode.parentNode.removeChild(pendingNode);
          throw err;
        }
      }
      voiceBtn.addEventListener('click', function (e) {
        e.preventDefault();
        if (isHolding || (activeRec && activeRec.state === 'recording')) return;
        setVoiceMode(!voiceMode);
      });
      holdBtn.addEventListener('pointerdown', async function (e) {
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        e.preventDefault();
        if (!ensureConvReady()) return;
        if (isHolding || (activeRec && activeRec.state === 'recording')) return;
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || typeof MediaRecorder === 'undefined') {
          alert('当前环境不支持语音录制');
          return;
        }
        isHolding = true;
        willCancel = false;
        abortRecording = false;
        sendOnStop = true;
        holdPointerId = e.pointerId;
        holdStartY = e.clientY;
        holdBtn.classList.add('active');
        showVoiceOverlay(false);
        try { holdBtn.setPointerCapture(e.pointerId); } catch (_) {}
        try {
          activeStream = await navigator.mediaDevices.getUserMedia({ audio: true });
          if (!isHolding || abortRecording) {
            cleanupVoiceStream();
            resetVoiceState();
            return;
          }
          activeChunks = [];
          activeRec = new MediaRecorder(activeStream);
          startedAt = Date.now();
          activeRec.ondataavailable = function (ev) {
            if (ev.data && ev.data.size > 0) activeChunks.push(ev.data);
          };
          activeRec.onstop = async function () {
            var shouldSend = sendOnStop && !abortRecording;
            var sec = Math.max(0, Math.round((Date.now() - startedAt) / 1000));
            var recMime = activeRec && activeRec.mimeType ? activeRec.mimeType : 'audio/webm';
            var blob = new Blob(activeChunks, { type: recMime });
            cleanupVoiceStream();
            activeRec = null;
            activeChunks = [];
            holdBtn.classList.remove('active');
            hideVoiceOverlay();
            if (!shouldSend) return;
            if (sec < 1) {
              showChatToast(screen, '说话时间太短');
              return;
            }
            if (!blob.size) {
              showChatToast(screen, '录音内容为空，请重试');
              return;
            }
            try {
              await uploadVoiceBlob(blob, recMime, Math.max(1, sec));
            } catch (err) {
              alert('语音发送失败：' + (err.message || err));
            }
          };
          activeRec.start();
          stopTimer = setTimeout(function () {
            if (activeRec && activeRec.state === 'recording') {
              try { activeRec.stop(); } catch (_) {}
            }
          }, 30000);
          if (!isHolding) {
            try { if (activeRec.state === 'recording') activeRec.stop(); } catch (_) {}
          }
        } catch (err) {
          resetVoiceState();
          alert('语音录制失败：' + (err.message || err));
        }
      });
      function finishHoldRecord() {
        if (!isHolding) return;
        isHolding = false;
        sendOnStop = !willCancel;
        hideVoiceOverlay();
        holdBtn.classList.remove('active');
        if (activeRec && activeRec.state === 'recording') {
          try { activeRec.stop(); } catch (_) {}
          return;
        }
        if (!activeRec) abortRecording = true;
        cleanupVoiceStream();
      }
      holdBtn.addEventListener('pointermove', function (e) {
        if (!isHolding || e.pointerId !== holdPointerId) return;
        willCancel = e.clientY < holdStartY - CANCEL_THRESHOLD;
        showVoiceOverlay(willCancel);
      });
      holdBtn.addEventListener('pointerup', function (e) {
        if (e.pointerId !== holdPointerId) return;
        e.preventDefault();
        finishHoldRecord();
      });
      holdBtn.addEventListener('pointercancel', function (e) {
        if (e.pointerId !== holdPointerId) return;
        willCancel = true;
        finishHoldRecord();
      });
    }
  }
  function convPeerUserId(info) {
    if (!info) return 0;
    if (info.peer && info.peer.userId) return Number(info.peer.userId);
    if (info.members) {
      var o = info.members.find(function (m) { return Number(m.userId) !== devUserId(); });
      if (o) return Number(o.userId);
    }
    return 0;
  }
  async function resolvePrivateConvForPeer(peerUserId) {
    if (!peerUserId || peerUserId === devUserId()) return null;
    try {
      var j = await apiFetch('/conversations');
      var rows = j.success ? (j.data || []) : [];
      for (var i = 0; i < rows.length; i++) {
        var c = rows[i];
        if (c.kind !== 'PRIVATE') continue;
        if (c.peer && Number(c.peer.userId) === peerUserId) return Number(c.id);
        if (c.peerUserId && Number(c.peerUserId) === peerUserId) return Number(c.id);
      }
      var cr = await apiFetch('/conversations', {
        method: 'POST',
        body: JSON.stringify({ kind: 'PRIVATE', title: '私聊', memberUserIds: [peerUserId] })
      });
      if (cr.success && cr.data && cr.data.conversationId) return Number(cr.data.conversationId);
    } catch (e) { console.warn('resolvePrivateConvForPeer', e); }
    return null;
  }
  async function ensureConvId(screenId) {
    if (screenId === 'C5') {
      var selectedConvId = currentPendingConvId();
      if (selectedConvId) {
        try {
          var current = await apiFetch('/conversations/' + selectedConvId);
          if (current.success && current.data && current.data.kind === 'PRIVATE') {
            var currentPeer = convPeerUserId(current.data);
            var wantPeer = currentPendingContactUserId();
            if (wantPeer && currentPeer && currentPeer !== wantPeer) {
              var fixed = await resolvePrivateConvForPeer(wantPeer);
              if (fixed) {
                setPendingConvId(fixed);
                setPendingPeerUserId(wantPeer);
                return fixed;
              }
            }
            if (currentPeer) setPendingPeerUserId(currentPeer);
            return setPendingConvId(selectedConvId);
          }
        } catch (e) {}
      }
      var wantPeer = currentPendingContactUserId();
      if (wantPeer) {
        var resolved = await resolvePrivateConvForPeer(wantPeer);
        if (resolved) {
          setPendingConvId(resolved);
          setPendingPeerUserId(wantPeer);
          return resolved;
        }
        return null;
      }
      return null;
    }
    var existingConvId = currentPendingConvId();
    if (existingConvId) return existingConvId;
    try {
      var j = await apiFetch('/conversations');
      var rows = j.success ? (j.data || []) : [];
      var want = screenId === 'C5' ? 'PRIVATE' : 'WORKGROUP_APPROVAL';
      var hit = rows.find(function (c) { return c.kind === want; })
        || (screenId === 'C2' ? rows.find(function (c) { return c.kind === 'WORKGROUP'; }) : null);
      if (hit && hit.id) {
        return setPendingConvId(hit.id);
      }
    } catch (e) {}
    return null;
  }
  async function loadChat(screenId) {
    if (screenId !== 'C5' && screenId !== 'C2') return;
    var gen = ++imLoadGen;
    var focusId = Number(window.__dunesFocusMessageId || 0);
    var anchorId = Number(window.__dunesMsgAnchorId || 0);
    var locateFromHistory = !!window.__dunesLocateFromHistory;
    var centerId = (locateFromHistory && focusId) ? focusId : anchorId;
    var locating = centerId > 0;
    var convId = await ensureConvId(screenId);
    if (gen !== imLoadGen) return;
    wireChatToolbar(screenId);
    var prevConvId = Number(window.__dunesActiveConvId || 0);
    setPendingConvId(convId);
    window.__dunesActiveConvId = convId;
    resubscribeImRealtime();
    var convChanged = prevConvId > 0 && prevConvId !== Number(convId);
    if (convChanged) clearChatLocateState();
    var box = document.getElementById(screenId === 'C2' ? 'c2-api-rows' : 'c5-api-rows');
    var forceReset = convChanged || !box || msgBoxLoadedConvId(box) !== Number(convId)
      || !!(locateFromHistory && focusId);
    if (forceReset) {
      box = resetMsgStream(screenId);
      if (!box) return;
      box.innerHTML = '<div class="msg-system"><span class="pill"><i class="ti ti-loader"></i> 加载消息…</span></div>';
      window.__dunesMsgNewestId = 0;
      window.__dunesMsgOldestId = 0;
    }
    if (!convId) {
      box.innerHTML = '<div class="msg-system"><span class="pill">未选中会话 · 请从消息列表或通讯录进入</span></div>';
      return;
    }
    var peer = null;
    try {
      var info = await apiFetch('/conversations/' + convId);
      if (gen !== imLoadGen || window.__dunesActiveConvId !== convId) return;
      if (info.success && info.data) {
        window.__dunesActiveConvKind = info.data.kind || '';
        window.__dunesPeerLastRead = Number(info.data.peerLastReadMessageId || 0);
        if (screenId === 'C5') {
          peer = info.data.peer;
          if (!peer && info.data.members) {
            peer = info.data.members.find(function (m) { return Number(m.userId) !== devUserId(); });
          }
          if (peer && peer.userId) setPendingPeerUserId(peer.userId);
          var wantPeerId = currentPendingContactUserId();
          if (!peer && wantPeerId) {
            try {
              var cj = await apiFetch('/contacts/' + wantPeerId);
              if (cj.success && cj.data) {
                peer = {
                  userId: wantPeerId,
                  displayName: cj.data.displayName,
                  departmentName: cj.data.department || cj.data.departmentName,
                  title: cj.data.title,
                  roleLabel: (cj.data.roleLabels && cj.data.roleLabels[0]) || ''
                };
              }
            } catch (e) {}
          }
          applyPrivateHeader(peer, info.data.title);
        } else {
          window.__dunesChatPeer = null;
          window.__dunesGroupMembers = (info.data.members || []).filter(function (m) {
            return Number(m.userId) !== devUserId();
          });
          window.__dunesGroupDetail = info.data;
          applyGroupHeader(info.data);
        }
      }
      var msgPath = '/conversations/' + convId + '/messages?size=' + (locating ? 40 : 20);
      if (locating) msgPath += '&around=' + centerId;
      var mj = await apiFetch(msgPath);
      if (gen !== imLoadGen || window.__dunesActiveConvId !== convId) return;
      if (mj.success && mj.data && mj.data.peerLastReadMessageId != null) {
        window.__dunesPeerLastRead = Number(mj.data.peerLastReadMessageId);
      }
      var items = mj.success && mj.data ? (mj.data.items || []) : [];
      items.forEach(function (m) { normalizeMsg(m); });
      items = sortChatItems(items);
      var shouldFocusLocate = locating;
      window.__dunesMsgHasMore = !!(mj.success && mj.data && mj.data.hasMore);
      window.__dunesMsgOldestId = items.length ? items[0].id : 0;
      window.__dunesMsgNewestId = items.length ? items[items.length - 1].id : 0;
      window.__dunesMsgHasNewer = !!(mj.success && mj.data && mj.data.hasNewer);
      if (!items.length) {
        if (!box.querySelector('[data-message-id]')) {
          box.innerHTML = '<div class="msg-system"><span class="pill">暂无消息</span></div>';
        }
        window.__dunesMsgHasMore = false;
        window.__dunesMsgHasNewer = false;
        markMsgBoxConv(box, convId);
      } else {
        paintMessages(box, items, peer, false);
        wireRecall(box, screenId);
        ensureLoadMoreHint(box, screenId);
        ensureLoadNewerHint(box, screenId);
        ensureLeadingDateDivider(box);
        wireMsgStreamHistory(screenId);
        markMsgBoxConv(box, convId);
        var stream = box.closest('.msg-stream');
        if (shouldFocusLocate) {
          window.__dunesMsgAnchorId = centerId;
          window.__dunesLocateFromHistory = false;
          window.__dunesFocusMessageId = null;
          focusMessageInChat(centerId);
          ensureJumpToLatestBar(screenId);
        } else {
          window.__dunesMsgAnchorId = null;
          var jumpBar = document.getElementById('dunes-jump-latest');
          if (jumpBar) jumpBar.remove();
          scrollChatToBottom(screenId);
        }
      }
      await afterReadInChat(convId);
      setTimeout(function () { syncConvPresence(); applyOnlinePresence(); }, 300);
      if (window.__dunesChatPresenceTimer) clearInterval(window.__dunesChatPresenceTimer);
      window.__dunesChatPresenceTimer = setInterval(function () {
        if (!document.querySelector('.screen.active') || (document.querySelector('.screen.active').dataset.screen !== 'C5' && document.querySelector('.screen.active').dataset.screen !== 'C2')) {
          clearInterval(window.__dunesChatPresenceTimer);
          return;
        }
        syncConvPresence();
        refreshPeerReadFromServer(convId);
      }, 8000);
    } catch (e) {
      if (gen !== imLoadGen) return;
      box.innerHTML = '<div class="msg-system"><span class="pill">加载失败：' + esc(e.message || e) + '</span></div>';
      console.warn('DunesImChat.loadChat', e);
    }
    wireInput(screenId);
  }
  function wireInput(screenId) {
    stripLegacyImInputHandlers(screenId);
    var input = document.getElementById(screenId === 'C2' ? 'c2-input' : 'c5-input');
    var btn = document.getElementById(screenId === 'C2' ? 'c2-send' : 'c5-send');
    if (!input || input.dataset.dunesImWired) return;
    input.dataset.dunesImWired = '1';
    async function send() {
      var text = input.value.trim();
      var convId = currentPendingConvId();
      if (!text || !convId) return;
      input.value = '';
      var wasHistoryView = isHistoryLocatedChat();
      clearChatLocateState();
      try {
        var payload = null;
        if (screenId === 'C2') {
          var mentionUserIds = parseMentionUserIds(text);
          if (mentionUserIds.length) payload = { mentionUserIds: mentionUserIds };
        }
        var j = await apiFetch('/conversations/' + convId + '/messages', {
          method: 'POST',
          body: JSON.stringify({ kind: 'TEXT', bodyText: text, payload: payload })
        });
        if (!j.success) alert(j.message || '发送失败');
        else {
          var msg = j.data && (j.data.message || j.data);
          if (wasHistoryView) {
            await jumpToLatestMessages(screenId);
            return;
          }
          var box = msgBoxForScreen(screenId);
          if (!boxMatchesConv(box, convId)) {
            await loadChat(screenId);
            return;
          }
          if (msg && msg.id) {
            ensureMessageSender(msg);
            markRtEventSeen({ type: 'message', conversationId: convId, message: msg });
            appendRealtimeMessage(msg, screenId, convId);
            await afterReadInChat(convId);
            refreshPeerReadFromServer(convId);
          } else {
            await loadChat(screenId);
          }
        }
      } catch (e) {
        alert('发送失败：' + (e.message || e));
      }
    }
    if (btn && !btn.dataset.dunesImWired) {
      btn.dataset.dunesImWired = '1';
      btn.addEventListener('click', function (e) { e.preventDefault(); send(); });
    }
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
    });
    if (screenId === 'C2') wireGroupAtMention(screenId);
  }
  function stripLegacyImInputHandlers(screenId) {
    var inputId = screenId === 'C2' ? 'c2-input' : 'c5-input';
    var btnId = screenId === 'C2' ? 'c2-send' : 'c5-send';
    var input = document.getElementById(inputId);
    var btn = document.getElementById(btnId);
    if (input && input.parentNode) {
      var ni = input.cloneNode(true);
      ni.value = input.value;
      ni.removeAttribute('data-wired' + screenId);
      ni.removeAttribute('data-dunes-im-wired');
      input.parentNode.replaceChild(ni, input);
    }
    if (btn && btn.parentNode) {
      var nb = btn.cloneNode(true);
      nb.removeAttribute('data-wired' + screenId);
      nb.removeAttribute('data-dunes-im-wired');
      btn.parentNode.replaceChild(nb, btn);
    }
  }
  function patchDunesApi() {
    if (!window.DunesApi || window.DunesApi.__dunesImPatched) return;
    window.DunesApi.__dunesImPatched = true;
    window.DunesApi.loadImDetail = function (screenId) { return loadChat(screenId); };
    window.DunesApi.sendImMessage = function () { return Promise.resolve(); };
    window.DunesApi.wireImInput = function (screenId) {
      stripLegacyImInputHandlers(screenId);
      return wireInput(screenId);
    };
    window.DunesApi.wireImAttach = function () { return Promise.resolve(); };
    window.DunesApi.wireC12Search = function () { return wireC12Search(); };
    window.DunesApi.searchConvMessages = function (q) { return searchConvMessages(q || ''); };
    var origConnect = window.DunesApi.connectImWs;
    window.DunesApi.connectImWs = function () { return connectImRealtime(); };
    if (!origConnect) connectImRealtime();
    stripLegacyImInputHandlers('C2');
    stripLegacyImInputHandlers('C5');
    stripLegacyAttachHandlers('C2');
    stripLegacyAttachHandlers('C5');
    wireInput('C2');
    wireInput('C5');
    var origLoadContact = window.DunesApi.loadContactDetail;
    if (typeof origLoadContact === 'function') {
      window.DunesApi.loadContactDetail = function (uid) {
        return Promise.resolve(origLoadContact(uid)).then(function () {
          refreshC9Presence();
        });
      };
    }
  }
  function searchTargetScreen(kind) {
    if (window.__dunesC12NovaMode) return 'C4';
    kind = String(kind || window.__dunesActiveConvKind || '').toUpperCase();
    if (kind === 'AI_ASSISTANT') return 'C4';
    return kind === 'PRIVATE' ? 'C5' : 'C2';
  }
  var _c12Gen = 0;
  var _c12Loading = false;
  var _c12HasMore = false;
  var _c12OldestId = 0;
  var _c12LastQuery = '';
  async function currentConvKind() {
    var convId = currentPendingConvId();
    if (!convId) return window.__dunesActiveConvKind || '';
    try {
      var d = await apiFetch('/conversations/' + convId);
      if (d.success && d.data && d.data.kind) {
        window.__dunesActiveConvKind = d.data.kind;
        return d.data.kind;
      }
    } catch (e) {}
    return window.__dunesActiveConvKind || '';
  }
  function clearHistoryLocateState() {
    clearChatLocateState();
  }
  function wireC12Search() {
    var backBtn = document.querySelector('.screen[data-screen="C12"] .ds-back');
    var actionBack = document.querySelector('.screen[data-screen="C12"] .action-bar .act-btn');
    var title = document.querySelector('.screen[data-screen="C12"] .ds-name');
    var ret = window.__dunesHistoryReturnScreen || searchTargetScreen(window.__dunesActiveConvKind);
    if (backBtn) backBtn.dataset.go = ret;
    if (actionBack) actionBack.dataset.go = ret;
    var crumb = document.querySelector('.screen[data-screen="C12"] .ds-crumb');
    if (crumb) {
      if (window.__dunesC12NovaMode) crumb.textContent = 'NOVA · 搜索';
      else {
        var d = window.__dunesGroupDetail || {};
        crumb.textContent = (d.title || '群聊') + ' · 搜索';
      }
    }
    if (backBtn && !backBtn.dataset.dunesClearLocate) {
      backBtn.dataset.dunesClearLocate = '1';
      backBtn.addEventListener('click', clearHistoryLocateState, true);
    }
    if (actionBack && !actionBack.dataset.dunesClearLocate) {
      actionBack.dataset.dunesClearLocate = '1';
      actionBack.addEventListener('click', clearHistoryLocateState, true);
    }
    if (title) title.textContent = '查找聊天内容';
    var input = document.getElementById('c12-search-input');
    var clr = document.getElementById('c12-search-clear');
    if (input && !input.dataset.dunesWired) {
      input.dataset.dunesWired = '1';
      var run = function () { searchConvMessages(input.value.trim()); };
      input.addEventListener('input', run);
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') run(); });
      if (clr) clr.addEventListener('click', function () { input.value = ''; run(); });
    }
    wireC12Paging();
  }
  function wireC12Paging() {
    var content = document.querySelector('.screen[data-screen="C12"] .content');
    if (!content || content.dataset.dunesC12Paging) return;
    content.dataset.dunesC12Paging = '1';
    content.addEventListener('scroll', function () {
      if (!_c12HasMore || _c12Loading) return;
      if (content.scrollTop + content.clientHeight >= content.scrollHeight - 80) {
        loadMoreC12Messages();
      }
    }, { passive: true });
  }
  function c12TimeLabel(at) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    var hm = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
    var now = new Date();
    if (dayKey(d) === dayKey(now)) return '今 ' + hm;
    var yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (dayKey(d) === dayKey(yesterday)) return '昨 ' + hm;
    if (d.getFullYear() === now.getFullYear()) {
      return (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + hm;
    }
    return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + hm;
  }
  function lastC12CreatedAt(box) {
    if (!box) return null;
    var cards = box.querySelectorAll('.noti-card[data-message-id]');
    if (!cards.length) return null;
    return cards[cards.length - 1].getAttribute('data-created-at') || null;
  }
  function paintC12Hits(box, hits, kind, append) {
    if (!box || !hits || !hits.length) return;
    hits.forEach(function (m) { normalizeMsg(m); });
    var prevAt = append ? lastC12CreatedAt(box) : null;
    var frag = document.createDocumentFragment();
    hits.forEach(function (m) {
      var at = msgCreatedAt(m);
      var divLabel = dayDividerLabel(at, prevAt);
      if (divLabel) frag.appendChild(createDateDivider(divLabel));
      frag.appendChild(renderC12Hit(m, kind, at));
      prevAt = at;
    });
    if (append) box.appendChild(frag);
    else {
      box.innerHTML = '';
      box.appendChild(frag);
    }
    ensureLeadingDateDivider(box);
  }
  function renderC12Hit(m, kind, createdAt) {
    var name = (m.sender && m.sender.displayName) || '系统';
    var at = createdAt || msgCreatedAt(m);
    var tm = c12TimeLabel(at);
    var card = document.createElement('div');
    card.className = 'noti-card tappable';
    card.dataset.messageId = m.id || '';
    card.setAttribute('data-created-at', at);
    card.innerHTML = '<div class="nc-ic"><i class="ti ti-message-2"></i></div>'
      + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(name) + '</div><div class="nc-time">' + esc(tm) + '</div></div>'
      + '<div class="nc-desc">' + esc(m.bodyText || '') + '<span style="font-family:var(--mono);font-size:9px;color:var(--accent);margin-left:5px">→ 点击定位</span></div></div>';
    card.addEventListener('click', function () {
      window.__dunesLocateFromHistory = true;
      window.__dunesFocusMessageId = Number(m.id || 0);
      window.__dunesMsgAnchorId = Number(m.id || 0);
      var target = searchTargetScreen(kind);
      if (window.__dunesC12NovaMode) window.__dunesC12NovaMode = false;
      if (typeof go === 'function') go(target);
      else if (typeof setScreen === 'function') setScreen(target, false);
    });
    return card;
  }
  function c12LoadingRow(text) {
    var row = document.createElement('div');
    row.id = 'c12-load-more';
    row.className = 'api-strip';
    row.innerHTML = '<i class="ti ti-loader"></i><span>' + esc(text || '加载更多聊天记录…') + '</span>';
    return row;
  }
  async function fetchC12Messages(q, before) {
    var kind = await currentConvKind();
    var onlyPrivate = String(kind || '').toUpperCase() === 'PRIVATE';
    var params = 'size=20';
    if (q) params += '&q=' + encodeURIComponent(q);
    if (before) params += '&before=' + before;
    var convId = currentPendingConvId();
    var j = await apiFetch('/conversations/' + convId + '/messages/search?' + params);
    var hits = j.success && j.data ? (j.data.items || []) : [];
    if (onlyPrivate) {
      var pid = Number(window.__dunesPendingPeerUserId || window.pendingContactUserId || (window.__dunesChatPeer && window.__dunesChatPeer.userId) || 0);
      if (!pid) {
        try {
          var d = await apiFetch('/conversations/' + convId);
          if (d.success && d.data && d.data.peer && d.data.peer.userId) pid = Number(d.data.peer.userId);
        } catch (e) {}
      }
      if (pid) {
        hits = hits.filter(function (m) {
          var sid = Number(m && m.sender && m.sender.userId);
          return !sid || sid === pid || sid === devUserId();
        });
      }
    }
    return { kind: kind, hits: hits, hasMore: !!(j.success && j.data && j.data.hasMore) };
  }
  async function searchConvMessages(q) {
    var box = document.getElementById('c12-api-rows');
    if (!box) return;
    if (!currentPendingConvId()) {
      box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>请先进入一个会话再查看历史</span></div>';
      return;
    }
    var gen = ++_c12Gen;
    _c12Loading = true;
    _c12HasMore = false;
    _c12OldestId = 0;
    _c12LastQuery = q || '';
    box.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>查询聊天记录…</span></div>';
    try {
      var result = await fetchC12Messages(q || '', 0);
      if (gen !== _c12Gen) return;
      var hits = result.hits;
      if (!hits.length) {
        box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>' + (q ? '无匹配聊天记录' : '暂无聊天记录') + '</span></div>';
        return;
      }
      box.innerHTML = '';
      paintC12Hits(box, hits, result.kind, false);
      _c12OldestId = hits[hits.length - 1].id || 0;
      _c12HasMore = !!result.hasMore;
    } catch (e) {
      box.innerHTML = '<div class="api-strip"><span>搜索失败：' + esc(e.message || e) + '</span></div>';
      console.warn('searchConvMessages', e);
    } finally {
      if (gen === _c12Gen) _c12Loading = false;
    }
  }
  async function loadMoreC12Messages() {
    var box = document.getElementById('c12-api-rows');
    if (!box || !_c12HasMore || _c12Loading || !_c12OldestId) return;
    var gen = _c12Gen;
    _c12Loading = true;
    var marker = c12LoadingRow('加载更早聊天记录…');
    box.appendChild(marker);
    try {
      var result = await fetchC12Messages(_c12LastQuery, _c12OldestId);
      if (gen !== _c12Gen) return;
      marker.remove();
      var hits = result.hits;
      if (!hits.length) {
        _c12HasMore = false;
        return;
      }
      paintC12Hits(box, hits, result.kind, true);
      _c12OldestId = hits[hits.length - 1].id || _c12OldestId;
      _c12HasMore = !!result.hasMore;
    } catch (e) {
      marker.innerHTML = '<span>加载失败：' + esc(e.message || e) + '</span>';
      console.warn('loadMoreC12Messages', e);
    } finally {
      if (gen === _c12Gen) _c12Loading = false;
    }
  }
  async function leaveChat() {
    var convId = window.__dunesActiveConvId || currentPendingConvId();
    if (window.__dunesChatPresenceTimer) {
      clearInterval(window.__dunesChatPresenceTimer);
      window.__dunesChatPresenceTimer = null;
    }
    if (convId) await markConversationRead(convId);
    if (convId && window.DunesInbox && window.DunesInbox.patchConvUnread) {
      window.DunesInbox.patchConvUnread(convId, 0);
    }
  }
  function chatAlreadyLoaded(screenId) {
    if (screenId !== 'C5' && screenId !== 'C2') return false;
    var convId = Number(currentPendingConvId() || 0);
    if (!convId) return false;
    if (Number(window.__dunesActiveConvId || 0) !== convId) return false;
    var box = msgBoxForScreen(screenId);
    if (!box || !box.querySelector('[data-message-id]')) return false;
    if (msgBoxLoadedConvId(box) !== convId) return false;
    var active = document.querySelector('.screen.active');
    return !!(active && active.dataset.screen === screenId
      && !window.__dunesLocateFromHistory && !window.__dunesMsgAnchorId);
  }
  function onScreen(id) {
    if (id === 'C12') {
      window.__dunesWasOnC12 = true;
      currentConvKind().then(function () {
        wireC12Search();
        searchConvMessages('');
      });
    }
    if (id === 'C5' || id === 'C2') {
      if (window.__dunesWasOnC12 && !window.__dunesLocateFromHistory && !window.__dunesMsgAnchorId) {
        clearHistoryLocateState();
      }
      window.__dunesWasOnC12 = false;
      var targetConv = currentPendingConvId();
      var box = msgBoxForScreen(id);
      if (targetConv && (Number(window.__dunesActiveConvId || 0) !== targetConv
          || msgBoxLoadedConvId(box) !== targetConv)) {
        loadChat(id);
        return;
      }
      if (chatAlreadyLoaded(id)) {
        resubscribeImRealtime();
        wireInput(id);
        if (!isHistoryLocatedChat()) scrollChatToBottom(id);
        return;
      }
      loadChat(id);
    }
    if (id === 'C1' && window.DunesInbox) window.DunesInbox.loadC1();
    if (id === 'Z2' && window.DunesInbox) {
      if (typeof window.DunesInbox.markAllNotificationsRead === 'function') {
        window.DunesInbox.markAllNotificationsRead().then(function () {
          if (window.DunesInbox.loadZ2Notifications) window.DunesInbox.loadZ2Notifications();
        });
      } else if (window.DunesInbox.loadZ2Notifications) {
        window.DunesInbox.loadZ2Notifications();
      }
    }
    if (id === 'C10' && window.DunesInbox && window.DunesInbox.loadBroadcastList) {
      window.DunesInbox.loadBroadcastList();
    }
  }
  function init() {
    patchDunesApi();
    window.__dunesResubscribeIm = resubscribeImRealtime;
    window.__dunesSelectConversation = function (convId, peerUserId) {
      var cid = Number(convId || 0);
      var pid = Number(peerUserId || 0);
      if (pid > 0) setPendingPeerUserId(pid);
      if (cid > 0) setPendingConvId(cid);
      else if (pid > 0 && currentPendingConvId()) {
        window.__dunesActiveConvId = null;
        clearChatLocateState();
      }
    };
    ['C2', 'C5'].forEach(wireChatToolbar);
    connectImRealtime();
    var tries = 0;
    var t = setInterval(function () {
      patchDunesApi();
      if (centrifugeCtor() && !isImRealtimeUp() && !imConnectInflight) {
        connectImRealtime();
      }
      if (++tries > 20) clearInterval(t);
    }, 1000);
  }
  window.DunesPresence = {
    isUserOnline: isUserOnline,
    refreshAll: refreshAllPresenceUi,
    refreshC9: refreshC9Presence
  };
  init();
  return {
    onScreen: onScreen,
    loadChat: loadChat,
    reloadActiveChat: function (screenId) { return loadChat(screenId || 'C2'); },
    wireC12Search: wireC12Search,
    searchConvMessages: searchConvMessages,
    leaveChat: leaveChat,
    connectImRealtime: connectImRealtime,
    markConversationRead: markConversationRead,
    refreshAllPresenceUi: refreshAllPresenceUi
  };
})();
''';
}
