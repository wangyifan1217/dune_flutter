/// 知识库聊天：会话 ensure、历史搜索、页内空态与 SSE 流式注入。
abstract final class KbChatInjection {
  static const js = r'''
window.DunesKbChat = (function () {
  var convId = 0;
  var historyAll = [];
  var historyHasMore = false;
  var historyNextBefore = '';
  var historyLoading = false;
  var msgHasMore = false;
  var msgOldestId = 0;
  var msgLoadingOlder = false;
  var sending = false;
  var kbGenerating = false;
  var kbGenStatus = '知识库助手正在生成…';
  var kbGenPollTimer = null;
  var KB_GEN_TTL_MS = 15 * 60 * 1000;
  var _kbPreviewTimer = null;
  var _kbPreviewInflight = null;
  var KB_PREVIEW_CACHE_KEY = 'dunes_kb_last_preview';
  var KB_PREVIEW_TIME_CACHE_KEY = 'dunes_kb_last_preview_at';

  function activeIs(screen) {
    return document.querySelector('.screen.active')?.dataset?.screen === screen;
  }
  function apiBase() {
    var base = window.__dunesApiBase || localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    return String(base || '').replace(/\/$/, '');
  }
  function token() {
    return window.__dunesToken || localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
  }
  function kbAvHtml() {
    if (window.dunesKbAvatarHtml) return window.dunesKbAvatarHtml('msg-av-sm kb-ai-av');
    return '<div class="msg-av-sm kb-ai-av"><i class="ti ti-books"></i></div>';
  }
  function esc(s) {
    return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function dedupeKbAnswer(text) {
    text = String(text || '').trim();
    if (text.length < 80) return text;
    var start = Math.floor(text.length / 2) - 8;
    if (start < 12) start = 12;
    var end = Math.floor(text.length / 2) + 8;
    if (end > text.length - 12) end = text.length - 12;
    for (var split = start; split <= end; split++) {
      var head = text.slice(0, split).trim();
      var tail = text.slice(split).trim();
      if (head && head === tail) return head;
    }
    var half = Math.floor(text.length / 2);
    if (half >= 40) {
      var head2 = text.slice(0, half);
      var tail2 = text.slice(half);
      if (head2 === tail2 || tail2.indexOf(head2) === 0) return head2.trim();
    }
    var cut2 = repeatedConsecutiveTailCut(text);
    if (cut2 > 0) return text.slice(0, cut2).trim();
    var cut3 = repeatedOpeningReplayCut(text);
    if (cut3 > 0) return text.slice(0, cut3).trim();
    var cut = repeatedTailCut(text);
    if (cut > 0) return text.slice(0, cut).trim();
    return text;
  }
  function openingAnchor(text) {
    var nl = text.indexOf('\n');
    if (nl >= 0) return text.slice(0, nl).trim();
    var dot = text.indexOf('。');
    if (dot >= 0 && dot < 120) return text.slice(0, dot + 1).trim();
    return text.trim();
  }
  function repeatedOpeningReplayCut(text) {
    text = String(text || '').trim();
    if (text.length < 160) return 0;
    var opener = openingAnchor(text);
    if (opener.length < 12) return 0;
    var first = text.indexOf(opener);
    if (first < 0) return 0;
    var searchFrom = first + opener.length;
    if (searchFrom >= text.length) return 0;
    var second = text.indexOf(opener, searchFrom);
    if (second < 0) return 0;
    if (second < text.length / 4) return 0;
    return second;
  }
  function collapseKbWs(s) {
    return String(s || '').replace(/\s+/g, ' ').trim();
  }
  function repeatedConsecutiveTailCut(text) {
    var minBlock = 40;
    var n = text.length;
    if (n < minBlock * 2) return 0;
    var maxSize = Math.floor(n / 2);
    for (var size = maxSize; size >= minBlock; size--) {
      if (n < size * 2) continue;
      var a = text.slice(n - size * 2, n - size);
      var b = text.slice(n - size);
      if (a === b || collapseKbWs(a) === collapseKbWs(b)) return n - size;
    }
    return 0;
  }
  function repeatedTailCut(text) {
    var minPrefix = 12;
    var minOverlap = 40;
    var n = text.length;
    if (n < minOverlap * 2) return 0;
    var prefix = text.slice(0, minPrefix);
    for (var start = Math.floor(n / 3); start < n - minPrefix; start++) {
      if (text.slice(start, start + minPrefix) !== prefix) continue;
      var overlap = Math.min(n - start, start);
      if (overlap < minOverlap) continue;
      var same = 0;
      for (var i = 0; i < overlap; i++) {
        if (text.charAt(i) === text.charAt(start + i)) same++;
      }
      if (same / overlap >= 0.8) return start;
    }
    return 0;
  }
  function kbMdLite(text) {
    var s = esc(String(text || ''));
    s = s.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
    s = s.replace(/^#{1,3}\s+(.+)$/gm, '<b>$1</b>');
    s = s.replace(/^\s*(\d+)[.)]\s+(.+)$/gm, '<span style="font-weight:600">$1.</span> $2');
    s = s.replace(/^\s*[-*]\s+(.+)$/gm, '• $1');
    s = s.replace(/([。！？；])\s*(?=[^<\s])/g, '$1<br><br>');
    s = s.replace(/\n{2,}/g, '<br><br>');
    s = s.replace(/\n/g, '<br>');
    return s;
  }
  function kbBubbleHtml(text) {
    return kbMdLite(kbSanitizeAnswer(text));
  }
  function kbSanitizeAnswer(text) {
    text = String(text || '');
    text = text.replace(/<(?:redacted_)?think(?:ing)?>[\s\S]*?<\/(?:redacted_)?think(?:ing)?>/gi, '');
    var m = text.match(/<(?:redacted_)?think(?:ing)?>/i);
    if (m && m.index >= 0) text = text.slice(0, m.index);
    return dedupeKbAnswer(text.trim());
  }
  function dayKey(d) { return d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate(); }
  function dayDividerLabel(at, prevAt) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    var prev = prevAt ? new Date(prevAt) : null;
    if (prev && !isNaN(prev.getTime()) && dayKey(d) === dayKey(prev)) return '';
    var now = new Date();
    var wd = ['周日','周一','周二','周三','周四','周五','周六'][d.getDay()];
    if (dayKey(d) === dayKey(now)) return '今天 · ' + wd;
    var y = new Date(now); y.setDate(y.getDate() - 1);
    if (dayKey(d) === dayKey(y)) return '昨天 · ' + wd;
    if (d.getFullYear() === now.getFullYear()) return (d.getMonth() + 1) + '月' + d.getDate() + '日 · ' + wd;
    return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日 · ' + wd;
  }
  function dateDivider(label) {
    var div = document.createElement('div');
    div.className = 'msg-date-divider';
    div.textContent = label;
    return div;
  }
  function genKey(id) { return 'dunes_kb_generating_' + String(id || convId || 0); }
  function persistKbGenerating(id, status) {
    id = id || convId;
    if (!id) return;
    try { sessionStorage.setItem(genKey(id), JSON.stringify({ at: Date.now(), status: status || kbGenStatus })); } catch (e) {}
  }
  function clearKbGenerating(id) {
    try { sessionStorage.removeItem(genKey(id || convId)); } catch (e) {}
  }
  function loadPersistedKbGenerating(id) {
    id = id || convId;
    if (!id) return false;
    try {
      var raw = sessionStorage.getItem(genKey(id));
      if (!raw) return false;
      var o = JSON.parse(raw);
      if (!o || Date.now() - Number(o.at || 0) > KB_GEN_TTL_MS) { clearKbGenerating(id); return false; }
      kbGenerating = true;
      kbGenStatus = o.status || '知识库助手正在生成…';
      return true;
    } catch (e) { return false; }
  }
  function cacheKbPreview(text, at) {
    text = String(text || '').trim();
    try {
      if (text) {
        sessionStorage.setItem(KB_PREVIEW_CACHE_KEY, text);
        localStorage.setItem(KB_PREVIEW_CACHE_KEY, text);
        if (at) {
          sessionStorage.setItem(KB_PREVIEW_TIME_CACHE_KEY, String(at));
          localStorage.setItem(KB_PREVIEW_TIME_CACHE_KEY, String(at));
        }
      } else {
        sessionStorage.removeItem(KB_PREVIEW_CACHE_KEY);
        localStorage.removeItem(KB_PREVIEW_CACHE_KEY);
        sessionStorage.removeItem(KB_PREVIEW_TIME_CACHE_KEY);
        localStorage.removeItem(KB_PREVIEW_TIME_CACHE_KEY);
      }
    } catch (e) {}
  }
  function cachedKbPreview() {
    try {
      return sessionStorage.getItem(KB_PREVIEW_CACHE_KEY) || localStorage.getItem(KB_PREVIEW_CACHE_KEY) || '';
    } catch (e) {
      return '';
    }
  }
  function cachedKbPreviewAt() {
    try {
      return sessionStorage.getItem(KB_PREVIEW_TIME_CACHE_KEY) || localStorage.getItem(KB_PREVIEW_TIME_CACHE_KEY) || '';
    } catch (e) {
      return '';
    }
  }
  function patchKbInbox(generating, preview, at) {
    var row = document.querySelector('.chat-row[data-kb-chat="1"]');
    if (!generating) cacheKbPreview(preview, at);
    if (!row) return;
    var pv = row.querySelector('.cr-pv');
    if (!pv) return;
    if (generating) {
      pv.innerHTML = '<span class="generating"><i class="ti ti-loader ti-spin"></i> ' + esc(kbGenStatus || '知识库助手正在生成…') + '</span>';
      row.classList.add('kb-generating');
    } else {
      row.classList.remove('kb-generating');
      var text = String(preview || '').trim();
      pv.textContent = text ? (text.length > 80 ? text.slice(0, 80) + '…' : text) : '向知识库提问…';
      var tm = row.querySelector('.cr-tm');
      if (!tm) {
        var top = row.querySelector('.cr-top');
        if (top) {
          tm = document.createElement('div');
          tm.className = 'cr-tm';
          top.appendChild(tm);
        }
      }
      if (tm) tm.textContent = formatHistoryTime(at || cachedKbPreviewAt());
    }
  }
  function formatTime(at) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  }
  function formatHistoryTime(at) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    var now = new Date();
    if (dayKey(d) === dayKey(now)) return formatTime(at);
    return (d.getMonth() + 1) + '/' + d.getDate();
  }
  function refreshKbInboxPreviewNow() {
    if (!token()) return Promise.resolve();
    if (_kbPreviewInflight) return _kbPreviewInflight;
    _kbPreviewInflight = apiJson('/ai/conversations?kind=KB_ALL&size=1').then(function (d) {
      var items = d.items || [];
      if (!items.length) {
        patchKbInbox(false, '');
        return;
      }
      var row = items[0];
      if (row.assistantGenerating) {
        kbGenStatus = row.assistantGeneratingStatus || kbGenStatus || '知识库助手正在生成…';
        patchKbInbox(true);
        return;
      }
      patchKbInbox(false, row.lastMessagePreview || '', row.lastMessageAt || row.updatedAt || row.createdAt || '');
    }).catch(function () {}).then(function () {
      _kbPreviewInflight = null;
    });
    return _kbPreviewInflight;
  }
  function refreshKbInboxPreview(immediate) {
    if (_kbPreviewTimer) clearTimeout(_kbPreviewTimer);
    if (immediate) {
      _kbPreviewTimer = null;
      return refreshKbInboxPreviewNow();
    }
    _kbPreviewTimer = setTimeout(function () {
      _kbPreviewTimer = null;
      refreshKbInboxPreviewNow();
    }, 320);
  }
  window.__dunesKbPreviewHtml = function () {
    try {
      for (var i = 0; i < sessionStorage.length; i++) {
        var k = sessionStorage.key(i);
        if (k && k.indexOf('dunes_kb_generating_') === 0) {
          var o = JSON.parse(sessionStorage.getItem(k) || '{}');
          if (o && Date.now() - Number(o.at || 0) <= KB_GEN_TTL_MS) {
            return '<span class="generating"><i class="ti ti-loader ti-spin"></i> ' + esc(o.status || '知识库助手正在生成…') + '</span>';
          }
        }
      }
    } catch (e) {}
    var cached = cachedKbPreview();
    return cached ? esc(cached.length > 80 ? cached.slice(0, 80) + '…' : cached) : '向知识库提问…';
  }
  function applyKbChatChrome() {
    var screen = document.querySelector('.screen[data-screen="K2"]');
    if (!screen) return;
    var ctx = screen.querySelector('.kb-doc-context');
    if (ctx) ctx.style.display = 'none';
    screen.querySelectorAll('.dunes-k2-static').forEach(function (el) {
      if (el.parentNode) el.parentNode.removeChild(el);
    });
    var nm = screen.querySelector('.cv-nm');
    if (nm) nm.innerHTML = '知识库 <span class="badge-ai">AI</span>';
    var sub = document.getElementById('k2-doc-sub');
    if (sub) sub.textContent = '基于企业知识库回答';
    var pill = screen.querySelector('.msg-system .pill');
    if (pill && pill.parentNode) pill.parentNode.removeChild(pill.parentNode);
  }
  function apiJson(path, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ 'Content-Type': 'application/json', Authorization: 'Bearer ' + token() }, opts.headers || {});
    return fetch(apiBase() + path, opts).then(function (r) {
      return r.text().then(function (text) {
        var j = {};
        if (text && text.trim()) {
          try { j = JSON.parse(text); } catch (e) { throw new Error(text); }
        }
        if (!r.ok || j.success === false) throw new Error(j.message || ('HTTP ' + r.status));
        return j.data || j;
      });
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
  async function kbVoiceUploadBlob(blob, recMime) {
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
  function kbAsrDialogueMessage(err) {
    var msg = String((err && err.message) || err || '').trim();
    var lower = msg.toLowerCase();
    if (lower.indexOf('upstream') >= 0 || msg.indexOf('网络错误') >= 0 || msg.indexOf('暂时不可用') >= 0) {
      return '抱歉，语音识别服务暂时不可用。您可以稍后再试，或直接打字提问。';
    }
    if (msg.indexOf('未识别') >= 0 || msg.indexOf('未得到') >= 0 || msg.indexOf('empty') >= 0) {
      return '抱歉，我没有听清您说的内容。请靠近麦克风清晰说话后再试，或直接打字提问。';
    }
    if (msg.indexOf('超过') >= 0 && msg.indexOf('秒') >= 0) {
      return '抱歉，语音长度不能超过 30 秒。请缩短录音后重试，或直接打字提问。';
    }
    if (msg.indexOf('格式') >= 0) {
      return '抱歉，当前语音格式暂不支持识别。请重新录制或直接打字提问。';
    }
    if (msg.indexOf('未开通') >= 0 || msg.indexOf('glm-asr') >= 0 || lower.indexOf('asr_not_configured') >= 0) {
      return '语音识别未开通：请在 New API 后台为当前令牌开通 glm-asr-2512 模型';
    }
    return '抱歉，暂时无法识别您的语音。请重新录制或直接打字提问。';
  }
  function isPublicMediaUrl(v) {
    return /^https?:\/\//i.test(String(v || '').trim());
  }
  async function uploadViaPresigned(file) {
    var authH = token() ? { Authorization: 'Bearer ' + token() } : {};
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
  function appendKbVoiceBubble(sec, url, objectKey, pending, meta) {
    var box = rowsBox();
    if (!box) return null;
    meta = meta || {};
    sec = Math.max(1, Number(sec) || 1);
    url = String(url || '');
    objectKey = String(objectKey || '');
    var row = document.createElement('div');
    row.className = 'msg-row sent dunes-kb-voice-row' + (pending ? ' dunes-kb-voice-live' : '');
    row.setAttribute('data-kb-voice', '1');
    if (meta.id) row.setAttribute('data-message-id', String(meta.id));
    if (meta.createdAt) row.setAttribute('data-created-at', String(meta.createdAt));
    var time = formatTime(meta.createdAt || new Date().toISOString());
    row.innerHTML = '<div class="msg-av-sm person-e">我</div><div class="msg-content"><div class="msg-meta"><span class="nm">我</span>' + (time ? '<span>' + time + '</span>' : '') + '</div>'
      + '<div class="msg-bubble sent dunes-voice-bubble' + (pending ? ' pending' : '') + '" data-url="' + esc(url) + '" data-object-key="' + esc(objectKey) + '" data-bucket="im-attachments">'
      + '<span class="voice-sec">' + sec + '\'</span><span class="voice-wave"><i class="ti ti-volume"></i></span></div>'
      + (pending ? '<div class="kb-voice-asr-hint" style="font-size:11px;color:var(--text-3);margin-top:4px;text-align:right">语音识别中…</div>' : '')
      + '</div></div>';
    box.appendChild(row);
    wireK2VoicePlay();
    scrollK2();
    return row;
  }
  function updateKbVoiceBubble(row, sec, url, objectKey) {
    if (!row) return;
    var bubble = row.querySelector('.dunes-voice-bubble');
    if (!bubble) return;
    if (url) bubble.setAttribute('data-url', url);
    if (objectKey) bubble.setAttribute('data-object-key', objectKey);
    if (sec) {
      var secEl = bubble.querySelector('.voice-sec');
      if (secEl) secEl.textContent = Math.max(1, Number(sec) || 1) + '\'';
    }
  }
  function finishKbVoiceBubble(row, transcript) {
    if (!row) return;
    var bubble = row.querySelector('.dunes-voice-bubble');
    if (bubble) bubble.classList.remove('pending');
    var hint = row.querySelector('.kb-voice-asr-hint');
    if (hint && hint.parentNode) hint.parentNode.removeChild(hint);
    row.classList.remove('dunes-kb-voice-live');
    transcript = String(transcript || '').trim();
    if (transcript && !row.querySelector('.kb-voice-transcript')) {
      var cap = document.createElement('div');
      cap.className = 'kb-voice-transcript';
      cap.style.cssText = 'font-size:12px;color:var(--text-2);margin-top:4px;line-height:1.4';
      cap.textContent = transcript;
      var content = row.querySelector('.msg-content');
      if (content) content.appendChild(cap);
    }
  }
  function wireK2VoicePlay() {
    var box = rowsBox();
    if (!box || box.dataset.kbVoicePlayWired) return;
    box.dataset.kbVoicePlayWired = '1';
    box.addEventListener('click', async function (e) {
      var b = e.target.closest('.dunes-voice-bubble');
      if (!b || !box.contains(b)) return;
      e.preventDefault();
      e.stopPropagation();
      var url = b.getAttribute('data-url') || '';
      var key = b.getAttribute('data-object-key') || '';
      if (!isPublicMediaUrl(url) && !/^blob:/i.test(url) && key) {
        try {
          var pr = await apiJson('/storage/presigned-get?bucket=im-attachments&objectKey=' + encodeURIComponent(key));
          if (pr && pr.url) url = pr.url;
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
  async function transcribeKbVoice(prepared) {
    var form = new FormData();
    var voiceFile;
    try {
      voiceFile = new File([prepared.blob], prepared.fileName, { type: prepared.mimeType });
    } catch (_) {
      voiceFile = prepared.blob;
    }
    form.append('file', voiceFile, prepared.fileName);
    var url = apiBase() + '/ai/transcribe';
    var r = await fetch(url, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token() },
      body: form
    });
    var textBody = await r.text();
    var j = {};
    try { j = JSON.parse(textBody); } catch (e) {}
    if (r.status === 404) {
      throw new Error('语音识别接口未就绪，请重启 kb-go 与 API 网关后重试');
    }
    if (!r.ok || j.success === false) {
      throw new Error(j.message || ('语音识别失败 HTTP ' + r.status));
    }
    var data = j.data || j;
    var text = String((data && data.text) || '').trim();
    if (!text) throw new Error('语音识别未得到有效转写，请改用文字发送或稍后重试');
    return text;
  }
  function sendVoiceQuestion(text, voiceMeta) {
    text = String(text || '').trim();
    if (!text || !convId || sending) return;
    sendCurrent(text, true, voiceMeta);
  }
  async function saveKbLocalAssistant(text) {
    text = String(text || '').trim();
    if (!text || !convId) return null;
    try {
      return await apiJson('/ai/conversations/' + convId + '/messages/local', {
        method: 'POST',
        body: JSON.stringify({ content: text })
      });
    } catch (_) {
      return null;
    }
  }
  async function saveKbVoiceUserMessage(content, voiceMeta) {
    content = String(content || '').trim() || '[语音]';
    if (!convId) return null;
    try {
      return await apiJson('/ai/conversations/' + convId + '/messages/voice', {
        method: 'POST',
        body: JSON.stringify({ content: content, metadata: voiceMeta || {} })
      });
    } catch (_) {
      return null;
    }
  }
  function tagKbVoiceRow(row, saved) {
    if (!row || !saved || !saved.messageId) return;
    row.setAttribute('data-message-id', String(saved.messageId));
    row.classList.remove('dunes-kb-voice-live');
  }
  function kbVoiceMetaFromMessage(m) {
    var meta = m && (m.metadata || m.meta);
    if (meta && meta.voice) return meta.voice;
    if (m && m.voice) return m.voice;
    return null;
  }
  function appendKbVoiceHistoryRow(voice, transcript, meta) {
    voice = voice || {};
    meta = meta || {};
    var sec = Math.max(1, Number(voice.durationSec) || 1);
    var url = String(voice.url || voice.accessUrl || '');
    var key = String(voice.objectKey || '');
    var row = appendKbVoiceBubble(sec, url, key, false, meta);
    if (!row) return null;
    finishKbVoiceBubble(row, transcript || voice.transcript || '');
    return row;
  }
  function rowsBox() { return document.getElementById('k2-api-rows'); }
  function streamBox() { return document.getElementById('k2-msg-stream'); }
  function scrollK2() {
    var stream = streamBox();
    if (!stream) return;
    function doScroll() {
      stream.scrollTop = stream.scrollHeight;
      var box = rowsBox();
      if (box && box.lastElementChild) {
        try { box.lastElementChild.scrollIntoView({ block: 'end', behavior: 'auto' }); } catch (e) { box.lastElementChild.scrollIntoView(false); }
      }
    }
    requestAnimationFrame(function () {
      doScroll();
      requestAnimationFrame(doScroll);
    });
    [0, 50, 150].forEach(function (ms) { setTimeout(doScroll, ms); });
  }
  function inputEl() { return document.getElementById('k2-input'); }
  function sendBtn() { return document.getElementById('k2-send'); }

  function setInputEnabled(on, placeholder) {
    var input = inputEl();
    var btn = sendBtn();
    if (input) {
      input.disabled = !on;
      input.placeholder = placeholder || (on ? '向知识库提问…' : '请先完成知识库准备');
    }
    if (btn) {
      btn.style.opacity = on ? '1' : '.45';
      btn.style.pointerEvents = on ? 'auto' : 'none';
    }
  }
  function appendMsg(role, text, citations, skipScroll, meta) {
    var box = rowsBox();
    if (!box) return null;
    meta = meta || {};
    if (role === 'user') {
      var voice = kbVoiceMetaFromMessage(meta);
      if (voice) return appendKbVoiceHistoryRow(voice, text, meta);
    }
    var row = document.createElement('div');
    row.className = 'msg-row ' + (role === 'user' ? 'sent' : 'recv');
    if (meta.id) row.setAttribute('data-message-id', String(meta.id));
    if (meta.createdAt) row.setAttribute('data-created-at', String(meta.createdAt));
    if (role === 'user') {
      var time = formatTime(meta.createdAt);
      row.innerHTML = '<div class="msg-av-sm person-e">我</div><div class="msg-content"><div class="msg-meta"><span class="nm">我</span>' + (time ? '<span>' + time + '</span>' : '') + '</div><div class="msg-bubble sent">' + esc(text) + '</div></div>';
    } else {
      var time2 = formatTime(meta.createdAt);
      var cites = '';
      (citations || []).slice(0, 3).forEach(function (c) {
        var title = c.documentTitle || c.title || c.document_id || '知识库文档';
        var page = c.page ? (' · 第 ' + c.page + ' 页') : '';
        var chunk = c.chunkText || c.chunk || c.content || '';
        cites += '<div class="doc-excerpt"><div class="de-bd"><div class="de-h"><span class="src">' + esc(title) + '</span><span class="pg">' + esc(page) + '</span></div><div class="de-q">' + esc(chunk) + '</div></div></div>';
      });
      row.innerHTML = kbAvHtml() + '<div class="msg-content" style="max-width:88%"><div class="msg-meta"><span class="nm">知识库</span><span class="badge-ai">AI</span>' + (time2 ? '<span>' + time2 + '</span>' : '') + '</div><div class="msg-bubble ai-recv kb-ai-bubble">' + kbBubbleHtml(text) + cites + '</div></div>';
    }
    box.appendChild(row);
    if (!skipScroll) scrollK2();
    return row;
  }
  function renderEmpty(readiness) {
    var box = rowsBox();
    if (!box) return;
    var msg = readiness && readiness.message ? readiness.message : '请先上传文档或订阅知识库后再开始提问';
    var title = kbEmptyTitle(readiness);
    var hint = String(readiness && readiness.code || '') === 'nova_not_ready' || String(readiness && readiness.code || '') === 'rag_not_ready'
      ? '系统正在为您开通 New API 与知识库账号，请稍候再试。'
      : '完成准备后即可向知识库提问。';
    box.innerHTML = '<div class="msg-row recv">' + kbAvHtml() + '<div class="msg-content" style="max-width:88%"><div class="msg-bubble ai-recv kb-ai-bubble"><p style="margin:0 0 6px;font-weight:600">' + esc(title) + '</p><p style="margin:0 0 8px">' + esc(msg) + '</p><p style="margin:0 0 10px;font-size:12px;color:var(--text-3)">' + esc(hint) + '</p><div class="k2-kb-entry tappable" id="k2-empty-retry" role="button" tabindex="0"><div class="k2-kb-ic"><i class="ti ti-refresh"></i></div><div class="k2-kb-bd"><div class="k2-kb-t">刷新状态</div><div class="k2-kb-d">账号或文档就绪后重试</div></div><i class="ti ti-chevron-right k2-kb-arr"></i></div><div class="k2-kb-entry tappable" id="k2-empty-go-kb" role="button" tabindex="0" style="margin-top:8px"><div class="k2-kb-ic"><i class="ti ti-books"></i></div><div class="k2-kb-bd"><div class="k2-kb-t">去我的知识库</div><div class="k2-kb-d">上传文档或订阅知识库</div></div><i class="ti ti-chevron-right k2-kb-arr"></i></div></div></div></div>';
    var retry = document.getElementById('k2-empty-retry');
    if (retry) retry.addEventListener('click', function () {
      if (typeof onScreen === 'function') onScreen('K2');
    });
    var btn = document.getElementById('k2-empty-go-kb');
    if (btn) btn.addEventListener('click', function () {
      window.pendingKbHomeFrom = 'K2';
      if (typeof go === 'function') go('K1');
    });
    setInputEnabled(false, '请先上传或订阅知识库');
  }
  function renderMessages(items) {
    var box = rowsBox();
    if (!box) return;
    box.innerHTML = '';
    var prevAt = null;
    (items || []).forEach(function (m) {
      var at = m.createdAt || m.created_at || '';
      var label = dayDividerLabel(at, prevAt);
      if (label) box.appendChild(dateDivider(label));
      appendMsg(m.role === 'user' ? 'user' : 'assistant', m.content || '', m.citations || [], true, { id: m.id, createdAt: at, metadata: m.metadata || null });
      prevAt = at;
    });
    msgHasMore = false;
    msgOldestId = items && items.length ? Number(items[0].id || 0) : 0;
    scrollK2();
  }
  function ensureSession(forceNew) {
    var kind = String(window.pendingKbKind || 'KB_ALL').toUpperCase();
    var path = forceNew ? '/ai/conversations/sessions/new' : '/ai/conversations/sessions/ensure';
    return apiJson(path, { method: 'POST', body: JSON.stringify({ kind: kind }) }).then(function (d) {
      convId = Number(d.conversationId || 0);
      return d;
    });
  }
  function showKbTip(msg) {
    msg = String(msg || '').trim() || '请稍后再试';
    if (window.DunesDialog && typeof window.DunesDialog.alert === 'function') {
      return window.DunesDialog.alert(msg);
    }
    if (window.DunesAPI && typeof window.DunesAPI.toast === 'function') {
      window.DunesAPI.toast(msg);
      return Promise.resolve();
    }
    var phone = document.querySelector('.screen.active .phone-screen') || document.querySelector('.phone-screen');
    if (phone) {
      var t = document.createElement('div');
      t.className = 'toast-tmp';
      t.style.cssText = 'position:absolute;left:50%;bottom:88px;transform:translateX(-50%);max-width:88%;background:rgba(20,20,20,.88);color:#fff;padding:10px 14px;border-radius:9px;font-size:11.5px;z-index:80;line-height:1.4;text-align:center';
      t.textContent = msg;
      phone.appendChild(t);
      setTimeout(function () { t.remove(); }, 3200);
    }
    return Promise.resolve();
  }
  function checkReady() {
    return apiJson('/kb/readiness').catch(function (err) {
      var detail = String((err && err.message) || '');
      var msg = '知识库服务暂不可用，请稍后重试';
      if (/502|503|504|upstream|ECONNREFUSED|connect|HTTP 5/i.test(detail)) {
        msg = '知识库服务连接失败，请确认后端 kb-go 已启动';
      }
      return { canChat: false, code: 'service_unavailable', message: msg };
    });
  }
  function showKbNotReadyTip(readiness) {
    var msg = String((readiness && readiness.message) || '知识库正在准备中，请稍后再试').trim();
    showKbTip(msg);
  }
  var KB_ENTRY_OK_KEY = 'dunes_kb_entry_ok';
  var KB_ENTRY_OK_TTL_MS = 30 * 60 * 1000;
  function markKbEntryOk() {
    try { sessionStorage.setItem(KB_ENTRY_OK_KEY, String(Date.now())); } catch (e) {}
  }
  function kbEntryRecentlyOk() {
    try {
      var t = Number(sessionStorage.getItem(KB_ENTRY_OK_KEY) || 0);
      return t > 0 && Date.now() - t < KB_ENTRY_OK_TTL_MS;
    } catch (e) { return false; }
  }
  function kbAccountsReady(readiness) {
    if (!readiness) return false;
    if (readiness.canChat) return true;
    var code = String(readiness.code || '');
    if (code === 'ready') return true;
    if (code === 'service_unavailable' || code === 'check_failed') return false;
    if (code === 'rag_not_ready') return false;
    var rag = readiness.rag || {};
    if (rag.ready === true) {
      var docs = readiness.documents || {};
      var rf = readiness.ragflow || {};
      var subs = rf.subscriptions || {};
      if (docs.hasIndexed || Number(docs.indexed || 0) > 0 || Number(rf.indexedDocCount || 0) > 0 || Number(subs.active || 0) > 0) {
        return true;
      }
    }
    if (code === 'credentials_unavailable') {
      var docs2 = readiness.documents || {};
      var rf2 = readiness.ragflow || {};
      var subs2 = rf2.subscriptions || {};
      if (docs2.hasIndexed || Number(docs2.indexed || 0) > 0 || Number(rf2.indexedDocCount || 0) > 0 || Number(subs2.active || 0) > 0) return true;
    }
    return false;
  }
  function hasKbChatHistory() {
    return apiJson('/ai/conversations?kind=KB_ALL&size=10').then(function (d) {
      var items = d.items || d.conversations || [];
      for (var i = 0; i < items.length; i++) {
        var row = items[i] || {};
        if (Number(row.messageCount || row.message_count || 0) > 0) return true;
      }
      return false;
    }).catch(function () { return false; });
  }
  function guardKbEntry(opts) {
    opts = opts || {};
    if (opts.fromHistory || window.__dunesKbOpenFromHistory || kbEntryRecentlyOk()) return Promise.resolve(true);
    return hasKbChatHistory().then(function (hadChat) {
      if (hadChat) {
        markKbEntryOk();
        return true;
      }
      return checkReady().then(function (readiness) {
        if (readiness && readiness.canChat) {
          markKbEntryOk();
          return true;
        }
        if (kbAccountsReady(readiness)) {
          markKbEntryOk();
          return true;
        }
        showKbNotReadyTip(readiness);
        return false;
      });
    });
  }
  function kbEmptyTitle(readiness) {
    var code = String((readiness && readiness.code) || '');
    if (code === 'service_unavailable' || code === 'check_failed') return '服务暂不可用';
    if (code === 'nova_not_ready' || code === 'rag_not_ready') return '账号开通中';
    if (code === 'documents_parsing') return '文档解析中';
    if (code === 'no_kb_source') return '暂无知识库内容';
    return '暂时无法对话';
  }
  function loadConversation() {
    if (!convId) return Promise.resolve();
    return apiJson('/ai/conversations/' + convId + '?size=40').then(function (d) {
      var items = d.items || d.messages || [];
      renderMessages(items);
      msgHasMore = !!d.hasMore;
      msgOldestId = items.length ? Number(items[0].id || 0) : 0;
      var g = d.assistantGenerating || {};
      if (g.active || loadPersistedKbGenerating(convId)) {
        kbGenerating = true;
        kbGenStatus = g.status || kbGenStatus || '知识库助手正在生成…';
        showPendingGenerating();
        startKbPoll();
      } else {
        kbGenerating = false;
        clearKbGenerating(convId);
      }
    }).catch(function (e) {
      var box = rowsBox();
      if (box) box.innerHTML = '<div class="api-strip"><span>' + esc(e.message || e) + '</span></div>';
    });
  }
  function loadKbSessionAfterReady() {
    var sessionPromise;
    if (window.__dunesKbOpenFromHistory && window.pendingKbConvId) {
      convId = Number(window.pendingKbConvId || 0);
      window.pendingKbConvId = null;
      window.__dunesKbOpenFromHistory = false;
      sessionPromise = Promise.resolve({ conversationId: convId });
    } else {
      window.pendingKbConvId = null;
      window.__dunesKbOpenFromHistory = false;
      sessionPromise = ensureSession(false);
    }
    setInputEnabled(true, '向知识库提问…');
    return sessionPromise.then(function () {
      return loadConversation().then(function () {
        applyKbChatChrome();
        scrollK2();
      });
    });
  }
  function onScreen(screen) {
    if (screen === 'K2') {
      wireK2();
      wireK2Scroll();
      applyKbChatChrome();
      var box = rowsBox();
      if (box) box.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>正在加载知识库会话…</span></div>';
      setInputEnabled(false, '正在加载…');
      return checkReady().then(function (readiness) {
        if (!readiness.canChat && !kbAccountsReady(readiness)) {
          return hasKbChatHistory().then(function (hadChat) {
            if (!hadChat) {
              renderEmpty(readiness);
              return;
            }
            return loadKbSessionAfterReady();
          });
        }
        return loadKbSessionAfterReady();
      }).catch(function (e) {
        var box = rowsBox();
        if (box) box.innerHTML = '<div class="api-strip"><span>' + esc(e.message || e) + '</span></div>';
      });
    }
    if (screen === 'K11') {
      wireK11();
      return loadHistory(false);
    }
  }
  function wireK2() {
    var input = inputEl();
    var btn = sendBtn();
    var back = document.getElementById('k2-back');
    if (back && !back.dataset.kbWired) {
      back.dataset.kbWired = '1';
      back.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        stopKbPoll();
        window.pendingKbConvId = null;
        window.__dunesKbOpenFromHistory = false;
        convId = 0;
        var from = String(window.pendingKbFrom || '').toUpperCase();
        window.pendingKbFrom = '';
        var target = from === 'C1' ? 'C1' : (from === 'K3' ? 'K3' : 'K1');
        if (typeof go === 'function') go(target);
      });
    }
    if (input && !input.dataset.kbWired) {
      input.dataset.kbWired = '1';
      input.dataset.wired = '1';
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          e.stopImmediatePropagation();
          sendCurrent();
        }
      }, true);
    }
    if (btn && !btn.dataset.kbWired) {
      btn.dataset.kbWired = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopImmediatePropagation();
        sendCurrent();
      }, true);
    }
    var hist = document.getElementById('k2-btn-history');
    if (hist && !hist.dataset.kbWired) {
      hist.dataset.kbWired = '1';
      hist.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); if (typeof go === 'function') go('K11'); });
    }
    var search = document.getElementById('k2-btn-search');
    if (search && !search.dataset.kbWired) {
      search.dataset.kbWired = '1';
      search.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (typeof go === 'function') go('K11');
        setTimeout(function () {
          var btn = document.getElementById('k11-header-search');
          if (btn) btn.click();
        }, 160);
      });
    }
    var add = document.getElementById('k2-btn-new');
    if (add && !add.dataset.kbWired) {
      add.dataset.kbWired = '1';
      add.addEventListener('click', function (e) {
        e.preventDefault(); e.stopPropagation();
        ensureSession(true).then(loadConversation);
      });
    }
    var kb = document.getElementById('k2-btn-kb');
    if (kb && !kb.dataset.kbWired) {
      kb.dataset.kbWired = '1';
      kb.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        window.pendingKbHomeFrom = 'K2';
        if (typeof go === 'function') go('K1');
      });
    }
    wireK2Voice();
  }
  function wireK2Voice() {
    var screen = document.querySelector('.screen[data-screen="K2"]');
    if (!screen || screen.dataset.kbVoiceWired) return;
    if (typeof window.__dunesWireHoldToTalkVoice !== 'function') return;
    window.__dunesWireHoldToTalkVoice({
      screen: screen,
      prefix: 'k2',
      textInput: inputEl(),
      canRecord: function () { return !sending && !kbGenerating && !!convId; },
      onBlocked: function () {
        if (!convId) alert('请先进入知识库对话');
        else if (sending || kbGenerating) alert('知识库助手正在回复，请稍候');
      },
      beforeRecord: function () {
        if (convId) return Promise.resolve();
        return ensureSession(false);
      },
      onVoiceBlob: async function (blob, recMime, sec) {
        sec = Math.max(1, Number(sec) || 1);
        var localUrl = URL.createObjectURL(blob);
        var voiceRow = appendKbVoiceBubble(sec, localUrl, '', true);
        var voiceMeta = { voice: { url: localUrl, durationSec: sec, mimeType: String(recMime || blob.type || 'audio/webm') } };
        try {
          var prepared = await kbVoiceUploadBlob(blob, recMime);
          voiceMeta.voice.mimeType = prepared.mimeType;
          var voiceFile;
          try { voiceFile = new File([prepared.blob], prepared.fileName, { type: prepared.mimeType }); } catch (_) { voiceFile = prepared.blob; voiceFile.name = prepared.fileName; }
          try {
            var up = await uploadViaPresigned(voiceFile);
            voiceMeta.voice.url = up.url || up.objectKey || localUrl;
            voiceMeta.voice.objectKey = up.objectKey || up.url || '';
            updateKbVoiceBubble(voiceRow, sec, voiceMeta.voice.url, voiceMeta.voice.objectKey);
          } catch (_) {}
          var text = await transcribeKbVoice(prepared);
          voiceMeta.voice.transcript = text;
          finishKbVoiceBubble(voiceRow, text);
          sendVoiceQuestion(text, voiceMeta);
        } catch (err) {
          finishKbVoiceBubble(voiceRow);
          var savedVoice = await saveKbVoiceUserMessage('[语音]', voiceMeta);
          tagKbVoiceRow(voiceRow, savedVoice);
          var errText = kbAsrDialogueMessage(err);
          var savedAssistant = await saveKbLocalAssistant(errText);
          appendMsg('assistant', errText, [], false, savedAssistant && savedAssistant.messageId ? { id: savedAssistant.messageId } : {});
        }
      }
    });
    screen.dataset.kbVoiceWired = '1';
  }
  function appendCitations(bubble, acc, citations, source) {
    if (!bubble) return;
    acc = kbSanitizeAnswer(acc);
    bubble.innerHTML = kbBubbleHtml(acc || '暂时无法从知识库检索到相关内容，请确认文档已上传并完成解析。');
    (citations || []).slice(0, 3).forEach(function (c) {
      var div = document.createElement('div');
      div.className = 'doc-excerpt';
      div.innerHTML = '<div class="de-bd"><div class="de-h"><span class="src">' + esc(c.documentTitle || c.title || '知识库文档') + '</span></div><div class="de-q">' + esc(c.chunkText || c.chunk || c.content || '') + '</div></div>';
      bubble.appendChild(div);
    });
    if (source === 'mock') {
      var hint = document.createElement('div');
      hint.className = 'kb-mock-hint';
      hint.textContent = '演示回复 · RAGFlow 未返回检索结果';
      bubble.appendChild(hint);
    }
    scrollK2();
  }
  function mergeKbStreamText(acc, text) {
    text = String(text || '');
    if (!text) return acc || '';
    acc = String(acc || '');
    if (!acc) return text;
    if (text === acc) return acc;
    if (text.indexOf(acc) === 0) return text;
    if (acc.length >= 80 && acc.indexOf(text) === 0) return acc;
    if (acc.indexOf(text) >= 0 && text.length > 12) return acc;
    var max = Math.min(acc.length, text.length);
    for (var i = max; i > 0; i--) {
      if (acc.slice(-i) === text.slice(0, i)) return dedupeKbAnswer(acc + text.slice(i));
    }
    return dedupeKbAnswer(acc + text);
  }
  function showPendingGenerating() {
    var box = rowsBox();
    if (!box || box.querySelector('.kb-server-pending')) return;
    var row = appendMsg('assistant', kbGenStatus || '知识库助手正在生成…', [], false);
    if (row) row.classList.add('kb-server-pending');
    setInputEnabled(false, '知识库助手生成中…');
    patchKbInbox(true);
  }
  function removePendingGenerating() {
    var box = rowsBox();
    if (!box) return;
    box.querySelectorAll('.kb-server-pending').forEach(function (el) { if (el.parentNode) el.parentNode.removeChild(el); });
  }
  function startKbPoll() {
    if (kbGenPollTimer || !convId) return;
    persistKbGenerating(convId, kbGenStatus);
    kbGenPollTimer = setInterval(function () {
      if (!convId) { stopKbPoll(); return; }
      apiJson('/ai/conversations/' + convId + '?size=40').then(function (d) {
        var g = d.assistantGenerating || {};
        if (g.active) {
          kbGenerating = true;
          kbGenStatus = g.status || kbGenStatus || '知识库助手正在生成…';
          persistKbGenerating(convId, kbGenStatus);
          showPendingGenerating();
          return;
        }
        stopKbPoll();
        kbGenerating = false;
        clearKbGenerating(convId);
        removePendingGenerating();
        renderMessages(d.items || d.messages || []);
        setInputEnabled(true, '向知识库提问…');
        var items = d.items || d.messages || [];
        if (activeIs('C1')) patchKbInbox(false, items.length ? items[items.length - 1].content : '', new Date().toISOString());
      }).catch(function () {});
    }, 2500);
  }
  function stopKbPoll() {
    if (kbGenPollTimer) {
      clearInterval(kbGenPollTimer);
      kbGenPollTimer = null;
    }
  }
  function wireK2Scroll() {
    var stream = streamBox();
    if (!stream || stream.dataset.kbScrollWired) return;
    stream.dataset.kbScrollWired = '1';
    stream.addEventListener('scroll', function () {
      if (stream.scrollTop < 72) loadOlderMessages();
    });
  }
  function loadOlderMessages() {
    if (msgLoadingOlder || !msgHasMore || !convId || !msgOldestId) return Promise.resolve();
    var box = rowsBox();
    var stream = streamBox();
    if (!box || !stream) return Promise.resolve();
    msgLoadingOlder = true;
    var prevHeight = stream.scrollHeight;
    return apiJson('/ai/conversations/' + convId + '?size=20&before=' + msgOldestId).then(function (d) {
      var items = d.items || d.messages || [];
      msgHasMore = !!d.hasMore;
      if (!items.length) return;
      msgOldestId = Number(items[0].id || msgOldestId);
      var frag = document.createDocumentFragment();
      var prevAt = null;
      items.forEach(function (m) {
        if (m.id && box.querySelector('[data-message-id="' + m.id + '"]')) return;
        var at = m.createdAt || '';
        var label = dayDividerLabel(at, prevAt);
        if (label) frag.appendChild(dateDivider(label));
        var wrap = document.createElement('div');
        var row = appendMsg(m.role === 'user' ? 'user' : 'assistant', m.content || '', m.citations || [], true, { id: m.id, createdAt: at, metadata: m.metadata || null });
        if (row && row.parentNode) {
          row.parentNode.removeChild(row);
          frag.appendChild(row);
        }
        prevAt = at;
      });
      box.insertBefore(frag, box.firstChild);
      stream.scrollTop = stream.scrollHeight - prevHeight;
    }).catch(function () {}).then(function () { msgLoadingOlder = false; });
  }
  function sendCurrent(forcedText, skipUserBubble, voiceMeta) {
    if (sending) return;
    if (forcedText != null && typeof forcedText !== 'string') forcedText = null;
    var input = inputEl();
    var text = forcedText != null ? String(forcedText || '').trim() : (input ? String(input.value || '').trim() : '');
    if (!text || !convId) return;
    sending = true;
    setInputEnabled(false, '知识库助手思考中…');
    if (input && forcedText == null) input.value = '';
    if (!skipUserBubble) appendMsg('user', text);
    var row = appendMsg('assistant', '正在检索知识库…');
    var bubble = row ? row.querySelector('.msg-bubble') : null;
    var acc = '';
    var cites = [];
    var finished = false;
    var answerSource = '';
    kbGenerating = true;
    kbGenStatus = '知识库助手正在生成…';
    persistKbGenerating(convId, kbGenStatus);
    patchKbInbox(true);
    var streamBody = { content: text };
    if (voiceMeta) streamBody.metadata = voiceMeta;
    fetch(apiBase() + '/ai/conversations/' + convId + '/messages/stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token() },
      body: JSON.stringify(streamBody)
    }).then(function (r) {
      if (!r.ok) {
        return r.text().then(function (body) {
          var msg = '知识库问答暂不可用，请稍后重试';
          try { var j = JSON.parse(body); if (j.message) msg = j.message; } catch (e) {}
          throw new Error(msg);
        });
      }
      var reader = r.body.getReader();
      var dec = new TextDecoder();
      var sseBuf = '';
      function pump() {
        return reader.read().then(function (chunk) {
          if (chunk.done) {
            if (!finished && bubble) appendCitations(bubble, acc, cites, answerSource);
            return;
          }
          sseBuf += dec.decode(chunk.value, { stream: true });
          var blocks = sseBuf.split('\n\n');
          sseBuf = blocks.pop() || '';
          blocks.forEach(function (block) {
            var dataLine = '';
            block.split('\n').forEach(function (line) { if (line.indexOf('data:') === 0) dataLine = line.slice(5).trim(); });
            if (!dataLine) return;
            try {
              var ev = JSON.parse(dataLine);
              if (ev.event === 'error' && ev.message) {
                finished = true;
                kbGenerating = false;
                clearKbGenerating(convId);
                if (bubble) bubble.innerHTML = kbBubbleHtml(ev.message);
                scrollK2();
              }
              if (ev.event === 'assistant_saved' && ev.text && bubble) {
                acc = mergeKbStreamText(acc, ev.text);
                bubble.innerHTML = kbBubbleHtml(acc || ev.text);
                if (ev.messageId && row) row.setAttribute('data-message-id', String(ev.messageId));
                scrollK2();
              }
              if (ev.event === 'user_saved' && ev.messageId) {
                var liveVoice = document.querySelector('#k2-api-rows .msg-row[data-kb-voice="1"]:not([data-message-id])');
                tagKbVoiceRow(liveVoice, { messageId: ev.messageId });
              }
              if (ev.event === 'delta' && ev.text) {
                acc = mergeKbStreamText(acc, ev.text);
                if (bubble) bubble.innerHTML = kbBubbleHtml(acc);
                scrollK2();
              }
              if (ev.source) answerSource = ev.source;
              if (ev.event === 'citations') {
                cites = ev.citations || [];
                finished = true;
                kbGenerating = false;
                clearKbGenerating(convId);
                appendCitations(bubble, acc, cites, answerSource);
              }
              if (ev.event === 'done' && !finished) {
                finished = true;
                kbGenerating = false;
                clearKbGenerating(convId);
                appendCitations(bubble, acc, cites, answerSource);
              }
            } catch (e) {}
          });
          return pump();
        });
      }
      return pump();
    }).catch(function (e) {
      kbGenerating = false;
      clearKbGenerating(convId);
      if (bubble) bubble.textContent = e.message || '知识库问答暂不可用，请稍后重试';
    }).then(function () {
      sending = false;
      patchKbInbox(false, kbSanitizeAnswer(acc) || (bubble ? bubble.textContent : ''), new Date().toISOString());
      setInputEnabled(true, '向知识库提问…');
    });
  }
  function wireK11() {
    var btn = document.getElementById('k11-header-search');
    var bar = document.getElementById('k11-search-bar');
    var input = document.getElementById('k11-search-input');
    var clear = document.getElementById('k11-search-clear');
    if (btn && !btn.dataset.kbWired) {
      btn.dataset.kbWired = '1';
      btn.addEventListener('click', function () {
        var on = bar && bar.style.display === 'none';
        if (bar) bar.style.display = on ? 'flex' : 'none';
        if (on && input) input.focus();
      });
    }
    if (input && !input.dataset.kbWired) {
      input.dataset.kbWired = '1';
      input.addEventListener('input', function () { filterHistory(input.value); });
    }
    if (clear && !clear.dataset.kbWired) {
      clear.dataset.kbWired = '1';
      clear.addEventListener('click', function () { if (input) input.value = ''; filterHistory(''); });
    }
  }
  function loadHistory() {
    var box = document.getElementById('k11-api-rows');
    if (!box) return Promise.resolve();
    historyLoading = true;
    historyNextBefore = '';
    box.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>加载对话历史…</span></div>';
    return apiJson('/kb/chat/history?view=turns&size=30').then(function (d) {
      historyAll = Array.isArray(d) ? d : (d.items || []);
      historyHasMore = !!d.hasMore;
      historyNextBefore = d.nextBefore || '';
      renderHistory(historyAll);
    }).catch(function (e) {
      box.innerHTML = '<div class="api-strip"><span>' + esc(e.message || e) + '</span></div>';
    }).then(function () {
      historyLoading = false;
    });
  }
  function loadMoreHistory() {
    if (historyLoading || !historyHasMore || !historyNextBefore) return Promise.resolve();
    historyLoading = true;
    return apiJson('/kb/chat/history?view=turns&size=30&before=' + encodeURIComponent(historyNextBefore)).then(function (d) {
      var items = d.items || [];
      historyAll = historyAll.concat(items);
      historyHasMore = !!d.hasMore;
      historyNextBefore = d.nextBefore || '';
      renderHistory(historyAll);
    }).then(function () { historyLoading = false; }, function () { historyLoading = false; });
  }
  function filterHistory(q) {
    q = String(q || '').toLowerCase();
    if (!q) return renderHistory(historyAll);
    renderHistory(historyAll.filter(function (r) {
      return String(r.title || '').toLowerCase().indexOf(q) >= 0 || String(r.lastMessagePreview || '').toLowerCase().indexOf(q) >= 0;
    }));
  }
  function renderHistory(rows) {
    var box = document.getElementById('k11-api-rows');
    if (!box) return;
    box.innerHTML = '';
    if (!rows.length) {
      box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>暂无知识库对话</span></div>';
      return;
    }
    var prevAt = null;
    rows.forEach(function (r) {
      var label = dayDividerLabel(r.lastMessageAt, prevAt);
      if (label) {
        var divider = document.createElement('div');
        divider.className = 'msg-date-divider';
        divider.textContent = label;
        box.appendChild(divider);
      }
      var div = document.createElement('div');
      div.className = 'noti-card tappable';
      var title = String(r.title || '').trim() || '提问';
      var preview = String(r.lastMessagePreview || '').trim();
      var desc = r.assistantGenerating ? ('<span class="generating"><i class="ti ti-loader ti-spin"></i> ' + esc(r.assistantGeneratingStatus || '知识库助手正在生成…') + '</span>') : esc(preview || '（暂无回答预览）');
      div.innerHTML = '<div class="nc-ic">' + (window.dunesKbIconHtml ? window.dunesKbIconHtml() : '<i class="ti ti-book"></i>') + '</div><div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(title) + '</div><div class="nc-time">' + esc(formatHistoryTime(r.lastMessageAt)) + '</div></div><div class="nc-desc">' + desc + '</div></div>';
      div.addEventListener('click', function () {
        convId = Number(r.conversationId || 0);
        window.pendingKbConvId = convId;
        window.__dunesKbOpenFromHistory = true;
        if (typeof go === 'function') go('K2');
      });
      box.appendChild(div);
      prevAt = r.lastMessageAt;
    });
    if (historyHasMore) {
      var more = document.createElement('div');
      more.className = 'api-strip tappable';
      more.innerHTML = '<i class="ti ti-arrow-down"></i><span>加载更多历史</span>';
      more.addEventListener('click', loadMoreHistory);
      box.appendChild(more);
    }
  }
  function onLeave(prevScreen) {
    if (prevScreen === 'K2') {
      stopKbPoll();
      window.pendingKbConvId = null;
      window.__dunesKbOpenFromHistory = false;
    }
  }
  return { onScreen: onScreen, onLeave: onLeave, guardKbEntry: guardKbEntry, loadHistory: loadHistory, patchKbInbox: patchKbInbox, refreshKbInboxPreview: refreshKbInboxPreview, applyKbChatChrome: applyKbChatChrome };
})();
''';
}
