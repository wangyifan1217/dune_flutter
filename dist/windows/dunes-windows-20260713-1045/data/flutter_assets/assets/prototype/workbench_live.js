(function (global) {
  'use strict';

  var ccItems = [];
  var ccFilter = 'ALL';
  var ccSearchQuery = '';
  var b14Items = [];
  var b14Filter = 'ALL';
  var b14SearchQuery = '';
  var b1Items = [];
  var b1Filter = 'ALL';
  var b1SearchQuery = '';

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }

  function unwrap(res) {
    if (!res) return null;
    if (res.success === false) throw new Error(res.message || 'request failed');
    return res.data !== undefined ? res.data : res;
  }

  function flowApiBase() {
    var flow = localStorage.getItem('dunes_flow_api_base');
    if (flow) return flow.replace(/\/$/, '');
    var stored = localStorage.getItem('dunes_api_base');
    if (stored) return stored.replace(/\/$/, '');
    var host = localStorage.getItem('dunes_api_host') || window.location.hostname || 'localhost';
    return 'http://' + host + ':6087/api/v1';
  }

  function apiBases() {
    var list = [];
    var flow = localStorage.getItem('dunes_flow_api_base');
    if (flow) list.push(flow.replace(/\/$/, ''));
    var stored = localStorage.getItem('dunes_api_base');
    if (stored) list.push(stored.replace(/\/$/, ''));
    var host = localStorage.getItem('dunes_api_host') || window.location.hostname || 'localhost';
    list.push('http://' + host + ':6087/api/v1');
    list.push('http://' + host + ':6090/api/v1');
    var seen = {};
    return list.filter(function (b) {
      if (seen[b]) return false;
      seen[b] = true;
      return true;
    });
  }

  function authHeaders() {
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var h = { 'Content-Type': 'application/json' };
    if (token) h.Authorization = 'Bearer ' + token;
    return h;
  }

  async function flowRequest(path, opts) {
    opts = opts || {};
    var lastErr = null;
    var bases = apiBases();
    for (var i = 0; i < bases.length; i++) {
      try {
        var r = await fetch(bases[i] + path, {
          method: opts.method || 'GET',
          headers: Object.assign({}, authHeaders(), opts.headers || {}),
          body: opts.body,
        });
        var text = await r.text();
        if (r.status === 404 || r.status === 501) {
          lastErr = new Error(text || 'not found');
          continue;
        }
        if (!text) {
          if (!r.ok) throw new Error('HTTP ' + r.status);
          return { success: r.ok, data: null };
        }
        var body;
        try {
          body = JSON.parse(text);
        } catch (e) {
          if (!r.ok) throw new Error(text);
          return { success: true, data: text };
        }
        if (!r.ok || (body && body.success === false)) {
          throw new Error((body && body.message) || text || 'HTTP ' + r.status);
        }
        return body;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error('API unavailable');
  }

  function formatShortDate(iso) {
    if (!iso) return '—';
    try {
      var d = new Date(iso);
      if (isNaN(d.getTime())) return '—';
      var p = function (n) {
        return String(n).padStart(2, '0');
      };
      return (
        d.getFullYear() +
        '-' +
        p(d.getMonth() + 1) +
        '-' +
        p(d.getDate()) +
        ' ' +
        p(d.getHours()) +
        ':' +
        p(d.getMinutes()) +
        ':' +
        p(d.getSeconds())
      );
    } catch (e) {
      return String(iso).slice(0, 10);
    }
  }

  function statusLabelZh(st) {
    st = String(st || '').toUpperCase();
    if (st === 'DRAFT') return '草稿';
    if (st === 'PENDING_INITIATE') return '待确认';
    if (st === 'PENDING') return '审批中';
    if (st === 'APPROVED') return '已通过';
    if (st === 'LIVE') return '已上线';
    if (st === 'REJECTED') return '已驳回';
    if (st === 'VOIDED' || st === 'SUPERSEDED') return '已作废';
    if (st === 'OPEN') return '待处理';
    if (st === 'DONE') return '已完成';
    return st || '—';
  }

  function statusBadgeClass(st) {
    st = String(st || '').toUpperCase();
    if (st === 'DRAFT' || st === 'PENDING_INITIATE') return 'draft';
    if (st === 'APPROVED') return 'approved';
    if (st === 'LIVE') return 'live';
    if (st === 'REJECTED') return 'bad';
    if (st === 'VOIDED' || st === 'SUPERSEDED') return 'voided';
    return 'pending';
  }

  function bizTypeZh(bt) {
    bt = String(bt || '').toUpperCase();
    if (bt === 'PROPOSAL') return '销售提案';
    if (bt === 'CONTRACT') return '合同';
    if (bt === 'PAYMENT') return '付款';
    if (bt === 'EXPENSE') return '费用';
    return bt || '事项';
  }

  function kindZh(k) {
    k = String(k || '').toUpperCase();
    if (k === 'APPROVAL') return '待审批';
    if (k === 'CC_RO') return '抄送';
    if (k === 'TASK') return '任务';
    if (k === 'EXECUTION') return '执行';
    return k || '待办';
  }

  function proposalKindZh(k) {
    k = String(k || '').toUpperCase();
    if (k === 'SALES') return '销售';
    if (k === 'PROCUREMENT') return '采购';
    return k || '销售';
  }

  function proposalTypeLabel(item) {
    var parts = [bizTypeZh(item.businessType || 'PROPOSAL')];
    var sub = item.tag1 || item.txType || item.proposalKind || '';
    if (sub && String(sub).toUpperCase() !== String(item.businessType || '').toUpperCase()) {
      parts.push(String(sub));
    }
    if (item.goodType && item.goodType !== item.txType && item.goodType !== item.tag1) {
      parts.push(String(item.goodType));
    }
    return parts.join(' · ');
  }

  function countByStatus(items) {
    var c = { ALL: items.length, DRAFT: 0, PENDING: 0, APPROVED: 0, LIVE: 0, REJECTED: 0 };
    items.forEach(function (it) {
      var st = String(it.status || '').toUpperCase();
      if (st === 'DRAFT' || st === 'PENDING_INITIATE') c.DRAFT++;
      else if (st === 'PENDING') c.PENDING++;
      else if (st === 'APPROVED') c.APPROVED++;
      else if (st === 'LIVE') c.LIVE++;
      else if (st === 'REJECTED') c.REJECTED++;
    });
    return c;
  }

  function progressFoot(item) {
    var st = String(item.status || '').toUpperCase();
    var cur = Number(item.currentStep || 0);
    var tot = Number(item.totalSteps || 0);
    var pct = 25;
    var px = '草稿';
    var hint = '';
    if (st === 'PENDING' && tot > 0) {
      pct = Math.min(95, Math.round((cur / tot) * 100));
      px = cur + '/' + tot + ' 步';
      hint = '';
    } else if (st === 'APPROVED') {
      pct = 100;
      px = '待合同';
    } else if (st === 'LIVE') {
      pct = 100;
      px = '已上线';
    } else if (st === 'REJECTED') {
      pct = 100;
      px = '已驳回';
      hint = '查看驳回原因 · 可重新填写';
    } else if (st === 'VOIDED' || st === 'SUPERSEDED') {
      pct = 100;
      px = '已作废';
      hint = '提案已关闭';
    } else if (st !== 'DRAFT' && st !== 'PENDING_INITIATE') {
      pct = 60;
      px = '已提交';
    }
    if (!hint && item.ccReasons && item.ccReasons.length) hint = item.ccReasons.join(' · ');
    else if (!hint && item.scaleWan) hint = '¥' + item.scaleWan + '万';
    return { pct: pct, px: px, hint: hint };
  }

  function isDeletableDraft(item) {
    var st = String((item && item.status) || '').toUpperCase();
    return st === 'DRAFT' || st === 'PENDING_INITIATE';
  }

  function renderProposalStyleCard(item, opts) {
    opts = opts || {};
    var st = String(item.status || '').toUpperCase();
    var itemBt = String(item.businessType || 'PROPOSAL').toUpperCase();
    var badge = statusBadgeClass(st);
    var prog = progressFoot(item);
    var typePill = item.tag1 || item.txType || '';
    var typePillHtml = typePill
      ? '<span class="pl-type-pill">' + esc(typePill) + '</span>'
      : '';
    var idLine =
      opts.mode === 'b1' || opts.mode === 'b14'
        ? esc(item.code || '') + ' · ' + esc(proposalTypeLabel(item))
        : esc(item.code || '') + ' · ' + proposalKindZh(item.proposalKind || item.txType);
    var metaParts = [];
    if (opts.mode === 'b1' && (item.initiatorName || item.createdByName)) {
      metaParts.push('<span class="pl-submitter">提交人 ' + esc(item.initiatorName || item.createdByName) + '</span>');
    }
    if (item.createdByName && opts.mode !== 'b1') metaParts.push(esc(item.createdByName));
    if (item.initiatorName && opts.mode !== 'b1') metaParts.push(esc(item.initiatorName));
    metaParts.push(formatShortDate(item.createdAt));
    if (item.scaleWan) metaParts.push('<b>¥' + esc(item.scaleWan) + '万</b>');
    var footHint = prog.hint || (opts.mode === 'cc' ? '抄送知会' : '查看详情');
    var delBtn =
      opts.showDelete && isDeletableDraft(item)
        ? '<button type="button" class="pl-del-btn" data-del-id="' +
          esc(item.id || item.businessId || '') +
          '" aria-label="删除草稿" title="删除草稿"><i class="ti ti-trash"></i></button>'
        : '';
    var dataAttrs =
      ' data-p1-id="' +
      (item.id || item.businessId || '') +
      '" data-business-type="' +
      esc((item.businessType || 'PROPOSAL').toUpperCase()) +
      '" data-business-id="' +
      (item.businessId || item.id || '') +
      '"';
    var cls = 'p-list-card p1-item tappable' + (opts.extraClass ? ' ' + opts.extraClass : '');
    return (
      '<div class="' +
      cls +
      '"' +
      dataAttrs +
      ' data-p1-status="' +
      esc(st) +
      '">' +
      '<div class="pl-h"><div style="flex:1;min-width:0">' +
      '<div class="pl-name">' +
      esc(item.title || item.name || '未命名') +
      typePillHtml +
      '</div>' +
      '<div class="pl-id">' +
      idLine +
      '</div></div>' +
      delBtn +
      '<span class="st-badge ' +
      badge +
      '">' +
      esc(statusLabelZh(st)) +
      '</span></div>' +
      '<div class="pl-meta">' +
      metaParts.join('<span class="dot"></span>') +
      '</div>' +
      '<div class="pl-foot"><div class="progress"><div class="pb"><i style="width:' +
      prog.pct +
      '%;background:var(--accent)"></i></div><span class="px">' +
      esc(prog.px) +
      '</span></div>' +
      '<span style="font-size:9px;color:var(--accent);letter-spacing:.02em;font-weight:600">→ ' +
      esc(footHint) +
      '</span>' +
      (opts.mode === 'b14' && st === 'REJECTED' && item.canRefedit !== false
        ? '<button type="button" class="pl-refedit-btn" data-business-id="' +
          esc(item.businessId || item.id || '') +
          '"><i class="ti ti-edit"></i>重新填写</button>'
        : '') +
      (opts.mode === 'b14' && (st === 'PENDING' || st === 'REJECTED')
        ? '<button type="button" class="pl-track-btn" data-business-id="' +
          esc(item.businessId || item.id || '') +
          '"><i class="ti ti-route"></i>流程追踪</button>'
        : '') +
      (opts.mode === 'b1' && itemBt === 'PROPOSAL'
        ? '<button type="button" class="pl-track-btn" data-business-id="' +
          esc(item.businessId || item.id || '') +
          '"><i class="ti ti-route"></i>流程追踪</button>'
        : '') +
      '</div></div>'
    );
  }

  function renderB14Card(item) {
    return renderProposalStyleCard(
      {
        id: item.businessId || item.id,
        businessId: item.businessId || item.id,
        businessType: item.businessType || 'PROPOSAL',
        title: item.title || item.name,
        code: item.code || bizTypeZh(item.businessType) + ' #' + (item.businessId || item.id),
        status: item.status,
        proposalKind: item.proposalKind || item.txType || item.businessType,
        tag1: item.tag1,
        txType: item.txType,
        goodType: item.goodType,
        createdAt: item.createdAt,
        currentStep: item.currentStep,
        totalSteps: item.totalSteps,
        scaleWan: item.scaleWan,
        createdByName: item.createdByName,
        initiatorName: item.initiatorName,
      },
      { extraClass: 'b14-item', mode: 'b14', showDelete: true },
    );
  }

  function pickProposalStatus(current, incoming) {
    var cur = String(current || '').toUpperCase();
    var inc = String(incoming || '').toUpperCase();
    if (cur === 'VOIDED' || inc === 'VOIDED') return 'VOIDED';
    if (cur === 'SUPERSEDED' || inc === 'SUPERSEDED') return 'SUPERSEDED';
    if (cur === 'PENDING' || inc === 'PENDING') return 'PENDING';
    if (cur === 'REJECTED' || inc === 'REJECTED') return 'REJECTED';
    if (cur === 'DRAFT' || inc === 'DRAFT') return 'DRAFT';
    if (cur === 'PENDING_INITIATE' || inc === 'PENDING_INITIATE') return 'PENDING_INITIATE';
    return inc || cur;
  }

  function resolveB1ProposalStatus(item, detail, trail) {
    if (String(item.status || '').toUpperCase() === 'OPEN') return 'PENDING';
    var trailSt = trail && trail.status ? String(trail.status).toUpperCase() : '';
    var detailSt = String((detail && detail.status) || '').toLowerCase();
    var detailMapped = detailSt === 'pending' ? 'PENDING' : detailSt.toUpperCase();
    return pickProposalStatus(pickProposalStatus(trailSt, detailMapped), '');
  }

  function dedupeB1ByBusiness(items) {
    var map = {};
    (items || []).forEach(function (it) {
      var key = String(it.businessId || it.id);
      if (!key) return;
      var prev = map[key];
      if (!prev || Number(it.todoId || 0) >= Number(prev.todoId || 0)) {
        map[key] = it;
      }
    });
    return Object.keys(map).map(function (k) {
      return map[k];
    });
  }

  function rejectionSeenStorageKey(item) {
    var bid = item.businessId || item.business_id || item.id;
    var bt = String(item.businessType || item.business_type || 'PROPOSAL').toUpperCase();
    return 'dunes_rejection_seen_' + bt + '_' + bid;
  }

  function markRejectionSeen(item) {
    if (!item) return;
    try {
      localStorage.setItem(rejectionSeenStorageKey(item), String(Date.now()));
    } catch (e) {}
  }

  function markAllRejectedSeen(items) {
    (items || []).forEach(function (it) {
      if (String(it.status || '').toUpperCase() === 'REJECTED') markRejectionSeen(it);
    });
  }

  function isRejectionSeen(item) {
    if (!item) return false;
    try {
      return !!localStorage.getItem(rejectionSeenStorageKey(item));
    } catch (e) {
      return false;
    }
  }

  function countUnseenRejected(items) {
    return (items || []).filter(function (it) {
      var st = String(it.status || '').toUpperCase();
      return st === 'REJECTED' && !isRejectionSeen(it);
    }).length;
  }

  function syncRejectedPrompts() {
    var unseen = countUnseenRejected(b14Items);
    renderB14RejectedBanner(unseen);
    highlightB14RejectedEntry(unseen);
    return unseen;
  }

  function markRejectionSeenByBusinessId(businessId) {
    var item = b14Items.find(function (it) {
      return String(it.businessId || it.id) === String(businessId);
    });
    if (item) {
      markRejectionSeen(item);
      syncRejectedPrompts();
      return;
    }
    try {
      localStorage.setItem('dunes_rejection_seen_PROPOSAL_' + businessId, String(Date.now()));
    } catch (e) {}
    syncRejectedPrompts();
  }

  function countActionableRejected(items) {
    return (items || []).filter(function (it) {
      return String(it.status || '').toUpperCase() === 'REJECTED';
    }).length;
  }

  function mergeB14Items(initiated, mine) {
    var byId = {};
    (initiated || []).forEach(function (it) {
      var bid = it.businessId || it.business_id || it.id;
      if (bid == null || bid === '') return;
      var key = String(bid);
      var normalized = Object.assign({}, it, {
        businessId: bid,
        businessType: (it.businessType || it.business_type || 'PROPOSAL').toUpperCase(),
      });
      var prev = byId[key];
      if (!prev || String(normalized.createdAt || '').localeCompare(String(prev.createdAt || '')) >= 0) {
        byId[key] = Object.assign({}, prev || {}, normalized, {
          status: pickProposalStatus(prev && prev.status, normalized.status),
        });
      }
    });
    (mine || []).forEach(function (p) {
      var bid = p.id || p.businessId;
      if (bid == null || bid === '') return;
      var key = String(bid);
      if (byId[key]) {
        if (!byId[key].code && p.code) byId[key].code = p.code;
        if (!byId[key].scaleWan && p.scaleWan) byId[key].scaleWan = p.scaleWan;
        if (!byId[key].title && (p.title || p.name)) byId[key].title = p.title || p.name;
        if (p.status) byId[key].status = pickProposalStatus(byId[key].status, p.status);
        if (p.tag1) byId[key].tag1 = p.tag1;
        if (p.txType) byId[key].txType = p.txType;
        return;
      }
      byId[key] = {
        businessId: bid,
        businessType: 'PROPOSAL',
        title: p.title || p.name || '未命名',
        code: p.code,
        status: p.status,
        createdAt: p.createdAt,
        scaleWan: p.scaleWan,
        proposalKind: p.proposalKind || p.txType,
        tag1: p.tag1,
        txType: p.txType,
        goodType: p.goodType,
        currentStep: 0,
        totalSteps: 0,
      };
    });
    return Object.keys(byId)
      .map(function (k) {
        return byId[k];
      })
      .sort(function (a, b) {
        return String(b.createdAt || '').localeCompare(String(a.createdAt || ''));
      });
  }

  function scaleWanFromDetail(detail) {
    if (!detail) return '';
    var fv = detail.formValues || {};
    var fin = detail.finance || {};
    return fv.targetMonthlyScaleWan || fin.targetMonthlyScaleWan || detail.scaleWan || '';
  }

  async function enrichB1TodoItem(item) {
    var bt = String(item.businessType || 'PROPOSAL').toUpperCase();
    if (bt !== 'PROPOSAL') {
      var nonProposalStatus = String(item.status || '').toUpperCase() === 'OPEN' ? 'PENDING' : 'APPROVED';
      return {
        id: item.businessId,
        businessId: item.businessId,
        businessType: bt,
        title: item.title || bizTypeZh(bt) + ' 待办',
        code: bizTypeZh(bt) + ' #' + (item.businessId || '—'),
        status: nonProposalStatus,
        todoStatus: item.status,
        todoId: item.id,
        createdAt: item.doneAt || item.createdAt,
        proposalKind: bt,
      };
    }
    try {
      var detail = unwrap(await flowRequest('/xflow/proposals/' + item.businessId + '/detail'));
      var trail = null;
      try {
        trail = unwrap(await flowRequest('/approvals/PROPOSAL/' + item.businessId));
      } catch (e2) {
        /* optional */
      }
      var status = resolveB1ProposalStatus(item, detail, trail);
      var decision = '';
      if (trail && Array.isArray(trail.steps) && item.sourceStepId) {
        var myStep = trail.steps.find(function (s) {
          return String(s.id) === String(item.sourceStepId);
        });
        decision = myStep && myStep.decision ? String(myStep.decision).toUpperCase() : '';
      }
      var initiator = (detail && (detail.createdBy || detail.owner1 || detail.initiator)) || '';
      return {
        id: item.businessId,
        businessId: item.businessId,
        todoId: item.id,
        todoStatus: item.status,
        sourceStepId: item.sourceStepId,
        approvalDecision: decision,
        businessType: 'PROPOSAL',
        kind: item.kind || 'APPROVAL',
        title: (detail && detail.title) || item.title || '销售提案',
        code: (detail && detail.code) || 'P-' + item.businessId,
        status: status,
        proposalKind: (detail && detail.txType) || 'PROPOSAL',
        tag1: detail && detail.tag1,
        txType: detail && detail.txType,
        goodType: detail && detail.goodType,
        createdAt: item.doneAt || item.createdAt || (detail && detail.createdAt),
        currentStep: trail && trail.currentStep ? trail.currentStep : 1,
        totalSteps: trail && trail.steps && trail.steps.length ? trail.steps.length : 0,
        scaleWan: scaleWanFromDetail(detail),
        createdByName: initiator,
        initiatorName: initiator,
      };
    } catch (e) {
      return {
        id: item.businessId,
        businessId: item.businessId,
        businessType: bt,
        title: item.title || '销售提案',
        code: 'P-' + (item.businessId || '—'),
        status: String(item.status || '').toUpperCase() === 'OPEN' ? 'PENDING' : 'APPROVED',
        todoId: item.id,
        todoStatus: item.status,
        createdAt: item.doneAt || item.createdAt,
        proposalKind: 'PROPOSAL',
      };
    }
  }

  async function enrichB14ProposalItem(item) {
    var bt = String(item.businessType || 'PROPOSAL').toUpperCase();
    if (bt !== 'PROPOSAL') return item;
    var bid = item.businessId || item.id;
    if (!bid) return item;
    try {
      var detail = unwrap(await flowRequest('/xflow/proposals/' + bid + '/detail'));
      var trail = null;
      try {
        trail = unwrap(await flowRequest('/approvals/PROPOSAL/' + bid));
      } catch (e2) {
        /* optional */
      }
      var st = String((detail && detail.status) || item.status || 'pending').toLowerCase();
      var detailStatus = st === 'pending' ? 'PENDING' : st.toUpperCase();
      if (st === 'superseded') detailStatus = 'SUPERSEDED';
      if (st === 'voided') detailStatus = 'VOIDED';
      var prevStatus = String(item.status || '').toUpperCase();
      var trailStatus = trail && String(trail.status || '').toUpperCase();
      var status = pickProposalStatus(
        pickProposalStatus(prevStatus, trailStatus),
        detailStatus,
      );
      if (st === 'superseded' || st === 'voided') status = detailStatus;
      return Object.assign({}, item, {
        title: (detail && detail.title) || item.title,
        code: (detail && detail.code) || item.code,
        status: status,
        canRefedit: st === 'rejected' && st !== 'voided' && st !== 'superseded',
        tag1: (detail && detail.tag1) || item.tag1,
        txType: (detail && detail.txType) || item.txType,
        goodType: (detail && detail.goodType) || item.goodType,
        scaleWan: scaleWanFromDetail(detail) || item.scaleWan,
        currentStep: trail && trail.currentStep ? trail.currentStep : item.currentStep || 0,
        totalSteps: trail && trail.steps && trail.steps.length ? trail.steps.length : item.totalSteps || 0,
      });
    } catch (e) {
      return item;
    }
  }

  function renderB1Card(item) {
    return renderProposalStyleCard(
      {
        id: item.businessId || item.id,
        businessId: item.businessId || item.id,
        businessType: item.businessType || 'PROPOSAL',
        title: item.title,
        code: item.code || 'P-' + (item.businessId || item.id),
        status: item.status || 'PENDING',
        proposalKind: item.proposalKind || item.txType || 'PROPOSAL',
        tag1: item.tag1,
        txType: item.txType,
        goodType: item.goodType,
        createdAt: item.createdAt,
        currentStep: item.currentStep,
        totalSteps: item.totalSteps,
        scaleWan: item.scaleWan,
        createdByName: item.createdByName || item.initiatorName,
        initiatorName: item.initiatorName || item.createdByName,
      },
      { extraClass: 'b1-item', mode: 'b1' },
    );
  }

  function applyListHero(screenId, titlePrefix, items, filterKey) {
    var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
    if (!screen) return;
    var counts = countByStatus(items);
    var headK = screen.querySelector('.hero-stat .head .k');
    if (headK) headK.textContent = titlePrefix + ' · ' + counts.ALL + ' 份';
    var big = screen.querySelector('.hero-stat .big');
    if (big) big.innerHTML = String(counts.ALL) + '<span class="u">份</span>';
    var badge = screen.querySelector('.hero-stat .head .badge');
    if (badge) {
      if (screenId === 'B14' && counts.REJECTED > 0) {
        badge.textContent = counts.REJECTED + ' 已驳回';
        badge.className = 'badge urge';
      } else if (counts.PENDING > 0) {
        badge.textContent = counts.PENDING + ' 审批中';
        badge.className = 'badge urge';
      } else {
        badge.textContent = '无待审';
        badge.className = 'badge';
      }
    }
    var foot = screen.querySelector('.hero-stat .foot');
    if (foot) {
      var map =
        screenId === 'B14'
          ? [
              ['草稿', counts.DRAFT],
              ['审批中', counts.PENDING],
              ['已通过', counts.APPROVED],
              ['已驳回', counts.REJECTED],
            ]
          : [
              ['草稿', counts.DRAFT],
              ['审批中', counts.PENDING],
              ['已通过', counts.APPROVED],
              ['已上线', counts.LIVE],
            ];
      foot.querySelectorAll('.item').forEach(function (el, i) {
        var row = map[i];
        if (!row) return;
        var l = el.querySelector('.l');
        var v = el.querySelector('.v');
        if (l) l.textContent = row[0];
        if (v) {
          v.textContent = String(row[1]);
          v.className =
            'v' +
            (row[0] === '审批中' && row[1] > 0
              ? ' urge'
              : row[0] === '已通过' || row[0] === '已上线'
                ? ' pos'
                : row[0] === '已驳回' && row[1] > 0
                  ? ' bad'
                  : '');
        }
      });
    }
    var chips = screen.querySelector(filterKey);
    if (chips) {
      var html =
        '<div class="cond-chip' +
        (filterKey === '#p1StatusChips' && ccFilter === 'ALL' ? ' on' : filterKey === '#b14StatusChips' && b14Filter === 'ALL' ? ' on' : filterKey === '#b1StatusChips' && b1Filter === 'ALL' ? ' on' : '') +
        '" data-status-filter="ALL"><span class="dot"></span>全部 ' +
        counts.ALL +
        '</div>';
      ['DRAFT', 'PENDING', 'APPROVED', 'REJECTED', 'LIVE'].forEach(function (k) {
        var label = statusLabelZh(k);
        var n = counts[k] || 0;
        var on =
          (filterKey === '#p1StatusChips' && ccFilter === k) ||
          (filterKey === '#b14StatusChips' && b14Filter === k) ||
          (filterKey === '#b1StatusChips' && b1Filter === k);
        html +=
          '<div class="cond-chip' +
          (on ? ' on' : '') +
          '" data-status-filter="' +
          k +
          '">' +
          label +
          ' ' +
          n +
          '</div>';
      });
      chips.innerHTML = html;
      chips.querySelectorAll('[data-status-filter]').forEach(function (chip) {
        chip.classList.add('tappable');
        chip.addEventListener('click', function (ev) {
          ev.stopPropagation();
          var f = chip.getAttribute('data-status-filter') || 'ALL';
          if (filterKey === '#p1StatusChips') {
            ccFilter = f;
            renderCCList();
          } else if (filterKey === '#b14StatusChips') {
            b14Filter = f;
            renderB14List();
          } else if (filterKey === '#b1StatusChips') {
            b1Filter = f;
            renderB1List();
          }
        });
      });
    }
  }

  function filterStatus(items, filter) {
    if (filter === 'ALL') return items.slice();
    return items.filter(function (it) {
      var st = String(it.status || '').toUpperCase();
      if (filter === 'DRAFT') return st === 'DRAFT' || st === 'PENDING_INITIATE';
      return st === filter;
    });
  }

  function openProposal(id, todoHint) {
    if (!id) return;
    if (!todoHint) {
      var b1Item = b1Items.find(function (it) {
        return String(it.businessId || it.id) === String(id);
      });
      if (b1Item && b1Item.todoId && String(b1Item.todoStatus || '').toUpperCase() === 'OPEN') {
        todoHint = {
          id: b1Item.todoId,
          sourceStepId: b1Item.sourceStepId,
          status: 'OPEN',
          kind: 'APPROVAL',
          businessType: String(b1Item.businessType || 'PROPOSAL').toUpperCase(),
          businessId: b1Item.businessId || b1Item.id,
        };
      }
    }
    if (window.XFlowDynamic && window.XFlowDynamic.openProposalDetail) {
      window.XFlowDynamic.openProposalDetail(id, todoHint);
      return;
    }
    window.pendingProposalId = Number(id);
    if (typeof go === 'function') go('XF');
  }

  function wireDeleteButtons(root, onDeleted) {
    if (!root) return;
    root.querySelectorAll('.pl-del-btn').forEach(function (btn) {
      if (btn._delWired) return;
      btn._delWired = true;
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        ev.preventDefault();
        var id = btn.getAttribute('data-del-id');
        if (!id) return;
        if (window.XFlowDynamic && window.XFlowDynamic.deleteProposalDraft) {
          window.XFlowDynamic.deleteProposalDraft(id, {
            goBack: false,
            onDeleted: onDeleted,
          });
        }
      });
    });
  }

  function wireListCards(root, selector) {
    if (!root) return;
    root.querySelectorAll(selector).forEach(function (card) {
      if (card._wlWired) return;
      card._wlWired = true;
      card.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var bt = (card.getAttribute('data-business-type') || 'PROPOSAL').toUpperCase();
        var bid = card.getAttribute('data-business-id') || card.getAttribute('data-p1-id');
        if (card.classList.contains('cc-item') && bid) markCCProposalRead(bid);
        if (card.classList.contains('b14-item') && bid) {
          var b14Item = b14Items.find(function (it) {
            return String(it.businessId || it.id) === String(bid);
          });
          if (b14Item && String(b14Item.status || '').toUpperCase() === 'REJECTED') {
            markRejectionSeen(b14Item);
            syncRejectedPrompts();
          }
        }
        if (bt === 'PROPOSAL' && bid) openProposal(bid);
      });
    });
  }

  function ccReadKey() {
    return 'dunes_cc_read_proposals';
  }

  function readCCProposalSet() {
    try {
      return JSON.parse(localStorage.getItem(ccReadKey()) || '{}') || {};
    } catch (e) {
      return {};
    }
  }

  function markCCProposalRead(id) {
    var read = readCCProposalSet();
    read[String(id)] = Date.now();
    try {
      localStorage.setItem(ccReadKey(), JSON.stringify(read));
    } catch (e) {}
  }

  function renderCCList() {
    var list = document.getElementById('p1ListCards');
    if (!list) return;
    applyListHero('P1', '抄送我的提案', ccItems, '#p1StatusChips');
    var items = filterStatus(ccItems, ccFilter);
    var q = (ccSearchQuery || '').trim().toLowerCase();
    if (q) {
      items = items.filter(function (it) {
        var hay = [it.title, it.name, it.code, it.tag1, it.txType, it.goodType, proposalTypeLabel(it), it.createdByName, (it.ccReasons || []).join(' ')]
          .join(' ')
          .toLowerCase();
        return hay.indexOf(q) >= 0;
      });
    }
    if (!items.length) {
      list.innerHTML = '<div class="xf-loading-hint">' + (q ? '无匹配结果' : '暂无抄送提案') + '</div>';
      return;
    }
    list.innerHTML = items.map(function (it) {
      return renderProposalStyleCard(it, { mode: 'cc', extraClass: 'cc-item' });
    }).join('');
    wireListCards(list, '.p1-item');
  }

  async function loadCCProposals() {
    try {
      var res = await flowRequest('/xflow/proposals/cc');
      ccItems = Array.isArray(unwrap(res)) ? unwrap(res) : [];
      renderCCList();
      wireCCSearch();
    } catch (e) {
      console.warn('loadCCProposals', e);
    }
  }

  function renderB14List() {
    var list = document.getElementById('b14ListCards');
    if (!list) return;
    applyListHero('B14', '我发起的审批', b14Items, '#b14StatusChips');
    var items = filterStatus(b14Items, b14Filter);
    var q = (b14SearchQuery || '').trim().toLowerCase();
    if (q) {
      items = items.filter(function (it) {
        var hay = [it.title, it.code, it.tag1, it.txType, it.goodType, proposalTypeLabel(it), it.createdByName, it.initiatorName]
          .join(' ')
          .toLowerCase();
        return hay.indexOf(q) >= 0;
      });
    }
    if (!items.length) {
      list.innerHTML = '<div class="xf-loading-hint">' + (q ? '无匹配结果' : '暂无发起记录') + '</div>';
      return;
    }
    list.innerHTML = items.map(renderB14Card).join('');
    wireListCards(list, '.b14-item');
    wireB14TrackButtons(list);
    wireB14RefeditButtons(list);
    wireDeleteButtons(list, function (id) {
      b14Items = b14Items.filter(function (it) {
        return String(it.businessId || it.id) !== String(id);
      });
      renderB14List();
    });
  }

  async function loadB14Initiated() {
    var initiated = [];
    var mine = [];
    var err1 = null;
    var err2 = null;
    try {
      initiated = unwrap(await flowRequest('/workbench/my-initiated')) || [];
      if (!Array.isArray(initiated)) initiated = [];
    } catch (e1) {
      err1 = e1;
      console.warn('loadB14Initiated my-initiated', e1);
    }
    try {
      mine = unwrap(await flowRequest('/xflow/proposals/mine')) || [];
      if (!Array.isArray(mine)) mine = [];
    } catch (e2) {
      err2 = e2;
      console.warn('loadB14Initiated proposals/mine', e2);
    }
    b14Items = mergeB14Items(initiated, mine);
    if (window.__pendingB14Filter) {
      b14Filter = window.__pendingB14Filter;
      window.__pendingB14Filter = null;
    }
    b14Items = await Promise.all(b14Items.map(enrichB14ProposalItem));
    if (!b14Items.length && (err1 || err2)) {
      var list = document.getElementById('b14ListCards');
      if (list) list.innerHTML = '<div class="xf-loading-hint">加载失败，请确认已登录</div>';
      return;
    }
    renderB14List();
    syncRejectedPrompts();
    wireB14Search();
    if (typeof refreshB2Menu === 'function') refreshB2Menu();
  }

  function renderB1List() {
    var list = document.getElementById('b1ListCards');
    if (!list) return;
    var statusCounts = countByStatus(b1Items);
    var pending = statusCounts.PENDING || 0;
    var screen = document.querySelector('.screen[data-screen="B1"]');
    if (screen) {
      var headK = screen.querySelector('.hero-stat .head .k');
      if (headK) headK.textContent = '我的审批 · ' + b1Items.length + ' 项';
      var big = screen.querySelector('.hero-stat .big');
      if (big) big.innerHTML = String(pending) + '<span class="u">项</span>';
      var badge = screen.querySelector('.hero-stat .badge');
      if (badge) badge.textContent = pending > 0 ? pending + ' 待处理' : '无待办';
    }
    var chips = document.getElementById('b1StatusChips');
    if (chips) {
      chips.innerHTML =
        '<div class="cond-chip' + (b1Filter === 'ALL' ? ' on' : '') + '" data-b1-status="ALL"><span class="dot"></span>全部 ' + b1Items.length + '</div>' +
        '<div class="cond-chip' + (b1Filter === 'PENDING' ? ' on' : '') + '" data-b1-status="PENDING">审批中 ' + statusCounts.PENDING + '</div>' +
        '<div class="cond-chip' + (b1Filter === 'APPROVED' ? ' on' : '') + '" data-b1-status="APPROVED">已通过 ' + statusCounts.APPROVED + '</div>' +
        '<div class="cond-chip' + (b1Filter === 'REJECTED' ? ' on' : '') + '" data-b1-status="REJECTED">已驳回 ' + statusCounts.REJECTED + '</div>';
      chips.querySelectorAll('[data-b1-status]').forEach(function (chip) {
        chip.classList.add('tappable');
        chip.addEventListener('click', function (ev) {
          ev.stopPropagation();
          b1Filter = chip.getAttribute('data-b1-status') || 'ALL';
          renderB1List();
        });
      });
    }
    var items = b1Items.slice().sort(function (a, b) {
      return String(b.createdAt || '').localeCompare(String(a.createdAt || ''));
    });
    if (b1Filter !== 'ALL') {
      items = items.filter(function (it) {
        return String(it.status || '').toUpperCase() === b1Filter;
      });
    }
    var q = (b1SearchQuery || '').trim().toLowerCase();
    if (q) {
      items = items.filter(function (it) {
        var hay = [it.title, it.code, it.initiatorName, it.createdByName, it.businessType, it.tag1, it.txType, proposalTypeLabel(it)]
          .join(' ')
          .toLowerCase();
        return hay.indexOf(q) >= 0;
      });
    }
    if (!items.length) {
      list.innerHTML = '<div class="xf-loading-hint">' + (q ? '无匹配结果' : '暂无审批记录') + '</div>';
      return;
    }
    list.innerHTML = items.map(renderB1Card).join('');
    wireListCards(list, '.b1-item');
    wireB1TrackButtons(list);
  }

  function wireB14Search() {
    var input = document.getElementById('b14SearchInput');
    if (!input || input._b14SearchWired) return;
    input._b14SearchWired = true;
    input.addEventListener('input', function () {
      b14SearchQuery = input.value || '';
      renderB14List();
    });
  }

  function wireCCSearch() {
    var input = document.getElementById('p1SearchInput');
    if (!input || input._p1SearchWired) return;
    input._p1SearchWired = true;
    input.addEventListener('input', function () {
      ccSearchQuery = input.value || '';
      renderCCList();
    });
  }

  function wireB1Search() {
    var input = document.getElementById('b1SearchInput');
    if (!input || input._b1SearchWired) return;
    input._b1SearchWired = true;
    input.addEventListener('input', function () {
      b1SearchQuery = input.value || '';
      renderB1List();
    });
  }

  function wireB1TrackButtons(root) {
    if (!root) return;
    root.querySelectorAll('.pl-track-btn').forEach(function (btn) {
      if (btn._b1TrackWired) return;
      btn._b1TrackWired = true;
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        ev.preventDefault();
        var bid = btn.getAttribute('data-business-id');
        var item = b1Items.find(function (it) {
          return String(it.businessId || it.id) === String(bid);
        });
        if (window.WorkbenchLive && window.WorkbenchLive.openB14Track && item) {
          window.WorkbenchLive.openB14Track(item);
        } else if (bid && window.XFlowDynamic && window.XFlowDynamic.openProposalDetail) {
          window.XFlowDynamic.openProposalDetail(bid);
        }
      });
    });
  }

  async function loadB1ApprovalTodos() {
    try {
      var res = await flowRequest('/workbench/inbox?kind=APPROVAL&status=ALL');
      var raw = Array.isArray(unwrap(res)) ? unwrap(res) : [];
      raw = raw.filter(function (t) {
        return String(t.kind || 'APPROVAL').toUpperCase() === 'APPROVAL';
      });
      b1Items = dedupeB1ByBusiness(await Promise.all(raw.map(enrichB1TodoItem)));
      wireB1Search();
      renderB1List();
      if (window.DunesAPI && window.DunesAPI.myStats) {
        var statsRes = await window.DunesAPI.myStats;
        var stats = (statsRes && statsRes.data) || statsRes;
        if (stats && typeof applyMyStats === 'function') applyMyStats(stats);
      }
    } catch (e) {
      console.warn('loadB1ApprovalTodos', e);
    }
  }

  function ensureMyTabRedDots() {
    document.querySelectorAll('.tab-bar .tab[data-go="B2"]').forEach(function (tab) {
      if (!tab.querySelector('.red-dot')) {
        var dot = document.createElement('span');
        dot.className = 'red-dot';
        tab.appendChild(dot);
      }
    });
  }

  function renderB14RejectedBanner(rejected) {
    var n = Number(rejected) || 0;
    var screen = document.querySelector('.screen[data-screen="B2"]');
    if (!screen) return;
    var content = screen.querySelector('.content');
    if (!content) return;
    var old = content.querySelector('.wf-rejected-banner');
    if (old) old.remove();
    if (n <= 0) return;
    var banner = document.createElement('div');
    banner.className = 'wf-rejected-banner tappable';
    banner.setAttribute('data-b14-filter', 'REJECTED');
    banner.innerHTML =
      '<div class="wf-rejected-icon"><i class="ti ti-alert-circle"></i></div>' +
      '<div class="wf-rejected-body"><b>您有 ' +
      n +
      ' 条审批被驳回</b><span>进入「我发起的」查看原因并重新填写</span></div>' +
      '<i class="ti ti-chevron-right wf-rejected-chev"></i>';
    banner.addEventListener('click', function () {
      markAllRejectedSeen(b14Items);
      window.__pendingB14Filter = 'REJECTED';
      if (typeof go === 'function') go('B14');
      syncRejectedPrompts();
    });
    var pendingBanner = content.querySelector('.wf-pending-banner');
    if (pendingBanner && pendingBanner.nextSibling) {
      content.insertBefore(banner, pendingBanner.nextSibling);
    } else if (pendingBanner) {
      content.appendChild(banner);
    } else {
      content.insertBefore(banner, content.firstChild);
    }
  }

  function renderB2PendingBanner(pending) {
    var n = Number(pending) || 0;
    var screen = document.querySelector('.screen[data-screen="B2"]');
    if (!screen) return;
    var content = screen.querySelector('.content');
    if (!content) return;
    var old = content.querySelector('.wf-pending-banner');
    if (old) old.remove();
    if (n <= 0) return;
    var banner = document.createElement('div');
    banner.className = 'wf-pending-banner tappable';
    banner.setAttribute('data-go', 'B1');
    banner.innerHTML =
      '<div class="wf-pending-icon"><i class="ti ti-bell-ringing"></i></div>' +
      '<div class="wf-pending-body"><b>您有 ' +
      n +
      ' 条待审批</b><span>点击进入「我审批的」立即处理</span></div>' +
      '<i class="ti ti-chevron-right wf-pending-chev"></i>';
    content.insertBefore(banner, content.firstChild);
  }

  function highlightB14RejectedEntry(rejected) {
    var n = Number(rejected) || 0;
    var screen = document.querySelector('.screen[data-screen="B2"]');
    if (!screen) return;
    var mi = screen.querySelector('.menu-item[data-go="B14"]');
    if (!mi) return;
    var ic = mi.querySelector('.mi-ic');
    if (ic) {
      var dot = ic.querySelector('.red-dot');
      if (!dot) {
        dot = document.createElement('span');
        dot.className = 'red-dot';
        ic.appendChild(dot);
      }
      if (n > 0) {
        dot.classList.add('show');
        dot.classList.remove('has-count');
        dot.textContent = '';
      } else {
        dot.classList.remove('show', 'has-count');
        dot.textContent = '';
      }
    }
  }

  function highlightB2ApprovalEntry(pending) {
    var n = Number(pending) || 0;
    var screen = document.querySelector('.screen[data-screen="B2"]');
    if (!screen) return;
    screen.querySelectorAll('.menu-item').forEach(function (mi) {
      var title = mi.querySelector('.mi-t');
      if (!title || title.textContent.indexOf('我审批') < 0) return;
      mi.classList.toggle('menu-item-urgent', n > 0);
    });
    var qs = screen.querySelector('.quick-stats .qs-cell[data-go="B1"]');
    if (qs) qs.classList.toggle('qs-urgent', n > 0);
  }

  function updateMyTabBadge(pending) {
    var n = Number(pending) || 0;
    window.__dunesMyPending = n;
    ensureMyTabRedDots();
    document.querySelectorAll('.tab-bar .tab[data-go="B2"] .red-dot').forEach(function (dot) {
      if (n > 0) {
        dot.classList.add('show');
        dot.classList.remove('has-count');
        dot.textContent = '';
      } else {
        dot.classList.remove('show', 'has-count');
        dot.textContent = '';
      }
    });
    renderB2PendingBanner(n);
    highlightB2ApprovalEntry(n);
  }

  var _myBadgeRefreshTimer = null;
  function scheduleMyBadgeRefresh(data) {
    if (_myBadgeRefreshTimer) clearTimeout(_myBadgeRefreshTimer);
    _myBadgeRefreshTimer = setTimeout(function () {
      _myBadgeRefreshTimer = null;
      refreshMyBadgeFromServer(data);
    }, 350);
  }

  function normalizeStats(stats) {
    stats = stats || {};
    return {
      pendingForMe: stats.pendingForMe != null ? stats.pendingForMe : stats.openTodos || 0,
      initiatedByMe: stats.initiatedByMe != null ? stats.initiatedByMe : stats.initiated || 0,
      handledThisMonth:
        stats.approvalHandled != null
          ? stats.approvalHandled
          : stats.handledThisMonth != null
            ? stats.handledThisMonth
            : stats.approved != null
              ? stats.approved
              : 0,
      outstandingInvoices: stats.outstandingInvoices || 0,
      proposalTotal: stats.proposalTotal || 0,
      proposalDrafts: stats.proposalDrafts || 0,
      proposalPending: stats.proposalPending || 0,
      proposalApproved: stats.proposalApproved || 0,
      proposalLive: stats.proposalLive || 0,
      approvalPending: stats.approvalPending || 0,
      approvalRejected: stats.approvalRejected || 0,
      ccProposalCount: stats.ccProposalCount || 0,
      ccProposalPending: stats.ccProposalPending || 0,
    };
  }

  async function refreshMyBadgeFromServer(data) {
    data = data || {};
    try {
      var hadBaseline = window.__dunesMyRejectedInit === true;
      var prevRejected = window.__dunesMyRejected || 0;
      var hadPendingBaseline = window.__dunesMyPendingInit === true;
      var prevPending = window.__dunesMyPending || 0;
      var res = await flowRequest('/workbench/my-stats');
      var stats = unwrap(res);
      if (!stats) return;
      window.__dunesLastMyStats = normalizeStats(stats);
      var n = stats.pendingForMe != null ? stats.pendingForMe : stats.openTodos || 0;
      updateMyTabBadge(n);
      if (typeof applyMyStats === 'function') applyMyStats(stats);
      if (n > 0) {
        var active = document.querySelector('.screen.active');
        if (active && active.dataset && active.dataset.screen === 'B1') {
          loadB1ApprovalTodos().catch(function () {});
        }
      }
      await loadCCProposals();
      await loadB14Initiated();
      if (window.DunesApi && typeof window.DunesApi.refreshKbMenuStats === 'function') {
        try { await window.DunesApi.refreshKbMenuStats(); } catch (kbErr) {}
      }
      refreshB2Menu(stats);
      var rejected = syncRejectedPrompts();
      if (hadPendingBaseline && n > prevPending && data.event !== 'approval_rejected') {
        if (window.DunesAPI && DunesAPI.toast) {
          DunesAPI.toast('您有 ' + (n - prevPending) + ' 条新的待审批，请及时处理', false);
        }
      }
      if (data.event === 'approval_rejected' || (hadBaseline && rejected > prevRejected)) {
        if (window.DunesAPI && DunesAPI.toast) {
          DunesAPI.toast('您有 1 条审批被驳回，请及时查看', false);
        }
      }
      window.__dunesMyRejected = rejected;
      window.__dunesMyRejectedInit = true;
      window.__dunesMyPendingInit = true;
    } catch (e) {
      console.warn('refreshMyBadgeFromServer', e);
    }
  }

  function onApprovalRejected(data) {
    scheduleMyBadgeRefresh(Object.assign({ event: 'approval_rejected' }, data || {}));
  }

  function refreshB2Menu(stats) {
    var s = normalizeStats(stats || window.__dunesLastMyStats || {});
    var screen = document.querySelector('.screen[data-screen="B2"]');
    if (!screen) return;
    screen.querySelectorAll('.menu-item').forEach(function (mi) {
      var go = mi.getAttribute('data-go');
      var title = mi.querySelector('.mi-t');
      var desc = mi.querySelector('.mi-d');
      var badge = mi.querySelector('.num-badge');
      if (!title || !desc) return;
      if (go === 'B14') {
        var total = b14Items.length || s.initiatedByMe || 0;
        var pending = countByStatus(b14Items).PENDING || s.approvalPending || 0;
        var rejectedTotal = countByStatus(b14Items).REJECTED || s.approvalRejected || 0;
        var rejectedUnseen = countUnseenRejected(b14Items);
        desc.textContent = total + ' 条 · ' + pending + ' 审批中 · ' + rejectedTotal + ' 已驳回';
        if (badge) {
          badge.textContent = String(rejectedUnseen > 0 ? rejectedUnseen : pending || 0);
          badge.className =
            'num-badge ' + (rejectedUnseen > 0 || pending > 0 ? 'coral urge' : 'gray');
        }
        mi.classList.toggle('menu-item-urgent', rejectedUnseen > 0 || pending > 0);
        highlightB14RejectedEntry(rejectedUnseen);
      }
      if (go === 'P1') {
        var ccTotal = s.ccProposalCount || ccItems.length;
        var ccPending = countByStatus(ccItems).PENDING || s.ccProposalPending || 0;
        desc.textContent = ccTotal + ' 份抄送 · ' + ccPending + ' 审批中';
        if (badge) badge.textContent = String(ccTotal);
      }
      if (go === 'B1' && title.textContent.indexOf('我审批') >= 0) {
        var pendingForMe = Number(s.pendingForMe);
        if (isNaN(pendingForMe)) pendingForMe = 0;
        if (!pendingForMe && b1Items.length) {
          pendingForMe = countByStatus(b1Items).PENDING || 0;
        }
        var handledThisMonth = Number(s.handledThisMonth);
        if (isNaN(handledThisMonth)) handledThisMonth = 0;
        desc.textContent = pendingForMe + ' 待我审 · ' + handledThisMonth + ' 已审核';
        if (badge) {
          badge.textContent = String(pendingForMe || 0);
          badge.className = 'num-badge' + (pendingForMe > 0 ? ' coral urge' : ' gray');
        }
        mi.classList.toggle('menu-item-urgent', pendingForMe > 0);
      }
      if (go === 'K1') {
        var kb = window.__dunesKbSummary || {};
        var docCount = Number(kb.documentCount || 0);
        var categoryCount = Number(kb.categoryCount || 0);
        var unreadCount = Number(kb.unreadCount || 0);
        desc.textContent = docCount + ' 文档 · ' + categoryCount + ' 分类 · ' + unreadCount + ' 未读';
        if (badge) {
          badge.textContent = String(unreadCount);
          badge.className = 'num-badge' + (unreadCount > 0 ? ' coral urge' : ' gray');
        }
      }
    });
  }

  async function refreshMyProposals() {
    await refreshMyBadgeFromServer();
    await loadB14Initiated();
  }

  async function loadB10FromApi(id) {
    var pid = id || window.pendingProposalId;
    if (!pid) return;
    try {
      var res = await flowRequest('/xflow/proposals/' + pid + '/detail');
      var d = unwrap(res);
      if (!d) return;
      var lbl = document.getElementById('b10-proposal-label');
      var title = document.querySelector('.screen[data-screen="B10"] .ds-name');
      if (lbl) lbl.textContent = d.code || 'PROP-' + pid;
      if (title) title.textContent = d.title || '提案详情';
    } catch (e) {
      console.warn('loadB10FromApi', e);
    }
  }

  ensureMyTabRedDots();
  setTimeout(function () {
    refreshMyBadgeFromServer();
  }, 400);

  async function openB14Track(item) {
    if (!item) return;
    if (String(item.status || '').toUpperCase() === 'REJECTED') {
      markRejectionSeen(item);
      syncRejectedPrompts();
    }
    var bt = String(item.businessType || 'PROPOSAL').toUpperCase();
    var bid = item.businessId || item.id;
    var todoHint = null;
    if (item.todoId && String(item.todoStatus || '').toUpperCase() === 'OPEN') {
      todoHint = {
        id: item.todoId,
        sourceStepId: item.sourceStepId,
        status: 'OPEN',
        kind: 'APPROVAL',
        businessType: bt,
        businessId: bid,
      };
    }
    if (bt === 'PROPOSAL' && bid && window.XFlowDynamic && window.XFlowDynamic.openProposalDetail) {
      window.XFlowDynamic.openProposalDetail(bid, todoHint);
      setTimeout(function () {
        var tab = document.querySelector('#xf-detail-panel .xf-det-tab[data-tab="track"]');
        if (tab) tab.click();
      }, 600);
      return;
    }
    if (typeof setB14TrackFromItem === 'function') setB14TrackFromItem(item);
    else if (typeof setB14View === 'function') setB14View('track');
  }

  function wireB14RefeditButtons(root) {
    if (!root) return;
    root.querySelectorAll('.pl-refedit-btn').forEach(function (btn) {
      if (btn._refeditWired) return;
      btn._refeditWired = true;
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        ev.preventDefault();
        var bid = btn.getAttribute('data-business-id');
        var item = b14Items.find(function (it) {
          return String(it.businessId || it.id) === String(bid);
        });
        if (item) {
          markRejectionSeen(item);
          syncRejectedPrompts();
        }
        if (bid && window.XFlowDynamic && window.XFlowDynamic.openRejectedProposalEdit) {
          window.XFlowDynamic.openRejectedProposalEdit(bid);
        } else if (bid) {
          openProposal(bid);
        }
      });
    });
  }

  function wireB14TrackButtons(root) {
    if (!root) return;
    root.querySelectorAll('.pl-track-btn').forEach(function (btn) {
      if (btn._trackWired) return;
      btn._trackWired = true;
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        ev.preventDefault();
        var bid = btn.getAttribute('data-business-id');
        var item = b14Items.find(function (it) {
          return String(it.businessId || it.id) === String(bid);
        });
        if (item) openB14Track(item);
      });
    });
  }

  global.WorkbenchLive = {
    loadCCProposals: loadCCProposals,
    loadP1Workbench: loadCCProposals,
    loadB14Initiated: loadB14Initiated,
    setB14Filter: function (f) {
      b14Filter = f || 'ALL';
      renderB14List();
    },
    loadB1ApprovalTodos: loadB1ApprovalTodos,
    markRejectionSeenByBusinessId: markRejectionSeenByBusinessId,
    refreshMyProposals: refreshMyProposals,
      refreshB2Menu: refreshB2Menu,
      renderB2PendingBanner: renderB2PendingBanner,
      highlightB2ApprovalEntry: highlightB2ApprovalEntry,
    ensureMyTabRedDots: ensureMyTabRedDots,
    updateMyTabBadge: updateMyTabBadge,
    scheduleMyBadgeRefresh: scheduleMyBadgeRefresh,
    refreshMyBadgeFromServer: refreshMyBadgeFromServer,
    onApprovalRejected: onApprovalRejected,
    highlightB14RejectedEntry: highlightB14RejectedEntry,
    loadB10FromApi: loadB10FromApi,
    normalizeStats: normalizeStats,
    openProposal: openProposal,
    openB14Track: openB14Track,
    statusLabelZh: statusLabelZh,
    bizTypeZh: bizTypeZh,
  };
})(typeof window !== 'undefined' ? window : global);
