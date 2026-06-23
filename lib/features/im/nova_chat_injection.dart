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
  var novaActiveAbortController = null;
  var novaUserStopped = false;
  var novaActiveStreamUi = null;
  var novaStreamDraftTimer = null;
  var novaStreamUserText = '';
  var novaDraftAttachments = [];
  var novaDraftSeq = 0;
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
  var novaStickToBottom = true;
  var novaAutoSwitchingHistory = false;
  var novaScrollRaf = 0;
  var NOVA_C4_DEBUG_BAR = false;
  var novaDebugState = { source: '-', convId: 0, aiCount: 0, localCount: 0, mergedCount: 0, shownCount: 0 };
  var novaHistoryFetchInflight = null;
  var novaHistoryFetchInflightKey = '';
  var novaHistoryFetchLastKey = '';
  var novaHistoryFetchLastAt = 0;
  var novaHistoryFetchLastItems = null;
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
      bgStreaming = true;
      sending = true;
      return true;
    } catch (e) {
      return false;
    }
  }
  function novaStreamDraftKey() {
    return 'dunes_nova_stream_draft_' + String(convId || 0);
  }
  function buildNovaStreamDraft(ui, userText) {
    ui = ui || novaActiveStreamUi;
    return {
      at: Date.now(),
      status: novaGenStatus || '正在生成…',
      after: novaGenAfterMsgId || 0,
      userText: String(userText || novaStreamUserText || ''),
      thinkStream: ui ? String(ui.thinkStream || '') : '',
      text: ui ? String(ui.text || '') : '',
      streaming: !!(ui && ui._novaStreaming)
    };
  }
  function persistNovaStreamDraft(ui, userText) {
    if (!convId) return;
    if (!novaServerGenerating && !bgStreaming && !sending) {
      clearNovaStreamDraft();
      return;
    }
    try {
      sessionStorage.setItem(novaStreamDraftKey(), JSON.stringify(buildNovaStreamDraft(ui, userText)));
    } catch (e) {}
  }
  function clearNovaStreamDraft() {
    try { sessionStorage.removeItem(novaStreamDraftKey()); } catch (e) {}
    if (novaStreamDraftTimer) {
      clearTimeout(novaStreamDraftTimer);
      novaStreamDraftTimer = null;
    }
  }
  function loadNovaStreamDraft() {
    try {
      var raw = sessionStorage.getItem(novaStreamDraftKey());
      if (!raw) return null;
      var o = JSON.parse(raw);
      if (!o || Date.now() - Number(o.at || 0) > NOVA_GEN_STORAGE_TTL_MS) {
        clearNovaStreamDraft();
        return null;
      }
      return o;
    } catch (e) { return null; }
  }
  function schedulePersistNovaStreamDraft(ui, userText) {
    if (novaStreamDraftTimer) return;
    novaStreamDraftTimer = setTimeout(function () {
      novaStreamDraftTimer = null;
      persistNovaStreamDraft(ui, userText);
    }, 280);
  }
  function restoreNovaStreamDraftToUi(ui, draft) {
    if (!ui || !draft) return;
    ui.thinkStream = String(draft.thinkStream || '');
    ui.text = String(draft.text || '');
    ui._novaStreaming = draft.streaming !== false;
    if (draft.status) setNovaThinkStatus(ui, draft.status);
    renderNovaThinkBody(ui);
    paintNovaStreamText(ui, false);
    syncNovaStreamThinking(ui);
  }
  function ensureGeneratingUserVisible(draft) {
    if (!draft) return;
    var box = rowsEl();
    if (!box) return;
    var after = Number(draft.after || 0);
    if (after > 0 && box.querySelector('[data-message-id="' + after + '"]')) return;
    if (!draft.userText) return;
    appendUserBubble(draft.userText, after > 0 ? after : (Date.now() - 1));
    commitNovaUserLiveRows();
  }
  function isNovaGenerationActive() {
    return !!(novaServerGenerating || bgStreaming || sending);
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
  var YUNSHU_NAME = '云枢';
  var NOVA_WELCOME = '你好，我是你的云枢助手。可以帮你查审批、找合同、对账单、读文档；直接问我即可。';
  var NOVA_VIEW_SINCE_KEY = 'dunes_nova_view_since';
  function setNovaViewSince(at) {
    try { localStorage.setItem(NOVA_VIEW_SINCE_KEY, at || new Date().toISOString()); } catch (e) {}
  }
  function clearNovaViewSince() {
    try { localStorage.removeItem(NOVA_VIEW_SINCE_KEY); } catch (e) {}
  }
  function novaViewSinceMs() {
    try {
      var raw = localStorage.getItem(NOVA_VIEW_SINCE_KEY);
      if (!raw) return 0;
      var t = new Date(raw).getTime();
      return isNaN(t) ? 0 : t;
    } catch (e) { return 0; }
  }
  function filterNovaViewMessages(items, opts) {
    opts = opts || {};
    items = items || [];
    if (window.__dunesLocateFromHistory) return items;
    if (opts.generating || isNovaGenerationActive()) return items;
    if (opts.fullHistory) return items;
    var since = novaViewSinceMs();
    if (!since) return items;
    var filtered = items.filter(function (m) {
      var t = new Date(m.createdAt || 0).getTime();
      return !isNaN(t) && t >= since - 5000;
    });
    return filtered.length ? filtered : items;
  }
  var NOVA_INPUT_PLACEHOLDER = '问云枢';
  var NOVA_INPUT_BUSY_PLACEHOLDER = '云枢正在生成中，请稍候…';
  var NOVA_BLOCKED_PLACEHOLDER = '云枢账号尚未开通';
  var novaAccountReady = true;
  var novaBlockMessage = '';
  var novaReadinessChecked = false;

  function isNovaAccountBlocked() {
    return novaReadinessChecked && !novaAccountReady;
  }
  function checkNovaReadiness() {
    if (!window.DunesNovaApi || typeof window.DunesNovaApi.refreshCredentials !== 'function') {
      novaAccountReady = false;
      novaBlockMessage = '云枢适配层未加载';
      novaReadinessChecked = true;
      syncNovaInputLock();
      syncNovaBlockedBanner();
      return Promise.resolve({ ready: false, message: novaBlockMessage });
    }
    return window.DunesNovaApi.refreshCredentials().then(function (d) {
      d = d || {};
      if (d.ready === true) {
        novaAccountReady = true;
        novaBlockMessage = '';
      } else {
        novaAccountReady = false;
        novaBlockMessage = String(d.message || d.lastError || '云枢账号尚未开通，请稍后再试').trim();
      }
      novaReadinessChecked = true;
      syncNovaInputLock();
      syncNovaBlockedBanner();
      syncC4ModelPicker();
      if (window.DunesNovaApi && window.DunesNovaApi.refreshModelCatalog) {
        window.DunesNovaApi.refreshModelCatalog();
      }
      if (d.quota && d.quota.remain != null) {
        localStorage.setItem('dunes_remain_quota', String(d.quota.remain));
      }
      return { ready: novaAccountReady, message: novaBlockMessage };
    }).catch(function (err) {
      novaAccountReady = false;
      novaBlockMessage = String((err && err.message) || '云枢服务暂不可用').trim();
      novaReadinessChecked = true;
      syncNovaInputLock();
      syncNovaBlockedBanner();
      return { ready: false, message: novaBlockMessage };
    });
  }
  function injectC4ModelPickerStyles() {
    if (document.getElementById('c4-model-picker-style')) return;
    var s = document.createElement('style');
    s.id = 'c4-model-picker-style';
    s.textContent = ''
      + '.c4-model-picker-wrap{padding:10px 14px 8px;background:var(--bg-card,#fff);border-bottom:1px solid var(--line-soft,rgba(0,0,0,.06));flex-shrink:0}'
      + '.c4-model-trigger{display:flex;align-items:center;gap:10px;width:100%;padding:10px 12px;border:1px solid var(--line-soft,rgba(0,0,0,.08));border-radius:14px;background:var(--bg-app,#f8f7f4);cursor:pointer;-webkit-tap-highlight-color:transparent;transition:border-color .2s,box-shadow .2s,transform .12s;text-align:left}'
      + '.c4-model-trigger:active{transform:scale(.985)}'
      + '.c4-model-trigger.open{border-color:rgba(85,59,150,.35);box-shadow:0 0 0 3px rgba(85,59,150,.1)}'
      + '.c4-model-trigger.disabled{opacity:.85;cursor:default;pointer-events:none}'
      + '.c4-model-trigger-ic{width:36px;height:36px;border-radius:11px;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#553B96,#7B5CB8);color:#fff;font-size:17px;flex-shrink:0;box-shadow:0 4px 12px -4px rgba(85,59,150,.55)}'
      + '.c4-model-trigger-text{flex:1;min-width:0;display:flex;flex-direction:column;gap:3px;min-width:0}'
      + '.c4-model-trigger-label{font-size:13px;font-weight:650;color:var(--text-1,#1a1a1a);letter-spacing:.03em;line-height:1.25;font-family:var(--mono,ui-monospace,monospace)}'
      + '.c4-model-trigger-intro{font-size:11px;color:var(--text-3,#888);line-height:1.35;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}'
      + '.c4-model-trigger-chev{font-size:16px;color:var(--text-3,#999);flex-shrink:0;transition:transform .22s ease}'
      + '.c4-model-trigger.open .c4-model-trigger-chev{transform:rotate(180deg)}'
      + '.c4-model-sheet-root{position:fixed;inset:0;z-index:120;display:flex;align-items:flex-end;justify-content:center;pointer-events:none;opacity:0;visibility:hidden;transition:opacity .24s ease,visibility .24s}'
      + '.c4-model-sheet-root.show{pointer-events:auto;opacity:1;visibility:visible}'
      + '.c4-model-sheet-backdrop{position:absolute;inset:0;background:rgba(12,10,20,.42);backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px);opacity:0;transition:opacity .24s ease}'
      + '.c4-model-sheet-root.show .c4-model-sheet-backdrop{opacity:1}'
      + '.c4-model-sheet{position:relative;width:100%;max-width:430px;background:var(--bg-card,#fff);border-radius:20px 20px 0 0;padding:8px 0 calc(12px + env(safe-area-inset-bottom,0px));box-shadow:0 -8px 40px rgba(0,0,0,.12);transform:translateY(100%);transition:transform .28s cubic-bezier(.32,.72,0,1)}'
      + '.c4-model-sheet-root.show .c4-model-sheet{transform:translateY(0)}'
      + '.c4-model-sheet-handle{width:36px;height:4px;border-radius:99px;background:var(--line-soft,rgba(0,0,0,.12));margin:6px auto 12px}'
      + '.c4-model-sheet-title{padding:0 18px 4px;font-size:13px;font-weight:700;color:var(--text-2,#555);letter-spacing:.02em}'
      + '.c4-model-sheet-foot{margin:8px 18px 0;padding:8px 0 2px;border-top:1px solid var(--line-soft,rgba(0,0,0,.06));font-size:10px;line-height:1.5;color:var(--text-3,#999)}'
      + '.c4-model-sheet-list{padding:0 10px;display:flex;flex-direction:column;gap:6px;max-height:min(52vh,360px);overflow-y:auto}'
      + '.c4-model-sheet-item{display:flex;align-items:center;gap:12px;width:100%;padding:12px 14px;border:none;border-radius:14px;background:transparent;cursor:pointer;text-align:left;-webkit-tap-highlight-color:transparent;transition:background .15s}'
      + '.c4-model-sheet-item:active{background:var(--bg-soft,#f3f2ef)}'
      + '.c4-model-sheet-item.active{background:linear-gradient(135deg,rgba(85,59,150,.08),rgba(123,92,184,.06));box-shadow:inset 0 0 0 1px rgba(85,59,150,.18)}'
      + '.c4-model-sheet-item-ic{width:40px;height:40px;border-radius:12px;display:flex;align-items:center;justify-content:center;background:var(--bg-app,#f5f4f1);color:var(--accent,#553B96);font-size:18px;flex-shrink:0}'
      + '.c4-model-sheet-item.active .c4-model-sheet-item-ic{background:linear-gradient(135deg,#553B96,#7B5CB8);color:#fff}'
      + '.c4-model-sheet-item-bd{flex:1;min-width:0}'
      + '.c4-model-sheet-item-nm{font-size:13px;font-weight:650;color:var(--text-1,#1a1a1a);letter-spacing:.03em;font-family:var(--mono,ui-monospace,monospace)}'
      + '.c4-model-sheet-item-intro{font-size:11px;color:var(--text-3,#888);margin-top:3px;line-height:1.45}'
      + '.c4-model-sheet-item-ok{width:22px;height:22px;border-radius:99px;display:flex;align-items:center;justify-content:center;font-size:13px;color:#fff;background:linear-gradient(135deg,#553B96,#7B5CB8);opacity:0;transform:scale(.7);transition:opacity .18s,transform .18s;flex-shrink:0}'
      + '.c4-model-sheet-item.active .c4-model-sheet-item-ok{opacity:1;transform:scale(1)}';
    document.head.appendChild(s);
  }
  var c4ModelSheetWired = false;
  function c4ModelApi() { return window.DunesNovaApi || null; }
  function c4ModelLabel(id) {
    var api = c4ModelApi();
    if (api && typeof api.modelDisplayName === 'function') return api.modelDisplayName(id);
    return String(id || '').trim().toUpperCase();
  }
  function c4ModelIntro(id) {
    var api = c4ModelApi();
    if (api && typeof api.modelDisplayIntro === 'function') return api.modelDisplayIntro(id);
    return '';
  }
  function closeC4ModelSheet() {
    var root = document.getElementById('c4-model-sheet-root');
    var trigger = document.getElementById('c4-model-trigger');
    if (root) root.classList.remove('show');
    if (trigger) trigger.classList.remove('open');
  }
  function openC4ModelSheet() {
    var trigger = document.getElementById('c4-model-trigger');
    if (trigger && trigger.classList.contains('disabled')) return;
    var root = ensureC4ModelSheet();
    if (!root) return;
    syncC4ModelSheetList();
    root.classList.add('show');
    if (trigger) trigger.classList.add('open');
  }
  function ensureC4ModelSheet() {
    var root = document.getElementById('c4-model-sheet-root');
    if (root) return root;
    root = document.createElement('div');
    root.id = 'c4-model-sheet-root';
    root.className = 'c4-model-sheet-root';
    root.innerHTML = ''
      + '<div class="c4-model-sheet-backdrop" data-c4-model-close></div>'
      + '<div class="c4-model-sheet" role="dialog" aria-label="选择对话模型">'
      + '<div class="c4-model-sheet-handle"></div>'
      + '<div class="c4-model-sheet-title">选择对话模型</div>'
      + '<div id="c4-model-sheet-list" class="c4-model-sheet-list"></div>'
      + '<div class="c4-model-sheet-foot">模型介绍可在沙丘工作台 · 云枢模型管理中配置</div></div>';
    var host = document.querySelector('.screen[data-screen="C4"] .phone-screen') || document.body;
    host.appendChild(root);
    if (!c4ModelSheetWired) {
      c4ModelSheetWired = true;
      root.addEventListener('click', function (e) {
        if (e.target.closest('[data-c4-model-close]')) { closeC4ModelSheet(); return; }
        var item = e.target.closest('.c4-model-sheet-item');
        if (!item) return;
        var id = item.getAttribute('data-model-id') || '';
        if (!id) return;
        var api = c4ModelApi();
        if (api && api.setSelectedChatModel) api.setSelectedChatModel(id);
        syncC4ModelPicker();
        closeC4ModelSheet();
      });
    }
    return root;
  }
  function syncC4ModelSheetList() {
    var list = document.getElementById('c4-model-sheet-list');
    var api = c4ModelApi();
    if (!list || !api || typeof api.chatSelectableModels !== 'function') return;
    var models = api.chatSelectableModels();
    var current = api.selectedChatModel();
    list.innerHTML = models.map(function (m) {
      var active = m === current;
      var intro = c4ModelIntro(m);
      return ''
        + '<button type="button" class="c4-model-sheet-item' + (active ? ' active' : '') + '" data-model-id="' + esc(m) + '">'
        + '<span class="c4-model-sheet-item-ic"><i class="ti ti-cpu"></i></span>'
        + '<span class="c4-model-sheet-item-bd">'
        + '<div class="c4-model-sheet-item-nm">' + esc(c4ModelLabel(m)) + '</div>'
        + (intro ? '<div class="c4-model-sheet-item-intro">' + esc(intro) + '</div>' : '')
        + '</span>'
        + '<span class="c4-model-sheet-item-ok"><i class="ti ti-check"></i></span></button>';
    }).join('');
  }
  function updateC4ModelTrigger(current, models) {
    var trigger = document.getElementById('c4-model-trigger');
    if (!trigger) return;
    var labelEl = trigger.querySelector('.c4-model-trigger-label');
    var introEl = trigger.querySelector('.c4-model-trigger-intro');
    var chev = trigger.querySelector('.c4-model-trigger-chev');
    if (labelEl) labelEl.textContent = c4ModelLabel(current);
    var intro = c4ModelIntro(current);
    if (introEl) {
      introEl.textContent = intro || '';
      introEl.style.display = intro ? 'block' : 'none';
    } else if (intro) {
      var textWrap = trigger.querySelector('.c4-model-trigger-text');
      if (textWrap) {
        introEl = document.createElement('span');
        introEl.className = 'c4-model-trigger-intro';
        introEl.textContent = intro;
        textWrap.appendChild(introEl);
      }
    }
    var multi = models.length > 1;
    trigger.classList.toggle('disabled', !multi);
    if (chev) chev.style.visibility = multi ? 'visible' : 'hidden';
  }
  function wireC4ModelPicker() {
    if (document.body.dataset.c4ModelPickerWired) return;
    document.body.dataset.c4ModelPickerWired = '1';
    document.addEventListener('click', function (e) {
      if (!activeIsC4()) return;
      if (e.target.closest('#c4-model-trigger') && !e.target.closest('#c4-model-trigger.disabled')) {
        e.preventDefault();
        e.stopPropagation();
        var root = document.getElementById('c4-model-sheet-root');
        if (root && root.classList.contains('show')) closeC4ModelSheet();
        else openC4ModelSheet();
      }
    }, true);
  }
  function ensureC4ModelPicker() {
    injectC4ModelPickerStyles();
    wireC4ModelPicker();
    var oldWrap = document.getElementById('c4-model-picker-wrap');
    if (oldWrap && oldWrap.querySelector('#c4-model-select')) {
      oldWrap.remove();
    }
    var trigger = document.getElementById('c4-model-trigger');
    if (trigger) return trigger;
    var slot = document.getElementById('c4-model-picker-slot');
    if (!slot) {
      var header = document.querySelector('.screen[data-screen="C4"] .chat-conv-header');
      if (!header || !header.parentNode) return null;
      slot = document.createElement('div');
      slot.id = 'c4-model-picker-slot';
      header.parentNode.insertBefore(slot, header.nextSibling);
    }
    var wrap = document.createElement('div');
    wrap.id = 'c4-model-picker-wrap';
    wrap.className = 'c4-model-picker-wrap';
    wrap.innerHTML = ''
      + '<button type="button" id="c4-model-trigger" class="c4-model-trigger" aria-haspopup="dialog">'
      + '<span class="c4-model-trigger-ic"><i class="ti ti-cpu"></i></span>'
      + '<span class="c4-model-trigger-text">'
      + '<span class="c4-model-trigger-label">NOVA_DEEPSEEK</span>'
      + '<span class="c4-model-trigger-intro" style="display:none"></span></span>'
      + '<i class="ti ti-chevron-down c4-model-trigger-chev"></i></button>';
    slot.appendChild(wrap);
    ensureC4ModelSheet();
    return wrap.querySelector('#c4-model-trigger');
  }
  function syncC4ModelPicker() {
    if (!window.DunesNovaApi || typeof window.DunesNovaApi.chatSelectableModels !== 'function') return;
    var trigger = ensureC4ModelPicker();
    var wrap = document.getElementById('c4-model-picker-wrap');
    if (!trigger || !wrap) return;
    var models = window.DunesNovaApi.chatSelectableModels();
    var current = window.DunesNovaApi.selectedChatModel();
    updateC4ModelTrigger(current, models);
    if (models.length <= 1) {
      wrap.style.display = models.length ? 'block' : 'none';
    } else {
      wrap.style.display = 'block';
    }
    syncC4ModelSheetList();
    if (window.DunesNovaApi.setSelectedChatModel) window.DunesNovaApi.setSelectedChatModel(current);
  }
  function applyYunshuBranding() {
    var screen = c4Screen();
    if (screen) {
      screen.setAttribute('data-name', YUNSHU_NAME);
      var cv = screen.querySelector('.cv-nm');
      if (cv) cv.innerHTML = YUNSHU_NAME + ' <span class="group-tag" style="background:linear-gradient(135deg,#FFD580,#FFA850);color:#5D3508">AI</span>';
      var ah = screen.querySelector('.ah-nm');
      if (ah) ah.innerHTML = YUNSHU_NAME + '<span class="badge-ai">AI</span>';
      screen.querySelectorAll('[data-nova-icon]').forEach(function (img) { img.setAttribute('alt', YUNSHU_NAME); });
      var prompts = document.getElementById('c4-ai-prompts') || screen.querySelector('.ai-prompts');
      if (prompts) prompts.style.display = 'none';
    }
    document.querySelectorAll('.screen[data-screen="C4"] .msg-meta .nm, .chat-section.pin').forEach(function (el) {
      if (el && el.textContent && el.textContent.trim() === 'NOVA') el.textContent = YUNSHU_NAME;
    });
    var hist = document.querySelector('.screen[data-screen="C11"] .ds-name');
    if (hist && /NOVA/.test(hist.textContent || '')) hist.textContent = YUNSHU_NAME + '对话历史';
    var input = document.getElementById('c4-input');
    if (input && !isNovaInputLocked()) input.placeholder = NOVA_INPUT_PLACEHOLDER;
  }
  function applyNovaNotReady(msg) {
    novaAccountReady = false;
    novaBlockMessage = String(msg || '云枢账号尚未开通，请稍后再试').trim();
    novaReadinessChecked = true;
    syncNovaInputLock();
    syncNovaBlockedBanner();
  }
  function showNovaNotReadyTip(msg) {
    msg = String(msg || novaBlockMessage || '云枢账号尚未开通，请稍后再试').trim();
    if (window.DunesDialog && typeof window.DunesDialog.alert === 'function') {
      window.DunesDialog.alert(msg);
      return;
    }
    if (window.DunesAPI && typeof window.DunesAPI.toast === 'function') {
      window.DunesAPI.toast(msg);
      return;
    }
    var hint = document.getElementById('c4-input-busy-hint');
    if (hint) {
      hint.textContent = msg;
      hint.style.display = 'block';
      hint.classList.add('nova-input-busy-flash');
      setTimeout(function () { if (hint) hint.classList.remove('nova-input-busy-flash'); }, 700);
    }
  }
  function showNovaGeneratingBackgroundTip() {
    var msg = '云枢正在生成，稍后回到通讯可继续查看';
    if (window.DunesAPI && typeof window.DunesAPI.toast === 'function') {
      window.DunesAPI.toast(msg);
      return;
    }
    var hint = document.getElementById('c4-input-busy-hint');
    if (hint) {
      hint.textContent = msg;
      hint.style.display = 'block';
    }
  }
  function syncNovaBlockedBanner() {
    var stream = streamWrap();
    if (!stream) return;
    var id = 'c4-nova-block-banner';
    var existing = document.getElementById(id);
    if (novaAccountReady) {
      if (existing) existing.remove();
      return;
    }
    if (!existing) {
      existing = document.createElement('div');
      existing.id = id;
      existing.className = 'msg-system';
      var box = rowsEl();
      if (box && box.parentNode) box.parentNode.insertBefore(existing, box);
      else stream.insertBefore(existing, stream.firstChild);
    }
    existing.innerHTML = '<span class="pill" style="background:var(--coral-soft);color:var(--coral-deep);border-color:var(--coral-line)"><i class="ti ti-alert-circle"></i> ' + esc(novaBlockMessage || NOVA_BLOCKED_PLACEHOLDER) + '</span>';
  }
  function parseNovaHttpError(r, j) {
    j = j || {};
    var msg = String(j.message || ('HTTP ' + (r && r.status ? r.status : ''))).trim();
    var code = String(j.code || '').trim();
    if (code === 'nova_not_ready' || (r && r.status === 503)) applyNovaNotReady(msg);
    return msg;
  }

  function isNovaInputLocked() {
    return !!(sending || novaServerGenerating || bgStreaming || isNovaAccountBlocked());
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
    screen.classList.toggle('nova-account-blocked', isNovaAccountBlocked());
    if (inputBar) inputBar.classList.toggle('nova-input-locked', locked);
    if (input) {
      input.readOnly = locked;
      if (isNovaAccountBlocked()) {
        input.placeholder = novaBlockMessage || NOVA_BLOCKED_PLACEHOLDER;
      } else {
        input.placeholder = locked ? NOVA_INPUT_BUSY_PLACEHOLDER : NOVA_INPUT_PLACEHOLDER;
      }
      input.setAttribute('aria-disabled', locked ? 'true' : 'false');
    }
    if (sendBtn) {
      var stopping = !!(sending || bgStreaming || novaServerGenerating);
      sendBtn.style.pointerEvents = isNovaAccountBlocked() ? 'none' : '';
      sendBtn.style.opacity = isNovaAccountBlocked() ? '0.45' : '';
      sendBtn.setAttribute('aria-disabled', isNovaAccountBlocked() ? 'true' : 'false');
      sendBtn.setAttribute('title', stopping ? '停止生成' : '发送');
      sendBtn.innerHTML = stopping ? '<i class="ti ti-square"></i>' : '<i class="ti ti-send"></i>';
      sendBtn.classList.toggle('nova-stop-btn', stopping);
    }
    [voiceBtn, attachBtn].forEach(function (el) {
      if (!el) return;
      el.style.opacity = locked ? '0.45' : '';
      el.setAttribute('aria-disabled', locked ? 'true' : 'false');
    });
    if (qaBar) {
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
      if (isNovaAccountBlocked()) {
        hint.textContent = novaBlockMessage || NOVA_BLOCKED_PLACEHOLDER;
        hint.style.display = 'block';
      } else {
        hint.textContent = locked ? String(novaGenStatus || NOVA_INPUT_BUSY_PLACEHOLDER) : '';
        hint.style.display = locked ? 'block' : 'none';
      }
    }
    var headerBusy = isNovaGenerationActive();
    ['c4-btn-new', 'c4-btn-history', 'c4-btn-search'].forEach(function (id) {
      var btn = document.getElementById(id);
      if (!btn) return;
      btn.style.pointerEvents = headerBusy ? 'none' : '';
      btn.style.opacity = headerBusy ? '0.38' : '';
      btn.setAttribute('aria-disabled', headerBusy ? 'true' : 'false');
      btn.classList.toggle('nova-header-disabled', headerBusy);
      if (headerBusy) btn.setAttribute('title', '云枢正在生成中，请稍候…');
      else if (id === 'c4-btn-new') btn.setAttribute('title', '新对话');
      else if (id === 'c4-btn-history') btn.setAttribute('title', '对话历史');
      else if (id === 'c4-btn-search') btn.setAttribute('title', '搜索');
    });
  }
  function showNovaInputBusyHint() {
    if (isNovaAccountBlocked()) { showNovaNotReadyTip(novaBlockMessage); return; }
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
  function injectNovaDraftStyles() {
    if (document.getElementById('c4-nova-draft-style')) return;
    var s = document.createElement('style');
    s.id = 'c4-nova-draft-style';
    s.textContent = ''
      + '.c4-nova-draft-tray{display:none;padding:8px 12px 6px;border-top:1px solid var(--line-soft,rgba(0,0,0,.06));background:var(--bg-card,#fff);flex-shrink:0}'
      + '.c4-nova-draft-tray.show{display:block}'
      + '.c4-nova-draft-list{display:flex;gap:8px;overflow-x:auto;padding-bottom:6px}'
      + '.c4-nova-draft-item{position:relative;flex:0 0 auto;width:62px;height:62px;border-radius:12px;background:var(--bg-app,#f8f7f4);border:1px solid var(--line-soft,rgba(0,0,0,.08));overflow:hidden}'
      + '.c4-nova-draft-item img{width:100%;height:100%;object-fit:cover;display:block}'
      + '.c4-nova-draft-file{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:6px;color:var(--accent,#553B96);font-size:10px;text-align:center}'
      + '.c4-nova-draft-file i{font-size:18px}'
      + '.c4-nova-draft-name{max-width:52px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text-2,#555)}'
      + '.c4-nova-draft-remove{position:absolute;right:3px;top:3px;border:none;background:rgba(0,0,0,.48);color:#fff;border-radius:99px;width:18px;height:18px;line-height:18px;padding:0;font-size:12px;cursor:pointer}'
      + '.c4-nova-upload-card{display:flex;align-items:center;gap:8px;padding:8px 10px;border:1px solid var(--line-soft,rgba(0,0,0,.08));border-radius:12px;background:var(--bg-app,#f8f7f4);font-size:12px;color:var(--text-2,#555)}'
      + '.c4-nova-upload-card .ti{color:var(--accent,#553B96);font-size:16px;flex-shrink:0}'
      + '.c4-nova-upload-main{flex:1;min-width:0}'
      + '.c4-nova-upload-title{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}'
      + '.c4-nova-upload-bar{height:4px;border-radius:99px;background:rgba(85,59,150,.12);margin-top:6px;overflow:hidden}'
      + '.c4-nova-upload-bar span{display:block;height:100%;width:0;background:linear-gradient(90deg,#553B96,#7B5CB8);transition:width .18s}'
      + '.c4-nova-upload-remove{border:none;background:rgba(0,0,0,.08);border-radius:99px;width:22px;height:22px;line-height:22px;padding:0;color:var(--text-2,#555);cursor:pointer;flex-shrink:0}'
      + '.dunes-nova-combo-attachments{margin-top:8px;display:flex;gap:8px;flex-wrap:wrap}'
      + '.dunes-nova-combo-img{width:76px;height:76px;object-fit:cover;border-radius:10px;display:block;cursor:pointer;background:rgba(255,255,255,.2)}'
      + '.dunes-nova-combo-file{display:flex;align-items:center;gap:6px;max-width:180px;padding:7px 9px;border-radius:10px;background:rgba(255,255,255,.18);font-size:12px;color:inherit;text-decoration:none}'
      + '.dunes-nova-combo-file span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}'
      + '.plus-btn.nova-stop-btn{background:linear-gradient(135deg,#B94A48,#D86A62)!important}';
    document.head.appendChild(s);
  }
  function ensureNovaDraftTray() {
    injectNovaDraftStyles();
    var tray = document.getElementById('c4-nova-draft-tray');
    if (tray) return tray;
    var screen = c4Screen();
    var inputBar = screen && screen.querySelector('.msg-input-bar');
    if (!inputBar || !inputBar.parentNode) return null;
    tray = document.createElement('div');
    tray.id = 'c4-nova-draft-tray';
    tray.className = 'c4-nova-draft-tray';
    inputBar.parentNode.insertBefore(tray, inputBar);
    tray.addEventListener('click', function (e) {
      var rm = e.target.closest('[data-nova-draft-remove]');
      if (rm) {
        e.preventDefault();
        removeNovaDraftAttachment(rm.getAttribute('data-nova-draft-remove'));
        return;
      }
      var clear = e.target.closest('[data-nova-draft-clear]');
      if (!clear) return;
      e.preventDefault();
      clearNovaDraftAttachments();
    });
    return tray;
  }
  function renderNovaDraftAttachments() {
    var tray = ensureNovaDraftTray();
    if (!tray) return;
    tray.classList.toggle('show', novaDraftAttachments.length > 0);
    if (!novaDraftAttachments.length) {
      tray.innerHTML = '';
      return;
    }
    var imgs = novaDraftAttachments.filter(function (a) { return a.kind === 'IMAGE'; }).length;
    var files = novaDraftAttachments.length - imgs;
    var uploading = novaDraftAttachments.some(function (a) { return a.uploading; });
    var pct = Math.max(0, Math.min(100, Math.round(novaDraftAttachments.reduce(function (sum, a) { return sum + Number(a.progress || 0); }, 0) / Math.max(1, novaDraftAttachments.length))));
    var parts = [];
    if (imgs) parts.push(imgs + ' 张图片');
    if (files) parts.push(files + ' 个文件');
    var title = (uploading ? '上传中 ' + pct + '% · ' : '已选择 ') + parts.join('、');
    var itemsHtml = novaDraftAttachments.map(function (a) {
      var inner = a.kind === 'IMAGE'
        ? '<img src="' + esc(a.localUrl || '') + '" alt="' + esc(a.name) + '">'
        : '<div class="c4-nova-draft-file"><i class="ti ti-paperclip"></i><span class="c4-nova-draft-name">' + esc(a.name) + '</span></div>';
      return '<div class="c4-nova-draft-item" title="' + esc(a.name) + '">' + inner
        + (uploading ? '' : '<button type="button" class="c4-nova-draft-remove" data-nova-draft-remove="' + esc(a.id) + '">×</button>')
        + '</div>';
    }).join('');
    tray.innerHTML = '<div class="c4-nova-draft-list">' + itemsHtml + '</div><div class="c4-nova-upload-card">'
      + '<i class="ti ti-upload"></i>'
      + '<div class="c4-nova-upload-main"><div class="c4-nova-upload-title">' + esc(title) + '</div>'
      + '<div class="c4-nova-upload-bar"><span style="width:' + (uploading ? pct : 0) + '%"></span></div></div>'
      + (uploading ? '' : '<button type="button" class="c4-nova-upload-remove" data-nova-draft-clear>×</button>')
      + '</div>';
  }
  function removeNovaDraftAttachment(id) {
    var next = [];
    novaDraftAttachments.forEach(function (a) {
      if (String(a.id) === String(id)) {
        try { if (a.localUrl) URL.revokeObjectURL(a.localUrl); } catch (e) {}
      } else {
        next.push(a);
      }
    });
    novaDraftAttachments = next;
    renderNovaDraftAttachments();
  }
  function updateNovaDraftUpload(id, progress, uploading) {
    novaDraftAttachments.forEach(function (a) {
      if (String(a.id) === String(id)) {
        a.progress = progress;
        a.uploading = uploading;
      }
    });
    renderNovaDraftAttachments();
  }
  function clearNovaDraftAttachments() {
    novaDraftAttachments.forEach(function (a) { try { if (a.localUrl) URL.revokeObjectURL(a.localUrl); } catch (e) {} });
    novaDraftAttachments = [];
    renderNovaDraftAttachments();
  }
  function guessNovaFileKind(f) {
    if (!f) return 'FILE';
    if ((f.type || '').indexOf('image/') === 0) return 'IMAGE';
    var name = String(f.name || '').toLowerCase();
    if (/\.(jpe?g|png|gif|webp|bmp|heic|heif)$/.test(name)) return 'IMAGE';
    return 'FILE';
  }
  function onNovaFilesPicked(files, labelPrefix) {
    if (!files || !files.length) return;
    addNovaDraftFiles(files, labelPrefix);
    var tray = document.getElementById('c4-nova-draft-tray');
    if (tray) {
      tray.classList.add('show');
      try { tray.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } catch (e) {}
    }
    if (window.DunesAPI && window.DunesAPI.toast) {
      window.DunesAPI.toast('已选择 ' + files.length + ' 个文件，可继续输入文字后发送');
    }
  }
  function addNovaDraftFiles(files, labelPrefix) {
    Array.prototype.slice.call(files || []).forEach(function (f) {
      if (!f) return;
      var isImg = guessNovaFileKind(f) === 'IMAGE';
      novaDraftAttachments.push({
        id: 'draft-' + (++novaDraftSeq),
        file: f,
        kind: isImg ? 'IMAGE' : 'FILE',
        name: f.name || ('upload-' + Date.now()),
        label: (isImg ? (labelPrefix || '[图片] ') : '') + (f.name || '附件'),
        mimeType: f.type || (isImg ? 'image/*' : 'application/octet-stream'),
        size: f.size || 0,
        localUrl: isImg ? URL.createObjectURL(f) : '',
        progress: 0,
        uploading: false
      });
    });
    renderNovaDraftAttachments();
    var input = document.getElementById('c4-input');
    if (input) input.focus();
  }
  function novaDraftPrompt(text, drafts) {
    text = String(text || '').trim();
    var imgs = drafts.filter(function (a) { return a.kind === 'IMAGE'; }).length;
    var files = drafts.length - imgs;
    if (text) return text;
    if (imgs && files) return '请结合这些图片和文件进行分析。';
    if (imgs > 1) return '请分析这些图片并回答用户可能关心的问题。';
    if (imgs === 1) return '请分析这张图片并回答用户可能关心的问题。';
    if (files > 1) return '请阅读并总结这些文件。';
    return '请阅读并总结这个文件。';
  }
  function stopNovaGeneration() {
    if (!(sending || bgStreaming || novaServerGenerating)) return;
    novaUserStopped = true;
    document.querySelectorAll('#c4-api-rows .msg-row.recv.dunes-nova-live').forEach(function (row) {
      row.dataset.novaStopped = '1';
    });
    try { if (novaActiveAbortController) novaActiveAbortController.abort(); } catch (e) {}
    novaServerGenerating = false;
    sending = false;
    bgStreaming = false;
    clearPersistedNovaGenerating();
    stopNovaGeneratingPoll();
    removeNovaServerPendingRow();
    syncInboxNovaGenerating('已停止生成');
    syncNovaInputLock();
  }
  function novaAttachmentSummary(drafts) {
    drafts = drafts || [];
    var imgs = drafts.filter(function (a) { return a.kind === 'IMAGE'; }).length;
    var files = drafts.length - imgs;
    var parts = [];
    if (imgs) parts.push(imgs + ' 张图片');
    if (files) parts.push(files + ' 个文件');
    return parts.length ? ('已上传 ' + parts.join('、')) : '';
  }
  function sendNovaDraftMessage(text, drafts) {
    drafts = drafts || [];
    if (!drafts.length) return sendMessage(text);
    if (isNovaAccountBlocked()) { showNovaNotReadyTip(novaBlockMessage); return Promise.resolve(); }
    if (!window.DunesNovaApi || !window.DunesNovaApi.isReady()) {
      showNovaNotReadyTip(novaBlockMessage || '云枢尚未就绪');
      return Promise.resolve();
    }
    return ensureSession().then(function () {
      return Promise.all(drafts.map(function (a) {
        updateNovaDraftUpload(a.id, 1, true);
        return uploadViaPresigned(a.file, function (pct) { updateNovaDraftUpload(a.id, pct, true); }).then(function (up) {
          var objectKey = up.objectKey || '';
          var publicUrl = isPublicMediaUrl(up.url) ? up.url : '';
          var accessUrl = publicUrl;
          if (!accessUrl && window.DunesNovaApi && window.DunesNovaApi.resolvePublicFileUrl) {
            accessUrl = window.DunesNovaApi.resolvePublicFileUrl({
              url: up.url,
              objectKey: objectKey,
              backend: up.backend,
              bucket: 'im-attachments',
              fileName: a.name,
              mimeType: a.mimeType
            });
          }
          a.payload = {
            url: accessUrl || publicUrl || objectKey,
            objectKey: objectKey,
            accessUrl: accessUrl || publicUrl || '',
            publicUrl: accessUrl || publicUrl || '',
            previewUrl: accessUrl || publicUrl || objectKey,
            mimeType: a.mimeType,
            fileName: a.name,
            size: a.size,
            kind: a.kind,
            backend: up.backend || '',
            bucket: 'im-attachments'
          };
          updateNovaDraftUpload(a.id, 100, false);
          return a;
        });
      }));
    }).then(function (uploaded) {
      var displayText = text || novaAttachmentSummary(uploaded);
      var combinedPayload = { attachments: uploaded.map(function (a) { return a.payload; }) };
      var userMsgId = persistNovaUserMessage(displayText || novaDraftPrompt(text, uploaded), 'TEXT', combinedPayload);
      if (displayText) appendUserBubble(displayText, userMsgId, combinedPayload);
      commitNovaUserLiveRows();
      var prompt = novaDraftPrompt(text, uploaded);
      var kind = uploaded.length === 1 ? uploaded[0].kind : 'MIXED';
      clearNovaDraftAttachments();
      return sendMessageViaNovaApi(text || '', 0, {
        skipUserBubble: true,
        skipPersistUser: true,
        kind: kind,
        files: uploaded.map(function (a) { return a.file; }),
        payloads: uploaded.map(function (a) { return a.payload; }),
        multimodalPrompt: prompt,
        bodyText: text || uploaded.map(function (a) { return a.label; }).join('、')
      });
    }).catch(function (e) {
      showNovaNotReadyTip('上传失败：' + ((e && e.message) || e));
    });
  }
  function submitC4Input() {
    if (!activeIsC4()) return;
    if (sending || bgStreaming || novaServerGenerating) { stopNovaGeneration(); return; }
    if (isNovaAccountBlocked()) { showNovaNotReadyTip(novaBlockMessage); return; }
    if (isNovaInputLocked()) { showNovaInputBusyHint(); return; }
    var t = readC4Input();
    var drafts = novaDraftAttachments.slice();
    if (!t && !drafts.length) return;
    clearC4Input();
    sendNovaDraftMessage(t, drafts);
  }

  function apiBase() {
    return localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
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
  function novaSelfUserId() {
    var uid = Number(localStorage.getItem('dunes_user_id') || window.__dunesSelfUserId || 0);
    return isNaN(uid) ? 0 : uid;
  }
  function ensureNovaOwnerStorage() {
    var uid = novaSelfUserId();
    var owner = Number(localStorage.getItem('dunes_nova_owner_uid') || 0);
    if (uid > 0 && owner > 0 && owner !== uid) {
      if (window.DunesNovaApi && window.DunesNovaApi.clearAllAiLocalHistory) {
        window.DunesNovaApi.clearAllAiLocalHistory();
      }
      convId = 0;
    }
    if (uid > 0) {
      try { localStorage.setItem('dunes_nova_owner_uid', String(uid)); } catch (e) {}
    }
  }
  function novaTurnBelongsToSelf(turn) {
    var self = novaSelfUserId();
    if (!turn) return false;
    if (!self) return true;
    var uid = Number(turn.userId || turn.user_id || 0);
    if (!uid || uid === self) return true;
    var biz = String(turn.bizUserId || turn.biz_user_id || '').trim().toLowerCase();
    if (biz) {
      var myBiz = String(localStorage.getItem('dunes_nova_biz_user_id') || window.__dunesNovaBizUserId || '').trim().toLowerCase();
      if (!myBiz) myBiz = ('dune_' + self).toLowerCase();
      if (myBiz && biz === myBiz) return true;
    }
    return false;
  }
  function novaTurnConvId(turn) {
    return Number((turn && (turn.conversationId || turn.conversation_id)) || 0);
  }
  function novaTurnMessageId(turn) {
    return Number((turn && (turn.messageId || turn.message_id)) || 0);
  }
  function novaTurnAt(turn) {
    return (turn && (turn.lastMessageAt || turn.last_message_at || turn.createdAt || turn.created_at)) || '';
  }
  function novaTurnUserText(turn) {
    return String((turn && (turn.userMessage || turn.user_message || turn.prompt || turn.question)) || '').trim();
  }
  function novaTurnAssistantText(turn) {
    return String((turn && (turn.assistantMessage || turn.assistant_message || turn.answer || turn.response)) || '').trim();
  }
  function novaTurnPreviewText(turn) {
    return String((turn && (turn.lastMessagePreview || turn.last_message_preview || turn.preview)) || '').trim();
  }
  function novaTurnTitleText(turn) {
    return String((turn && (turn.title || turn.name || turn.subject)) || '').trim();
  }
  function extractAiHistoryTurnRows(j) {
    if (!j || j.success === false) return [];
    var d = j.data != null ? j.data : j;
    if (Array.isArray(d)) return d;
    if (Array.isArray(d.items)) return d.items;
    if (Array.isArray(d.turns)) return d.turns;
    if (Array.isArray(d.list)) return d.list;
    if (Array.isArray(d.records)) return d.records;
    if (Array.isArray(d.content)) return d.content;
    return [];
  }
  function turnHasDisplayableContent(turn) {
    return !!(novaTurnUserText(turn) || novaTurnAssistantText(turn) || novaTurnPreviewText(turn) || novaTurnTitleText(turn));
  }
  function filterNovaMsgsForSelf(items) {
    var self = novaSelfUserId();
    if (!self) return items || [];
    return (items || []).filter(function (m) {
      if (!m) return false;
      var kind = String(m.kind || '').toUpperCase();
      if (kind === 'AI_ASSISTANT' || kind === 'AI_TOOL_CALL') return true;
      var role = String(m.role || '').toLowerCase();
      if (role === 'assistant' || role === 'system') return true;
      var sid = Number((m.sender && m.sender.userId) || m.userId || 0);
      return !sid || sid === self;
    });
  }
  function validateNovaConvId(targetId) {
    targetId = Number(targetId || 0);
    if (!targetId) return Promise.resolve(0);
    return fetchNovaAiHistoryTurns({ size: 200, conversationId: targetId }).then(function (turns) {
      turns = turns || [];
      if (!turns.length) {
        return fetchNovaAiHistoryTurns({ size: 200 }).then(function (allTurns) {
          var hits = (allTurns || []).filter(function (t) {
            return novaTurnConvId(t) === targetId && turnHasDisplayableContent(t);
          });
          return hits.length ? targetId : 0;
        });
      }
      return turns.some(turnHasDisplayableContent) ? targetId : 0;
    }).catch(function () { return 0; });
  }
  function novaUserAvHtml() {
    if (typeof myMsgAvatarHtml === 'function') return myMsgAvatarHtml(selfInitial());
    return '<div class="msg-av-sm person-e">' + esc(selfInitial()) + '</div>';
  }
  function hydrateNovaUserAvatars(root) {
    if (typeof hydrateMsgAvatarsIn === 'function') hydrateMsgAvatarsIn(root);
    else if (typeof applyMyMsgAvatar === 'function' && root) {
      root.querySelectorAll('.msg-row.sent').forEach(function (row) { applyMyMsgAvatar(row, selfInitial()); });
    }
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
  function novaAttachmentsFromPayload(payload) {
    payload = payload || {};
    if (Array.isArray(payload.attachments)) return payload.attachments;
    return [];
  }
  function renderNovaCombinedAttachments(payload) {
    var atts = novaAttachmentsFromPayload(payload);
    if (!atts.length) return '';
    var html = '<div class="dunes-nova-combo-attachments">';
    atts.forEach(function (a) {
      a = a || {};
      var fileName = a.fileName || '图片';
      var isImg = String(a.mimeType || '').indexOf('image/') === 0 || isImageExt(fileExt(fileName));
      var key = novaAttachmentObjectKey(a);
      var url = a.url || key || '';
      var src = isImg && isPublicMediaUrl(url) ? esc(url) : '';
      if (isImg) {
        html += '<img src="' + src + '" class="dunes-img-thumb dunes-nova-combo-img" data-url="' + esc(url) + '" data-object-key="' + esc(key) + '" data-bucket="im-attachments" data-full-url="' + esc(url) + '" data-file-name="' + esc(fileName) + '" alt="' + esc(fileName) + '">';
      } else {
        var fileName = a.fileName || '附件';
        var href = isPublicMediaUrl(url) ? esc(url) : storageDownloadEndpoint(key || url, 'im-attachments', fileName);
        html += '<a class="dunes-attach-link dunes-nova-file-link dunes-nova-combo-file" href="' + href + '" data-url="' + esc(url) + '" data-object-key="' + esc(key) + '" data-bucket="im-attachments" data-file-name="' + esc(fileName) + '" target="_blank" rel="noopener"><i class="ti ti-paperclip"></i><span>' + esc(fileName) + '</span></a>';
      }
    });
    return html + '</div>';
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
    wireNovaRichContent(root);
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
  function applyNovaConversationId(id) {
    id = Number(id || 0);
    if (!id) return 0;
    convId = id;
    window.pendingConvId = convId;
    try { pendingConvId = convId; } catch (e) {}
    localStorage.setItem('dunes_nova_conv_id', String(convId));
    try {
      if (window.DunesInbox && window.DunesInbox.refreshNovaInboxPreview) {
        window.DunesInbox.refreshNovaInboxPreview();
      }
    } catch (e) {}
    return convId;
  }
  function createNovaServerConversation(title) {
    return apiJson('/ai/conversations', {
      method: 'POST',
      body: JSON.stringify({ kind: 'AI_ASSISTANT', title: title || YUNSHU_NAME })
    }).then(function (j) {
      var d = j.data || j;
      var id = Number(d.conversationId || d.id || 0);
      if (id) applyNovaConversationId(id);
      return id || convId;
    });
  }
  function ensureNovaServerConversation(title) {
    if (convId) return Promise.resolve(convId);
    return createNovaServerConversation(title).catch(function () { return convId || 0; });
  }
  function saveNovaServerMessage(role, content, payload) {
    content = String(content || '').trim();
    if ((!content && !payload) || !convId) return Promise.resolve(null);
    var body = { role: role, content: content, kind: role === 'assistant' ? 'AI_ASSISTANT' : 'TEXT' };
    if (payload) body.metadata = payload;
    return apiJson('/ai/conversations/' + convId + '/messages/local', {
      method: 'POST',
      body: JSON.stringify(body)
    }).catch(function () {
      return createNovaServerConversation(content.slice(0, 24) || YUNSHU_NAME).then(function () {
        return apiJson('/ai/conversations/' + convId + '/messages/local', {
          method: 'POST',
          body: JSON.stringify(body)
        });
      });
    }).catch(function () { return null; });
  }
  function rowsEl() {
    return document.getElementById('c4-api-rows');
  }
  function ensureNovaDebugBar() {
    var bar = document.getElementById('c4-nova-debug-bar');
    if (!NOVA_C4_DEBUG_BAR) {
      if (bar && bar.parentNode) bar.parentNode.removeChild(bar);
      return null;
    }
    var screen = c4Screen();
    if (!screen) return null;
    if (bar) return bar;
    var host = document.getElementById('c4-model-picker-wrap') || document.getElementById('c4-model-picker-slot');
    if (!host) return null;
    bar = document.createElement('div');
    bar.id = 'c4-nova-debug-bar';
    bar.style.cssText = 'margin:6px 14px 4px;padding:6px 8px;border-radius:8px;background:rgba(85,59,150,.08);color:#5b4a88;font-size:10px;font-family:ui-monospace,Consolas,monospace;line-height:1.35;white-space:pre-wrap;';
    host.insertAdjacentElement('afterend', bar);
    return bar;
  }
  function setNovaDebugInfo(patch) {
    if (!NOVA_C4_DEBUG_BAR) return;
    patch = patch || {};
    novaDebugState = Object.assign({}, novaDebugState, patch, { convId: Number(convId || patch.convId || 0) });
    var bar = ensureNovaDebugBar();
    if (!bar) return;
    bar.textContent = '[C4 DEBUG] conv=' + (novaDebugState.convId || 0)
      + ' source=' + (novaDebugState.source || '-')
      + (novaDebugState.rawTurns != null ? (' raw=' + Number(novaDebugState.rawTurns || 0)) : '')
      + ' ai=' + Number(novaDebugState.aiCount || 0)
      + ' local=' + Number(novaDebugState.localCount || 0)
      + ' merged=' + Number(novaDebugState.mergedCount || 0)
      + ' shown=' + Number(novaDebugState.shownCount || 0);
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
  function isNovaStreamNearBottom() {
    var stream = streamWrap();
    if (!stream) return true;
    return stream.scrollHeight - stream.scrollTop - stream.clientHeight < 96;
  }
  function updateNovaStickToBottom() {
    novaStickToBottom = isNovaStreamNearBottom();
  }
  function pinNovaScrollToBottom() {
    novaStickToBottom = true;
  }
  function scrollC4(forceScroll) {
    if (novaSuppressAutoScroll || isNovaHistoryLocated()) return;
    if (!forceScroll && !novaStickToBottom) return;
    if (novaScrollRaf) return;
    novaScrollRaf = requestAnimationFrame(function () {
      novaScrollRaf = 0;
      var stream = streamWrap();
      if (!stream) return;
      stream.scrollTop = stream.scrollHeight;
      requestAnimationFrame(function () {
        stream.scrollTop = stream.scrollHeight;
        updateNovaStickToBottom();
      });
    });
  }
  function observeNovaRowsScroll() {
    if (scrollObserved) return;
    var box = rowsEl();
    if (!box || typeof MutationObserver === 'undefined') return;
    scrollObserved = true;
    var scrollMoTimer = null;
    var mo = new MutationObserver(function () {
      if (novaSuppressAutoScroll || isNovaHistoryLocated()) return;
      if (!novaStickToBottom) return;
      if (scrollMoTimer) return;
      scrollMoTimer = setTimeout(function () {
        scrollMoTimer = null;
        scrollC4(false);
      }, 48);
    });
    mo.observe(box, { childList: true, subtree: true });
  }
  function readStatusHtml(msgId) {
    var id = Number(msgId || 0);
    if (!id) return '';
    // 云枢会话无对端已读游标，用户消息展示为已送达即可。
    return '<div class="msg-read-status read">已读</div>';
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
  function markNovaUserMessagesRead() {
    var box = rowsEl();
    var maxId = Number(novaPeerRead || 0);
    if (box) {
      box.querySelectorAll('.msg-row.sent[data-message-id]').forEach(function (row) {
        var id = Number(row.dataset.messageId || 0);
        if (id > maxId) maxId = id;
      });
    }
    if (maxId > novaPeerRead) {
      novaPeerRead = maxId;
      refreshNovaReadStatuses();
    }
  }
  function markNovaConversationRead() {
    if (!convId) return Promise.resolve();
    if (window.DunesInbox && window.DunesInbox.patchConvUnread) {
      window.DunesInbox.patchConvUnread(convId, 0);
    }
    return Promise.resolve();
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
  function commitNovaUserLiveRows() {
    var box = rowsEl();
    if (!box) return;
    box.querySelectorAll('.msg-row.sent.dunes-nova-live').forEach(function (row) {
      row.classList.remove('dunes-nova-live');
    });
  }
  function resolveNovaConvIdForEnter() {
    var direct = window.__dunesNovaDirectTurn ? novaTurnConvId(window.__dunesNovaDirectTurn) : 0;
    if (direct > 0) return direct;
    var saved = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
    if (saved > 0) return saved;
    if (convId > 0) return convId;
    return 0;
  }
  function novaLatestLocalConvId() {
    if (!window.DunesNovaApi || !window.DunesNovaApi.loadLocalTurns) return 0;
    var turns = window.DunesNovaApi.loadLocalTurns('nova') || [];
    var best = 0;
    var bestAt = 0;
    turns.forEach(function (t) {
      var id = novaTurnConvId(t);
      var at = new Date(novaTurnAt(t) || 0).getTime();
      if (id > 0 && at >= bestAt) { bestAt = at; best = id; }
    });
    return best;
  }
  function latestNovaLocalTurnWithPreview() {
    if (!window.DunesNovaApi || !window.DunesNovaApi.loadLocalTurns) return null;
    var turns = window.DunesNovaApi.loadLocalTurns('nova') || [];
    var best = null;
    var bestAt = 0;
    (turns || []).forEach(function (t) {
      if (!t || !novaTurnBelongsToSelf(t)) return;
      var id = novaTurnConvId(t);
      if (!id) return;
      var preview = novaTurnAssistantText(t) || novaTurnPreviewText(t) || novaTurnUserText(t);
      if (!preview || isNovaWelcomePreview(preview)) return;
      var at = new Date(novaTurnAt(t) || 0).getTime();
      if (!best || (!isNaN(at) && at >= bestAt)) {
        best = t;
        bestAt = isNaN(at) ? 0 : at;
      }
    });
    return best;
  }
  function paintNovaLocalTurnPreview(reason) {
    var turn = latestNovaLocalTurnWithPreview();
    if (!turn) return 0;
    var cid = novaTurnConvId(turn);
    if (!cid) return 0;
    applyNovaConversationId(cid);
    var msgs = aiHistoryTurnsToNovaMsgs([turn], cid);
    if (!msgs.length) return 0;
    paintNovaMessages(msgs, { scroll: true });
    setHasChat(true);
    if (window.DunesNovaApi && window.DunesNovaApi.saveSessionMessages) {
      window.DunesNovaApi.saveSessionMessages('nova', cid, msgs, { displayOnly: true });
    }
    setNovaDebugInfo({
      source: reason || 'local_turn_preview',
      convId: cid,
      aiCount: 0,
      localCount: msgs.length,
      mergedCount: msgs.length,
      shownCount: msgs.length
    });
    return cid;
  }
  function paintDirectNovaTurnFromHistory(reason) {
    var turn = window.__dunesNovaDirectTurn;
    if (!turn) return 0;
    var cid = novaTurnConvId(turn);
    if (!cid) return 0;
    applyNovaConversationId(cid);
    var msgs = aiHistoryTurnsToNovaMsgs([turn], cid);
    if (msgs.length) {
      paintNovaMessages(msgs, { scroll: true });
      setHasChat(true);
      if (window.DunesNovaApi && window.DunesNovaApi.saveSessionMessages) {
        window.DunesNovaApi.saveSessionMessages('nova', cid, msgs, { displayOnly: true });
      }
    }
    setNovaDebugInfo({
      source: reason || 'direct_turn',
      convId: cid,
      aiCount: msgs.length,
      localCount: 0,
      mergedCount: msgs.length,
      shownCount: msgs.length
    });
    return cid;
  }
  function mergeNovaHistoryItems(serverItems, localItems) {
    var map = {};
    (serverItems || []).forEach(function (m) {
      normalizeNovaMsg(m);
      if (m && m.id != null) map[String(m.id)] = m;
    });
    (localItems || []).forEach(function (m) {
      normalizeNovaMsg(m);
      if (!m || m.id == null) return;
      var key = String(m.id);
      var prev = map[key];
      if (!prev) map[key] = m;
      else if ((m.payload && !prev.payload) || String(m.bodyText || '').length > String(prev.bodyText || '').length) map[key] = m;
    });
    var sorted = Object.keys(map).map(function (k) { return map[k]; }).sort(function (a, b) {
      return Number(a.id) - Number(b.id);
    });
    var out = [];
    sorted.forEach(function (m) {
      var prev = out.length ? out[out.length - 1] : null;
      if (prev) {
        var pAi = String(prev.kind || '').toUpperCase().indexOf('AI') >= 0;
        var mAi = String(m.kind || '').toUpperCase().indexOf('AI') >= 0;
        var pTxt = String(prev.bodyText || prev.content || '').trim();
        var mTxt = String(m.bodyText || m.content || '').trim();
        if (pAi && mAi && pTxt && pTxt === mTxt) return;
      }
      out.push(m);
    });
    return out;
  }
  function parseAiHistoryPayload(j) {
    if (!j || j.success === false) return { items: [] };
    var d = j.data != null ? j.data : j;
    if (Array.isArray(d)) return { items: d, turns: d };
    return d || { items: [] };
  }
  function pickLatestConvIdFromTurns(turns) {
    var best = 0;
    var bestAt = 0;
    (turns || []).forEach(function (t) {
      if (!novaTurnBelongsToSelf(t)) return;
      var id = novaTurnConvId(t);
      var at = new Date(novaTurnAt(t) || 0).getTime();
      if (id > 0 && !isNaN(at) && at >= bestAt) { bestAt = at; best = id; }
    });
    return best;
  }
  function dedupeNovaHistoryTurns(rows) {
    var map = {};
    (rows || []).forEach(function (r) {
      if (!novaTurnBelongsToSelf(r)) return;
      var k = String(novaTurnConvId(r) || '');
      if (!k) return;
      var prev = map[k];
      var rAt = new Date(novaTurnAt(r) || 0).getTime();
      var pAt = prev ? new Date(novaTurnAt(prev) || 0).getTime() : 0;
      if (!prev || (!isNaN(rAt) && rAt >= pAt)) map[k] = Object.assign({}, prev || {}, r);
    });
    return Object.keys(map).map(function (k) { return map[k]; }).sort(function (a, b) {
      return new Date(novaTurnAt(b) || 0).getTime() - new Date(novaTurnAt(a) || 0).getTime();
    });
  }
  function syncNovaTurnsToLocal(turns) {
    if (!window.DunesNovaApi || !window.DunesNovaApi.upsertLocalTurn) return;
    (turns || []).forEach(function (t) {
      if (!novaTurnBelongsToSelf(t)) return;
      var cid = novaTurnConvId(t);
      if (!cid) return;
      var preview = novaTurnPreviewText(t);
      if (isNovaWelcomePreview(preview)) {
        preview = novaTurnAssistantText(t).slice(0, 200)
          || novaTurnUserText(t).slice(0, 200);
      }
      window.DunesNovaApi.upsertLocalTurn('nova', {
        conversationId: cid,
        title: t.title || t.name || '',
        lastMessagePreview: preview || novaTurnPreviewText(t),
        lastMessageAt: novaTurnAt(t),
        messageId: novaTurnMessageId(t)
      });
    });
  }
  function aiHistoryMessagesToNovaMsgs(messages, convId) {
    var userId = Number(localStorage.getItem('dunes_user_id') || 0);
    return (messages || []).map(function (m, i) {
      var role = String(m.role || '').toLowerCase();
      var isUser = role === 'user';
      var text = String(m.content || m.bodyText || '').trim();
      return {
        id: Number(m.id || 0) || (Number(convId || 0) * 1000 + i + 1),
        kind: isUser ? 'TEXT' : 'AI_ASSISTANT',
        bodyText: text,
        content: text,
        createdAt: m.createdAt || m.created_at || new Date().toISOString(),
        sender: isUser
          ? { userId: userId, displayName: selfName() }
          : { displayName: YUNSHU_NAME, userId: 0 }
      };
    });
  }
  function dedupeNovaTurnsForDisplay(turns) {
    var seen = {};
    var out = [];
    (turns || []).slice().sort(function (a, b) {
      return new Date(novaTurnAt(a) || 0).getTime() - new Date(novaTurnAt(b) || 0).getTime();
    }).forEach(function (turn) {
      var key = [
        novaTurnConvId(turn),
        novaTurnMessageId(turn) || 0,
        novaTurnUserText(turn),
        novaTurnAssistantText(turn) || novaTurnPreviewText(turn),
        novaTurnAt(turn)
      ].join('\x1e');
      if (seen[key]) return;
      seen[key] = 1;
      out.push(turn);
    });
    return out;
  }
  function aiHistoryTurnsToNovaMsgs(turns, convId) {
    turns = dedupeNovaTurnsForDisplay(turns);
    var userId = Number(localStorage.getItem('dunes_user_id') || 0);
    var out = [];
    var usedMsgIds = {};
    function allocMsgId(seed, fallbackSeed) {
      var id = Number(seed || 0);
      if (id <= 0) id = Number(fallbackSeed || 0);
      if (id <= 0) id = Date.now();
      while (usedMsgIds[id]) id += 1;
      usedMsgIds[id] = 1;
      return id;
    }
    var sorted = (turns || []).slice().sort(function (a, b) {
      return new Date(novaTurnAt(a) || 0).getTime() - new Date(novaTurnAt(b) || 0).getTime();
    });
    sorted.forEach(function (turn, idx) {
      var turnMid = novaTurnMessageId(turn);
      var fallbackBase = (Number(convId || 0) * 1000000) + (idx * 10 + 1);
      var userMsgId = allocMsgId(turnMid, fallbackBase);
      var aiMsgId = allocMsgId(turnMid > 0 ? (turnMid + 1) : 0, userMsgId + 1);
      var at = novaTurnAt(turn) || new Date().toISOString();
      var userText = novaTurnUserText(turn);
      if (!userText) userText = novaTurnTitleText(turn);
      if (userText) {
        out.push({
          id: userMsgId,
          kind: 'TEXT',
          bodyText: userText,
          content: userText,
          createdAt: at,
          sender: { userId: userId, displayName: selfName() }
        });
      }
      var aiText = novaTurnAssistantText(turn);
      if (!aiText) aiText = novaTurnPreviewText(turn);
      if (aiText) {
        out.push({
          id: aiMsgId,
          kind: 'AI_ASSISTANT',
          bodyText: aiText,
          content: aiText,
          createdAt: at,
          sender: { displayName: YUNSHU_NAME, userId: 0 }
        });
      }
    });
    return out;
  }
  function latestConvIdFromRows(rows) {
    var best = 0;
    var bestAt = 0;
    (rows || []).forEach(function (t) {
      var id = novaTurnConvId(t);
      if (!id) return;
      var at = new Date(novaTurnAt(t) || 0).getTime();
      if (!best || (!isNaN(at) && at >= bestAt)) {
        best = id;
        bestAt = isNaN(at) ? 0 : at;
      }
    });
    return best;
  }
  function paintLatestAiHistoryDirect(reason) {
    return fetchNovaAiHistoryTurns({ size: 200 }).then(function (rows) {
      rows = rows || [];
      var latest = latestConvIdFromRows(rows);
      if (!latest) {
        setNovaDebugInfo({
          source: (reason || 'direct_ai_history') + '_empty',
          rawTurns: rows.length,
          aiCount: 0,
          localCount: 0,
          mergedCount: 0,
          shownCount: 0
        });
        return 0;
      }
      var turns = rows.filter(function (t) { return novaTurnConvId(t) === latest; });
      var msgs = aiHistoryTurnsToNovaMsgs(turns, latest);
      applyNovaConversationId(latest);
      if (msgs.length) {
        paintNovaMessages(msgs, { scroll: true });
        setHasChat(true);
        if (window.DunesNovaApi && window.DunesNovaApi.saveSessionMessages) {
          window.DunesNovaApi.saveSessionMessages('nova', latest, msgs, { displayOnly: true });
        }
      }
      setNovaDebugInfo({
        source: reason || 'direct_ai_history',
        convId: latest,
        aiCount: msgs.length,
        localCount: 0,
        mergedCount: msgs.length,
        shownCount: msgs.length
      });
      return latest;
    }).catch(function (e) {
      setNovaDebugInfo({ source: (reason || 'direct_ai_history') + '_err', aiCount: 0, localCount: 0, mergedCount: 0, shownCount: 0 });
      return 0;
    });
  }
  function aiHistoryDetailToMessages(detail, convId) {
    var msgs = detail.messages || [];
    if (msgs.length) return aiHistoryMessagesToNovaMsgs(msgs, convId);
    var turns = detail.turns || detail.items || [];
    if (turns.length) return aiHistoryTurnsToNovaMsgs(turns, convId);
    return [];
  }
  function fetchAiHistoryTurnRowsFromApi(size, before, conversationId) {
    size = Number(size || 100) || 100;
    before = String(before || '');
    conversationId = Number(conversationId || 0);
    function convQuery(q) {
      if (conversationId > 0) q += '&conversationId=' + encodeURIComponent(String(conversationId));
      return q;
    }
    function rowsFrom(j) {
      return extractAiHistoryTurnRows(j);
    }
    function loadTurnsPath() {
      var q = convQuery('/ai/history/turns?size=' + size);
      if (before) q += '&before=' + encodeURIComponent(before);
      return apiJson(q);
    }
    function loadViewPath() {
      var q = convQuery('/ai/history?view=turns&size=' + size);
      if (before) q += '&before=' + encodeURIComponent(before);
      return apiJson(q);
    }
    return loadTurnsPath().then(function (j) {
      var rows = rowsFrom(j);
      if (rows.length) return rows;
      return loadViewPath().then(function (j2) {
        return rowsFrom(j2);
      });
    }).catch(function () {
      return loadViewPath().then(function (j3) {
        return rowsFrom(j3);
      }).catch(function () { return []; });
    });
  }
  function fetchNovaAiHistoryTurns(opts) {
    opts = opts || {};
    var size = Number(opts.size || 100) || 100;
    var filterConvId = Number(opts.conversationId || 0);
    return fetchAiHistoryTurnRowsFromApi(size, opts.before || '', filterConvId).then(function (rows) {
      rows = rows || [];
      if (filterConvId) {
        // conversationId endpoint can return mixed rows; filter by conversation first.
        return rows.filter(function (t) { return novaTurnConvId(t) === filterConvId; });
      }
      return rows.filter(novaTurnBelongsToSelf);
    });
  }
  function novaTurnMergeKey(turn) {
    if (!turn) return '';
    var cid = novaTurnConvId(turn);
    var mid = novaTurnMessageId(turn);
    var at = novaTurnAt(turn) || '';
    var userText = novaTurnUserText(turn);
    var aiText = novaTurnAssistantText(turn) || novaTurnPreviewText(turn);
    if (mid > 0) {
      return String(cid) + '|mid:' + String(mid) + '|at:' + at + '|u:' + userText + '|a:' + aiText;
    }
    return String(cid) + '|at:' + at + '|u:' + userText + '|a:' + aiText;
  }
  function mergeNovaTurnRows(existing, incoming) {
    var out = (existing || []).slice();
    var seen = {};
    out.forEach(function (t) {
      var key = novaTurnMergeKey(t);
      if (key) seen[key] = true;
    });
    (incoming || []).forEach(function (t) {
      var key = novaTurnMergeKey(t);
      if (!key) return;
      if (seen[key]) return;
      seen[key] = true;
      out.push(t);
    });
    return out;
  }
  function fetchAllNovaTurnsForConv(targetConvId) {
    targetConvId = Number(targetConvId || 0);
    if (!targetConvId) return Promise.resolve([]);
    var all = [];
    var before = '';
    var rounds = 0;
    function nextPage() {
      if (rounds >= 15) return Promise.resolve(all);
      rounds++;
      return fetchAiHistoryTurnRowsFromApi(100, before, targetConvId).then(function (rows) {
        rows = rows || [];
        rows = rows.filter(function (t) { return novaTurnConvId(t) === targetConvId; });
        if (!rows.length) return all;
        all = mergeNovaTurnRows(all, rows);
        if (rows.length < 100) return all;
        var oldestAt = novaTurnAt(rows[rows.length - 1]) || '';
        if (!oldestAt || oldestAt === before) return all;
        before = oldestAt;
        return nextPage();
      });
    }
    return nextPage();
  }
  function fetchNovaAiHistoryMessages(targetConvId, opts) {
    opts = opts || {};
    targetConvId = Number(targetConvId || convId || 0);
    var allowAutoSwitch = opts.allowAutoSwitch !== false;
    var reqKey = String(targetConvId || 0) + '|' + (allowAutoSwitch ? '1' : '0');
    var now = Date.now();
    if (novaHistoryFetchInflight && novaHistoryFetchInflightKey === reqKey) {
      return novaHistoryFetchInflight;
    }
    if (novaHistoryFetchLastKey === reqKey && now - novaHistoryFetchLastAt < 500 && Array.isArray(novaHistoryFetchLastItems)) {
      return Promise.resolve(novaHistoryFetchLastItems.slice());
    }
    var task = fetchAllNovaTurnsForConv(targetConvId).then(function (turns) {
      if (targetConvId > 0 && !turns.length) {
        return fetchNovaAiHistoryTurns({ size: 500 }).then(function (allTurns) {
          return (allTurns || []).filter(function (t) { return novaTurnConvId(t) === targetConvId; });
        });
      }
      return turns;
    }).then(function (turns) {
      try {
        window.__dunesNovaTurnsDebug = {
          requestedConvId: targetConvId,
          turnsCount: (turns || []).length,
          sample: (turns || []).slice(0, 8).map(function (t) {
            return {
              conversationId: novaTurnConvId(t),
              messageId: novaTurnMessageId(t),
              at: novaTurnAt(t),
              title: novaTurnTitleText(t)
            };
          })
        };
      } catch (e) {}
      if (targetConvId > 0 && !turns.length) {
        if (Number(localStorage.getItem('dunes_nova_conv_id') || 0) === targetConvId) {
          try { localStorage.removeItem('dunes_nova_conv_id'); } catch (e) {}
        }
        if (convId === targetConvId) convId = 0;
        return [];
      }
      if (!turns.length && allowAutoSwitch) {
        return fetchNovaAiHistoryTurns({ size: 500 }).then(function (allTurns) {
          var latest = pickLatestConvIdFromTurns(allTurns);
          if (latest > 0) {
            targetConvId = latest;
            applyNovaConversationId(latest);
            turns = (allTurns || []).filter(function (t) { return novaTurnConvId(t) === latest; });
          }
          if (!turns.length) return [];
          return aiHistoryTurnsToNovaMsgs(turns, targetConvId);
        });
      }
      if (!turns.length) return [];
      return aiHistoryTurnsToNovaMsgs(turns, targetConvId);
    }).then(function (items) {
      novaHistoryFetchLastKey = reqKey;
      novaHistoryFetchLastAt = Date.now();
      novaHistoryFetchLastItems = (items || []).slice();
      return items || [];
    }).catch(function () { return []; });
    novaHistoryFetchInflight = task;
    novaHistoryFetchInflightKey = reqKey;
    return task.finally(function () {
      if (novaHistoryFetchInflight === task) {
        novaHistoryFetchInflight = null;
        novaHistoryFetchInflightKey = '';
      }
    });
  }
  function fetchNovaLatestConvIdFromServer() {
    return fetchNovaAiHistoryTurns({ size: 40 }).then(function (turns) {
      syncNovaTurnsToLocal(turns);
      return pickLatestConvIdFromTurns(turns);
    }).catch(function () { return 0; });
  }
  function isNovaWelcomePreview(text) {
    text = String(text || '').trim();
    if (!text) return true;
    if (text.indexOf('你好，我是你的云枢助手') === 0) return true;
    if (text.indexOf('沙丘助手') >= 0) return true;
    return false;
  }
  function novaLocalPreviewMissing(targetConvId) {
    targetConvId = Number(targetConvId || 0);
    if (!targetConvId || !window.DunesNovaApi) return true;
    var turns = window.DunesNovaApi.loadLocalTurns('nova') || [];
    for (var i = 0; i < turns.length; i++) {
      if (novaTurnConvId(turns[i]) !== targetConvId) continue;
      var pv = novaTurnPreviewText(turns[i]);
      if (pv && !isNovaWelcomePreview(pv)) return false;
    }
    var msgs = window.DunesNovaApi.loadSessionMessages('nova', targetConvId) || [];
    for (var j = msgs.length - 1; j >= 0; j--) {
      var m = msgs[j];
      if (!m) continue;
      var kind = String(m.kind || '').toUpperCase();
      var role = String(m.role || '').toLowerCase();
      if (role !== 'assistant' && kind.indexOf('AI') < 0) continue;
      var txt = String(m.bodyText || m.content || '').trim();
      if (txt && !isNovaWelcomePreview(txt)) return false;
    }
    return true;
  }
  function syncNovaConvFromServer(targetConvId) {
    targetConvId = Number(targetConvId || 0);
    if (!targetConvId) return Promise.resolve(0);
    return validateNovaConvId(targetConvId).then(function (ok) {
      if (!ok) return 0;
      applyNovaConversationId(targetConvId);
      return fetchNovaAiHistoryTurns({ conversationId: targetConvId, size: 50 });
    }).then(function (turns) {
      if (!turns && turns !== 0) return 0;
      syncNovaTurnsToLocal(turns);
      if (window.DunesInbox && window.DunesInbox.refreshNovaInboxPreview) {
        window.DunesInbox.refreshNovaInboxPreview();
      }
      return targetConvId;
    }).catch(function () { return 0; });
  }
  function prefetchServerHistory() {
    var saved = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
    var knownId = saved > 0 ? saved : 0;
    if (knownId > 0 && !novaLocalPreviewMissing(knownId)) {
      return Promise.resolve(knownId);
    }
    if (knownId > 0) {
      return syncNovaConvFromServer(knownId);
    }
    return fetchNovaLatestConvIdFromServer().then(function (id) {
      if (id > 0) return syncNovaConvFromServer(id);
      return 0;
    }).catch(function () { return 0; });
  }
  function finishStreamUi(ui, attempt, text) {
    if (ui._novaNotReady) {
      applyNovaNotReady(ui._novaError || novaBlockMessage);
      commitNovaUserLiveRows();
      if (ui.row && ui.row.parentNode) ui.row.parentNode.removeChild(ui.row);
      sending = false;
      bgStreaming = false;
      novaServerGenerating = false;
      clearPersistedNovaGenerating();
      clearNovaStreamDraft();
      novaActiveStreamUi = null;
      novaStreamUserText = '';
      stopNovaGeneratingPoll();
      syncInboxNovaGenerating();
      syncNovaInputLock();
      return Promise.resolve();
    }
    stopNovaGeneratingPoll();
    finalizeNovaThinkingPanel(ui);
    removeExtraNovaStreamRows(ui && ui.row);
    var preview = novaFinalReplyText(ui) || String(ui.text || text || '').trim();
    var savedUserLabel = String(novaStreamUserText || text || '').trim();
    if (ui && ui.row && preview) {
      finalizeStreamRow(ui, Number(ui._novaAiMsgId || 0) || (Date.now() + 1), preview);
    }
    if (ui.row) ui.row.classList.remove('dunes-nova-live', 'dunes-nova-server-pending');
    sending = false;
    bgStreaming = false;
    novaServerGenerating = false;
    clearPersistedNovaGenerating();
    clearNovaStreamDraft();
    novaActiveStreamUi = null;
    novaStreamUserText = '';
    markNovaUserMessagesRead();
    if (convId && ui && !ui._novaTurnPersisted && preview) {
      persistNovaAssistantReply({
        ui: ui,
        reply: preview,
        userLabel: savedUserLabel,
        skipUser: true,
        aiMsgId: Number(ui._novaAiMsgId || 0) || undefined
      });
    } else if (convId) {
      flushNovaConvToLocalHistory(convId);
    }
    syncInboxNovaGenerating(preview ? preview.slice(0, 80) : '');
    syncNovaInputLock();
    if (activeIsC4()) {
      scrollC4();
      return markNovaConversationRead();
    }
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
  function uploadViaPresigned(file, onProgress) {
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var form = new FormData();
    form.append('file', file, file.name || ('upload-' + Date.now()));
    form.append('bucket', 'im-attachments');
    if (convId) form.append('conversationId', String(convId));
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('POST', apiBase() + '/storage/upload');
      if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
      xhr.upload.onprogress = function (ev) {
        if (ev.lengthComputable && typeof onProgress === 'function') {
          onProgress(Math.max(1, Math.min(99, Math.round(ev.loaded * 100 / ev.total))));
        }
      };
      xhr.onload = function () {
        var proxy = {};
        try { proxy = xhr.responseText ? JSON.parse(xhr.responseText) : {}; } catch (e) {}
        if (xhr.status >= 200 && xhr.status < 300 && proxy && proxy.success && proxy.data) {
          var d = proxy.data;
          var key = d.objectKey || d.url || '';
          var url = d.url || '';
          if (url || key) {
            if (typeof onProgress === 'function') onProgress(100);
            resolve({ url: url, objectKey: key || url, backend: d.backend || '' });
            return;
          }
        }
        reject(new Error((proxy && proxy.message) || ('上传失败 HTTP ' + xhr.status)));
      };
      xhr.onerror = function () { reject(new Error('上传失败，请检查网络')); };
      xhr.send(form);
    });
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
    if (isNovaAccountBlocked()) {
      showNovaNotReadyTip(novaBlockMessage);
      return Promise.resolve();
    }
    if (isNovaInputLocked()) {
      showNovaInputBusyHint();
      return Promise.resolve();
    }
    if (!window.DunesNovaApi || !window.DunesNovaApi.isReady()) {
      showNovaNotReadyTip(novaBlockMessage || '云枢尚未就绪');
      return Promise.resolve();
    }
    if (!convId) {
      return ensureSession().then(function () { return sendNovaAttachment(kind, label, payload, opts); });
    }
    payload = payload || {};
    if (!opts.skipBubble) {
      appendUserAttachmentBubble(kind, label, payload);
      persistNovaUserMessage(label, kind, payload);
    }
    var prompt = String(label || opts.bodyText || '').trim();
    if (String(kind).toUpperCase() === 'IMAGE' && !prompt) prompt = '请分析这张图片';
    if (String(kind).toUpperCase() === 'FILE' && !prompt) prompt = '请阅读并总结这个文件';
    return sendMessageViaNovaApi('', 0, { skipUserBubble: true, kind: kind, payload: payload, multimodalPrompt: prompt, bodyText: label });
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
  function novaHiddenInputStyle() {
    return 'position:fixed;top:50%;left:50%;width:1px;height:1px;opacity:0.01;overflow:hidden;';
  }
  function ensureNovaHiddenInput(id, accept, capture) {
    var host = document.body || c4Screen();
    if (!host) return null;
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('input');
      el.type = 'file';
      el.id = id;
      el.accept = accept || 'image/*';
      el.style.cssText = novaHiddenInputStyle();
      if (capture) el.setAttribute('capture', capture);
      host.appendChild(el);
    }
    return el;
  }
  function wireNovaFilePicker(id, accept, capture, multiple, onPick) {
    var el = ensureNovaHiddenInput(id, accept, capture);
    if (!el) return el;
    if (accept != null) el.accept = accept;
    el.multiple = !!multiple;
    if (capture) el.setAttribute('capture', capture);
    else el.removeAttribute('capture');
    if (el.dataset.wired) return el;
    el.dataset.wired = '1';
    el.addEventListener('change', function () {
      var picked = el.files ? Array.prototype.slice.call(el.files) : [];
      el.value = '';
      if (picked.length) onPick(picked);
    });
    return el;
  }
  function wireNovaFilePickers() {
    wireNovaFilePicker('c4-camera-slot', 'image/*', 'environment', false, function (files) {
      if (files[0]) onNovaFilesPicked([files[0]], '[拍照] ');
    });
    wireNovaFilePicker('c4-album-slot', 'image/*', '', true, function (files) {
      onNovaFilesPicked(files, '[图片] ');
    });
    wireNovaFilePicker('c4-upload-slot', '*/*', '', true, function (files) {
      onNovaFilesPicked(files, '[文件] ');
    });
  }
  function triggerNovaFileInput(id, accept, capture, multiple) {
    if (isNovaInputLocked()) { showNovaInputBusyHint(); return; }
    wireNovaFilePickers();
    var el = ensureNovaHiddenInput(id, accept, capture);
    if (!el) return;
    if (accept != null) el.accept = accept;
    if (capture) el.setAttribute('capture', capture);
    else el.removeAttribute('capture');
    el.multiple = !!multiple;
    el.value = '';
    el.click();
  }
  function wireC4MediaToolbar() {
    var screen = c4Screen();
    if (!screen) return;
    wireNovaFilePickers();
    var attachBtn = screen.querySelector('.msg-input-bar .emoji-btn');
    if (attachBtn && !attachBtn.dataset.wired) {
      attachBtn.dataset.wired = '1';
      attachBtn.title = '发送文件';
      attachBtn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        triggerNovaFileInput('c4-upload-slot', '*/*', '', true);
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
          try {
            var prepared = await novaVoiceUploadBlob(blob, recMime);
            if (!window.DunesNovaApi || !window.DunesNovaApi.isReady()) {
              showNovaNotReadyTip(novaBlockMessage || '云枢尚未就绪');
              return;
            }
            var transcript = await window.DunesNovaApi.transcribeAudio(prepared.blob, prepared.fileName);
            var liveRow = rowsEl() && rowsEl().querySelector('.dunes-nova-voice-live, .msg-row[data-nova-voice="1"]:last-child');
            if (liveRow) {
              var bubble = liveRow.querySelector('.msg-bubble');
              if (bubble) bubble.textContent = transcript;
            }
            await sendMessage(transcript, 0, { skipUserBubble: true });
          } catch (err) {
            showNovaNotReadyTip((err && err.message) || '语音识别失败，请改用文字发送');
          }
        }
      });
    }
    wireC4VoicePlay();
  }
  function mdLite(text) {
    return novaMarkdownInlineHtml(text);
  }
  function novaPhPush(list, html) {
    var id = '@@NOVA_PH_' + list.length + '@@';
    list.push({ id: id, html: html });
    return id;
  }
  function novaMarkdownInlineHtml(text) {
    text = String(text || '');
    if (!text) return '';
    var ph = [];
    text = text.replace(/!\[([^\]]*)\]\((https?:[^)\s]+)\)/gi, function (_, alt, url) {
      var nm = alt || '图片';
      try { if (!alt) nm = decodeURIComponent(url.split('/').pop().split('?')[0]); } catch (e) {}
      return novaPhPush(ph, renderNovaImageCard({ url: url, name: nm, ext: fileExt(url) }));
    });
    text = text.replace(/`([^`\n]+)`/g, function (_, c) {
      return novaPhPush(ph, '<code class="nova-inline-code">' + esc(c) + '</code>');
    });
    text = text.replace(/\*\*(.+?)\*\*/g, function (_, b) {
      return novaPhPush(ph, '<strong>' + esc(b) + '</strong>');
    });
    text = text.replace(/\*(.+?)\*/g, function (_, b) {
      return novaPhPush(ph, '<em>' + esc(b) + '</em>');
    });
    text = text.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/gi, function (_, label, url) {
      return novaPhPush(ph, novaRenderMarkdownLink(label, url));
    });
    var s = esc(text);
    ph.forEach(function (p) { s = s.split(p.id).join(p.html); });
    s = s.replace(/\n/g, '<br>');
    return s;
  }
  function renderNovaCodeBlock(lang, code, partial) {
    lang = String(lang || '').trim() || 'text';
    code = String(code || '');
    var id = 'nova-cb-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
    return ''
      + '<div class="nova-code-block' + (partial ? ' is-streaming' : '') + '" data-lang="' + esc(lang) + '">'
      + '<div class="nova-code-head">'
      + '<span class="nova-code-lang">' + esc(lang) + '</span>'
      + '<button type="button" class="nova-code-copy" data-copy-id="' + esc(id) + '" title="复制代码">'
      + '<i class="ti ti-copy"></i><span>复制</span></button>'
      + '</div>'
      + '<pre class="nova-code-pre"><code id="' + esc(id) + '" class="nova-code-body">' + esc(code) + '</code></pre>'
      + (partial ? '<div class="nova-code-stream-hint">代码生成中…</div>' : '')
      + '</div>';
  }
  function splitNovaMarkdownFences(text) {
    text = String(text || '');
    var parts = [];
    var re = /```(\w*)\n?([\s\S]*?)```/g;
    var last = 0;
    var m;
    var hit = false;
    while ((m = re.exec(text)) !== null) {
      hit = true;
      if (m.index > last) parts.push({ type: 'text', content: text.slice(last, m.index) });
      parts.push({ type: 'code', lang: m[1] || '', content: m[2].replace(/\n$/, '') });
      last = re.lastIndex;
    }
    if (hit) {
      if (last < text.length) parts.push({ type: 'text', content: text.slice(last) });
      return parts;
    }
    var open = text.match(/```(\w*)\n?([\s\S]*)$/);
    if (open && text.indexOf('```') === text.lastIndexOf('```')) {
      var before = text.slice(0, open.index);
      if (before) parts.push({ type: 'text', content: before });
      parts.push({ type: 'code', lang: open[1] || '', content: open[2], partial: true });
      return parts;
    }
    parts.push({ type: 'text', content: text });
    return parts;
  }
  function renderNovaMarkdownHtml(text) {
    var parts = splitNovaMarkdownFences(text);
    return parts.map(function (p) {
      if (p.type === 'code') return renderNovaCodeBlock(p.lang, p.content, !!p.partial);
      return renderNovaBodyInlineSegment(p.content);
    }).join('');
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
  function stripNovaToolCallLeak(text) {
    text = String(text || '');
    if (!text) return '';
    text = text.replace(/<\s*tool_calls[\s\S]*?<\s*\/\s*tool_calls\s*>/gi, '');
    text = text.replace(/<\s*tool_call[\s\S]*?<\s*\/\s*tool_call\s*>/gi, '');
    text = text.replace(/<\s*invoke[\s\S]*?<\s*\/\s*invoke\s*>/gi, '');
    text = text.replace(/<\s*parameter[\s\S]*?<\s*\/\s*parameter\s*>/gi, '');
    text = text.replace(/\btool_calls\s*>[\s\S]*?(?:>\s*\/\s*tool_calls\s*>|>\s*tool_calls\s*>)/gi, '');
    text = text.replace(/\binvoke\s*name\s*=\s*["'][^"']+["'][\s\S]*?(?:>\s*\/\s*invoke\s*>|>\s*invoke\s*>)/gi, '');
    text = text.replace(/(?:parameter\s*name\s*=|parametername\s*=)\s*["'][^"']+["'][\s\S]*?>\s*parameter\s*>/gi, '');
    text = text.replace(/<\/?tool_calls\s*>/gi, '');
    text = text.replace(/<\/?invoke\s*>/gi, '');
    text = text.replace(/<\/?parameter\s*>/gi, '');
    return text.replace(/\n{3,}/g, '\n\n').trim();
  }
  function extractNovaToolCallFiles(text) {
    text = String(text || '');
    if (!/tool_calls|invoke|write_file|parametername/i.test(text)) return [];
    var files = [];
    var seen = {};
    var re = /(?:parameter\s*name\s*=\s*["']path["']|parametername\s*=\s*["']path["']|["']path["'][^>]*>)\s*(\/[\w./-]+\.\w+)/gi;
    var m;
    while ((m = re.exec(text)) !== null) {
      var path = String(m[1] || '').trim();
      if (!path || seen[path]) continue;
      seen[path] = 1;
      var name = path.split('/').pop() || 'file';
      files.push({ path: path, name: name, ext: fileExt(name), url: '', agentPath: path });
    }
    return files;
  }
  function isNovaDeliverableFileExt(ext) {
    return /^(md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z|pptx?)$/i.test(String(ext || ''));
  }
  function extractNovaMarkdownFileLinks(text) {
    text = String(text || '');
    var files = [];
    var seen = {};
    var re = /\[([^\]]+)\]\((https?:[^)\s]+)\)/gi;
    var m;
    while ((m = re.exec(text)) !== null) {
      var name = String(m[1] || '').trim() || '文件';
      var url = String(m[2] || '').trim();
      if (!url) continue;
      var ext = fileExt(name) || fileExt(url.split('?')[0]);
      if (!ext || isImageExt(ext) || !isNovaDeliverableFileExt(ext)) continue;
      if (seen[url]) continue;
      seen[url] = 1;
      files.push({ url: url, name: name, ext: ext });
    }
    return files;
  }
  function collectNovaExtraFiles(raw, html) {
    var markdownFiles = extractNovaMarkdownFileLinks(raw);
    var mdNames = {};
    markdownFiles.forEach(function (f) { mdNames[f.name] = 1; });
    var all = markdownFiles.concat(
      extractNovaToolCallFiles(raw),
      extractNovaGeneratedFiles(raw),
      extractNovaNamedDownloadFiles(raw)
    );
    var rawText = String(raw || '');
    var hasDownloadIntent = /(?:可下载|下载链接|点击下载|Markdown文件|markdown文件|📎|下载\s*链接|附件|\.md\)|\.pdf\))/i.test(rawText);
    var shown = String(html || '');
    var out = [];
    var seen = {};
    all.forEach(function (f) {
      if (f.url && seen[f.url]) return;
      if (!f.url) {
        var agentKey = f.agentPath || f.path || '';
        if (!agentKey || seen[agentKey]) return;
        if (f.name && mdNames[f.name]) return;
        if (!hasDownloadIntent && !f.url) return;
        seen[agentKey] = 1;
      } else {
        seen[f.url] = 1;
      }
      if (shown.indexOf('data-filename="' + f.name + '"') >= 0) return;
      if (f.url && shown.indexOf(f.url) >= 0) return;
      out.push(f);
    });
    return out;
  }
  function normalizeNovaMarkdownLayout(text) {
    text = String(text || '');
    text = text.replace(/(\.(?:md|txt|html?|pdf|docx?|xlsx?|csv|json|yaml|yml|zip|rar|7z))(#\s*)/gi, '$1\n\n$2');
    text = text.replace(/([。！？!?.])(#\s*[^\n#]+)/g, '$1\n\n$2');
    text = text.replace(/([^\n])(#[#]?\s*[🔍✅🎯💡][^\n]*)/g, '$1\n\n$2');
    text = text.replace(/([^\n])(-\s*[✅🎯💡])/g, '$1\n$2');
    text = text.replace(/([：:])\s*-\s*/g, '$1\n- ');
    return text.trim();
  }
  function shouldRenderLinkAsFileCard(label, url) {
    if (!/^https?:\/\//i.test(String(url || ''))) return false;
    var ext = fileExt(label) || fileExt(String(url || '').split('?')[0]);
    return !!ext && !isImageExt(ext) && isNovaDeliverableFileExt(ext);
  }
  function novaRenderMarkdownLink(label, url) {
    var item = { url: url, name: label, ext: fileExt(label) || fileExt(url) };
    if (isImageFile(item)) return renderNovaImageCard(item);
    if (shouldRenderLinkAsFileCard(label, url)) return renderNovaFileCard(item);
    return '<a class="nova-md-link" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + esc(label) + '</a>';
  }
  function novaMarkdownBlockHtml(text) {
    text = normalizeNovaMarkdownLayout(text);
    var lines = String(text || '').split('\n');
    var html = '';
    var inList = false;
    function closeList() {
      if (inList) { html += '</ul>'; inList = false; }
    }
    lines.forEach(function (line) {
      var trimmed = line.trim();
      if (!trimmed) { closeList(); return; }
      var hm = trimmed.match(/^#{1,3}\s*(.+)$/);
      if (hm) {
        closeList();
        html += '<div class="nova-md-h">' + novaMarkdownInlineHtml(hm[1]) + '</div>';
        return;
      }
      var lm = trimmed.match(/^[-*•]\s+(.+)$/);
      if (lm) {
        if (!inList) { html += '<ul class="nova-md-list">'; inList = true; }
        html += '<li>' + novaMarkdownInlineHtml(lm[1]) + '</li>';
        return;
      }
      closeList();
      html += '<div class="nova-md-p">' + novaMarkdownInlineHtml(trimmed) + '</div>';
    });
    closeList();
    return html;
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
      ui.textEl.innerHTML = renderNovaBodyHtml(reply, ui);
      wireNovaRichContent(ui.textEl);
      stopNovaStreamWaitHint(ui);
    } else if (final) {
      ui.textEl.innerHTML = '';
    }
    syncNovaStreamThinking(ui);
    scrollC4();
  }
  function ensureNovaStreamVisibleReply(ui) {
    if (!ui || !ui.textEl) return '';
    var finalReply = novaFinalReplyText(ui) || String(ui.text || '').trim();
    var hasThink = !!(ui.thinkStream && ui.thinkStream.trim());
    if (finalReply) return finalReply;
    if (hasThink) {
      ui.textEl.innerHTML = '<span style="color:var(--text-2)">云枢已完成分析，请展开上方「深度思考」查看详情。</span>';
      if (ui.thinkPanel) {
        showNovaThinkPanel(ui, '已完成思考');
        ui.thinkPanel.classList.remove('collapsed');
      }
      return ui.thinkStream.trim();
    }
    ui.textEl.innerHTML = '<span style="color:var(--coral)">云枢未返回内容，请重试或切换模型（当前：' + esc(novaCurrentModelLabel()) + '）。</span>';
    return '';
  }
  function finalizeNovaThinkingPanel(ui) {
    if (!ui || !ui.thinkPanel) return;
    stopNovaStreamWaitHint(ui);
    paintNovaStreamText(ui, true);
    var finalReply = novaFinalReplyText(ui) || String(ui.text || '').trim();
    var hasThink = !!(ui.thinkStream && ui.thinkStream.trim());
    var hasTools = Object.keys(ui.tools || {}).length > 0;
    if (!finalReply) ensureNovaStreamVisibleReply(ui);
    if (hasThink || hasTools) {
      if (hasThink) renderNovaThinkBody(ui);
      if (hasTools) renderNovaToolSteps(ui);
      showNovaThinkPanel(ui, '已完成思考');
      ui.thinkPanel.classList.add('collapsed');
    } else if (finalReply) {
      ui.thinkPanel.style.display = 'none';
    } else {
      ui.thinkPanel.style.display = 'none';
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
  var NOVA_GEN_FILE_EXT = 'md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z|png|jpe?g|gif|webp|svg|pptx?';
  function novaGeneratedFilePathRe() {
    return new RegExp('((?:/[\\\\w.-]+)+\\.(?:' + NOVA_GEN_FILE_EXT + '))', 'gi');
  }
  function resolveNovaGeneratedFileUrl(path) {
    path = String(path || '').trim();
    if (!path) return '';
    if (/^https?:\/\//i.test(path)) return path;
    var base = (window.DunesNovaApi && window.DunesNovaApi.novaBase) ? window.DunesNovaApi.novaBase() : '';
    if (!base) return '';
    return base.replace(/\/$/, '') + '/v1/files/download?path=' + encodeURIComponent(path);
  }
  function extractNovaGeneratedFiles(text) {
    var raw = normalizeNovaBodyText(text);
    if (!raw) return [];
    if (extractNovaMarkdownFileLinks(raw).length) return [];
    var re = novaGeneratedFilePathRe();
    var files = [];
    var seen = {};
    var m;
    while ((m = re.exec(raw)) !== null) {
      var path = m[1];
      if (seen[path]) continue;
      seen[path] = 1;
      var name = path.split('/').pop() || 'file';
      files.push({
        path: path,
        name: name,
        ext: fileExt(name),
        url: '',
        agentPath: path
      });
    }
    return files;
  }
  function guessNovaAgentPaths(name) {
    name = String(name || '').trim();
    if (!name) return [];
    var base = name.split('/').pop() || name;
    var out = [];
    [name, base, '/tmp/' + base, '/workspace/' + base, '/opt/data/' + base, '/root/' + base].forEach(function (p) {
      if (p && out.indexOf(p) < 0) out.push(p);
    });
    return out;
  }
  function extractNovaNamedDownloadFiles(text) {
    var raw = normalizeNovaBodyText(text);
    if (!raw) return [];
    if (!/(?:可下载|下载链接|点击下载|Markdown文件|markdown文件|📎|下载\s*链接)/i.test(raw)) return [];
    if (tryParseHermesFileJson(raw) || extractNovaMarkdownFileLinks(raw).length) return [];
    var files = [];
    var seen = {};
    var re = /([\w\u4e00-\u9fff._-]+\.(?:md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z))/gi;
    var m;
    while ((m = re.exec(raw)) !== null) {
      var name = String(m[1] || '').trim();
      if (!name || seen[name] || !isNovaDeliverableFileExt(fileExt(name))) continue;
      seen[name] = 1;
      var paths = guessNovaAgentPaths(name);
      files.push({
        name: name,
        ext: fileExt(name),
        url: '',
        agentPath: paths[0] || name,
        agentPathCandidates: paths
      });
    }
    return files;
  }
  function renderNovaTextWithGeneratedFiles(raw) {
    raw = String(raw || '');
    if (!raw.trim()) return '';
    if (extractNovaMarkdownFileLinks(raw).length) return '';
    var re = novaGeneratedFilePathRe();
    var html = '';
    var last = 0;
    var m;
    var hit = false;
    re.lastIndex = 0;
    while ((m = re.exec(raw)) !== null) {
      hit = true;
      if (m.index > last) html += novaMarkdownInlineHtml(raw.slice(last, m.index));
      var path = m[1];
      var name = path.split('/').pop() || 'file';
      html += renderNovaFileCard({
        url: '',
        name: name,
        ext: fileExt(name),
        agentPath: path
      });
      last = re.lastIndex;
    }
    if (!hit) return '';
    if (last < raw.length) html += novaMarkdownInlineHtml(raw.slice(last));
    return html;
  }
  function novaBodyNeedsRichRender(text) {
    var raw = sanitizeNovaBody(text || '');
    if (!raw) return false;
    if (/```/.test(raw) || /`[^`\n]+`/.test(raw)) return true;
    if (/!\[[^\]]*\]\(https?:/i.test(raw)) return true;
    if (tryParseHermesFileJson(raw) || tryParseMarkdownFileLink(raw)) return true;
    if (extractNovaGeneratedFiles(raw).length) return true;
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
      + '<div class="dni-foot">'
      + '<span class="dni-name">' + esc(name) + '</span>'
      + '<span class="dni-actions">'
      + '<button type="button" class="dni-btn nova-img-preview-btn" title="查看大图"><i class="ti ti-zoom-in"></i></button>'
      + '<button type="button" class="dni-btn nova-img-dl-btn" data-url="' + esc(file.url) + '" data-filename="' + esc(name) + '" title="下载图片"><i class="ti ti-download"></i></button>'
      + '</span></div></div>';
  }
  function renderNovaFileCard(file) {
    if (!file || (!file.url && !file.agentPath && !file.path)) return '';
    var ext = file.ext || fileExt(file.name);
    var icon = fileIconClass(ext);
    var sizeHint = ext ? ext.toUpperCase() : 'FILE';
    var dlUrl = file.url || '';
    var agentPath = file.agentPath || file.path || '';
    var pathCandidates = file.agentPathCandidates || (agentPath ? guessNovaAgentPaths(file.name || agentPath) : []);
    return ''
      + '<div class="dunes-nova-file-card tappable" role="button" tabindex="0"'
      + ' data-url="' + esc(dlUrl) + '" data-filename="' + esc(file.name) + '" data-download="1"'
      + (agentPath ? ' data-agent-path="' + esc(agentPath) + '"' : '')
      + (pathCandidates && pathCandidates.length ? ' data-agent-path-candidates="' + esc(JSON.stringify(pathCandidates)) + '"' : '')
      + '>'
      + '<div class="dnf-icon"><i class="ti ' + icon + '"></i></div>'
      + '<div class="dnf-bd"><div class="dnf-name">' + esc(file.name) + '</div>'
      + '<div class="dnf-meta">' + esc(sizeHint) + ' · 点击下载</div></div>'
      + '<div class="dnf-go" title="下载"><i class="ti ti-download"></i></div></div>';
  }
  function renderNovaDeliverableCard(file) {
    if (isImageFile(file)) return renderNovaImageCard(file);
    return renderNovaFileCard(file);
  }
  function renderNovaBodyInlineSegment(body) {
    var raw = String(body || '').replace(/\]\s*\n+\s*\(/g, '](');
    if (!raw.trim()) return '';
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
      return renderNovaBodyInlineSegment(rest) + card;
    }
    var linkRe = /\[([^\]]+)\]\((https?:[^)\s]+)\)/gi;
    var html = '';
    var last = 0;
    var m;
    var hit = false;
    while ((m = linkRe.exec(raw)) !== null) {
      hit = true;
      if (m.index > last) html += novaMarkdownInlineHtml(raw.slice(last, m.index));
      html += novaRenderMarkdownLink(m[1], m[2]);
      last = linkRe.lastIndex;
    }
    if (hit) {
      if (last < raw.length) html += novaMarkdownInlineHtml(raw.slice(last));
      return html;
    }
    var bareRe = /\((https?:\/\/[^)\s]+\.(?:jpe?g|png|gif|webp|svg)(?:\?[^)\s]*)?)\)/gi;
    last = 0;
    hit = false;
    html = '';
    while ((m = bareRe.exec(raw)) !== null) {
      hit = true;
      if (m.index > last) html += novaMarkdownInlineHtml(raw.slice(last, m.index));
      var u = m[1];
      var nm = '';
      try { nm = decodeURIComponent(u.split('/').pop().split('?')[0]); } catch (e2) { nm = '图片'; }
      html += renderNovaImageCard({ url: u, name: nm, ext: fileExt(u) });
      last = bareRe.lastIndex;
    }
    if (hit) {
      if (last < raw.length) html += novaMarkdownInlineHtml(raw.slice(last));
      return html;
    }
    var withFiles = renderNovaTextWithGeneratedFiles(raw);
    if (withFiles) return withFiles;
    if (/^#{1,3}\s/m.test(raw) || /^[-*•]\s/m.test(raw) || /\n[-*•]\s/m.test(raw)) {
      return novaMarkdownBlockHtml(raw);
    }
    return novaMarkdownInlineHtml(raw);
  }
  function prepareNovaAssistantBody(body) {
    var split = splitNovaReasoningReply(body, true);
    var raw = stripHermesProgressLines(sanitizeNovaBody(split.reply || body));
    if (!raw) return { raw: '', toolRaw: '' };
    return { raw: stripNovaToolCallLeak(raw), toolRaw: raw };
  }
  function renderNovaBodyHtml(body, streamUi) {
    var prep = prepareNovaAssistantBody(body);
    var raw = prep.raw;
    if (!raw && prep.toolRaw) raw = stripNovaToolCallLeak(prep.toolRaw);
    if (!raw) return '';
    var html = /```/.test(raw) ? renderNovaMarkdownHtml(raw) : renderNovaBodyInlineSegment(raw);
    var extra = collectNovaExtraFiles(prep.toolRaw || body, html);
    if (streamUi && streamUi.pendingFiles && streamUi.pendingFiles.length) {
      extra = extra.concat(streamUi.pendingFiles);
    }
    if (extra.length) html += extra.map(function (f) { return renderNovaFileCard(f); }).join('');
    return html;
  }
  function novaCurrentModelLabel() {
    var id = (window.DunesNovaApi && window.DunesNovaApi.selectedChatModel)
      ? window.DunesNovaApi.selectedChatModel()
      : (localStorage.getItem('dunes_nova_chat_model') || '');
    if (window.DunesNovaApi && window.DunesNovaApi.modelDisplayName) {
      return window.DunesNovaApi.modelDisplayName(id) || id || '当前模型';
    }
    return id || '当前模型';
  }
  function ensureNovaImageViewerReady() {
    if (typeof window.__dunesOpenImageViewer === 'function') return;
    if (window.DunesImChat && typeof window.DunesImChat.ensureImageViewer === 'function') {
      window.DunesImChat.ensureImageViewer();
    }
  }
  async function openNovaImagePreview(el) {
    ensureNovaImageViewerReady();
    if (!el) return;
    var u = el.getAttribute('data-full-url') || el.getAttribute('data-url') || el.src || '';
    var objectKey = el.getAttribute('data-object-key') || '';
    var fileName = el.getAttribute('data-file-name') || el.getAttribute('alt') || 'image.jpg';
    var bucket = el.getAttribute('data-bucket') || 'im-attachments';
    if (!objectKey && u && !isPublicMediaUrl(u)) objectKey = u;
    if (objectKey || (!isPublicMediaUrl(u) && u)) {
      try { u = await resolveNovaAttachmentUrl(el) || u; } catch (e) {}
    }
    if (!u && objectKey) {
      try {
        var pr = await apiJson('/storage/presigned-get?bucket=' + encodeURIComponent(bucket) + '&objectKey=' + encodeURIComponent(objectKey));
        if (pr.success && pr.data && pr.data.url) u = pr.data.url;
      } catch (e2) {}
    }
    if (!u && !objectKey) {
      if (window.DunesAPI && window.DunesAPI.toast) window.DunesAPI.toast('图片加载中，请稍后再试');
      return;
    }
    if (typeof window.__dunesOpenImageViewer === 'function') {
      window.__dunesOpenImageViewer(u, { objectKey: objectKey, fileName: fileName, bucket: bucket });
      return;
    }
    if (u) window.open(u, '_blank', 'noopener');
  }
  function openNovaImageUrl(url) {
    if (!url) return;
    ensureNovaImageViewerReady();
    if (typeof window.__dunesOpenImageViewer === 'function') {
      window.__dunesOpenImageViewer(url);
      return;
    }
    window.open(url, '_blank', 'noopener');
  }
  function openNovaDirectFileUrl(url, fileName) {
    url = String(url || '').trim();
    fileName = String(fileName || 'download').trim() || 'download';
    if (!url) return;
    try {
      var a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    } catch (e) {
      window.open(url, '_blank', 'noopener');
    }
  }
  function openNovaFileDownload(url, fileName, agentPath, agentPathCandidates) {
    url = String(url || '').trim();
    fileName = String(fileName || 'download').trim() || 'download';
    agentPath = String(agentPath || '').trim();
    if (/^https?:\/\//i.test(url)) {
      openNovaDirectFileUrl(url, fileName);
      return;
    }
    if (agentPath || agentPathCandidates) {
      fetchNovaAgentFile(url, fileName, agentPath, agentPathCandidates);
      return;
    }
    if (fileName) fetchNovaAgentFile('', fileName, '', guessNovaAgentPaths(fileName));
  }
  function novaDownloadHeaders() {
    var h = { Accept: '*/*' };
    var key = localStorage.getItem('dunes_nova_api_key') || '';
    if (key) h.Authorization = 'Bearer ' + key;
    var sid = (window.DunesNovaApi && window.DunesNovaApi.novaThreadSessionId)
      ? window.DunesNovaApi.novaThreadSessionId() : '';
    if (sid) h['X-Nova-Chat-Session-Id'] = sid;
    return h;
  }
  function fetchNovaAgentFile(url, fileName, agentPath, agentPathCandidates) {
    var candidates = [];
    if (url && /\/v1\/files\/download/i.test(url)) candidates.push(url);
    var paths = [];
    agentPath = String(agentPath || '').trim();
    if (agentPath) paths.push(agentPath);
    if (agentPathCandidates) {
      if (typeof agentPathCandidates === 'string') {
        try { agentPathCandidates = JSON.parse(agentPathCandidates); } catch (e0) { agentPathCandidates = [agentPathCandidates]; }
      }
      if (Array.isArray(agentPathCandidates)) {
        agentPathCandidates.forEach(function (p) {
          p = String(p || '').trim();
          if (p && paths.indexOf(p) < 0) paths.push(p);
        });
      }
    }
    if (!paths.length && fileName) paths = guessNovaAgentPaths(fileName);
    var base = (window.DunesNovaApi && window.DunesNovaApi.novaBase) ? window.DunesNovaApi.novaBase().replace(/\/$/, '') : '';
    paths.forEach(function (p) {
      if (base) candidates.push(base + '/v1/files/download?path=' + encodeURIComponent(p));
    });
    var idx = 0;
    function tryNext() {
      if (idx >= candidates.length) {
        if (window.DunesAPI && window.DunesAPI.toast) {
          window.DunesAPI.toast('文件下载失败：云枢未返回有效下载链接，请让 Nova 在回复中附带 [文件名](https://...) 链接');
        }
        return;
      }
      var u = candidates[idx++];
      fetch(u, { headers: novaDownloadHeaders() }).then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.blob();
      }).then(function (blob) {
        if (!blob || !(blob.size >= 0)) throw new Error('empty');
        var objUrl = URL.createObjectURL(blob);
        try {
          var a = document.createElement('a');
          a.href = objUrl;
          a.download = fileName;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
        } finally {
          setTimeout(function () { URL.revokeObjectURL(objUrl); }, 2000);
        }
      }).catch(function () { tryNext(); });
    }
    tryNext();
  }
  function copyNovaCodeBlock(codeId, btn) {
    var el = document.getElementById(codeId);
    if (!el) return;
    var text = el.textContent || '';
    function done(ok) {
      if (!btn) return;
      var span = btn.querySelector('span');
      if (ok && span) {
        var prev = span.textContent;
        span.textContent = '已复制';
        setTimeout(function () { span.textContent = prev || '复制'; }, 1500);
      }
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { done(true); }).catch(function () { done(false); });
      return;
    }
    try {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      done(true);
    } catch (e2) { done(false); }
  }
  function wireNovaRichContent(root) {
    if (!root) return;
    wireNovaImageThumbs(root);
    root.querySelectorAll('.nova-code-copy').forEach(function (btn) {
      if (btn.dataset.novaCopyWired) return;
      btn.dataset.novaCopyWired = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        copyNovaCodeBlock(btn.getAttribute('data-copy-id'), btn);
      });
    });
    root.querySelectorAll('.nova-img-dl-btn').forEach(function (btn) {
      if (btn.dataset.novaDlWired) return;
      btn.dataset.novaDlWired = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        openNovaFileDownload(
          btn.getAttribute('data-url'),
          btn.getAttribute('data-filename'),
          btn.getAttribute('data-agent-path'),
          btn.getAttribute('data-agent-path-candidates')
        );
      });
    });
    root.querySelectorAll('.dunes-nova-file-card').forEach(function (card) {
      if (card.dataset.novaFileWired) return;
      card.dataset.novaFileWired = '1';
      card.addEventListener('click', function (e) {
        if (e.target.closest('.nova-code-copy, .nova-img-dl-btn')) return;
        e.preventDefault();
        e.stopPropagation();
        openNovaFileDownload(
          card.getAttribute('data-url'),
          card.getAttribute('data-filename'),
          card.getAttribute('data-agent-path'),
          card.getAttribute('data-agent-path-candidates')
        );
      });
    });
    root.querySelectorAll('.dunes-nova-image-card .nova-img-preview-btn').forEach(function (btn) {
      if (btn.dataset.novaPvWired) return;
      btn.dataset.novaPvWired = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var card = btn.closest('.dunes-nova-image-card');
        var img = card && card.querySelector('img');
        if (img) openNovaImagePreview(img);
      });
    });
    root.querySelectorAll('.nova-md-link').forEach(function (a) {
      if (a.dataset.novaLinkWired) return;
      a.dataset.novaLinkWired = '1';
      a.addEventListener('click', function (e) {
        e.stopPropagation();
        var href = a.getAttribute('href');
        if (!href) return;
        e.preventDefault();
        try { window.open(href, '_blank', 'noopener noreferrer'); } catch (err) {
          window.location.href = href;
        }
      });
    });
  }
  function wireNovaImageThumbs(root) {
    if (!root) return;
    ensureNovaImageViewerReady();
    root.querySelectorAll('.dunes-img-thumb, .dunes-nova-combo-img, .dunes-nova-image-card img').forEach(function (img) {
      if (img.dataset.novaImgWired) return;
      img.dataset.novaImgWired = '1';
      img.style.cursor = 'pointer';
      img.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        openNovaImagePreview(img);
      });
    });
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
    var isAi = kind === 'AI_ASSISTANT' || kind === 'AI_TOOL_CALL' || (!isUser && (sender.displayName === YUNSHU_NAME || sender.displayName === 'NOVA' || uid === 0));
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
        + novaUserAvHtml()
        + '<div class="msg-content"><div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent"><img src="' + src + '" class="dunes-img-thumb" data-url="' + esc(mediaUrl) + '" data-object-key="' + esc(mediaKey) + '" data-bucket="im-attachments" data-full-url="' + esc(mediaUrl) + '" data-file-name="' + esc(payload.fileName || body || 'image.jpg') + '" style="max-width:170px;border-radius:10px;display:block;cursor:pointer"></div>'
        + readStatusHtml(m.id) + '</div></div>';
    }
    if (isUser && kind === 'AUDIO') {
      var sec = Math.max(1, Number((payload && payload.durationSec) || String(body).replace(/\D/g, '') || 1));
      var audioKey = novaAttachmentObjectKey(payload);
      var audioUrl = payload && (payload.url || audioKey) || '';
      return ''
        + '<div class="msg-row sent" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + novaUserAvHtml()
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
        + novaUserAvHtml()
        + '<div class="msg-content"><div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent"><i class="ti ti-paperclip"></i> <a class="dunes-attach-link dunes-nova-file-link" href="' + href + '" data-url="' + esc(fileUrl) + '" data-object-key="' + esc(fileKey) + '" data-bucket="im-attachments" data-file-name="' + esc(payload.fileName || body) + '" target="_blank" rel="noopener">' + esc(body) + '</a></div>'
        + readStatusHtml(m.id) + '</div></div>';
    }
    if (isUser && kind === 'TEXT') {
      var combinedHtml = renderNovaCombinedAttachments(payload);
      return ''
        + '<div class="msg-row sent" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + novaUserAvHtml()
        + '<div class="msg-content">'
        + '<div class="msg-meta"><span>' + esc(time) + '</span><span class="nm">' + esc(selfName()) + '</span></div>'
        + '<div class="msg-bubble sent">' + (body ? esc(body) : '') + combinedHtml + '</div>'
        + readStatusHtml(m.id)
        + '</div></div>';
    }
    if (isAi || kind.indexOf('AI') >= 0) {
      return ''
        + '<div class="msg-row recv" data-msg-id="' + esc(m.id) + '" data-message-id="' + esc(m.id) + '"' + createdAttr + '>'
        + novaAvHtml('msg-av-sm ai-bot')
        + '<div class="msg-content">'
        + '<div class="msg-meta"><span class="nm">' + esc(YUNSHU_NAME) + '</span>'
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
      + '<div class="msg-meta"><span class="nm">' + esc(YUNSHU_NAME) + '</span>'
      + '<span class="badge-ai">AI</span></div>'
      + '<div class="msg-bubble ai-recv">' + esc(NOVA_WELCOME) + '</div>'
      + '</div></div>';
    setHasChat(false);
  }
  function applyNovaPeerFromPayload(j, items) {
    if (j.data && j.data.peerLastReadMessageId != null) {
      novaPeerRead = Number(j.data.peerLastReadMessageId) || 0;
    }
    markNovaUserMessagesRead();
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
    if (!window.DunesInbox) return;
    if (window.DunesInbox.patchNovaGeneratingPreview) {
      if (novaServerGenerating) {
        window.DunesInbox.patchNovaGeneratingPreview(convId, true, novaGenStatus);
      } else {
        window.DunesInbox.patchNovaGeneratingPreview(convId, false, '', previewText != null ? previewText : undefined);
      }
    }
    if (window.DunesInbox.refreshNovaInboxPreview) {
      window.DunesInbox.refreshNovaInboxPreview();
    }
  }
  function syncNovaLocalTurnPreview(targetConvId) {
    targetConvId = Number(targetConvId || convId || 0);
    if (!targetConvId || !window.DunesNovaApi || !window.DunesNovaApi.loadSessionMessages) return;
    var items = window.DunesNovaApi.loadSessionMessages('nova', targetConvId) || [];
    if (!items.length) return;
    var preview = lastNovaPreviewFromItems(items);
    if (!preview) {
      for (var i = items.length - 1; i >= 0; i--) {
        if (isUserOutboundMessage(items[i])) {
          preview = String(items[i].bodyText || '').trim();
          break;
        }
      }
    }
    var title = '';
    for (var j = items.length - 1; j >= 0; j--) {
      if (isUserOutboundMessage(items[j])) {
        title = String(items[j].bodyText || '').slice(0, 24);
        if (!title && items[j].payload && items[j].payload.attachments && items[j].payload.attachments.length) {
          title = items[j].payload.attachments.length > 1 ? '图文对话' : '图片对话';
        }
        break;
      }
    }
    if (!title) title = '对话';
    var last = items[items.length - 1];
    var turnMessageId = 0;
    for (var um = items.length - 1; um >= 0; um--) {
      if (isUserOutboundMessage(items[um])) {
        turnMessageId = Number(items[um].id || 0);
        break;
      }
    }
    if (window.DunesNovaApi.upsertLocalTurn) {
      window.DunesNovaApi.upsertLocalTurn('nova', {
        conversationId: targetConvId,
        title: title,
        lastMessagePreview: String(preview || title).slice(0, 200),
        lastMessageAt: (last && last.createdAt) || new Date().toISOString(),
        messageId: turnMessageId || (last && last.id) || 0,
        source: 'app'
      });
    }
  }
  function flushNovaConvToLocalHistory(targetConvId) {
    syncNovaLocalTurnPreview(targetConvId);
  }
  function novaTurnTitleFromUser(userLabel, payload) {
    userLabel = String(userLabel || '').trim();
    if (userLabel && userLabel !== '[图片]' && userLabel !== '[文件]' && userLabel !== '[消息]') {
      return userLabel.slice(0, 24);
    }
    if (payload && payload.attachments && payload.attachments.length) {
      return payload.attachments.length > 1 ? '图文对话' : '图片对话';
    }
    if (userLabel) return userLabel.slice(0, 24);
    return '对话';
  }
  function buildNovaHistoryTurnPayload(turn) {
    turn = turn || {};
    var userId = Number(localStorage.getItem('dunes_user_id') || 0);
    var bizUser = (window.DunesNovaApi && window.DunesNovaApi.novaBizUser) ? window.DunesNovaApi.novaBizUser() : '';
    var sessionId = (window.DunesNovaApi && window.DunesNovaApi.novaProfileSessionId)
      ? window.DunesNovaApi.novaProfileSessionId()
      : ((window.DunesNovaApi && window.DunesNovaApi.novaThreadSessionId) ? window.DunesNovaApi.novaThreadSessionId() : '');
    var model = String(turn.model || '');
    if (!model && window.DunesNovaApi && window.DunesNovaApi.selectedChatModel) {
      try { model = window.DunesNovaApi.selectedChatModel() || ''; } catch (e) {}
    }
    var assistant = String(turn.assistantMessage || '');
    var userMsg = String(turn.userMessage || '');
    var preview = String(turn.lastMessagePreview || '');
    if (!preview) preview = assistant.slice(0, 200) || userMsg.slice(0, 200);
    return {
      conversationId: Number(turn.conversationId),
      messageId: Number(turn.messageId || 0) || 0,
      title: String(turn.title || '对话').slice(0, 64),
      lastMessagePreview: preview.slice(0, 200),
      lastMessageAt: turn.lastMessageAt || new Date().toISOString(),
      source: 'app',
      userId: userId,
      userDisplayName: selfName(),
      bizUserId: bizUser,
      novaSessionId: sessionId,
      model: model,
      userMessage: userMsg.slice(0, 8000),
      assistantMessage: assistant.slice(0, 32000)
    };
  }
  var NOVA_HISTORY_SYNC_QUEUE_KEY = 'dunes_nova_history_sync_queue';
  var novaHistoryLastServerSync = '';
  function enqueueNovaHistorySync(payload) {
    try {
      var q = JSON.parse(localStorage.getItem(NOVA_HISTORY_SYNC_QUEUE_KEY) || '[]');
      q.push({ payload: payload, at: Date.now(), tries: 0 });
      if (q.length > 50) q = q.slice(q.length - 50);
      localStorage.setItem(NOVA_HISTORY_SYNC_QUEUE_KEY, JSON.stringify(q));
    } catch (e) {}
  }
  function flushNovaHistorySyncQueue() {
    var raw;
    try { raw = localStorage.getItem(NOVA_HISTORY_SYNC_QUEUE_KEY); } catch (e) { return Promise.resolve(); }
    if (!raw) return Promise.resolve();
    var q;
    try { q = JSON.parse(raw); } catch (e2) { return Promise.resolve(); }
    if (!q || !q.length) return Promise.resolve();
    var remain = [];
    var chain = Promise.resolve();
    q.forEach(function (item) {
      chain = chain.then(function () {
        return apiJson('/ai/history/turns', {
          method: 'POST',
          body: JSON.stringify(item.payload || {})
        }).then(function () { return null; }).catch(function () {
          item.tries = Number(item.tries || 0) + 1;
          if (item.tries < 5) remain.push(item);
          return null;
        });
      });
    });
    return chain.then(function () {
      try { localStorage.setItem(NOVA_HISTORY_SYNC_QUEUE_KEY, JSON.stringify(remain)); } catch (e3) {}
    });
  }
  function registerNovaHistoryTurn(turn) {
    if (!turn || !Number(turn.conversationId || 0)) return Promise.resolve();
    var payload = buildNovaHistoryTurnPayload(turn);
    var syncSig = [
      payload.conversationId,
      payload.messageId,
      payload.userMessage,
      payload.assistantMessage
    ].join('\x1e');
    if (syncSig === novaHistoryLastServerSync) return Promise.resolve();
    novaHistoryLastServerSync = syncSig;
    if (window.DunesNovaApi && window.DunesNovaApi.upsertLocalTurn) {
      window.DunesNovaApi.upsertLocalTurn('nova', {
        conversationId: payload.conversationId,
        title: payload.title,
        lastMessagePreview: payload.lastMessagePreview,
        lastMessageAt: payload.lastMessageAt,
        messageId: payload.messageId,
        source: 'app'
      });
    }
    return apiJson('/ai/history/turns', {
      method: 'POST',
      body: JSON.stringify(payload)
    }).then(function () {
      dequeueNovaHistorySync(payload);
      return null;
    }).catch(function () {
      enqueueNovaHistorySync(payload);
      return null;
    });
  }
  function dequeueNovaHistorySync(payload) {
    try {
      var q = JSON.parse(localStorage.getItem(NOVA_HISTORY_SYNC_QUEUE_KEY) || '[]');
      if (!q || !q.length) return;
      var sig = [
        payload.conversationId,
        payload.messageId,
        payload.userMessage,
        payload.assistantMessage
      ].join('\x1e');
      q = q.filter(function (item) {
        var p = item && item.payload;
        if (!p) return false;
        var itemSig = [
          p.conversationId,
          p.messageId,
          p.userMessage,
          p.assistantMessage
        ].join('\x1e');
        return itemSig !== sig;
      });
      localStorage.setItem(NOVA_HISTORY_SYNC_QUEUE_KEY, JSON.stringify(q));
    } catch (e) {}
  }
  function mergeLocalNovaHistoryTurns(serverRows) {
    var rows = (serverRows || []).slice();
    if (!window.DunesNovaApi || !window.DunesNovaApi.loadLocalTurns) return rows;
    var localRows = window.DunesNovaApi.loadLocalTurns('nova') || [];
    var map = {};
    rows.forEach(function (r) {
      var k = String(novaTurnConvId(r) || '');
      if (k) map[k] = r;
    });
    localRows.forEach(function (r) {
      var k = String(novaTurnConvId(r) || '');
      if (!k) return;
      var prev = map[k];
      var rAt = new Date(novaTurnAt(r) || 0).getTime();
      var pAt = prev ? new Date(novaTurnAt(prev) || 0).getTime() : 0;
      if (!prev || (!isNaN(rAt) && rAt >= pAt)) map[k] = Object.assign({}, prev || {}, r);
    });
    return Object.keys(map).map(function (k) { return map[k]; }).sort(function (a, b) {
      return new Date(novaTurnAt(b) || 0).getTime() - new Date(novaTurnAt(a) || 0).getTime();
    });
  }
  function persistNovaAssistantReply(opts) {
    opts = opts || {};
    if (opts.ui && opts.ui._novaTurnPersisted) return;
    var reply = stripHermesProgressLines(sanitizeNovaBody(String(opts.reply || ''))).trim();
    if (!convId || !reply) return;
    var userLabel = String(opts.userLabel || novaStreamUserText || '').trim() || '[消息]';
    var kind = String(opts.kind || 'TEXT').toUpperCase();
    var userPayload = opts.userPayload || null;
    if (opts.ui) opts.ui._novaTurnPersisted = true;
    var aiMsgId = Number(opts.aiMsgId) || (Date.now() + 1);
    var now = new Date().toISOString();
    if (window.DunesNovaApi && window.DunesNovaApi.appendSessionMessages) {
      var cached = window.DunesNovaApi.loadSessionMessages('nova', convId) || [];
      var toAppend = [];
      if (!opts.skipUser) {
        var userExists = false;
        for (var u = cached.length - 1; u >= 0; u--) {
          if (isUserOutboundMessage(cached[u])) {
            userExists = String(cached[u].bodyText || '') === userLabel;
            break;
          }
        }
        if (!userExists) {
          var userMsg = {
            id: Date.now(),
            kind: kind,
            bodyText: userLabel,
            content: userLabel,
            role: 'user',
            sender: { userId: Number(localStorage.getItem('dunes_user_id') || '1'), displayName: selfName() },
            createdAt: now
          };
          if (userPayload) userMsg.payload = userPayload;
          toAppend.push(userMsg);
        }
      }
      var hasSameAi = false;
      for (var a = cached.length - 1; a >= 0; a--) {
        var cm = cached[a];
        if (!cm) continue;
        var ck = String(cm.kind || '').toUpperCase();
        var aiLike = ck.indexOf('AI') >= 0 || (cm.sender && (cm.sender.displayName === YUNSHU_NAME || cm.sender.displayName === 'NOVA'));
        if (aiLike) {
          hasSameAi = String(cm.bodyText || '') === reply;
          break;
        }
      }
      if (!hasSameAi) {
        toAppend.push({
          id: aiMsgId,
          kind: 'AI_ASSISTANT',
          bodyText: reply,
          content: reply,
          role: 'assistant',
          sender: { displayName: YUNSHU_NAME, userId: 0 },
          createdAt: now
        });
      }
      if (toAppend.length) window.DunesNovaApi.appendSessionMessages('nova', convId, toAppend);
    }
    registerNovaHistoryTurn({
      conversationId: convId,
      title: novaTurnTitleFromUser(userLabel, userPayload),
      lastMessagePreview: reply.slice(0, 200),
      lastMessageAt: now,
      messageId: Number(opts.userMsgId || novaGenAfterMsgId || 0) || aiMsgId,
      userMessage: userLabel,
      assistantMessage: reply
    });
    saveNovaServerMessage('assistant', reply);
  }
  function persistNovaUserMessage(text, kind, payload) {
    if (!window.DunesNovaApi || !window.DunesNovaApi.appendSessionMessages || !convId) return 0;
    kind = String(kind || 'TEXT').toUpperCase();
    var id = Date.now();
    var msg = {
      id: id,
      kind: kind,
      bodyText: text,
      content: text,
      role: 'user',
      sender: { userId: Number(localStorage.getItem('dunes_user_id') || '1'), displayName: selfName() },
      createdAt: new Date().toISOString()
    };
    if (payload) msg.payload = payload;
    window.DunesNovaApi.appendSessionMessages('nova', convId, [msg]);
    saveNovaServerMessage('user', text, payload);
    novaGenAfterMsgId = id;
    persistNovaGenerating();
    return id;
  }
  function restoreNovaGeneratingIfNeeded() {
    if (novaServerGenerating) return true;
    return loadPersistedNovaGenerating();
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
    else if (!bgStreaming && !sending) {
      clearPersistedNovaGenerating();
      clearNovaStreamDraft();
    }
    syncInboxNovaGenerating(novaServerGenerating ? null : lastNovaPreviewFromItems(items));
    syncNovaInputLock();
  }
  function lastNovaPreviewFromItems(items) {
    if (!items || !items.length) return '';
    for (var i = items.length - 1; i >= 0; i--) {
      var m = items[i];
      if (!m) continue;
      var kind = String(m.kind || '').toUpperCase();
      if (kind.indexOf('AI') >= 0 || (m.sender && (!m.sender.userId || m.sender.displayName === YUNSHU_NAME || m.sender.displayName === 'NOVA'))) {
        return stripHermesProgressLines(sanitizeNovaBody(String(m.bodyText || '')));
      }
    }
    return '';
  }
  function refreshNovaGeneratingStatus() {
    if (!convId) return Promise.resolve();
    restoreNovaGeneratingIfNeeded();
    return Promise.resolve();
  }
  function paintNovaHistoryFromItems(serverItems, opts) {
    opts = opts || {};
    var items = filterNovaMsgsForSelf(serverItems || []);
    items = filterNovaViewMessages(items, { fullHistory: true });
    removeNovaServerPendingRow();
    if (items.length) {
      paintNovaMessages(items, opts.preserveLive ? opts : Object.assign({}, opts, { preserveLive: isNovaGenerationActive() }));
      setHasChat(true);
      return items;
    }
    var box = rowsEl();
    var hasRows = box && box.querySelector('.msg-row:not(.dunes-nova-welcome)');
    if (!hasRows && !opts.keepIfHasRows) showWelcome();
    else if (hasRows) setHasChat(true);
    return items;
  }
  function removeNovaServerPendingRow() {
    var box = rowsEl();
    if (!box) return;
    var keep = novaActiveStreamUi && novaActiveStreamUi.row;
    box.querySelectorAll('.dunes-nova-server-pending').forEach(function (row) {
      if (keep && row === keep) return;
      if (row.parentNode) row.parentNode.removeChild(row);
    });
  }
  function removeExtraNovaStreamRows(keepRow) {
    var box = rowsEl();
    if (!box) return;
    box.querySelectorAll('.msg-row.recv.dunes-nova-live, .msg-row.recv.dunes-nova-server-pending').forEach(function (row) {
      if (keepRow && row === keepRow) return;
      if (row.parentNode) row.parentNode.removeChild(row);
    });
  }
  function findActiveNovaStreamRow(box) {
    if (!box) return null;
    if (novaActiveStreamUi && novaActiveStreamUi.row && novaActiveStreamUi.row.parentNode && box.contains(novaActiveStreamUi.row)) {
      return novaActiveStreamUi.row;
    }
    var rows = box.querySelectorAll('.msg-row.recv.dunes-nova-live, .msg-row.recv.dunes-nova-server-pending');
    return rows.length ? rows[rows.length - 1] : null;
  }
  function stopNovaGeneratingPoll() {
    if (novaGenPollTimer) {
      clearInterval(novaGenPollTimer);
      novaGenPollTimer = null;
    }
  }
  function maybeShowServerGenerating(opts) {
    opts = opts || {};
    if (!isNovaGenerationActive()) return;
    syncInboxNovaGenerating();
    if (!opts.force && (sending || bgStreaming) && novaActiveStreamUi && novaActiveStreamUi.row && novaActiveStreamUi.row.parentNode && activeIsC4()) {
      startNovaGeneratingPoll();
      syncNovaInputLock();
      return;
    }
    if (!opts.force && (sending || bgStreaming)) return;
    var box = rowsEl();
    if (!box) return;
    var draft = loadNovaStreamDraft();
    if (novaActiveStreamUi && (novaActiveStreamUi.thinkStream || novaActiveStreamUi.text)) {
      persistNovaStreamDraft(novaActiveStreamUi);
      draft = loadNovaStreamDraft();
    }
    if (box.querySelector('.dunes-nova-server-pending')) {
      var pendingRow = box.querySelector('.dunes-nova-server-pending');
      var pendingUi = (novaActiveStreamUi && novaActiveStreamUi.row === pendingRow)
        ? novaActiveStreamUi
        : novaUiFromStreamRow(pendingRow);
      if (pendingUi) novaActiveStreamUi = pendingUi;
      if (draft) restoreNovaStreamDraftToUi(pendingUi, draft);
      else if (pendingUi && pendingUi.thinkStatus) pendingUi.thinkStatus.textContent = novaGenStatus || '正在生成…';
      startNovaGeneratingPoll();
      syncNovaInputLock();
      return;
    }
    var liveRow = findActiveNovaStreamRow(box);
    if (liveRow) {
      var liveUi = (novaActiveStreamUi && novaActiveStreamUi.row === liveRow)
        ? novaActiveStreamUi
        : novaUiFromStreamRow(liveRow);
      if (liveUi) {
        novaActiveStreamUi = liveUi;
        liveRow.classList.add('dunes-nova-server-pending', 'dunes-nova-live');
        if (draft) restoreNovaStreamDraftToUi(liveUi, draft);
        else if (liveUi.thinkStatus) liveUi.thinkStatus.textContent = novaGenStatus || '正在生成…';
        startNovaGeneratingPoll();
        syncNovaInputLock();
        return;
      }
    }
    ensureGeneratingUserVisible(draft);
    var ui = createAiStreamRow();
    novaActiveStreamUi = ui;
    ui.row.classList.add('dunes-nova-server-pending', 'dunes-nova-live');
    if (draft) restoreNovaStreamDraftToUi(ui, draft);
    else showNovaThinkPanel(ui, novaGenStatus || '正在生成…');
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
      fetchNovaAiHistoryMessages(convId, { allowAutoSwitch: false }).then(function (aiItems) {
        var r = { items: aiItems || [], j: {} };
        applyNovaPeerFromPayload(r.j, r.items);
        applyNovaGeneratingState(r.j, r.items);
        if (!novaServerGenerating) {
          var streamActive = !!(bgStreaming || sending);
          if (!streamActive) {
            try {
              var raw = sessionStorage.getItem(novaGenStorageKey());
              if (raw) {
                var o = JSON.parse(raw);
                if (o && Date.now() - Number(o.at || 0) <= NOVA_GEN_STORAGE_TTL_MS && !hasAiReplyAfter(r.items, Number(o.after || 0))) {
                  streamActive = true;
                  novaServerGenerating = true;
                  novaGenAfterMsgId = Number(o.after || 0);
                  novaGenStatus = o.status || novaGenStatus || '正在生成…';
                }
              }
            } catch (e) {}
          }
          if (streamActive) {
            syncInboxNovaGenerating();
            if (activeIsC4()) maybeShowServerGenerating({ force: true });
            return;
          }
          stopNovaGeneratingPoll();
          clearPersistedNovaGenerating();
          clearNovaStreamDraft();
          novaActiveStreamUi = null;
          novaStreamUserText = '';
          syncInboxNovaGenerating(lastNovaPreviewFromItems(r.items));
          syncNovaInputLock();
          if (activeIsC4()) {
            removeNovaServerPendingRow();
            var box = rowsEl();
            var hasFinalAi = box && uiHasFinalAssistantBubble(box, lastNovaPreviewFromItems(r.items));
            if (!hasFinalAi) loadHistory();
            refreshNovaReadStatuses();
            if (novaStickToBottom) scrollC4(false);
          }
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
    clearNovaLocateState();
    return loadHistory();
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
  function dedupeNovaDisplayMessages(items) {
    var out = [];
    (items || []).forEach(function (m) {
      if (!m) return;
      var mAi = String(m.kind || '').toUpperCase().indexOf('AI') >= 0;
      var mTxt = String(m.bodyText || m.content || '').trim();
      if (mAi && mTxt) {
        for (var i = 0; i < out.length; i++) {
          var o = out[i];
          var oAi = String(o.kind || '').toUpperCase().indexOf('AI') >= 0;
          var oTxt = String(o.bodyText || o.content || '').trim();
          if (oAi && oTxt === mTxt) return;
        }
      }
      out.push(m);
    });
    return out;
  }
  function uiHasFinalAssistantBubble(box, previewText) {
    if (!box || !previewText) return false;
    previewText = stripHermesProgressLines(sanitizeNovaBody(String(previewText || ''))).trim();
    if (!previewText) return false;
    var want = previewText.replace(/\s+/g, ' ').trim();
    var hits = 0;
    box.querySelectorAll('.msg-row.recv .msg-bubble.ai-recv').forEach(function (bubble) {
      var txt = String(bubble.textContent || '').replace(/\s+/g, ' ').trim();
      if (!txt || !want) return;
      if (txt === want || txt.indexOf(want.slice(0, Math.min(48, want.length))) >= 0) hits++;
    });
    return hits > 0;
  }
  function captureNovaLiveRows() {
    var box = rowsEl();
    if (!box) return [];
    return Array.prototype.slice.call(box.querySelectorAll('.dunes-nova-live, .dunes-nova-server-pending'));
  }
  function restoreNovaLiveRows(liveRows, box) {
    if (!box || !liveRows || !liveRows.length) return;
    liveRows.forEach(function (row) {
      if (!row) return;
      if (row.parentNode !== box) box.appendChild(row);
    });
  }
  function paintNovaMessages(items, opts) {
    opts = opts || {};
    var box = rowsEl();
    if (!box) return;
    items = dedupeNovaDisplayMessages(items || []);
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
      var liveRows = opts.preserveLive ? captureNovaLiveRows() : [];
      box.innerHTML = '';
      box.appendChild(frag);
      restoreNovaLiveRows(liveRows, box);
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
    hydrateNovaUserAvatars(box);
    wireC4VoicePlay();
    wireNovaRichContent(box);
    if (opts.scroll !== false) scrollC4(!!opts.scrollForce);
  }
  function loadOlderNovaMessages() {
    if (novaMsgLoadingOlder || !convId || isNovaGenerationActive()) return Promise.resolve();
    novaMsgLoadingOlder = true;
    novaSuppressAutoScroll = true;
    var stream = streamWrap();
    var prevHeight = stream ? stream.scrollHeight : 0;
    return fetchNovaAiHistoryMessages(convId, { allowAutoSwitch: false }).then(function (items) {
      items = filterNovaViewMessages(items || [], { fullHistory: true });
      var box = rowsEl();
      if (!box || !items.length) {
        novaMsgHasMore = false;
        ensureNovaLoadMoreHint(box);
        return;
      }
      novaMsgHasMore = false;
      paintNovaMessages(items, { prepend: false, scroll: false });
      if (stream) stream.scrollTop = Math.max(0, stream.scrollHeight - prevHeight);
      ensureNovaLoadMoreHint(box);
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
      updateNovaStickToBottom();
      if (stream.scrollTop < 72 && !isNovaGenerationActive()) loadOlderNovaMessages();
    }, { passive: true });
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
      sender: { displayName: YUNSHU_NAME, userId: 0 },
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
    setNovaDebugInfo({ source: 'server', localCount: 0, aiCount: 0, mergedCount: 0, shownCount: 0 });
    var stillGenerating = restoreNovaGeneratingIfNeeded();
    if (!stillGenerating) {
      stopNovaGeneratingPoll();
      removeNovaServerPendingRow();
    }
    function paintAndFinish(items) {
      var generating = stillGenerating || isNovaGenerationActive();
      items = filterNovaMsgsForSelf(items || []);
      var mergedCount = items.length;
      items = filterNovaViewMessages(items, { generating: generating, fullHistory: true });
      setNovaDebugInfo({ source: 'ai_history', aiCount: mergedCount, mergedCount: mergedCount, shownCount: items.length });
      if (!items.length && !generating) {
        showWelcome();
        setHasChat(false);
        syncNovaInputLock();
        return Promise.resolve();
      }
      if (items.length) {
        paintNovaMessages(items, { scroll: true, scrollForce: novaStickToBottom, preserveLive: generating });
        wireNovaStreamHistory();
        setHasChat(true);
      } else if (generating) {
        setHasChat(true);
      }
      if (generating) {
        if (novaActiveStreamUi) persistNovaStreamDraft(novaActiveStreamUi);
        maybeShowServerGenerating({ force: true });
        startNovaGeneratingPoll();
        syncInboxNovaGenerating();
      }
      syncNovaInputLock();
      return Promise.resolve();
    }
    return fetchNovaAiHistoryMessages(convId, { allowAutoSwitch: false }).then(function (aiItems) {
      return paintAndFinish(aiItems);
    }).catch(function () {
      setNovaDebugInfo({ source: 'server_err', aiCount: 0, mergedCount: 0, shownCount: 0 });
      return paintAndFinish([]);
    });
  }
  function loadHistoryAround(centerId) {
    if (!convId || !centerId) return loadHistory();
    novaSuppressAutoScroll = true;
    clearNovaViewSince();
    return fetchNovaAiHistoryMessages(convId, { allowAutoSwitch: false }).then(function (items) {
      items = filterNovaViewMessages(items || [], { fullHistory: true });
      if (!items.length) return loadHistory();
      stopNovaGeneratingPoll();
      removeNovaServerPendingRow();
      paintNovaMessages(items, { scroll: false });
      wireNovaStreamHistory();
      setHasChat(true);
      syncNovaInputLock();
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
    if (isNovaAccountBlocked()) { showNovaNotReadyTip(novaBlockMessage); return Promise.resolve(); }
    if (isNovaGenerationActive()) { showNovaInputBusyHint(); return Promise.resolve(); }
    var prevConv = convId;
    if (prevConv) flushNovaConvToLocalHistory(prevConv);
    stopNovaGeneratingPoll();
    novaServerGenerating = false;
    sending = false;
    bgStreaming = false;
    clearPersistedNovaGenerating();
    novaPeerRead = 0;
    clearNovaDraftAttachments();
    clearApiRows();
    showWelcome();
    setHasChat(false);
    convId = 0;
    window.pendingConvId = 0;
    try { pendingConvId = null; } catch (e) {}
    try { localStorage.removeItem('dunes_nova_conv_id'); } catch (e2) {}
    syncInboxNovaGenerating('');
    syncNovaInputLock();
    scrollC4();
    if (window.DunesAPI && window.DunesAPI.toast) {
      window.DunesAPI.toast('已开启新对话，上一段可在右上角「历史」查看');
    }
    return createNovaServerConversation(YUNSHU_NAME).then(function (id) {
      if (id) {
        if (prevConv && id === prevConv) {
          clearNovaViewSince();
        } else {
          setNovaViewSince();
        }
        applyNovaConversationId(id);
        if (window.DunesNovaApi && window.DunesNovaApi.saveSessionMessages) {
          window.DunesNovaApi.saveSessionMessages('nova', id, []);
        }
        syncInboxNovaGenerating('');
      } else {
        clearNovaViewSince();
      }
      return id || convId;
    }).catch(function () {
      clearNovaViewSince();
      return convId || 0;
    });
  }
  function isNovaSlashNew(text) {
    var t = String(text || '').trim().toLowerCase();
    return t === '/new' || t === '/新对话' || t === '新对话';
  }
  function openNovaSearch() {
    if (isNovaGenerationActive()) { showNovaInputBusyHint(); return Promise.resolve(); }
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
      var at = novaTurnAt(r) || '';
      var divLabel = dayDividerLabel(at, prevAt);
      if (divLabel) {
        var secEl = document.createElement('div');
        secEl.className = 'msg-date-divider';
        secEl.textContent = divLabel;
        box.appendChild(secEl);
      }
      var conv = novaTurnConvId(r);
      var mid = novaTurnMessageId(r);
      var preview = stripHermesProgressLines(sanitizeNovaBody(novaTurnPreviewText(r)));
      if (preview.indexOf('你好，我是你的') === 0) preview = '';
      var card = document.createElement('div');
      card.className = 'noti-card tappable';
      card.dataset.title = String(r.title || '');
      card.dataset.preview = preview;
      card.innerHTML = '<div class="nc-ic nova-hist-ic">' + novaIcHtml() + '</div>'
        + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(novaTurnTitleText(r) || '新对话') + '</div>'
        + '<div class="nc-time">' + esc(formatNovaHistoryTime(at)) + '</div></div>'
        + '<div class="nc-desc">' + esc(preview || '（暂无消息预览）') + '</div></div>';
      card.addEventListener('click', function () {
        clearNovaViewSince();
        applyNovaConversationId(conv);
        window.__dunesNovaDirectTurn = Object.assign({}, r);
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
    if (name) name.textContent = YUNSHU_NAME + '对话历史';
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
    var historyHasMore = false;
    function loadHistoryRows() {
      return fetchAiHistoryTurnRowsFromApi(20, append ? novaHistoryOldestAt : '').then(function (rows) {
        historyHasMore = rows.length >= 20;
        return rows;
      });
    }
    return loadHistoryRows().then(function (rows) {
      syncNovaTurnsToLocal(rows);
      rows = dedupeNovaHistoryTurns(rows);
      rows = mergeLocalNovaHistoryTurns(rows);
      if (!append && !rows.length && window.DunesNovaApi && window.DunesNovaApi.loadLocalTurns) {
        rows = mergeLocalNovaHistoryTurns([]);
      }
      novaHistoryHasMore = historyHasMore;
      if (rows.length) novaHistoryOldestAt = novaTurnAt(rows[rows.length - 1]) || novaHistoryOldestAt;
      if (append) novaHistoryAll = novaHistoryAll.concat(rows);
      else novaHistoryAll = rows;
      var input = document.getElementById('c11-search-input');
      var sq = input ? input.value.trim() : '';
      if (sq) filterNovaHistory(sq);
      else renderNovaHistoryList(rows, !!append);
    }).catch(function (e) {
      if (!append && window.DunesNovaApi && window.DunesNovaApi.loadLocalTurns) {
        var localRows = window.DunesNovaApi.loadLocalTurns('nova') || [];
        novaHistoryAll = localRows;
        renderNovaHistoryList(localRows);
        return;
      }
      if (!append) box.innerHTML = '<div class="api-strip"><span>加载失败：' + esc(e.message || e) + '</span></div>';
    }).then(function () {
      novaHistoryLoading = false;
    });
  }
  var c4HeaderWired = false;
  function openNovaHistoryFromC4() {
    if (isNovaGenerationActive()) { showNovaInputBusyHint(); return; }
    if (typeof go === 'function') go('C11');
    else if (typeof setScreen === 'function') setScreen('C11', false);
  }
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
        if (isNovaGenerationActive()) { showNovaInputBusyHint(); return; }
        startNewConversation();
        return;
      }
      if (e.target.closest('#c4-btn-history')) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        openNovaHistoryFromC4();
        return;
      }
      if (e.target.closest('#c4-btn-search')) {
        e.preventDefault();
        e.stopPropagation();
        if (isNovaGenerationActive()) { showNovaInputBusyHint(); return; }
        openNovaSearch();
      }
    }, true);
  }
  function ensureSession() {
    ensureNovaOwnerStorage();
    if (convId) return Promise.resolve(convId);
    var saved = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
    if (saved > 0) {
      return validateNovaConvId(saved).then(function (ok) {
        if (ok > 0) {
          applyNovaConversationId(ok);
          return convId;
        }
        try { localStorage.removeItem('dunes_nova_conv_id'); } catch (e) {}
        convId = 0;
        return ensureSession();
      });
    }
    if (window.DunesNovaApi && window.DunesNovaApi.ensureNovaProfileSession) {
      window.DunesNovaApi.ensureNovaProfileSession();
    }
    return fetchNovaLatestConvIdFromServer().then(function (serverId) {
      if (serverId > 0) {
        applyNovaConversationId(serverId);
        return convId;
      }
      return createNovaServerConversation(YUNSHU_NAME).then(function (id) {
        if (id) return id;
        return 0;
      }).catch(function () {
        return 0;
      });
    });
  }
  function appendUserBubble(text, msgId, payload) {
    var box = rowsEl();
    if (!box) return;
    if (payload && novaAttachmentsFromPayload(payload).length) {
      var fake = {
        id: msgId || 0,
        kind: 'TEXT',
        bodyText: text,
        createdAt: new Date().toISOString(),
        sender: { userId: Number(localStorage.getItem('dunes_user_id') || '1'), displayName: selfName() },
        payload: payload
      };
      var wrap = document.createElement('div');
      wrap.innerHTML = renderHistoryMessage(fake);
      var comboRow = wrap.firstElementChild;
      if (comboRow) {
        comboRow.classList.add('dunes-nova-live');
        if (msgId) comboRow.dataset.messageId = String(msgId);
        box.appendChild(comboRow);
        hydrateNovaMediaUrls(comboRow);
        hydrateNovaUserAvatars(comboRow);
        wireNovaRichContent(comboRow);
        setHasChat(true);
        pinNovaScrollToBottom();
        scrollC4(true);
      }
      return;
    }
    var row = document.createElement('div');
    row.className = 'msg-row sent dunes-nova-live';
    if (msgId) row.dataset.messageId = String(msgId);
    row.innerHTML = ''
      + novaUserAvHtml()
      + '<div class="msg-content">'
      + '<div class="msg-meta"><span class="nm">' + esc(selfName()) + '</span></div>'
      + '<div class="msg-bubble sent">' + esc(text) + '</div>'
      + readStatusHtml(msgId || 0)
      + '</div>';
    box.appendChild(row);
    hydrateNovaUserAvatars(row);
    setHasChat(true);
    pinNovaScrollToBottom();
    scrollC4(true);
  }
  function createAiStreamRow() {
    var box = rowsEl();
    var row = document.createElement('div');
    row.className = 'msg-row recv dunes-nova-live';
    row.innerHTML = ''
      + novaAvHtml('msg-av-sm ai-bot')
      + '<div class="msg-content">'
      + '<div class="msg-meta"><span class="nm">' + esc(YUNSHU_NAME) + '</span>'
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
    pinNovaScrollToBottom();
    scrollC4(true);
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
  function novaUiFromStreamRow(row) {
    if (!row) return null;
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
      schedulePersistNovaStreamDraft(ui);
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
      var resultRaw = typeof data.result === 'string' ? data.result : JSON.stringify(data.result || {});
      var toolFiles = extractNovaToolCallFiles(resultRaw).concat(extractNovaGeneratedFiles(resultRaw));
      if (toolFiles.length) {
        if (!ui.pendingFiles) ui.pendingFiles = [];
        var seen = {};
        ui.pendingFiles.forEach(function (f) { seen[f.agentPath || f.path || f.name] = 1; });
        toolFiles.forEach(function (f) {
          var key = f.agentPath || f.path || f.name;
          if (!key || seen[key]) return;
          seen[key] = 1;
          ui.pendingFiles.push(f);
        });
        paintNovaStreamText(ui, false);
      }
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
      schedulePersistNovaStreamDraft(ui);
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
      if (data.code === 'vision_not_configured' || String(msg).indexOf('未开通') >= 0) {
        msg = '图片识别未开通：请确认当前模型「' + novaCurrentModelLabel() + '」已在 Nova 后台配置可用';
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
        msg = '云枢响应超时，模型处理较慢，请稍后重试';
      } else if (/hermes HTTP 500|do_request_failed|new_api_error/i.test(String(msg))) {
        msg = '云枢模型服务暂时不可用，请稍后重试或联系管理员';
      }
      ui._novaError = msg;
      ui.textEl.innerHTML = '<span style="color:var(--coral)">' + esc(msg) + '</span>';
      if (data.code === 'nova_not_ready') {
        ui._novaNotReady = true;
        applyNovaNotReady(msg);
      }
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
          ui.textEl.innerHTML = renderNovaBodyHtml(finalReply, ui);
          wireNovaRichContent(ui.textEl);
        } else if (!ui.textEl.innerHTML) {
          ui.textEl.innerHTML = '';
        }
      }
      if (data.messageId) finalizeStreamRow(ui, Number(data.messageId), serverText);
      if (finalReply) ui._novaAiMsgId = Number(data.messageId || ui._novaAiMsgId || 0) || undefined;
      if (data.peerLastReadMessageId != null) applyNovaPeerRead(data.peerLastReadMessageId);
      else if (data.messageId) applyNovaPeerRead(data.messageId);
      if (activeIsC4()) {
        markNovaConversationRead();
        scrollC4();
      }
    }
  }
  function sendMessageViaNovaApi(text, attempt, opts) {
    opts = opts || {};
    text = String(text || '').trim();
    attempt = attempt || 0;
    if (!window.DunesNovaApi || !window.DunesNovaApi.isReady()) {
      showNovaNotReadyTip(novaBlockMessage || '云枢尚未就绪');
      return Promise.resolve();
    }
    sending = true;
    bgStreaming = true;
    novaServerGenerating = true;
    novaUserStopped = false;
    novaActiveAbortController = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var kind = String(opts.kind || 'TEXT').toUpperCase();
    var hasMultimodalEarly = !!(opts.file || (opts.files && opts.files.length) || (opts.payload && (opts.payload.url || opts.payload.objectKey)) || (opts.payloads && opts.payloads.length));
    novaGenStatus = (kind === 'IMAGE' || (hasMultimodalEarly && kind !== 'FILE')) ? '正在分析图片…' : (kind === 'FILE' ? '正在阅读文件…' : '正在生成…');
    var userLabel = text || opts.multimodalPrompt || opts.bodyText || (kind === 'IMAGE' ? '[图片]' : kind === 'FILE' ? '[文件]' : '');
    novaStreamUserText = userLabel;
    persistNovaGenerating();
    persistNovaStreamDraft(null, novaStreamUserText);
    syncInboxNovaGenerating();
    syncNovaInputLock();
    if (attempt === 0 && !opts.skipUserBubble) {
      pinNovaScrollToBottom();
      var userPayload = opts.payload || (opts.payloads && opts.payloads.length ? { attachments: opts.payloads } : null);
      if (text) {
        var plainUserId = persistNovaUserMessage(text, 'TEXT');
        appendUserBubble(text, plainUserId);
      } else if (userLabel) {
        var mediaUserId = persistNovaUserMessage(userLabel, kind, userPayload);
        appendUserBubble(userLabel, mediaUserId, userPayload);
      }
      commitNovaUserLiveRows();
    }
    var ui = createAiStreamRow();
    novaActiveStreamUi = ui;
    if (kind === 'IMAGE') showNovaThinkPanel(ui, '正在识别图片…');
    else if (kind === 'FILE') showNovaThinkPanel(ui, '正在阅读文件…');
    else showNovaThinkPanel(ui, '正在生成…');
    startNovaStreamWaitHint(ui);
    var hasMultimodal = !!(opts.file || (opts.files && opts.files.length) || (opts.payload && (opts.payload.url || opts.payload.accessUrl)) || (opts.payloads && opts.payloads.length));
    var model = window.DunesNovaApi.selectedChatModel();
    var contentPromise = hasMultimodal
      ? window.DunesNovaApi.buildMultimodalContent({
          text: opts.multimodalPrompt || text || userLabel,
          kind: kind,
          file: opts.file,
          files: opts.files,
          payload: opts.payload,
          payloads: opts.payloads,
          imagePartType: window.DunesNovaApi.imagePartTypeForModel(model)
        })
      : Promise.resolve(text || userLabel);
    var novaUrl = (window.DunesNovaApi.novaBase ? window.DunesNovaApi.novaBase() : '') + '/v1/chat/completions';
    try {
      console.info('[DunesNovaChat] Nova POST', novaUrl, 'model=', model, 'multimodal=', hasMultimodal);
    } catch (logErr) {}
    ui._novaStreamModel = model;
    return contentPromise.then(function (content) {
      var messages = window.DunesNovaApi.buildNovaChatMessages
        ? window.DunesNovaApi.buildNovaChatMessages(content)
        : [{ role: 'user', content: content }];
      return window.DunesNovaApi.chatCompletionsStream({
        messages: messages,
        model: model,
        signal: novaActiveAbortController && novaActiveAbortController.signal
      }).then(function (r) {
        ui._novaHttpStatus = r && r.status;
        try { console.info('[DunesNovaChat] Nova HTTP', r && r.status, 'model=', model); } catch (logErr2) {}
        return window.DunesNovaApi.pumpOpenAiSse(r, {
          onThinkingDelta: function (piece) {
            applyStreamEvent(ui, 'thinking_delta', { text: piece });
            schedulePersistNovaStreamDraft(ui);
          },
          onDelta: function (piece) {
            if (HERMES_THINK_LINE_RE.test(String(piece || '').trim())) {
              applyStreamEvent(ui, 'thinking_delta', { text: piece });
              schedulePersistNovaStreamDraft(ui);
              return;
            }
            ui.text += piece;
            requestAnimationFrame(function () { paintNovaStreamText(ui, false); });
            schedulePersistNovaStreamDraft(ui);
          },
          onRag: function (rag) {
            if (rag && rag.used && ui.textEl) {
              var hint = ui.row && ui.row.querySelector('.nova-rag-hint');
              if (!hint && ui.textEl.parentNode) {
                hint = document.createElement('div');
                hint.className = 'nova-rag-hint';
                hint.style.cssText = 'font-size:11px;color:var(--text-3);margin-top:6px';
                hint.textContent = '已参考您的文档';
                ui.textEl.parentNode.appendChild(hint);
              }
            }
          },
          onQuota: function (q) {
            if (q && q.remain != null) localStorage.setItem('dunes_remain_quota', String(q.remain));
          }
        });
      }).then(function () {
        var reply = novaFinalReplyText(ui) || String(ui.text || '').trim();
        if (!reply && ui.thinkStream && ui.thinkStream.trim()) {
          ensureNovaStreamVisibleReply(ui);
          reply = ui.thinkStream.trim();
        }
        if (!reply) {
          throw new Error('Nova 未返回正文（model=' + model + ', HTTP ' + (ui._novaHttpStatus || '?') + '）');
        }
        markNovaUserMessagesRead();
        commitNovaUserLiveRows();
      });
    }).catch(function (e) {
      var msg = String((e && e.message) || e || '云枢请求失败');
      if (ui._novaStreamModel) msg = msg + ' [model=' + ui._novaStreamModel + ']';
      var stopped = novaUserStopped || (e && e.name === 'AbortError') || (ui.row && ui.row.dataset && ui.row.dataset.novaStopped === '1');
      novaServerGenerating = false;
      clearPersistedNovaGenerating();
      syncNovaInputLock();
      commitNovaUserLiveRows();
      if (stopped) {
        ui.text = novaFinalReplyText(ui) || ui.text || '已停止生成';
        if (ui.textEl) {
          ui.textEl.innerHTML = renderNovaBodyHtml(ui.text, ui);
          wireNovaRichContent(ui.textEl);
        }
        var partial = novaFinalReplyText(ui) || String(ui.text || '').trim();
        if (partial && partial !== '已停止生成') {
          persistNovaAssistantReply({
            ui: ui,
            reply: partial,
            userLabel: userLabel,
            kind: kind,
            skipUser: true
          });
        }
      } else {
        if (!ui.row || !ui.row.parentNode) ui = createAiStreamRow();
        ui.thinkPanel.style.display = 'none';
        if (!isNovaAccountBlocked()) {
          ui.textEl.innerHTML = '<span style="color:var(--coral)">' + esc(msg) + '</span>';
        } else {
          showNovaNotReadyTip(novaBlockMessage || msg);
        }
      }
      stopNovaGeneratingPoll();
      if (stopped) {
        syncInboxNovaGenerating('已停止生成');
      }
    }).then(function () {
      novaActiveAbortController = null;
      novaUserStopped = false;
      return finishStreamUi(ui, attempt, text);
    });
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
    var hasMedia = !!(opts.kind && (opts.file || opts.payload)) || !!opts.multimodalPrompt;
    if ((!text && !hasMedia) || sending || novaServerGenerating) {
      if (novaServerGenerating || sending || bgStreaming) showNovaInputBusyHint();
      else if (novaServerGenerating) maybeShowServerGenerating();
      return Promise.resolve();
    }
    if (isNovaAccountBlocked()) {
      showNovaNotReadyTip(novaBlockMessage);
      return Promise.resolve();
    }
    if (!novaReadinessChecked && attempt === 0) {
      return checkNovaReadiness().then(function (d) {
        if (d && d.ready === false) {
          showNovaNotReadyTip(novaBlockMessage);
          return;
        }
        return sendMessage(text, attempt, opts);
      });
    }
    if (!window.DunesNovaApi || !window.DunesNovaApi.isReady()) {
      showNovaNotReadyTip(novaBlockMessage || '云枢尚未就绪');
      return Promise.resolve();
    }
    if (!text && !hasMedia) {
      return Promise.resolve();
    }
    return ensureSession().then(function () {
      return sendMessageViaNovaApi(text, attempt, opts);
    });
  }
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
        var cardImg = imgCard.querySelector('img') || imgCard;
        openNovaImagePreview(cardImg);
        return;
      }
      var fileCard = e.target.closest('.dunes-nova-file-card');
      if (fileCard) {
        e.preventDefault();
        e.stopPropagation();
        openNovaFileDownload(
          fileCard.getAttribute('data-url') || '',
          fileCard.getAttribute('data-filename') || 'download',
          fileCard.getAttribute('data-agent-path') || '',
          fileCard.getAttribute('data-agent-path-candidates') || ''
        );
        return;
      }
      if (e.target.closest('#c4-send')) {
        e.preventDefault();
        e.stopPropagation();
        if (sending || bgStreaming || novaServerGenerating) {
          stopNovaGeneration();
          return;
        }
        submitC4Input();
        return;
      }
      var cell = e.target.closest('#c4-quick-actions .qa-cell');
      if (cell && !cell.dataset.go) {
        var label = (cell.querySelector('.qa-t') || {}).textContent || '';
        label = label.trim();
        if (label === '拍照' || cell.getAttribute('data-qa') === 'camera') {
          e.preventDefault();
          e.stopPropagation();
          triggerNovaFileInput('c4-camera-slot', 'image/*', 'environment', false);
          return;
        }
        if (label === '图片' || cell.getAttribute('data-qa') === 'album') {
          e.preventDefault();
          e.stopPropagation();
          triggerNovaFileInput('c4-album-slot', 'image/*', '', true);
          return;
        }
        if (label === '新对话' || cell.getAttribute('data-qa') === 'new-chat') {
          e.preventDefault();
          e.stopPropagation();
          startNewConversation();
          return;
        }
      }
      if (e.target.closest('.msg-input-bar .emoji-btn')) {
        e.preventDefault();
        e.stopPropagation();
        triggerNovaFileInput('c4-upload-slot', '*/*', '', true);
        return;
      }
      if (isNovaInputLocked() && e.target.closest('#c4-quick-actions .qa-cell, #c4-send, .msg-input-bar .voice-btn, .msg-input-bar .emoji-btn, #c4-input')) {
        e.preventDefault();
        e.stopPropagation();
        showNovaInputBusyHint();
        return;
      }
      if (isNovaAccountBlocked() && e.target.closest('#c4-quick-actions .qa-cell, #c4-send, .msg-input-bar .voice-btn, .msg-input-bar .emoji-btn, #c4-input')) {
        e.preventDefault();
        e.stopPropagation();
        showNovaNotReadyTip(novaBlockMessage);
        return;
      }
      var imgThumb = e.target.closest('.dunes-img-thumb, .dunes-nova-combo-img');
      if (imgThumb) {
        e.preventDefault();
        e.stopPropagation();
        openNovaImagePreview(imgThumb);
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
    closeC4ModelSheet();
    if (convId) applyNovaConversationId(convId);
    if (convId) flushNovaConvToLocalHistory(convId);
    if (bgStreaming || novaServerGenerating || sending) {
      persistNovaStreamDraft(novaActiveStreamUi);
      persistNovaGenerating();
      syncInboxNovaGenerating();
      showNovaGeneratingBackgroundTip();
      commitNovaUserLiveRows();
      if (novaServerGenerating && !novaGenPollTimer) startNovaGeneratingPoll();
    } else if (convId && window.DunesNovaApi && window.DunesNovaApi.loadSessionMessages) {
      var leaveItems = window.DunesNovaApi.loadSessionMessages('nova', convId) || [];
      syncInboxNovaGenerating(lastNovaPreviewFromItems(leaveItems) || undefined);
      stopNovaGeneratingPoll();
    } else {
      stopNovaGeneratingPoll();
    }
    if (!novaServerGenerating && !sending) {
      if (bgStreaming) {
        commitNovaUserLiveRows();
        if (!novaActiveStreamUi) clearNovaLiveRows();
      }
      bgStreaming = false;
    }
  }
  function onScreen(id) {
    if (id === 'C11') {
      if (window.DunesNovaApi && window.DunesNovaApi.ensureAiLocalHistoryPurged) {
        window.DunesNovaApi.ensureAiLocalHistoryPurged();
      }
      wireC11Header();
      loadNovaHistoryList();
      return;
    }
    if (id !== 'C4') return;
    ensureNovaOwnerStorage();
    if (Number(localStorage.getItem('dunes_nova_conv_id') || 0) > 0) clearNovaViewSince();
    if (window.DunesNovaApi && window.DunesNovaApi.ensureAiLocalHistoryPurged) {
      window.DunesNovaApi.ensureAiLocalHistoryPurged();
    }
    flushNovaHistorySyncQueue();
    if (typeof window.__dunesRefreshUserProfile === 'function') {
      window.__dunesRefreshUserProfile();
    }
    if (typeof window.__dunesWireNovaC4 === 'function') window.__dunesWireNovaC4();
    wireStackOnce();
    wireC4Header();
    applyYunshuBranding();
    wireC4MediaToolbar();
    ensureNovaDebugBar();
    setNovaDebugInfo({ source: 'enter', aiCount: 0, localCount: 0, mergedCount: 0, shownCount: 0 });
    ensureNovaImageViewerReady();
    observeNovaRowsScroll();
    wireNovaStreamHistory();
    if (window.DunesScreenLoader) window.DunesScreenLoader.show('C4', '加载对话…');
    if (!bgStreaming && !novaServerGenerating) sending = false;
    var resolved = resolveNovaConvIdForEnter();
    if (!resolved) {
      resolved = paintDirectNovaTurnFromHistory('direct_turn_open');
    }
    if (!resolved) {
      resolved = paintNovaLocalTurnPreview('local_turn_open');
    }
    var focusId = Number(window.__dunesFocusMessageId || window.__dunesMsgAnchorId || 0);
    var locating = focusId > 0 && !!window.__dunesLocateFromHistory;
    var validateChain = resolved > 0
      ? validateNovaConvId(resolved).then(function (ok) {
          if (ok > 0) applyNovaConversationId(ok);
          else {
            try { localStorage.removeItem('dunes_nova_conv_id'); } catch (e) {}
            convId = 0;
          }
        })
      : Promise.resolve();
    validateChain.then(function () {
      if (convId > 0) return Promise.resolve(convId);
      return paintLatestAiHistoryDirect('direct_open').then(function (id) {
        if (id > 0) return id;
        return prefetchServerHistory();
      });
    }).then(function () {
      if (convId > 0) return Promise.resolve(convId);
      return ensureSession();
    }).then(function () {
      return checkNovaReadiness();
    }).then(function () {
      var jobs = [];
      if (window.DunesNovaApi && window.DunesNovaApi.refreshModelCatalog) {
        jobs.push(window.DunesNovaApi.refreshModelCatalog().catch(function () {}));
      }
      if (window.DunesNovaApi && window.DunesNovaApi.refreshCredentials) {
        jobs.push(window.DunesNovaApi.refreshCredentials().catch(function () {}));
      }
      return jobs.length ? Promise.all(jobs) : Promise.resolve();
    }).then(function () {
      syncC4ModelPicker();
      return refreshNovaGeneratingStatus();
    }).then(function () {
      if (isNovaGenerationActive()) persistNovaStreamDraft(novaActiveStreamUi);
      restoreNovaGeneratingIfNeeded();
      if (locating) {
        return loadHistoryAround(focusId);
      }
      if (convId > 0) {
        if (isNovaGenerationActive()) {
          var liveBox = rowsEl();
          var hasLiveUi = liveBox && liveBox.querySelector('.dunes-nova-live, .dunes-nova-server-pending');
          if (hasLiveUi) {
            maybeShowServerGenerating({ force: true });
            if (!novaGenPollTimer) startNovaGeneratingPoll();
            return Promise.resolve();
          }
        }
        return loadHistory();
      }
      return paintLatestAiHistoryDirect('direct_final');
    }).then(function () {
      return markNovaConversationRead();
    }).then(function () {
      syncNovaInputLock();
      if (!isNovaHistoryLocated()) {
        pinNovaScrollToBottom();
        scrollC4(true);
      }
      if (window.DunesInbox && window.DunesInbox.refreshNovaInboxPreview) {
        window.DunesInbox.refreshNovaInboxPreview();
      }
    }).finally(function () {
      if (window.DunesScreenLoader) window.DunesScreenLoader.hide('C4');
    });
  }
  wireStackOnce();
  wireC4Header();
  wireNovaFilePickers();
  window.sendAssistantStream = function (text) { return sendMessage(text); };
  return {
    onScreen: onScreen,
    onLeave: onLeave,
    sendMessage: sendMessage,
    ensureSession: ensureSession,
    checkNovaReadiness: checkNovaReadiness,
    loadHistory: loadHistory,
    loadHistoryAround: loadHistoryAround,
    startNewConversation: startNewConversation,
    openNovaSearch: openNovaSearch,
    loadNovaHistoryList: loadNovaHistoryList,
    isGenerationActive: isNovaGenerationActive,
    flushNovaHistorySyncQueue: flushNovaHistorySyncQueue,
    prefetchServerHistory: prefetchServerHistory,
    fetchLatestConvIdFromServer: fetchNovaLatestConvIdFromServer
  };
})();
''';
}
