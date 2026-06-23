/// Nova OpenAI 兼容 API 适配层 + C4/K2 运行时补丁（UI 不变）。
abstract final class NovaApiInjection {
  static const js = r'''
window.DunesNovaApi = (function () {
  var ASR_MODEL = 'glm-asr-2512';

  function novaBase() {
    return String(window.__dunesNovaBase || localStorage.getItem('dunes_nova_base') || '__NOVA_BASE_URL__').replace(/\/$/, '');
  }
  function dunesBase() {
    return String(window.__dunesApiBase || localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__').replace(/\/$/, '');
  }
  function dunesToken() {
    return window.__dunesToken || localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
  }
  function novaKey() {
    return window.__dunesNovaApiKey || localStorage.getItem('dunes_nova_api_key') || '';
  }
  function novaBizUser() {
    var u = window.__dunesNovaBizUserId || localStorage.getItem('dunes_nova_biz_user_id') || '';
    if (u) return u;
    var uid = localStorage.getItem('dunes_user_id');
    if (uid) return 'dune_' + uid;
    return '';
  }
  function ensureNovaProfileSession() {
    var biz = novaBizUser();
    if (!biz) return localStorage.getItem('dunes_nova_profile_session') || '';
    var key = 'profile-' + biz;
    try {
      var prev = localStorage.getItem('dunes_nova_profile_session');
      if (prev !== key) localStorage.setItem('dunes_nova_profile_session', key);
    } catch (e) {}
    return key;
  }
  function novaProfileSessionId() {
    var key = localStorage.getItem('dunes_nova_profile_session') || '';
    if (key) return key;
    return ensureNovaProfileSession();
  }
  // chat/completions 带 profile-{bizUserId}，双端 Nova 记忆互通；messages 仍仅 system + 本条 user
  function novaChatRequestSessionId(opts) {
    opts = opts || {};
    if (opts.sessionId != null && String(opts.sessionId).trim()) {
      return String(opts.sessionId).trim();
    }
    return novaProfileSessionId();
  }
  function novaThreadSessionId(opts) {
    opts = opts || {};
    if (opts.sessionId) return String(opts.sessionId);
    var profileSid = novaProfileSessionId();
    if (profileSid) return profileSid;
    if (opts.conversationId != null && String(opts.conversationId) !== '' && String(opts.conversationId) !== '0') {
      return 'conv-' + String(opts.conversationId);
    }
    var legacy = localStorage.getItem('dunes_nova_chat_session') || '';
    if (legacy && String(legacy).indexOf('profile-') === 0) return legacy;
    return legacy || '';
  }
  function isGlmModel(id) {
    return /^glm/i.test(String(id || '').trim());
  }
  function chatSelectableModels() {
    var allowed = [];
    try { allowed = JSON.parse(localStorage.getItem('dunes_allowed_models') || '[]'); } catch (e) {}
    if (!allowed.length) allowed = [defaultModel()];
    var out = [];
    for (var i = 0; i < allowed.length; i++) {
      if (!isGlmModel(allowed[i])) out.push(allowed[i]);
    }
    out = out.filter(function (v, idx, arr) { return arr.indexOf(v) === idx; });
    if (!out.length) {
      var def = defaultModel();
      if (def && !isGlmModel(def)) out.push(def);
    }
    if (!out.length) out = ['nova_deepseek'];
    return out;
  }
  function selectedChatModel() {
    var sel = String(localStorage.getItem('dunes_nova_chat_model') || '').trim();
    var list = chatSelectableModels();
    if (sel && list.indexOf(sel) >= 0) return sel;
    var def = defaultModel();
    if (def && list.indexOf(def) >= 0) return def;
    return list[0] || def || 'nova_deepseek';
  }
  function setSelectedChatModel(id) {
    id = String(id || '').trim();
    if (!id) return;
    localStorage.setItem('dunes_nova_chat_model', id);
  }
  function modelDisplayName(id) {
    return String(id || '').trim().toUpperCase();
  }
  function storeModelCatalog(catalog) {
    if (!catalog || !catalog.length) return;
    try { localStorage.setItem('dunes_nova_model_catalog', JSON.stringify(catalog)); } catch (e) {}
  }
  function modelDisplayIntro(id) {
    id = String(id || '').trim();
    try {
      var raw = localStorage.getItem('dunes_nova_model_catalog') || '[]';
      var list = JSON.parse(raw);
      if (Array.isArray(list)) {
        for (var i = 0; i < list.length; i++) {
          var row = list[i] || {};
          if (String(row.modelId || row.model_id || '') === id) {
            var intro = String(row.intro || row.label || row.description || '').trim();
            if (intro && intro.toUpperCase() !== id.toUpperCase()) return intro;
          }
        }
      }
    } catch (e) {}
    return '';
  }
  function fetchModelCatalog() {
    if (!dunesToken()) return Promise.resolve([]);
    return apiJsonDunes('/me/nova-models').then(function (d) {
      d = d || {};
      var catalog = Array.isArray(d.modelCatalog) ? d.modelCatalog : [];
      storeModelCatalog(catalog);
      return catalog;
    }).catch(function () { return []; });
  }
  function defaultModel() {
    return localStorage.getItem('dunes_nova_default_model') || 'nova_deepseek';
  }
  function novaHeaders(extra) {
    extra = extra || {};
    var h = Object.assign({}, extra);
    var key = novaKey();
    if (key) h.Authorization = 'Bearer ' + key;
    return h;
  }
  function isReady() {
    return localStorage.getItem('dunes_nova_ready') === '1' && !!novaKey();
  }
  function esc(s) {
    return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function apiJsonDunes(path, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ 'Content-Type': 'application/json', Authorization: 'Bearer ' + dunesToken() }, opts.headers || {});
    return fetch(dunesBase() + path, opts).then(function (r) {
      return r.text().then(function (text) {
        var j = {};
        try { if (text && text.trim()) j = JSON.parse(text); } catch (e) { throw new Error(text || ('HTTP ' + r.status)); }
        if (!r.ok || j.success === false) throw new Error(j.message || ('HTTP ' + r.status));
        return j.data !== undefined ? j.data : j;
      });
    });
  }

  function refreshCredentials() {
    if (!dunesToken()) return Promise.resolve({ ready: false });
    return apiJsonDunes('/me/nova-credentials').then(function (d) {
      d = d || {};
      if (d.baseUrl) {
        window.__dunesNovaBase = d.baseUrl;
        localStorage.setItem('dunes_nova_base', d.baseUrl);
      }
      if (d.api_token || d.apiKey) {
        var key = d.api_token || d.apiKey;
        window.__dunesNovaApiKey = key;
        localStorage.setItem('dunes_nova_api_key', key);
      }
      if (d.bizUserId) {
        window.__dunesNovaBizUserId = d.bizUserId;
        localStorage.setItem('dunes_nova_biz_user_id', d.bizUserId);
        localStorage.setItem('dunes_nova_profile_session', 'profile-' + d.bizUserId);
      }
      if (d.defaultModel) localStorage.setItem('dunes_nova_default_model', d.defaultModel);
      if (d.allowedModels) localStorage.setItem('dunes_allowed_models', JSON.stringify(d.allowedModels));
      if (d.asrModel) localStorage.setItem('dunes_nova_asr_model', d.asrModel);
      if (d.modelCatalog) storeModelCatalog(d.modelCatalog);
      localStorage.setItem('dunes_nova_ready', d.ready ? '1' : '0');
      if (d.quota && d.quota.remain != null) localStorage.setItem('dunes_remain_quota', String(d.quota.remain));
      return d;
    }).catch(function () { return { ready: false }; });
  }

  function refreshModelCatalog() {
    return fetchModelCatalog();
  }

  function transcribeAudio(blob, fileName) {
    fileName = fileName || 'audio.wav';
    var form = new FormData();
    try { form.append('file', new File([blob], fileName, { type: blob.type || 'audio/wav' })); } catch (_) { form.append('file', blob, fileName); }
    form.append('model', localStorage.getItem('dunes_nova_asr_model') || ASR_MODEL);
    return fetch(novaBase() + '/v1/audio/transcriptions', {
      method: 'POST',
      headers: novaHeaders(),
      body: form
    }).then(function (r) {
      return r.text().then(function (text) {
        var j = {};
        try { if (text) j = JSON.parse(text); } catch (e) {}
        if (!r.ok) throw new Error((j.error && j.error.message) || j.message || ('语音识别失败 HTTP ' + r.status));
        var data = j.data || {};
        var out = String(
          j.text
          || j.transcript
          || j.result
          || (typeof data === 'string' ? data : '')
          || data.text
          || data.transcript
          || data.result
          || ''
        ).trim();
        if (!out && Array.isArray(j.segments)) out = j.segments.map(function (s) { return s && s.text || ''; }).join('').trim();
        if (!out && Array.isArray(data.segments)) out = data.segments.map(function (s) { return s && s.text || ''; }).join('').trim();
        if (!out && j.choices && j.choices[0] && j.choices[0].message) out = String(j.choices[0].message.content || '').trim();
        if (!out) throw new Error('语音识别未得到有效转写');
        return out;
      });
    });
  }

  function allAllowedModels() {
    var allowed = [];
    try { allowed = JSON.parse(localStorage.getItem('dunes_allowed_models') || '[]'); } catch (e) {}
    if (!allowed.length && defaultModel()) allowed = [defaultModel()];
    return allowed;
  }
  function pickMultimodalModel() {
    var selected = selectedChatModel();
    if (selected) return selected;
    var selectable = chatSelectableModels();
    if (selectable.length) return selectable[0];
    var allowed = allAllowedModels();
    var prefs = ['nova_gpt5.5', 'nova_gpt-image-2', 'nova_deepseek'];
    for (var i = 0; i < prefs.length; i++) {
      if (allowed.indexOf(prefs[i]) >= 0) return prefs[i];
    }
    return defaultModel();
  }

  function readFileAsDataUrl(file) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () { resolve(reader.result || ''); };
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }

  function normalizeImageForVision(file) {
    if (!file || !(file.size > 0)) return Promise.resolve(file);
    var mime = String(file.type || '').toLowerCase();
    var name = String(file.name || '').toLowerCase();
    var isImg = mime.indexOf('image/') === 0 || /\.(jpe?g|png|gif|webp|bmp|heic|heif)$/i.test(name);
    if (!isImg) return Promise.resolve(file);
    return new Promise(function (resolve) {
      var img = new Image();
      var objUrl = '';
      try { objUrl = URL.createObjectURL(file); } catch (e) { resolve(file); return; }
      img.onload = function () {
        try { if (objUrl) URL.revokeObjectURL(objUrl); } catch (e) {}
        var maxDim = 1568;
        var w = img.naturalWidth || img.width || 1;
        var h = img.naturalHeight || img.height || 1;
        var scale = Math.min(1, maxDim / Math.max(w, h));
        var cw = Math.max(1, Math.round(w * scale));
        var ch = Math.max(1, Math.round(h * scale));
        var canvas = document.createElement('canvas');
        canvas.width = cw;
        canvas.height = ch;
        var ctx = canvas.getContext('2d');
        if (!ctx) { resolve(file); return; }
        ctx.drawImage(img, 0, 0, cw, ch);
        canvas.toBlob(function (blob) {
          if (!blob || !(blob.size > 0)) { resolve(file); return; }
          var outName = (file.name || 'image.jpg').replace(/\.[^.]+$/, '') + '.jpg';
          try { resolve(new File([blob], outName, { type: 'image/jpeg' })); }
          catch (_) { blob.name = outName; blob.type = 'image/jpeg'; resolve(blob); }
        }, 'image/jpeg', 0.82);
      };
      img.onerror = function () {
        try { if (objUrl) URL.revokeObjectURL(objUrl); } catch (e) {}
        resolve(file);
      };
      img.src = objUrl;
    });
  }

  function fileToJpegDataUrl(file) {
    return normalizeImageForVision(file).then(function (jpegFile) {
      return readFileAsBase64(jpegFile).then(function (b64) {
        b64 = String(b64 || '').trim();
        if (!b64) throw new Error('图片编码失败，请换 JPG/PNG 重试');
        return 'data:image/jpeg;base64,' + b64;
      });
    });
  }

  function readFileAsBase64(file) {
    return readFileAsDataUrl(file).then(function (dataUrl) {
      var s = String(dataUrl || '');
      var idx = s.indexOf(',');
      return idx >= 0 ? s.slice(idx + 1) : s;
    });
  }

  function fetchBlobFromUrl(url) {
    return fetch(url).then(function (r) { return r.blob(); });
  }

  function storagePublicBase() {
    return (
      localStorage.getItem('dunes_storage_public_base') ||
      localStorage.getItem('dunes_ftp_public_base') ||
      'https://image.heunion.com/zdfiles'
    ).replace(/\/$/, '');
  }

  function joinPublicUrl(base, objectKey) {
    if (!objectKey) return '';
    if (/^https?:\/\//i.test(objectKey)) return objectKey;
    return String(base || '').replace(/\/$/, '') + '/' + String(objectKey).replace(/^\//, '');
  }

  function resolvePublicFileUrl(item) {
    item = item || {};
    var direct = String(item.accessUrl || item.publicUrl || item.url || '').trim();
    if (/^https?:\/\//i.test(direct)) return direct;
    var key = String(item.objectKey || item.url || '').trim();
    if (/^https?:\/\//i.test(key)) return key;
    if (!key) return '';
    var bucket = String(item.bucket || 'im-attachments');
    if (
      item.backend === 'ftp' ||
      bucket === 'im-attachments' ||
      key.indexOf('proposals/') === 0 ||
      key.indexOf('im/') === 0
    ) {
      return joinPublicUrl(storagePublicBase(), key);
    }
    return '';
  }

  function fetchPresignedGetUrl(payload) {
    payload = payload || {};
    var key = String(payload.objectKey || '').trim();
    if (!key || /^https?:\/\//i.test(key)) return Promise.resolve('');
    var bucket = payload.bucket || 'im-attachments';
    var token = dunesToken();
    var base = dunesBase();
    return fetch(base + '/storage/presigned-get?bucket=' + encodeURIComponent(bucket) + '&objectKey=' + encodeURIComponent(key), {
      headers: token ? { Authorization: 'Bearer ' + token } : {}
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.success && j.data && j.data.url) return String(j.data.url);
      return '';
    }).catch(function () { return ''; });
  }

  function resolveVisionImageUrl(payload) {
    payload = payload || {};
    var pub = resolvePublicFileUrl(payload);
    if (pub) return Promise.resolve(pub);
    return fetchPresignedGetUrl(payload);
  }

  function imagePartToBase64(file, imagePartType, parts, slotIdx) {
    return fileToJpegDataUrl(file).then(function (dataUrl) {
      if (dataUrl.length < 128 || dataUrl.indexOf('data:image/jpeg;base64,') !== 0) {
        throw new Error('图片编码失败，请换 JPG/PNG 重试');
      }
      try {
        console.info('[DunesNovaApi] vision jpeg dataUrl len=', dataUrl.length);
      } catch (logErr) {}
      var part;
      if (imagePartType === 'image_url') {
        part = { type: 'image_url', image_url: { url: dataUrl } };
      } else {
        part = { type: 'image', image: dataUrl };
      }
      if (typeof slotIdx === 'number') parts[slotIdx] = part;
      else parts.push(part);
    });
  }

  function blobToFile(payload, blob) {
    payload = payload || {};
    var name = payload.fileName || 'upload.bin';
    var mime = payload.mimeType || blob.type || 'application/octet-stream';
    if ((mime === 'application/octet-stream' || !mime) && /\.(jpe?g|png|gif|webp|bmp)$/i.test(name)) {
      var ext = (name.match(/\.(jpe?g|png|gif|webp|bmp)$/i) || [])[1] || 'jpeg';
      mime = 'image/' + String(ext).replace(/^jpg$/i, 'jpeg').toLowerCase();
    }
    try { return new File([blob], name, { type: mime }); } catch (_) { blob.name = name; return blob; }
  }

  function fetchAttachmentBlobFromKey(objectKey, bucket, fileName, mimeType) {
    bucket = bucket || 'im-attachments';
    var token = dunesToken();
    var base = dunesBase();
    return fetch(base + '/storage/presigned-get?bucket=' + encodeURIComponent(bucket) + '&objectKey=' + encodeURIComponent(objectKey), {
      headers: token ? { Authorization: 'Bearer ' + token } : {}
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (!j.success || !j.data || !j.data.url) throw new Error('无法获取图片临时地址');
      return fetchBlobFromUrl(j.data.url);
    }).then(function (blob) {
      return blobToFile({ fileName: fileName, mimeType: mimeType }, blob);
    });
  }

  function resolveMultimodalFile(file, payload) {
    payload = payload || {};
    if (file && file.size > 0) return Promise.resolve(file);
    var url = String(payload.url || payload.accessUrl || '').trim();
    var key = String(payload.objectKey || '').trim();
    if (!key && url && !/^https?:\/\//i.test(url)) key = url;
    if (key && !/^https?:\/\//i.test(key)) {
      return fetchAttachmentBlobFromKey(key, payload.bucket, payload.fileName, payload.mimeType);
    }
    if (url && /^https?:\/\//i.test(url)) {
      return fetchBlobFromUrl(url).then(function (blob) { return blobToFile(payload, blob); });
    }
    if (key && /^https?:\/\//i.test(key)) {
      return fetchBlobFromUrl(key).then(function (blob) { return blobToFile(payload, blob); });
    }
    return Promise.reject(new Error('附件无法读取，请重新选择图片'));
  }

  function buildMultimodalContent(opts) {
    opts = opts || {};
    var kind = String(opts.kind || 'TEXT').toUpperCase();
    var text = String(opts.text || opts.multimodalPrompt || '').trim();
    var imagePartType = String(opts.imagePartType || localStorage.getItem('dunes_nova_image_part_type') || 'image').trim() || 'image';
    var files = [];
    if (opts.files && opts.files.length) files = Array.prototype.slice.call(opts.files);
    else if (opts.file) files = [opts.file];
    var payloads = [];
    if (opts.payloads && opts.payloads.length) payloads = opts.payloads;
    else if (opts.payload) payloads = [opts.payload];
    var slots = Math.max(files.length, payloads.length);
    if (!slots) {
      if (text) return Promise.resolve(text);
      return Promise.resolve('');
    }
    var parts = [];
    if (text) parts.push({ type: 'text', text: text });
    var mediaParts = new Array(slots);
    var slotJobs = [];
    for (var si = 0; si < slots; si++) {
      (function (idx) {
        var payload = payloads[idx] || payloads[0] || {};
        var fileKind = String(payload.kind || kind || '').toUpperCase();
        var isImg = fileKind === 'IMAGE' || kind === 'IMAGE' || (files[idx] && (files[idx].type || '').indexOf('image/') === 0);
        if (isImg && fileKind !== 'FILE') {
          slotJobs.push(resolveMultimodalFile(files[idx], payload).then(function (resolvedFile) {
            return imagePartToBase64(resolvedFile, imagePartType, mediaParts, idx);
          }));
          return;
        }
        slotJobs.push(resolveMultimodalFile(files[idx], payload).then(function (resolvedFile) {
          return readFileAsBase64(resolvedFile).then(function (b64) {
            mediaParts[idx] = { type: 'file', file: { filename: resolvedFile.name || 'upload.bin', file_data: b64 } };
          });
        }));
      })(si);
    }
    return Promise.all(slotJobs).then(function () {
      mediaParts.forEach(function (p) { if (p) parts.push(p); });
      if (!parts.length) return text || '';
      if (parts.length === 1 && parts[0].type === 'text') return parts[0].text;
      return parts;
    });
  }

  function msgCacheKey(tag, convId) {
    return 'dunes_' + tag + '_msgs_' + String(convId || 0);
  }

  function loadSessionMessages(tag, convId) {
    try {
      var raw = localStorage.getItem(msgCacheKey(tag, convId));
      return raw ? JSON.parse(raw) : [];
    } catch (e) { return []; }
  }

  function saveSessionMessages(tag, convId, items, opts) {
    opts = opts || {};
    var list = items || [];
    if (opts.displayOnly) {
      list = list.map(function (m) {
        if (!m || typeof m !== 'object') return m;
        return Object.assign({}, m, { _displayOnly: true });
      });
    }
    try { localStorage.setItem(msgCacheKey(tag, convId), JSON.stringify(list)); } catch (e) {}
  }

  function appendSessionMessages(tag, convId, newItems) {
    var items = loadSessionMessages(tag, convId);
    (newItems || []).forEach(function (m) {
      m.id = m.id || (Date.now() + Math.floor(Math.random() * 1000));
      m.createdAt = m.createdAt || new Date().toISOString();
      items.push(m);
    });
    if (items.length > 200) items = items.slice(items.length - 200);
    saveSessionMessages(tag, convId, items);
    return items;
  }

  function loadLocalTurns(tag) {
    var key = tag === 'kb' ? 'dunes_kb_local_history' : 'dunes_nova_local_history';
    try { return JSON.parse(localStorage.getItem(key) || '[]'); } catch (e) { return []; }
  }

  function upsertLocalTurn(tag, turn) {
    var key = tag === 'kb' ? 'dunes_kb_local_history' : 'dunes_nova_local_history';
    var arr = loadLocalTurns(tag);
    turn.conversationId = turn.conversationId || turn.id || Date.now();
    turn.lastMessageAt = turn.lastMessageAt || new Date().toISOString();
    var found = false;
    arr = arr.map(function (r) {
      if (Number(r.conversationId) === Number(turn.conversationId)) { found = true; return Object.assign({}, r, turn); }
      return r;
    });
    if (!found) arr.unshift(turn);
    if (arr.length > 40) arr = arr.slice(0, 40);
    try { localStorage.setItem(key, JSON.stringify(arr)); } catch (e) {}
  }

  var AI_LOCAL_PURGE_KEY = 'dunes_ai_local_purge_v';
  var AI_LOCAL_PURGE_VERSION = '2026-06-20-nova-api';

  function clearAllAiLocalHistory() {
    var tags = ['nova', 'kb'];
    tags.forEach(function (tag) {
      try { localStorage.removeItem(tag === 'kb' ? 'dunes_kb_local_history' : 'dunes_nova_local_history'); } catch (e) {}
      try {
        var prefix = 'dunes_' + tag + '_msgs_';
        var drop = [];
        for (var i = 0; i < localStorage.length; i++) {
          var k = localStorage.key(i);
          if (k && k.indexOf(prefix) === 0) drop.push(k);
        }
        drop.forEach(function (k) { try { localStorage.removeItem(k); } catch (e2) {} });
      } catch (e3) {}
    });
    ['dunes_nova_conv_id', 'dunes_nova_history_sync_queue', 'dunes_nova_view_since', 'dunes_nova_chat_session', 'dunes_nova_owner_uid'].forEach(function (k) {
      try { localStorage.removeItem(k); } catch (e4) {}
    });
    try {
      var ssDrop = [];
      for (var j = 0; j < sessionStorage.length; j++) {
        var sk = sessionStorage.key(j);
        if (sk && (sk.indexOf('dunes_nova_generating_') === 0 || sk.indexOf('dunes_nova_stream_draft_') === 0)) ssDrop.push(sk);
      }
      ssDrop.forEach(function (k) { try { sessionStorage.removeItem(k); } catch (e5) {} });
    } catch (e6) {}
  }

  function ensureAiLocalHistoryPurged() {
    try {
      if (localStorage.getItem(AI_LOCAL_PURGE_KEY) === AI_LOCAL_PURGE_VERSION) return;
      clearAllAiLocalHistory();
      localStorage.setItem(AI_LOCAL_PURGE_KEY, AI_LOCAL_PURGE_VERSION);
    } catch (e) {}
  }

  function sessionMessageRole(m) {
    if (!m) return '';
    var role = String(m.role || '').toLowerCase();
    if (role === 'user' || role === 'assistant' || role === 'system') return role;
    var kind = String(m.kind || '').toUpperCase();
    if (kind.indexOf('AI') >= 0) return 'assistant';
    return 'user';
  }

  function sessionMessageContent(m) {
    if (!m) return '';
    if (m.content != null && typeof m.content === 'object') return m.content;
    var text = m.content != null ? m.content : (m.bodyText || '');
    return String(text || '').trim();
  }

  function buildNovaUserSystemMessage() {
    var name = String(localStorage.getItem('dunes_display_name') || '').trim();
    var uid = String(localStorage.getItem('dunes_user_id') || '').trim();
    var phone = String(localStorage.getItem('dunes_phone') || '').trim();
    var biz = novaBizUser();
    if (!name && !uid && !phone && !biz) return null;
    var lines = [
      '你是沙丘 APP 内置的企业助手「云枢」。',
      '以下「当前登录用户」信息来自沙丘账号系统，回答身份/称呼/手机号等问题时必须以此为准，不要臆造或使用其它昵称、历史测试名。'
    ];
    if (name) lines.push('姓名：' + name);
    if (phone) lines.push('手机：' + phone);
    if (uid) lines.push('用户ID：' + uid);
    if (biz) lines.push('系统账号：' + biz);
    lines.push('除非用户明确要求生成/下载文件，否则不要主动附带历史文件或杜撰附件。');
    return { role: 'system', content: lines.join('\n') };
  }

  // 云枢 API 上下文：仅 system（当前登录用户）+ 本条 user，绝不读取 dunes_nova_msgs_* 历史。
  function buildNovaChatMessages(latestContent) {
    var hasLatest = latestContent != null && !(typeof latestContent === 'string' && !String(latestContent).trim());
    var out = [];
    var sys = buildNovaUserSystemMessage();
    if (sys) out.push(sys);
    if (hasLatest) out.push({ role: 'user', content: latestContent });
    return out;
  }

  function buildChatCompletionMessages(opts) {
    opts = opts || {};
    return buildNovaChatMessages(opts.latestContent);
  }

  function chatCompletionsStream(opts) {
    opts = opts || {};
    var messages = opts.messages || [];
    var model = opts.model || selectedChatModel();
    var sessionId = novaChatRequestSessionId(opts);
    var headers = novaHeaders({ 'Content-Type': 'application/json', Accept: 'text/event-stream' });
    if (sessionId) headers['X-Nova-Chat-Session-Id'] = sessionId;
    var body = { model: model, stream: true, messages: messages };
    var bizUser = novaBizUser();
    if (bizUser) body.user = bizUser;
    try {
      console.info(
        '[DunesNovaApi] chat user=', bizUser || '(empty)',
        'session=', sessionId || '(none, stateless)',
        'messages=', messages.length,
        'roles=', messages.map(function (m) { return m && m.role; }).join(',')
      );
    } catch (logErr) {}
    return fetch(novaBase() + '/v1/chat/completions', {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(body),
      signal: opts.signal
    });
  }

  function imagePartTypeForModel(model) {
    model = String(model || '');
    if (/gpt|nova_gpt/i.test(model)) return 'image_url';
    var stored = localStorage.getItem('dunes_nova_image_part_type');
    if (stored) return stored;
    return 'image';
  }
  function parseNovaHttpError(status, text) {
    var msg = 'Nova 请求失败 HTTP ' + status;
    text = String(text || '').trim();
    if (!text) return new Error(msg);
    try {
      var j = JSON.parse(text);
      var m = (j.error && j.error.message) || j.message || msg;
      var c = (j.error && j.error.code) || j.code || '';
      if (c) m += ' (' + c + ')';
      return new Error(m);
    } catch (e) {
      return new Error(text.slice(0, 320));
    }
  }
  function parseSseJsonBlock(block) {
    var dataLine = '';
    String(block || '').split('\n').forEach(function (line) {
      var t = line.trim();
      if (t.indexOf('data:') === 0) dataLine = t.slice(5).trim();
    });
    if (!dataLine || dataLine === '[DONE]') return null;
    try { return JSON.parse(dataLine); } catch (e) { return null; }
  }

  function pumpOpenAiSse(response, handlers) {
    handlers = handlers || {};
    var streamErr = null;
    var hadOutput = false;
    function markOutput() { hadOutput = true; }
    function processJson(j) {
      if (!j) return;
      if (j.quota && handlers.onQuota) handlers.onQuota(j.quota);
      if (j.rag && handlers.onRag) handlers.onRag(j.rag);
      if (j.error) {
        var em = (j.error && j.error.message) || j.message || 'Nova 流式错误';
        var ec = (j.error && j.error.code) || j.code || '';
        streamErr = new Error(ec ? (em + ' (' + ec + ')') : em);
        return;
      }
      var delta = j.choices && j.choices[0] && j.choices[0].delta;
      var msg = j.choices && j.choices[0] && j.choices[0].message;
      if (delta) {
        if (delta.reasoning_content) {
          markOutput();
          if (handlers.onThinkingDelta) handlers.onThinkingDelta(delta.reasoning_content);
          else if (handlers.onDelta) handlers.onDelta(delta.reasoning_content);
        }
        var piece = delta.content != null ? delta.content : (delta.text || '');
        if (piece) {
          markOutput();
          if (handlers.onDelta) handlers.onDelta(typeof piece === 'string' ? piece : String(piece));
        }
      } else if (msg && msg.content != null) {
        markOutput();
        var body = typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content);
        if (body && handlers.onDelta) handlers.onDelta(body);
      }
      if (j.choices && j.choices[0] && j.choices[0].finish_reason && handlers.onDone) handlers.onDone(j);
    }
    function consumeSseText(text) {
      String(text || '').split('\n\n').forEach(function (block) {
        processJson(parseSseJsonBlock(block));
      });
    }
    function finishPump() {
      if (streamErr) return Promise.reject(streamErr);
      if (!hadOutput) return Promise.reject(new Error('Nova 未返回任何内容'));
      if (handlers.onDone) handlers.onDone({});
      return Promise.resolve();
    }
    if (!response.ok) {
      return response.text().then(function (t) {
        return Promise.reject(parseNovaHttpError(response.status, t));
      });
    }
    if (!response.body || !response.body.getReader) {
      return response.text().then(function (t) {
        t = String(t || '').trim();
        if (!t) return Promise.reject(new Error('Nova 返回空响应体'));
        if (t.charAt(0) === '{') {
          try {
            var j = JSON.parse(t);
            if (j.error) return Promise.reject(parseNovaHttpError(response.status, t));
            processJson(j);
          } catch (e) {
            if (handlers.onDelta) { handlers.onDelta(t); markOutput(); }
          }
        } else {
          consumeSseText(t);
        }
        return finishPump();
      });
    }
    var reader = response.body.getReader();
    var dec = new TextDecoder();
    var buf = '';
    function pump() {
      return reader.read().then(function (chunk) {
        if (chunk.value) buf += dec.decode(chunk.value, { stream: true });
        var parts = buf.split('\n\n');
        buf = parts.pop() || '';
        parts.forEach(function (block) {
          processJson(parseSseJsonBlock(block));
        });
        if (chunk.done) {
          if (buf.trim()) consumeSseText(buf);
          return finishPump();
        }
        return pump();
      });
    }
    return pump();
  }

  function normalizeKbDocRow(doc, i) {
    doc = doc || {};
    var runStatus = String(doc.runStatus || doc.run || '').trim();
    var runUpper = runStatus.toUpperCase();
    var progress = Number(doc.progress);
    var chunkCount = Number(doc.chunk_count != null ? doc.chunk_count : doc.chunkCount);
    var indexed = doc.indexed === true || String(doc.ingestionStatus || '').toUpperCase() === 'INDEXED';
    if (!indexed && runUpper === 'DONE' && (progress === 1 || (chunkCount || 0) > 0)) indexed = true;
    return {
      id: doc.id || doc.documentId || doc.ragflowDocId || ('doc-' + i),
      title: doc.title || doc.name || doc.fileName || '知识库文档',
      fileName: doc.fileName || doc.name || doc.title || '',
      fileExtension: doc.fileExtension || '',
      ingestionStatus: doc.ingestionStatus || (indexed ? 'INDEXED' : (runUpper === 'DONE' ? 'DONE' : 'UPLOADED')),
      indexed: indexed,
      runStatus: runStatus,
      progress: progress,
      chunk_count: chunkCount
    };
  }

  function parseKbSummary(st) {
    st = st || {};
    var rawDocs = Array.isArray(st.documents) ? st.documents : [];
    var docs = rawDocs.map(function (d, i) { return normalizeKbDocRow(d, i); });
    var folders = Array.isArray(st.folders) ? st.folders : (Array.isArray(st.datasets) ? st.datasets : []);
    var docCount = Number(
      st.documentCount != null ? st.documentCount
        : (st.documentsCount != null ? st.documentsCount
          : (st.total != null ? st.total
            : (st.stats && st.stats.documentCount != null ? st.stats.documentCount : docs.length)))
    ) || 0;
    var categoryCount = folders.length;
    if (!categoryCount && (st.folderId || st.datasetId || st.dataset_id || docCount > 0 || st.ready || st.canChat)) categoryCount = 1;
    var unreadCount = Number(
      st.unreadCount != null ? st.unreadCount
        : (st.unreadDocuments != null ? st.unreadDocuments
          : (st.stats && st.stats.unreadCount != null ? st.stats.unreadCount : 0))
    ) || 0;
    var ready = st.canChat === true || st.ready === true
      || String(st.status || '').toLowerCase() === 'ready'
      || String(st.kb_status || '').toLowerCase() === 'ready';
    var rag = st.rag || {};
    var rf = st.ragflow || {};
    if (!ready && (rag.ready === true || rf.ready === true)) ready = true;
    if (!ready && docCount > 0) {
      var indexed = docs.filter(function (d) {
        return d && (d.indexed === true || String(d.ingestionStatus || '').toUpperCase() === 'INDEXED');
      }).length;
      if (indexed > 0) ready = true;
    }
    return {
      documentCount: docCount,
      categoryCount: categoryCount,
      unreadCount: unreadCount,
      ready: ready,
      canChat: ready,
      documents: docs,
      folders: folders,
      folderId: st.folderId || st.datasetId || st.dataset_id || (folders[0] && (folders[0].id || folders[0].datasetId)) || '',
      message: st.message || ''
    };
  }

  function fetchKbStatus() {
    return fetch(novaBase() + '/v1/app/kb/status', { headers: novaHeaders({ Accept: 'application/json' }) }).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok || j.success === false) {
          var errMsg = (j.error && j.error.message) || j.message || ('知识库状态获取失败 (' + r.status + ')');
          throw new Error(errMsg);
        }
        var st = j.data || j;
        st.__summary = parseKbSummary(st);
        return st;
      });
    });
  }

  function uploadKbDocument(file) {
    var form = new FormData();
    form.append('file', file, file.name || 'upload.bin');
    return fetch(novaBase() + '/v1/app/kb/documents', { method: 'POST', headers: novaHeaders(), body: form }).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok || j.success === false) throw new Error((j.error && j.error.message) || j.message || '上传失败');
        return j.data || j;
      });
    });
  }

  function deleteKbDocument(documentId, opts) {
    opts = opts || {};
    var id = String(documentId || '').trim();
    if (!id) return Promise.reject(new Error('缺少文档 ID'));
    var url = novaBase() + '/v1/app/kb/documents/' + encodeURIComponent(id);
    var folderId = opts.folderId != null ? String(opts.folderId).trim() : '';
    if (folderId) url += '?folderId=' + encodeURIComponent(folderId);
    return fetch(url, {
      method: 'DELETE',
      headers: novaHeaders({ Accept: 'application/json' })
    }).then(function (r) {
      return r.text().then(function (text) {
        var j = {};
        try { if (text && text.trim()) j = JSON.parse(text); } catch (e) {}
        if (!r.ok || j.success === false) {
          throw new Error((j.error && j.error.message) || j.message || ('删除失败 HTTP ' + r.status));
        }
        return j.data || j;
      });
    });
  }

  function patchNovaChat() {
    if (!window.DunesNovaChat || window.DunesNovaChat.__novaApiPatched) return;
    window.DunesNovaChat.__novaApiPatched = true;
  }

  function patchKbChat() {
    if (!window.DunesKbChat || window.DunesKbChat.__novaApiPatched) return;
    window.DunesKbChat.__novaApiPatched = true;
  }

  function patchKbTranscribe() {
    window.__dunesNovaTranscribe = transcribeAudio;
  }

  function patchDunesApiKb() {
    /* K1 KB 适配在 index.html DunesApi 内直接调用 DunesNovaApi，此处不再 fallback kb-go */
  }

  function install() {
    patchKbTranscribe();
    patchNovaChat();
    patchKbChat();
    patchDunesApiKb();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install);
  } else {
    setTimeout(install, 0);
  }

  return {
    novaBase: novaBase,
    isReady: isReady,
    refreshCredentials: refreshCredentials,
    transcribeAudio: transcribeAudio,
    chatCompletionsStream: chatCompletionsStream,
    buildNovaChatMessages: buildNovaChatMessages,
    buildChatCompletionMessages: buildChatCompletionMessages,
    pumpOpenAiSse: pumpOpenAiSse,
    fetchKbStatus: fetchKbStatus,
    parseKbSummary: parseKbSummary,
    uploadKbDocument: uploadKbDocument,
    deleteKbDocument: deleteKbDocument,
    pickMultimodalModel: pickMultimodalModel,
    imagePartTypeForModel: imagePartTypeForModel,
    parseNovaHttpError: parseNovaHttpError,
    chatSelectableModels: chatSelectableModels,
    selectedChatModel: selectedChatModel,
    setSelectedChatModel: setSelectedChatModel,
    modelDisplayName: modelDisplayName,
    modelDisplayIntro: modelDisplayIntro,
    refreshModelCatalog: refreshModelCatalog,
    buildMultimodalContent: buildMultimodalContent,
    resolvePublicFileUrl: resolvePublicFileUrl,
    resolveVisionImageUrl: resolveVisionImageUrl,
    loadSessionMessages: loadSessionMessages,
    appendSessionMessages: appendSessionMessages,
    loadLocalTurns: loadLocalTurns,
    upsertLocalTurn: upsertLocalTurn,
    clearAllAiLocalHistory: clearAllAiLocalHistory,
    ensureAiLocalHistoryPurged: ensureAiLocalHistoryPurged,
    novaBizUser: novaBizUser,
    ensureNovaProfileSession: ensureNovaProfileSession,
    novaProfileSessionId: novaProfileSessionId,
    novaThreadSessionId: novaThreadSessionId,
    novaChatRequestSessionId: novaChatRequestSessionId,
    novaProfileSessionId: novaProfileSessionId,
    install: install
  };
  try { ensureNovaProfileSession(); } catch (e) {}
})();
''';
}
